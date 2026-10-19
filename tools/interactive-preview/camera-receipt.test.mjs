// Original MIT. Authored synthetic receipts/files; no camera/native execution.
import test from 'node:test';
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {validateCameraReceipt,validateCameraSources,expectedCoverage,cameraSourceGroups,frozenCameraReferences,referenceSHA,apronStartsSupported,apronStartSourcePins} from './camera-receipt.mjs';
const here=path.dirname(fileURLToPath(import.meta.url));
const independentlyBoundApronPins=Object.freeze({
 'native/fdm_jsbsim/interactive/include/flight/interactive/session.hpp':{bytes:4375,sha256:'642fb88d08a794739c4d45ea49fff7a1abbb996c7f550c41716726971c7d8e4c'},
 'native/fdm_jsbsim/interactive/src/session.cpp':{bytes:57564,sha256:'ee113d7ec820f6f577e64d5f6c09d7414bd5b9a2f0070d2ddad04e65fefa0516'},
 'native/godot_bridge/src/interactive_bridge.cpp':{bytes:14213,sha256:'f7b7fa15d5db3c1b6d25f649585136af4627cc97d3fad7dd11c7cdf635b96d37'},
});
const referenceRoot=process.env.FLIGHT_CAMERA_TEST_REFERENCES||path.resolve(here,'../../tests/camera');
const coupled={source_variant:'jsbsim-1.3.1-event-aware-coupled-midpoint-v1',declared_source_fingerprint:'a'.repeat(64)};
const upstream={...coupled,source_variant:'jsbsim-1.3.1-upstream'};
const harnessFiles={'camera_checks.gd':{bytes:10,sha256:'f'.repeat(64)},'camera_checks.tscn':{bytes:11,sha256:'e'.repeat(64)}};
const sourceFiles={'camera/view_policy.gd':{bytes:21,sha256:'b'.repeat(64)}};
function receipt(identity=coupled){
 const child=()=>({passed:true,checks:3,failures:[],scope:'Synthetic validator fixture, not runtime evidence'});
 return {execution:{display_backend:'Windows',capture_observed:true,harness_files:structuredClone(harnessFiles)},schema:'CameraChecks/v1',passed:true,checks:9,failures:[],scope:'Synthetic receipt',reference:{cases:132,sha256:referenceSHA},groups:{policy:child(),panel:child(),scene:{...child(),coverage:expectedCoverage(identity),cold_rejection:identity.source_variant===upstream.source_variant}},source_files:structuredClone(sourceFiles),native_identity:{source_variant:identity.source_variant,source_fingerprint:identity.declared_source_fingerprint}};
}
test('coupled 21 combinations and upstream 14 plus cold rejection have distinct capabilities',()=>{
 assert.deepEqual(validateCameraReceipt(receipt(),{nativeIdentity:coupled,sourceFiles,harnessFiles,requireFullSupported:true}),{checks:9,coverage:21,full_supported:true});
 assert.deepEqual(validateCameraReceipt(receipt(upstream),{nativeIdentity:upstream,sourceFiles,harnessFiles,harnessFiles}),{checks:9,coverage:14,full_supported:false});
 assert.throws(()=>validateCameraReceipt(receipt(upstream),{nativeIdentity:upstream,sourceFiles,harnessFiles,requireFullSupported:true}));
});
const mutants={
 headlessDisplay:r=>r.execution.display_backend='headless',
 missingCapture:r=>r.execution.capture_observed=false,
 missingHarness:r=>delete r.execution.harness_files['camera_checks.gd'],
 wrongHarness:r=>r.execution.harness_files['camera_checks.gd'].sha256='0'.repeat(64),
 extraHarness:r=>r.execution.harness_files['extra.gd']={bytes:1,sha256:'0'.repeat(64)},
 extraExecution:r=>r.execution.fake=true,
 missingScene:r=>delete r.groups.scene,
 zeroPolicy:r=>r.groups.policy.checks=0,
 zeroPanel:r=>r.groups.panel.checks=0,
 zeroScene:r=>r.groups.scene.checks=0,
 failedChild:r=>r.groups.scene.passed=false,
 childFailure:r=>r.groups.panel.failures=['fixture_failure'],
 hostFailure:r=>r.failures=['fixture_failure'],
 wrongTotal:r=>r.checks=132,
 duplicateCoverage:r=>r.groups.scene.coverage[20]=r.groups.scene.coverage[0],
 missingCoverage:r=>r.groups.scene.coverage.pop(),
 extraCoverage:r=>r.groups.scene.coverage.push(r.groups.scene.coverage[0]),
 wrongStart:r=>r.groups.scene.coverage[0].start='invented',
 wrongProfile:r=>r.groups.scene.coverage[0].profile='cessna',
 wrongPreset:r=>r.groups.scene.coverage[0].preset='invented',
 extraCoverageField:r=>r.groups.scene.coverage[0].fake=true,
 falseColdCapability:r=>r.groups.scene.cold_rejection=true,
 staleFingerprint:r=>r.native_identity.source_fingerprint='c'.repeat(64),
 wrongVariant:r=>r.native_identity.source_variant=upstream.source_variant,
 wrongReference:r=>r.reference.sha256='d'.repeat(64),
 wrongReferenceCount:r=>r.reference.cases=131,
 sourceDrift:r=>r.source_files['camera/view_policy.gd'].bytes++,
 extraSource:r=>r.source_files['camera/extra.gd']={bytes:1,sha256:'e'.repeat(64)},
 extraReceiptKey:r=>r.extra=true,
 stringPassed:r=>r.passed='true',
 nonfiniteChecks:r=>r.groups.policy.checks=NaN,
};
for(const [name,mutate] of Object.entries(mutants))test('reject synthetic '+name,()=>{const value=receipt();mutate(value);assert.throws(()=>validateCameraReceipt(value,{nativeIdentity:coupled,sourceFiles,harnessFiles,requireFullSupported:true}));});
test('unknown native backend cannot select its own coverage route',()=>assert.throws(()=>expectedCoverage({...coupled,source_variant:'invented'})));

