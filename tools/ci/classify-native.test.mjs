import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import {spawnSync} from 'node:child_process';
import {test} from 'node:test';
import {allowedPath, classifyRaw, classifyContext} from './classify-native.mjs';
const hash = '1'.repeat(40);
const record = (name, status = 'M', old = '100644', next = '100644') => Buffer.from(`:${old} ${next} ${hash} ${hash} ${status}\0${name}\0`);
test('exact documentation allowlist accepts nested ADR/evidence prose and closed backlog', () => {
  for (const name of ['docs/README.md', 'docs/decisions/ADR-010.md', 'docs/evidence/P0/acceptance.md', 'docs/backlog.json', 'README.md', 'AGENTS.md', 'CONTRIBUTING.md', 'SECURITY.md']) assert.equal(allowedPath(name), true, name);
});
test('all runtime/workflow/license/data/tool/test paths force full proof', () => {
  for (const name of ['native/a.md', 'app/a.md', 'tools/a.md', 'tests/a.md', 'schemas/a.md', '.github/workflows/native-ci.yml', 'LICENSE', 'third_party/licenses/register.json', 'assets/a.md', 'docs/backlog.JSON', 'docs/runtime.json', 'docs/a.gd', 'readme.md', 'docs/a.MD', 'docs-a.md']) assert.equal(classifyRaw(record(name)).docs_only, false, name);
});
test('path normalization tricks and undecodable names do not become allowed', () => {
  for (const name of ['/docs/a.md', 'docs//a.md', 'docs/../a.md', 'docs/./a.md', 'docs\\a.md', 'docs/a.md\napp/a.gd', 'docs/a.md\0', 'docs/ÃƒÂ©.md']) assert.equal(allowedPath(name), false, name);
  assert.throws(() => classifyRaw(Buffer.from([0xff, 0])));
});
test('deletion, rename, type, executable and symlink transitions force full proof', () => {
  for (const item of [record('docs/a.md', 'D', '100644', '000000'), record('docs/a.md', 'R100'), record('docs/a.md', 'T', '120000'), record('docs/a.md', 'M', '100755'), record('docs/a.md', 'M', '100644', '100755'), record('docs/a.md', 'A', '000000', '120000')]) assert.equal(classifyRaw(item).docs_only, false);
  const renamed = Buffer.concat([record('docs/old.md','D','100644','000000'),record('docs/new.md','A','000000')]);
  assert.equal(classifyRaw(renamed).docs_only, false);
});
test('empty, malformed, and mixed paths cannot skip runtime proof', () => {
  assert.equal(classifyRaw(Buffer.from('')).docs_only, false);
  assert.throws(() => classifyRaw(Buffer.from('invalid')));
  assert.throws(() => classifyRaw(Buffer.from('\0')));
  assert.equal(classifyRaw(Buffer.concat([record('docs/a.md'),record('app/flight.gd')])).docs_only, false);
});
test('actual immutable Git base/head and merge tree binding; no bare path-list shortcut', () => {
  const repo = fs.mkdtempSync(path.join(os.tmpdir(), 'flight-ci-scope-'));
  const git = (...args) => {
    const r = spawnSync('git', ['-C', repo, ...args], {encoding:'utf8', env:{...process.env,GIT_CONFIG_NOSYSTEM:'1'}});
    assert.equal(r.status, 0, r.stderr); return r.stdout.trim();
  };
  try {
    git('init','--initial-branch=main'); git('config','user.name','Fixture');git('config','user.email','fixture@invalid.example');git('config','commit.gpgsign','false');
    fs.mkdirSync(path.join(repo,'docs'));fs.writeFileSync(path.join(repo,'docs','a.md'),'base\n');git('add','.');git('commit','-m','base');
    const base=git('rev-parse','HEAD');git('checkout','-b','topic');fs.writeFileSync(path.join(repo,'docs','a.md'),'head\n');git('commit','-am','docs');const head=git('rev-parse','HEAD');
    git('checkout','main');git('merge','--no-ff','topic','-m','merge');const checkoutSHA=git('rev-parse','HEAD');
    const ctx={repo,eventName:'pull_request',event:{pull_request:{base:{sha:base,repo:{full_name:'owner/repo'}},head:{sha:head}}},checkoutSHA,repository:'owner/repo'};
    assert.equal(classifyContext(ctx).docs_only,true);
    assert.equal(classifyContext(ctx).runtime_proof_executed,false);
    assert.equal(classifyContext({...ctx,eventName:'push'}).runtime_proof_executed,null);
    for(const eventName of ['push','workflow_dispatch','pull_request_target','unknown']) assert.equal(classifyContext({...ctx,eventName}).docs_only,false);
    assert.equal(classifyContext({...ctx,checkoutSHA:head}).docs_only,false);
    assert.equal(classifyContext({...ctx,repository:'other/repo'}).docs_only,false);
    assert.equal(classifyContext({...ctx,event:{pull_request:{base:{sha:base,repo:{full_name:'owner/repo'}},head:{sha:hash}}}}).docs_only,false);
    fs.writeFileSync(path.join(repo,'docs','a.md'),'uncommitted\n');assert.equal(classifyContext(ctx).docs_only,false);git('checkout','--','docs/a.md');
    // A merge-only runtime addition retains both parents, so parent checks alone are insufficient.
    fs.mkdirSync(path.join(repo,'app'));fs.writeFileSync(path.join(repo,'app','flight.gd'),'bad merge-only code\n');git('add','.');git('commit','--amend','--no-edit');
    assert.equal(classifyContext({...ctx,checkoutSHA:git('rev-parse','HEAD')}).docs_only,false);
  } finally { fs.rmSync(repo,{recursive:true,force:true}); }
});
