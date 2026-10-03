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
  let clock = 10_000_000;
  const lines = intervals.map((us, index) => {
    clock += us;
    return `${index + 1},${clock},${us / 1000},${index},1,${2 * (index + 1)},${index + 1},${1000 * (index + 1)},${index === 0 ? 1 : 2}`;
  });
  fs.writeFileSync(path.join(directory, 'frames.csv'), header + lines.join('\n') + '\n');
  const processDuration = duration + 12;
  const memoryLines = Array.from({length: processDuration - 1}, (_, index) => `${index + 1},4096`);
  fs.writeFileSync(path.join(directory, 'working-set.csv'), 'elapsed_s,working_set_bytes\n' + memoryLines.join('\n') + '\n');

  const report = {
    TEST_ONLY: true,
    scope: 'TEST-ONLY parser integrity fixture; no execution, rendering or GPU evidence',
    duration_s: duration, warmup_s: 10, frames: 3, average_fps: 3 / duration,
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
  function writeLog(suffix = '') {
    fs.writeFileSync(path.join(directory, 'runtime.log'), 'TEST-ONLY fabricated markers; NO GPU EXECUTION\n'
      + 'RENDER_DEVICE ' + JSON.stringify(report.device) + '\n'
      + 'RENDERED_ORIGIN_PAIR ' + JSON.stringify(report.rendered_origin_pair) + '\n'
      + 'RENDER_PROBE ' + JSON.stringify(report) + '\n' + suffix);
  }
  function save({updateLog = true} = {}) {
    json(path.join(directory, 'manifest.json'), manifest);
    json(path.join(directory, 'report.json'), report);
    if(updateLog) writeLog();
  }
  save();
  return {directory, snapshot, payload, tools, report, manifest, save, writeLog};
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
