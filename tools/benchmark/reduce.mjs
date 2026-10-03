import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import {pathToFileURL} from 'node:url';
import {comparePNG} from './png.mjs';

export function nearestRank(values, p) {
  assert(values.length > 0 && p > 0 && p <= 1, 'Nonempty quantile domain required');
  const ordered = [...values].sort((a,b) => a-b);
  return ordered[Math.ceil(ordered.length*p)-1];
}

export function parseTrace(text) {
  const lines = text.trimEnd().split(/\r?\n/);
  assert.equal(lines.shift(), 'process_frame,wall_us,frame_ms,gpu_timestamp_frame,new_gpu_sample,gpu_render_ms,cpu_render_ms,video_bytes,origin_version');
  assert(lines.length >= 2, 'Truncated frame trace');
  let previous, gpuFrame = -1;
  return lines.map(line => {
    const fields = line.split(',').map(Number);
    assert.equal(fields.length,9);
    assert(fields.every(Number.isFinite), 'Nonfinite frame evidence');
    const [frame,wall,interval,gpu,newGpu,gpuMs,cpuMs,video,origin] = fields;
    assert([frame,wall,gpu,newGpu,video,origin].every(Number.isSafeInteger));
    assert(frame >= 0 && wall > 0 && interval > 0 && gpuMs >= 0 && cpuMs >= 0 && video >= 0 && origin >= 0);
    assert(newGpu === 0 || newGpu === 1);
    if(previous) {
      assert.equal(frame,previous.frame+1,'Missing or duplicate process frame');
      assert(wall > previous.wall,'Nonmonotonic wall clock');
      assert(Math.abs(interval-(wall-previous.wall)/1000) < 0.000001,'Interval disagrees with monotonic timestamps');
      assert(origin >= previous.origin,'Origin version regressed');
    }
    if(newGpu) {
      assert(gpu > gpuFrame,'Duplicate GPU frame was counted twice');
      assert(gpuMs > 0,'Unavailable GPU timestamp cannot count as evidence');
      gpuFrame = gpu;
    } else {
      assert(gpu <= gpuFrame,'New GPU frame omitted from unique accounting');
    }
    previous = {frame,wall,interval,gpu,newGpu,gpuMs,cpuMs,video,origin};
    return previous;
  });
}

export function reduceTrace(rows) {
  const frameMs = rows.map(row => row.interval);
  const gpuMs = rows.filter(row => row.newGpu).map(row => row.gpuMs);
  const cpuMs = rows.filter(row => row.newGpu).map(row => row.cpuMs);
  const measuredSeconds = frameMs.reduce((sum,value) => sum+value,0)/1000;
  return {frames:rows.length,measured_wall_s:measuredSeconds,average_fps:rows.length/measuredSeconds,
    engine_callback_interval_ms:{p95:nearestRank(frameMs,.95),p99:nearestRank(frameMs,.99),maximum:Math.max(...frameMs)},
    gpu_render_ms:{p95:nearestRank(gpuMs,.95),p99:nearestRank(gpuMs,.99),unique_frames:gpuMs.length,available_fraction:gpuMs.length/rows.length},
    render_cpu_ms:{p95:nearestRank(cpuMs,.95),scope:'render operations and frame setup only; not whole main-thread cost'},
    peak_engine_video_allocation_bytes:Math.max(...rows.map(row => row.video)),
    origin_version:rows.at(-1).origin};
}

const digest = file => crypto.createHash('sha256').update(fs.readFileSync(file)).digest('hex');
const readJSON = file => JSON.parse(fs.readFileSync(file,'utf8').replace(/^\uFEFF/,''));

