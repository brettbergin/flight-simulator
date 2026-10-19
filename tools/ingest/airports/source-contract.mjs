import { readFileSync } from 'node:fs';
import { createHash } from 'node:crypto';
import { createRequire } from 'node:module';

// Offline source-contract conformance only. No acquisition, filesystem writes,
// datum conversion, terrain compilation, native authority or executable content.
const require = createRequire(new URL('../../../schemas/package.json', import.meta.url));
const Ajv2020 = require('ajv/dist/2020.js').default;
const addFormats = require('ajv-formats').default;
const ajv = new Ajv2020({ strict: true, strictNumbers: true, allErrors: true,
  coerceTypes: false, useDefaults: false, removeAdditional: false });
addFormats(ajv);
const schemaBase = new URL('../../../schemas/world/resident-airport/v1/', import.meta.url);
for (const name of ['common', 'source-dossier', 'normalized-airport']) {
  ajv.addSchema(JSON.parse(readFileSync(new URL(name + '.schema.json', schemaBase), 'utf8')));
}
const id = 'https://flight-simulator.invalid/contracts/world/resident-airport/v1/';
const dossierSchema = ajv.getSchema(id + 'source-dossier.schema.json');
const airportSchema = ajv.getSchema(id + 'normalized-airport.schema.json');
const MAX_BYTES = 4 * 1024 * 1024;
const MAX_DEPTH = 32;
const MAX_TOKENS = 200000;
const MAX_ERRORS = 64;

