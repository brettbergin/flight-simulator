import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { createHash } from 'node:crypto';
import { execFileSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { validateContract, registry, contractSetSha256, isSafeRelativePath } from '../../schemas/validate.mjs';

const fixtures = new Map();
for (const entry of registry.contracts) fixtures.set(entry.type, JSON.parse(await readFile(new URL(`fixtures/${entry.type}.json`, import.meta.url))));
const copy = type => structuredClone(fixtures.get(type));
const reject = (type, mutate) => { const data = copy(type); mutate(data); assert.equal(validateContract(data).valid, false, JSON.stringify(data)); };
test('all 14 boundaries have independently hashed original fixtures', async () => {
  assert.equal(registry.contracts.length, 14);
  const manifest = JSON.parse(await readFile(new URL('fixtures/manifest.json', import.meta.url)));
  assert.equal(manifest.contract_set_sha256, contractSetSha256);
  for (const file of manifest.files) {
    const bytes = await readFile(new URL(`fixtures/${file.path}`, import.meta.url));
    assert.equal(bytes.length, file.bytes);
    assert.equal(createHash('sha256').update(bytes).digest('hex'), file.sha256);
  }
  for (const [type, fixture] of fixtures) assert.deepEqual(validateContract(fixture, type), { valid: true, errors: [] }, type);
});
test('checked-in schemas and fixtures exactly match authoritative definitions', () => {
  execFileSync(process.execPath, [fileURLToPath(new URL('../../schemas/generate.mjs', import.meta.url)), '--check']);
  execFileSync(process.execPath, [fileURLToPath(new URL('make-fixtures.mjs', import.meta.url)), '--check']);
});
test('closed, versioned contracts reject incompatible or arbitrary payloads without mutating input', () => {
  for (const [type] of fixtures) {
    reject(type, d => { d.schema_version = 2; });
    reject(type, d => { d.extra = 'unrecognized'; });
  }
  assert.equal(validateContract({ type: 'Unknown', schema_version: 1 }).valid, false);
  assert.equal(validateContract(copy('ControlCommand'), 'SessionControl').valid, false);
  const data = copy('ControlCommand'); data.payload.pitch = '0.5'; const before = structuredClone(data);
  assert.equal(validateContract(data).valid, false); assert.deepEqual(data, before);
  reject('ControlCommand', d => { d.payload = { kind: 'execute', script: 'anything' }; });
});
test('uint64 strings round-trip beyond Number safe range and reject all noncanonical forms', () => {
  for (const value of ['0', '9007199254740993', '18446744073709551615']) {
    const data = copy('ControlCommand'); data.tick = value;
    const roundtrip = JSON.parse(JSON.stringify(data)); assert.equal(roundtrip.tick, value); assert.equal(validateContract(roundtrip).valid, true);
  }
  for (const value of ['18446744073709551616', '01', '-1', '+1', '1.0', '1e3', '', 9007199254740992]) reject('ControlCommand', d => { d.tick = value; });
});
test('finite SI domains, axes, temperatures and frame quaternion length are enforced', () => {
  for (const value of [NaN, Infinity, -Infinity, 1.01, -1.01]) reject('ControlCommand', d => { d.payload.pitch = value; });
  reject('ControlCommand', d => { d.payload.throttle = -0.01; });
  reject('AircraftSnapshot', d => { d.orientation_body_to_ned.w = 0.5; });
  reject('AircraftSnapshot', d => { d.position.latitude_rad = 45; });
  reject('AircraftSnapshot', d => { d.mass_kg = -1; });
  reject('AircraftSnapshot', d => { d.velocity_body_mps.x = Infinity; });
  reject('AircraftSnapshot', d => { d.ecef_position_m.x /= 0.3048; });
  reject('AtmosphereSample', d => { d.temperature_k = 0; });
  reject('AtmosphereSample', d => { d.relative_humidity = 1.1; });
  reject('AircraftSnapshot', d => { d.systems[0].quantity = 'bool'; });
});
test('fixed runtime tick and sensed rather than hidden truth constraints', () => {
  reject('AircraftSnapshot', d => { d.elapsed_s = 0.1; });
  reject('AircraftSnapshot', d => { d.clock.tick_rate_hz = 60; });
  const data = copy('AircraftSnapshot'); data.clock = { tick_rate_hz: 60, purpose: 'convergence' };
  assert.equal(validateContract(data).valid, true);
  reject('InstrumentSnapshot', d => { d.channels[0].sensor_tick = '1'; });
  reject('InstrumentSnapshot', d => { d.channels[0].status = 'normal'; });
  reject('InstrumentSnapshot', d => { d.channels[0].value = 10; });
  reject('InstrumentSnapshot', d => { d.channels[0].latency_s = -0.1; });
});
test('duplicate channel/system/contact identifiers cannot create conflicting interpretations', () => {
  reject('InstrumentSnapshot', d => { const other = structuredClone(d.channels[0]); other.status = 'normal'; other.value = 20; d.channels.push(other); });
  reject('AircraftSnapshot', d => { const other = structuredClone(d.systems[0]); other.value = 50; d.systems.push(other); });
  reject('AircraftSnapshot', d => { const contact = { id: 'left-main', point_body_m: { x: 0, y: 0, z: 0 }, force_body_n: { x: 0, y: 0, z: 0 }, on_ground: true };
    d.contacts = [contact, { ...structuredClone(contact), on_ground: false }]; });
  reject('SessionManifest', d => { d.initial_conditions.aircraft.systems.push(structuredClone(d.initial_conditions.aircraft.systems[0])); });
  const unique = copy('InstrumentSnapshot'); const channel = structuredClone(unique.channels[0]); channel.id = 'altimeter'; unique.channels.push(channel);
  assert.equal(validateContract(unique).valid, true);
});
test('ground data missing cannot masquerade as a valid contact and normal/friction are physical', () => {
  reject('GroundSample', d => { d.sample.normal_ned.z = 0; });
  reject('GroundSample', d => { d.sample.dynamic_friction = 0.9; });
  const data = copy('GroundSample'); data.sample = { kind: 'missing', reason: 'not-loaded' };
  assert.equal(validateContract(data).valid, true);
  data.sample.surface_height_m = 0; assert.equal(validateContract(data).valid, false);
});
test('session/checkpoint declarations require identity and evidence without granting restoration proof', () => {
  reject('SessionManifest', d => { d.initial_conditions.aircraft.session_id = 'other-session'; });
  reject('SessionManifest', d => { d.restore_capability = 'complete-checkpoint'; });
  reject('SessionManifest', d => { d.initial_conditions.atmosphere.tick = '1'; });
  reject('Checkpoint', d => { d.replay_until_tick = '1'; });
  reject('Checkpoint', d => { d.restore_capability = 'complete-checkpoint'; });
  reject('SessionControl', d => { d.payload = { kind: 'time_scale', scale: 100 }; });
  const event = copy('OperationalEvent'); event.payload = { kind: 'time-scale', scale: 4 };
  assert.equal(validateContract(event).valid, true);
  event.payload = { kind: 'command-rejected', command_sequence: '1', reason: 'capacity' };
  assert.equal(validateContract(event).valid, true);
});
test('content paths, source/effective intervals, coverage, sizes and evidence are bounded', () => {
  for (const path of ['../evil.json', '/absolute.json', 'C:/bad.json', 'a\\b.json', 'a//b.json', './x.json', 'a/../x.json', 'a/', 'CON.json', 'dir/NUL.json', 'x./safe.json']) {
    assert.equal(isSafeRelativePath(path), false); reject('AircraftManifest', d => { d.files[0].path = path; });
  }
  for (const path of ['evil.dll', 'evil.gd', 'evil.py', 'evil.tscn', 'evil.sql', 'evil.exe']) reject('AircraftManifest', d => { d.files[0].path = path; });
  reject('AircraftManifest', d => { d.mass_envelope_kg.minimum = 2000; });
  reject('AircraftManifest', d => { d.files.push(structuredClone(d.files[0])); });
  reject('AircraftManifest', d => { const other = structuredClone(d.files[0]); other.path = other.path.toUpperCase(); d.files.push(other); });
  reject('AircraftManifest', d => { d.evidence.source_ids = ['missing']; });
  reject('AircraftManifest', d => { d.evidence.status = 'validated'; });
  reject('WorldPackage', d => { d.effective_until = d.effective_from; });
  reject('WorldPackage', d => { d.effective_until = '2026-02-30T00:00:00Z'; });
  reject('WorldPackage', d => { d.vertical_datum = 'navd88'; });
  reject('WorldPackage', d => { d.coverage.crosses_antimeridian = true; });
  reject('WorldPackage', d => { d.magnetic_model = { id: 'synthetic-magnetic', epoch_year: 2025, source_id: 'missing-source' }; });
  const magnetic = copy('WorldPackage'); magnetic.magnetic_model = { id: 'synthetic-magnetic', epoch_year: 2025, source_id: 'original-fixture' };
  assert.equal(validateContract(magnetic).valid, true);
  reject('AircraftManifest', d => { d.files[0].bytes = 2147483648; });
});
test('training evidence range/completeness and invalid reasons are consistent', () => {
  reject('TrainingResult', d => { d.observations[0].start_tick = '1'; });
  reject('TrainingResult', d => { d.status = 'complete'; });
  reject('TrainingResult', d => { d.status = 'invalid'; });
  reject('TrainingResult', d => { d.invalid_reasons = ['bad-state']; });
  reject('TrainingResult', d => { d.status = 'complete'; d.observations = []; });
  reject('TrainingResult', d => { const other = structuredClone(d.observations[0]); other.result = 'met'; d.observations.push(other); });
  const complete = copy('TrainingResult'); complete.status = 'complete'; complete.observations[0].result = 'met';
  assert.equal(validateContract(complete).valid, true);
  const emptyIncomplete = copy('TrainingResult'); emptyIncomplete.observations = [];
  assert.equal(validateContract(emptyIncomplete).valid, true);
});
