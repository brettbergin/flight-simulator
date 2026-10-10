import test from 'node:test';
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { mkdtemp, mkdir, readFile, writeFile, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { parseBuildIdentity, backendIdentities, currentSourceFingerprint } from '../../tools/run-scenario/source-fingerprint.mjs';

const hash = value => createHash('sha256').update(value).digest('hex');
const backend = 'a'.repeat(64), buildControls = 'b'.repeat(64);
const manifest = (a = backend, b = buildControls) => `Source variant: synthetic-test\nBackend identity SHA256: ${a}\nBuild controls SHA256: ${b}\nCompiler: synthetic-fixture\n`;

test('build identity requires exactly one canonical backend and build-control hash', () => {
  assert.deepEqual(parseBuildIdentity(manifest()), { variant: 'synthetic-test', backend, buildControls });
  assert.deepEqual(parseBuildIdentity(manifest().replaceAll('\n', '\r\n')), { variant: 'synthetic-test', backend, buildControls });
  for (const bad of [undefined, '', 'Source variant: old-build\n',
    manifest().replace(`Backend identity SHA256: ${backend}\n`, ''),
    manifest().replace(`Build controls SHA256: ${buildControls}\n`, ''),
    manifest() + `Backend identity SHA256: ${backend}\n`,
    manifest() + `Build controls SHA256: ${buildControls}\n`,
    manifest(backend.toUpperCase()), manifest(backend.slice(1)), manifest(backend + '0'),
    manifest(backend, '0'.repeat(63)), manifest(' ' + backend), manifest(backend + ' '),
    manifest(backend.slice(0, 32) + '\r' + backend.slice(32)), manifest().replace('Source variant: synthetic-test\n', ''),
    manifest() + 'Source variant: synthetic-test\n', manifest() + 'x'.repeat(65536)]) {
    assert.throws(() => parseBuildIdentity(bad));
  }
});

test('actual adapter bytes reproduce CMake prefix, raw-byte hashes and sorted paths', async t => {
  const root = await mkdtemp(join(tmpdir(), 'flight-source-fingerprint-'));
  t.after(() => rm(root, { recursive: true, force: true }));
  const adapterRoot = join(root, 'adapter'), executable = join(root, 'build/bin/synthetic.exe');
  await mkdir(join(adapterRoot, 'src/nested'), { recursive: true });
  await mkdir(join(adapterRoot, 'include'), { recursive: true });
  await mkdir(join(root, 'build/bin'), { recursive: true });
  const source = new Map([
    ['src/z.cpp', Buffer.from('last\r\n')],
    ['src/nested/a.cpp', Buffer.from('nested\n')],
    ['include/a.hpp', Buffer.from('header\n')],
  ]);
  for (const [path, bytes] of source) await writeFile(join(adapterRoot, path), bytes);
  const manifestPath = join(root, 'build/jsbsim-source-build-manifest.txt');
  const identityBytes = await readFile(new URL('../../third_party/patches/jsbsim/event-aware-constant-power-v1/identity.json', import.meta.url));
  const inventoryBytes = await readFile(new URL('../../tools/export/jsbsim/upstream-file-inventory.json', import.meta.url));
  const accepted = backendIdentities(identityBytes, inventoryBytes);
  assert.equal(accepted.size, 2);
  await writeFile(manifestPath, manifest());
  await assert.rejects(() => currentSourceFingerprint(executable, { adapterRoot }), /unknown or stale/);
  const files = [...source.keys()].sort().map(path => `${path}:${hash(source.get(path))}\n`).join('');
  let expected;
  for (const [variant, selectedBackend] of accepted) {
    await writeFile(manifestPath, manifest(selectedBackend).replace('synthetic-test', variant));
    expected = hash(`jsbsim-backend:${selectedBackend}\njsbsim-build-controls:${buildControls}\n${files}`);
    assert.equal(await currentSourceFingerprint(executable, { adapterRoot }), expected);
  }
  const [variant, selectedBackend] = [...accepted].at(-1);
  const selectedManifest = controls => manifest(selectedBackend, controls).replace('synthetic-test', variant);
  assert.notEqual(expected, hash(files), 'old first-party-only fingerprint must fail');
  await writeFile(manifestPath, selectedManifest('d'.repeat(64)));
  assert.notEqual(await currentSourceFingerprint(executable, { adapterRoot }), expected, 'declared build controls remain in the fingerprint');
  await writeFile(manifestPath, selectedManifest(buildControls).replace(selectedBackend, 'c'.repeat(64)));
  await assert.rejects(() => currentSourceFingerprint(executable, { adapterRoot }), /unknown or stale/);
  await writeFile(manifestPath, selectedManifest(buildControls).replace(variant, 'jsbsim-unknown'));
  await assert.rejects(() => currentSourceFingerprint(executable, { adapterRoot }), /unknown or stale/);
  await writeFile(manifestPath, selectedManifest(buildControls));
  await writeFile(join(adapterRoot, 'src/z.cpp'), 'last\n');
  assert.notEqual(await currentSourceFingerprint(executable, { adapterRoot }), expected, 'raw source changes are detected');
  await writeFile(join(adapterRoot, 'src/z.cpp'), source.get('src/z.cpp'));
  await writeFile(join(adapterRoot, 'include/new.hpp'), 'new source\n');
  assert.notEqual(await currentSourceFingerprint(executable, { adapterRoot }), expected, 'new source inputs are detected');
  await rm(manifestPath);
  await assert.rejects(() => currentSourceFingerprint(executable, { adapterRoot }), /ENOENT/);
  await assert.rejects(() => currentSourceFingerprint('', { adapterRoot }), /explicit native executable/);
});

test('reviewed public backend metadata rejects inventory corruption before deriving identities', async () => {
  const identityBytes = await readFile(new URL('../../third_party/patches/jsbsim/event-aware-constant-power-v1/identity.json', import.meta.url));
  const inventoryBytes = await readFile(new URL('../../tools/export/jsbsim/upstream-file-inventory.json', import.meta.url));
  const identity = JSON.parse(identityBytes);
  for (const change of [value => value.schema_version = 2, value => value.vendor_files = 278,
    value => value.source_variant = 'unknown', value => value.recipe_sha256 = 'invalid',
    value => value.extra = true, value => value.source_archive_bytes = 0]) {
    const changed = structuredClone(identity); change(changed);
    assert.throws(() => backendIdentities(Buffer.from(JSON.stringify(changed)), inventoryBytes));
  }
  const changedInventory = Buffer.from(inventoryBytes); changedInventory[20] ^= 1;
  assert.throws(() => backendIdentities(identityBytes, changedInventory));
});

test('synthetic schema3 metadata uses its separate public identity and closed four-file verification', async t => {
  const root = await mkdtemp(join(tmpdir(), 'flight-schema3-fingerprint-'));
  t.after(() => rm(root, { recursive: true, force: true }));
  const inventoryBytes = await readFile(new URL('../../tools/export/jsbsim/upstream-file-inventory.json', import.meta.url));
  const oldBytes = await readFile(new URL('../../third_party/patches/jsbsim/event-aware-constant-power-v1/identity.json', import.meta.url));
  // Synthetic metadata tests the transport route only; it is not a qualified
  // source bundle, production identity, actual DLL or numerical-method result.
  const identity = JSON.parse(oldBytes);
  identity.source_variant = 'jsbsim-1.3.1-event-aware-coupled-midpoint-v1';
  identity.bundle_files = 293;
  identity.modified_vendor_files = 4;
  identity.changes = [...identity.changes, ...identity.changes.map(row => ({ ...row }))];
  const identityBytes = Buffer.from(JSON.stringify(identity) + '\n');
  const accepted = backendIdentities(identityBytes, inventoryBytes);
  assert.equal(accepted.size, 2);
  assert.equal(accepted.get('jsbsim-1.3.1-upstream'), backendIdentities(oldBytes, inventoryBytes).get('jsbsim-1.3.1-upstream'));
  const verification = { schema_version: 3, source_variant: identity.source_variant,
    bundle_files: 293, vendor_files: 279, unchanged_vendor_files: 275,
    modified_vendor_files: 4, provenance_reconstructed: true,
    recipe_sha256: identity.recipe_sha256, vendor_tree_sha256: identity.vendor_tree_sha256,
    materializer_sha256: identity.materializer_sha256 };
  const declaration = { schema_version: 1, identity_file_sha256: hash(identityBytes), identity, verification };
  const keys = new Set();
  JSON.stringify(declaration, (key, value) => { if (key) keys.add(key); return value; });
  const expectedBackend = hash(JSON.stringify(declaration, [...keys].sort()));
  assert.equal(accepted.get(identity.source_variant), expectedBackend);
  for (const mutate of [row => row.bundle_files = 291, row => row.modified_vendor_files = 2,
    row => row.changes.pop(), row => row.source_variant = 'jsbsim-1.3.1-event-aware-coupled-midpoint-v2']) {
    const invalid = structuredClone(identity); mutate(invalid);
    assert.throws(() => backendIdentities(Buffer.from(JSON.stringify(invalid)), inventoryBytes));
  }
  const transport = join(root, 'third_party/patches/jsbsim/event-aware-coupled-midpoint-v1');
  await mkdir(transport, { recursive: true });
  await mkdir(join(root, 'tools/export/jsbsim'), { recursive: true });
  await writeFile(join(transport, 'identity.json'), identityBytes);
  await writeFile(join(root, 'tools/export/jsbsim/upstream-file-inventory.json'), inventoryBytes);
  const adapterRoot = join(root, 'adapter');
  await mkdir(join(adapterRoot, 'src'), { recursive: true });
  await mkdir(join(adapterRoot, 'include'), { recursive: true });
  await mkdir(join(root, 'build/bin'), { recursive: true });
  const executable = join(root, 'build/bin/synthetic.exe');
  const manifestPath = join(root, 'build/jsbsim-source-build-manifest.txt');
  await writeFile(manifestPath, manifest(expectedBackend).replace('synthetic-test', identity.source_variant));
  assert.equal(await currentSourceFingerprint(executable, { adapterRoot, repositoryRoot: root }),
    hash(`jsbsim-backend:${expectedBackend}\njsbsim-build-controls:${buildControls}\n`));
  await writeFile(manifestPath, manifest(expectedBackend).replace('synthetic-test', 'jsbsim-1.3.1-event-aware-coupled-midpoint-v2'));
  await assert.rejects(() => currentSourceFingerprint(executable, { adapterRoot, repositoryRoot: root }));
});
