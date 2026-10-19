import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { createRequire } from 'node:module';

// Handwritten shape fixtures only. Never invokes a source selector, native build,
// library, grid, terrain compiler, process, Godot, profile store or actual pack.
const require = createRequire(new URL('../../schemas/package.json', import.meta.url));
const Ajv2020 = require('ajv/dist/2020.js').default;
const ajv = new Ajv2020({ strict: true, strictNumbers: true, allErrors: true,
  coerceTypes: false, useDefaults: false, removeAdditional: false });
const base = 'https://flight-simulator.invalid/contracts/world/resident-runtime/v1/';
const names = ['start-recipe', 'world-runtime-entry', 'component', 'native-closure'];
for (const name of names) ajv.addSchema(JSON.parse(readFileSync(new URL(
  '../../schemas/world/resident-runtime/v1/' + name + '.schema.json', import.meta.url), 'utf8')));
const data = Object.fromEntries(names.map(name => [name, JSON.parse(readFileSync(new URL(
  'fixtures/world/resident-runtime/v1/' + name + '.shape.json', import.meta.url), 'utf8'))]));
const checks = Object.fromEntries(names.map(name => [name, ajv.getSchema(base + name + '.schema.json')]));
for (const name of names) assert.equal(typeof checks[name], 'function');
function expect(name, value, wanted) {
  const before = structuredClone(value);
  assert.equal(checks[name](value), wanted, name + ': ' + JSON.stringify(checks[name].errors));
  assert.deepEqual(value, before, 'validation must not mutate');
}
function reject(name, change) {
  const copy = structuredClone(data[name]); change(copy); expect(name, copy, false);
}
function *objects(value, path = []) {
  if (value === null || typeof value !== 'object') return;
  if (!Array.isArray(value)) yield { value, path };
  for (const [key, child] of Object.entries(value)) yield *objects(child, [...path, key]);
}
function at(value, path) { for (const key of path) value = value[key]; return value; }
const tag = word => ({ $binary64_le: word });

test('four handwritten fixtures establish shape only without admitting products or a pose', () => {
  for (const name of names) expect(name, data[name], true);
  assert.equal(data['world-runtime-entry'].world.sha256, '0'.repeat(64));
  assert.equal(data['native-closure'].component_sha256, '0'.repeat(64));
  // These zero hashes and deliberately incomplete closures are not real pins.
  assert.equal(data['component'].sources.length, 1);
  assert.equal(data['native-closure'].translation_units.length, 4);
});

test('every fixture object is closed and each supplied key is required', () => {
  for (const name of names) for (const {value, path} of objects(data[name])) {
    reject(name, copy => { at(copy, path).__unexpected__ = true; });
    for (const key of Object.keys(value)) reject(name, copy => { delete at(copy, path)[key]; });
  }
});

test('serialized KAWO catalog fixes choices, anchor, six file order and individual byte caps', () => {
  for (const [key, wrong] of [['selector', 'original-synthetic'], ['named_start', 'airborne-prepared'],
    ['wind_profile', 'crosswind'], ['seed', 42], ['recording_version', 1], ['angular_integration_method', 'midpoint']])
    reject('world-runtime-entry', copy => { copy[key] = wrong; });
  reject('world-runtime-entry', copy => { copy.world.id = 'original.interactive-plane'; });
  reject('world-runtime-entry', copy => { copy.world.bytes = null; });
  reject('world-runtime-entry', copy => { copy.model_identity.backend_model = 'c172p'; });
  reject('world-runtime-entry', copy => { copy.clock.tick_rate_hz = 60; });
  reject('world-runtime-entry', copy => { copy.world_anchor.latitude_rad.$binary64_le = 'fcfc84c1e5e5ea3f'; });
  reject('world-runtime-entry', copy => { copy.world_anchor.ellipsoid_height_m.$binary64_le = '0000000000000080'; });
  reject('world-runtime-entry', copy => { copy.world_anchor.latitude_rad = .84; });
  reject('world-runtime-entry', copy => { copy.files.reverse(); });
  reject('world-runtime-entry', copy => { copy.files.pop(); });
  reject('world-runtime-entry', copy => { copy.files.push(structuredClone(copy.files[0])); });
  reject('world-runtime-entry', copy => { copy.files[0].path = '../ground.fgrd'; });
  reject('world-runtime-entry', copy => { copy.files[0].role = 'source-notice'; });
  const caps = [276946836, 4194304, 4194304, 4194304, 16384, 65536];
  for (let i = 0; i < caps.length; i++) {
    const boundary = structuredClone(data['world-runtime-entry']); boundary.files[i].bytes = caps[i];
    expect('world-runtime-entry', boundary, true);
    reject('world-runtime-entry', copy => { copy.files[i].bytes = caps[i] + 1; });
    reject('world-runtime-entry', copy => { copy.files[i].bytes = 0; });
  }
  for (const bad of [0, 4194305, 1.5, '100', NaN, Infinity])
    reject('world-runtime-entry', copy => { copy.world.bytes = bad; });
  for (const bad of ['A'.repeat(64), '0'.repeat(63), '0'.repeat(64) + '\n'])
    reject('world-runtime-entry', copy => { copy.model_inventory_sha256 = bad; });
});

