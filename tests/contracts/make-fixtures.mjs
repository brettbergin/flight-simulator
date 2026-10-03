// Original synthetic examples, independent of JSBSim aircraft distributions.
import { createHash } from 'node:crypto';
import { mkdir, readFile, writeFile } from 'node:fs/promises';
import { contractSetSha256 } from '../../schemas/validate.mjs';
const check = process.argv.includes('--check');
const hash = bytes => createHash('sha256').update(bytes).digest('hex');
const output = new Map();
const encode = value => JSON.stringify(value, null, 2) + '\n';
const packFile = (name, data, role) => {
  const bytes = encode(data); output.set(`packs/${name}`, bytes);
  return { path: name, sha256: hash(bytes), bytes: Buffer.byteLength(bytes), role };
};
const modelFile = packFile('original-synthetic-model.json', { notice: 'Original schema-only prototype; no flight dynamics, Cessna performance, or training-credit claim.' }, 'dynamics');
const mappingFile = packFile('original-synthetic-mapping.json', { pitch_positive: 'nose-up', elevator_positive: 'trailing-edge-down', pitch_to_elevator_sign: -1 }, 'mapping');
const ref = id => ({ id, version: '0.1.0-prototype', sha256: modelFile.sha256 });
const record = (type, fields) => ({ type, schema_version: 1, ...fields });
const header = { tick: '0', session_id: 'synthetic-session' };
const clock = { tick_rate_hz: 120, purpose: 'runtime' };
const assistance = { profile_id: 'unassisted', active: [] };
const position = { latitude_rad: 0, longitude_rad: 0, ellipsoid_height_m: 0 };
const vector = { x: 0, y: 0, z: 0 };
const aircraft = record('AircraftSnapshot', { ...header, clock, elapsed_s: 0, position,
  ecef_position_m: { x: 6378137, y: 0, z: 0 }, orientation_body_to_ned: { w: 1, x: 0, y: 0, z: 0 },
  velocity_body_mps: vector, angular_rate_body_radps: vector, acceleration_body_mps2: vector,
  mass_kg: 1000, center_of_gravity_body_m: vector, configuration: { flap_fraction: 0, gear_fraction: 1, trim_fraction: 0 },
  systems: [{ id: 'engine.rotation', quantity: 'radps', value: 0, validity: 'valid' }], contacts: [], validity: 'initializing' });
const atmosphere = record('AtmosphereSample', { ...header, position, pressure_pa: 101325, temperature_k: 288.15,
  density_kgpm3: 1.225, relative_humidity: 0, wind_toward_ned_mps: vector, turbulence_ned_mps: vector,
  seed: '9007199254740993', model_id: 'synthetic-still-air' });
const initial_conditions = { aircraft, atmosphere };
const sources = [{ id: 'original-fixture', revision: '1', locator: 'urn:flight-simulator:original-contract-fixture', sha256: modelFile.sha256,
  rights: 'redistributable', license: 'MIT', applicability: 'Original schema-only synthetic test data; no real airframe or airport.', effective_from: null, effective_until: null }];
const pack = { id: 'original-synthetic', version: '0.1.0-prototype', compatible_schema_version: 1,
  evidence: { status: 'prototype', report_ids: [], source_ids: ['original-fixture'] }, sources, files: [modelFile, mappingFile] };
