import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { createHash } from 'node:crypto';
import { validateSourcePair } from '../../../tools/ingest/airports/source-contract.mjs';

const fixture = name => readFileSync(new URL('./fixtures/' + name, import.meta.url));
const dossierBytes = fixture('dossier-valid.json');
const airportBytes = fixture('airport-valid.json');
const fresh = () => ({ dossier: JSON.parse(dossierBytes), airport: JSON.parse(airportBytes) });
const bytes = value => Buffer.from(JSON.stringify(value), 'utf8');
function pair(dossier, airport) {
  const raw = bytes(dossier);
  airport.dossier_sha256 = createHash('sha256').update(raw).digest('hex');
  return validateSourcePair(raw, bytes(airport));
}
function rejects(label, mutate, fragment = '') {
  test(label, () => {
    const { dossier, airport } = fresh();
    mutate(dossier, airport);
    const result = pair(dossier, airport);
    assert.equal(result.ok, false);
    assert.equal(result.dossier, null);
    assert.equal(result.airport, null);
    assert.ok(result.errors.length > 0 && result.errors.length <= 64);
    if (fragment) assert.ok(result.errors.some(error => error.message.includes(fragment)), JSON.stringify(result.errors));
  });
}

test('valid synthetic fixture retains source-only unresolved datums and unknown thresholds', () => {
  const result = validateSourcePair(dossierBytes, airportBytes);
  assert.equal(result.ok, true, JSON.stringify(result.errors));
  assert.equal(result.airport.purpose, 'synthetic-fixture');
  assert.equal(result.airport.reference_point.horizontal_crs, null);
  assert.equal(result.airport.field_elevation.vertical_datum, 'unresolved');
  assert.equal(result.airport.runways[0].ends[0].displacement_m.value, null);
  assert.equal(result.airport.runways[0].ends[0].declared_distances.lda_m.status, 'unknown');
});

test('all-unknown draft and zero runway records remain source preparation, not fake defaults', () => {
  const result = validateSourcePair(dossierBytes, fixture('airport-unknown-valid.json'));
  assert.equal(result.ok, true, JSON.stringify(result.errors));
  assert.equal(result.airport.reference_point.latitude_deg, null);
  assert.equal(result.airport.runways.length, 0);
});

test('cross-checked source facts can retain unresolved vertical realization without canonical claim', () => {
  const { dossier, airport } = fresh();
  airport.review_state = 'cross-checked';
  airport.field_elevation.vertical_datum = 'msl-unspecified';
  airport.reference_point.horizontal_crs = { authority: 'source', code: 'NAD83', realization: null, epoch_year: null };
  const result = pair(dossier, airport);
  assert.equal(result.ok, true, JSON.stringify(result.errors));
  assert.equal(result.airport.field_elevation.vertical_datum, 'msl-unspecified');
});

test('pending source keeps missing artifact and retrieval explicit', () => {
  const { dossier, airport } = fresh();
  dossier.sources[0].capture_state = 'pending';
  dossier.sources[0].artifact = null;
  dossier.sources[0].retrieved_utc = null;
  dossier.sources[0].rights = { status: 'pending', license: null, notice: '', reviewed_utc: null };
  const unknown = JSON.parse(fixture('airport-unknown-valid.json'));
  assert.equal(pair(dossier, unknown).ok, true);
});

test('fixture witness has exact independently retained source bytes', () => {
  const source = JSON.parse(dossierBytes).sources[0];
  const witness = fixture('source-witness.txt');
  assert.equal(witness.toString(), 'Original synthetic schema fixture. No operational KAWO facts.\n');
  assert.equal(witness.byteLength, source.artifact.bytes);
  assert.equal(createHash('sha256').update(witness).digest('hex'), source.artifact.sha256);
});

