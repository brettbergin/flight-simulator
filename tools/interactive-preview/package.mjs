import fs from 'node:fs';
import {selectedLibrary,verifyExportSelection} from '../export/selected-source.mjs';
import path from 'node:path';
import assert from 'node:assert/strict';
import {fileURLToPath} from 'node:url';
import {spawnSync} from 'node:child_process';
import {checkRuntime,checkDependencies,sha,runtimeNames} from '../export/check-runtime.mjs';
import {auditRelease,auditDependencyLock} from '../license-audit/audit.mjs';
const repo=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'../..');
const json=file=>JSON.parse(fs.readFileSync(file,'utf8').replace(/^\uFEFF/,''));
const write=(file,value)=>{fs.mkdirSync(path.dirname(file),{recursive:true});fs.writeFileSync(file,JSON.stringify(value,null,2)+'\n');};
const register=json(path.join(repo,'third_party/licenses/register.json'));
const model=register.entries.find(e=>e.id==='original-interactive-prototype');
const policy=model.content_policy;
const pistonModel=register.entries.find(e=>e.id==='original-piston-prop-v1');
const pistonNames=['inventory.json','aircraft/original-piston-prop/original-piston-prop.xml','engine/original-piston.xml','engine/original-fixed-prop.xml','parameter-ledger.json','NOTICE-MIT.txt','README.md'].sort();
function ordinaryAncestors(file){
 for(let at=path.resolve(file);;at=path.dirname(at)){
  const info=fs.lstatSync(at);assert(!info.isSymbolicLink(),'Model/receipt path contains link');
  assert(info.isFile()||info.isDirectory(),'Unsupported model/receipt filesystem object');
  if(path.dirname(at)===at)break;
 }
}
function ordinaryFiles(root,prefix=''){
 ordinaryAncestors(root);assert(fs.lstatSync(root).isDirectory(),'Model root must be an ordinary directory');
 return fs.readdirSync(root,{withFileTypes:true}).flatMap(entry=>{
  const name=prefix+entry.name,file=path.join(root,entry.name);const info=fs.lstatSync(file);
  assert(!info.isSymbolicLink(),'Model tree contains link');
  if(info.isDirectory())return ordinaryFiles(file,name+'/');
  assert(info.isFile(),'Model tree contains unsupported object');return [name];
 });
}
export function validatePistonModelTree(root,entry=pistonModel){
 assert(entry&&entry.content_policy&&entry.source,'Reviewed piston content policy missing');
 assert.equal(entry.id,'original-piston-prop-v1');assert.equal(entry.version,'0.1.0-prototype');
 const policy=entry.content_policy;
 assert.equal(policy.model_id,'original-piston-prop-v1');
 assert.equal(policy.root,'native/fdm_jsbsim/models/original-piston-prop');
 assert.equal(policy.inventory_path,'native/fdm_jsbsim/models/original-piston-prop/inventory.json');
 assert.equal(policy.inventory_sha256,'f7766fda173d8ee83d4c4a8c02f6333124175a1f7064d3f4d8e78df3d17da12a','Reviewed piston inventory identity changed');
 assert.equal(entry.source.revision,'sha256:f7766fda173d8ee83d4c4a8c02f6333124175a1f7064d3f4d8e78df3d17da12a');
 assert.deepEqual(ordinaryFiles(root).sort(),pistonNames,'Exact seven-file piston model tree required');
 const raw=fs.readFileSync(path.join(root,'inventory.json'));
 assert.equal(sha(raw),policy.inventory_sha256,'Frozen piston inventory changed');
 const inventory=json(path.join(root,'inventory.json'));
 assert.deepEqual(inventory.files,policy.files);assert.deepEqual(inventory.metadata,policy.metadata);
 const pins=[...policy.files,...policy.metadata];
 assert.deepEqual(['inventory.json',...pins.map(pin=>pin.path)].sort(),pistonNames,'Piston content-policy roster changed');
 for(const pin of pins){
  const bytes=fs.readFileSync(path.join(root,pin.path));assert.equal(bytes.length,pin.bytes);assert.equal(sha(bytes),pin.sha256,'Piston source/metadata changed');
 }
 return pistonNames;
}
const pistonGroups=['bridge','facade','pacing','input','panel','status','wind','scene'];
const plain=value=>value!==null&&typeof value==='object'&&!Array.isArray(value);
export function validatePistonReceipt(receipt){
 assert(plain(receipt));assert.deepEqual(Object.keys(receipt).sort(),['schema','passed','checks','failures','scope','groups'].sort(),'Cold receipt closed shape');
 assert.equal(receipt.schema,'PistonFlightChecks/v1');assert.equal(receipt.passed,true);
 assert(Number.isSafeInteger(receipt.checks)&&receipt.checks>0);assert.deepEqual(receipt.failures,[]);
 assert.equal(typeof receipt.scope,'string');assert(receipt.scope.trim().length>0&&receipt.scope.length<=1024);
 assert(plain(receipt.groups));assert.deepEqual(Object.keys(receipt.groups).sort(),[...pistonGroups].sort(),'All eight cold groups required');
 let total=0;
 for(const name of pistonGroups){
  const group=receipt.groups[name];assert(plain(group));
  assert.deepEqual(Object.keys(group).sort(),['passed','checks','failures','result'].sort(),'Cold group closed shape/'+name);
  assert.equal(group.passed,true);assert(Number.isSafeInteger(group.checks)&&group.checks>0);assert.deepEqual(group.failures,[]);assert(plain(group.result));
  if(name!=='scene'){
   assert.equal(group.result.passed,true);assert(Number.isSafeInteger(group.result.checks)&&group.result.checks>0);assert.deepEqual(group.result.failures,[]);
   assert.equal(group.checks,group.result.checks+1,'Child actual checks plus host admission/'+name);
  }
  total+=group.checks;assert(Number.isSafeInteger(total));
 }
 assert.equal(total,receipt.checks,'Cold group aggregate count');
 const profiles=receipt.groups.pacing.result.native_profiles;assert(Array.isArray(profiles));assert.equal(profiles.length,25);
 const covered=new Set();
 for(const row of profiles){
  assert(plain(row));assert(['30','60','144','240','jitter'].includes(row.cadence));assert(['1/4','1/2','1','2','4'].includes(row.scale));
  const key=row.cadence+':'+row.scale;assert(!covered.has(key),'Duplicate cold pacing profile');covered.add(key);
  assert.equal(row.completed_profile,true);assert.equal(row.final_tick,'120');assert(Number.isSafeInteger(row.final_debt_quanta));assert.equal(row.final_debt_quanta,0);
 }
 const scene=receipt.groups.scene;assert(scene.checks>=2,'Scene host assertions plus initialized assertion required');
 assert.equal(scene.result.initialized,true);assert.equal(scene.result.cold_initial_tick,'0');assert.equal(scene.result.cold_reset_tick,'0');
}
function models(source,destination){
 assert.equal(sha(fs.readFileSync(path.join(source,'inventory.json'))),policy.inventory_sha256,'Frozen model inventory changed');
 const inventory=json(path.join(source,'inventory.json'));assert.deepEqual(inventory.files,policy.files);
 for(const pin of policy.files){
  const bytes=fs.readFileSync(path.join(source,pin.path));
  assert.equal(bytes.length,pin.bytes);assert.equal(sha(bytes),pin.sha256,'Model XML changed');
  const target=path.join(destination,pin.path);fs.mkdirSync(path.dirname(target),{recursive:true});fs.writeFileSync(target,bytes);
 }
 fs.copyFileSync(path.join(source,'inventory.json'),path.join(destination,'inventory.json'));
}
function walk(root,prefix=''){return fs.readdirSync(root,{withFileTypes:true}).flatMap(e=>e.isDirectory()?walk(path.join(root,e.name),prefix+e.name+'/'):[prefix+e.name]);}
function compare(a,b,label,exact=false){
 if(typeof a==='number'){assert.equal(typeof b,'number');assert(Number.isFinite(a)&&Number.isFinite(b));assert(exact?a===b:Math.abs(a-b)<=1e-9+1e-12*Math.max(Math.abs(a),Math.abs(b)),label);return;}
 if(Array.isArray(a)){assert.equal(b.length,a.length,label);a.forEach((v,i)=>compare(v,b[i],label+'/'+i,exact));return;}
 if(a&&typeof a==='object'){assert.deepEqual(Object.keys(a).sort(),Object.keys(b).sort(),label);for(const key of Object.keys(a))if(key!=='session_id')compare(a[key],b[key],label+'/'+key,exact);return;}
 assert.equal(a,b,label);
}
export function validateResourceReceipt(receipt,resource){
 assert.deepEqual(Object.keys(receipt).sort(),['schema','path','bytes','sha256'].sort(),'Runtime resource receipt closed shape');
 assert.equal(receipt.schema,'PreviewNativeResource/v1');assert.equal(receipt.path,'build/native_identity.gd');
 assert(Number.isSafeInteger(receipt.bytes)&&receipt.bytes>=0);assert.equal(receipt.bytes,resource.bytes);
 assert.equal(typeof receipt.sha256,'string');assert.match(receipt.sha256,/^[a-f0-9]{64}$/);assert.equal(receipt.sha256,resource.sha256);
}
function audit(root,proof,build,python='python'){
 const payload=path.join(root,'payload'),evidence=path.join(root,'evidence'),replacement=path.join(root,'Replacement space — Δ飛行');
 const baseline=json(path.join(evidence,'smoke-receipt.json')),changed=json(path.join(evidence,'replacement-smoke-receipt.json'));
 for(const receipt of [baseline,changed]){
  assert.equal(receipt.passed,true);assert.deepEqual(receipt.failures,[]);
  assert(receipt.automated_loop.all_wow&&receipt.automated_loop.final_speed_mps<.1);
  assert(Number(receipt.automated_loop.touchdown_tick)>Number(receipt.automated_loop.takeoff_tick));
 }
 const moduleNames=['flight_godot_bridge.dll','jsbsim.dll',...runtimeNames].sort();
 function witness(receipt,packageRoot){
  const records=Object.entries(receipt.runtime_modules).map(([name,file])=>{
   const relative=path.relative(packageRoot,file).replaceAll('\\','/');
   assert(!relative.startsWith('../')&&!path.isAbsolute(relative),'Actual module outside payload');
   assert([name.toLowerCase(),'bin/'+name.toLowerCase()].includes(relative.toLowerCase()));
   const bytes=fs.readFileSync(file);return {name:name.toLowerCase(),path:file,relative,sha256:sha(bytes),bytes:bytes.length};
  }).sort((a,b)=>a.name.localeCompare(b.name));
  assert.deepEqual(records.map(x=>x.name).sort(),moduleNames);return records;
 }
 const modules=witness(baseline,payload),replacedModules=witness(changed,replacement);
 const nativeIdentity=json(path.join(evidence,'native-build-identity.json'));
 // Independent selector/current compiler/source reconstruction, not shape-only evidence.
 const qualification=spawnSync(python,['-B',path.join(repo,'tools/interactive-preview/native-identity.py'),'--repository-root',repo,'--build-root',build,'--evidence',path.join(evidence,'native-build-identity.json'),'--staged-root',path.join(root,'project'),'--staged-root',path.join(payload,'source/whole-flight-preview'),'--check-reconstruction-root',path.join(payload,'source/whole-flight-preview')],{encoding:'utf8'});
 assert.equal(qualification.status,0,'Independent native/resource package qualification failed');
 assert.deepEqual(JSON.parse(qualification.stdout),nativeIdentity);
 assert.equal(nativeIdentity.schema,'PreviewNativeBuildIdentity/v2');
 const selection=selectedLibrary(register,nativeIdentity,repo);
 verifyExportSelection(selection,proof);
 const libraryId=selection.component_id;
 const acceptedLibrary=json(path.join(proof,'evidence/package-inventory.json')).components.find(item=>item.id===libraryId);
 assert(acceptedLibrary,'Matching source release component missing');
 assert.equal(sha(fs.readFileSync(path.join(proof,'payload/bin/flight_godot_bridge.dll'))),nativeIdentity.build_witnesses.find(item=>item.path==='bin/flight_godot_bridge.dll').sha256,'Export consumer ABI differs');
 const reconstructionRoot=path.join(payload,'source/whole-flight-preview');
 const reconstruction=json(path.join(reconstructionRoot,'native-reconstruction.json'));
 assert.deepEqual(Object.keys(reconstruction).sort(),['schema','base_git_commit','files','scope'].sort());
 assert.equal(reconstruction.schema,'PreviewNativeReconstruction/v1');assert.match(reconstruction.base_git_commit,/^[a-f0-9]{40}$/);
 const names=new Set();for(const item of reconstruction.files){
  assert.deepEqual(Object.keys(item).sort(),['path','bytes','sha256'].sort());
  assert.equal(typeof item.path,'string');assert(!item.path.includes('\\')&&!item.path.includes(':')&&!item.path.startsWith('/')&&!item.path.split('/').some(x=>!x||x==='.'||x==='..'));
  assert(!names.has(item.path));names.add(item.path);assert(Number.isSafeInteger(item.bytes)&&item.bytes>=0);assert.match(item.sha256,/^[a-f0-9]{64}$/);
  for(const parent of [repo,path.join(reconstructionRoot,'repository')]){const file=path.join(parent,item.path);const raw=fs.readFileSync(file);assert.equal(raw.length,item.bytes);assert.equal(sha(raw),item.sha256);}
 }
 for(const item of nativeIdentity.source_bindings)assert(names.has(item.path),'Missing consumer reconstruction source');
 for(const name of ['native/fdm_jsbsim/interactive/native_identity.gd.in','tools/bootstrap/source-selection.cmake','CMakePresets.json'])assert(names.has(name),'Missing generator/build reconstruction source');
 for(const context of ['editor','portable','replacement'])validateResourceReceipt(json(path.join(evidence,context+'-native-identity-receipt.json')),nativeIdentity.resource);
 const bridgeIdentity=nativeIdentity.build_witnesses.find(item=>item.path==='bin/flight_godot_bridge.dll');
 assert.equal(bridgeIdentity.sha256,modules.find(item=>item.name==='flight_godot_bridge.dll').sha256);
 assert.equal(bridgeIdentity.sha256,replacedModules.find(item=>item.name==='flight_godot_bridge.dll').sha256);
 // Current UI drivers must execute in editor, portable and replacement contexts.
 const uiReceipts=['editor','portable','replacement'].map(name=>json(path.join(evidence,name+'-facade-receipt.json')));
 for(const receipt of uiReceipts){
  assert.equal(receipt.passed,true);assert.deepEqual(receipt.failures,[]);
  assert.deepEqual(Object.keys(receipt).sort(),['schema_version','scope','passed','checks','failures','facade','origin','participants','wire','scene','input','input_scene','instruments','cockpit','freeflight','observed','observed_archive','wind'].sort(),'Facade receipt closed shape');
  assert.deepEqual(Object.keys(receipt.wind).sort(),['bridge','cue','scene']);
  for(const [name,item] of Object.entries(receipt.wind)){
   const keys=name==='bridge'?['passed','checks','failures']:name==='cue'?['passed','checks','failures','scope','reference_cases','reference_sha256','runway_expectations']:['passed','checks','failures','scope'];
   assert.deepEqual(Object.keys(item).sort(),keys.sort(),'Wind receipt closed shape/'+name);
   assert.equal(item.passed,true);assert(Number.isSafeInteger(item.checks)&&item.checks>0);assert.deepEqual(item.failures,[]);
   if(name!=='bridge'){assert.equal(typeof item.scope,'string');assert(item.scope.length>0&&item.scope.length<=1024);}
  }
  assert.equal(receipt.wind.cue.reference_cases,22);assert.equal(receipt.wind.cue.runway_expectations,8);
  assert.equal(receipt.wind.cue.reference_sha256,'7d71cbb4f8d9ad12fe91501d5e020f14bbf02516d363512e69b6fa41320856c3');
  assert.equal(receipt.schema_version,1);assert(Number.isSafeInteger(receipt.checks)&&receipt.checks>0);assert.equal(typeof receipt.scope,'string');assert(receipt.scope.length>0&&receipt.scope.length<=1024);
  assert.deepEqual(Object.keys(receipt.freeflight).sort(),['geometry','scene']);
  for(const item of Object.values(receipt.freeflight)){assert.equal(item.passed,true);assert(item.checks>0);assert.deepEqual(item.failures,[]);}
  assert.deepEqual(Object.keys(receipt.observed).sort(),['recorder','scene'],'Both observed checks must execute');
  for(const [name,item] of Object.entries(receipt.observed)){
   assert.deepEqual(Object.keys(item).sort(),(name==='recorder'?['passed','checks','failures','reference_cases','reference_sha256','scope']:['passed','checks','failures','scope']).sort(),'Observed receipt closed shape/'+name);
   assert.equal(item.passed,true);assert(Number.isSafeInteger(item.checks)&&item.checks>0);assert.deepEqual(item.failures,[]);assert.equal(typeof item.scope,'string');assert(item.scope.length>0&&item.scope.length<=1024);
  }
  assert.deepEqual(Object.keys(receipt.observed_archive).sort(),['codec','files','scene']);
  for(const [name,item] of Object.entries(receipt.observed_archive)){
   const names=['passed','checks','failures','scope'];if(name==='codec')names.push('reference_cases','reference_sha256','binary64_cases','binary64_sha256');
   assert.deepEqual(Object.keys(item).sort(),names.sort(),'Archive receipt exact shape/'+name);
   assert.equal(item.passed,true);assert(Number.isSafeInteger(item.checks)&&item.checks>0);assert.deepEqual(item.failures,[]);assert.equal(typeof item.scope,'string');assert(item.scope.length>0&&item.scope.length<=1024);
  }
  assert.equal(receipt.observed_archive.codec.reference_cases,40);assert.equal(receipt.observed_archive.codec.reference_sha256,'961d8903f702f1d46374998db06b7517a1ca067333b3613bd2adbf3a8c06b15e');
  assert.equal(receipt.observed_archive.codec.binary64_cases,26);assert.equal(receipt.observed_archive.codec.binary64_sha256,'406b00475e444f71f6e1f57fd37100c52b86c076e0dccbf664bb5bfc05c028d8');
  assert.equal(receipt.observed.recorder.reference_cases,42);
  assert.equal(receipt.observed.recorder.reference_sha256,'a4c3184c46f2eb76c85ff4ba43fc8aac49e772a447576eeec5663fff1ac78844');
 }
 const pistonEnabled=nativeIdentity.source_variant==='jsbsim-1.3.1-event-aware-coupled-midpoint-v1';
 const coldReceipts=[];
 if(pistonEnabled){
  for(const modelRoot of [path.join(repo,pistonModel.content_policy.root),path.join(root,'project/piston-models'),path.join(payload,'piston-models'),path.join(replacement,'piston-models'),path.join(payload,'source/whole-flight-preview/piston-models')])validatePistonModelTree(modelRoot);
  for(const context of ['editor','portable','replacement']){
   const file=path.join(evidence,context+'-piston-receipt.json');ordinaryAncestors(file);assert(fs.lstatSync(file).isFile());
   const raw=fs.readFileSync(file);const receipt=json(file);validatePistonReceipt(receipt);
   coldReceipts.push({context,raw,checks:receipt.checks});
  }
 }else{assert(!fs.existsSync(path.join(payload,'piston-models')),'Cold model delivery requires selected coupled source');}
 const geometry=json(path.join(repo,'tests/ui/freeflight/reference.json'));
 assert.equal(geometry.case_count,16);assert.equal(geometry.cases.length,16);
 for(const folder of ['ui/freeflight','freeflight_tests']){
  const staged=path.join(root,'project',folder),source=path.join(payload,'source/whole-flight-preview',folder);
  const originals=walk(source).sort();
  assert.deepEqual(walk(staged).filter(x=>!x.endsWith('.gd.uid')).sort(),originals.filter(x=>!x.endsWith('.gd.uid')).sort());
  for(const file of originals)assert.equal(sha(fs.readFileSync(path.join(source,file))),sha(fs.readFileSync(path.join(staged,file))),'freeflight corresponding source/'+folder+'/'+file);
 }
 const observedGroups=[['app/replay/observed','replay/observed',['recorder.gd','review.gd','tick_math.gd','values.gd']],['app/ui/debrief/observed','ui/debrief/observed',['panel.gd']],['tests/debrief/observed','observed_tests',['recorder_checks.gd','scene_checks.gd','expected-v1.json','generate.py','preparation-binding-v2.json','root-ratification-v1.json','README.md','.gitattributes']],['app/replay/observed_archive','replay/observed_archive',['codec.gd','strict_json.gd','files.gd','windows_io.ps1']],['tests/debrief/observed_archive','observed_archive_tests',['archive_checks.gd','file_checks.gd','scene_checks.gd','visual_checks.gd','windows_fixture.ps1','generate.py','source-binding-v1.json','root-ratification-v1.json','README.md','.gitattributes','reference/expected-text-v1.json','reference/expected-binary64-v1.json']]];
 const windGroups=[['app/world/wind','world/wind',['wind_cue.gd']],['app/ui/wind','ui/wind',['panel.gd']],['tests/world/wind','wind_tests',['wind_checks.gd','ratification-v1.json','reference/expected-v1.json','reference/generate.py','reference/manifest-v1.json','reference/NOTICE-MIT.txt']],['tests/integration/wind','wind_scene_tests',['scene_checks.gd','visual_checks.gd']]];
 for(const [authored,folder,required] of [...observedGroups,...windGroups]){
  const author=path.join(repo,authored),staged=path.join(root,'project',folder),source=path.join(payload,'source/whole-flight-preview',folder);
  const originals=walk(author).sort();
  for(const entry of required)assert(originals.includes(entry),'Required observed source missing/'+entry);
  assert.deepEqual(walk(source).sort(),originals,'Observed corresponding-source resource set/'+folder);
  const authoredUIDs=new Set(originals.filter(file=>file.endsWith('.gd.uid')));
  const stagedFiles=walk(staged);
  for(const file of stagedFiles.filter(file=>file.endsWith('.gd.uid')&&!authoredUIDs.has(file))){
   assert(originals.includes(file.slice(0,-4)),'Orphan observed generated UID/'+file);
   const bytes=fs.readFileSync(path.join(staged,file));assert(bytes.length<=64);assert.match(bytes.toString('utf8'),/^uid:\/\/[a-z0-9]{1,20}\r?\n?$/);
  }
  assert.deepEqual(stagedFiles.filter(file=>!file.endsWith('.gd.uid')||authoredUIDs.has(file)).sort(),originals,'Observed staged resource set/'+folder);
  for(const file of originals){
   const expected=sha(fs.readFileSync(path.join(author,file)));
   assert.equal(sha(fs.readFileSync(path.join(source,file))),expected,'Observed corresponding source/'+folder+'/'+file);
   assert.equal(sha(fs.readFileSync(path.join(staged,file))),expected,'Observed staged source/'+folder+'/'+file);
  }
 }
 assert.equal(sha(fs.readFileSync(path.join(repo,'tests/debrief/observed/expected-v1.json'))),'a4c3184c46f2eb76c85ff4ba43fc8aac49e772a447576eeec5663fff1ac78844');

 const traces=['loop.records.ndjson','replacement.records.ndjson'].map(name=>fs.readFileSync(path.join(evidence,name),'utf8').trim().split('\n').map(JSON.parse));
 assert.equal(traces[0].length,traces[1].length);traces[0].forEach((a,i)=>compare(a,traces[1][i],'trace/'+i));
 const editorTrace=fs.readFileSync(path.join(evidence,'editor.records.ndjson'),'utf8').trim().split('\n').map(JSON.parse);
 assert.equal(editorTrace.length,traces[0].length);editorTrace.forEach((a,i)=>compare(a,traces[0][i],'same-build/'+i,true));
 const originalFiles=walk(payload).filter(x=>!['portable-smoke.log','smoke-receipt.json','loop.records.ndjson'].includes(x));
 const differences=originalFiles.filter(x=>sha(fs.readFileSync(path.join(payload,x)))!==sha(fs.readFileSync(path.join(replacement,x))));
 assert.deepEqual(differences.sort(),['JSBSim.dll','bin/JSBSim.dll'].sort(),'Replacement changed other payload bytes');
 const oldReplacement=json(path.join(proof,'evidence/replacement-evidence.json'));
 const replacementEvidence={...oldReplacement,scope:'Actual combined-model loop, same native/UI package with only JSBSim DLL replaced; rebuild source receipt inherited and rehashed from accepted export',baseline_library_sha256:modules.find(x=>x.name==='jsbsim.dll').sha256,replaced_library_sha256:replacedModules.find(x=>x.name==='jsbsim.dll').sha256,changed_payload_files:differences,other_payload_unchanged:true,actual_replacement_module_inside_payload:true,trace_records_compared:traces[0].length,comparison_absolute_tolerance:1e-9,comparison_relative_tolerance:1e-12};
 assert.equal(replacementEvidence.replaced_library_sha256,oldReplacement.replaced_library_sha256);
 assert.notEqual(replacementEvidence.baseline_library_sha256,replacementEvidence.replaced_library_sha256);
 write(path.join(evidence,'replacement-evidence.json'),replacementEvidence);
 write(path.join(evidence,'baseline-modules.json'),modules);write(path.join(evidence,'replacement-modules.json'),replacedModules);
 const runtime=checkRuntime(json(path.join(proof,'evidence/selected-crt.json')),fs.readFileSync(path.join(build,'toolchain-build-manifest.txt'),'utf8'),register.entries.find(e=>e.id==='microsoft-vc143-crt').runtime_policy,{packageRoot:payload});
 const dependencies=json(path.join(evidence,'native-dependencies.json'));checkDependencies(dependencies,{packageRoot:payload});
 for(const pin of policy.files){const b=fs.readFileSync(path.join(payload,'models',pin.path));assert.equal(sha(b),pin.sha256);assert.equal(b.length,pin.bytes);}
 assert.equal(sha(fs.readFileSync(path.join(payload,'models/inventory.json'))),policy.inventory_sha256);
 // Retain accepted vendor/source/notice declarations while replacing current binaries/content and adding authored source.
 const accepted=json(path.join(proof,'evidence/package-inventory.json'));
 const components=accepted.components.filter(c=>c.id!=='original-synthetic').map(c=>({...c,files:c.files.filter(f=>fs.existsSync(path.join(payload,f.path))).map(f=>({...f,sha256:sha(fs.readFileSync(path.join(payload,f.path)))}))}));
 function component(id){let c=components.find(x=>x.id===id);if(!c){const e=register.entries.find(x=>x.id===id);assert(e);c={id,version:e.version,source_revision:e.source.revision,files:[],notices:[]};components.push(c);}return c;}
 function declare(id,file,role){const c=component(id);c.files=c.files.filter(x=>x.path!==file);c.files.push({path:file,sha256:sha(fs.readFileSync(path.join(payload,file))),role});}
 function stage(id,file,value){const dest=path.join(payload,file);write(dest,value);declare(id,file,'evidence');}
 for(const file of walk(payload)){
  if(file.startsWith('piston-models/')){assert(pistonEnabled);declare(pistonModel.id,file,'content');}
  else if(file.startsWith('source/whole-flight-preview/piston-models/')){assert(pistonEnabled);declare(pistonModel.id,file,'source');}
  else if(file.startsWith('models/'))declare(model.id,file,'content');
  else if(file.startsWith('source/whole-flight-preview/'))declare('native-export-proof',file,'source');
  else if(file.endsWith('.exe'))declare('godot',file,'binary');
  else if(file.endsWith('.pck')||['launch.ps1','README.md'].includes(file))declare('native-export-proof',file,'content');
  else if(['portable-smoke.log','smoke-receipt.json','loop.records.ndjson'].includes(file))declare('native-export-proof',file,'evidence');
 }
 for(const notice of model.notice_files){const target='notices/'+path.basename(notice.path);fs.copyFileSync(path.join(repo,notice.path),path.join(payload,target));declare(model.id,target,'notice');component(model.id).notices.push({register_path:notice.path,package_path:target});}
 if(pistonEnabled){
  for(const notice of pistonModel.notice_files){
   const bytes=fs.readFileSync(path.join(repo,notice.path));assert.equal(sha(bytes),notice.sha256);
   const target='notices/'+path.basename(notice.path);fs.writeFileSync(path.join(payload,target),bytes);declare(pistonModel.id,target,'notice');
   const owner=component(pistonModel.id);owner.notices=owner.notices.filter(item=>item.register_path!==notice.path);owner.notices.push({register_path:notice.path,package_path:target});
  }
  for(const {context,raw} of coldReceipts){
   const target='evidence/'+context+'-piston-receipt.json';fs.mkdirSync(path.dirname(path.join(payload,target)),{recursive:true});
   fs.writeFileSync(path.join(payload,target),raw);declare('native-export-proof',target,'evidence');
  }
 }
 stage('microsoft-vc143-crt','evidence/selected-runtime.json',runtime);stage('microsoft-vc143-crt','evidence/native-dependencies.json',dependencies);
 stage(libraryId,'evidence/jsbsim-replacement.json',replacementEvidence);stage(libraryId,'evidence/baseline-modules.json',modules);stage(libraryId,'evidence/replacement-modules.json',replacedModules);
 assert.equal(sha(fs.readFileSync(path.join(payload,acceptedLibrary.source_archive))),selection.source_archive_sha256);
 const manifest={schema_version:1,components};
 assert.deepEqual(auditRelease(register,manifest,{repoRoot:repo,packageRoot:payload}),[]);
 assert.deepEqual(auditDependencyLock(register,json(path.join(repo,'third_party/dependencies.lock.json'))),[]);
 write(path.join(evidence,'package-inventory.json'),manifest);
 write(path.join(evidence,'package-audit.json'),{schema_version:1,rights_integrity_passed:true,actual_combined_replacement_passed:true,model_pins_verified:true,actual_seven_modules_inside_payload:true,exact_editor_portable_repeat:true,observed_editor_portable_replacement_checks_passed:true,observed_source_closure_verified:true,observed_archive_checks_passed:true,...(pistonEnabled?{piston_model_pins_verified:true,piston_editor_portable_replacement_checks_passed:true,piston_contexts:coldReceipts.map(({context,raw,checks})=>({context,checks,bytes:raw.length,sha256:sha(raw)}))}:{}),runtime_verification:runtime,trace_records_compared:traces[0].length,selected_library:selection,native_build_identity:nativeIdentity});
 console.log('PASS combined package model/source/notices/full PE+CRT closure and actual replacement loop');
}
const [mode,...args]=process.argv.slice(2);
if(process.argv[1]&&path.resolve(process.argv[1])===fileURLToPath(import.meta.url)){
if(mode==='models')models(...args);else if(mode==='audit')audit(...args);else throw new Error('Expected models or audit');
}
