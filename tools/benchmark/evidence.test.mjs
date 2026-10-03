// TEST-ONLY evidence packets: no Godot process, GPU, native executable or
// measured hardware is involved. These fixtures test integrity rejection;
// never publish their temporary files as benchmark or phase evidence.
import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import {fileURLToPath, pathToFileURL} from 'node:url';
import {deflateSync} from 'node:zlib';

const here = path.dirname(fileURLToPath(import.meta.url));
// Optional explicit module enables read-only review against the coordinator's
// narrow verifier fix without modifying this isolated checkout's production.
const verifier = process.env.RENDER_EVIDENCE_VERIFIER
  ? pathToFileURL(path.resolve(process.env.RENDER_EVIDENCE_VERIFIER)).href
  : new URL('./reduce.mjs', import.meta.url).href;
const {verifyEvidence} = await import(verifier);
const recipeBytes = fs.readFileSync(path.join(here, 'recipe.json'));
const recipe = JSON.parse(recipeBytes.toString('utf8').replace(/^\uFEFF/, ''));
const temporaryBase = path.resolve(here, '../../.local/benchmark-test-packets');
const sha = bytes => crypto.createHash('sha256').update(bytes).digest('hex');
const header = 'process_frame,wall_us,frame_ms,gpu_timestamp_frame,new_gpu_sample,gpu_render_ms,cpu_render_ms,video_bytes,origin_version\n';

// A separate test encoder uses PNG filter 0. CRC is calculated here rather
// than calling the production decoder/comparator being exercised.
function crc32(bytes) {
  let value = 0xffffffff;
  for(const byte of bytes) {
    value ^= byte;
    for(let bit = 0; bit < 8; bit++) value = (value >>> 1) ^ ((value & 1) ? 0xedb88320 : 0);
  }
  return (value ^ 0xffffffff) >>> 0;
}

function chunk(type, data) {
  const name = Buffer.from(type), length = Buffer.alloc(4), checksum = Buffer.alloc(4);
  length.writeUInt32BE(data.length);
  checksum.writeUInt32BE(crc32(Buffer.concat([name, data])));
  return Buffer.concat([length, name, data, checksum]);
}

function image(width, height, changed = false) {
  const ihdr = Buffer.alloc(13);
  ihdr.writeUInt32BE(width, 0);
  ihdr.writeUInt32BE(height, 4);
  ihdr[8] = 8;
  ihdr[9] = 2; // RGB, not RGBA: the comparison must normalize per pixel.
  const raw = Buffer.alloc((width * 3 + 1) * height);
  if(changed) raw[1] = 9; // One actual pixel exceeds the frozen eight-byte threshold.
  return Buffer.concat([Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]),
    chunk('IHDR', ihdr), chunk('IDAT', deflateSync(raw)), chunk('IEND', Buffer.alloc(0))]);
}

function json(file, value) {
  fs.writeFileSync(file, JSON.stringify(value, null, 2) + '\n');
}

