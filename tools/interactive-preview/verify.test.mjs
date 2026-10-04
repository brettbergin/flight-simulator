import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import {spawnSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';
const repo=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'../..');
const root=path.join(repo,'.local/interactive-preview/model-negatives');fs.mkdirSync(root,{recursive:true});
const run=(source,destination)=>spawnSync(process.execPath,[path.join(repo,'tools/interactive-preview/package.mjs'),'models',source,destination],{encoding:'utf8'});
test('runtime model staging pins actual bytes and rejects altered XML/inventory',()=>{
 const temporary=fs.mkdtempSync(path.join(root,'case-'));
 const source=path.join(temporary,'source');fs.cpSync(path.join(repo,'native/fdm_jsbsim/models/original-interactive'),source,{recursive:true});
 assert.equal(run(source,path.join(temporary,'valid')).status,0);
 const xml=path.join(source,'aircraft/original-interactive/original-interactive.xml');fs.appendFileSync(xml,'\n<!-- unauthorized performance change -->');
 const bad=run(source,path.join(temporary,'changed'));assert.notEqual(bad.status,0);assert.match(bad.stderr,/AssertionError/);
 fs.writeFileSync(path.join(source,'inventory.json'),'{}\n');
 const inventory=run(source,path.join(temporary,'inventory'));assert.notEqual(inventory.status,0);assert.match(inventory.stderr,/Frozen model inventory changed/);
});
