// Original MIT. Receipt admission only; this module never runs a camera or native worker.
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import {createHash} from 'node:crypto';
import {pathToFileURL} from 'node:url';

export const referenceSHA='d3ee38b2a2455e7a21c61ae46f01461dd901663c3743581059e19c5193f513cd';
export const frozenCameraReferences=Object.freeze({
 '.gitattributes':'a79691a93b46e49ce460c26ef22afcc03d6eca1e63bf2edbc20e96159510f6c9',
 'README.md':'a598e765421507aff4b9476be97f1131c36812d1a3c465b640cd56b102776cf9',
 'expected-v1.json':referenceSHA,
 'generate.py':'bb35c60914aaab18f0226bdbc20e5c0801db9fd6c8c11c42ee93554d3dc0a358',
 'root-ratification-v1.json':'31175acf5717e62df4456bad80a8da9ed3e116c1b0110c28bf6e6112c1f9c9f1',
 'source-binding-v1.json':'c8d817b250ed3e9d31e0ac0bb067fb7d55b2c142f5c667e7d1820c80719740df',
});
export const cameraSourceGroups=Object.freeze([
 ['app/camera','camera',['view_policy.gd']],
 ['app/ui/camera','ui/camera',['views_panel.gd']],
 ['tests/camera','camera_tests',[...Object.keys(frozenCameraReferences),'policy_checks.gd','panel_checks.gd','scene_checks.gd']],
]);
export const presets=Object.freeze(['cockpit','forward_horizon','left_window','right_window','panel','chase','orbit']);
const variants=['jsbsim-1.3.1-upstream','jsbsim-1.3.1-event-aware-constant-power-v1','jsbsim-1.3.1-event-aware-coupled-midpoint-v1','jsbsim-1.3.1-event-aware-coupled-midpoint-local-window-v2'];
const coupled=variant=>variants.slice(2).includes(variant);
const sha=raw=>createHash('sha256').update(raw).digest('hex');
const plain=v=>v!==null&&typeof v==='object'&&!Array.isArray(v)&&Object.getPrototypeOf(v)===Object.prototype;
function keys(v,names,label){assert(plain(v),label+' object');assert.deepEqual(Object.keys(v).sort(),[...names].sort(),label+' closed keys');}
function boundedScope(v){assert.equal(typeof v,'string');assert(v.trim().length>0&&v.length<=1024);}
function ordinary(file){for(let at=path.resolve(file);;at=path.dirname(at)){const st=fs.lstatSync(at);assert(!st.isSymbolicLink(),'No linked source ancestor');assert(st.isFile()||st.isDirectory(),'Ordinary source required');if(path.dirname(at)===at)break;}}
function roster(root){ordinary(root);assert(fs.lstatSync(root).isDirectory());return fs.readdirSync(root,{withFileTypes:true}).map(item=>{assert(item.isFile()&&!item.isSymbolicLink(),'Closed flat camera source group');return item.name;}).sort();}
function sourceIdentity(repository,project){
 const source_files={};
 for(const [authored,mapped,required] of cameraSourceGroups){
  const expected=[...required].sort();assert.deepEqual(roster(path.join(repository,authored)),expected);
  const actual=roster(path.join(project,mapped));
  for(const name of actual.filter(name=>!expected.includes(name))){
   assert(name.endsWith('.gd.uid')&&expected.includes(name.slice(0,-4)),'Only bound imported camera UID allowed');
   const raw=fs.readFileSync(path.join(project,mapped,name));assert(raw.length<=64);assert.match(raw.toString('utf8'),/^uid:\/\/[a-z0-9]{1,20}\r?\n?$/);
  }
  assert.deepEqual(actual.filter(name=>expected.includes(name)),expected);
  for(const name of expected){
   const author=path.join(repository,authored,name),staged=path.join(project,mapped,name);ordinary(author);ordinary(staged);
   const raw=fs.readFileSync(author);assert(raw.length>0);assert(fs.readFileSync(staged).equals(raw),'Exact staged camera bytes');
   if(authored==='tests/camera'&&Object.hasOwn(frozenCameraReferences,name))assert.equal(sha(raw),frozenCameraReferences[name],'Frozen preconsumer reference changed');
   // Godot excludes dotfiles. This exact transport file remains source-only:
   // validated in authoring/project/corresponding copies, never a PCK claim.
   if(!(authored==='tests/camera'&&name==='.gitattributes'))source_files[mapped+'/'+name]={bytes:raw.length,sha256:sha(raw)};
  }
 }
 return source_files;
}
export function validateCameraSources({repository,project,sourceRoot}){
 const source_files=sourceIdentity(repository,project);
 for(const [authored,mapped,required] of cameraSourceGroups){
  assert.deepEqual(roster(path.join(sourceRoot,mapped)),[...required].sort());
  for(const name of required){
   const original=fs.readFileSync(path.join(repository,authored,name));
   for(const target of [path.join(sourceRoot,mapped,name),path.join(sourceRoot,'repository',authored,name)]){ordinary(target);assert(fs.readFileSync(target).equals(original),'Camera corresponding-source byte identity');}
  }
 }
 return {source_files,harness_files:validateCameraHarnessSources(project,sourceRoot)};
}
export function cameraHarnessIdentity(project){
 const result={};
 for(const name of ['camera_checks.gd','camera_checks.tscn']){
  const file=path.join(project,name);ordinary(file);assert(fs.lstatSync(file).isFile());
  const raw=fs.readFileSync(file);assert(raw.length>0&&raw.length<=65536,'Bounded generated camera resource');
  result[name]={bytes:raw.length,sha256:sha(raw)};
 }
 const uid=path.join(project,'camera_checks.gd.uid');
 if(fs.existsSync(uid)){ordinary(uid);const raw=fs.readFileSync(uid);assert(raw.length<=64);assert.match(raw.toString('utf8'),/^uid:\/\/[a-z0-9]{1,20}\r?\n?$/);}
 return result;
}
export function validateCameraHarnessSources(project,sourceRoot){
 const result=cameraHarnessIdentity(project);
 assert(!fs.existsSync(path.join(sourceRoot,'camera_checks.gd.uid')),'Generated camera UID is project-only');
 for(const name of Object.keys(result)){
  const file=path.join(sourceRoot,name);ordinary(file);assert(fs.lstatSync(file).isFile());
  assert(fs.readFileSync(file).equals(fs.readFileSync(path.join(project,name))),'Exact camera generated corresponding source/'+name);
 }
 return result;
}
// The caller supplies native-identity.py's independently qualified build receipt.
// A backend name alone cannot establish that the first-party apron recipes exist.
export const apronStartSourcePins=Object.freeze({"native/fdm_jsbsim/interactive/include/flight/interactive/session.hpp":{"bytes":4151,"sha256":"40511064929f717e57ed3ff084a3aad0f9af6c406bb50ba74ec1a4fdbe5fcd8f"},"native/fdm_jsbsim/interactive/src/session.cpp":{"bytes":46016,"sha256":"272edf5984dc9205c75f7103546b0312c78ba43f05f416dad929172b8ef6fbeb"},"native/godot_bridge/src/interactive_bridge.cpp":{"bytes":12768,"sha256":"0ebe3a59122368733745f05d82204a2e5a2b9187e985c89bff7b59a6f5e9dcd3"}});
const nativeSourcePaths=Object.freeze(["native/fdm_jsbsim/interactive/src/session.cpp","native/fdm_jsbsim/interactive/include/flight/interactive/session.hpp","native/fdm_jsbsim/interactive/include/flight/interactive/surface.hpp","tests/interactive/native.cpp","tests/interactive/negatives.hpp","native/fdm_jsbsim/interactive/src/model-pins.hpp","native/fdm_jsbsim/interactive/src/piston-model-pins.hpp","tests/engine/CMakeLists.txt","tests/engine/loaded-library.hpp","tests/engine/native.cpp","tests/engine/native-mechanism.cpp","tests/engine/native-validate.py","tests/engine/native-generate.py","tests/engine/native-limits.hpp","tests/engine/native-limits.json","native/godot_bridge/src/bridge.cpp","native/godot_bridge/src/codec.hpp","native/godot_bridge/src/codec.cpp","native/godot_bridge/src/worker.hpp","native/godot_bridge/src/worker.cpp","native/godot_bridge/src/interactive_worker.hpp","native/godot_bridge/src/interactive_worker.cpp","native/godot_bridge/src/interactive_bridge.cpp","native/godot_bridge/src/wire_numbers.hpp","native/godot_bridge/src/wire_numbers.cpp"]);
export function apronStartsSupported(nativeIdentity){
 assert(plain(nativeIdentity));assert(variants.includes(nativeIdentity.source_variant));
 if(nativeIdentity.source_bindings===undefined){
  assert.notEqual(nativeIdentity.source_variant,variants[3],'Current local-window delivery requires actual new recipe bindings');
  return false; // Historical upstream/coupled-v1 identities retain old coverage.
 }
 const bindings=nativeIdentity.source_bindings;
 assert(Array.isArray(bindings)&&bindings.length===nativeSourcePaths.length,'Complete qualified native source roster');
 for(let i=0;i<bindings.length;i++){
  const row=bindings[i];keys(row,['path','bytes','raw_sha256','lf_sha256'],'Qualified native source');
  assert.equal(row.path,nativeSourcePaths[i]);assert(Number.isSafeInteger(row.bytes)&&row.bytes>0);
  for(const key of ['raw_sha256','lf_sha256'])assert.match(row[key],/^[a-f0-9]{64}$/);
 }
 const supported=Object.entries(apronStartSourcePins).every(([name,pin])=>{
  const row=bindings.find(item=>item.path===name);
  return row.bytes===pin.bytes&&row.raw_sha256===pin.sha256&&row.lf_sha256===pin.sha256;
 });
 if(nativeIdentity.source_variant===variants[3])assert(supported,'Current local-window delivery cannot fall back to historical camera coverage');
 return supported;
}
export function expectedCoverage(nativeIdentity){
 assert(plain(nativeIdentity));assert(variants.includes(nativeIdentity.source_variant),'Closed actual backend variant');
 assert.match(nativeIdentity.declared_source_fingerprint,/^[a-f0-9]{64}$/);
 const starts=[['original-interactive-prototype','ground-ready'],['original-interactive-prototype','airborne-prepared']];
 if(coupled(nativeIdentity.source_variant))starts.push(['original-piston-prop-v1','piston-cold-ground']);
 if(apronStartsSupported(nativeIdentity)){
  starts.push(['original-interactive-prototype','apron-ready']);
  if(coupled(nativeIdentity.source_variant))starts.push(['original-piston-prop-v1','piston-cold-apron']);
 }
 return starts.flatMap(([profile,start])=>presets.map(preset=>({profile,start,preset})));
}
export function validateCameraReceipt(value,{nativeIdentity,sourceFiles,harnessFiles,requireFullSupported=false}){
 assert.equal(typeof requireFullSupported,'boolean');
 keys(value,['schema','passed','checks','failures','scope','reference','groups','source_files','native_identity','execution'],'Camera receipt');
 assert.equal(value.schema,'CameraChecks/v1');assert.equal(value.passed,true);assert.deepEqual(value.failures,[]);boundedScope(value.scope);
 keys(value.reference,['cases','sha256'],'Camera reference');assert.equal(value.reference.cases,132);assert.equal(value.reference.sha256,referenceSHA);
 keys(value.native_identity,['source_variant','source_fingerprint'],'Camera native identity');
 assert.equal(value.native_identity.source_variant,nativeIdentity.source_variant);assert.equal(value.native_identity.source_fingerprint,nativeIdentity.declared_source_fingerprint);
 assert.deepEqual(value.source_files,sourceFiles,'Actual executed camera resource identities');
 keys(value.groups,['policy','panel','scene'],'Actual camera groups');let checks=0;
 for(const name of ['policy','panel','scene']){
  const group=value.groups[name];keys(group,['passed','checks','failures','scope',...(name==='scene'?['coverage','cold_rejection']:[])],'Camera '+name);
  assert.equal(group.passed,true);assert(Number.isSafeInteger(group.checks)&&group.checks>0,'Actual '+name+' checks required');assert.deepEqual(group.failures,[]);boundedScope(group.scope);
  checks+=group.checks;assert(Number.isSafeInteger(checks));
 }
 assert.equal(value.checks,checks,'Actual child counts, not a fabricated reference count');
 keys(value.execution,['display_backend','capture_observed','harness_files'],'Camera actual graphical execution');
 assert.equal(value.execution.display_backend,'Windows','Windows graphical display required; headless never qualifies');
 assert.equal(value.execution.capture_observed,true,'Actual mouse capture must have been observed');
 keys(harnessFiles,['camera_checks.gd','camera_checks.tscn'],'Expected generated camera harness');
 for(const item of Object.values(harnessFiles)){keys(item,['bytes','sha256'],'Generated resource identity');assert(Number.isSafeInteger(item.bytes)&&item.bytes>0&&item.bytes<=65536);assert.match(item.sha256,/^[a-f0-9]{64}$/);}
 assert.deepEqual(value.execution.harness_files,harnessFiles,'Actual PCK/editor generated harness identity');
 const coverage=value.groups.scene.coverage;assert(Array.isArray(coverage));
 for(const row of coverage){keys(row,['profile','start','preset'],'Actual camera start/view coverage');for(const key of ['profile','start','preset'])assert.equal(typeof row[key],'string');}
 const normalize=rows=>rows.map(row=>JSON.stringify([row.profile,row.start,row.preset])).sort();
 const expected=expectedCoverage(nativeIdentity);assert.deepEqual(normalize(coverage),normalize(expected),'Every actual supported start and preset exactly once');
 assert.equal(value.groups.scene.cold_rejection,!coupled(nativeIdentity.source_variant),'Honest upstream cold-admission rejection');
 if(requireFullSupported)assert(coupled(nativeIdentity.source_variant)&&expected.length===(apronStartsSupported(nativeIdentity)?35:21),'Full delivery requires actual source-qualified supported starts');
 return {checks,coverage:expected.length,full_supported:coupled(nativeIdentity.source_variant)};
}
if(process.argv[1]&&import.meta.url===pathToFileURL(process.argv[1]).href){
 const [mode,receiptPath,repository,project,identityPath,full,...extra]=process.argv.slice(2);assert.equal(mode,'receipt');assert.equal(extra.length,0);assert(['true','false'].includes(full));
 ordinary(receiptPath);const raw=fs.readFileSync(receiptPath);assert(raw.length>0&&raw.length<=1048576,'Bounded camera receipt');
 ordinary(identityPath);const nativeIdentity=JSON.parse(fs.readFileSync(identityPath,'utf8').replace(/^\uFEFF/,''));
 const result=validateCameraReceipt(JSON.parse(raw.toString('utf8').replace(/^\uFEFF/,'')),{nativeIdentity,sourceFiles:sourceIdentity(repository,project),harnessFiles:cameraHarnessIdentity(project),requireFullSupported:full==='true'});
 console.log(JSON.stringify({scope:'Receipt/source admission only; actual runtime and visual qualification remain separate',...result}));
}
