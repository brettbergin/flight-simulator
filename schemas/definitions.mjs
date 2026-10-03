// Authoritative, engine-independent schema definitions. Generated JSON is checked in.
// Every object is closed; arbitrary property bags and downloaded code are excluded.
const number = (minimum, maximum) => ({ type: 'number', ...(minimum === undefined ? {} : { minimum }), ...(maximum === undefined ? {} : { maximum }) });
const integer = (minimum, maximum) => ({ type: 'integer', minimum, maximum });
const string = (maxLength = 128, pattern) => ({ type: 'string', minLength: 1, maxLength, ...(pattern ? { pattern } : {}) });
const enumeration = (...values) => ({ enum: values });
const array = (items, maxItems = 256, minItems = 0) => ({ type: 'array', items, minItems, maxItems });
const object = properties => ({ type: 'object', properties, required: Object.keys(properties), additionalProperties: false });
const ref = name => ({ $ref: `#/$defs/${name}` });
const union = (...schemas) => ({ oneOf: schemas });
const nullable = schema => union(schema, { type: 'null' });
const id = string(128, '^[a-z][a-z0-9]*(?:[._-][a-z0-9]+)*$');
const hash = string(64, '^[a-f0-9]{64}$');
const version = string(64, '^[0-9]+\\.[0-9]+\\.[0-9]+(?:-[a-z0-9.-]+)?$');
const u64 = string(20, '^(0|[1-9][0-9]{0,19})$'); // semantic validator checks UINT64_MAX
const utc = { type: 'string', format: 'date-time', pattern: 'Z$', maxLength: 32 };
const vec = () => object({ x: number(), y: number(), z: number() });
const clock = object({ tick_rate_hz: enumeration(60, 120, 240), purpose: enumeration('runtime', 'convergence') });
const base = (name, fields) => object({ type: { const: name }, schema_version: { const: 1 }, ...fields });
const sample = { tick: ref('uint64'), session_id: id };
const source = object({ id, revision: string(256), locator: string(2048), sha256: hash,
  rights: enumeration('redistributable', 'reference-only', 'pending'), license: string(256),
  applicability: string(1024), effective_from: nullable(utc), effective_until: nullable(utc) });
const file = object({ path: string(512, '^[a-zA-Z0-9_./-]+$'), sha256: hash, bytes: integer(0, 2147483647), role: id });
const evidence = object({ status: enumeration('prototype', 'reference-reviewed', 'validated'), report_ids: array(id, 128), source_ids: array(id, 128) });
const contentRef = object({ id, version, sha256: hash });
const assistance = object({ profile_id: id, active: array(id, 64, 0) });
const axisPayload = object({ kind: { const: 'axes' }, roll: number(-1, 1), pitch: number(-1, 1), yaw: number(-1, 1),
  throttle: number(0, 1), mixture: number(0, 1), left_brake: number(0, 1), right_brake: number(0, 1), trim: number(-1, 1) });
const systemPayload = object({ kind: { const: 'system' }, control_id: id, value: union({ type: 'boolean' }, number(-1, 1)) });
const initial = object({ aircraft: ref('AircraftSnapshot'), atmosphere: ref('AtmosphereSample') });
const pack = { id, version, compatible_schema_version: { const: 1 }, evidence, sources: array(source, 1024, 1), files: array(file, 4096, 1) };
const event = (kind, fields) => object({ kind: { const: kind }, ...fields });

