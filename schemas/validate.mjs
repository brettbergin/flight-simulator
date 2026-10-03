import Ajv2020 from 'ajv/dist/2020.js';
import addFormats from 'ajv-formats';
import { readFile } from 'node:fs/promises';
import { createHash } from 'node:crypto';
import { pathToFileURL } from 'node:url';

// All references are preloaded from the local registry. No loadSchema/network hook.
const registryBytes = await readFile(new URL('registry.json', import.meta.url));
export const registry = JSON.parse(registryBytes);
export const contractSetSha256 = createHash('sha256').update(registryBytes).digest('hex');
const ajv = new Ajv2020({ strict: true, strictNumbers: true, allErrors: true, coerceTypes: false, useDefaults: false, removeAdditional: false });
addFormats(ajv);
for (const entry of [registry.definitions, ...registry.contracts]) {
  const bytes = await readFile(new URL(entry.path, import.meta.url));
  if (createHash('sha256').update(bytes).digest('hex') !== entry.sha256) throw new Error(`Schema hash mismatch: ${entry.path}`);
  ajv.addSchema(JSON.parse(bytes));
}
const validators = new Map(registry.contracts.map(entry => [entry.type, ajv.getSchema(`https://flight-simulator.invalid/contracts/v1/${entry.type}.schema.json`)]));
const maxU64 = 18446744073709551615n;
const tickFields = new Set(['tick', 'sequence', 'sensor_tick', 'start_tick', 'end_tick', 'parent_tick', 'replay_until_tick', 'command_sequence', 'seed', 'record_count']);
const tickArrays = new Set(['safe_restart_ticks', 'evidence_event_sequences']);
const packExtensions = new Set(['json', 'xml', 'glb', 'png', 'jpg', 'jpeg', 'webp', 'ogg', 'wav', 'bin', 'tif', 'tiff']);
export function isSafeRelativePath(value) {
  return typeof value === 'string' && /^[a-zA-Z0-9_./-]+$/.test(value) && value.length <= 512 &&
    !value.startsWith('/') && value.split('/').every(part => part !== '' && part !== '.' && part !== '..' &&
      !part.endsWith('.') && !/^(con|prn|aux|nul|com[1-9]|lpt[1-9])(?:\.|$)/i.test(part));
}
const norm = q => Math.hypot(...Object.values(q));
const ecef = p => {
  const f = 1 / 298.257223563, e2 = f * (2 - f), s = Math.sin(p.latitude_rad), c = Math.cos(p.latitude_rad);
  const n = 6378137 / Math.sqrt(1 - e2 * s * s);
  return { x: (n + p.ellipsoid_height_m) * c * Math.cos(p.longitude_rad),
    y: (n + p.ellipsoid_height_m) * c * Math.sin(p.longitude_rad), z: (n * (1 - e2) + p.ellipsoid_height_m) * s };
};
function semanticErrors(data) {
  const errors = [];
  const bad = (path, message) => errors.push({ instancePath: path, keyword: 'semantic', message });
  const walk = (value, path = '') => {
    if (value === null || typeof value !== 'object') return;
    for (const [key, child] of Object.entries(value)) {
      const childPath = `${path}/${key}`;
      if (tickFields.has(key) && child !== null && BigInt(child) > maxU64) bad(childPath, 'exceeds uint64');
      if (tickArrays.has(key)) for (const item of child) if (BigInt(item) > maxU64) bad(childPath, 'exceeds uint64');
      if (key === 'clock' && child.purpose === 'runtime' && child.tick_rate_hz !== 120) bad(childPath, 'runtime requires 120 Hz; other rates are convergence only');
      if (key === 'orientation_body_to_ned' && Math.abs(norm(child) - 1) > 1e-9) bad(childPath, 'quaternion must be unit length within 1e-9');
      if (key === 'normal_ned' && Math.abs(norm(child) - 1) > 1e-9) bad(childPath, 'normal must be unit length within 1e-9');
      if (key === 'path' || key === 'model_path' || key === 'mapping_path') {
        if (!isSafeRelativePath(child)) bad(childPath, 'unsafe relative path');
        if (path.startsWith('/files/') || key === 'model_path' || key === 'mapping_path') {
          if (!packExtensions.has(child.split('.').at(-1).toLowerCase())) bad(childPath, 'content cannot contain executable/script/unsupported formats');
        }
      }
      if (key === 'effective_until' && child !== null && value.effective_from !== null && Date.parse(child) <= Date.parse(value.effective_from)) bad(childPath, 'effective interval must be increasing');
      if (key === 'minimum' && typeof child === 'number' && child > value.maximum) bad(childPath, 'minimum exceeds maximum');
      if (key === 'minimum' && typeof child === 'object') for (const axis of ['x', 'y', 'z']) if (child[axis] > value.maximum[axis]) bad(childPath, 'minimum exceeds maximum');
      walk(child, childPath);
    }
    if (value.type === 'AircraftSnapshot') {
      for (const field of ['systems', 'contacts']) {
        const ids = value[field].map(item => item.id);
        if (new Set(ids).size !== ids.length) bad(`${path}/${field}`, 'duplicate stable identifier');
      }
      const expected = ecef(value.position), actual = value.ecef_position_m;
      if (Math.hypot(actual.x - expected.x, actual.y - expected.y, actual.z - expected.z) > 0.0001) bad(path + '/ecef_position_m', 'geodetic/ECEF representations differ by more than 0.1 mm');
      const time = Number(BigInt(value.tick)) / value.clock.tick_rate_hz;
      if (Math.abs(value.elapsed_s - time) > Math.max(1e-9, time * Number.EPSILON * 4)) bad(path + '/elapsed_s', 'must derive from tick/rate');
    }
    if (value.start_tick !== undefined && BigInt(value.start_tick) > BigInt(value.end_tick)) bad(path, 'evidence range reversed');
    if (value.quantity !== undefined && value.value !== null && value.value !== undefined) {
      if ((value.quantity === 'bool') !== (typeof value.value === 'boolean')) bad(path, 'quantity/value type mismatch');
      if (value.quantity === 'fraction' && (value.value < 0 || value.value > 1)) bad(path, 'fraction outside [0,1]');
      if (value.quantity === 'k' && value.value <= 0) bad(path, 'absolute kelvin must be positive');
    }
  };
  walk(data);
  if (data.type === 'InstrumentSnapshot') {
    if (new Set(data.channels.map(channel => channel.id)).size !== data.channels.length) bad('/channels', 'duplicate stable identifier');
    for (const [i, channel] of data.channels.entries()) {
      if (BigInt(channel.sensor_tick) > BigInt(data.tick)) bad(`/channels/${i}/sensor_tick`, 'future sensor sample');
      if (channel.status === 'normal' && channel.value === null) bad(`/channels/${i}/value`, 'normal channel needs sensed value');
      if (['off', 'unavailable'].includes(channel.status) && channel.value !== null) bad(`/channels/${i}/value`, 'off/unavailable channel must have null value');
    }
  }
  if (data.type === 'GroundSample' && data.sample.kind === 'valid' && data.sample.dynamic_friction > data.sample.static_friction) bad('/sample', 'dynamic friction exceeds static');
  if (data.type === 'SessionManifest') {
    if (data.restore_capability !== 'unsupported' && data.restore_evidence_id === null) bad('/restore_evidence_id', 'restore claim requires proof reference');
    for (const key of ['aircraft', 'atmosphere']) if (data.initial_conditions[key].session_id !== data.session_id || data.initial_conditions[key].tick !== '0') bad(`/initial_conditions/${key}`, 'initial state must belong to session at tick zero');
    const initialClock = data.initial_conditions.aircraft.clock;
    if (data.clock.tick_rate_hz !== initialClock.tick_rate_hz || data.clock.purpose !== initialClock.purpose) bad('/clock', 'initial clock mismatch');
  }
  if (data.type === 'Checkpoint') {
    if (data.restore_capability === 'replay-from-start' && data.replay_until_tick !== data.tick) bad('/replay_until_tick', 'replay reconstruction must reach checkpoint tick');
    if (data.restore_capability === 'complete-checkpoint' && data.blobs.length === 0) bad('/blobs', 'complete checkpoint needs hidden-state blobs');
  }
  if (data.type === 'TrainingResult') {
    if ((data.status === 'invalid') !== (data.invalid_reasons.length > 0)) bad('/invalid_reasons', 'invalid status requires reasons; other statuses cannot have invalid reasons');
    if (data.status === 'complete' && (data.observations.length === 0 || data.observations.some(o => o.result === 'not-observed'))) bad('/observations', 'complete result requires nonempty observed objectives');
    if (new Set(data.observations.map(o => o.objective_id)).size !== data.observations.length) bad('/observations', 'duplicate objective identifier');
  }
  if (data.type === 'WorldPackage') {
    const c = data.coverage;
    if (c.south_rad >= c.north_rad || (c.crosses_antimeridian ? c.west_rad <= c.east_rad : c.west_rad >= c.east_rad)) bad('/coverage', 'invalid coverage ordering');
    if (data.vertical_datum !== 'wgs84-ellipsoid' && data.geoid === null) bad('/geoid', 'non-ellipsoidal data needs explicit conversion reference');
  }
  if (data.type === 'ScenarioManifest') {
    const initial = data.initial_conditions;
    if (initial.aircraft.tick !== '0' || initial.atmosphere.tick !== '0' || initial.aircraft.session_id !== initial.atmosphere.session_id) bad('/initial_conditions', 'scenario starts with a consistent tick-zero template session');
    if (data.clock.tick_rate_hz !== initial.aircraft.clock.tick_rate_hz || data.clock.purpose !== initial.aircraft.clock.purpose) bad('/clock', 'initial clock mismatch');
  }
  if (['AircraftManifest', 'WorldPackage', 'ScenarioManifest'].includes(data.type)) {
    for (const field of ['sources', 'files', 'controls']) if (data[field]) {
      const keys = data[field].map(x => field === 'files' ? x.path.toLowerCase() : x.id);
      if (new Set(keys).size !== keys.length) bad(`/${field}`, 'duplicate stable identifier/path');
    }
    const sourceIds = new Set(data.sources.map(s => s.id));
    const paths = new Set(data.files.map(f => f.path));
    for (const sourceId of [...data.evidence.source_ids, ...(data.limit_source_ids ?? []), ...(data.dynamics?.parameter_source_ids ?? []),
      ...(data.source_edition_ids ?? []), ...(data.identity?.poh_source_id ? [data.identity.poh_source_id] : []),
      ...(data.magnetic_model ? [data.magnetic_model.source_id] : [])]) {
      if (!sourceIds.has(sourceId)) bad('/sources', `unresolved source id: ${sourceId}`);
    }
    for (const path of [data.dynamics?.model_path, data.mapping_path].filter(Boolean)) if (!paths.has(path)) bad('/files', `missing referenced file: ${path}`);
    if (data.evidence.status !== 'prototype' && data.evidence.report_ids.length === 0) bad('/evidence', 'review/validation requires evidence report IDs');
  }
  return errors;
}
export function validateContract(data, expectedType) {
  const type = data?.type;
  if (expectedType && type !== expectedType) return { valid: false, errors: [{ keyword: 'type', message: `Expected ${expectedType}` }] };
  const validate = validators.get(type);
  if (!validate) return { valid: false, errors: [{ keyword: 'type', message: 'Unsupported contract type' }] };
  if (!validate(data)) return { valid: false, errors: structuredClone(validate.errors) };
  const errors = semanticErrors(data);
  return { valid: errors.length === 0, errors };
}
if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  const path = process.argv[2];
  if (!path) throw new Error('Usage: node schemas/validate.mjs <json-file> [expected-type]');
  const result = validateContract(JSON.parse(await readFile(path, 'utf8')), process.argv[3]);
  console.log(JSON.stringify(result, null, 2));
  process.exitCode = result.valid ? 0 : 1;
}