test('start closes original ground-only tuple and finite word encoding preserves signed zero', () => {
  const check = ajv.getSchema(base + 'start-recipe.schema.json#/$defs/binary64');
  assert.equal(typeof check, 'function');
  for (const word of ['0000000000000000', '0000000000000080', '0100000000000000',
    '0100000000000080', 'ffffffffffffef7f', 'ffffffffffffefff']) {
    const atom = tag(word); assert.equal(check(atom), true, word); assert.equal(atom.$binary64_le, word);
  }
  for (const word of ['000000000000f07f', '000000000000f0ff', '010000000000f07f',
    '000000000000f87f', '000000000000f8ff', '000000000000F03F', '000000000000000'])
    reject('start-recipe', copy => { copy.position.ellipsoid_height_m = tag(word); });
  reject('start-recipe', copy => { copy.position.latitude_rad = 0; });
  reject('start-recipe', copy => { copy.orientation_rpy_ned_rad.yaw = {$binary64_le: '0000000000000000', extra: true}; });
  reject('start-recipe', copy => { copy.orientation_rpy_ned_rad.yaw = {$binary64_be: '0000000000000000'}; });
  for (const [key, wrong] of [['id', 'ready-runway16'], ['selector', 'original-synthetic'],
    ['named_start', 'apron-ready'], ['wind_profile', 'calm-v2'], ['seed', 42]])
    reject('start-recipe', copy => { copy[key] = wrong; });
});

test('component path grammar refuses escapes, alternative separators and unknown rows', () => {
  for (const bad of ['', '/absolute', 'C:/drive', 'C:relative', '../escape', 'a/../b', './a',
    'a/.', 'a/..', 'a//b', 'a/', 'a\\b', 'a\u0000b', 'a\nb', 'a.json\n'])
    reject('component', copy => { copy.sources[0].path = bad; });
  const dotted = structuredClone(data.component); dotted.sources[0].path = 'native/a.b/.hidden.hpp';
  expect('component', dotted, true);
  reject('component', copy => { copy.sources = []; copy.controls = []; });
  reject('component', copy => { copy.sources.push(structuredClone(copy.sources[0])); });
  reject('component', copy => { copy.sources = Array.from({length: 257}, (_, i) => ({path: 'src/' + i + '.cpp', sha256: '0'.repeat(64)})); });
  reject('component', copy => { copy.sources[0].sha256 = 'f'.repeat(65); });
});

test('native observation fixes four ordered units, seven witnesses and resource names', () => {
  reject('native-closure', copy => { copy.passed = false; });
  reject('native-closure', copy => { copy.scope = 'entire-simulator-qualified'; });
  reject('native-closure', copy => { copy.component_manifest.path = 'component-v2.json'; });
  reject('native-closure', copy => { copy.component_manifest.bytes = 65537; });
  reject('native-closure', copy => { copy.native_identity.source_variant = 'world-specific-backend'; });
  reject('native-closure', copy => { copy.native_identity.resource.build_path = 'elsewhere.gd'; });
  reject('native-closure', copy => { copy.native_identity.resource.staged_path = 'native_identity.gd'; });
  reject('native-closure', copy => { copy.translation_units.reverse(); });
  reject('native-closure', copy => { copy.translation_units.pop(); });
  reject('native-closure', copy => { copy.translation_units[0].compile_commands_index = -1; });
  reject('native-closure', copy => { copy.translation_units[0].fp_policy = 'fast-math'; });
  reject('native-closure', copy => { copy.translation_units[0].object_path = '../validation.obj'; });
  reject('native-closure', copy => { copy.link.grid_objects.pop(); });
  reject('native-closure', copy => { copy.build_witnesses.reverse(); });
  reject('native-closure', copy => { copy.build_witnesses.push(structuredClone(copy.build_witnesses[0])); });
  reject('native-closure', copy => { copy.native_identity.bridge.path = 'download/other.dll'; });
  const gnu = structuredClone(data['native-closure']);
  gnu.native_identity.bridge.path = gnu.link.bridge.path = gnu.build_witnesses[0].path = 'bin/libflight_godot_bridge.so';
  for (const row of gnu.translation_units) row.fp_policy = 'gnu-no-fast-no-contract';
  expect('native-closure', gnu, true);
});

test('actual-input response rows are closed, bounded and never executable directives', () => {
  const response = {path: 'response/compile.rsp', bytes: 4194304, sha256: '0'.repeat(64)};
  const copy = structuredClone(data['native-closure']);
  copy.translation_units[0].response_files = [response]; copy.link.response_files = [structuredClone(response)];
  expect('native-closure', copy, true);
  reject('native-closure', row => { row.translation_units[0].response_files = [{...response, bytes: 4194305}]; });
  reject('native-closure', row => { row.link.response_files = [{...response, execute: true}]; });
  reject('native-closure', row => { row.link.response_files = [response, structuredClone(response)]; });
  reject('native-closure', row => { row.link.response_files = Array.from({length: 17}, (_, i) => ({...response, path: 'response/' + i + '.rsp'})); });
  for (const bad of [0, -1, 1.5, '1', NaN, Infinity])
    reject('native-closure', row => { row.native_identity.bytes = bad; });
});

test('shape success explicitly leaves actual semantic admission unproved', () => {
  const wrongPose = structuredClone(data['start-recipe']);
  wrongPose.orientation_rpy_ned_rad.roll = tag('000000000000f03f'); // 1rad, exceeds semantic0.2 bound.
  expect('start-recipe', wrongPose, true);
  const crossed = structuredClone(data.component);
  crossed.controls[0] = structuredClone(crossed.sources[0]); // cross-array path uniqueness is external.
  expect('component', crossed, true);
  const wrongLink = structuredClone(data['native-closure']);
  wrongLink.link.grid_objects.reverse(); wrongLink.component_sha256 = '1'.repeat(64);
  expect('native-closure', wrongLink, true);
  // None establishes actual ordered source/command/response/archive graph equality,
  // staged bytes, source fingerprints, external pins, readiness, pilot or phase gates.
});
