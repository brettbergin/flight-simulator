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

// ADR018 synthetic admission fixtures exercise the delivery boundary only;
// they are not lifecycle, simulator, flight, hardware or visual observations.
import {validateFirstFlightReceipt,validateFirstFlightFacadeAdmission,validateFirstFlightSources,firstFlightSourceGroups} from './package.mjs';
const savedFirstFlightSource='5e0abfeae9ffd249f8be3f4410d9903f30736698fcb276bdf72f3630132102e5';
const observedFirstFlightSource='a'.repeat(64); // Synthetic validator fixture, not an observed flight.
function firstFlightReceipt(coupled=true,sourceFingerprint=coupled?savedFirstFlightSource:observedFirstFlightSource){
 const legacy={id:'original-interactive-prototype',version:'0.1.0-prototype',backend_model:'original-interactive'};
 const piston={id:'original-piston-prop-v1',version:'0.1.0-prototype',backend_model:'original-piston-prop'};
 const ready=['ready-flight',legacy,'ground-ready'],airborne=['airborne-orientation',legacy,'airborne-prepared'],cold=['cold-familiarization',piston,'piston-cold-ground'];
 const choices=coupled?[cold,ready,airborne]:[ready,airborne];
 const sources=coupled?['original-interactive-prototype_ground-ready','original-piston-prop-v1_piston-cold-ground']:['original-interactive-prototype_ground-ready','original-interactive-prototype_airborne-prepared'];
 const row=(label,choice)=>({label,model_identity:structuredClone(choice[1]),start:choice[2],tick:'0',pause_attempts:[true],native_calls:3,completed:0});
 const adoptions=sources.flatMap(source=>choices.map(choice=>row('immediate_'+source+'_'+choice[0],choice)));
 adoptions.push(...choices.map(choice=>row('confirmed_'+choice[0],choice)),row('joined_failure_explicit_recovery',ready));
 const basic=()=>({passed:true,checks:3,failures:[],scope:'Synthetic closed admission only; no executed lifecycle, flight or visual qualification'});
 const bindings=basic();bindings.limits=bindings.scope;delete bindings.scope;
 return {briefing:basic(),bindings,geometry:{...basic(),fixture_sha256:'2a4540d99d4500e326a1b1f0673583bd6f8ea99d430b991fcca1130befbbddcc',captured_readback_sha256:'58b1a7b0ec46161357c1268dbaeeaab27f84bbbd4de70def35571fd45ddb67f9',baseline_origin:sourceFingerprint===savedFirstFlightSource?'saved-capture':'observed-native',baseline_source_fingerprint:sourceFingerprint},card:basic(),map:basic(),scene:{...basic(),adoptions,include_piston:coupled,route_scope:coupled?'coupled: all six same/cross-profile choices and three advanced confirmations':'upstream: four legacy start mappings, two advanced confirmations and explicit cold admission rejection; cold runtime is not qualified'}};
}
test('first-flight origin follows exact current source independently of backend coverage',()=>{
 for(const mode of [true,false])for(const source of [savedFirstFlightSource,observedFirstFlightSource]){
  const good=firstFlightReceipt(mode,source);
  assert.equal(validateFirstFlightReceipt(good,mode,source),18);
  assert.throws(()=>validateFirstFlightReceipt(good,mode),'No implicit current source, including coupled');
  for(const change of [
   r=>delete r.geometry.baseline_origin,r=>delete r.geometry.baseline_source_fingerprint,
   r=>r.geometry.baseline_origin=source===savedFirstFlightSource?'observed-native':'saved-capture',
   r=>r.geometry.baseline_origin='observed-upstream',r=>r.geometry.baseline_origin='',r=>r.geometry.baseline_origin=null,
   r=>r.geometry.baseline_source_fingerprint='b'.repeat(64),r=>r.geometry.baseline_source_fingerprint=null,
   r=>r.geometry.baseline_source_fingerprint=source===savedFirstFlightSource?observedFirstFlightSource:savedFirstFlightSource,
  ]){const bad=firstFlightReceipt(mode,source);change(bad);assert.throws(()=>validateFirstFlightReceipt(bad,mode,source));}
  for(const invalid of [null,42,'','A'.repeat(64),'a'.repeat(63),'a'.repeat(65)])assert.throws(()=>validateFirstFlightReceipt(good,mode,invalid));
 }
});
test('mandatory first-flight receipt rejects skipped groups bad counts and unbound source/capture pins',()=>{
 for(const mode of [true,false])assert.equal(validateFirstFlightReceipt(firstFlightReceipt(mode),mode,mode?savedFirstFlightSource:observedFirstFlightSource),18);
 assert.throws(()=>validateFirstFlightReceipt(firstFlightReceipt()));
 for(const name of ['briefing','bindings','geometry','card','map','scene']){
  for(const change of [
   r=>delete r[name],r=>r[name]=null,r=>r[name].passed=false,r=>r[name].passed='true',
   r=>r[name].checks=0,r=>r[name].checks=-1,r=>r[name].checks=1.5,r=>r[name].checks='3',r=>r[name].checks=Number.MAX_SAFE_INTEGER+1,
   r=>r[name].failures=['unexecuted'],r=>r[name].failures=null,r=>r[name].skipped=true,
   r=>{delete r[name].scope;delete r[name].limits;},r=>{r[name].scope='';delete r[name].limits;},
   r=>{r[name].scope=' '.repeat(3);delete r[name].limits;},r=>{r[name].scope='x'.repeat(1025);delete r[name].limits;},
   r=>{r[name].scope='scope';r[name].limits='ambiguous';},
  ]){const bad=firstFlightReceipt();change(bad);assert.throws(()=>validateFirstFlightReceipt(bad,true,savedFirstFlightSource),name);}
 }
 for(const change of [r=>r.extra=true,r=>r.geometry.fixture_sha256='a'.repeat(64),r=>r.geometry.captured_readback_sha256='b'.repeat(64),r=>delete r.geometry.fixture_sha256,r=>delete r.geometry.captured_readback_sha256,r=>r.map.checks=Number.MAX_SAFE_INTEGER]){
  const bad=firstFlightReceipt();change(bad);assert.throws(()=>validateFirstFlightReceipt(bad,true,savedFirstFlightSource));
 }
});
test('first-flight scene binds the selected backend and complete nonduplicated actual start mapping roster',()=>{
 assert.throws(()=>validateFirstFlightReceipt(firstFlightReceipt(false),true,observedFirstFlightSource));
 assert.throws(()=>validateFirstFlightReceipt(firstFlightReceipt(true),false,savedFirstFlightSource));
 const mutations=[
  r=>r.scene.include_piston='true',r=>r.scene.route_scope='coupled: passed',r=>r.scene.adoptions.pop(),
  r=>r.scene.adoptions.push(structuredClone(r.scene.adoptions[0])),r=>r.scene.adoptions[1]=structuredClone(r.scene.adoptions[0]),
  r=>r.scene.adoptions[0].model_identity.version='0.2.0',r=>r.scene.adoptions[0].model_identity.extra=true,
  r=>r.scene.adoptions[0].start='ground-ready',r=>r.scene.adoptions[0].tick=0,r=>r.scene.adoptions[0].tick='1',
  r=>r.scene.adoptions[0].pause_attempts.push(false),r=>r.scene.adoptions[0].pause_attempts=[],r=>r.scene.adoptions[0].pause_attempts=[1],r=>r.scene.adoptions[0].pause_attempts=null,
  r=>r.scene.adoptions[0].native_calls=0,r=>r.scene.adoptions[0].native_calls=3.5,r=>r.scene.adoptions[0].completed=1,
  r=>r.scene.adoptions[0].skipped=true,r=>r.scene.adoptions[0].label='invented-route',
 ];
 for(const mutate of mutations){const bad=firstFlightReceipt();mutate(bad);assert.throws(()=>validateFirstFlightReceipt(bad,true,savedFirstFlightSource));}
 const legacy=firstFlightReceipt(false);legacy.scene.route_scope=firstFlightReceipt(true).scene.route_scope;
 assert.throws(()=>validateFirstFlightReceipt(legacy,false,observedFirstFlightSource),'Upstream cannot claim coupled cold coverage');
});
test('facade closed shape makes first-flight mandatory without dropping previous groups',()=>{
 const keys=['schema_version','scope','passed','checks','failures','facade','origin','participants','wire','scene','input','input_scene','instruments','cockpit','freeflight','observed','observed_archive','wind','audio'];
 const good=Object.fromEntries(keys.map(name=>[name,null]));good.first_flight=firstFlightReceipt();
 good.cockpit={hud_caption:{passed:true,checks:1,failures:[],scope:'Synthetic receipt admission fixture'}};
 good.audio=audioReceipt();
 assert.equal(validateFirstFlightFacadeAdmission(good,true,savedFirstFlightSource),18);
 for(const mode of [true,false])for(const source of [savedFirstFlightSource,observedFirstFlightSource]){
  const coherent=structuredClone(good);coherent.first_flight=firstFlightReceipt(mode,source);
  assert.equal(validateFirstFlightFacadeAdmission(coherent,mode,source),18);
  assert.throws(()=>validateFirstFlightFacadeAdmission(coherent,mode));
 }
 const upstream=structuredClone(good);upstream.first_flight=firstFlightReceipt(false);
 assert.equal(validateFirstFlightFacadeAdmission(upstream,false,observedFirstFlightSource),18);
 assert.throws(()=>validateFirstFlightFacadeAdmission(upstream,false));
 assert.throws(()=>validateFirstFlightFacadeAdmission(upstream,false,'b'.repeat(64)));
 for(const name of [...keys,'first_flight']){const bad=structuredClone(good);delete bad[name];assert.throws(()=>validateFirstFlightFacadeAdmission(bad,true,savedFirstFlightSource));}
 const extra=structuredClone(good);extra.runtime_skip=true;assert.throws(()=>validateFirstFlightFacadeAdmission(extra,true,savedFirstFlightSource));
 for(const mutate of [
  r=>{r.cockpit=null;},r=>{delete r.cockpit.hud_caption;},r=>{r.cockpit.hud_caption=null;},
  r=>{r.cockpit.hud_caption.passed=false;},r=>{r.cockpit.hud_caption.passed='true';},
  r=>{r.cockpit.hud_caption.checks=0;},r=>{r.cockpit.hud_caption.checks=-1;},
  r=>{r.cockpit.hud_caption.checks=1.5;},r=>{r.cockpit.hud_caption.checks='1';},
  r=>{r.cockpit.hud_caption.checks=Number.MAX_SAFE_INTEGER+1;},
  r=>{r.cockpit.hud_caption.failures=['failed'];},r=>{r.cockpit.hud_caption.failures=null;},
  r=>{r.cockpit.hud_caption.scope=' ';},r=>{r.cockpit.hud_caption.scope='x'.repeat(1025);},
  r=>{delete r.cockpit.hud_caption.checks;},r=>{r.cockpit.hud_caption.skipped=true;},
 ]){const bad=structuredClone(good);mutate(bad);assert.throws(()=>validateFirstFlightFacadeAdmission(bad,true,savedFirstFlightSource),'Mandatory active HUD-caption result');}
});
test('all eight first-flight source groups bind exact authoring staged and corresponding bytes',()=>{
 const temporary=fs.mkdtempSync(path.join(root,'first-flight-'));
 const authored=path.join(temporary,'repo'),project=path.join(temporary,'project'),source=path.join(temporary,'source');
 assert.equal(firstFlightSourceGroups.length,8);
 const mapping=firstFlightSourceGroups.flatMap(([a,b,names])=>names.map(name=>[a+'/'+name,b+'/'+name]));
 assert.equal(mapping.length,15);
 for(const [name,mapped] of mapping){
  const raw=name==='content/world/synthetic/practice-circuit.json'?fs.readFileSync(path.join(repo,name)):Buffer.from('Original synthetic source-closure fixture: '+name+'\n');
  for(const [base,relative] of [[authored,name],[project,mapped],[source,mapped]]){const target=path.join(base,relative);fs.mkdirSync(path.dirname(target),{recursive:true});fs.writeFileSync(target,raw);}
 }
 const expected=validateFirstFlightSources(authored,project,source);
 assert.equal(Object.keys(expected.source_files).length,15);
 assert.equal(expected.source_files['content/world/synthetic/practice-circuit.json'].sha256,'2a4540d99d4500e326a1b1f0673583bd6f8ea99d430b991fcca1130befbbddcc');
 assert.equal(mapping.find(([name])=>name==='tests/integration/first_flight/visual_checks.gd')[1],'first_flight_scene_tests/visual_checks.gd');
 assert.equal(mapping.find(([name])=>name==='tests/integration/first_flight/layout_visual_checks.gd')[1],'first_flight_scene_tests/layout_visual_checks.gd');
 assert.equal(mapping.find(([name])=>name==='tests/integration/first_flight/hud_caption_visual_checks.gd')[1],'first_flight_scene_tests/hud_caption_visual_checks.gd');
 for(const [name,mapped] of mapping)for(const [base,relative] of [[authored,name],[project,mapped],[source,mapped]]){
  const file=path.join(base,relative),raw=fs.readFileSync(file);
  fs.appendFileSync(file,'drift');assert.throws(()=>validateFirstFlightSources(authored,project,source));fs.writeFileSync(file,raw);
  fs.unlinkSync(file);assert.throws(()=>validateFirstFlightSources(authored,project,source));fs.writeFileSync(file,raw);
 }
 for(const [a,b] of firstFlightSourceGroups)for(const [base,folder] of [[authored,a],[project,b],[source,b]]){
  const extra=path.join(base,folder,'unbound.gd');fs.writeFileSync(extra,'extends RefCounted');assert.throws(()=>validateFirstFlightSources(authored,project,source));fs.unlinkSync(extra);
 }
 const uid=path.join(project,'ui/first_flight/binding_help.gd.uid');fs.writeFileSync(uid,'uid://firstflightfixture\n');
 assert.doesNotThrow(()=>validateFirstFlightSources(authored,project,source));
 for(const value of ['invalid','uid://'+'a'.repeat(21)+'\n','uid://valid\nextra']){fs.writeFileSync(uid,value);assert.throws(()=>validateFirstFlightSources(authored,project,source));}
 fs.unlinkSync(uid);
 const orphan=path.join(project,'ui/first_flight/unknown.gd.uid');fs.writeFileSync(orphan,'uid://fixture\n');assert.throws(()=>validateFirstFlightSources(authored,project,source));fs.unlinkSync(orphan);
 const originals=mapping.find(([name])=>name==='content/world/synthetic/practice-circuit.json');
 for(const [base,name] of [[authored,originals[0]],[project,originals[1]],[source,originals[1]]])fs.appendFileSync(path.join(base,name),'\n');
 assert.throws(()=>validateFirstFlightSources(authored,project,source),/Frozen circuit content changed/,'Coherent three-tree drift cannot replace frozen content');
 for(const [base,name] of [[authored,originals[0]],[project,originals[1]],[source,originals[1]]])fs.writeFileSync(path.join(base,name),fs.readFileSync(path.join(repo,originals[0])));
 const folder=path.join(source,'first_flight_scene_tests'),outside=path.join(temporary,'outside');fs.renameSync(folder,outside);fs.symlinkSync(outside,folder,process.platform==='win32'?'junction':'dir');
 assert.throws(()=>validateFirstFlightSources(authored,project,source),/link/);
});