function packet(t, {resolution = [2, 1], duration = 1, fov = 70} = {}) {
  fs.mkdirSync(temporaryBase, {recursive: true});
  const root = fs.mkdtempSync(path.join(temporaryBase, 'TEST-ONLY-'));
  t.after(() => {
    // Verify the absolute deletion target remains in this explicit test area.
    assert.equal(path.dirname(path.resolve(root)), temporaryBase);
    assert(path.basename(root).startsWith('TEST-ONLY-'));
    fs.rmSync(root, {recursive: true, force: true});
  });
  const directory = path.join(root, 'evidence');
  const snapshot = path.join(root, 'project');
  const payload = path.join(root, 'payload');
  const tools = path.join(directory, 'verification-tools');
  for(const folder of [directory, snapshot, path.join(snapshot, 'render'), path.join(payload, 'bin'), tools]) fs.mkdirSync(folder, {recursive: true});

  const sceneSources = ['render/render.gd', 'render/frame.gd', 'project.godot'].map(name => {
    const bytes = Buffer.from('TEST-ONLY synthetic source placeholder: ' + name + '\n');
    fs.writeFileSync(path.join(snapshot, name), bytes);
    return {path: name, bytes: bytes.length, sha256: sha(bytes)};
  });
  const payloadIdentities = {};
  for(const [field, name] of [['executable_sha256', 'flight-render.exe'], ['pck_sha256', 'flight-render.pck'],
    ['bridge_sha256', 'bin/flight_godot_bridge.dll'], ['jsbsim_sha256', 'bin/JSBSim.dll']]) {
    // These are labeled text bytes, not native programs. They are never run.
    const bytes = Buffer.from('TEST-ONLY non-executable payload placeholder: ' + name + '\n');
    fs.writeFileSync(path.join(payload, name), bytes);
    payloadIdentities[field] = sha(bytes);
  }
  const benchmarkTools = ['run.ps1', 'reduce.mjs', 'png.mjs', 'recipe.json'].map(name => {
    const bytes = fs.readFileSync(path.join(here, name));
    fs.writeFileSync(path.join(tools, name), bytes);
    return {path: 'tools/benchmark/' + name, sha256: sha(bytes)};
  });
  fs.writeFileSync(path.join(directory, 'recipe.json'), recipeBytes);
  json(path.join(directory, 'hardware.json'), {TEST_ONLY: true, no_gpu_or_hardware_measurement: true});
  const before = image(...resolution), after = image(...resolution, true);
  fs.writeFileSync(path.join(directory, 'origin-before.png'), before);
  fs.writeFileSync(path.join(directory, 'origin-after.png'), after);
  fs.writeFileSync(path.join(directory, 'view.png'), before);

  // Three unequal, hand-calculated intervals; no production quantile/reducer
  // helper computes the expected summary. Long variants still contain only
  // synthetic samples and intentionally fail frame-throughput budgets.
  const intervals = [duration * 250_000, duration * 333_333, duration * 416_667];
  const captureStart=1_000_000;
  let clock = captureStart+10_000_000;
  const frameClocks=[];
  const lines = intervals.map((us, index) => {
    clock += us;
    frameClocks.push((clock-captureStart)/1e6);
    return `${index + 1},${clock},${us / 1000},${index},1,${2 * (index + 1)},${index + 1},${1000 * (index + 1)},${index === 0 ? 1 : 2}`;
  });
  fs.writeFileSync(path.join(directory, 'frames.csv'), header + lines.join('\n') + '\n');
  const processDuration = duration + 12;
  const memoryLines = Array.from({length: processDuration - 1}, (_, index) => `${index + 1},4096`);
  fs.writeFileSync(path.join(directory, 'working-set.csv'), 'elapsed_s,working_set_bytes\n' + memoryLines.join('\n') + '\n');

  // One warmup event, then only actual due callback events. The intentionally
  // sparse long packet skips missed deadlines rather than inventing swaps.
  const events=[{process_frame:0,wall_s:5,epoch:1,tile_index:0,scheduled_s:5,
    submit_ms:.125,active_nodes:64,deferred_old_nodes:1}];
  let nextScheduled=10;
  for(const [index,wall] of frameClocks.entries()) {
    if(wall<nextScheduled) continue;
    const epoch=events.length+1;
    events.push({process_frame:index+1,wall_s:wall,epoch,tile_index:[0,7,56,63][(epoch-1)%4],
      scheduled_s:nextScheduled,submit_ms:.25+index*.125,active_nodes:64,deferred_old_nodes:1});
    nextScheduled=Math.floor(wall/5+1)*5;
  }
  const maxSubmit=events.at(-1).submit_ms; // Values strictly increase; hand-calculated p95=max for <=4 events.
  const report = {
    TEST_ONLY: true,
    scope: 'TEST-ONLY parser integrity fixture; no execution, rendering or GPU evidence',
    duration_s: duration, warmup_s: 10, frames: 3, average_fps: 3 / duration,
    capture_start_us:captureStart,capture_elapsed_s:10+duration,
    render_tile_attachment:{events,interval_s:5,replacements:events.length,steady_tile_count:64,
      maximum_deferred_old_nodes:1,p95_submit_cpu_ms:maxSubmit,maximum_submit_cpu_ms:maxSubmit,
      next_scheduled_s:nextScheduled,scope:'TEST-ONLY invented event packet; no actual mesh attachment'},
    frame_ms: {p95: intervals[2] / 1000, p99: intervals[2] / 1000},
    gpu_ms: {p95: 6, p99: 6, positive_unique_frame_samples: 3, duplicate_observations: 0},
    device: {
      adapter: recipe.required_adapter, method: recipe.renderer, driver: recipe.driver,
      resolution, presentation_window: recipe.presentation_window, fov_deg: fov,
      fixture: 'overcast', max_fps: recipe.max_fps, vsync_mode: 0, msaa_mode: 1,
      taa: recipe.taa, render_scale: 1, fov_axis: recipe.fov_axis,
      engine: {string: '4.7.2-stable (official)', hash: 'ed1daf0bf001b61586d9930840f2f1394092c079'}
    },
    rebase: {transactions: 2, origin_version: 2, max_projected_delta_px: 0.1,
      max_relative_audio_delta_m: 0.0001, canonical_unchanged: true, mixed_version_negative_detected: true},
    rendered_origin_pair: {pixels: resolution[0] * resolution[1], changed_pixels: 1,
      changed_fraction: 1 / (resolution[0] * resolution[1]), channel_delta_threshold: 8,
      maximum_channel_delta: 9, changed_fraction_budget: recipe.thresholds.paired_image_changed_fraction_max}
  };
  const manifest = {
    TEST_ONLY: true, scope: report.scope, fixture: 'overcast', duration_s: duration,
    resolution, fov_deg: fov, warmup_s: 10, wall_process_duration_s: processDuration,
    git_head: '0'.repeat(40), exit_code: 0, scene_sources: sceneSources,
    benchmark_tools: benchmarkTools, ...payloadIdentities,
    engine_sha256: sha(Buffer.from('TEST-ONLY fake engine identity')),
    template_sha256: sha(Buffer.from('TEST-ONLY fake template identity')),
    recipe_sha256: sha(recipeBytes)
  };
  const cleanup={schema_version:1,passed:true,timeout_s:2,elapsed_ms:10,waited_process_frames:2,
    initial_observed:{audio_stream:true,audio_playback:true},
    retirement:{audio_stream_retired:true,audio_playback_retired:true,active_terrain_nodes:64,queued_terrain_nodes:0},
    started_us:clock+1000,completed_us:clock+11000,
    scope:'TEST-ONLY invented cleanup receipt; no actual resource retirement'};
  function writeLog(suffix = '') {
    fs.writeFileSync(path.join(directory, 'runtime.log'), 'TEST-ONLY fabricated markers; NO GPU EXECUTION\n'
      + 'RENDER_DEVICE ' + JSON.stringify(report.device) + '\n'
      + 'RENDERED_ORIGIN_PAIR ' + JSON.stringify(report.rendered_origin_pair) + '\n'
      + 'RENDER_PROBE ' + JSON.stringify(report) + '\n'
      + 'RENDER_CLEANUP ' + JSON.stringify(cleanup) + '\n' + suffix);
  }
  function save({updateLog = true} = {}) {
    json(path.join(directory, 'manifest.json'), manifest);
    json(path.join(directory, 'report.json'), report);
    json(path.join(directory, 'cleanup.json'), cleanup);
    if(updateLog) writeLog();
  }
  save();
  return {directory, snapshot, payload, tools, report, manifest, cleanup, save, writeLog};
}

