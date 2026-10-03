import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import assert from 'node:assert/strict';
import { fileURLToPath } from 'node:url';
import { spawnSync } from 'node:child_process';
import { auditRegister, auditRelease, auditDependencyLock, sha256 } from './audit.mjs';

const repoRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
const register = JSON.parse(fs.readFileSync(path.join(repoRoot, 'third_party/licenses/register.json'), 'utf8'));
const tempParent = fs.realpathSync(os.tmpdir());
const tempRoot = fs.mkdtempSync(path.join(tempParent, 'flight-license-test-'));
const packageRoot = path.join(tempRoot, 'payload');
fs.mkdirSync(packageRoot);
let checks = 0;
const check = (name, action) => { action(); checks++; process.stdout.write(`PASS ${name}\n`); };
const clone = value => structuredClone(value);
const has = (errors, phrase) => assert.ok(errors.some(item => item.includes(phrase)), errors.join('\n'));
const inventoryMutation = (name, mutate, expected) => check(name, () => { const copy = clone(register); mutate(copy); has(auditRegister(copy, { repoRoot }), expected); });
const write = (relative, bytes, role) => {
  const full = path.join(packageRoot, relative);
  fs.mkdirSync(path.dirname(full), { recursive: true });
  fs.writeFileSync(full, bytes);
  return { path: relative, sha256: sha256(bytes), role };
};

