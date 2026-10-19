import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { createRequire } from 'node:module';

// Schema conformance only. No compiler, source decoder, PROJ, native library,
// acquisition, subprocess, or candidate product is invoked by these tests.
const require = createRequire(new URL('../../schemas/package.json', import.meta.url));
const Ajv2020 = require('ajv/dist/2020.js').default;
const ajv = new Ajv2020({ strict: true, strictNumbers: true, allErrors: true,
  coerceTypes: false, useDefaults: false, removeAdditional: false });
const base = 'https://flight-simulator.invalid/contracts/world/kawo-terrain/v1/';
for (const name of ['airport-geometry', 'inputs', 'compile-receipt'])
  ajv.addSchema(JSON.parse(readFileSync(new URL('../../schemas/world/kawo-terrain/v1/' + name + '.schema.json', import.meta.url), 'utf8')));
const fixture = name => JSON.parse(readFileSync(new URL('fixtures/world/kawo-terrain/v1/' + name, import.meta.url), 'utf8'));
const geometry = fixture('airport-geometry.valid.json');
const inputs = fixture('inputs.valid.json');
// Both pieces are handwritten, not generated from a schema or compiler output.
const receipt = { ...fixture('receipt-fields.valid.json'), airport_geometry: structuredClone(geometry) };
const validate = name => {
  const result = ajv.getSchema(base + name);
  assert.ok(result, name);
  return result;
};
const schemas = {
  inputs: validate('inputs.schema.json'),
  geometry: validate('airport-geometry.schema.json'),
  receipt: validate('compile-receipt.schema.json')
};
const data = { inputs, geometry, receipt };
function expect(name, value, expected) {
  const before = structuredClone(value);
  assert.equal(schemas[name](value), expected, JSON.stringify(schemas[name].errors));
  assert.deepEqual(value, before, 'schema validation must not mutate input');
}
function reject(name, mutate) {
  const value = structuredClone(data[name]);
  mutate(value);
  expect(name, value, false);
}
function *objects(value, path = []) {
  if (value === null || typeof value !== 'object') return;
  if (!Array.isArray(value)) yield { value, path };
  for (const [key, child] of Object.entries(value)) yield *objects(child, [...path, key]);
}
function at(value, path) {
  for (const key of path) value = value[key];
  return value;
}
const tag = word => ({ $binary64_le: word });

test('handwritten fixtures establish shape only and leave unknown source frame null', () => {
  for (const name of Object.keys(data)) expect(name, data[name], true);
  assert.equal(receipt.frame.source_realization, null);
  assert.equal(receipt.frame.source_epoch_year, null);
  assert.equal(receipt.frame.total3d_accuracy, 'unknown');
  assert.equal(receipt.operations[2].published_accuracy_m, null);
  assert.ok(receipt.operations.every(operation => operation.projjson === '{}'),
    'schema-only PROJJSON tokens must never be represented as qualified records');
});

test('every handwritten object is closed and all supplied fields are required', () => {
  for (const name of Object.keys(data)) {
    for (const { value, path } of objects(data[name])) {
      reject(name, copy => { at(copy, path).__unexpected__ = true; });
      for (const key of Object.keys(value)) reject(name, copy => { delete at(copy, path)[key]; });
    }
  }
});

test('authoring inputs close raw pins, sizes, types and local absolute path syntax', () => {
  for (const bad of ['other', 'KawoTerrainInputs/v2', 1]) reject('inputs', value => { value.schema = bad; });
  for (const key of ['tile55', 'tile55_metadata', 'tile56', 'tile56_metadata']) {
    reject('inputs', value => { value[key].bytes++; });
    reject('inputs', value => { value[key].sha256 = '0'.repeat(64); });
  }
  for (const key of ['airport', 'dossier', 'tool_qualification']) {
    for (const bad of [0, -1, 4194305, 1.5, '100', NaN, Infinity])
      reject('inputs', value => { value[key].bytes = bad; });
  }
  for (const bad of ['relative.json', '/tmp/a.json', 'C:a.json', '//server/share/a.json',
    '\\\\server\\share\\a.json', 'C:/a/../b.json', 'C:/./a.json', 'C:/a//b.json',
    'C:/a.json:stream', 'C:/a/', 'C:/a\u0000.json', 'C:/a?.json', 'C:/a.json\n'])
    reject('inputs', value => { value.airport.absolute_path = bad; });
  const windows = structuredClone(inputs);
  windows.airport.absolute_path = 'C:\\schema-fixture\\airport.json';
  expect('inputs', windows, true);
  reject('inputs', value => { value.airport.sha256 = 'A'.repeat(64); });
});