test('TEST-ONLY valid diagnostic packet verifies bytes and hand-calculated statistics without GPU claims', t => {
  const fixture = packet(t);
  const result = verifyEvidence(fixture.directory);
  assert.equal(result.capture_class, 'diagnostic-capture');
  assert.equal(result.engineering_checks.target_configuration, false);
  assert.equal(result.engineering_checks.continuous_ten_minutes, false);
  assert.equal(result.average_fps, 3);
  assert.equal(result.independent_image_pair.changed_pixels, 1);
  assert.match(result.scope, /TEST-ONLY.*no execution/);
});

test('matching effective settings retain diagnostic class against the frozen 1440p/600-second recipe', t => {
  const fixture = packet(t, {fov: 80});
  assert.deepEqual(recipe.resolution, [2560, 1440]);
  assert.equal(recipe.duration_s, 600);
  const result = verifyEvidence(fixture.directory);
  assert.equal(result.capture_class, 'diagnostic-capture');
  assert.equal(result.engineering_checks.target_configuration, false);
});

test('recipe-matching synthetic metadata becomes canonical configuration, never hardware proof', t => {
  const fixture = packet(t, {resolution: recipe.resolution, duration: recipe.duration_s, fov: recipe.fov_deg});
  const result = verifyEvidence(fixture.directory);
  assert.equal(result.capture_class, 'canonical-target-capture');
  assert.equal(result.engineering_checks.target_configuration, true);
  assert.equal(result.engineering_checks.average_fps, false);
  assert.equal(result.engineering_checks.callback_p95, false);
  assert.match(result.scope, /TEST-ONLY/);
});