// ADR020 fixture admission only: no audio/native/Godot processes in these tests.
import {audioSourceGroups,validateAudioSources,validateAudioSourceDescriptors,validateAudioReceipt} from './package.mjs';
function audioReceipt(){
 return Object.fromEntries(['cues','options','renderer','panel','lifecycle'].map(name=>[name,{passed:true,checks:3,failures:[],...(name==='panel'?{scope:'Synthetic audio receipt admission only'}:{})}]));
}
test('audio admission requires all five executed closed typed nonvacuous groups',()=>{
 assert.equal(validateAudioReceipt(audioReceipt()),15);
 for(const bad of [null,[],{},false])assert.throws(()=>validateAudioReceipt(bad));
 for(const name of Object.keys(audioReceipt())){
  for(const change of [
   r=>delete r[name],r=>r[name]=null,r=>r[name]=[],r=>r[name].passed=false,r=>r[name].passed='true',
   ...[0,-1,1.5,'1',true,Number.MAX_SAFE_INTEGER+1].map(value=>r=>r[name].checks=value),
   r=>r[name].failures=null,r=>r[name].failures=['failed'],r=>r[name].failures={},r=>r[name].skipped=true,
   ...['passed','checks','failures'].map(key=>r=>delete r[name][key]),
  ]){const bad=audioReceipt();change(bad);assert.throws(()=>validateAudioReceipt(bad),name);}
 }
 for(const scope of [null,1,'','  ','x'.repeat(1025)]){const bad=audioReceipt();bad.panel.scope=scope;assert.throws(()=>validateAudioReceipt(bad));}
 for(const change of [r=>delete r.panel.scope,r=>r.cues.scope='unexpected',r=>r.runtime_skip=true,r=>r.cues.checks=Number.MAX_SAFE_INTEGER]){const bad=audioReceipt();change(bad);assert.throws(()=>validateAudioReceipt(bad));}
 const keys=['schema_version','scope','passed','checks','failures','facade','origin','participants','wire','scene','input','input_scene','instruments','cockpit','freeflight','observed','observed_archive','wind','first_flight'];
 const good=Object.fromEntries(keys.map(name=>[name,null]));good.first_flight=firstFlightReceipt();good.cockpit={hud_caption:{passed:true,checks:1,failures:[],scope:'Fixture'}};good.audio=audioReceipt();
 assert.doesNotThrow(()=>validateFirstFlightFacadeAdmission(good,true,savedFirstFlightSource));
 for(const change of [r=>delete r.audio,r=>r.audio={},r=>r.audio=null,r=>r.audio.lifecycle.checks=0,r=>r.audio.lifecycle.skipped=true]){const bad=structuredClone(good);change(bad);assert.throws(()=>validateFirstFlightFacadeAdmission(bad,true,savedFirstFlightSource));}
});
test('audio recursive closure binds three groups eight scripts and existing Sound in three trees',()=>{
 const temporary=fs.mkdtempSync(path.join(root,'audio-'));
 const authored=path.join(temporary,'repo'),project=path.join(temporary,'project'),source=path.join(temporary,'source');
 assert.equal(audioSourceGroups.length,3);
 const mapping=audioSourceGroups.flatMap(([a,b,names])=>names.map(name=>[a+'/'+name,b+'/'+name]));assert.equal(mapping.length,8);
 mapping.push(['app/proof/interactive/flight_sound.gd','interactive/flight_sound.gd']);
 for(const [name,mapped] of mapping)for(const [base,relative] of [[authored,name],[project,mapped],[source,mapped]]){const target=path.join(base,relative);fs.mkdirSync(path.dirname(target),{recursive:true});fs.writeFileSync(target,'Original audio source fixture '+name+'\n');}
 const identity=validateAudioSources(authored,project,source);assert.equal(Object.keys(identity.source_files).length,9);
 const descriptors=audioSourceGroups.map(([a,b,required])=>({source:a,destination:b,required:[...required],snapshot:[...required].sort().map(name=>({path:name,...identity.source_files[a+'/'+name]}))}));
 assert.doesNotThrow(()=>validateAudioSourceDescriptors(descriptors,identity.source_files));
 for(const change of [g=>g.pop(),g=>g.push(structuredClone(g[0])),g=>g[1]=structuredClone(g[0]),g=>g[0].destination='other',g=>g[0].required.pop(),g=>g[0].snapshot.pop(),g=>g[0].snapshot[0].sha256='a'.repeat(64),g=>g[0].snapshot[0].bytes=true,g=>g[0].snapshot[0].skipped=true,g=>g[0].skipped=true,g=>g[0].snapshot.reverse()]){const bad=structuredClone(descriptors);change(bad);assert.throws(()=>validateAudioSourceDescriptors(bad,identity.source_files));}
 for(const [name,mapped] of mapping)for(const [base,relative] of [[authored,name],[project,mapped],[source,mapped]]){
  const file=path.join(base,relative),raw=fs.readFileSync(file);fs.appendFileSync(file,'drift');assert.throws(()=>validateAudioSources(authored,project,source));fs.writeFileSync(file,raw);
  fs.unlinkSync(file);assert.throws(()=>validateAudioSources(authored,project,source));fs.writeFileSync(file,raw);
 }
 for(const [a,b] of audioSourceGroups)for(const [base,folder] of [[authored,a],[project,b],[source,b]]){const extra=path.join(base,folder,'nested','unbound.gd');fs.mkdirSync(path.dirname(extra),{recursive:true});fs.writeFileSync(extra,'extends RefCounted');assert.throws(()=>validateAudioSources(authored,project,source));fs.rmSync(path.dirname(extra),{recursive:true});}
 const uid=path.join(project,'audio/audio_cues.gd.uid');fs.writeFileSync(uid,'uid://audioproof\n');assert.doesNotThrow(()=>validateAudioSources(authored,project,source));
 for(const text of ['invalid','uid://'+'a'.repeat(21)+'\n','uid://valid\nextra']){fs.writeFileSync(uid,text);assert.throws(()=>validateAudioSources(authored,project,source));}fs.unlinkSync(uid);
 for(const [base,folder] of [[authored,'app/audio'],[project,'audio'],[source,'audio']]){const orphan=path.join(base,folder,'orphan.gd.uid');fs.writeFileSync(orphan,'uid://audiofixture\n');assert.throws(()=>validateAudioSources(authored,project,source));fs.unlinkSync(orphan);}
 const folder=path.join(source,'audio'),outside=path.join(temporary,'outside');fs.renameSync(folder,outside);fs.symlinkSync(outside,folder,process.platform==='win32'?'junction':'dir');assert.throws(()=>validateAudioSources(authored,project,source),/link/);
});