function stageFixture(){
 const root=fs.mkdtempSync(path.join(os.tmpdir(),'flight-camera-validator-'));
 const repository=path.join(root,'repository'),project=path.join(root,'project'),sourceRoot=path.join(root,'corresponding');
 for(const [authored,mapped,required] of cameraSourceGroups)for(const name of required){
  const raw=authored==='tests/camera'&&Object.hasOwn(frozenCameraReferences,name)?fs.readFileSync(path.join(referenceRoot,name)):Buffer.from('# Authored synthetic staging fixture\nextends RefCounted\n');
  for(const file of [path.join(repository,authored,name),path.join(project,mapped,name),path.join(sourceRoot,mapped,name),path.join(sourceRoot,'repository',authored,name)]){fs.mkdirSync(path.dirname(file),{recursive:true});fs.writeFileSync(file,raw);}
 }
 for(const name of ['camera_checks.gd','camera_checks.tscn'])for(const base of [project,sourceRoot])fs.writeFileSync(path.join(base,name),'# Synthetic generated resource fixture '+name+'\n');
 return {root,repository,project,sourceRoot};
}
function sourceTest(name,change,passes=false){test(name,()=>{const fixture=stageFixture();try{change(fixture);if(passes)assert.equal(Object.keys(validateCameraSources(fixture).source_files).length,10);else assert.throws(()=>validateCameraSources(fixture));}finally{fs.rmSync(fixture.root,{recursive:true,force:true});}});}
sourceTest('exact frozen references and two corresponding copies admit',()=>{},true);
sourceTest('bound import UID only admitted in staged project',f=>fs.writeFileSync(path.join(f.project,'camera/view_policy.gd.uid'),'uid://abc123\n'),true);
sourceTest('missing reference rejects',f=>fs.unlinkSync(path.join(f.project,'camera_tests/expected-v1.json')));
sourceTest('changed staged policy rejects',f=>fs.appendFileSync(path.join(f.project,'camera/view_policy.gd'),'# drift'));
sourceTest('changed original corresponding source rejects',f=>fs.appendFileSync(path.join(f.sourceRoot,'repository/app/camera/view_policy.gd'),'# drift'));
sourceTest('changed mapped corresponding source rejects',f=>fs.appendFileSync(path.join(f.sourceRoot,'ui/camera/views_panel.gd'),'# drift'));
sourceTest('uniformly replaced frozen reference rejects',f=>{for(const file of [path.join(f.repository,'tests/camera/expected-v1.json'),path.join(f.project,'camera_tests/expected-v1.json'),path.join(f.sourceRoot,'camera_tests/expected-v1.json'),path.join(f.sourceRoot,'repository/tests/camera/expected-v1.json')])fs.writeFileSync(file,'{}');});
sourceTest('authored extra script rejects',f=>fs.writeFileSync(path.join(f.repository,'app/camera/extra.gd'),'extends RefCounted'));
sourceTest('unbound imported UID rejects',f=>fs.writeFileSync(path.join(f.project,'camera/unbound.gd.uid'),'uid://abc123\n'));
sourceTest('malformed imported UID rejects',f=>fs.writeFileSync(path.join(f.project,'camera/view_policy.gd.uid'),'not-a-uid'));
sourceTest('generated UID cannot enter corresponding source',f=>fs.writeFileSync(path.join(f.sourceRoot,'camera/view_policy.gd.uid'),'uid://abc123\n'));
sourceTest('source-only transport still must retain its frozen bytes',f=>fs.appendFileSync(path.join(f.repository,'tests/camera/.gitattributes'),'# drift'));