export function verifyTileAttachments(report, recipe, rows) {
  const interval=recipe.scene.far_tile_replacement_interval_s;
  assert.equal(interval,5,'Reviewed tile attachment interval required');
  assert(Number.isSafeInteger(report.capture_start_us) && report.capture_start_us>=0,'Invalid capture start clock');
  const elapsed=report.capture_elapsed_s;
  assert(Number.isFinite(elapsed) && elapsed>0 && Math.abs(elapsed-report.warmup_s-report.duration_s)<=.1,'Invalid final capture elapsed');
  assert(Math.abs(report.capture_start_us+elapsed*1e6-rows.at(-1).wall)<=1,'Capture elapsed does not match final trace clock');
  const attachment=report.render_tile_attachment;
  assert(attachment && Array.isArray(attachment.events),'Tile attachment event evidence required');
  assert.equal(attachment.interval_s,interval,'Tile interval summary mismatch');
  const byFrame=new Map(rows.map(row=>[row.frame,row]));
  let scheduled=interval, previousFrame=-1, previousWall=-1, maximumDeferred=0;
  const timings=[];
  for(const [index,event] of attachment.events.entries()) {
    assert(Number.isSafeInteger(event.process_frame) && event.process_frame>previousFrame && event.process_frame<=rows.at(-1).frame,'Tile event frame order');
    assert(Number.isFinite(event.wall_s) && event.wall_s>previousWall && event.wall_s<=elapsed,'Tile event wall clock order');
    assert.equal(event.epoch,index+1,'Tile event epoch sequence');
    assert.equal(event.tile_index,[0,7,56,63][index%4],'Tile corner cycle');
    assert.equal(event.scheduled_s,scheduled,'Tile scheduled deadline recurrence');
    assert(event.wall_s>=scheduled,'Tile attachment occurred before its deadline');
    assert(Number.isFinite(event.submit_ms) && event.submit_ms>=0,'Invalid tile submission timing');
    assert.equal(event.active_nodes,64,'Unbounded active terrain nodes');
    assert(Number.isSafeInteger(event.deferred_old_nodes) && event.deferred_old_nodes>=0 && event.deferred_old_nodes<=1,'Unbounded deferred terrain nodes');
    if(event.wall_s>report.warmup_s) {
      const row=byFrame.get(event.process_frame);
      assert(row,'Post-warmup tile event missing from raw trace');
      assert(Math.abs(report.capture_start_us+event.wall_s*1e6-row.wall)<=1,'Tile event timestamp disagrees with raw trace');
    } else assert(event.process_frame<rows[0].frame,'Warmup tile event overlaps captured frames');
    timings.push(event.submit_ms);
    maximumDeferred=Math.max(maximumDeferred,event.deferred_old_nodes);
    previousFrame=event.process_frame;
    previousWall=event.wall_s;
    // Skip missed deadlines explicitly; never fabricate catch-up events.
    scheduled=Math.floor(event.wall_s/interval+1)*interval;
  }
  assert.equal(attachment.next_scheduled_s,scheduled,'Tile pending deadline summary mismatch');
  assert(scheduled>elapsed,'Tile attachment evidence missing final due event');
  assert.equal(attachment.replacements,attachment.events.length,'Tile replacement count mismatch');
  assert.equal(attachment.steady_tile_count,64,'Tile steady node count mismatch');
  assert.equal(attachment.maximum_deferred_old_nodes,maximumDeferred,'Tile deferred node maximum mismatch');
  const p95=timings.length?nearestRank(timings,.95):-1;
  const maximum=timings.length?Math.max(...timings):-1;
  assert(Number.isFinite(attachment.p95_submit_cpu_ms) && Math.abs(attachment.p95_submit_cpu_ms-p95)<=1e-9,'Tile submission percentile mismatch');
  assert(Number.isFinite(attachment.maximum_submit_cpu_ms) && Math.abs(attachment.maximum_submit_cpu_ms-maximum)<=1e-9,'Tile submission maximum mismatch');
  return {replacements:timings.length,interval_s:interval,steady_tile_count:64,maximum_deferred_old_nodes:maximumDeferred,
    p95_submit_cpu_ms:p95,maximum_submit_cpu_ms:maximum,next_scheduled_s:scheduled,
    scope:'Verified event cadence and node bounds; CPU submission only, not GPU resource retirement or storage/GIS/contact streaming'};
}

