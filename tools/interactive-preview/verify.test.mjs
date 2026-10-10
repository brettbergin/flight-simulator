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

// Pure package validator fixtures; no compiler/native/Godot execution.
import {validateResourceReceipt} from './package.mjs';
test('export resource receipts bind exact independently expected canonical bytes',()=>{
 const resource={bytes:512,sha256:'a'.repeat(64)};
 const good={schema:'PreviewNativeResource/v1',path:'build/native_identity.gd',bytes:512,sha256:resource.sha256};
 assert.doesNotThrow(()=>validateResourceReceipt(good,resource));
 for(const bad of [{...good,schema:'old'},{...good,path:'../outside'},{...good,bytes:true},{...good,bytes:511},{...good,sha256:'b'.repeat(64)},{...good,extra:true}])assert.throws(()=>validateResourceReceipt(bad,resource));
 for(const key of Object.keys(good)){const bad={...good};delete bad[key];assert.throws(()=>validateResourceReceipt(bad,resource));}
});
