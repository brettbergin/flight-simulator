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

import {stageAcceptedSourceIdentity} from './package.mjs';
import {createHash} from 'node:crypto';
test('modified preview stages the exact declared baseline source identity and preserves pristine delivery',()=>{
 const temporary=fs.mkdtempSync(path.join(root,'source-identity-'));
 const baseline=path.join(temporary,'baseline'),payload=path.join(temporary,'payload');
 fs.mkdirSync(path.join(baseline,'evidence'),{recursive:true});fs.mkdirSync(payload);
 const entry=JSON.parse(fs.readFileSync(path.join(repo,'third_party/licenses/register.json'),'utf8')).entries.find(item=>item.id==='jsbsim-coupled-midpoint-v1');
 const pin=entry.library_policy.source_identity,file='evidence/jsbsim-coupled-source-identity.json';
 const raw=fs.readFileSync(path.join(repo,pin.path));
 const selection={modified:true,component_id:entry.id,source_variant:'jsbsim-1.3.1-event-aware-coupled-midpoint-v1',source_identity:pin};
 const accepted={id:entry.id,modified:true,source_variant:selection.source_variant,source_identity:file,files:[{path:file,role:'evidence',sha256:pin.sha256}]};
 fs.writeFileSync(path.join(baseline,file),raw);
 assert.equal(stageAcceptedSourceIdentity(payload,baseline,accepted,selection),file);
 assert.deepEqual(fs.readFileSync(path.join(payload,file)),raw);
 assert.equal(createHash('sha256').update(fs.readFileSync(path.join(payload,file))).digest('hex'),accepted.files[0].sha256);
 for(const mutate of [c=>{c.files=[];},c=>{c.files.push({...c.files[0]});},c=>{c.files[0].role='source';},c=>{c.files[0].sha256='a'.repeat(64);},c=>{c.source_identity='../outside.json';}]){
  const bad=structuredClone(accepted);mutate(bad);assert.throws(()=>stageAcceptedSourceIdentity(payload,baseline,bad,selection));
 }
 fs.appendFileSync(path.join(baseline,file),'\n');assert.throws(()=>stageAcceptedSourceIdentity(payload,baseline,accepted,selection),/Accepted source identity bytes differ/);
 fs.unlinkSync(path.join(baseline,file));assert.throws(()=>stageAcceptedSourceIdentity(payload,baseline,accepted,selection));
 fs.writeFileSync(path.join(baseline,file),raw);fs.appendFileSync(path.join(payload,file),'\n');
 assert.throws(()=>stageAcceptedSourceIdentity(payload,baseline,accepted,selection),/Existing staged source identity differs/);
 const pristine=path.join(temporary,'pristine');fs.mkdirSync(pristine);
 assert.equal(stageAcceptedSourceIdentity(pristine,baseline,{}, {modified:false}),null);
 assert.deepEqual(fs.readdirSync(pristine),[],'Pristine path stages no modified-library evidence');
});

// Pure source/receipt admission: no Godot/compiler/native or GPU execution.
import {groundMaterialIdentity,validateGroundMaterialReceipt,validateGroundMaterialSources} from './package.mjs';
test('ground material package binds actual resources and all three independent receipts',()=>{
 const temporary=fs.mkdtempSync(path.join(root,'ground-'));
 const authored=path.join(temporary,'repo'),project=path.join(temporary,'project'),source=path.join(temporary,'source');
 const mapping={'app/proof/interactive/flight_world.gd':'interactive/flight_world.gd','tests/world/ground-materials/checks.gd':'ground_material_tests/checks.gd','content/aircraft/prototype/ground-presentation.json':'content/aircraft/prototype/ground-presentation.json'};
 for(const [name,mapped] of Object.entries(mapping)){
  const bytes=fs.readFileSync(path.join(repo,name));
  for(const [base,relative] of [[authored,name],[project,mapped],[source,mapped]]){const file=path.join(base,relative);fs.mkdirSync(path.dirname(file),{recursive:true});fs.writeFileSync(file,bytes);}
 }
 const expected=validateGroundMaterialSources(authored,project,source);
 assert.deepEqual(expected,groundMaterialIdentity(authored));
 const good={result:{passed:true,checks:371,failures:[],scope:'Synthetic admission only; not GPU evidence'},...expected};
 assert.equal(validateGroundMaterialReceipt(good,expected),371);
 for(const mutate of [r=>{r.result.checks=0;},r=>{r.result.checks=370;},r=>{r.result.checks='371';},r=>{r.result.passed=false;},r=>{r.result.failures=['failed'];},r=>{r.result.extra=true;},r=>{r.extra=true;},r=>{delete r.source_files['tests/world/ground-materials/checks.gd'];},r=>{r.source_files['app/proof/interactive/flight_world.gd'].sha256='a'.repeat(64);},r=>{r.source_files['content/aircraft/prototype/ground-presentation.json'].bytes++;},r=>{r.shader_code_utf8_sha256='b'.repeat(64);}]){
  const bad=structuredClone(good);mutate(bad);assert.throws(()=>validateGroundMaterialReceipt(bad,expected));
 }
 for(const [name,mapped] of Object.entries(mapping)){
  for(const base of [project,source]){const file=path.join(base,mapped),old=fs.readFileSync(file);fs.appendFileSync(file,'\n');assert.throws(()=>validateGroundMaterialSources(authored,project,source));fs.writeFileSync(file,old);}
 }
 const uid=path.join(project,'ground_material_tests/checks.gd.uid');fs.writeFileSync(uid,'uid://groundfixture\n');
 assert.doesNotThrow(()=>validateGroundMaterialSources(authored,project,source));fs.writeFileSync(uid,'invalid');assert.throws(()=>validateGroundMaterialSources(authored,project,source));fs.unlinkSync(uid);
 for(const [base,folder] of [[authored,'tests/world/ground-materials'],[project,'ground_material_tests'],[source,'ground_material_tests']]){
  const extra=path.join(base,folder,'extra.gd');fs.writeFileSync(extra,'extends Node');assert.throws(()=>validateGroundMaterialSources(authored,project,source));fs.unlinkSync(extra);
 }
 const check=path.join(project,'ground_material_tests/checks.gd'),saved=fs.readFileSync(check);fs.unlinkSync(check);assert.throws(()=>validateGroundMaterialSources(authored,project,source));fs.writeFileSync(check,saved);
 const folder=path.join(source,'ground_material_tests'),outside=path.join(temporary,'outside');fs.renameSync(folder,outside);fs.symlinkSync(outside,folder,process.platform==='win32'?'junction':'dir');
 assert.throws(()=>validateGroundMaterialSources(authored,project,source),/link/);
});