const fields = {
  ControlCommand: { ...header, tick: '1', sequence: '9007199254740993', source_id: 'pilot.controls', authority: 'pilot', assistance,
    payload: { kind: 'axes', roll: 0, pitch: 0.5, yaw: 0, throttle: 0, mixture: 1, left_brake: 0, right_brake: 0, trim: 0 } },
  SessionControl: { ...header, sequence: '1', source_id: 'session.owner', payload: { kind: 'pause', paused: true } },
  AircraftSnapshot: aircraft,
  InstrumentSnapshot: { ...header, channels: [{ id: 'airspeed', sensor_tick: '0', quantity: 'mps', value: null, latency_s: 0.1, filter_id: 'none', status: 'off' }] },
  AtmosphereSample: atmosphere,
  GroundSample: { ...header, position, datum: 'wgs84-ellipsoid', sample: { kind: 'valid', surface_height_m: 0,
    normal_ned: { x: 0, y: 0, z: -1 }, static_friction: 0.8, dynamic_friction: 0.6, material_id: 'synthetic-asphalt', world: ref('synthetic-world') } },
  OperationalEvent: { ...header, sequence: '1', source_id: 'sim', confidence: 'observed', content_version: '0.1.0-prototype', payload: { kind: 'pause', paused: true } },
  SessionManifest: { session_id: header.session_id, build: { id: 'contract-fixture', git_commit: '0'.repeat(40), fingerprint: modelFile.sha256 },
    contract_set_sha256: contractSetSha256, aircraft: ref('synthetic-aircraft'), world: ref('synthetic-world'), scenario: ref('synthetic-scenario'),
    seed: atmosphere.seed, clock, calibration: ref('synthetic-calibration'), assistance, initial_conditions,
    command_log: { path: 'commands.jsonl', sha256: hash(''), bytes: 0, role: 'command-log' },
    event_log: { path: 'events.jsonl', sha256: hash(''), bytes: 0, role: 'event-log' }, restore_capability: 'unsupported', restore_evidence_id: null, created_utc: '2026-10-03T00:00:00Z' },
  ReplayHeader: { session: ref('synthetic-session'), build_fingerprint: modelFile.sha256, contract_set_sha256: contractSetSha256,
    clock, seed: atmosphere.seed, record_count: '0', command_log_sha256: hash(''), determinism: 'unproven' },
  Checkpoint: { ...header, id: 'synthetic-checkpoint', session_manifest_sha256: modelFile.sha256, build_fingerprint: modelFile.sha256,
    restore_capability: 'replay-from-start', restore_evidence_id: 'synthetic-schema-example-only', blobs: [], replay_until_tick: '0' },
  TrainingResult: { session_id: header.session_id, lesson: ref('synthetic-lesson'), rubric: ref('synthetic-rubric'), status: 'incomplete', repeatability: 'unverified', assistance,
    observations: [{ objective_id: 'schema-example', result: 'not-observed', start_tick: '0', end_tick: '0', evidence_event_sequences: [], explanation_id: 'not-flown' }], invalid_reasons: [] },
  AircraftManifest: { ...pack, identity: { manufacturer: 'Original fixture', family: 'Synthetic', variant: 'Schema example', configuration_id: 'synthetic-config',
    serial_applicability: 'No real aircraft', engine: 'Unmodeled', propeller: 'Unmodeled', panel: 'Unmodeled', poh_source_id: null },
    dynamics: { backend: 'fixture', model_path: modelFile.path, provenance: 'original-synthetic', parameter_source_ids: ['original-fixture'] },
    capabilities: ['single-engine-piston'], controls: [{ id: 'electrical.master', value_type: 'boolean', minimum: 0, maximum: 1 }],
    mass_envelope_kg: { minimum: 900, maximum: 1100 }, cg_envelope_body_m: { minimum: { x: -1, y: -1, z: -1 }, maximum: { x: 1, y: 1, z: 1 } },
    geometry: { wingspan_m: 10, length_m: 8, height_m: 3 }, checklist_ids: [], limit_source_ids: ['original-fixture'], mapping_path: mappingFile.path },
  WorldPackage: { ...pack, coverage: { south_rad: -0.1, north_rad: 0.1, west_rad: -0.1, east_rad: 0.1, crosses_antimeridian: false },
    horizontal_datum: 'wgs84', vertical_datum: 'wgs84-ellipsoid', geoid: null, magnetic_model: null,
    effective_from: '2026-10-03T00:00:00Z', effective_until: '2026-10-04T00:00:00Z', data_status: 'synthetic', products: ['terrain'], update_policy: 'fixed-scenario' },
  ScenarioManifest: { ...pack, jurisdiction: 'synthetic', prerequisites: [], required_aircraft: ref('synthetic-aircraft'), required_world: ref('synthetic-world'),
    seed: atmosphere.seed, clock, initial_conditions, objectives: ['schema-example'], rubric: ref('synthetic-rubric'), allowed_assists: [],
    scheduled_actions: [], safe_restart_ticks: ['0'], evidence_event_kinds: ['pause'], source_edition_ids: ['original-fixture'] }
};
for (const [type, value] of Object.entries(fields)) output.set(`${type}.json`, encode(record(type, value)));
output.set('geodesy.json', encode({ provenance: 'Original analytical cases from WGS84 defining constants; not operational airport data.',
  references: ['https://earth-info.nga.mil/?action=wgs84&dir=wgs84'], tolerance_m: 0.00001,
  cases: [{ name: 'equator-prime-meridian', geodetic: [0, 0, 0], ecef_m: [6378137, 0, 0] },
    { name: 'equator-east-90', geodetic: [0, Math.PI / 2, 0], ecef_m: [0, 6378137, 0] },
    { name: 'north-pole', geodetic: [Math.PI / 2, 0, 0], ecef_m: [0, 0, 6356752.314245179] },
    { name: 'south-pole', geodetic: [-Math.PI / 2, 0, 0], ecef_m: [0, 0, -6356752.314245179] },
    { name: 'equator-dateline-1000m', geodetic: [0, Math.PI, 1000], ecef_m: [-6379137, 0, 0] },
    { name: 'latitude45-longitude45', geodetic: [Math.PI / 4, Math.PI / 4, 0], ecef_m: [3194419.1450605746, 3194419.1450605746, 4487348.408865919] }] }));
const entries = [...output].map(([path, bytes]) => ({ path, sha256: hash(bytes), bytes: Buffer.byteLength(bytes) }));
output.set('manifest.json', encode({ fixture_version: 1, evidence_status: 'prototype', notice: 'Schema/geodesy fixtures only; no FDM validation or restoration proof.', contract_set_sha256: contractSetSha256, files: entries }));
for (const [path, bytes] of output) {
  const url = new URL(`fixtures/${path}`, import.meta.url);
  if (check) { if (await readFile(url, 'utf8') !== bytes) throw new Error(`Stale fixture: ${path}`); }
  else { await mkdir(new URL('.', url), { recursive: true }); await writeFile(url, bytes); }
}
console.log(`${check ? 'Checked' : 'Generated'} ${entries.length} original fixtures`);