import {isOriginalAudioSourcePath,stageOriginalAudioNotice} from './package.mjs';
test('original audio source attribution stages actual reviewed MIT notice without reclassifying PCK',()=>{
 assert(isOriginalAudioSourcePath('source/whole-flight-preview/audio/sample_renderer.gd'));
 assert(isOriginalAudioSourcePath('source/whole-flight-preview/interactive/flight_sound.gd'));
 for(const name of ['WholeFlightPreview.pck','source/whole-flight-preview/audio/audio_cues.gd','source/whole-flight-preview/audio/sample_renderer.gd.uid','interactive/flight_sound.gd'])assert.equal(isOriginalAudioSourcePath(name),false);
 const temporary=fs.mkdtempSync(path.join(root,'audio-notice-')),authored=path.join(temporary,'repo'),payload=path.join(temporary,'payload');fs.mkdirSync(authored);fs.mkdirSync(payload);
 const entry=JSON.parse(fs.readFileSync(path.join(repo,'third_party/licenses/register.json'),'utf8')).entries.find(item=>item.id==='original-prototype-audio');
 const raw=fs.readFileSync(path.join(repo,'LICENSE'));fs.writeFileSync(path.join(authored,'LICENSE'),raw);
 const notice=stageOriginalAudioNotice(authored,payload,entry);assert.equal(notice.file,'notices/Original-Audio-MIT.txt');assert.equal(notice.register_path,'LICENSE');assert.equal(notice.sha256,entry.notice_files[0].sha256);assert(fs.readFileSync(path.join(payload,notice.file)).equals(raw));
 assert.deepEqual(stageOriginalAudioNotice(authored,payload,entry),notice);
 for(const change of [e=>e.id='other',e=>e.class='other',e=>e.license='GPL',e=>e.notice_files=[],e=>e.notice_files[0].path='../LICENSE',e=>e.notice_files[0].sha256='a'.repeat(64)]){const bad=structuredClone(entry);change(bad);assert.throws(()=>stageOriginalAudioNotice(authored,payload,bad));}
 fs.appendFileSync(path.join(authored,'LICENSE'),'drift');assert.throws(()=>stageOriginalAudioNotice(authored,payload,entry));assert(fs.readFileSync(path.join(payload,notice.file)).equals(raw),'Rejected notice preserves staged bytes');
});