try {
  check('actual notice hashes and eight inventory classes', () => assert.deepEqual(auditRegister(register, { repoRoot }), []));
  inventoryMutation('unknown rights state fails closed', r => r.entries[0].redistribution = 'maybe', 'unknown redistribution');
  inventoryMutation('incomplete class inventory', r => r.entries = r.entries.filter(e => e.class !== 'audio-assets'), 'missing audio-assets');
  inventoryMutation('missing owner', r => delete r.entries[0].owner, 'missing owner');
  inventoryMutation('provisional evidence cannot clear runtime', r => r.entries[0].evidence = 'provisional', 'included rights');
  inventoryMutation('unknown obligation', r => r.entries[0].obligations.push('skip-source'), 'unknown obligations');
  inventoryMutation('malformed obligations reject without exception', r => r.entries[0].obligations = {}, 'unknown obligations');
  inventoryMutation('malformed source rejects without exception', r => r.entries[0].source = [], 'incomplete source');
  inventoryMutation('notice tampering detected', r => r.entries[0].notice_files[0].sha256 = '0'.repeat(64), 'SHA-256 mismatch');
  inventoryMutation('traversal notice path rejected', r => r.entries[0].notice_files[0].path = '../secret', 'incomplete or duplicate notice');
  inventoryMutation('excluded reference needs reason', r => delete r.entries.find(e => e.id === 'cessna-172s-poh').blocker, 'requires blocker');
  inventoryMutation('duplicate ID rejected', r => r.entries.push(clone(r.entries[0])), 'duplicate ID');

  // Auditor fixtures are not real source archives, DLLs or aircraft models.
  const fixture = clone(register);
  const source = write('source/library-fixture.zip', Buffer.from('TEST ONLY library-source fixture'), 'source');
  fixture.entries[0].library_policy.source_archive_sha256 = source.sha256;
  const files = [source,
    write('bin/JSBSim.dll', Buffer.from('TEST ONLY DLL fixture'), 'binary'),
    write('source/BUILD.md', Buffer.from('TEST ONLY build and replacement instructions'), 'build-instructions'),
    write('evidence/replacement.json', Buffer.from('{"test_only":true,"replaced":true}'), 'evidence')];
  const notices = fixture.entries[0].notice_files.map((notice, index) => {
    const name = `notices/${index}.txt`;
    files.push(write(name, fs.readFileSync(path.join(repoRoot, notice.path)), 'notice'));
    return { register_path: notice.path, package_path: name };
  });
  const manifest = { schema_version: 1, components: [{ id: 'jsbsim', version: '1.3.1', source_revision: fixture.entries[0].source.revision,
    files, notices, source_archive: source.path, build_instructions: 'source/BUILD.md', shared_library: 'bin/JSBSim.dll',
    replacement_test: 'evidence/replacement.json', linkage: 'dynamic', reverse_engineering_permitted: true, modified: false }] };
  check('complete conditional release fixture', () => assert.deepEqual(auditRelease(fixture, manifest, { repoRoot, packageRoot }), []));
  const releaseMutation = (name, mutate, expected) => check(name, () => {
    const copy = clone(manifest); mutate(copy.components[0], copy);
    has(auditRelease(fixture, copy, { repoRoot, packageRoot }), expected);
  });
  releaseMutation('unregistered component', c => c.id = 'unknown-runtime', 'unregistered release');
  releaseMutation('excluded POH cannot be packaged', c => c.id = 'cessna-172s-poh', 'excluded material');
  releaseMutation('source pin mismatch', c => c.source_revision = 'another-commit', 'version/revision differs');
  releaseMutation('missing notice mapping', c => c.notices.pop(), 'required staged notice');
  releaseMutation('missing corresponding source', c => delete c.source_archive, 'corresponding-source');
  releaseMutation('static link cannot pass dynamic policy', c => c.linkage = 'static', 'replaceable shared-library');
  releaseMutation('missing replacement evidence', c => delete c.replacement_test, 'replacement test');
  releaseMutation('missing reverse engineering permission', c => delete c.reverse_engineering_permitted, 'permission not recorded');
  releaseMutation('modified upstream needs new review', c => c.modified = true, 'modified library');
  releaseMutation('changed payload hash', c => c.files[0].sha256 = '0'.repeat(64), 'SHA-256 mismatch');
  releaseMutation('unsafe payload path', c => c.files[0].path = '../outside', 'invalid file record');
  releaseMutation('duplicate component', (c, m) => m.components.push(clone(c)), 'duplicate release');
  check('unresolved distributable source blocks upstream ZIP', () => has(auditRelease(register, manifest, { repoRoot, packageRoot }), 'corresponding-source'));
  const extra = write('unreviewed-model.xml', Buffer.from('TEST ONLY unreviewed file'), 'content');
  check('undeclared payload rejected', () => has(auditRelease(fixture, manifest, { repoRoot, packageRoot }), 'undeclared file'));
  fs.unlinkSync(path.join(packageRoot, extra.path));
  const lock = { schema_version: 1, sources: fixture.entries.filter(e => ['jsbsim','godot-cpp','sqlite'].includes(e.id)).map(e => ({ id:e.id, license_id:e.id, version:e.version, commit:e.source.revision, sha256:e.source.archive_sha256 })), tools:[{ id:'godot', license_id:'godot', version:'4.7.2-stable' },{id:'build-only-cmake'}] };
  check('dependency pins match review', () => assert.deepEqual(auditDependencyLock(register, lock), []));
  check('dependency version drift', () => { const copy = clone(lock); copy.sources[0].version='1.4'; has(auditDependencyLock(register,copy),'version differs'); });
  check('dependency digest drift', () => { const copy = clone(lock); copy.sources[0].sha256='0'.repeat(64); has(auditDependencyLock(register,copy),'revision/digest differs'); });
  check('dependency rights unknown', () => { const copy = clone(lock); copy.sources[0].license_id='unknown'; has(auditDependencyLock(register,copy),'rights missing'); });
  check('CLI malformed arguments fail', () => {
    const result = spawnSync(process.execPath, [path.join(repoRoot,'tools/license-audit/audit.mjs'),'--release'], { encoding:'utf8' });
    assert.equal(result.status,1); assert.match(result.stderr,/usage:/);
  });
  check('CLI default verifies registry', () => {
    const result = spawnSync(process.execPath, [path.join(repoRoot,'tools/license-audit/audit.mjs')], { encoding:'utf8' });
    assert.equal(result.status,0,result.stderr); assert.match(result.stdout,/PASS rights inventory/);
  });
  process.stdout.write(`PASS ${checks} rights audit checks\n`);
} finally {
  // Resolve and verify the single generated subtree before recursive cleanup.
  const resolved = fs.realpathSync(tempRoot);
  if (path.dirname(resolved) !== tempParent || !path.basename(resolved).startsWith('flight-license-test-')) throw new Error('unsafe test cleanup target');
  fs.rmSync(resolved, { recursive: true, force: true });
}