test('inconsistent effective settings, fallback adapter and enabled VSync reject even with refreshed log', t => {
  for(const [field, value] of [['resolution', [3, 1]], ['fov_deg', 80], ['adapter', 'Unreviewed adapter'],
    ['method', 'gl_compatibility'], ['vsync_mode', 1], ['msaa_mode', 0], ['render_scale', 0.5]]) {
    const fixture = packet(t);
    fixture.report.device[field] = value;
    fixture.save();
    assert.throws(() => verifyEvidence(fixture.directory), undefined, field);
  }
});

test('forged image fraction rejects independently of a matching fabricated runtime log', t => {
  const fixture = packet(t);
  fixture.report.rendered_origin_pair.changed_fraction = 0;
  fixture.save();
  assert.throws(() => verifyEvidence(fixture.directory), /Forged image change fraction/);
});

test('false canonical/coherence flags and negative rebase maxima reject after matching log refresh', t => {
  for(const [field, value] of [['canonical_unchanged', false], ['mixed_version_negative_detected', false],
    ['max_projected_delta_px', -1], ['max_relative_audio_delta_m', -1], ['transactions', 0]]) {
    const fixture = packet(t);
    fixture.report.rebase[field] = value;
    fixture.save();
    assert.throws(() => verifyEvidence(fixture.directory), undefined, field);
  }
});

test('a report changed independently of runtime markers rejects', t => {
  const fixture = packet(t);
  fixture.report.rebase.max_projected_delta_px = 0.2;
  fixture.save({updateLog: false});
  assert.throws(() => verifyEvidence(fixture.directory), /Runtime log does not match/);
});

test('runtime errors and singular/plural shutdown leaks invalidate a complete otherwise valid packet', t => {
  for(const diagnostic of ['ERROR: test-only runtime failure', 'SCRIPT ERROR: test-only script failure',
    'FATAL: test-only native failure', 'WARNING: 1 ObjectDB instance was leaked at exit',
    'WARNING: 2 ObjectDB instances were leaked at exit']) {
    const fixture = packet(t);
    fixture.writeLog(diagnostic + '\n');
    assert.throws(() => verifyEvidence(fixture.directory), /Runtime diagnostics invalidate/, diagnostic);
  }
});