test('finite scalar encoding preserves bits and rejects nonfinite and noncanonical tags', () => {
  const finite = validate('airport-geometry.schema.json#/$defs/binary64');
  for (const word of ['0000000000000000', '0000000000000080', '0100000000000000',
    '0100000000000080', 'ffffffffffffef7f', 'ffffffffffffefff']) {
    const scalar = tag(word);
    assert.equal(finite(scalar), true, word);
    assert.equal(scalar.$binary64_le, word);
  }
  for (const row of fixture('rejected-binary64.json'))
    assert.equal(finite(row.value), false, row.name);
  const positive = validate('airport-geometry.schema.json#/$defs/positive_binary64');
  assert.equal(positive(tag('0100000000000000')), true);
  for (const word of ['0000000000000000', '0000000000000080', '000000000000f0bf'])
    assert.equal(positive(tag(word)), false, word);
});

test('raw binary64 bounds include the exact endpoint and predecessor, excluding next ULP', () => {
  // Hand IEEE754 atoms, no JS floating-point re-encoding of expected limits.
  const bounds = [
    ['nonnegative_at_most_16', 'ffffffffffff2f40', '0000000000003040', '0100000000003040'],
    ['nonnegative_at_most_2048', 'ffffffffffff9f40', '000000000000a040', '010000000000a040'],
    ['nonnegative_at_most_1_over_4096', 'ffffffffffff2f3f', '000000000000303f', '010000000000303f'],
    ['nonnegative_at_most_1_over_1024', 'ffffffffffff4f3f', '000000000000503f', '010000000000503f']
  ];
  for (const [name, below, limit, above] of bounds) {
    const check = validate('compile-receipt.schema.json#/$defs/' + name);
    for (const word of ['0000000000000000', '0100000000000000', below, limit])
      assert.equal(check(tag(word)), true, name + ': ' + word);
    for (const word of [above, '000000000000f07f', '000000000000f87f', '0000000000000080'])
      assert.equal(check(tag(word)), false, name + ': ' + word);
  }
});

test('geometry closes frame bits, labels, runway order, mm bounds and positive lengths', () => {
  reject('geometry', value => { value.world_anchor.latitude_rad.$binary64_le = 'fcfc84c1e5e5ea3f'; });
  reject('geometry', value => { value.world_anchor.ellipsoid_height_m.$binary64_le = '0000000000000080'; });
  reject('geometry', value => { value.position_frame = 'ned'; });
  reject('geometry', value => { value.bearing_reference = 'magnetic'; });
  reject('geometry', value => { value.runways.reverse(); });
  reject('geometry', value => { value.runways[0].ends.reverse(); });
  reject('geometry', value => { value.runways[0].ends[0].designator = '12'; });
  reject('geometry', value => { value.runways[0].material_polygon_id = 'kawo.runway.16-34'; });
  reject('geometry', value => { value.runways[0].ends[0].landing_threshold = null; });
  reject('geometry', value => { value.runways[0].width_m = null; });
  reject('geometry', value => { value.runways[0].width_m = tag('0000000000000000'); });
  reject('geometry', value => { value.runways[0].published_length_m = tag('000000000000f0bf'); });
  reject('geometry', value => { value.runways[0].ends[0].eus_m.push(tag('0000000000000000')); });
  for (const bad of [-8192001, 8192001, 1.5, '1'])
    reject('geometry', value => { value.runways[0].footprint_mm[0][0] = bad; });
  reject('geometry', value => { value.runways[0].footprint_mm.pop(); });
  reject('geometry', value => { value.runways[0].footprint_mm.push(value.runways[0].footprint_mm[0]); });
  reject('geometry', value => { value.runways[0].footprint_mm[1] = structuredClone(value.runways[0].footprint_mm[0]); });
});

