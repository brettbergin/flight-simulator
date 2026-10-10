import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import assert from 'node:assert/strict';
import { fileURLToPath } from 'node:url';
import { spawnSync } from 'node:child_process';
import { auditRegister, auditRelease, auditDependencyLock, sha256 } from './audit.mjs';
import { COUPLED_ID, COUPLED_VARIANT, auditCoupledIdentity } from './modified-jsbsim.mjs';

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
  // Closed modified-source admission. These fixtures do not claim authentic
  // DLL/replacement success: archive bytes below are deliberately TEST ONLY.
  const coupledEntry = register.entries.find(e => e.id === COUPLED_ID);
  const coupledIdentity = JSON.parse(fs.readFileSync(path.join(repoRoot,coupledEntry.library_policy.source_identity.path),'utf8'));
  check('renewed closed schema3 source identity', () => assert.deepEqual(auditCoupledIdentity(coupledIdentity), []));
  for (const [name,mutate] of [
    ['unknown identity key',x=>x.unreviewed=true],
    ['boolean identity schema',x=>x.schema_version=true],
    ['schema2 file count',x=>x.bundle_files=289],
    ['vendor count drift',x=>x.vendor_files=278],
    ['modified roster omission',x=>x.changes.pop()],
    ['modified roster reordered',x=>x.changes.reverse()],
    ['unexpected changed source',x=>x.changes[0].path='src/FGFDMExec.cpp'],
    ['unsafe source member',x=>x.changes[0].after.member='../FGPiston.cpp'],
    ['before-image digest drift',x=>x.changes[0].before.sha256='0'.repeat(64)],
    ['undated old piston after-image',x=>x.changes[0].after.sha256='80f51ec8f702cf0b484ac076272e3440f59ddd4ae2ac10dbcc503e5377357232'],
    ['archive byte count drift',x=>x.source_archive_bytes--],
    ['unknown recipe digest',x=>x.recipe_sha256='0'.repeat(64)],
    ['unknown materializer digest',x=>x.materializer_sha256='0'.repeat(64)],
    ['unknown inventory digest',x=>x.upstream_inventory_sha256='0'.repeat(64)],
    ['wrong acquisition',x=>x.acquisition_sha256='0'.repeat(64)]])
    check(name,()=>{const x=clone(coupledIdentity);mutate(x);has(auditCoupledIdentity(x),'closed schema3');});
  const changeCoupled=(r,fn)=>fn(r.entries.find(e=>e.id===COUPLED_ID));
  inventoryMutation('reserved ID cannot fall back without policy',r=>changeCoupled(r,e=>delete e.library_policy.release_policy),'reserved modified release');
  inventoryMutation('unknown modified policy fails closed',r=>changeCoupled(r,e=>e.library_policy.release_policy='another-policy'),'unknown or misplaced release');
  inventoryMutation('pristine ID cannot borrow modified policy',r=>r.entries[0].library_policy.release_policy=COUPLED_ID,'unknown or misplaced release');
  inventoryMutation('reviewed identity path cannot traverse',r=>changeCoupled(r,e=>e.library_policy.source_identity.path='../identity.json'),'reserved modified release');
  inventoryMutation('self-declared identity hash is insufficient',r=>changeCoupled(r,e=>e.library_policy.source_identity.sha256='0'.repeat(64)),'reserved modified release');
  inventoryMutation('historical numerical archive is not release source',r=>changeCoupled(r,e=>e.library_policy.source_archive_sha256='9b1b9c5bf5da4dd6514c590570486c3920915ea80fcf3a29713f5bac137d3492'),'reserved modified release');
  inventoryMutation('modification policy cannot omit retained grants',r=>changeCoupled(r,e=>e.library_policy.modification_policy='Changed source'),'reserved modified release');
  inventoryMutation('vendor changes cannot be relicensed MIT',r=>changeCoupled(r,e=>e.license='MIT'),'reserved modified release');
  inventoryMutation('dated notice cannot be omitted',r=>changeCoupled(r,e=>e.notice_files.pop()),'dated modification notices');
  check('modified source review needs repository root',()=>has(auditRegister(register),'repository root required'));

  // Separate payload so the original unmodified fixtures and dependency-lock
  // checks remain independent. Stage exact real identity/notice/BUILD bytes;
  // the fake archive must still fail its real pinned digest, never get blessed.
  const modifiedRoot=path.join(tempRoot,'modified-payload');fs.mkdirSync(modifiedRoot);
  const stage=(relative,bytes,role)=>{const full=path.join(modifiedRoot,relative);fs.mkdirSync(path.dirname(full),{recursive:true});fs.writeFileSync(full,bytes);return {path:relative,sha256:sha256(bytes),role};};
  const modSource=stage('source/fixture.zip',Buffer.from('TEST ONLY: not the reviewed corresponding-source archive'),'source');
  const modFiles=[modSource,stage('bin/JSBSim.dll',Buffer.from('TEST ONLY DLL'),'binary'),
    stage('source/BUILD.md',fs.readFileSync(path.join(repoRoot,'tools/export/jsbsim-coupled-midpoint/BUILD.md')),'build-instructions'),
    stage('evidence/replacement.json',Buffer.from('{"test_only":true}'),'evidence'),
    stage('evidence/source-identity.json',fs.readFileSync(path.join(repoRoot,coupledEntry.library_policy.source_identity.path)),'evidence')];
  const modNotices=coupledEntry.notice_files.map((n,i)=>{const relative=`notices/${i}.txt`;modFiles.push(stage(relative,fs.readFileSync(path.join(repoRoot,n.path)),'notice'));return {register_path:n.path,package_path:relative};});
  const modComponent={id:COUPLED_ID,version:'1.3.1',source_revision:coupledEntry.source.revision,files:modFiles,notices:modNotices,
    source_archive:modSource.path,build_instructions:'source/BUILD.md',shared_library:'bin/JSBSim.dll',replacement_test:'evidence/replacement.json',
    linkage:'dynamic',reverse_engineering_permitted:true,modified:true,source_variant:COUPLED_VARIANT,
    source_identity:'evidence/source-identity.json',modification_notice:modNotices[3].package_path};
  const modManifest={schema_version:1,components:[modComponent]};
  const modAudit=m=>auditRelease(register,m,{repoRoot,packageRoot:modifiedRoot});
  check('synthetic archive never qualifies closed modified release',()=>{
    const errors=modAudit(modManifest);assert.equal(errors.length,2,errors.join('\n'));
    has(errors,'exact corresponding-source archive');has(errors,'archive: SHA-256 mismatch');
  });
  const modMutation=(name,mutate,phrase)=>check(name,()=>{const copy=clone(modManifest);mutate(copy.components[0],copy);has(modAudit(copy),phrase);});
  modMutation('modified release cannot assert pristine',c=>c.modified=false,'modified:true');
  modMutation('modified release variant must match',c=>c.source_variant='jsbsim-1.3.1-event-aware-angular-v1','exact source variant');
  modMutation('identity evidence required',c=>delete c.source_identity,'staged source identity');
  modMutation('identity evidence cannot be notice',c=>c.files.find(f=>f.path===c.source_identity).role='notice','staged source identity');
  modMutation('identity hash cannot be substituted',c=>c.files.find(f=>f.path===c.source_identity).sha256='0'.repeat(64),'staged source identity');
  modMutation('dated notice cannot refer to upstream COPYING',c=>c.modification_notice=modNotices[0].package_path,'dated modification notice mapping');
  modMutation('schema3 build instructions cannot be arbitrary',c=>c.files.find(f=>f.path===c.build_instructions).sha256='0'.repeat(64),'schema3 build/replacement');
  modMutation('modified dynamic replacement gate retained',c=>delete c.replacement_test,'replacement test');
  modMutation('modified reverse engineering gate retained',c=>c.reverse_engineering_permitted=false,'permission not recorded');
  modMutation('pristine and modified declarations cannot coexist',(c,m)=>{const p=clone(c);p.id='jsbsim';p.modified=false;m.components.push(p);},'cannot coexist');
  check('raw staged identity tampering rejected',()=>{
    const target=path.join(modifiedRoot,modComponent.source_identity);const original=fs.readFileSync(target);
    try {fs.appendFileSync(target,' ');has(modAudit(modManifest),'SHA-256 mismatch');}
    finally {fs.writeFileSync(target,original);}
  });
  check('changed date in staged modification notice rejected',()=>{
    const target=path.join(modifiedRoot,modComponent.modification_notice);const original=fs.readFileSync(target);
    try {fs.writeFileSync(target,original.toString('utf8').replace('2026-10-09','2025-01-01'));has(modAudit(modManifest),'SHA-256 mismatch');}
    finally {fs.writeFileSync(target,original);}
  });
  process.stdout.write(`PASS ${checks} rights audit checks\n`);
} finally {
  // Resolve and verify the single generated subtree before recursive cleanup.
  const resolved = fs.realpathSync(tempRoot);
  if (path.dirname(resolved) !== tempParent || !path.basename(resolved).startsWith('flight-license-test-')) throw new Error('unsafe test cleanup target');
  fs.rmSync(resolved, { recursive: true, force: true });
}
