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
const piston=register.entries.find(e=>e.id==='original-piston-prop-v1');
function models(source,destination,profile='original-interactive-prototype'){
 assert(['original-interactive-prototype','original-piston-prop-v1'].includes(profile),'Unknown model profile');
 const selected=profile==='original-piston-prop-v1'?piston.content_policy:policy;
 assert.equal(sha(fs.readFileSync(path.join(source,'inventory.json'))),selected.inventory_sha256,'Frozen model inventory changed');
 const inventory=json(path.join(source,'inventory.json'));assert.deepEqual(inventory.files,selected.files);
 if(profile==='original-piston-prop-v1'){
  assert.deepEqual(inventory.metadata,selected.metadata);
  assert(!fs.lstatSync(source).isSymbolicLink(),'Model root alias');
  assert.deepEqual(walk(source).sort(),['inventory.json',...selected.files.map(x=>x.path),...selected.metadata.map(x=>x.path)].sort(),'Exact piston source closure');
 }
 // Validate every file BEFORE copying any payload; metadata is native-pinned.
 const files=[...selected.files,...(selected.metadata??[])];
 for(const pin of files){
  const file=path.join(source,pin.path);
  if(profile==='original-piston-prop-v1')assert(!fs.lstatSync(file).isSymbolicLink()&&fs.realpathSync(file)===file,'Model file alias');
  const bytes=fs.readFileSync(file);assert.equal(bytes.length,pin.bytes);assert.equal(sha(bytes),pin.sha256,'Model XML or metadata changed');
 }
 for(const pin of files){
  const bytes=fs.readFileSync(path.join(source,pin.path));
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
 const pistonPolicy=piston.content_policy;
 assert.equal(sha(fs.readFileSync(path.join(payload,'piston-models/inventory.json'))),pistonPolicy.inventory_sha256);
 for(const pin of [...pistonPolicy.files,...pistonPolicy.metadata]){
  const bytes=fs.readFileSync(path.join(payload,'piston-models',pin.path));assert.equal(bytes.length,pin.bytes);assert.equal(sha(bytes),pin.sha256);
 }
 // Retain accepted vendor/source/notice declarations while replacing current binaries/content and adding authored source.
 const accepted=json(path.join(proof,'evidence/package-inventory.json'));
 const components=accepted.components.filter(c=>c.id!=='original-synthetic').map(c=>({...c,files:c.files.filter(f=>fs.existsSync(path.join(payload,f.path))).map(f=>({...f,sha256:sha(fs.readFileSync(path.join(payload,f.path)))}))}));
 function component(id){let c=components.find(x=>x.id===id);if(!c){const e=register.entries.find(x=>x.id===id);assert(e);c={id,version:e.version,source_revision:e.source.revision,files:[],notices:[]};components.push(c);}return c;}
 function declare(id,file,role){const c=component(id);c.files=c.files.filter(x=>x.path!==file);c.files.push({path:file,sha256:sha(fs.readFileSync(path.join(payload,file))),role});}
 function stage(id,file,value){const dest=path.join(payload,file);write(dest,value);declare(id,file,'evidence');}
 for(const file of walk(payload)){
  if(file.startsWith('models/'))declare(model.id,file,'content');
  else if(file.startsWith('piston-models/'))declare(piston.id,file,'content');
  else if(file.startsWith('source/whole-flight-preview/'))declare('native-export-proof',file,'source');
  else if(file.endsWith('.exe'))declare('godot',file,'binary');
  else if(file.endsWith('.pck')||['launch.ps1','README.md'].includes(file))declare('native-export-proof',file,'content');
  else if(['portable-smoke.log','smoke-receipt.json','loop.records.ndjson'].includes(file))declare('native-export-proof',file,'evidence');
 }
 for(const notice of model.notice_files){const target='notices/'+path.basename(notice.path);fs.copyFileSync(path.join(repo,notice.path),path.join(payload,target));declare(model.id,target,'notice');component(model.id).notices.push({register_path:notice.path,package_path:target});}
 for(const notice of piston.notice_files){const target='notices/'+path.basename(notice.path);fs.copyFileSync(path.join(repo,notice.path),path.join(payload,target));declare(piston.id,target,'notice');component(piston.id).notices.push({register_path:notice.path,package_path:target});}
 stage('microsoft-vc143-crt','evidence/selected-runtime.json',runtime);stage('microsoft-vc143-crt','evidence/native-dependencies.json',dependencies);
 stage('jsbsim','evidence/jsbsim-replacement.json',replacementEvidence);stage('jsbsim','evidence/baseline-modules.json',modules);stage('jsbsim','evidence/replacement-modules.json',replacedModules);
 assert.equal(sha(fs.readFileSync(path.join(payload,'source/jsbsim-1.3.1-library-source.zip'))),register.entries.find(x=>x.id==='jsbsim').library_policy.source_archive_sha256);
 const manifest={schema_version:1,components};
 assert.deepEqual(auditRelease(register,manifest,{repoRoot:repo,packageRoot:payload}),[]);
 assert.deepEqual(auditDependencyLock(register,json(path.join(repo,'third_party/dependencies.lock.json'))),[]);
 write(path.join(evidence,'package-inventory.json'),manifest);
 write(path.join(evidence,'package-audit.json'),{schema_version:1,rights_integrity_passed:true,actual_combined_replacement_passed:true,model_pins_verified:true,actual_seven_modules_inside_payload:true,exact_editor_portable_repeat:true,runtime_verification:runtime,trace_records_compared:traces[0].length});
 console.log('PASS combined package model/source/notices/full PE+CRT closure and actual replacement loop');
}
const [mode,...args]=process.argv.slice(2);
if(mode==='models')models(...args);else if(mode==='audit')audit(...args);else throw new Error('Expected models or audit');