function strictJson(bytes) {
  if (!(bytes instanceof Uint8Array) || bytes.byteLength < 1 || bytes.byteLength > MAX_BYTES)
    throw new Error('input must be 1..4194304 UTF8 bytes');
  if (bytes[0] === 0xef && bytes[1] === 0xbb && bytes[2] === 0xbf) throw new Error('UTF8 BOM is unsupported');
  const text = new TextDecoder('utf-8', { fatal: true }).decode(bytes);
  let offset = 0, tokens = 0;
  const whitespace = () => { while (/[\x20\x09\x0a\x0d]/.test(text[offset] ?? '') && offset < text.length) offset++; };
  const stringToken = /"(?:[^"\\\u0000-\u001f]|\\(?:["\\/bfnrt]|u[0-9a-fA-F]{4}))*"/y;
  const numberToken = /-?(?:0|[1-9][0-9]*)(?:\.[0-9]+)?(?:[eE][+-]?[0-9]+)?/y;
  function string() {
    stringToken.lastIndex = offset;
    const match = stringToken.exec(text);
    if (!match) throw new Error('invalid JSON string');
    offset = stringToken.lastIndex;
    const value = JSON.parse(match[0]);
    for (let i = 0; i < value.length; i++) {
      const code = value.charCodeAt(i);
      if (code >= 0xd800 && code <= 0xdbff) {
        const next = value.charCodeAt(++i);
        if (!(next >= 0xdc00 && next <= 0xdfff)) throw new Error('unpaired Unicode surrogate');
      } else if (code >= 0xdc00 && code <= 0xdfff) throw new Error('unpaired Unicode surrogate');
    }
    return value;
  }
  function value(depth) {
    if (depth > MAX_DEPTH || ++tokens > MAX_TOKENS) throw new Error('JSON structural limit exceeded');
    whitespace();
    if (text[offset] === '"') return string();
    if (text[offset] === '{') {
      offset++; whitespace(); const object = Object.create(null), seen = new Set();
      if (text[offset] === '}') { offset++; return object; }
      while (true) {
        const key = string();
        if (seen.has(key)) throw new Error('duplicate JSON object key');
        seen.add(key); whitespace();
        if (text[offset++] !== ':') throw new Error('missing JSON colon');
        object[key] = value(depth + 1); whitespace();
        const delimiter = text[offset++];
        if (delimiter === '}') return object;
        if (delimiter !== ',') throw new Error('invalid JSON object delimiter');
        whitespace();
      }
    }
    if (text[offset] === '[') {
      offset++; whitespace(); const array = [];
      if (text[offset] === ']') { offset++; return array; }
      while (true) {
        array.push(value(depth + 1)); whitespace();
        const delimiter = text[offset++];
        if (delimiter === ']') return array;
        if (delimiter !== ',') throw new Error('invalid JSON array delimiter');
      }
    }
    for (const [literal, result] of [['true', true], ['false', false], ['null', null]]) {
      if (text.startsWith(literal, offset)) { offset += literal.length; return result; }
    }
    numberToken.lastIndex = offset;
    const match = numberToken.exec(text);
    if (!match) throw new Error('invalid JSON value');
    offset = numberToken.lastIndex;
    const number = Number(match[0]);
    if (!Number.isFinite(number)) throw new Error('nonfinite JSON number');
    return number;
  }
  const parsed = value(0); whitespace();
  if (offset !== text.length) throw new Error('trailing JSON content');
  return parsed;
}

function safeRelativePath(path) {
  return /^[A-Za-z0-9_./-]{1,512}$/.test(path) && !path.startsWith('/') &&
    path.split('/').every(part => part !== '' && part !== '.' && part !== '..' &&
      !part.endsWith('.') && !/^(con|prn|aux|nul|com[1-9]|lpt[1-9])(?:\.|$)/i.test(part));
}

function sameCrs(a, b) {
  return a === null || b === null ? a === b :
    ['authority', 'code', 'realization', 'epoch_year'].every(key => a[key] === b[key]);
}

function semantics(dossier, airport, rawDossier, bad) {
  const sourceIds = new Map();
  for (const [index, source] of dossier.sources.entries()) {
    const path = '/dossier/sources/' + index;
    if (sourceIds.has(source.id)) bad(path, 'duplicate source ID');
    sourceIds.set(source.id, source);
    let url;
    try { url = new URL(source.url); } catch { bad(path + '/url', 'invalid absolute HTTPS URL'); }
    if (url && (url.protocol !== 'https:' || url.username || url.password || !url.hostname))
      bad(path + '/url', 'HTTPS URL must have a host and no credentials');
    if (source.retrieved_utc > dossier.as_of_utc) bad(path, 'retrieval is after dossier snapshot');
    if (source.effective_from && source.effective_until && source.effective_from >= source.effective_until)
      bad(path, 'source effective interval is empty or reversed');
    if (source.capture_state === 'pending' && source.retrieved_utc !== null) bad(path, 'pending source must retain unknown retrieval UTC');
    if (source.capture_state !== 'pending' && source.retrieved_utc === null) bad(path, 'captured source requires retrieval UTC');
    if (source.capture_state === 'pending' && source.artifact !== null)
      bad(path, 'pending source cannot claim captured artifact');
    if (source.capture_state !== 'pending' && source.artifact === null)
      bad(path, 'captured or reviewed source requires artifact hash and byte count');
    const rights = source.rights;
    if (rights.status === 'pending') {
      if (rights.reviewed_utc !== null) bad(path, 'pending rights cannot claim review UTC');
    } else if (!rights.license || !rights.reviewed_utc || rights.reviewed_utc > dossier.as_of_utc)
      bad(path, 'resolved rights require license and applicable review UTC');
    if (source.capture_state === 'reviewed' && rights.status === 'pending')
      bad(path, 'reviewed source requires resolved rights classification');
    if (source.artifact?.relative_path !== null && source.artifact && !safeRelativePath(source.artifact.relative_path))
      bad(path, 'unsafe artifact relative path');
    if (source.artifact?.relative_path !== null && source.artifact && rights.status !== 'redistributable')
      bad(path, 'only redistributable artifacts may have a package relative path');
    if ((dossier.purpose === 'synthetic-fixture') !== (source.kind === 'original-fixture'))
      bad(path, 'fixture sources and source-record purpose must not mix');
  }
  const validateRefs = (refs, path, known = false) => {
    const seen = new Set();
    for (const ref of refs) {
      const key = ref.source_id + '\0' + ref.locator;
      if (seen.has(key)) bad(path, 'duplicate source reference');
      seen.add(key);
      const source = sourceIds.get(ref.source_id);
      if (!source) bad(path, 'unknown source reference');
      else if (known && source.capture_state === 'pending') bad(path, 'known observation requires captured source');
      else if (known && airport.review_state === 'cross-checked' && source.capture_state !== 'reviewed')
        bad(path, 'cross-checked known observation requires reviewed source');
    }
  };
  for (const [i, conflict] of dossier.conflicts.entries()) {
    validateRefs(conflict.source_refs, '/dossier/conflicts/' + i);
    if (conflict.resolution) validateRefs(conflict.resolution.source_refs, '/dossier/conflicts/' + i + '/resolution');
    else if (airport.review_state === 'cross-checked') bad('/dossier/conflicts/' + i, 'cross-checked record has unresolved source conflict');
  }
  const digest = createHash('sha256').update(rawDossier).digest('hex');
  if (airport.dossier_sha256 !== digest) bad('/airport/dossier_sha256', 'dossier raw byte hash mismatch');
  if (airport.airport_icao !== dossier.airport_icao || airport.purpose !== dossier.purpose)
    bad('/airport', 'airport and dossier identity/purpose mismatch');
  function walk(node, path) {
    if (node === null || typeof node !== 'object') return;
    if (Array.isArray(node.source_refs)) validateRefs(node.source_refs, path, node.status === 'known');
    if (node.status === 'conflicted' && airport.review_state === 'cross-checked') bad(path, 'cross-checked record contains conflicted observation');
    for (const [key, child] of Object.entries(node)) if (key !== 'source_refs') walk(child, path + '/' + key);
  }
  walk(airport, '/airport');
  const ids = new Set();
  const unique = (id, path) => { if (ids.has(id)) bad(path, 'duplicate runway or end ID'); ids.add(id); };
  const designators = new Set();
  for (const [i, runway] of airport.runways.entries()) {
    unique(runway.id, '/airport/runways/' + i);
    for (const [j, end] of runway.ends.entries()) {
      unique(end.id, '/airport/runways/' + i + '/ends/' + j);
      if (end.designator.status === 'known') {
        if (designators.has(end.designator.value)) bad('/airport/runways/' + i, 'duplicate published runway end designator');
        designators.add(end.designator.value);
      }
      if (runway.length_m.status === 'known' && end.displacement_m.status === 'known' && end.displacement_m.value > runway.length_m.value)
        bad('/airport/runways/' + i, 'threshold displacement exceeds stated runway length');
    }
    if (runway.length_m.status === 'known' && runway.length_m.value <= 0 || runway.width_m.status === 'known' && runway.width_m.value <= 0)
      bad('/airport/runways/' + i, 'known runway dimensions must be positive');
    const [first, second] = runway.ends;
    if (first.designator.status === 'known' && second.designator.status === 'known') {
      const a = first.designator.value, b = second.designator.value;
      const opposite = ((Number(a.slice(0, 2)) + 17) % 36) + 1;
      const side = { '': '', L: 'R', R: 'L', C: 'C' }[a.slice(2)];
      if (Number(b.slice(0, 2)) !== opposite || b.slice(2) !== side)
        bad('/airport/runways/' + i, 'known paired runway designators must be reciprocal');
    }
    if (first.physical_end.status === 'known' && second.physical_end.status === 'known' &&
        first.physical_end.latitude_deg === second.physical_end.latitude_deg &&
        first.physical_end.longitude_deg === second.physical_end.longitude_deg &&
        sameCrs(first.physical_end.horizontal_crs, second.physical_end.horizontal_crs))
      bad('/airport/runways/' + i, 'known physical endpoints coincide in the same stated CRS');
  }
  if (airport.review_state === 'cross-checked') {
    if ([airport.name, airport.reference_point, airport.field_elevation].some(field => field.status !== 'known') || airport.runways.length === 0)
      bad('/airport', 'cross-checked record requires known name/reference/elevation and at least one runway');
    for (const [i, runway] of airport.runways.entries()) {
      if ([runway.length_m, runway.width_m, runway.surface].some(field => field.status !== 'known') ||
          runway.ends.some(end => end.designator.status !== 'known' || end.physical_end.status !== 'known'))
        bad('/airport/runways/' + i, 'cross-checked runway requires known dimensions/surface/end designators/physical endpoints');
    }
  }
}

export function validateSourcePair(dossierBytes, airportBytes) {
  const errors = [];
  const bad = (path, message) => { if (errors.length < MAX_ERRORS) errors.push({ path: path.slice(0, 512), message }); };
  let dossier, airport;
  try { dossier = strictJson(dossierBytes); } catch (error) { bad('/dossier', error.message); }
  try { airport = strictJson(airportBytes); } catch (error) { bad('/airport', error.message); }
  if (errors.length) return { ok: false, errors, dossier: null, airport: null };
  for (const [name, validator, value] of [['dossier', dossierSchema, dossier], ['airport', airportSchema, airport]]) {
    if (!validator(value)) for (const error of validator.errors) bad('/' + name + error.instancePath, 'schema ' + error.keyword);
  }
  if (!errors.length) semantics(dossier, airport, dossierBytes, bad);
  return errors.length ? { ok: false, errors, dossier: null, airport: null } : { ok: true, errors: [], dossier, airport };
}