export const definitions = {
  uint64: u64,
  geodetic: object({ latitude_rad: number(-Math.PI / 2, Math.PI / 2), longitude_rad: number(-Math.PI, Math.PI), ellipsoid_height_m: number(-2000, 10000000) }),
  ecef_m: vec(), ned_mps: vec(), body_mps: vec(), body_radps: vec(), body_mps2: vec(), body_m: vec(), ned_normal: vec(),
  quaternion_body_to_ned: object({ w: number(-1, 1), x: number(-1, 1), y: number(-1, 1), z: number(-1, 1) }),
  ControlCommand: base('ControlCommand', { ...sample, sequence: ref('uint64'), source_id: id,
    authority: enumeration('pilot', 'avionics', 'scenario', 'instructor'), assistance,
    payload: union(axisPayload, systemPayload) }),
  SessionControl: base('SessionControl', { ...sample, sequence: ref('uint64'), source_id: id,
    payload: union(event('pause', { paused: { type: 'boolean' } }), event('time_scale', { scale: enumeration(0.25, 0.5, 1, 2, 4) })) }),
  AircraftSnapshot: base('AircraftSnapshot', { ...sample, clock, elapsed_s: number(0),
    position: ref('geodetic'), ecef_position_m: ref('ecef_m'), orientation_body_to_ned: ref('quaternion_body_to_ned'),
    velocity_body_mps: ref('body_mps'), angular_rate_body_radps: ref('body_radps'), acceleration_body_mps2: ref('body_mps2'),
    mass_kg: number(0.001, 1000000), center_of_gravity_body_m: ref('body_m'),
    configuration: object({ flap_fraction: number(0, 1), gear_fraction: number(0, 1), trim_fraction: number(-1, 1) }),
    systems: array(object({ id, quantity: enumeration('fraction', 'radps', 'pa', 'k', 'kg', 'a', 'v', 'bool'), value: union(number(), { type: 'boolean' }), validity: enumeration('valid', 'unavailable') }), 256),
    contacts: array(object({ id, point_body_m: ref('body_m'), force_body_n: vec(), on_ground: { type: 'boolean' } }), 32),
    validity: enumeration('valid', 'invalid', 'initializing') }),
  InstrumentSnapshot: base('InstrumentSnapshot', { ...sample, channels: array(object({ id, sensor_tick: ref('uint64'),
    quantity: enumeration('m', 'mps', 'rad', 'radps', 'k', 'pa', 'kg', 'a', 'v', 'fraction', 'bool'),
    value: nullable(union(number(), { type: 'boolean' })), latency_s: number(0, 60),
    filter_id: id, status: enumeration('normal', 'failed', 'unreliable', 'off', 'unavailable') }), 256) }),
  AtmosphereSample: base('AtmosphereSample', { ...sample, position: ref('geodetic'), pressure_pa: number(1, 200000),
    temperature_k: number(1, 400), density_kgpm3: number(0.000001, 10), relative_humidity: number(0, 1),
    wind_toward_ned_mps: ref('ned_mps'), turbulence_ned_mps: ref('ned_mps'), seed: ref('uint64'), model_id: id }),
  GroundSample: base('GroundSample', { ...sample, position: ref('geodetic'), datum: { const: 'wgs84-ellipsoid' },
    sample: union(event('valid', { surface_height_m: number(-2000, 100000), normal_ned: ref('ned_normal'),
      static_friction: number(0, 5), dynamic_friction: number(0, 5), material_id: id, world: contentRef }),
    event('missing', { reason: enumeration('outside-coverage', 'not-loaded', 'datum-unresolved', 'invalid-data') })) }),
  OperationalEvent: base('OperationalEvent', { ...sample, sequence: ref('uint64'), source_id: id,
    confidence: enumeration('observed', 'derived', 'unknown'), content_version: version,
    payload: union(event('command-rejected', { command_sequence: ref('uint64'), reason: enumeration('late', 'duplicate', 'invalid', 'unsupported-control', 'wrong-session', 'unauthorized-source', 'capacity') }),
      event('system-state', { system_id: id, state: id }), event('failure', { failure_id: id, active: { type: 'boolean' } }),
      event('procedure', { procedure_id: id, step_id: id, result: enumeration('observed', 'omitted', 'incorrect') }),
      event('clearance', { clearance_id: id, aircraft_id: id, acknowledged: { type: 'boolean' } }),
      event('assistance', { assistance_id: id, active: { type: 'boolean' } }), event('pause', { paused: { type: 'boolean' } }),
      event('time-scale', { scale: enumeration(0.25, 0.5, 1, 2, 4) }),
      event('session-branch', { parent_session_id: id, parent_tick: ref('uint64') }),
      event('save', { checkpoint_id: id, result: enumeration('saved', 'failed') })) }),
  SessionManifest: base('SessionManifest', { session_id: id, build: object({ id, git_commit: string(40, '^[a-f0-9]{40}$'), fingerprint: hash }),
    contract_set_sha256: hash, aircraft: contentRef, world: contentRef, scenario: contentRef, seed: ref('uint64'), clock,
    calibration: contentRef, assistance, initial_conditions: initial,
    command_log: file, event_log: file, restore_capability: enumeration('unsupported', 'replay-from-start', 'safe-restart', 'complete-checkpoint'),
    restore_evidence_id: nullable(id), created_utc: utc }),
  ReplayHeader: base('ReplayHeader', { session: contentRef, build_fingerprint: hash, contract_set_sha256: hash,
    clock, seed: ref('uint64'), record_count: ref('uint64'), command_log_sha256: hash,
    determinism: enumeration('same-build-tolerances', 'unproven') }),
  Checkpoint: base('Checkpoint', { ...sample, id, session_manifest_sha256: hash, build_fingerprint: hash,
    restore_capability: enumeration('replay-from-start', 'safe-restart', 'complete-checkpoint'),
    restore_evidence_id: id, blobs: array(file, 256), replay_until_tick: nullable(ref('uint64')) }),
  TrainingResult: base('TrainingResult', { session_id: id, lesson: contentRef, rubric: contentRef,
    status: enumeration('complete', 'incomplete', 'invalid'), repeatability: enumeration('same-build', 'unverified'), assistance,
    observations: array(object({ objective_id: id, result: enumeration('met', 'not-met', 'not-observed'),
      start_tick: ref('uint64'), end_tick: ref('uint64'), evidence_event_sequences: array(ref('uint64'), 256), explanation_id: id }), 256),
    invalid_reasons: array(id, 128) }),
  AircraftManifest: base('AircraftManifest', { ...pack,
    identity: object({ manufacturer: string(), family: string(), variant: string(), configuration_id: id, serial_applicability: string(1024),
      engine: string(), propeller: string(), panel: string(), poh_source_id: nullable(id) }),
    dynamics: object({ backend: enumeration('jsbsim', 'fixture'), model_path: string(512), provenance: enumeration('original-synthetic', 'licensed-source'), parameter_source_ids: array(id, 1024) }),
    capabilities: array(id, 256, 1), controls: array(object({ id, value_type: enumeration('boolean', 'normalized'), minimum: number(-1, 1), maximum: number(-1, 1) }), 256),
    mass_envelope_kg: object({ minimum: number(0.001, 1000000), maximum: number(0.001, 1000000) }),
    cg_envelope_body_m: object({ minimum: ref('body_m'), maximum: ref('body_m') }),
    geometry: object({ wingspan_m: number(0.001, 200), length_m: number(0.001, 200), height_m: number(0.001, 100) }),
    checklist_ids: array(id, 256), limit_source_ids: array(id, 256), mapping_path: string(512) }),
  WorldPackage: base('WorldPackage', { ...pack,
    coverage: object({ south_rad: number(-Math.PI / 2, Math.PI / 2), north_rad: number(-Math.PI / 2, Math.PI / 2),
      west_rad: number(-Math.PI, Math.PI), east_rad: number(-Math.PI, Math.PI), crosses_antimeridian: { type: 'boolean' } }),
    horizontal_datum: { const: 'wgs84' }, vertical_datum: enumeration('wgs84-ellipsoid', 'egm96', 'egm2008', 'navd88'),
    geoid: nullable(contentRef), magnetic_model: nullable(object({ id, epoch_year: number(1900, 2200), source_id: id })),
    effective_from: utc, effective_until: utc, data_status: enumeration('synthetic', 'historical', 'current-source'),
    products: array(enumeration('terrain', 'airport', 'navaid', 'vector', 'imagery'), 5, 1), update_policy: enumeration('fixed-scenario', 'explicit-owner-update') }),
  ScenarioManifest: base('ScenarioManifest', { ...pack, jurisdiction: id, prerequisites: array(id, 128),
    required_aircraft: contentRef, required_world: contentRef, seed: ref('uint64'), clock, initial_conditions: initial,
    objectives: array(id, 128, 1), rubric: contentRef, allowed_assists: array(id, 64),
    scheduled_actions: array(object({ tick: ref('uint64'), action_id: id, target_id: id }), 1024),
    safe_restart_ticks: array(ref('uint64'), 128), evidence_event_kinds: array(id, 128), source_edition_ids: array(id, 128) })
};

export const contractNames = Object.keys(definitions).filter(name => /^[A-Z]/.test(name));
export function schemaFor(name) {
  if (!contractNames.includes(name)) throw new Error(`Unknown contract ${name}`);
  return { $schema: 'https://json-schema.org/draft/2020-12/schema',
    $id: `https://flight-simulator.invalid/contracts/v1/${name}.schema.json`,
    title: `${name}/v1`, $ref: `definitions.schema.json#/$defs/${name}` };
}
