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


// Pure fixed-policy model and receipt admission; no engine or Godot execution.
import {validatePistonModelTree,validatePistonReceipt} from './package.mjs';
test('piston delivery binds exactly seven ordinary model and provenance files',()=>{
 const temporary=fs.mkdtempSync(path.join(root,'piston-'));
 const source=path.join(temporary,'source');fs.cpSync(path.join(repo,'native/fdm_jsbsim/models/original-piston-prop'),source,{recursive:true});
 assert.equal(validatePistonModelTree(source).length,7);
 const ledger=path.join(source,'parameter-ledger.json'),old=fs.readFileSync(ledger);fs.appendFileSync(ledger,'\n');
 assert.throws(()=>validatePistonModelTree(source));fs.writeFileSync(ledger,old);
 const extra=path.join(source,'extra.xml');fs.writeFileSync(extra,'<extra/>');assert.throws(()=>validatePistonModelTree(source));fs.unlinkSync(extra);
 const inventory=path.join(source,'inventory.json'),oldInventory=fs.readFileSync(inventory);fs.writeFileSync(inventory,'{}\n');
 assert.throws(()=>validatePistonModelTree(source),/Frozen piston inventory changed/);fs.writeFileSync(inventory,oldInventory);
 const removed=path.join(source,'NOTICE-MIT.txt'),oldNotice=fs.readFileSync(removed);fs.unlinkSync(removed);assert.throws(()=>validatePistonModelTree(source));fs.writeFileSync(removed,oldNotice);
 // Windows junctions need no file-symlink privilege and remain visible to lstat.
 const engine=path.join(source,'engine'),outside=path.join(temporary,'outside');fs.renameSync(engine,outside);fs.symlinkSync(outside,engine,process.platform==='win32'?'junction':'dir');
 assert.throws(()=>validatePistonModelTree(source),/link/);
});
function coldReceipt(){
 const groups=Object.fromEntries(['bridge','facade','pacing','input','panel','status','wind'].map(name=>[name,{passed:true,checks:3,failures:[],result:{passed:true,checks:2,failures:[]}}]));
 groups.pacing.result.native_profiles=['30','60','144','240','jitter'].flatMap(cadence=>['1/4','1/2','1','2','4'].map(scale=>({cadence,scale,completed_profile:true,final_tick:'120',final_debt_quanta:0})));
 groups.scene={passed:true,checks:2,failures:[],result:{initialized:true,cold_initial_tick:'0',cold_reset_tick:'0'}};
 return {schema:'PistonFlightChecks/v1',passed:true,checks:23,failures:[],scope:'Synthetic package receipt admission',groups};
}
test('cold package receipt requires actual counts all eight groups and twenty-five pacing completions',()=>{
 assert.doesNotThrow(()=>validatePistonReceipt(coldReceipt()));
 const mutations=[
  r=>{delete r.groups.wind;},r=>{r.extra=true;},r=>{r.checks++;},r=>{r.groups.bridge.result.checks=0;},
  r=>{r.groups.input.result.passed=false;},r=>{r.groups.panel.result=[];},r=>{r.groups.status.failures=['actual_failure'];},
  r=>{r.groups.pacing.result.native_profiles.pop();},r=>{r.groups.pacing.result.native_profiles[1]=r.groups.pacing.result.native_profiles[0];},
  r=>{r.groups.pacing.result.native_profiles[0].completed_profile=false;},r=>{r.groups.pacing.result.native_profiles[0].final_tick=120;},
  r=>{r.groups.pacing.result.native_profiles[0].final_debt_quanta='0';},r=>{r.groups.scene.result.initialized=false;},
  r=>{r.groups.scene.result.cold_initial_tick=0;},r=>{r.groups.scene.result.cold_reset_tick='1';},r=>{r.scope='x'.repeat(1025);},
 ];
 for(const mutate of mutations){const bad=coldReceipt();mutate(bad);assert.throws(()=>validatePistonReceipt(bad));}
});

test('standalone piston validator rejects coherent register-policy identity drift',()=>{
 const entry=JSON.parse(fs.readFileSync(path.join(repo,'third_party/licenses/register.json'),'utf8')).entries.find(item=>item.id==='original-piston-prop-v1');
 const source=path.join(repo,entry.content_policy.root);assert.doesNotThrow(()=>validatePistonModelTree(source,entry));
 for(const mutate of [e=>{e.content_policy.inventory_sha256='a'.repeat(64);e.source.revision='sha256:'+'a'.repeat(64);},e=>{e.content_policy.root='native/another-model';},e=>{e.content_policy.inventory_path='native/another-model/inventory.json';},e=>{e.id='another-model';},e=>{e.version='0.2.0';}]){
  const changed=structuredClone(entry);mutate(changed);assert.throws(()=>validatePistonModelTree(source,changed));
 }
});