test('changed recipe, staged source, payload and any cloned verifier tool reject real byte hashes', t => {
  for(const [location, name, diagnostic] of [['evidence', 'recipe.json', /Recipe not bound/],
    ['snapshot', 'render/render.gd', /Staged source/], ['payload', 'flight-render.pck', /Exported payload identity/],
    ...['run.ps1', 'reduce.mjs', 'png.mjs', 'recipe.json'].map(name => ['tools', name, /Verification tool identity/])]) {
    const fixture = packet(t);
    const base = location === 'evidence' ? fixture.directory : fixture[location];
    const file = path.join(base, name);
    if(location === 'snapshot') {
      const bytes = fs.readFileSync(file);
      bytes[0] ^= 1; // Preserve length: exercise the SHA check, not just stat.
      fs.writeFileSync(file, bytes);
    } else fs.appendFileSync(file, location === 'evidence' ? '\n' : '\nTEST-ONLY corrupt bytes');
    assert.throws(() => verifyEvidence(fixture.directory), diagnostic, location + '/' + name);
  }
});

test('omitted/duplicate verifier identities and forged source hashes reject complete packets', t => {
  for(const mutate of [fixture => fixture.manifest.benchmark_tools.pop(),
    fixture => fixture.manifest.benchmark_tools[3] = {...fixture.manifest.benchmark_tools[0]},
    fixture => fixture.manifest.scene_sources[0].sha256 = '0'.repeat(64)]) {
    const fixture = packet(t);
    mutate(fixture);
    fixture.save();
    assert.throws(() => verifyEvidence(fixture.directory));
  }
});

test('unsafe staged-source paths reject without reading outside the packet', t => {
  for(const unsafe of ['../outside.gd', 'render/../render/frame.gd', 'C:outside.gd']) {
    const fixture = packet(t);
    fixture.manifest.scene_sources[0].path = unsafe;
    fixture.save();
    assert.throws(() => verifyEvidence(fixture.directory), /Unsafe staged source identity/);
  }
});

test('memory tail removal and gaps reject despite sufficient total sample count', t => {
  for(const mutate of [lines => lines.slice(0, -4), lines => lines.filter((_, index) => ![3, 4, 5].includes(index))]) {
    const fixture = packet(t);
    const file = path.join(fixture.directory, 'working-set.csv');
    const lines = fs.readFileSync(file, 'utf8').trimEnd().split('\n');
    fs.writeFileSync(file, mutate(lines).join('\n') + '\n');
    assert.throws(() => verifyEvidence(fixture.directory), /Working-set (process coverage truncated|sampling gap)/);
  }
});

test('wrong frame/GPU summaries reject even after their runtime markers are refreshed', t => {
  for(const [section, field, value, diagnostic] of [['frame_ms', 'p95', 1, /Frame percentile mismatch/],
    ['gpu_ms', 'p99', 1, /GPU percentile mismatch/], ['gpu_ms', 'positive_unique_frame_samples', 1, /strictly equal/],
    [null, 'average_fps', 60, /Summary FPS mismatch/], [null, 'frames', 4, /strictly equal/]]) {
    const fixture = packet(t);
    (section ? fixture.report[section] : fixture.report)[field] = value;
    fixture.save();
    assert.throws(() => verifyEvidence(fixture.directory), diagnostic, `${section ?? 'report'}.${field}`);
  }
});

test('TEST-ONLY tile events include warmup and independently account for explicitly skipped deadlines', t => {
  const fixture=packet(t,{duration:25});
  // Callback times16.25,24.583325,35 skip20 and30 deadlines respectively.
  assert.deepEqual(fixture.report.render_tile_attachment.events.map(event=>event.scheduled_s),[5,10,20,25]);
  const result=verifyEvidence(fixture.directory);
  assert.equal(result.render_tile_attachment.replacements,4);
  assert.equal(result.render_tile_attachment.maximum_deferred_old_nodes,1);
  assert.equal(result.render_tile_attachment.p95_submit_cpu_ms,.5);
  assert.equal(result.render_tile_attachment.next_scheduled_s,40);
});