import {validatePointerSummary,validatePointerFlight,pointerSourcePaths} from './package.mjs';
const pointerLimitsPin='9b667d4b61e47e94af1eed20701119bd72d6de63e6eac28b8597ab44ae6d9feb';
function syntheticPointerSummary(){
 const basic=()=>({passed:true,checks:2,failures:[],scope:'Synthetic closed receipt admission only'});
 return {schema:'PointerEngineChecks/v1',passed:true,checks:8,failures:[],scope:'Synthetic closed receipt admission only',source_files:{fixture:{bytes:1,sha256:'a'.repeat(64)}},native_identity:{schema:'PreviewNativeResource/v1',path:'build/native_identity.gd',bytes:3,sha256:'b'.repeat(64)},groups:{mapper:basic(),panel:basic(),host:{...basic(),physical_capture_observed:false,display_backend:'headless'},flight:{...basic(),rows:13321,initialized:true,native_joined:true,audio_joined:true,limits_sha256:pointerLimitsPin,first_running_tick:10,first_stopped_tick:5000,trace:{path:'pointer-flight-trace.json',bytes:100,sha256:'c'.repeat(64)}}}};
}
test('pointer summary requires four real groups exact counts source identity and bounded external trace',()=>{
 const expected=syntheticPointerSummary(),resource={bytes:3,sha256:'b'.repeat(64)};
 assert.equal(validatePointerSummary(expected,expected.source_files,resource),8);
 const bads=[
  r=>delete r.groups.mapper,r=>delete r.groups.panel,r=>delete r.groups.host,r=>delete r.groups.flight,
  r=>r.groups.host.physical_capture_observed=true,r=>r.groups.host.display_backend='',
  r=>r.groups.flight.rows=13320,r=>r.groups.flight.native_joined=false,r=>r.groups.flight.audio_joined=false,
  r=>r.groups.flight.initialized=false,r=>r.groups.flight.limits_sha256='d'.repeat(64),
  r=>r.groups.flight.trace.path='../pointer-flight-trace.json',r=>r.groups.flight.trace.bytes=0,
  r=>r.groups.flight.trace.bytes=129*1024*1024,r=>r.groups.flight.trace.sha256='unbound',
  r=>r.checks+=1,r=>r.groups.mapper.checks=0,r=>r.groups.panel.passed=false,
  r=>r.source_files.fixture.sha256='e'.repeat(64),r=>delete r.source_files.fixture,
  r=>r.native_identity.sha256='f'.repeat(64),r=>r.groups.flight.rows_embedded=[],r=>r.extra=true,
 ];
 for(const mutate of bads){const receipt=structuredClone(expected);mutate(receipt);assert.throws(()=>validatePointerSummary(receipt,expected.source_files,resource));}
});
test('pointer full trace cannot be replaced by passing labels or missing native rows',()=>{
 const summary=syntheticPointerSummary().groups.flight;
 const trace={schema:'PointerEngineFlight/v1',passed:true,checks:2,failures:[],scene_failures:[],initialized:true,limits_sha256:pointerLimitsPin,initial_readback:{},first_running_tick:10,first_stopped_tick:5000,gestures:[],lever_values:[],denied:[],rows:[],native_joined:true,audio_joined:true,scope:summary.scope};
 assert.throws(()=>validatePointerFlight(trace,summary,{},'a'.repeat(64)));
 const extra=structuredClone(trace);extra.driver_failures=[];assert.throws(()=>validatePointerFlight(extra,summary,{},'a'.repeat(64)));
 assert.equal(pointerSourcePaths['tests/integration/input/pointer_visual.gd'],'pointer_scene_tests/pointer_visual.gd');
 assert.equal(pointerSourcePaths['tests/engine/native-limits.json'],'pointer_scene_tests/native-limits.json');
 assert.equal(pointerSourcePaths['generated/pointer_checks.gd'],'pointer_checks.gd');
});