test('receipt fixes input and operation ordering, portable locators and exact known pins', () => {
  reject('receipt', value => { [value.inputs[0], value.inputs[1]] = [value.inputs[1], value.inputs[0]]; });
  reject('receipt', value => { value.inputs.push(structuredClone(value.inputs[0])); });
  reject('receipt', value => { value.inputs[0].locator = 'C:/private/airport.json'; });
  reject('receipt', value => { value.inputs[2].sha256 = '0'.repeat(64); });
  reject('receipt', value => { value.tools.pyproj_wheel_sha256 = '0'.repeat(64); });
  reject('receipt', value => { value.operations.reverse(); });
  reject('receipt', value => { value.operations[3].direction = 'forward'; });
  reject('receipt', value => { value.operations[3].definition = '+proj=vgridshift +grids=other.tif'; });
  reject('receipt', value => { value.operations[3].grids[0].sha256 = '0'.repeat(64); });
  reject('receipt', value => { value.operations[1].published_accuracy_m = 0; });
  reject('receipt', value => { value.operations[2].published_accuracy_m = 0; });
  reject('receipt', value => { value.operations[0].axis_in = []; });
  reject('receipt', value => { value.operations[0].axis_in = ['a', 'b', 'c', 'd']; });
  reject('receipt', value => { value.operations[0].units_in = ['m\u0000']; });
  reject('receipt', value => { value.operations[0].units_in = ['degree\n']; });
  reject('receipt', value => { value.operations[0].projjson = 'x'.repeat(65537); });
});

test('receipt cannot promote source frame, alter construction, or add an output/self hash', () => {
  reject('receipt', value => { value.quality = 'survey-grade'; });
  reject('receipt', value => { value.frame.source_realization = 'NAD83(2011)'; });
  reject('receipt', value => { value.frame.source_epoch_year = 2010; });
  reject('receipt', value => { value.frame.total3d_accuracy = 4; });
  reject('receipt', value => { value.grid.spacing_m = 2; });
  reject('receipt', value => { value.grid.rows = 1537; });
  reject('receipt', value => { value.mosaic.policy = 'average-overlap'; });
  reject('receipt', value => { value.construction.updates = 7; });
  reject('receipt', value => { value.construction.initial_y_m = tag('0000000000000080'); });
  reject('receipt', value => { value.construction.pre_round_residual_limit_m = tag('010000000000303f'); });
  reject('receipt', value => { value.validation.core_definition_valid = false; });
  reject('receipt', value => { value.validation.valid_vertices = 6296578; });
  reject('receipt', value => { value.validation.max_gradient_norm = tag('0100000000003040'); });
  reject('receipt', value => { value.validation.bracket_span_m = tag('010000000000a040'); });
  reject('receipt', value => { value.validation.max_pre_round_residual_m = tag('010000000000303f'); });
  reject('receipt', value => { value.validation.max_last_delta_m = tag('010000000000303f'); });
  reject('receipt', value => { value.validation.max_post_round_residual_m = tag('010000000000503f'); });
  reject('receipt', value => { value.outputs[0].path = 'other/ground.fgrd'; });
  reject('receipt', value => { value.outputs[0].bytes = 276946837; });
  reject('receipt', value => { value.outputs.push({ path: 'compile-receipt.json', sha256: '0'.repeat(64), bytes: 1 }); });
  reject('receipt', value => { value.limitations.pop(); });
  reject('receipt', value => { value.limitations[0] = 'all frames known'; });
});

test('schema-only success explicitly leaves non-schema relationships unproved', () => {
  // Acceptance controls, not a semantic validator or acceptable compiled product.
  const unrelated = structuredClone(receipt);
  unrelated.airport_geometry.ground_payload_sha256 = '0'.repeat(64);
  unrelated.validation.missing_vertices = 1;
  unrelated.operations[0].projjson = '{}';
  expect('receipt', unrelated, true);
  const crossed = structuredClone(geometry);
  crossed.runways[0].footprint_mm = [[-1, -1], [1, 1], [-1, 1], [1, -1]];
  expect('geometry', crossed, true);
});