rejects('unknown top-level keys fail without stripping', (_d, a) => { a.current = true; });
rejects('unsupported schema version fails', (_d, a) => { a.schema = 'NormalizedAirport/v2'; });
rejects('different airport is outside the bounded contract', (_d, a) => { a.airport_icao = 'KPAE'; });
rejects('BOOL is not an elevation', (_d, a) => { a.field_elevation.value = true; });
rejects('unknown displacement cannot silently become zero', (_d, a) => { a.runways[0].ends[0].displacement_m.value = 0; });
rejects('out of range source position fails', (_d, a) => { a.reference_point.latitude_deg = 91; });
rejects('unknown source reference fails', (_d, a) => { a.name.source_refs[0].source_id = 'missing'; }, 'unknown source');
rejects('duplicate source IDs fail', d => { d.sources.push(structuredClone(d.sources[0])); }, 'duplicate source');
rejects('duplicate source references fail', (_d, a) => { a.name.source_refs.push(structuredClone(a.name.source_refs[0])); }, 'duplicate source reference');
rejects('duplicate end IDs fail', (_d, a) => { a.runways[0].ends[1].id = a.runways[0].ends[0].id; }, 'duplicate runway or end');
rejects('duplicate published designators fail', (_d, a) => { a.runways[0].ends[1].designator.value = '01'; }, 'duplicate published');
rejects('displacement cannot exceed runway length', (_d, a) => {
  a.runways[0].ends[0].displacement_m = { status: 'known', value: 1001, source_refs: structuredClone(a.name.source_refs), note: '' };
}, 'displacement exceeds');
rejects('known runway width must be positive', (_d, a) => { a.runways[0].width_m.value = 0; }, 'dimensions must');
rejects('effective interval is half-open and nonempty', d => {
  d.sources[0].effective_from = '2026-10-18T12:00:00Z'; d.sources[0].effective_until = '2026-10-18T12:00:00Z';
}, 'empty or reversed');
rejects('capture cannot claim future retrieval', d => { d.sources[0].retrieved_utc = '2026-10-19T12:00:00Z'; }, 'after dossier');
rejects('reviewed capture must retain artifact identity', d => { d.sources[0].artifact = null; }, 'requires artifact');
rejects('reviewed capture cannot retain pending rights', d => {
  d.sources[0].rights = { status: 'pending', license: null, notice: '', reviewed_utc: null };
}, 'resolved rights');
rejects('reference-only source cannot claim packaged asset path', d => { d.sources[0].rights.status = 'reference-only'; }, 'package relative path');
for (const path of ['../source.txt', '/source.txt', 'a//b.txt', 'con.txt', 'a/../b.txt', 'a./b.txt'])
  rejects('unsafe artifact path ' + path, d => { d.sources[0].artifact.relative_path = path; }, 'unsafe artifact');
rejects('credential-bearing source URL fails', d => { d.sources[0].url = 'https://name:secret@example.invalid/source'; }, 'no credentials');
rejects('synthetic witness cannot relabel a real source record', (d, a) => { d.purpose = 'source-record'; a.purpose = 'source-record'; }, 'must not mix');
rejects('cross-checked required source fields cannot be unknown', (_d, a) => {
  a.review_state = 'cross-checked'; a.name = { status: 'unknown', value: null, source_refs: [], note: '' };
}, 'requires known');
rejects('cross-checked record cannot have unresolved dossier conflicts', (d, a) => {
  a.review_state = 'cross-checked';
  d.conflicts.push({ field: '/runways/0', summary: 'Synthetic conflict', source_refs: [
    { source_id: 'fixture.source', locator: 'candidate 1' }, { source_id: 'fixture.source', locator: 'candidate 2' }], resolution: null });
}, 'unresolved source conflict');

test('raw dossier hash mismatch rejects even semantically identical reformatted JSON', () => {
  const compact = bytes(JSON.parse(dossierBytes));
  const result = validateSourcePair(compact, airportBytes);
  assert.equal(result.ok, false);
  assert.ok(result.errors.some(error => error.message.includes('raw byte hash mismatch')));
});

for (const [label, content, message] of [
  ['duplicate keys', '{"schema":1,"schema":2}', 'duplicate JSON'],
  ['escaped duplicate keys', '{"schema":1,"\\u0073chema":2}', 'duplicate JSON'],
  ['overflow number', '{"x":1e400}', 'nonfinite'],
  ['unpaired surrogate', '{"x":"\\ud800"}', 'surrogate'],
  ['trailing content', '{}{}', 'trailing'],
  ['invalid leading zero', '{"x":01}', 'delimiter'],
  ['too deep', '['.repeat(34) + '0' + ']'.repeat(34), 'structural limit'],
]) test('strict byte parser rejects ' + label, () => {
  const result = validateSourcePair(Buffer.from(content), airportBytes);
  assert.equal(result.ok, false);
  assert.ok(result.errors.some(error => error.message.includes(message)), JSON.stringify(result.errors));
});

test('malformed UTF8, BOM, empty and oversized bytes fail closed', () => {
  for (const input of [Buffer.from([0xff]), Buffer.from([0xef, 0xbb, 0xbf, 123, 125]), Buffer.alloc(0), Buffer.alloc(4194305, 32)]) {
    const result = validateSourcePair(input, airportBytes);
    assert.equal(result.ok, false);
    assert.equal(result.airport, null);
  }
});

test('conformance does not mutate caller bytes or fabricate canonical coordinates', () => {
  const d = Buffer.from(dossierBytes), a = Buffer.from(airportBytes);
  const result = validateSourcePair(d, a);
  assert.equal(result.ok, true);
  assert.deepEqual(d, dossierBytes); assert.deepEqual(a, airportBytes);
  assert.equal(Object.hasOwn(result.airport.reference_point, 'ellipsoid_height_m'), false);
});
rejects('known runway ends cannot pair nonreciprocal designators', (_d, a) => { a.runways[0].ends[1].designator.value = '16'; }, 'must be reciprocal');
rejects('known reciprocal runway sides must pair L with R', (_d, a) => { a.runways[0].ends[0].designator.value = '01L'; a.runways[0].ends[1].designator.value = '19L'; }, 'must be reciprocal');
rejects('known physical runway endpoints cannot coincide', (_d, a) => { a.runways[0].ends[1].physical_end = structuredClone(a.runways[0].ends[0].physical_end); }, 'endpoints coincide');
