import test from 'node:test';
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { mkdtemp, mkdir, readFile, writeFile, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { dirname, join } from 'node:path';
import { backendIdentities } from '../../tools/run-scenario/source-fingerprint.mjs';
import { currentInteractiveIdentity, interactiveSources } from './source-fingerprint.mjs';

const sha = raw => createHash('sha256').update(raw).digest('hex');
async function fixture(t) {
  const root = await mkdtemp(join(tmpdir(), 'flight-interactive-identity-'));
  t.after(() => rm(root, { recursive: true, force: true }));
  const repositoryRoot = join(root, 'repo'), executable = join(root, 'custom-build/bin/interactive_tests');
  const build = dirname(dirname(executable));
  const put = async (name, raw) => { const path = join(repositoryRoot, name); await mkdir(dirname(path), { recursive: true }); await writeFile(path, raw); };
  for (const path of interactiveSources) await put(path, `synthetic ${path}\r\n`);
  await put('native/fdm_jsbsim/interactive/CMakeLists.txt', 'set(INTERACTIVE_SOURCE_PATHS\n'+interactiveSources.join('\n')+')\n');
  const inventory = await readFile(new URL('../../tools/export/jsbsim/upstream-file-inventory.json', import.meta.url));
  await put('tools/export/jsbsim/upstream-file-inventory.json', inventory);
  const accepted = new Map();
  for (const transport of ['event-aware-constant-power-v1', 'event-aware-coupled-midpoint-v1']) {
    const raw = await readFile(new URL(`../../third_party/patches/jsbsim/${transport}/identity.json`, import.meta.url));
    await put(`third_party/patches/jsbsim/${transport}/identity.json`, raw);
    for (const row of backendIdentities(raw, inventory)) accepted.set(...row);
  }
  await mkdir(build, { recursive: true });
  async function declare(variant, controls = 'b'.repeat(64), backend = accepted.get(variant)) {
    const manifest = `Source variant: ${variant}\nBackend identity SHA256: ${backend}\nBuild controls SHA256: ${controls}\n`;
    await writeFile(join(build, 'jsbsim-source-build-manifest.txt'), manifest);
    const sources = [];
    for (const path of interactiveSources) sources.push(`${path}:${sha((await readFile(join(repositoryRoot,path),'utf8')).replaceAll('\r\n','\n'))}\n`);
    const body = `verified-jsbsim-backend:${backend}\njsbsim-build-controls:${controls}\n`+sources.join('');
    const fingerprint = sha(body);
    await writeFile(join(build, 'interactive-source-fingerprint.txt'), fingerprint+'\n'+body);
    return { fingerprint, files: sources.join(''), oldSix: sources.slice(0,6).join('') };
  }
  return { repositoryRoot, executable, build, accepted, declare, put };
}

test('interactive identity reproduces all three reviewed routes with ordered LF inputs and both prefixes', async t => {
  const f = await fixture(t);
  assert.equal(f.accepted.size,3);
  for (const variant of f.accepted.keys()) {
    const expected = await f.declare(variant);
    const actual = await currentInteractiveIdentity(f.executable,f);
    assert.equal(actual.fingerprint,expected.fingerprint);
    assert.equal(actual.sources.length,15);
    assert.notEqual(actual.fingerprint,sha(expected.oldSix),'historical six-input/no-prefix identity must fail');
    assert.notEqual(actual.fingerprint,sha(expected.files),'even fifteen inputs cannot omit provenance prefixes');
  }
});

test('LF normalization is retained while every late source and build control remains bound', async t => {
  const f = await fixture(t), variant = 'jsbsim-1.3.1-upstream';
  await f.declare(variant);
  const original = await currentInteractiveIdentity(f.executable,f);
  const path = join(f.repositoryRoot,interactiveSources.at(-1));
  await writeFile(path,(await readFile(path,'utf8')).replaceAll('\r\n','\n'));
  assert.deepEqual(await currentInteractiveIdentity(f.executable,f),original);
  await writeFile(path,'changed last source\n');
  await assert.rejects(()=>currentInteractiveIdentity(f.executable,f),/stale or noncanonical/);
  await f.declare(variant);
  assert.notEqual((await currentInteractiveIdentity(f.executable,f)).fingerprint,original.fingerprint);
  await f.declare(variant,'d'.repeat(64));
  assert.notEqual((await currentInteractiveIdentity(f.executable,f)).build_control_sha256,original.build_control_sha256);
});

test('unknown backend, changed closed roster and malformed/stale manifest fail closed', async t => {
  const f = await fixture(t), variant = 'jsbsim-1.3.1-upstream';
  await f.declare(variant,'b'.repeat(64),'c'.repeat(64));
  await assert.rejects(()=>currentInteractiveIdentity(f.executable,f),/unknown or stale/);
  await f.declare('jsbsim-unknown','b'.repeat(64),'c'.repeat(64));
  await assert.rejects(()=>currentInteractiveIdentity(f.executable,f),/unknown or stale/);
  await f.declare(variant);
  const cmake=join(f.repositoryRoot,'native/fdm_jsbsim/interactive/CMakeLists.txt');
  const saved=await readFile(cmake);
  await writeFile(cmake,saved.toString().replace(interactiveSources.at(-1),'tests/engine/unreviewed.json'));
  await assert.rejects(()=>currentInteractiveIdentity(f.executable,f),/source roster/);
  await writeFile(cmake,Buffer.concat([saved,saved]));
  await assert.rejects(()=>currentInteractiveIdentity(f.executable,f),/source roster/);
  await writeFile(cmake,saved);
  await writeFile(join(f.build,'interactive-source-fingerprint.txt'),'0'.repeat(64)+'\n');
  await assert.rejects(()=>currentInteractiveIdentity(f.executable,f),/stale or noncanonical/);
  await f.declare(variant);
  await rm(join(f.repositoryRoot,interactiveSources.at(-1)));
  await assert.rejects(()=>currentInteractiveIdentity(f.executable,f),/ENOENT/);
  await assert.rejects(()=>currentInteractiveIdentity('',f),/explicit interactive executable/);
});

test('Windows CRLF metadata preserves canonical identity and rejects a changed digest', async t => {
  const f = await fixture(t), variant = 'jsbsim-1.3.1-upstream';
  await f.declare(variant);
  const original = await currentInteractiveIdentity(f.executable,f);
  const metadata = join(f.build,'interactive-source-fingerprint.txt');
  const lf = await readFile(metadata,'utf8');
  await writeFile(metadata,lf.replaceAll('\n','\r\n'));
  assert.deepEqual(await currentInteractiveIdentity(f.executable,f),original,'only text metadata line endings normalize');
  const manifest = join(f.build,'jsbsim-source-build-manifest.txt');
  await writeFile(manifest,(await readFile(manifest,'utf8')).replaceAll('\n','\r\n'));
  const windows = await currentInteractiveIdentity(f.executable,f);
  assert.equal(windows.fingerprint,original.fingerprint);
  assert.deepEqual(windows.sources,original.sources);
  assert.notEqual(windows.build_manifest_sha256,original.build_manifest_sha256,'raw manifest witness remains exact');
  const corrupt = (lf[0]==='0'?'1':'0')+lf.slice(1);
  await writeFile(metadata,corrupt.replaceAll('\n','\r\n'));
  await assert.rejects(()=>currentInteractiveIdentity(f.executable,f),/stale or noncanonical/);
});