test('tile event absence, truncation and forged count reject even after matching log refresh', t => {
  for(const mutate of [attachment=>delete attachment.events,attachment=>attachment.events=[],
    attachment=>attachment.events.pop(),attachment=>attachment.replacements+=1]) {
    const fixture=packet(t);
    mutate(fixture.report.render_tile_attachment);
    fixture.save();
    assert.throws(()=>verifyEvidence(fixture.directory),/Tile/);
  }
});

test('tile epoch, corner cycle, cadence and pending deadline mutations reject', t => {
  for(const mutate of [attachment=>attachment.events[1].epoch=1,
    attachment=>attachment.events[1].tile_index=56,
    attachment=>attachment.events[1].scheduled_s=15,
    attachment=>attachment.events[0].scheduled_s=0,
    attachment=>attachment.next_scheduled_s=20,
    attachment=>attachment.interval_s=1]) {
    const fixture=packet(t);
    mutate(fixture.report.render_tile_attachment);
    fixture.save();
    assert.throws(()=>verifyEvidence(fixture.directory),/Tile/);
  }
  const fixture=packet(t,{duration:25});
  fixture.report.render_tile_attachment.events[2].scheduled_s=15; // Catch-up differs from explicit skip policy.
  fixture.save();
  assert.throws(()=>verifyEvidence(fixture.directory),/Tile scheduled deadline recurrence/);
});

test('tile frame and wall clocks bind events to actual raw rows and final capture clock', t => {
  for(const mutate of [report=>report.render_tile_attachment.events[1].process_frame=0,
    report=>report.render_tile_attachment.events[1].wall_s=10.2,
    report=>report.render_tile_attachment.events[0].wall_s=4.9,
    report=>report.render_tile_attachment.events[0].process_frame=1,
    report=>report.render_tile_attachment.events[1].wall_s=12,
    report=>report.capture_start_us+=10,
    report=>report.capture_elapsed_s+=.01]) {
    const fixture=packet(t);
    mutate(fixture.report);
    fixture.save();
    assert.throws(()=>verifyEvidence(fixture.directory),/Tile|Warmup|Capture/);
  }
});

test('tile active/deferred node bounds and summary maxima reject forged boundedness', t => {
  for(const mutate of [attachment=>attachment.events[0].active_nodes=65,
    attachment=>attachment.events[0].deferred_old_nodes=2,
    attachment=>attachment.events[0].deferred_old_nodes=-1,
    attachment=>attachment.steady_tile_count=63,
    attachment=>attachment.maximum_deferred_old_nodes=0]) {
    const fixture=packet(t);
    mutate(fixture.report.render_tile_attachment);
    fixture.save();
    assert.throws(()=>verifyEvidence(fixture.directory),/terrain nodes|Tile/);
  }
});

test('tile submission timings and recomputed summaries reject negative and forged metrics', t => {
  for(const mutate of [attachment=>attachment.events[1].submit_ms=-.1,
    attachment=>attachment.events[1].submit_ms=null,
    attachment=>attachment.events[1].submit_ms=.75,
    attachment=>attachment.p95_submit_cpu_ms=0,
    attachment=>attachment.maximum_submit_cpu_ms=0]) {
    const fixture=packet(t);
    mutate(fixture.report.render_tile_attachment);
    fixture.save();
    assert.throws(()=>verifyEvidence(fixture.directory),/tile submission|Tile submission/);
  }
});