export function verifyEvidence(directory) {
  const manifest = readJSON(path.join(directory,'manifest.json'));
  const recipe = readJSON(path.join(directory,'recipe.json'));
  const report = readJSON(path.join(directory,'report.json'));
  assert.equal(digest(path.join(directory,'recipe.json')),manifest.recipe_sha256,'Recipe not bound to run');
  assert.equal(manifest.exit_code,0);
  assert.equal(report.device.adapter,recipe.required_adapter);
  assert.equal(report.device.method,recipe.renderer);
  assert.equal(report.device.driver,recipe.driver);
  assert.deepEqual(report.device.resolution,manifest.resolution);
  assert.equal(report.device.fov_deg,manifest.fov_deg);
  assert.equal(report.device.fixture,manifest.fixture);
  assert.equal(report.duration_s,manifest.duration_s);
  assert.equal(report.warmup_s,manifest.warmup_s);
  assert.equal(report.device.max_fps,recipe.max_fps);
  assert.deepEqual(report.device.presentation_window,recipe.presentation_window);
  assert.equal(report.device.vsync_mode,0,'VSync must be disabled');
  assert.equal(report.device.msaa_mode,1,'MSAA 2x required');
  assert.equal(report.device.taa,recipe.taa);
  assert.equal(report.device.render_scale,1);
  assert.equal(report.device.fov_axis,recipe.fov_axis);
  assert.equal(report.device.engine.string,'4.7.2-stable (official)');
  assert.equal(report.device.engine.hash,'ed1daf0bf001b61586d9930840f2f1394092c079');
  assert(Number.isFinite(manifest.wall_process_duration_s) && manifest.wall_process_duration_s>=manifest.warmup_s+manifest.duration_s);
  const runtime=fs.readFileSync(path.join(directory,'runtime.log'),'utf8');
  assert(!/ERROR:|SCRIPT ERROR:|FATAL:|ObjectDB instances? (?:was|were) leaked/.test(runtime),'Runtime diagnostics invalidate evidence');
  for(const [marker,expected] of [['RENDER_DEVICE ',report.device],['RENDER_PROBE ',report],['RENDERED_ORIGIN_PAIR ',report.rendered_origin_pair]]) {
    const found=runtime.split(/\r?\n/).filter(line=>line.startsWith(marker));
    assert.equal(found.length,1,'Exact runtime receipt marker required');
    assert.deepEqual(JSON.parse(found[0].slice(marker.length)),expected,'Runtime log does not match evidence packet');
  }
  for(const field of ['engine_sha256','template_sha256','executable_sha256','pck_sha256','bridge_sha256','jsbsim_sha256']) assert.match(manifest[field],/^[0-9a-f]{64}$/);
  assert.match(manifest.git_head,/^[0-9a-f]{40}$/);
  assert(manifest.scene_sources.length>=3 && manifest.scene_sources.every(source => /^[0-9a-f]{64}$/.test(source.sha256)));
  const snapshot=path.resolve(directory,'../project');
  const payload=path.resolve(directory,'../payload');
  for(const source of manifest.scene_sources) {
    assert(!/[\\:]/.test(source.path) && !source.path.split('/').some(part=>part==='..' || part==='.' || part==='') && !path.isAbsolute(source.path),'Unsafe staged source identity');
    const file=path.resolve(snapshot,source.path);
    assert.equal(fs.statSync(file).size,source.bytes,'Staged source byte count');
    assert.equal(digest(file),source.sha256,'Staged source does not match captured snapshot');
  }
  assert.deepEqual(manifest.benchmark_tools.map(tool=>tool.path).sort(),['tools/benchmark/png.mjs','tools/benchmark/recipe.json','tools/benchmark/reduce.mjs','tools/benchmark/run.ps1'],'Complete immutable verification tool identity required');
  for(const tool of manifest.benchmark_tools) {
    assert(/^tools\/benchmark\/[^/]+$/.test(tool.path),'Unsafe benchmark tool identity');
    assert.equal(digest(path.join(directory,'verification-tools',path.basename(tool.path))),tool.sha256,'Verification tool identity mismatch');
  }
  for(const [field,name] of [['executable_sha256','flight-render.exe'],['pck_sha256','flight-render.pck'],['bridge_sha256','bin/flight_godot_bridge.dll'],['jsbsim_sha256','bin/JSBSim.dll']]) assert.equal(digest(path.join(payload,name)),manifest[field],'Exported payload identity mismatch');
  const rows = parseTrace(fs.readFileSync(path.join(directory,'frames.csv'),'utf8'));
  const result = reduceTrace(rows);
  result.render_tile_attachment=verifyTileAttachments(report,recipe,rows);
  assert.equal(result.frames,report.frames);
  assert(Math.abs(result.measured_wall_s-manifest.duration_s)<=.1,'Run does not cover declared continuous interval');
  assert(Math.abs(result.average_fps-report.average_fps)<=.00001,'Summary FPS mismatch');
  for(const percentile of ['p95','p99']) {
    assert(Math.abs(result.engine_callback_interval_ms[percentile]-report.frame_ms[percentile])<=.000001,'Frame percentile mismatch');
    assert(Math.abs(result.gpu_render_ms[percentile]-report.gpu_ms[percentile])<=.000001,'GPU percentile mismatch');
  }
  assert.equal(result.gpu_render_ms.unique_frames,report.gpu_ms.positive_unique_frame_samples);
  assert.equal(result.origin_version,report.rebase.origin_version);
  assert(Number.isSafeInteger(report.rebase.transactions) && report.rebase.transactions>0);
  assert.equal(report.rebase.transactions,report.rebase.origin_version);
  assert.equal(report.rebase.canonical_unchanged,true);
  assert.equal(report.rebase.mixed_version_negative_detected,true);
  for(const field of ['max_projected_delta_px','max_relative_audio_delta_m']) assert(Number.isFinite(report.rebase[field]) && report.rebase[field]>=0,'Invalid rebase metric');
  const memory = fs.readFileSync(path.join(directory,'working-set.csv'),'utf8').trim().split(/\r?\n/);
  assert.equal(memory.shift(),'elapsed_s,working_set_bytes');
  let last = -1;
  let firstTime;
  const workingSets = memory.map(line => {
    const [time,bytes] = line.split(',').map(Number);
    assert(Number.isFinite(time) && time>last && Number.isSafeInteger(bytes) && bytes>0);
    if(last<0) firstTime=time;
    else assert(time-last<=2.5,'Working-set sampling gap');
    last=time;
    return bytes;
  });
  assert(workingSets.length>=manifest.duration_s-3,'Working-set sampling truncated');
  assert(firstTime<=2.5 && manifest.wall_process_duration_s-last<=2.5,'Working-set process coverage truncated');
  result.peak_working_set_bytes=Math.max(...workingSets);
  const t = recipe.thresholds;
  const pair=comparePNG(fs.readFileSync(path.join(directory,'origin-before.png')),fs.readFileSync(path.join(directory,'origin-after.png')),Math.round(t.paired_image_channel_delta_threshold*255));
  assert.deepEqual([pair.width,pair.height],manifest.resolution,'Paired image resolution');
  for(const field of ['pixels','changed_pixels','maximum_channel_delta','channel_delta_threshold']) assert.equal(pair[field],report.rendered_origin_pair[field],'Paired image summary mismatch');
  assert(Math.abs(pair.changed_fraction-report.rendered_origin_pair.changed_fraction)<1e-12,'Forged image change fraction');
  assert.equal(report.rendered_origin_pair.changed_fraction_budget,t.paired_image_changed_fraction_max);
  const targetConfiguration=JSON.stringify(manifest.resolution)===JSON.stringify(recipe.resolution) && manifest.fov_deg===recipe.fov_deg && manifest.warmup_s===recipe.warmup_s && manifest.duration_s===recipe.duration_s;
  result.capture_class=targetConfiguration?'canonical-target-capture':'diagnostic-capture';
  result.independent_image_pair=pair;
  result.engineering_checks={
    target_configuration:targetConfiguration,
    continuous_ten_minutes:result.measured_wall_s>=599.9,
    average_fps:result.average_fps>=t.average_fps_min,
    callback_p95:result.engine_callback_interval_ms.p95<=t.engine_interval_p95_ms_max,
    callback_p99:result.engine_callback_interval_ms.p99<=t.engine_interval_p99_ms_max,
    gpu_render_p95:result.gpu_render_ms.p95<=t.gpu_render_p95_ms_max,
    gpu_timestamp_availability:result.gpu_render_ms.available_fraction>=t.gpu_unique_sample_fraction_min,
    working_set:result.peak_working_set_bytes<=t.working_set_bytes_max,
    engine_video_allocation:result.peak_engine_video_allocation_bytes<=t.engine_video_allocation_bytes_max,
    rebase_projection:report.rebase.max_projected_delta_px<=t.origin_projected_delta_px_max,
    rebase_audio_geometry:report.rebase.max_relative_audio_delta_m<=t.origin_audio_relative_delta_m_max,
    rebase_gpu_pair:pair.changed_fraction<=t.paired_image_changed_fraction_max
  };
  result.unmeasured_targets=recipe.unmeasured_targets;
  result.scope=manifest.scope;
  result.fixture=manifest.fixture;
  result.resolution=manifest.resolution;
  result.fov_deg=manifest.fov_deg;
  result.artifacts={};
  for(const name of ['manifest.json','recipe.json','hardware.json','frames.csv','report.json','working-set.csv','runtime.log','origin-before.png','origin-after.png','view.png']) result.artifacts[name]=digest(path.join(directory,name));
  return result;
}

if(process.argv[1] && import.meta.url===pathToFileURL(path.resolve(process.argv[1])).href) {
  const result = verifyEvidence(path.resolve(process.argv[2]));
  fs.writeFileSync(path.resolve(process.argv[2],'verified.json'),JSON.stringify(result,null,2)+'\n');
  console.log(JSON.stringify(result,null,2));
}
