import fs from 'node:fs';
import path from 'node:path';
import assert from 'node:assert/strict';
import {fileURLToPath} from 'node:url';
import {checkRuntime,checkDependencies,sha,runtimeNames} from '../export/check-runtime.mjs';
import {auditRelease,auditDependencyLock} from '../license-audit/audit.mjs';
const repo=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'../..');
const json=file=>JSON.parse(fs.readFileSync(file,'utf8').replace(/^\uFEFF/,''));
const write=(file,value)=>{fs.mkdirSync(path.dirname(file),{recursive:true});fs.writeFileSync(file,JSON.stringify(value,null,2)+'\n');};
const register=json(path.join(repo,'third_party/licenses/register.json'));
const model=register.entries.find(e=>e.id==='original-interactive-prototype');
const policy=model.content_policy;
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
function audit(root,proof,build){
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
 assert.equal(path.resolve(nativeIdentity.root),path.resolve(build));
 assert.match(nativeIdentity.declared_source_fingerprint,/^[a-f0-9]{64}$/);
 assert.equal(nativeIdentity.source_bindings.length,6);assert.equal(nativeIdentity.build_witnesses.length,4);
 for(const item of nativeIdentity.source_bindings){const bytes=fs.readFileSync(path.join(repo,item.path));assert.equal(bytes.length,item.bytes);assert.equal(sha(bytes),item.raw_sha256);assert.equal(sha(Buffer.from(bytes.toString('utf8').replaceAll('\r\n','\n'))),item.lf_sha256);}
 for(const item of nativeIdentity.build_witnesses){const bytes=fs.readFileSync(path.join(build,item.path));assert.equal(bytes.length,item.bytes);assert.equal(sha(bytes),item.sha256);}
 const bridgeIdentity=nativeIdentity.build_witnesses.find(item=>item.path==='bin/flight_godot_bridge.dll');
 assert.equal(bridgeIdentity.sha256,modules.find(item=>item.name==='flight_godot_bridge.dll').sha256);
 assert.equal(bridgeIdentity.sha256,replacedModules.find(item=>item.name==='flight_godot_bridge.dll').sha256);
 // Current UI drivers must execute in editor, portable and replacement contexts.
 const uiReceipts=['editor','portable','replacement'].map(name=>json(path.join(evidence,name+'-facade-receipt.json')));
 for(const receipt of uiReceipts){
  assert.equal(receipt.passed,true);assert.deepEqual(receipt.failures,[]);
  assert.deepEqual(Object.keys(receipt).sort(),['schema_version','scope','passed','checks','failures','facade','origin','participants','wire','scene','input','input_scene','instruments','cockpit','freeflight','observed','observed_archive'].sort(),'Facade receipt closed shape');
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
 const geometry=json(path.join(repo,'tests/ui/freeflight/reference.json'));
 assert.equal(geometry.case_count,16);assert.equal(geometry.cases.length,16);
 for(const folder of ['ui/freeflight','freeflight_tests']){
  const staged=path.join(root,'project',folder),source=path.join(payload,'source/whole-flight-preview',folder);
  const originals=walk(source).sort();
  assert.deepEqual(walk(staged).filter(x=>!x.endsWith('.gd.uid')).sort(),originals.filter(x=>!x.endsWith('.gd.uid')).sort());
  for(const file of originals)assert.equal(sha(fs.readFileSync(path.join(source,file))),sha(fs.readFileSync(path.join(staged,file))),'freeflight corresponding source/'+folder+'/'+file);
 }
 const observedGroups=[['app/replay/observed','replay/observed',['recorder.gd','review.gd','tick_math.gd','values.gd']],['app/ui/debrief/observed','ui/debrief/observed',['panel.gd']],['tests/debrief/observed','observed_tests',['recorder_checks.gd','scene_checks.gd','expected-v1.json','generate.py','preparation-binding-v2.json','root-ratification-v1.json','README.md','.gitattributes']],['app/replay/observed_archive','replay/observed_archive',['codec.gd','strict_json.gd','files.gd','windows_io.ps1']],['tests/debrief/observed_archive','observed_archive_tests',['archive_checks.gd','file_checks.gd','scene_checks.gd','visual_checks.gd','windows_fixture.ps1','generate.py','source-binding-v1.json','root-ratification-v1.json','README.md','.gitattributes','reference/expected-text-v1.json','reference/expected-binary64-v1.json']]];
 for(const [authored,folder,required] of observedGroups){
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
  if(file.startsWith('models/'))declare(model.id,file,'content');
  else if(file.startsWith('source/whole-flight-preview/'))declare('native-export-proof',file,'source');
  else if(file.endsWith('.exe'))declare('godot',file,'binary');
  else if(file.endsWith('.pck')||['launch.ps1','README.md'].includes(file))declare('native-export-proof',file,'content');
  else if(['portable-smoke.log','smoke-receipt.json','loop.records.ndjson'].includes(file))declare('native-export-proof',file,'evidence');
 }
 for(const notice of model.notice_files){const target='notices/'+path.basename(notice.path);fs.copyFileSync(path.join(repo,notice.path),path.join(payload,target));declare(model.id,target,'notice');component(model.id).notices.push({register_path:notice.path,package_path:target});}
 stage('microsoft-vc143-crt','evidence/selected-runtime.json',runtime);stage('microsoft-vc143-crt','evidence/native-dependencies.json',dependencies);
 stage('jsbsim','evidence/jsbsim-replacement.json',replacementEvidence);stage('jsbsim','evidence/baseline-modules.json',modules);stage('jsbsim','evidence/replacement-modules.json',replacedModules);
 assert.equal(sha(fs.readFileSync(path.join(payload,'source/jsbsim-1.3.1-library-source.zip'))),register.entries.find(x=>x.id==='jsbsim').library_policy.source_archive_sha256);
 const manifest={schema_version:1,components};
 assert.deepEqual(auditRelease(register,manifest,{repoRoot:repo,packageRoot:payload}),[]);
 assert.deepEqual(auditDependencyLock(register,json(path.join(repo,'third_party/dependencies.lock.json'))),[]);
 write(path.join(evidence,'package-inventory.json'),manifest);
 write(path.join(evidence,'package-audit.json'),{schema_version:1,rights_integrity_passed:true,actual_combined_replacement_passed:true,model_pins_verified:true,actual_seven_modules_inside_payload:true,exact_editor_portable_repeat:true,observed_editor_portable_replacement_checks_passed:true,observed_source_closure_verified:true,observed_archive_checks_passed:true,runtime_verification:runtime,trace_records_compared:traces[0].length});
 console.log('PASS combined package model/source/notices/full PE+CRT closure and actual replacement loop');
}
const [mode,...args]=process.argv.slice(2);
if(mode==='models')models(...args);else if(mode==='audit')audit(...args);else throw new Error('Expected models or audit');