test('TEST-ONLY cleanup is independently verified and hashed outside measured capture intervals', t => {
  const fixture=packet(t);
  const result=verifyEvidence(fixture.directory);
  assert.equal(result.measured_wall_s,1);
  assert.equal(result.average_fps,3);
  assert.equal(result.postmeasurement_cleanup.elapsed_ms,10);
  assert.equal(result.postmeasurement_cleanup.waited_process_frames,2);
  assert.equal(result.artifacts['cleanup.json'],sha(fs.readFileSync(path.join(fixture.directory,'cleanup.json'))));
  assert.equal(Object.hasOwn(fixture.report,'cleanup'),false);
  assert.equal(Object.hasOwn(fixture.report,'postmeasurement_cleanup'),false);
});

test('missing, tampered or multiply marked cleanup receipts reject complete otherwise valid packets', t => {
  for(const mutate of [fixture=>fs.unlinkSync(path.join(fixture.directory,'cleanup.json')),
    fixture=>{fixture.cleanup.elapsed_ms=11; fixture.save({updateLog:false});},
    fixture=>{
      const file=path.join(fixture.directory,'runtime.log');
      const lines=fs.readFileSync(file,'utf8').split('\n').filter(line=>!line.startsWith('RENDER_CLEANUP '));
      fs.writeFileSync(file,lines.join('\n'));
    },
    fixture=>fixture.writeLog('RENDER_CLEANUP '+JSON.stringify(fixture.cleanup)+'\n')]) {
    const fixture=packet(t);
    mutate(fixture);
    assert.throws(()=>verifyEvidence(fixture.directory),/cleanup|Cleanup|ENOENT/);
  }
});

test('cleanup must observe both real resources and report both retirements', t => {
  for(const [section,field,value] of [['initial_observed','audio_stream',false],
    ['initial_observed','audio_playback',false],['retirement','audio_stream_retired',false],
    ['retirement','audio_playback_retired',false],['initial_observed','audio_stream',null]]) {
    const fixture=packet(t);
    fixture.cleanup[section][field]=value;
    fixture.save();
    assert.throws(()=>verifyEvidence(fixture.directory),/Cleanup/);
  }
});

test('cleanup schema, success, exact deadline and process opportunity requirements reject forged success', t => {
  for(const [field,value] of [['schema_version',2],['passed',false],['timeout_s',3],
    ['elapsed_ms',-1],['elapsed_ms',2000],['elapsed_ms',2001],['elapsed_ms',null],
    ['waited_process_frames',1],['waited_process_frames',2.5]]) {
    const fixture=packet(t);
    fixture.cleanup[field]=value;
    if(field==='elapsed_ms' && Number.isFinite(value) && value>=0)
      fixture.cleanup.completed_us=fixture.cleanup.started_us+value*1000;
    fixture.save();
    assert.throws(()=>verifyEvidence(fixture.directory),/Cleanup|Reviewed cleanup/);
  }
});

test('cleanup final scene counts reject retained queued nodes or changed active workload', t => {
  for(const [field,value] of [['active_terrain_nodes',63],['active_terrain_nodes',65],
    ['queued_terrain_nodes',1],['queued_terrain_nodes',-1]]) {
    const fixture=packet(t);
    fixture.cleanup.retirement[field]=value;
    fixture.save();
    assert.throws(()=>verifyEvidence(fixture.directory),/Cleanup/);
  }
});

test('cleanup clocks must follow measurement and agree with elapsed within one microsecond', t => {
  for(const mutate of [fixture=>{
    fixture.cleanup.started_us-=1001;
    fixture.cleanup.completed_us-=1001;
  },fixture=>fixture.cleanup.completed_us=fixture.cleanup.started_us-1,
    fixture=>fixture.cleanup.completed_us+=2,
    fixture=>fixture.cleanup.started_us+=.5,
    fixture=>{fixture.cleanup.elapsed_ms=1999.9995; fixture.cleanup.completed_us=fixture.cleanup.started_us+2_000_000;}]) {
    const fixture=packet(t);
    mutate(fixture);
    fixture.save();
    assert.throws(()=>verifyEvidence(fixture.directory),/Cleanup/);
  }
});