sourceTest('missing generated camera script rejects',f=>fs.unlinkSync(path.join(f.project,'camera_checks.gd')));
sourceTest('missing generated camera scene rejects',f=>fs.unlinkSync(path.join(f.sourceRoot,'camera_checks.tscn')));
sourceTest('changed generated corresponding script rejects',f=>fs.appendFileSync(path.join(f.sourceRoot,'camera_checks.gd'),'# drift'));
sourceTest('malformed root camera UID rejects',f=>fs.writeFileSync(path.join(f.project,'camera_checks.gd.uid'),'invalid'));
sourceTest('root camera UID cannot enter corresponding source',f=>fs.writeFileSync(path.join(f.sourceRoot,'camera_checks.gd.uid'),'uid://abc123\n'));
sourceTest('bound root camera UID admits',f=>fs.writeFileSync(path.join(f.project,'camera_checks.gd.uid'),'uid://abc123\n'),true);

// Explicit synthetic receipt admission cases; these are not compiled identities.
const syntheticNativePaths=["native/fdm_jsbsim/interactive/src/session.cpp","native/fdm_jsbsim/interactive/include/flight/interactive/session.hpp","native/fdm_jsbsim/interactive/include/flight/interactive/surface.hpp","tests/interactive/native.cpp","tests/interactive/negatives.hpp","native/fdm_jsbsim/interactive/src/model-pins.hpp","native/fdm_jsbsim/interactive/src/piston-model-pins.hpp","tests/engine/CMakeLists.txt","tests/engine/loaded-library.hpp","tests/engine/native.cpp","tests/engine/native-mechanism.cpp","tests/engine/native-validate.py","tests/engine/native-generate.py","tests/engine/native-limits.hpp","tests/engine/native-limits.json","native/godot_bridge/src/bridge.cpp","native/godot_bridge/src/codec.hpp","native/godot_bridge/src/codec.cpp","native/godot_bridge/src/worker.hpp","native/godot_bridge/src/worker.cpp","native/godot_bridge/src/interactive_worker.hpp","native/godot_bridge/src/interactive_worker.cpp","native/godot_bridge/src/interactive_bridge.cpp","native/godot_bridge/src/wire_numbers.hpp","native/godot_bridge/src/wire_numbers.cpp"];
function syntheticCurrentIdentity(variant='jsbsim-1.3.1-event-aware-coupled-midpoint-local-window-v2'){
 return {source_variant:variant,declared_source_fingerprint:'a'.repeat(64),source_bindings:syntheticNativePaths.map(name=>{
  const pin=apronStartSourcePins[name];return {path:name,bytes:pin?.bytes??1,raw_sha256:pin?.sha256??'b'.repeat(64),lf_sha256:pin?.sha256??'b'.repeat(64)};
 })};
}
test('current apron gate pins bind actual repository source bytes before synthetic receipts',()=>{
 assert.deepEqual(apronStartSourcePins,independentlyBoundApronPins);
 for(const [name,want] of Object.entries(independentlyBoundApronPins)){
  const raw=fs.readFileSync(path.resolve(here,'../..',name));
  assert.deepEqual({bytes:raw.length,sha256:createHash('sha256').update(raw).digest('hex')},want,name);
 }
});
test('historical/current apron source hybrids cannot enable current camera coverage',()=>{
 const historical={
  'native/fdm_jsbsim/interactive/include/flight/interactive/session.hpp':{bytes:4151,sha256:'40511064929f717e57ed3ff084a3aad0f9af6c406bb50ba74ec1a4fdbe5fcd8f'},
  'native/fdm_jsbsim/interactive/src/session.cpp':{bytes:46016,sha256:'272edf5984dc9205c75f7103546b0312c78ba43f05f416dad929172b8ef6fbeb'},
  'native/godot_bridge/src/interactive_bridge.cpp':{bytes:12768,sha256:'0ebe3a59122368733745f05d82204a2e5a2b9187e985c89bff7b59a6f5e9dcd3'},
 };
 for(let mask=1;mask<8;mask++){
  const identity=syntheticCurrentIdentity();
  Object.entries(historical).forEach(([name,pin],index)=>{
   if(mask&(1<<index))Object.assign(identity.source_bindings.find(row=>row.path===name),{bytes:pin.bytes,raw_sha256:pin.sha256,lf_sha256:pin.sha256});
  });
  assert.throws(()=>expectedCoverage(identity),'Closed current tuple; no historical/hybrid fallback');
  identity.source_variant='jsbsim-1.3.1-upstream';
  assert.equal(apronStartsSupported(identity),false);
 }
});
test('current source-qualified coupled-v1/v2 35 and upstream21 retain all prior rows',()=>{
 for(const [variant,count,cold] of [['jsbsim-1.3.1-event-aware-coupled-midpoint-local-window-v2',35,true],['jsbsim-1.3.1-event-aware-coupled-midpoint-v1',35,true],['jsbsim-1.3.1-upstream',21,false]]){
  const identity=syntheticCurrentIdentity(variant);assert(apronStartsSupported(identity));
  const value=receipt(identity),result=validateCameraReceipt(value,{nativeIdentity:identity,sourceFiles,harnessFiles,requireFullSupported:cold});
  assert.equal(result.coverage,count);assert.equal(result.full_supported,cold);
  assert.equal(value.groups.scene.coverage.filter(row=>row.start==='apron-ready').length,7);
  assert.equal(value.groups.scene.coverage.filter(row=>row.start==='piston-cold-apron').length,cold?7:0);
  const historical=expectedCoverage(cold?coupled:upstream);
  for(const row of historical)assert(value.groups.scene.coverage.some(item=>JSON.stringify(item)===JSON.stringify(row)));
  const missing=structuredClone(value);missing.groups.scene.coverage=historical;
  assert.throws(()=>validateCameraReceipt(missing,{nativeIdentity:identity,sourceFiles,harnessFiles}));
 }
});
test('variant alone and incomplete or changed current recipe source never downgrade full coverage',()=>{
 const mutations=[r=>delete r.source_bindings,r=>r.source_bindings.pop(),r=>r.source_bindings.push(r.source_bindings[0]),r=>r.source_bindings[0].raw_sha256='0'.repeat(64),r=>r.source_bindings[0].lf_sha256='0'.repeat(64),r=>r.source_bindings[0].bytes++,r=>r.source_bindings[1].path=r.source_bindings[0].path,r=>r.source_bindings[0].extra=true,r=>r.source_bindings[0].bytes=true];
 for(const mutate of mutations){const identity=syntheticCurrentIdentity();mutate(identity);assert.throws(()=>expectedCoverage(identity));}
 assert.equal(apronStartsSupported(coupled),false);assert.equal(apronStartsSupported(upstream),false);
 const old=syntheticCurrentIdentity('jsbsim-1.3.1-upstream');old.source_bindings[0].raw_sha256='0'.repeat(64);assert.equal(apronStartsSupported(old),false);assert.equal(expectedCoverage(old).length,14);
});
