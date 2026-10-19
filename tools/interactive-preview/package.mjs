import fs from 'node:fs';
import {validateCameraSources,validateCameraReceipt} from './camera-receipt.mjs';
import {variant as localWindowVariant,validateLocalWindowReplayReceipt,validateLocalWindowReplaySources} from './local-window-replay.mjs';
import {validateContract} from '../../schemas/validate.mjs';
import {reproduce as reproduceKawoCatalog} from './world-catalog.mjs';
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
 validateActiveObservedResult(scene.result.observed_review,'Actual native piston observed review');
}
function validateActiveObservedResult(value,label){
 pointerKeys(value,['passed','checks','failures','scope'],label);
 assert.equal(value.passed,true,label+' passed');
 assert(Number.isSafeInteger(value.checks)&&value.checks>0,label+' active checks');
 assert.deepEqual(value.failures,[],label+' no failures');
 assert.equal(typeof value.scope,'string');assert(value.scope.trim().length>0&&value.scope.length<=1024,label+' bounded scope');
 return value.checks;
}
export function validateObservedPistonReceipt(value){
 const names=['archive','panel','recorder'];pointerKeys(value,names,'Observed piston mandatory groups');
 let total=0;
 for(const name of names){total+=validateActiveObservedResult(value[name],'Observed piston/'+name);assert(Number.isSafeInteger(total),'Observed piston aggregate safe integer');}
 return total;
}
export const observedSourceGroups=[['app/replay/observed','replay/observed',['recorder.gd','review.gd','tick_math.gd','values.gd']],['app/ui/debrief/observed','ui/debrief/observed',['panel.gd']],['tests/debrief/observed','observed_tests',['recorder_checks.gd','scene_checks.gd','piston_checks.gd','piston_panel_checks.gd','piston_scene_checks.gd','expected-v1.json','generate.py','preparation-binding-v2.json','root-ratification-v1.json','README.md','.gitattributes']],['app/replay/observed_archive','replay/observed_archive',['codec.gd','strict_json.gd','files.gd','windows_io.ps1']],['tests/debrief/observed_archive','observed_archive_tests',['archive_checks.gd','piston_checks.gd','file_checks.gd','scene_checks.gd','visual_checks.gd','windows_fixture.ps1','generate.py','source-binding-v1.json','root-ratification-v1.json','README.md','.gitattributes','reference/expected-text-v1.json','reference/expected-binary64-v1.json','reference/piston-small.fsreview.json']]];
export function validateObservedSources(repository,project,corresponding){
 for(const [authored,folder,required] of observedSourceGroups){
  const author=path.join(repository,authored),staged=path.join(project,folder),source=path.join(corresponding,folder);
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
 assert.equal(sha(fs.readFileSync(path.join(repository,'tests/debrief/observed/expected-v1.json'))),'a4c3184c46f2eb76c85ff4ba43fc8aac49e772a447576eeec5663fff1ac78844');
 assert.equal(sha(fs.readFileSync(path.join(repository,'tests/debrief/observed_archive/reference/piston-small.fsreview.json'))),'b9b55515115d02b2eb6f4aa9426882b5cbe4633747f4d4e8788b4e5e3223a34b','Frozen small piston reference changed');
 return true;
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
export function stageAcceptedSourceIdentity(payload,acceptedPayload,acceptedLibrary,selection){
 if(selection.modified===false)return null;
 assert.equal(selection.modified,true);assert(['jsbsim-coupled-midpoint-v1','jsbsim-coupled-midpoint-local-window-v2'].includes(selection.component_id),'Closed modified source policy required');
 assert.equal(acceptedLibrary.id,selection.component_id);assert.equal(acceptedLibrary.modified,true);
 assert.equal(acceptedLibrary.source_variant,selection.source_variant);
 const pin=register.entries.find(entry=>entry.id===selection.component_id).library_policy.source_identity;
 assert.deepEqual(selection.source_identity,pin,'Selected source identity policy differs');
 const file=acceptedLibrary.source_identity;
 assert.equal(file,'evidence/jsbsim-coupled-source-identity.json','Accepted source identity evidence path differs');
 const declarations=acceptedLibrary.files.filter(item=>item.path===file);
 assert.equal(declarations.length,1,'Accepted source identity evidence declaration required');
 assert.equal(declarations[0].role,'evidence');assert.equal(declarations[0].sha256,pin.sha256);
 const source=path.join(acceptedPayload,file);ordinaryAncestors(source);
 assert(fs.lstatSync(source).isFile(),'Accepted source identity must be an ordinary file');
 const raw=fs.readFileSync(source),original=fs.readFileSync(path.join(repo,pin.path));
 assert.equal(sha(raw),pin.sha256,'Accepted source identity bytes differ');
 assert.equal(sha(original),pin.sha256,'Repository source identity bytes differ');
 assert(raw.equals(original),'Accepted source identity differs from exact repository bytes');
 ordinaryAncestors(payload);const target=path.join(payload,file);
 fs.mkdirSync(path.dirname(target),{recursive:true});ordinaryAncestors(path.dirname(target));
 if(fs.lstatSync(target,{throwIfNoEntry:false})){ordinaryAncestors(target);assert(fs.readFileSync(target).equals(raw),'Existing staged source identity differs');}
 fs.writeFileSync(target,raw);
 return file;
}
const groundSourcePaths={
 'app/proof/interactive/flight_world.gd':'interactive/flight_world.gd',
 'tests/world/ground-materials/checks.gd':'ground_material_tests/checks.gd',
 'content/aircraft/prototype/ground-presentation.json':'content/aircraft/prototype/ground-presentation.json',
};
export function groundMaterialIdentity(repository){
 const source_files={};
 for(const name of Object.keys(groundSourcePaths)){
  const file=path.join(repository,name);ordinaryAncestors(file);const raw=fs.readFileSync(file);
  source_files[name]={bytes:raw.length,sha256:sha(raw)};
 }
 const text=fs.readFileSync(path.join(repository,'app/proof/interactive/flight_world.gd'),'utf8').replace(/\r\n/g,'\n');
 const shader=text.match(/const GROUND_SHADER := """([\s\S]*?)"""/);assert(shader,'Actual ground shader source missing');
 return {source_files,shader_code_utf8_sha256:sha(Buffer.from(shader[1],'utf8'))};
}
export function validateGroundMaterialReceipt(receipt,expected){
 assert.deepEqual(Object.keys(receipt).sort(),['result','source_files','shader_code_utf8_sha256'].sort());
 assert.deepEqual(Object.keys(receipt.result).sort(),['passed','checks','failures','scope'].sort());
 assert.equal(receipt.result.passed,true);assert.equal(receipt.result.checks,452);
 assert.deepEqual(receipt.result.failures,[]);assert.equal(typeof receipt.result.scope,'string');
 assert(receipt.result.scope.length>0&&receipt.result.scope.length<=1024);
 assert.deepEqual(receipt.source_files,expected.source_files,'Actual ground resource bytes differ');
 assert.equal(receipt.shader_code_utf8_sha256,expected.shader_code_utf8_sha256,'Actual ground shader string differs');
 return receipt.result.checks;
}
export function validateGroundMaterialSources(repository,project,source){
 const expected=groundMaterialIdentity(repository);
 for(const root of [repository,source]){
  const folder=path.join(root,root===repository?'tests/world/ground-materials':'ground_material_tests');
  assert.deepEqual(ordinaryFiles(folder).sort(),['checks.gd'],'Exact ground-material source roster');
 }
 const stagedFolder=path.join(project,'ground_material_tests');const staged=ordinaryFiles(stagedFolder).sort();
 for(const name of staged){
  if(name==='checks.gd')continue;
  assert.equal(name,'checks.gd.uid','Only bound generated ground UID allowed');
  const raw=fs.readFileSync(path.join(stagedFolder,name));assert(raw.length<=64);assert.match(raw.toString('utf8'),/^uid:\/\/[a-z0-9]{1,20}\r?\n?$/);
 }
 assert(staged.includes('checks.gd'));
 for(const [authored,mapped] of Object.entries(groundSourcePaths)){
  for(const root of [project,source]){
   const file=path.join(root,mapped);ordinaryAncestors(file);const raw=fs.readFileSync(file);
   assert.deepEqual({bytes:raw.length,sha256:sha(raw)},expected.source_files[authored],'Ground corresponding source/'+mapped);
  }
 }
 return expected;
}
// Frontend source closure only. Working native storage has a separate aggregate.
export const kawoRuntimeSourceGroups=[
 ['app/world','world',['world_admission.gd'],true],
 ['app/world/terrain','world/terrain',['resident_grid_reader.gd','kawo_world.gd'],false],
 ['app/world/decoration','world/decoration',['kawo_evergreens.gd'],false],
 ['assets_source/environment/original-evergreens-v1/exports','environment/original-evergreens-v1',['tall-narrow-lod1.glb','broad-tiered-lod1.glb','irregular-mature-lod1.glb'],true],
 ['third_party/licenses/notices','notices',['OriginalEvergreens-MIT.txt'],true],
 ['content/world/catalog','content/world/catalog',['kawo-runtime-v1.json'],false],
 ['content/world/airports/kawo/runtime-v1','worlds/kawo-prototype-v1',['world.json','ground.fgrd','airport.json','dossier.json','compile-receipt.json','start-ready34.json','NOTICE.txt'],false],
];
export function validateKawoRuntimeSources(repository,project,source,payload){
 // Reproduce both checked generated catalogs against the same fixed seven-file
 // content. No copied success flag substitutes for this offline source gate.
 const catalog=reproduceKawoCatalog(repository,false),source_files={};
 for(const [name,bytes,digest] of originalEvergreenAssets){
  const file=path.join(repository,'assets_source/environment/original-evergreens-v1/exports',name);ordinaryAncestors(file);
  const raw=fs.readFileSync(file);assert.equal(raw.length,bytes);assert.equal(sha(raw),digest,'Accepted original evergreen LOD1 pin/'+name);
 }
 for(const [authored,mapped,required,selected] of kawoRuntimeSourceGroups){
  const expected=[...required].sort();
  if(!selected){
   const actual=ordinaryFiles(path.join(repository,authored)).filter(name=>!name.endsWith('.gd.uid')).sort();
   assert.deepEqual(actual,expected,'Closed KAWO authored roster/'+authored);
  }
  for(const base of [project,source]){
   if(mapped==='environment/original-evergreens-v1')validateEvergreenImportRecipe(base,base===project);
   if(!selected){
    const actual=ordinaryFiles(path.join(base,mapped));
    for(const name of actual.filter(name=>!expected.includes(name))){
     assert(base===project&&name.endsWith('.gd.uid')&&expected.includes(name.slice(0,-4)),'Only bound staged KAWO script UID allowed');
     const raw=fs.readFileSync(path.join(base,mapped,name));assert(raw.length<=64);assert.match(raw.toString('utf8'),/^uid:\/\/[a-z0-9]{1,20}\r?\n?$/);
    }
    assert.deepEqual(actual.filter(name=>expected.includes(name)).sort(),expected,'Closed KAWO copied roster/'+mapped);
   }
   for(const name of expected){
    const original=path.join(repository,authored,name),actual=path.join(base,mapped,name);
    ordinaryAncestors(original);ordinaryAncestors(actual);
    const raw=fs.readFileSync(original);assert(raw.equals(fs.readFileSync(actual)),'Exact KAWO runtime/corresponding source/'+mapped+'/'+name);
    source_files[authored+'/'+name]={bytes:raw.length,sha256:sha(raw)};
   }
  }
  if(mapped==='worlds/kawo-prototype-v1'){
   assert.deepEqual(ordinaryFiles(path.join(payload,mapped)).sort(),expected,'Closed physical KAWO sibling pack');
   for(const name of expected){const file=path.join(payload,mapped,name);ordinaryAncestors(file);assert(fs.readFileSync(file).equals(fs.readFileSync(path.join(repository,authored,name))),'Physical KAWO pack bytes/'+name);}
   for(const base of [project,source,payload])assert.deepEqual(ordinaryFiles(path.join(base,'worlds')).sort(),expected.map(name=>'kawo-prototype-v1/'+name),'Single admitted physical world directory');
  }
 }
 return {source_files,catalog,scope:'Fixed pack/catalog/renderer and original decorative asset source closure only; actual flight, storage, GPU, hardware and pilot evidence remain separate'};
}
export const originalEvergreenAssets=[
 ['tall-narrow-lod1.glb',70024,'35f8cd9714082054e851550281c6996c67159d46b8a2345737a1b63a93e5299d'],
 ['broad-tiered-lod1.glb',70060,'cc386b8fa59a0e0787430081713d219b9ddfde017fd1fd3c81ed72551db4fdb8'],
 ['irregular-mature-lod1.glb',70060,'0e7c33c239b0d3773023e9fd5aec522392f270b06bd6b3591434d27c56378a7e'],
];
export function validateEvergreenImportRecipe(project,imported=true){
 const names=originalEvergreenAssets.map(([name])=>name);
 const expected=[...names,...(imported?names.map(name=>name+'.import'):[])].sort();
 assert.deepEqual(ordinaryFiles(path.join(project,'environment/original-evergreens-v1')).sort(),expected,'Closed copied evergreen directory');
 if(!imported)return;
 for(const [name] of originalEvergreenAssets){
  const file=path.join(project,'environment/original-evergreens-v1',name+'.import');ordinaryAncestors(file);
  const raw=fs.readFileSync(file);assert(raw.length>0&&raw.length<=65536,'Bounded actual evergreen import recipe');
  const lines=raw.toString('utf8').replaceAll('\r\n','\n').split('\n');
  for(const [key,value] of [['importer','"scene"'],['type','"PackedScene"'],['meshes/generate_lods','false'],['meshes/force_disable_compression','true']]){
   const matching=lines.filter(line=>line.startsWith(key+'='));assert.deepEqual(matching,[key+'='+value],'Fixed evergreen import option/'+key);
  }
 }
}
export function isOriginalEvergreenSourcePath(file){
 return originalEvergreenAssets.some(([name])=>file==='source/whole-flight-preview/environment/original-evergreens-v1/'+name);
}
export function validateKawoPackedResult(value){
 pointerKeys(value,['passed','checks','failures','joined','groups','actual_storage_exercised'],'Actual KAWO packed result');
 assert.equal(value.passed,true);assert.equal(value.joined,true);assert.equal(value.actual_storage_exercised,false);assert.equal(value.checks,86);assert.deepEqual(value.failures,[]);
 pointerKeys(value.groups,['source','scene'],'Closed KAWO actual groups');
 pointerKeys(value.groups.source,['checks','failures'],'KAWO source group');assert.equal(value.groups.source.checks,59);assert.deepEqual(value.groups.source.failures,[]);
 pointerKeys(value.groups.scene,['checks','failures','joined','adoption_diagnostic'],'KAWO Scene group');assert.equal(value.groups.scene.checks,25);assert.deepEqual(value.groups.scene.failures,[]);assert.equal(value.groups.scene.joined,true);pointerKeys(value.groups.scene.adoption_diagnostic,[],'Successful KAWO adoption diagnostic');
 return value.checks;
}
export function validateKawoRawExportAddon(project,source,rows){
 const names=['plugin.cfg','plugin.gd'];assert(Array.isArray(rows));assert.deepEqual(rows.map(row=>row.path),names,'Exact two generated exporter source rows');
 for(const base of [project,source]){
  const folder=path.join(base,'addons/kawo_raw_glbs'),actual=ordinaryFiles(folder);
  for(const extra of actual.filter(name=>!names.includes(name))){
   assert(base===project&&extra==='plugin.gd.uid','Only bound staged exporter UID allowed');
   const raw=fs.readFileSync(path.join(folder,extra));assert(raw.length<=64);assert.match(raw.toString('utf8'),/^uid:\/\/[a-z0-9]{1,20}\r?\n?$/);
  }
  assert.deepEqual(actual.filter(name=>names.includes(name)).sort(),names,'Closed exporter source roster');
  for(const row of rows){
   pointerKeys(row,['path','bytes','sha256'],'Generated exporter pin');assert(Number.isSafeInteger(row.bytes)&&row.bytes>0&&row.bytes<=16384);assert.match(row.sha256,/^[a-f0-9]{64}$/);
   const file=path.join(folder,row.path);ordinaryAncestors(file);const raw=fs.readFileSync(file);assert.equal(raw.length,row.bytes);assert.equal(sha(raw),row.sha256,'Actual/corresponding exporter source bytes');
  }
 }
 return rows;
}
export function stageOriginalEvergreenNotice(repository,payload,entry){
 assert.equal(entry?.id,'original-evergreens-v1');assert.equal(entry.class,'visual-assets');assert.equal(entry.license,'MIT');assert.equal(entry.redistribution,'permitted');
 assert(Array.isArray(entry.notice_files)&&entry.notice_files.length===1);const notice=entry.notice_files[0];
 assert.equal(notice.path,'third_party/licenses/notices/OriginalEvergreens-MIT.txt');
 assert.equal(notice.sha256,'65f8c7cf7043c71c07865ae41a9dbaf0a4938d4aff3c38162bfd3e0c1aa8205f');
 const input=path.join(repository,notice.path);ordinaryAncestors(input);const raw=fs.readFileSync(input);assert.equal(sha(raw),notice.sha256);
 const file='notices/OriginalEvergreens-MIT.txt',target=path.join(payload,file);fs.mkdirSync(path.dirname(target),{recursive:true});ordinaryAncestors(path.dirname(target));
 if(fs.existsSync(target))ordinaryAncestors(target);fs.writeFileSync(target,raw);
 return {file,register_path:notice.path,sha256:sha(raw)};
}
export const localPlayerSourceGroups=[
 ['app/persistence','persistence',['local_players_controller.gd']],
 ['app/ui/profiles','ui/profiles',['player_options.gd','players_panel.gd','player_name_panel.gd']],
 ['app/ui/history','ui/history',['practice_panel.gd','practice_details.gd','player_export_panel.gd','recovery_panel.gd']],
 ['tests/ui/profiles','player_tests',['local_players_ui_checks.gd','local_players_ui_checks_runner.gd','local_players_controller_checks.gd','local_players_scene_checks.gd','local_players_journey_checks.gd','local_players_journey_runner.gd','local_players_journey_first.gd','local_players_journey_resume.gd','local_players_integrated_checks.gd','local_players_integrated_runner.gd']],
];
export function validateLocalPlayerSources(repository,project,source){
 const source_files={};
 for(const [authored,mapped,required] of localPlayerSourceGroups){
  const originals=ordinaryFiles(path.join(repository,authored)).filter(name=>authored!=='app/persistence'||name==='local_players_controller.gd').sort();
  for(const name of required)assert(originals.includes(name),'Required player frontend source/'+name);
  assert.deepEqual(ordinaryFiles(path.join(source,mapped)).sort(),originals,'Player corresponding source roster/'+mapped);
  const staged=ordinaryFiles(path.join(project,mapped));
  for(const name of staged.filter(name=>!originals.includes(name))){
   assert(name.endsWith('.gd.uid')&&originals.includes(name.slice(0,-4)),'Only bound generated player UID allowed');
   const raw=fs.readFileSync(path.join(project,mapped,name));assert(raw.length<=64);assert.match(raw.toString('utf8'),/^uid:\/\/[a-z0-9]{1,20}\r?\n?$/);
  }
  assert.deepEqual(staged.filter(name=>originals.includes(name)).sort(),originals,'Player staged source roster/'+mapped);
  for(const name of originals){
   const raw=fs.readFileSync(path.join(repository,authored,name));
   source_files[authored+'/'+name]={bytes:raw.length,sha256:sha(raw)};
   for(const base of [project,source])assert(fs.readFileSync(path.join(base,mapped,name)).equals(raw),'Player actual corresponding bytes/'+mapped+'/'+name);
  }
 }
 assert(!fs.existsSync(path.join(project,'persistence/local_players.gdextension')),'Flight-only package must not load unqualified production storage');
 return {source_files,named_player_storage_included:false};
}
// ADR020 mandatory source and active checks, independent of piston opt-in.
export const audioSourceGroups=[
 ['app/audio','audio',['audio_cues.gd','audio_options.gd','sample_renderer.gd']],
 ['app/ui/audio','ui/audio',['audio_panel.gd']],
 ['tests/audio','audio_tests',['audio_cues_checks.gd','audio_options_checks.gd','audio_panel_checks.gd','sample_renderer_checks.gd']],
];
export function validateAudioSources(repository,project,source){
 const source_files={};
 for(const [authored,mapped,required] of audioSourceGroups){
  const expected=[...required].sort();
  for(const [base,folder] of [[repository,authored],[source,mapped]])assert.deepEqual(ordinaryFiles(path.join(base,folder)).sort(),expected,'Closed audio source roster/'+folder);
  const staged=ordinaryFiles(path.join(project,mapped));
  for(const name of staged.filter(name=>!expected.includes(name))){
   assert(name.endsWith('.gd.uid')&&expected.includes(name.slice(0,-4)),'Only bound generated audio UID allowed');
   const raw=fs.readFileSync(path.join(project,mapped,name));assert(raw.length<=64);assert.match(raw.toString('utf8'),/^uid:\/\/[a-z0-9]{1,20}\r?\n?$/);
  }
  assert.deepEqual(staged.filter(name=>expected.includes(name)).sort(),expected,'Complete audio staged roster/'+mapped);
  for(const name of expected){
   const relative=authored+'/'+name,raw=fs.readFileSync(path.join(repository,relative));
   source_files[relative]={bytes:raw.length,sha256:sha(raw)};
   for(const base of [project,source])assert(fs.readFileSync(path.join(base,mapped,name)).equals(raw),'Audio actual corresponding bytes/'+mapped+'/'+name);
  }
 }
 // Sound remains in the existing interactive source tree, not a duplicate emitter.
 const sound='app/proof/interactive/flight_sound.gd';ordinaryAncestors(path.join(repository,sound));
 const raw=fs.readFileSync(path.join(repository,sound));source_files[sound]={bytes:raw.length,sha256:sha(raw)};
 for(const base of [project,source]){
  const file=path.join(base,'interactive/flight_sound.gd');ordinaryAncestors(file);
  assert(fs.readFileSync(file).equals(raw),'Actual staged/corresponding Sound differs');
 }
 return {source_files};
}
export function validateAudioSourceDescriptors(groups,sourceFiles){
 assert(Array.isArray(groups)&&groups.length===audioSourceGroups.length,'All three audio source descriptors required');
 const seen=new Set();
 for(const group of groups){
  pointerKeys(group,['source','destination','required','snapshot'],'Audio source descriptor');
  assert.equal(typeof group.source,'string');assert(!seen.has(group.source),'Duplicate audio source descriptor');seen.add(group.source);
  const definition=audioSourceGroups.find(([authored])=>authored===group.source);assert(definition,'Unknown audio source descriptor');
  const [authored,mapped,required]=definition;assert.equal(group.destination,mapped);assert.deepEqual(group.required,required);
  assert(Array.isArray(group.snapshot));assert.equal(group.snapshot.length,required.length);
  assert.deepEqual(group.snapshot.map(file=>file.path),[...required].sort(),'Exact sorted recursive audio snapshot');
  for(const file of group.snapshot){
   pointerKeys(file,['path','bytes','sha256'],'Audio source pin');
   assert.deepEqual({bytes:file.bytes,sha256:file.sha256},sourceFiles[authored+'/'+file.path],'Audio descriptor binds actual authoring bytes');
   assert(Number.isSafeInteger(file.bytes)&&file.bytes>=0);assert.match(file.sha256,/^[a-f0-9]{64}$/);
  }
 }
}
export function isOriginalAudioSourcePath(file){
 return ['source/whole-flight-preview/audio/sample_renderer.gd','source/whole-flight-preview/interactive/flight_sound.gd'].includes(file);
}
export function stageOriginalAudioNotice(repository,payload,entry){
 assert.equal(entry?.id,'original-prototype-audio');assert.equal(entry.class,'audio-assets');assert.equal(entry.license,'MIT');
 assert(Array.isArray(entry.notice_files)&&entry.notice_files.length===1);const notice=entry.notice_files[0];assert.equal(notice.path,'third_party/licenses/notices/FirstParty-Interactive-MIT.txt');
 const source=path.join(repository,notice.path);ordinaryAncestors(source);const raw=fs.readFileSync(source);assert.equal(sha(raw),notice.sha256,'Original audio MIT notice differs');
 const file='notices/Original-Audio-MIT.txt',target=path.join(payload,file);fs.mkdirSync(path.dirname(target),{recursive:true});ordinaryAncestors(path.dirname(target));
 if(fs.existsSync(target))ordinaryAncestors(target);fs.writeFileSync(target,raw);
 return {file,register_path:notice.path,sha256:sha(raw)};
}
export function validateAudioReceipt(value){
 const names=['cues','options','renderer','panel','lifecycle'];pointerKeys(value,names,'Audio mandatory groups');
 let total=0;
 for(const name of names){
  const item=value[name];pointerKeys(item,['passed','checks','failures',...(name==='panel'?['scope']:[])],'Audio result/'+name);
  assert.equal(item.passed,true);assert(Number.isSafeInteger(item.checks)&&item.checks>0,'Active audio checks/'+name);assert.deepEqual(item.failures,[]);
  if(name==='panel'){assert.equal(typeof item.scope,'string');assert(item.scope.trim().length>0&&item.scope.length<=1024,'Bounded audio panel scope');}
  total+=item.checks;assert(Number.isSafeInteger(total),'Audio aggregate safe integer');
 }
 return total;
}
// ADR018 delivery is mandatory; a skipped/partial child cannot admit a player.
export const firstFlightSourceGroups=[
 ['app/ui/first_flight','ui/first_flight',['briefing_panel.gd','binding_help.gd','circuit_guide.gd']],
 ['app/world/synthetic','world/synthetic',['circuit_geometry.gd','taxi-layout-v1.json']],
 ['content/scenarios/first-flight','content/scenarios/first-flight',['briefing.json']],
 ['content/world/synthetic','content/world/synthetic',['practice-circuit.json','taxi-layout-v1.json']],
 ['tests/scenarios/first-flight','scenario_tests/first-flight',['briefing_checks.gd','circuit_checks.gd']],
 ['tests/ui/first_flight','first_flight_ui_tests',['briefing_checks.gd']],
 ['tests/world/synthetic','world_tests/synthetic',['circuit_checks.gd']],
 ['tests/integration/first_flight','first_flight_scene_tests',['scene_checks.gd','map_checks.gd','visual_checks.gd','layout_visual_checks.gd','hud_caption_visual_checks.gd']],
];
const circuitFixtureSHA='2a4540d99d4500e326a1b1f0673583bd6f8ea99d430b991fcca1130befbbddcc';
const taxiLayoutFixtureSHA='d8668af407885949a4eb05fbe170d41fe6c6752d3ce15670f9879a36063d355c';
const circuitCaptureSHA='58b1a7b0ec46161357c1268dbaeeaab27f84bbbd4de70def35571fd45ddb67f9';
const circuitCaptureSource='5e0abfeae9ffd249f8be3f4410d9903f30736698fcb276bdf72f3630132102e5';
const firstFlightNames=['briefing','bindings','geometry','card','map','scene'];
const facadeReceiptKeys=['schema_version','scope','passed','checks','failures','facade','origin','participants','wire','scene','input','input_scene','instruments','cockpit','freeflight','observed','observed_archive','wind','first_flight','audio'];
const firstFlightChoices=[
 {id:'cold-familiarization',start:'piston-cold-ground',model_identity:{id:'original-piston-prop-v1',version:'0.1.0-prototype',backend_model:'original-piston-prop'}},
 {id:'ready-flight',start:'ground-ready',model_identity:{id:'original-interactive-prototype',version:'0.1.0-prototype',backend_model:'original-interactive'}},
 {id:'airborne-orientation',start:'airborne-prepared',model_identity:{id:'original-interactive-prototype',version:'0.1.0-prototype',backend_model:'original-interactive'}},
];
export function validateFirstFlightSources(repository,project,source){
 const source_files={};
 for(const [authored,mapped,required] of firstFlightSourceGroups){
  const expected=[...required].sort();
  const authorExpected=mapped==='world/synthetic'?expected.filter(name=>name!=='taxi-layout-v1.json'):expected;
  assert.deepEqual(ordinaryFiles(path.join(repository,authored)).sort(),authorExpected,'Closed first-flight authoring roster/'+authored);
  assert.deepEqual(ordinaryFiles(path.join(source,mapped)).sort(),expected,'Closed first-flight corresponding roster/'+mapped);
  const staged=ordinaryFiles(path.join(project,mapped));
  for(const name of staged.filter(name=>!expected.includes(name))){
   assert(name.endsWith('.gd.uid')&&expected.includes(name.slice(0,-4)),'Only bound generated first-flight UID allowed');
   const raw=fs.readFileSync(path.join(project,mapped,name));assert(raw.length<=64);assert.match(raw.toString('utf8'),/^uid:\/\/[a-z0-9]{1,20}\r?\n?$/);
  }
  assert.deepEqual(staged.filter(name=>expected.includes(name)).sort(),expected,'Complete first-flight staged roster/'+mapped);
  for(const name of expected){
   const relative=mapped==='world/synthetic'&&name==='taxi-layout-v1.json'?'content/world/synthetic/taxi-layout-v1.json':authored+'/'+name,raw=fs.readFileSync(path.join(repository,relative));
   source_files[relative]={bytes:raw.length,sha256:sha(raw)};
   for(const base of [project,source])assert(fs.readFileSync(path.join(base,mapped,name)).equals(raw),'First-flight actual corresponding bytes/'+mapped+'/'+name);
  }
 }
 assert.equal(source_files['content/world/synthetic/practice-circuit.json'].sha256,circuitFixtureSHA,'Frozen circuit content changed');
 assert.equal(source_files['content/world/synthetic/taxi-layout-v1.json'].sha256,taxiLayoutFixtureSHA,'Frozen taxi layout content changed');
 return {source_files};
}
// ADR027 delivery resources are explicit; source mode alone is not start support.
export const taxiSourceGroups=[
 ['app/world/taxi','world/taxi',['taxi_layout.gd','taxi_navigation.gd']],
 ['app/ui/taxi','ui/taxi',['taxi_panel.gd']],
 ['tests/world/taxi','taxi_tests',['shipping_probe.gd','shipping_observer.gd','pilot_journey.gd','layout_checks.gd','navigation_checks.gd','panel_checks.gd','map_checks.gd','reference/expected-v1.json','reference/generate.py','reference/source-binding-v1.json','reference/README.md','start-reference/expected-v1.json','start-reference/generate.py','start-reference/source-binding-v1.json','start-reference/README.md','start-reference/prop-disk-v1.json','start-reference/generate-prop-disk.py','compatibility-reference/expected-v1.json','compatibility-reference/generate.py','compatibility-reference/source-binding-v1.json','compatibility-reference/README.md']],
 ['tests/integration/taxi','taxi_scene_tests',['scene_checks.gd']],
];
export const taxiStartSourcePins={
 'native/fdm_jsbsim/interactive/include/flight/interactive/session.hpp':'642fb88d08a794739c4d45ea49fff7a1abbb996c7f550c41716726971c7d8e4c',
 'native/fdm_jsbsim/interactive/src/session.cpp':'ee113d7ec820f6f577e64d5f6c09d7414bd5b9a2f0070d2ddad04e65fefa0516',
 'native/godot_bridge/src/interactive_bridge.cpp':'f7b7fa15d5db3c1b6d25f649585136af4627cc97d3fad7dd11c7cdf635b96d37',
};
export const taxiReferencePins={
 "reference/expected-v1.json": "9b9579b18c38ba3c1393af76798fa39b8683229fdf2eff553b1c12e0fd3ae37c",
 "reference/generate.py": "799fbcc5fc2144e713d295559e961d1614e245b7bf2a003135ce1234eedec558",
 "reference/source-binding-v1.json": "1366d0484be3eb6a6ca13028f7f431894d6c879c01dbe2a04f3107a7a7678c8b",
 "reference/README.md": "dd070ab6dcfcd45de6c2dd26129b2402c045cc7eb0b5ebfa6dd2a8ceee81df41",
 "start-reference/expected-v1.json": "fb543ddd1681c3cb040cdfd1c65ff404eb9409e73bb6f613c225a3a501f2e333",
 "start-reference/generate.py": "da0e7b91bd3a3ea7df60f80b01b75df209bc4271950f6458fa462da4efba2645",
 "start-reference/source-binding-v1.json": "5b097ee7c6b727e0f19fe4079913c1e0c4ad6453de9628d01a9bc9588c08c230",
 "start-reference/README.md": "4eb067f2cf2d7bae258984704685578a672be0cae697b6af0b1212bca980eeb6",
 "start-reference/prop-disk-v1.json": "545c0dc04dfa8e5d10eebaef0458dbfb46bb12f53d2d5ab05cf02004bcfe6537",
 "start-reference/generate-prop-disk.py": "dd9aa4014416a2871cb13239fc74c29b1ff21c7d6f26e158ff0ad8bfcc02d8ff",
 "compatibility-reference/expected-v1.json": "0ae22514067840455e4e01fb65cde1c39015e731937ff6971df030ce81a0d811",
 "compatibility-reference/generate.py": "c7dca2b57ef8ed9d7f0922b8abc7916632cffe6adbecadb40b8b2cbefa40a263",
 "compatibility-reference/source-binding-v1.json": "92944cb006c2497211c5dec3fa847e17dd52b6dd46df085c6c8bc7864378603c",
 "compatibility-reference/README.md": "453c91177bb7549b6fb16b30634b7c08fcebd4af79a5c5f2d8e7853a210a35b9"
};
export function taxiStartsSupported(nativeIdentity){
 assert(Array.isArray(nativeIdentity.source_bindings),'Already-qualified actual native source bindings required');
 if(nativeIdentity.source_variant!=='jsbsim-1.3.1-event-aware-coupled-midpoint-local-window-v2')return false;
 return Object.entries(taxiStartSourcePins).every(([name,pin])=>{
  const rows=nativeIdentity.source_bindings.filter(row=>row.path===name);
  return rows.length===1&&rows[0].raw_sha256===pin;
 });
}
export function validateTaxiSources(repository,project,source){
 const source_files={};
 for(const [authored,mapped,required] of taxiSourceGroups){
  const expected=[...required].sort();
  assert.deepEqual(ordinaryFiles(path.join(repository,authored)).sort(),expected,'Closed taxi authoring roster/'+authored);
  // Editor validation runs before the corresponding-source copy exists. Only
  // this exact same-root case uses the staged UID policy below; final package
  // admission always supplies its distinct, UID-free corresponding source.
  if(path.resolve(source)!==path.resolve(project))assert.deepEqual(ordinaryFiles(path.join(source,mapped)).sort(),expected,'Closed taxi corresponding roster/'+mapped);
  const staged=ordinaryFiles(path.join(project,mapped));
  for(const name of staged.filter(name=>!expected.includes(name))){
   assert(name.endsWith('.gd.uid')&&expected.includes(name.slice(0,-4)),'Only already-bound taxi script UID allowed');
   const raw=fs.readFileSync(path.join(project,mapped,name));assert(raw.length<=64);assert.match(raw.toString('utf8'),/^uid:\/\/[a-z0-9]{1,20}\r?\n?$/);
  }
  assert.deepEqual(staged.filter(name=>expected.includes(name)).sort(),expected,'Complete staged taxi roster');
  for(const name of expected){
   const relative=authored+'/'+name,raw=fs.readFileSync(path.join(repository,relative));
   if(authored==='tests/world/taxi'&&Object.hasOwn(taxiReferencePins,name))assert.equal(sha(raw),taxiReferencePins[name],'Frozen taxi independent reference/'+name);
   source_files[relative]={bytes:raw.length,sha256:sha(raw)};
   for(const base of [project,source])assert(fs.readFileSync(path.join(base,mapped,name)).equals(raw),'Exact taxi corresponding bytes/'+mapped+'/'+name);
  }
 }
 const relative='content/world/synthetic/taxi-layout-v1.json',raw=fs.readFileSync(path.join(repository,relative));
 assert.equal(sha(raw),taxiLayoutFixtureSHA,'Frozen original taxi layout');
 source_files[relative]={bytes:raw.length,sha256:sha(raw)};
 for(const base of [project,source])assert(fs.readFileSync(path.join(base,'world/synthetic/taxi-layout-v1.json')).equals(raw),'Composite runtime taxi layout exact bytes');
 const harness=fs.readFileSync(path.join(project,'sim_loop_checks.gd'));
 assert(fs.readFileSync(path.join(source,'sim_loop_checks.gd')).equals(harness),'Taxi generated harness corresponding source');
 return {source_files,harness_file:{path:'sim_loop_checks.gd',bytes:harness.length,sha256:sha(harness)}};
}
export function validateTaxiReceipt(receipt,{nativeIdentity,sourceFiles,harnessFile,requireFullSupported}){
 assert.equal(typeof requireFullSupported,'boolean');
 pointerKeys(receipt,['schema','passed','checks','failures','scope','full_supported','groups','source_files','native_identity','harness_file'],'Taxi receipt');
 assert.equal(receipt.schema,'TaxiNavigationChecks/v1');assert.equal(typeof receipt.passed,'boolean');assert.equal(typeof receipt.full_supported,'boolean');
 assert.equal(typeof receipt.scope,'string');assert(receipt.scope.trim().length>0&&receipt.scope.length<=1024);
 assert(Array.isArray(receipt.failures));assert(Number.isSafeInteger(receipt.checks)&&receipt.checks>0);
 assert.deepEqual(receipt.source_files,sourceFiles,'Actual raw exported taxi resources');
 assert.deepEqual(receipt.harness_file,harnessFile,'Actual exported taxi harness bytes');
 validateResourceReceipt(receipt.native_identity,nativeIdentity.resource);
 pointerKeys(receipt.groups,['layout','panel','map','scene'],'Taxi children');
 let checks=0;
 for(const name of ['layout','panel','map','scene']){
  const child=receipt.groups[name];
  if(name==='scene'&&!receipt.full_supported){assert.equal(child,null,'Unavailable native Scene cannot claim skipped PASS');continue;}
  pointerKeys(child,['passed','checks','failures','scope'],'Taxi child/'+name);
  assert.equal(child.passed,true);assert(Number.isSafeInteger(child.checks)&&child.checks>0);assert.deepEqual(child.failures,[]);
  assert.equal(typeof child.scope,'string');assert(child.scope.trim().length>0&&child.scope.length<=1024);
  checks+=child.checks;assert(Number.isSafeInteger(checks));
 }
 assert.equal(receipt.checks,checks,'Exact actual taxi child aggregate');
 if(requireFullSupported){
  assert(taxiStartsSupported(nativeIdentity),'Mandatory new native start source is absent');
  assert.equal(receipt.full_supported,true);assert.equal(receipt.passed,true);assert.deepEqual(receipt.failures,[]);
 }else{
  assert.equal(receipt.full_supported,false,'Upstream is not full cold/apron qualification');
  assert.equal(receipt.passed,false);assert.deepEqual(receipt.failures,['taxi_full_start_domain_unavailable']);
 }
 return {checks,full_supported:receipt.full_supported};
}

export function validateFirstFlightReceipt(value,includePiston,expectedSourceFingerprint){
 assert.equal(typeof includePiston,'boolean','Actual selected native source mode required');
 assert.equal(typeof expectedSourceFingerprint,'string','Actual selected source fingerprint required');
 assert.match(expectedSourceFingerprint,/^[0-9a-f]{64}$/,'Exact source fingerprint');
 pointerKeys(value,firstFlightNames,'First-flight groups');
 let checks=0;
 for(const name of firstFlightNames){
  const group=value[name];assert(plain(group),'Actual first-flight result required/'+name);
  const diagnostic=Object.hasOwn(group,'scope')?'scope':'limits';
  const extras=name==='geometry'?['fixture_sha256','captured_readback_sha256','baseline_origin','baseline_source_fingerprint']:name==='scene'?['adoptions','include_piston','route_scope']:[];
  pointerKeys(group,['passed','checks','failures',diagnostic,...extras],'First-flight child/'+name);
  assert.equal(group.passed,true);assert(Number.isSafeInteger(group.checks)&&group.checks>0,'Active first-flight count/'+name);assert.deepEqual(group.failures,[]);
  assert.equal(typeof group[diagnostic],'string');assert(group[diagnostic].trim().length>0&&group[diagnostic].length<=1024,'Bounded first-flight scope/'+name);
  checks+=group.checks;assert(Number.isSafeInteger(checks));
 }
 assert.equal(value.geometry.fixture_sha256,circuitFixtureSHA,'Actual circuit fixture receipt pin');
 assert.equal(value.geometry.captured_readback_sha256,circuitCaptureSHA,'Actual original capture receipt pin');
 assert.equal(value.geometry.baseline_origin,expectedSourceFingerprint===circuitCaptureSource?'saved-capture':'observed-native','Selected-source baseline origin');
 assert.equal(value.geometry.baseline_source_fingerprint,expectedSourceFingerprint,'Actual selected-source baseline binding');
 const scene=value.scene;
 assert.equal(scene.include_piston,includePiston,'First-flight scene selected-source mode');
 assert.equal(scene.route_scope,includePiston?'coupled: all six same/cross-profile choices and three advanced confirmations':'upstream: four legacy start mappings, two advanced confirmations and explicit cold admission rejection; cold runtime is not qualified','Honest first-flight route coverage');
 const choices=includePiston?firstFlightChoices:firstFlightChoices.slice(1);
 const oldSources=includePiston?[['original-interactive-prototype','ground-ready'],['original-piston-prop-v1','piston-cold-ground']]:[['original-interactive-prototype','ground-ready'],['original-interactive-prototype','airborne-prepared']];
 const expected=new Map();
 for(const [profile,start] of oldSources)for(const choice of choices)expected.set('immediate_'+profile+'_'+start+'_'+choice.id,choice);
 for(const choice of choices)expected.set('confirmed_'+choice.id,choice);
 expected.set('joined_failure_explicit_recovery',firstFlightChoices[1]);
 assert(Array.isArray(scene.adoptions));assert.equal(scene.adoptions.length,expected.size,'All actual first-flight adoptions required');
 const seen=new Set();
 for(const row of scene.adoptions){
  pointerKeys(row,['label','model_identity','start','tick','pause_attempts','native_calls','completed'],'First-flight adoption');
  assert.equal(typeof row.label,'string');assert(expected.has(row.label)&&!seen.has(row.label),'Missing/unknown/duplicate first-flight mapping');seen.add(row.label);
  const choice=expected.get(row.label);assert.deepEqual(row.model_identity,choice.model_identity,'Exact adopted first-flight profile');assert.equal(row.start,choice.start);assert.equal(row.tick,'0');
  assert(Array.isArray(row.pause_attempts)&&row.pause_attempts.length>0&&row.pause_attempts.length<=128);for(const paused of row.pause_attempts)assert.equal(paused,true,'No hidden first-flight Resume');
  assert(Number.isSafeInteger(row.native_calls)&&row.native_calls>0);assert.equal(row.completed,0);
 }
 return checks;
}
export function validateFirstFlightFacadeAdmission(receipt,includePiston,expectedSourceFingerprint){
 pointerKeys(receipt,facadeReceiptKeys,'Facade receipt');
 pointerKeys(receipt.observed,['piston','recorder','scene'],'Observed mandatory groups');
 validateObservedPistonReceipt(receipt.observed.piston);
 validateAudioReceipt(receipt.audio);
 validateHudCaptionReceipt(receipt.cockpit?.hud_caption);
 return validateFirstFlightReceipt(receipt.first_flight,includePiston,expectedSourceFingerprint);
}
export function validateHudCaptionReceipt(value){
 assert(plain(value),'Mandatory HUD-caption checks');
 pointerKeys(value,['passed','checks','failures','scope'],'HUD-caption result');
 assert.equal(value.passed,true,'HUD-caption checks passed');
 assert(Number.isSafeInteger(value.checks)&&value.checks>0,'Active HUD-caption checks');
 assert.deepEqual(value.failures,[],'No HUD-caption failures');
 assert.equal(typeof value.scope,'string');
 assert(value.scope.trim().length>0&&value.scope.length<=1024,'Bounded HUD-caption scope');
 return value.checks;
}


const originalCockpitAuthoring='assets_source/c172/original-prototype';
const originalCockpitAuthoringNames=['README.md','cockpit-reference-v1.json','cockpit-source.json','generate_cockpit.py','original-cockpit.blend','textures/original-surface-albedo.png','textures/original-surface-roughness.png'].sort();
const originalCockpitRuntimeNames=['original-cockpit.glb','original_asset.gd'].sort();
export function validateOriginalCockpitReceipt(value){
 pointerKeys(value,['schema','checks','failures','passed','baseline_sha256','scope'],'Original cockpit actual import');
 assert.equal(value.schema,'OriginalCockpitActualImportChecks/v1');assert.equal(value.passed,true);
 assert(Number.isSafeInteger(value.checks)&&value.checks>0);assert.deepEqual(value.failures,[]);
 assert.equal(value.baseline_sha256,'fbe01696c09d17042079060739d5599d649e30164727c4a414492c1402a88eba');
 assert.equal(typeof value.scope,'string');assert(value.scope.trim().length>0&&value.scope.length<=1024);
 return value.checks;
}
export function validateOriginalCockpitSources(repository,project,sourceRoot){
 const authored=path.join(repository,originalCockpitAuthoring),copied=path.join(sourceRoot,originalCockpitAuthoring);
 for(const root of [authored,copied])assert.deepEqual(ordinaryFiles(root).sort(),originalCockpitAuthoringNames,'Closed original cockpit corresponding source');
 assert(!fs.existsSync(path.join(project,'assets_source')),'Blender authoring source must stay outside project/PCK');
 for(const file of originalCockpitAuthoringNames)assert(fs.readFileSync(path.join(authored,file)).equals(fs.readFileSync(path.join(copied,file))),'Exact original cockpit authoring source/'+file);
 const runtime=path.join(repository,'app/cockpit/assets');assert.deepEqual(ordinaryFiles(runtime).sort(),originalCockpitRuntimeNames,'Closed authored cockpit runtime leaf');
 assert.deepEqual(ordinaryFiles(path.join(sourceRoot,'cockpit/assets')).sort(),originalCockpitRuntimeNames,'Exact cockpit corresponding runtime source');
 const generated=['original-cockpit.glb.import',...['albedo','roughness'].flatMap(kind=>['original-cockpit_original-surface-'+kind+'.png','original-cockpit_original-surface-'+kind+'.png.import'])].sort();
 const actual=ordinaryFiles(path.join(project,'cockpit/assets')).sort();
 const expected=[...originalCockpitRuntimeNames,...generated];
 if(actual.includes('original_asset.gd.uid')){const raw=fs.readFileSync(path.join(project,'cockpit/assets/original_asset.gd.uid'));assert(raw.length<=64);assert.match(raw.toString('utf8'),/^uid:\/\/[a-z0-9]{1,20}\r?\n?$/);expected.push('original_asset.gd.uid');}
 assert.deepEqual(actual,expected.sort(),'Closed fixed cockpit import output roster');
 for(const file of originalCockpitRuntimeNames)for(const root of [path.join(project,'cockpit/assets'),path.join(sourceRoot,'cockpit/assets')])assert(fs.readFileSync(path.join(runtime,file)).equals(fs.readFileSync(path.join(root,file))),'Exact original cockpit runtime bytes/'+file);
 for(const kind of ['albedo','roughness'])assert(fs.readFileSync(path.join(authored,'textures/original-surface-'+kind+'.png')).equals(fs.readFileSync(path.join(project,'cockpit/assets/original-cockpit_original-surface-'+kind+'.png'))),'Actual extracted original tile bytes/'+kind);
 const provenance=json(path.join(authored,'cockpit-source.json'));
 assert.equal(provenance.schema,'OriginalCockpitSourceGeneration/v1');assert.equal(provenance.license,'MIT');assert.equal(provenance.author,'Flight Simulator contributors');assert.equal(provenance.manufacturer_geometry,false);
 assert.equal(provenance.blender_version,'4.5.14 LTS');assert.equal(provenance.blender_build,'62c1db4208e8');
 assert.equal(provenance.baseline.sha256,'fbe01696c09d17042079060739d5599d649e30164727c4a414492c1402a88eba');
 assert.equal(provenance.reference.sha256,'76a44bb463dfd04a883e4f93f9db81ee6fc0f4c0a2bd004a6c05e8fb64cee57c');
 assert.equal(sha(fs.readFileSync(path.join(authored,'cockpit-reference-v1.json'))),provenance.reference.sha256);
 const gen=fs.readFileSync(path.join(authored,'generate_cockpit.py'));assert.equal(gen.length,provenance.generator.bytes);assert.equal(sha(gen),provenance.generator.sha256);
 assert(Array.isArray(provenance.outputs)&&provenance.outputs.length===4);
 const outputs=[['original-cockpit.blend',path.join(authored,'original-cockpit.blend')],['original-cockpit.glb',path.join(runtime,'original-cockpit.glb')],...['albedo','roughness'].map(kind=>['original-surface-'+kind+'.png',path.join(authored,'textures/original-surface-'+kind+'.png')])];
 for(let i=0;i<outputs.length;i++){const [name,file]=outputs[i],record=provenance.outputs[i];pointerKeys(record,['path','bytes','sha256'],'Original output pin');assert.equal(typeof record.path,'string');assert.equal(path.win32.basename(record.path),name);const raw=fs.readFileSync(file);assert.equal(raw.length,record.bytes);assert.equal(sha(raw),record.sha256);}
 return {authoring_files:originalCockpitAuthoringNames.length,runtime_files:originalCockpitRuntimeNames.length};
}
export function isOriginalCockpitSourcePath(file){
 return file.startsWith('source/whole-flight-preview/'+originalCockpitAuthoring+'/')||originalCockpitRuntimeNames.some(name=>file==='source/whole-flight-preview/cockpit/assets/'+name);
}
export function stageOriginalCockpitNotice(repository,payload,entry){
 assert.equal(entry?.id,'original-prototype-cockpit-v1');assert.equal(entry.class,'visual-assets');assert.equal(entry.license,'MIT');
 assert(Array.isArray(entry.notice_files)&&entry.notice_files.length===1);const notice=entry.notice_files[0];assert.equal(notice.path,'third_party/licenses/notices/FirstParty-Interactive-MIT.txt');
 const source=path.join(repository,notice.path);ordinaryAncestors(source);const raw=fs.readFileSync(source);assert.equal(sha(raw),notice.sha256);
 const file='notices/Original-Cockpit-MIT.txt',target=path.join(payload,file);fs.mkdirSync(path.dirname(target),{recursive:true});ordinaryAncestors(path.dirname(target));if(fs.existsSync(target))ordinaryAncestors(target);fs.writeFileSync(target,raw);return {file,register_path:notice.path,sha256:sha(raw)};
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
 const qualification=spawnSync(python,['-B',path.join(repo,'tools/interactive-preview/native-identity.py'),'--repository-root',repo,'--build-root',build,'--evidence',path.join(evidence,'native-build-identity.json'),'--resident-closure-evidence',path.join(evidence,'resident-world-native-closure-v1.json'),'--staged-root',path.join(root,'project'),'--staged-root',path.join(payload,'source/whole-flight-preview'),'--check-reconstruction-root',path.join(payload,'source/whole-flight-preview')],{encoding:'utf8'});
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
 const pointerEnabled=['jsbsim-1.3.1-event-aware-coupled-midpoint-v1','jsbsim-1.3.1-event-aware-coupled-midpoint-local-window-v2'].includes(nativeIdentity.source_variant);
 const pointerReceipts=[];
 if(pointerEnabled){validatePointerSources(repo,path.join(root,'project'),reconstructionRoot);for(const context of ['editor','portable','replacement'])pointerReceipts.push({context,...validatePointerEvidence(path.join(evidence,context+'-pointer-check-receipt.json'),path.join(evidence,context+'-pointer-flight-trace.json'),repo,path.join(root,'project'),nativeIdentity)});}
 validateOriginalCockpitSources(repo,path.join(root,'project'),reconstructionRoot);
 const audioIdentity=validateAudioSources(repo,path.join(root,'project'),reconstructionRoot);
 validateLocalPlayerSources(repo,path.join(root,'project'),reconstructionRoot);
 const kawoIdentity=validateKawoRuntimeSources(repo,path.join(root,'project'),reconstructionRoot,payload);
 const kawoRawExportAddon=validateKawoRawExportAddon(path.join(root,'project'),reconstructionRoot,json(path.join(evidence,'kawo-raw-export-addon.json')));
 const kawoContexts=['editor','portable','replacement'].map(context=>{const file=path.join(evidence,context+'-kawo-checks.json');ordinaryAncestors(file);const raw=fs.readFileSync(file),result=json(file);validateKawoPackedResult(result);return {context,raw,result};});
 write(path.join(evidence,'kawo-source-closure.json'),{schema:'KawoDeliverySourceClosure/v1',passed:true,...kawoIdentity});
 validateAudioSourceDescriptors(json(path.join(evidence,'audio-source-groups.json')),audioIdentity.source_files);
 const firstFlightIdentity=validateFirstFlightSources(repo,path.join(root,'project'),reconstructionRoot);
 const taxiIdentity=validateTaxiSources(repo,path.join(root,'project'),reconstructionRoot);
 const taxiReceipts=['editor','portable','replacement'].map(context=>{
  const file=path.join(evidence,context+'-taxi-receipt.json');ordinaryAncestors(file);const raw=fs.readFileSync(file);
  const result=validateTaxiReceipt(JSON.parse(raw.toString('utf8')),{nativeIdentity,sourceFiles:taxiIdentity.source_files,harnessFile:taxiIdentity.harness_file,requireFullSupported:pointerEnabled&&nativeIdentity.source_variant===localWindowVariant});
  return {context,raw,...result};
 });
 const groundIdentity=validateGroundMaterialSources(repo,path.join(root,'project'),reconstructionRoot);
 const groundReceipts=['editor','portable','replacement'].map(context=>{
  const file=path.join(evidence,context+'-ground-receipt.json');ordinaryAncestors(file);const raw=fs.readFileSync(file);
  const checks=validateGroundMaterialReceipt(JSON.parse(raw.toString('utf8')),groundIdentity);
  return {context,raw,checks};
 });
 // Current UI drivers must execute in editor, portable and replacement contexts.
 const uiReceipts=['editor','portable','replacement'].map(name=>json(path.join(evidence,name+'-facade-receipt.json')));
 for(const receipt of uiReceipts){
  assert.equal(receipt.passed,true);assert.deepEqual(receipt.failures,[]);
  validateOriginalCockpitReceipt(receipt.cockpit?.asset);
  validateFirstFlightFacadeAdmission(receipt,pointerEnabled,nativeIdentity.declared_source_fingerprint);
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
  assert.deepEqual(Object.keys(receipt.observed).sort(),['piston','recorder','scene'],'All observed groups must execute');
  for(const name of ['recorder','scene']){
   const item=receipt.observed[name];
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
 const pistonEnabled=['jsbsim-1.3.1-event-aware-coupled-midpoint-v1','jsbsim-1.3.1-event-aware-coupled-midpoint-local-window-v2'].includes(nativeIdentity.source_variant);
 const wireCodecContexts=['editor','portable','replacement'].map(context=>({context,checks:validateWireCodecReceipt(json(path.join(evidence,context+'-wire-codec-receipt.json')),pistonEnabled,nativeIdentity.declared_source_fingerprint)}));
 const cameraIdentity=validateCameraSources({repository:repo,project:path.join(root,'project'),sourceRoot:reconstructionRoot});
 const cameraReceipts=['editor','portable','replacement'].map(context=>{
  const file=path.join(evidence,context+'-camera-receipt.json');ordinaryAncestors(file);
  const raw=fs.readFileSync(file);assert(raw.length>0&&raw.length<=1048576);
  const result=validateCameraReceipt(JSON.parse(raw.toString('utf8').replace(/^\uFEFF/,'')),{nativeIdentity,sourceFiles:cameraIdentity.source_files,harnessFiles:cameraIdentity.harness_files,requireFullSupported:pistonEnabled});
  return {context,raw,...result};
 });
 const localWindowReceipts=[];
 if(nativeIdentity.source_variant===localWindowVariant){
  validateLocalWindowReplaySources({repository:repo,project:path.join(root,'project'),sourceRoot:reconstructionRoot,nativeIdentity});
  const recipeBytes=fs.readFileSync(path.join(repo,'tests/engine/local-window-replay/recipe.json'));
  const argumentBytes=fs.readFileSync(path.join(repo,'tests/engine/local-window-replay/argument-binary64.json'));
  for(const [context,contextRoot] of [['editor',path.join(root,'project')],['portable',payload],['replacement',replacement]]){
   const file=path.join(evidence,context+'-local-window-replay-receipt.json');ordinaryAncestors(file);
   const info=fs.lstatSync(file);assert(info.isFile()&&info.size>0&&info.size<=16777216);
   const raw=fs.readFileSync(file),receipt=JSON.parse(raw);
   const result=validateLocalWindowReplayReceipt(receipt,{recipeBytes,argumentBytes,sourceFingerprint:nativeIdentity.declared_source_fingerprint,sourceVariant:nativeIdentity.source_variant,modelRoot:path.join(contextRoot,'piston-models').replaceAll('\\','/'),validateContract});
   localWindowReceipts.push({context,raw,...result});
  }
 }
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
 validateWireCodecSources(repo,path.join(root,'project'),path.join(payload,'source/whole-flight-preview'),nativeIdentity);
 validateObservedSources(repo,path.join(root,'project'),path.join(payload,'source/whole-flight-preview'));
 const windGroups=[['app/world/wind','world/wind',['wind_cue.gd']],['app/ui/wind','ui/wind',['panel.gd']],['tests/world/wind','wind_tests',['wind_checks.gd','ratification-v1.json','reference/expected-v1.json','reference/generate.py','reference/manifest-v1.json','reference/NOTICE-MIT.txt']],['tests/integration/wind','wind_scene_tests',['scene_checks.gd','visual_checks.gd']]];
 for(const [authored,folder,required] of windGroups){
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
 stage('native-export-proof','evidence/kawo-raw-export-addon.json',kawoRawExportAddon);
 for(const item of kawoContexts){const file='evidence/'+item.context+'-kawo-checks.json';fs.writeFileSync(path.join(payload,file),item.raw);declare('native-export-proof',file,'evidence');}
 for(const file of walk(payload)){
  if(file.startsWith('piston-models/')){assert(pistonEnabled);declare(pistonModel.id,file,'content');}
  else if(file.startsWith('source/whole-flight-preview/piston-models/')){assert(pistonEnabled);declare(pistonModel.id,file,'source');}
  else if(file.startsWith('models/'))declare(model.id,file,'content');
  else if(isOriginalCockpitSourcePath(file)){
   for(const owner of components)owner.files=owner.files.filter(item=>item.path!==file);
   declare('original-prototype-cockpit-v1',file,'source');
  }
  else if(isOriginalAudioSourcePath(file)){
   // Move these authored synthesis sources out of the prior aggregate declaration.
   for(const owner of components)owner.files=owner.files.filter(item=>item.path!==file);
   declare('original-prototype-audio',file,'source');
  }
  else if(isOriginalEvergreenSourcePath(file)){
   for(const owner of components)owner.files=owner.files.filter(item=>item.path!==file);
   declare('original-evergreens-v1',file,'source');
  }
  else if(file.startsWith('source/whole-flight-preview/'))declare('native-export-proof',file,'source');
  else if(file.endsWith('.exe'))declare('godot',file,'binary');
  else if(file.endsWith('.pck')||['launch.ps1','README.md'].includes(file))declare('native-export-proof',file,'content');
  else if(['portable-smoke.log','smoke-receipt.json','loop.records.ndjson'].includes(file))declare('native-export-proof',file,'evidence');
 }
 // Source closure above already pins this exact physical seven-file roster.
 // Declare only those files; unknown world directories/files still fail audit.
 for(const [,mapped,names] of kawoRuntimeSourceGroups){
  if(mapped==='worlds/kawo-prototype-v1')for(const name of names)declare('native-export-proof',mapped+'/'+name,'content');
 }
 const cockpitNotice=stageOriginalCockpitNotice(repo,payload,register.entries.find(entry=>entry.id==='original-prototype-cockpit-v1'));
 declare('original-prototype-cockpit-v1',cockpitNotice.file,'notice');
 const cockpitOwner=component('original-prototype-cockpit-v1');cockpitOwner.notices=cockpitOwner.notices.filter(item=>item.register_path!==cockpitNotice.register_path);cockpitOwner.notices.push({register_path:cockpitNotice.register_path,package_path:cockpitNotice.file});
 const audioNotice=stageOriginalAudioNotice(repo,payload,register.entries.find(entry=>entry.id==='original-prototype-audio'));
 declare('original-prototype-audio',audioNotice.file,'notice');
 const audioOwner=component('original-prototype-audio');audioOwner.notices=audioOwner.notices.filter(item=>item.register_path!==audioNotice.register_path);
 audioOwner.notices.push({register_path:audioNotice.register_path,package_path:audioNotice.file});
 const evergreenNotice=stageOriginalEvergreenNotice(repo,payload,register.entries.find(entry=>entry.id==='original-evergreens-v1'));
 declare('original-evergreens-v1',evergreenNotice.file,'notice');
 const evergreenOwner=component('original-evergreens-v1');evergreenOwner.notices=evergreenOwner.notices.filter(item=>item.register_path!==evergreenNotice.register_path);
 evergreenOwner.notices.push({register_path:evergreenNotice.register_path,package_path:evergreenNotice.file});
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
 for(const {context,raw} of groundReceipts){
  const target='evidence/'+context+'-ground-receipt.json';fs.mkdirSync(path.dirname(path.join(payload,target)),{recursive:true});
  fs.writeFileSync(path.join(payload,target),raw);declare('native-export-proof',target,'evidence');
 }
 for(const {context,raw} of pointerReceipts){const target='evidence/'+context+'-pointer-check-receipt.json';fs.mkdirSync(path.dirname(path.join(payload,target)),{recursive:true});fs.writeFileSync(path.join(payload,target),raw);declare('native-export-proof',target,'evidence');}
 for(const {context,raw} of taxiReceipts){const target='evidence/'+context+'-taxi-receipt.json';fs.mkdirSync(path.dirname(path.join(payload,target)),{recursive:true});fs.writeFileSync(path.join(payload,target),raw);declare('native-export-proof',target,'evidence');}
 for(const {context,raw} of cameraReceipts){const target='evidence/'+context+'-camera-receipt.json';fs.mkdirSync(path.dirname(path.join(payload,target)),{recursive:true});fs.writeFileSync(path.join(payload,target),raw);declare('native-export-proof',target,'evidence');}
 for(const {context,raw} of localWindowReceipts){const target='evidence/'+context+'-local-window-replay-receipt.json';fs.mkdirSync(path.dirname(path.join(payload,target)),{recursive:true});fs.writeFileSync(path.join(payload,target),raw);declare('native-export-proof',target,'evidence');}
 stage('microsoft-vc143-crt','evidence/selected-runtime.json',runtime);stage('microsoft-vc143-crt','evidence/native-dependencies.json',dependencies);
 stage(libraryId,'evidence/jsbsim-replacement.json',replacementEvidence);stage(libraryId,'evidence/baseline-modules.json',modules);stage(libraryId,'evidence/replacement-modules.json',replacedModules);
 const sourceIdentity=stageAcceptedSourceIdentity(payload,path.join(proof,'payload'),acceptedLibrary,selection);
 if(sourceIdentity!==null)declare(libraryId,sourceIdentity,'evidence');
 assert.equal(sha(fs.readFileSync(path.join(payload,acceptedLibrary.source_archive))),selection.source_archive_sha256);
 const manifest={schema_version:1,components};
 assert.deepEqual(auditRelease(register,manifest,{repoRoot:repo,packageRoot:payload}),[]);
 assert.deepEqual(auditDependencyLock(register,json(path.join(repo,'third_party/dependencies.lock.json'))),[]);
 write(path.join(evidence,'package-inventory.json'),manifest);
 write(path.join(evidence,'package-audit.json'),{schema_version:1,rights_integrity_passed:true,actual_combined_replacement_passed:true,taxi_full_supported:taxiReceipts.every(row=>row.full_supported),taxi_checks_passed:taxiReceipts.every(row=>row.full_supported),taxi_source_closure_verified:true,taxi_source_files:taxiIdentity.source_files,taxi_harness_file:taxiIdentity.harness_file,taxi_contexts:taxiReceipts.map(({context,raw,checks,full_supported})=>({context,checks,full_supported,bytes:raw.length,sha256:sha(raw)})),camera_checks_passed:true,camera_source_closure_verified:true,camera_source_files:cameraIdentity.source_files,camera_generated_harness:cameraIdentity.harness_files,camera_contexts:cameraReceipts.map(({context,raw,checks,coverage,full_supported})=>({context,checks,coverage,full_supported,bytes:raw.length,sha256:sha(raw)})),wire_codec_checks_passed:true,wire_codec_source_closure_verified:true,wire_codec_contexts:wireCodecContexts,local_window_replay_enabled:nativeIdentity.source_variant===localWindowVariant,...(nativeIdentity.source_variant===localWindowVariant?{local_window_replay_contexts:localWindowReceipts.map(({context,raw,checks,calls,final_tick,continuation_completed,joined})=>({context,checks,calls,final_tick,continuation_completed,joined,bytes:raw.length,sha256:sha(raw)})),local_window_replay_source_closure_verified:true}:{}),model_pins_verified:true,actual_seven_modules_inside_payload:true,exact_editor_portable_repeat:true,observed_editor_portable_replacement_checks_passed:true,observed_source_closure_verified:true,audio_checks_passed:true,audio_source_closure_verified:true,audio_source_files:audioIdentity.source_files,audio_contexts:uiReceipts.map((receipt,index)=>({context:['editor','portable','replacement'][index],checks:validateAudioReceipt(receipt.audio)})),first_flight_checks_passed:true,first_flight_source_closure_verified:true,first_flight_source_files:firstFlightIdentity.source_files,first_flight_contexts:uiReceipts.map((receipt,index)=>({context:['editor','portable','replacement'][index],checks:validateFirstFlightReceipt(receipt.first_flight,pointerEnabled,nativeIdentity.declared_source_fingerprint),route_scope:receipt.first_flight.scene.route_scope})),observed_archive_checks_passed:true,pointer_checks_enabled:pointerEnabled,...(pointerEnabled?{pointer_checks_passed:true,pointer_contexts:pointerReceipts.map(({context,raw,traceRaw,receipt,rows,commands})=>({context,checks:receipt.checks,rows,commands,summary:{bytes:raw.length,sha256:sha(raw)},trace:{path:context+'-pointer-flight-trace.json',bytes:traceRaw.length,sha256:sha(traceRaw)}}))}:{}),ground_material_checks_passed:true,ground_material_contexts:groundReceipts.map(({context,raw,checks})=>({context,checks,bytes:raw.length,sha256:sha(raw)})),...(pistonEnabled?{piston_model_pins_verified:true,piston_editor_portable_replacement_checks_passed:true,piston_contexts:coldReceipts.map(({context,raw,checks})=>({context,checks,bytes:raw.length,sha256:sha(raw)}))}:{}),runtime_verification:runtime,trace_records_compared:traces[0].length,selected_library:selection,native_build_identity:nativeIdentity});
 console.log('PASS combined package model/source/notices/full PE+CRT closure and actual replacement loop');
}

const pointerLimitsSHA='9b667d4b61e47e94af1eed20701119bd72d6de63e6eac28b8597ab44ae6d9feb';
export const pointerSourcePaths={
 'app/input/input_mapper.gd':'input/input_mapper.gd',
 'app/input/input_preset.gd':'input/input_preset.gd',
 'app/cockpit/engine_controls.gd':'cockpit/engine_controls.gd',
 'app/cockpit/instruments/engine_status.gd':'cockpit/instruments/engine_status.gd',
 'app/simulation/flight_scene.gd':'simulation/flight_scene.gd',
 'app/simulation/session_facade.gd':'simulation/session_facade.gd',
 'tests/input/pointer_engine_checks.gd':'input_tests/pointer_engine_checks.gd',
 'tests/cockpit/engine_controls_checks.gd':'cockpit_tests/engine_controls_checks.gd',
 'tests/integration/input/pointer_engine_scene_checks.gd':'pointer_scene_tests/pointer_engine_scene_checks.gd',
 'tests/integration/input/pointer_flight_checks.gd':'pointer_scene_tests/pointer_flight_checks.gd',
 'tests/integration/input/pointer_visual.gd':'pointer_scene_tests/pointer_visual.gd',
 'tests/engine/native-limits.json':'pointer_scene_tests/native-limits.json',
 ...Object.fromEntries(pistonNames.map(name=>['native/fdm_jsbsim/models/original-piston-prop/'+name,'piston-models/'+name])),
 'generated/pointer_checks.gd':'pointer_checks.gd',
};
function pointerKeys(value,keys,label){assert(plain(value),label+' object');assert.deepEqual(Object.keys(value).sort(),[...keys].sort(),label+' closed shape');}
function pointerPass(value,extras=[]){
 pointerKeys(value,['passed','checks','failures','scope',...extras],'Pointer group');
 assert.equal(value.passed,true);assert(Number.isSafeInteger(value.checks)&&value.checks>0);assert.deepEqual(value.failures,[]);
 assert.equal(typeof value.scope,'string');assert(value.scope.trim().length>0&&value.scope.length<=1024);
}
export function pointerSourceIdentity(repository,project){
 const source_files={};
 for(const [authored,mapped] of Object.entries(pointerSourcePaths)){
  const file=path.join(authored.startsWith('generated/')?project:repository,authored.startsWith('generated/')?mapped:authored);
  ordinaryAncestors(file);assert(fs.lstatSync(file).isFile());const raw=fs.readFileSync(file);
  source_files[authored]={bytes:raw.length,sha256:sha(raw)};
 }
 assert.equal(source_files['tests/engine/native-limits.json'].sha256,pointerLimitsSHA,'Frozen original lifecycle limits changed');
 return source_files;
}
export function validatePointerSummary(receipt,sourceFiles,resource){
 pointerKeys(receipt,['schema','passed','checks','failures','scope','groups','source_files','native_identity'],'Pointer receipt');
 assert.equal(receipt.schema,'PointerEngineChecks/v1');assert.equal(receipt.passed,true);assert.deepEqual(receipt.failures,[]);
 assert(Number.isSafeInteger(receipt.checks)&&receipt.checks>0);assert.equal(typeof receipt.scope,'string');assert(receipt.scope.trim().length>0&&receipt.scope.length<=1024);
 assert.deepEqual(receipt.source_files,sourceFiles,'Actual pointer runtime resources differ');validateResourceReceipt(receipt.native_identity,resource);
 pointerKeys(receipt.groups,['mapper','panel','host','flight'],'Pointer mandatory four groups');
 pointerPass(receipt.groups.mapper);pointerPass(receipt.groups.panel);pointerPass(receipt.groups.host,['physical_capture_observed','display_backend']);
 const host=receipt.groups.host;assert.equal(typeof host.display_backend,'string');assert(host.display_backend.length>0&&host.display_backend.length<=64);
 assert.equal(host.physical_capture_observed,host.display_backend!=='headless','Physical capture must remain unobserved on headless');
 const flight=receipt.groups.flight;
 pointerPass(flight,['rows','initialized','native_joined','audio_joined','limits_sha256','first_running_tick','first_stopped_tick','trace']);
 assert.equal(flight.rows,13321);assert.equal(flight.initialized,true);assert.equal(flight.native_joined,true);assert.equal(flight.audio_joined,true);assert.equal(flight.limits_sha256,pointerLimitsSHA);
 for(const name of ['first_running_tick','first_stopped_tick'])assert(Number.isSafeInteger(flight[name])&&flight[name]>=0);
 pointerKeys(flight.trace,['path','bytes','sha256'],'External pointer flight binding');assert.equal(flight.trace.path,'pointer-flight-trace.json');
 assert(Number.isSafeInteger(flight.trace.bytes)&&flight.trace.bytes>0&&flight.trace.bytes<=128*1024*1024);assert.match(flight.trace.sha256,/^[a-f0-9]{64}$/);
 assert.equal(receipt.checks,Object.values(receipt.groups).reduce((sum,item)=>sum+item.checks,0),'Pointer aggregate uses each raw suite count exactly once');
 return receipt.checks;
}
export function validatePointerFlight(trace,summary,limits,fingerprint){
 pointerKeys(trace,['schema','passed','checks','failures','scene_failures','initialized','limits_sha256','initial_readback','first_running_tick','first_stopped_tick','gestures','lever_values','denied','rows','native_joined','audio_joined','scope'],'External pointer flight');
 assert.equal(trace.schema,'PointerEngineFlight/v1');
 for(const key of ['passed','checks','failures','scope','initialized','limits_sha256','first_running_tick','first_stopped_tick','native_joined','audio_joined'])assert.deepEqual(trace[key],summary[key],'Pointer full trace summary/'+key);
 assert.deepEqual(trace.scene_failures,[]);assert(Array.isArray(trace.rows));assert.equal(trace.rows.length,13321);
 const initial=trace.initial_readback;assert(plain(initial));assert.equal(initial.tick,'0');assert.equal(initial.paused,true);assert.equal(initial.native_live,true);assert.equal(initial.native_source_fingerprint,fingerprint);
 assert.deepEqual(initial.model_identity,limits.profile);assert.equal(initial.named_start,'piston-cold-ground');assert.equal(initial.prepared_world_sha256,limits.world_sha256);
 const targets=limits.targets;let nextSequence=1,previousFuel=100,firstRunning=-1,firstStopped=-1,maxCrank=0,maxTaxiSpeed=0,taxiStart=null;
 for(const [index,row] of trace.rows.entries()){
  pointerKeys(row,['tick','wall_us','raw','requested','expected_commands','actual_commands','readback'],'Pointer row');
  const tick=index+1;assert.equal(row.tick,tick);assert.equal(row.wall_us,tick%3===1?8334:8333);
  assert.deepEqual(row.actual_commands,row.expected_commands,'Exact full pointer command arrays/'+tick);
  assert(Array.isArray(row.actual_commands));
  for(const command of row.actual_commands){
   pointerKeys(command,['type','schema_version','tick','session_id','sequence','source_id','authority','assistance','payload'],'Pointer command');
   assert.equal(command.type,'ControlCommand');assert.equal(command.schema_version,1);assert.equal(command.tick,String(tick));assert.equal(command.sequence,String(nextSequence++));assert.equal(command.session_id,initial.session_id);assert.equal(command.source_id,'pilot.controls');assert.equal(command.authority,'pilot');assert.deepEqual(command.assistance,{profile_id:'unassisted',active:[]});
  }
  const state=row.readback;assert(plain(state));assert.equal(state.tick,String(tick));assert.equal(state.session_id,initial.session_id);assert.equal(state.native_live,true);assert.equal(state.paused,false);assert.equal(state.host_mode,'live');assert.equal(state.native_source_fingerprint,fingerprint);assert.equal(state.prepared_world_sha256,initial.prepared_world_sha256);assert.deepEqual(state.model_identity,initial.model_identity);assert.equal(state.debt_quanta,tick%3===1?320:tick%3===2?160:0);
  assert.equal(state.aircraft.tick,String(tick));assert.equal(state.aircraft.session_id,initial.session_id);
  const readings=new Map(state.aircraft.systems.map(item=>[item.id,item]));
  const value=id=>{const item=readings.get(id);assert(item&&item.validity==='valid','Public pointer channel/'+id);return item.value;};
  assert.equal(state.held_axes.throttle,row.requested.requested_axes.throttle);assert.equal(state.held_axes.mixture,row.requested.requested_axes.mixture);
  for(const command of row.actual_commands){
   if(command.payload.kind==='axes')assert.deepEqual(command.payload,state.held_axes,'Full admitted axes reflected in actual publication');
   else{pointerKeys(command.payload,['kind','control_id','value'],'Pointer system payload');assert.equal(command.payload.kind,'system');assert(['engine.ignition_left','engine.ignition_right','engine.starter','fuel.feed'].includes(command.payload.control_id));assert.equal(typeof command.payload.value,'boolean');assert.equal(command.payload.value,value(command.payload.control_id),'Admitted system reflected in actual publication');}
  }
  const shaft=value('propeller.angular_speed'),running=value('engine.running'),fuel=value('fuel.total');assert(Number.isFinite(shaft)&&shaft>=targets.shaft_radps_domain[0]&&shaft<=targets.shaft_radps_domain[1]);assert.equal(typeof running,'boolean');assert(Number.isFinite(fuel)&&fuel>=0&&fuel<=100&&fuel<=previousFuel+targets.fuel_abs_tolerance_kg);previousFuel=fuel;
  if(running&&firstRunning<0)firstRunning=tick;if(tick>=120&&tick<=240)maxCrank=Math.max(maxCrank,shaft);
  if(tick>=960&&tick<=6120){assert.equal(running,true);assert(state.aircraft.contacts.length>0&&state.aircraft.contacts.every(item=>item.on_ground));}
  if(tick>=960&&tick<=3480)assert(shaft>=targets.warm_shaft_radps[0]&&shaft<=targets.warm_shaft_radps[1]);
  if(tick>=961)assert.equal(value('engine.starter'),false);
  const velocity=state.aircraft.velocity_body_mps,speed=Math.hypot(velocity.x,velocity.y,velocity.z);
  if(tick===3480)taxiStart=state.aircraft.ecef_position_m;
  if(tick>=3480&&tick<=4680)maxTaxiSpeed=Math.max(maxTaxiSpeed,speed);
  if(tick===4680){const end=state.aircraft.ecef_position_m;const forward=(end.x-taxiStart.x)*(-Math.sin(.8)*Math.cos(-2))+(end.y-taxiStart.y)*(-Math.sin(.8)*Math.sin(-2))+(end.z-taxiStart.z)*Math.cos(.8);assert(forward>=targets.taxi_forward_distance_min_m&&velocity.x>=targets.taxi_end_forward_speed_min_mps&&maxTaxiSpeed<=targets.taxi_speed_max_mps);}
  if(tick>=4681&&firstStopped<0&&speed<=targets.stopped_speed_max_mps)firstStopped=tick;
  if(tick===6120){assert.equal(running,true);assert(shaft>0);assert.equal(value('fuel.feed'),true);assert.equal(state.held_axes.mixture,1);}
  if(tick===6121){assert.equal(running,false);assert(shaft>0);}
  if(tick===9720)assert(shaft<=targets.coast_60rpm_radps);
  if(tick===13320)assert(shaft<=targets.coast_1rpm_radps);
  if(tick===13321)for(const id of ['fuel.feed','engine.ignition_left','engine.ignition_right'])assert.equal(value(id),false);
 }
 assert.equal(trace.first_running_tick,firstRunning);assert(firstRunning>=0&&firstRunning<=targets.first_running_deadline_s*120);assert(maxCrank>=targets.cranking_min_radps);assert.equal(trace.first_stopped_tick,firstStopped);assert(firstStopped>=0&&firstStopped<=targets.stopped_deadline_s*120);
 assert(Array.isArray(trace.gestures)&&trace.gestures.length>0);assert(Array.isArray(trace.lever_values)&&trace.lever_values.length>0);
 assert.deepEqual(trace.denied.map(item=>item.case),['malformed_Raw','bound_primary']);for(const item of trace.denied){assert.equal(item.paused,true);assert.deepEqual(item.before,item.after,'Denied pointer input admitted no commands/advance');assert.equal(typeof item.problem,'string');assert(item.problem.length>0);}
 return {rows:trace.rows.length,commands:nextSequence-1};
}
export function validatePointerEvidence(receiptFile,traceFile,repository,project,nativeIdentity){
 ordinaryAncestors(receiptFile);ordinaryAncestors(traceFile);
 const raw=fs.readFileSync(receiptFile);assert(raw.length>0&&raw.length<=512*1024,'Bounded pointer summary required');const receipt=JSON.parse(raw.toString('utf8'));
 validatePointerSummary(receipt,pointerSourceIdentity(repository,project),nativeIdentity.resource);
 const traceRaw=fs.readFileSync(traceFile);assert.equal(traceRaw.length,receipt.groups.flight.trace.bytes);assert.equal(sha(traceRaw),receipt.groups.flight.trace.sha256);
 const result=validatePointerFlight(JSON.parse(traceRaw.toString('utf8')),receipt.groups.flight,json(path.join(repository,'tests/engine/native-limits.json')),nativeIdentity.declared_source_fingerprint);
 return {receipt,raw,traceRaw,...result};
}
function validatePointerSources(repository,project,reconstruction){
 for(const [authored,mapped] of Object.entries(pointerSourcePaths)){
  const expected=fs.readFileSync(path.join(authored.startsWith('generated/')?project:repository,authored.startsWith('generated/')?mapped:authored));
  for(const root of [project,reconstruction]){const file=path.join(root,mapped);ordinaryAncestors(file);assert(fs.lstatSync(file).isFile());assert.deepEqual(fs.readFileSync(file),expected,'Pointer staged/corresponding resource/'+mapped);}
 }
 for(const folder of ['cockpit_tests','pointer_scene_tests']){
  const expected=Object.values(pointerSourcePaths).filter(item=>item.startsWith(folder+'/')).map(item=>item.slice(folder.length+1)).sort();
  assert.deepEqual(ordinaryFiles(path.join(reconstruction,folder)).sort(),expected,'Closed pointer corresponding-source roster');
  const files=ordinaryFiles(path.join(project,folder));
  for(const file of files.filter(item=>!expected.includes(item))){assert(file.endsWith('.gd.uid')&&expected.includes(file.slice(0,-4)));const raw=fs.readFileSync(path.join(project,folder,file));assert(raw.length<=64);assert.match(raw.toString('utf8'),/^uid:\/\/[a-z0-9]{1,20}\r?\n?$/);}
  assert.deepEqual(files.filter(item=>expected.includes(item)).sort(),expected);
 }
}


export function validateWireCodecReceipt(receipt,includePiston,expectedFingerprint){
 pointerKeys(receipt,['passed','checks','failures','evidence','scope'],'Wire codec receipt');
 assert.equal(receipt.passed,true);assert(Number.isSafeInteger(receipt.checks)&&receipt.checks>0);assert.deepEqual(receipt.failures,[]);
 assert.equal(typeof receipt.scope,'string');assert(receipt.scope.length>0&&receipt.scope.length<=1024);
 assert(plain(receipt.evidence));
 pointerKeys(receipt.evidence.oracle,['cases','sha256','actual_classdb'],'Wire oracle');
 assert.deepEqual(receipt.evidence.oracle,{cases:49,sha256:'1cab52841eb0cb063d547bf90e7a50f04a1871a5293bdfee4e0a78ddb8940ff6',actual_classdb:true});
 if(includePiston){
  const actual=receipt.evidence.native;
  pointerKeys(actual,['aircraft_json','atmosphere_json','applied_commands_json','events_json','typed_held_axes','source_fingerprint','tick'],'Actual cold wire witness');
  assert.equal(actual.source_fingerprint,expectedFingerprint);assert.equal(actual.tick,'1');
  assert.equal(actual.typed_held_axes.mixture,0.06);assert.equal(actual.typed_held_axes.throttle,0.06);assert.equal(actual.typed_held_axes.trim,-0.06);
  const aircraft=JSON.parse(actual.aircraft_json);assert.equal(aircraft.tick,'1');
  const mixture=aircraft.systems.filter(row=>row.id==='engine.mixture');assert.equal(mixture.length,1);
  assert.equal(mixture[0].value,actual.typed_held_axes.mixture);
  assert.equal(typeof receipt.evidence.actual_mixture_token,'string');assert.equal(Number(receipt.evidence.actual_mixture_token),0.06);
  assert(Array.isArray(actual.applied_commands_json)&&actual.applied_commands_json.length>0);
  assert(Array.isArray(actual.events_json));
  assert(Array.isArray(receipt.evidence.native_calls)&&receipt.evidence.native_calls.at(-1).method==='close');
  assert.equal(receipt.evidence.adjacent_fault.mutated,true);
  assert(Array.isArray(receipt.evidence.adjacent_fault.actual_calls)&&receipt.evidence.adjacent_fault.actual_calls.at(-1).method==='close');
 }else{
  assert.equal(typeof receipt.evidence.native_witness,'string');assert(receipt.evidence.native_witness.length>0);
  assert(!Object.hasOwn(receipt.evidence,'native'),'No cold qualification in upstream codec receipt');
 }
 return receipt.checks;
}
export function validateWireCodecSources(repository,project,source,nativeIdentity){
 const definitions=[['tests/wire_codec/checks.gd','wire_codec_tests/checks.gd'],['docs/evidence/P2/native-wire-number-reference.json','wire_codec_tests/reference.json']];
 for(const [authored,mapped] of definitions){
  const original=path.join(repository,authored);ordinaryAncestors(original);
  const bytes=fs.readFileSync(original);
  for(const base of [project,source]){const file=path.join(base,mapped);ordinaryAncestors(file);assert(fs.readFileSync(file).equals(bytes),'Exact wire resource/'+mapped);}
 }
 assert.equal(sha(fs.readFileSync(path.join(project,'wire_codec_tests/reference.json'))),'1cab52841eb0cb063d547bf90e7a50f04a1871a5293bdfee4e0a78ddb8940ff6');
 const expected=['checks.gd','reference.json'];
 assert.deepEqual(ordinaryFiles(path.join(source,'wire_codec_tests')).sort(),expected);
 const staged=ordinaryFiles(path.join(project,'wire_codec_tests'));
 for(const file of staged.filter(file=>!expected.includes(file))){
  assert.equal(file,'checks.gd.uid');const raw=fs.readFileSync(path.join(project,'wire_codec_tests',file));assert(raw.length<=64);assert.match(raw.toString('utf8'),/^uid:\/\/[a-z0-9]{1,20}\r?\n?$/);
 }
 assert.deepEqual(staged.filter(file=>expected.includes(file)).sort(),expected);
 const authors=ordinaryFiles(path.join(repository,'tests/wire_codec')).sort();
 assert.deepEqual(ordinaryFiles(path.join(source,'tests/wire_codec')).sort(),authors);
 for(const file of authors)assert(fs.readFileSync(path.join(repository,'tests/wire_codec',file)).equals(fs.readFileSync(path.join(source,'tests/wire_codec',file))),'Exact corresponding wire test source/'+file);
 for(const [file,pin] of [['native-wire-number-reference.py','3783367f8bc110c8f4122187083aeef0e7ef8db49ec27c93b2a67732b65430d1'],['native-wire-number-reference.json','1cab52841eb0cb063d547bf90e7a50f04a1871a5293bdfee4e0a78ddb8940ff6']]){
  const relative='docs/evidence/P2/'+file;
  for(const base of [repository,source]){const artifact=path.join(base,relative);ordinaryAncestors(artifact);assert.equal(sha(fs.readFileSync(artifact)),pin,'Frozen numeric reference and corresponding generator/'+file);}
 }
 for(const name of ['native/godot_bridge/src/wire_numbers.hpp','native/godot_bridge/src/wire_numbers.cpp','native/godot_bridge/src/bridge.cpp']){
  const binding=nativeIdentity.source_bindings.find(row=>row.path===name);assert(binding,'Numeric helper/registration must enter actual native fingerprint');
  assert.equal(binding.lf_sha256,sha(fs.readFileSync(path.join(repository,name)).toString('utf8').replaceAll('\r\n','\n')));
 }
}

const [mode,...args]=process.argv.slice(2);
if(process.argv[1]&&path.resolve(process.argv[1])===fileURLToPath(import.meta.url)){
if(mode==='kawo-packed-receipt'){assert.equal(args.length,1);ordinaryAncestors(args[0]);validateKawoPackedResult(json(args[0]));console.log('PASS actual KAWO source59/Scene25/host86 joined result');}else
if(mode==='models')models(...args);else if(mode==='audit')audit(...args);else if(mode==='pointer-receipt'){assert.equal(args.length,5);validatePointerEvidence(args[0],args[1],args[2],args[3],json(args[4]));console.log('PASS actual pointer four-suite receipt/external trace/source/native identity');}else if(mode==='taxi-receipt'){assert.equal(args.length,6);assert(['true','false'].includes(args[5]));const identity=json(args[4]);const sources=validateTaxiSources(args[1],args[2],args[3]);ordinaryAncestors(args[0]);validateTaxiReceipt(json(args[0]),{nativeIdentity:identity,sourceFiles:sources.source_files,harnessFile:sources.harness_file,requireFullSupported:args[5]==='true'});console.log('PASS actual taxi resources/source and explicit full-start scope');}else if(mode==='ground-receipt'){assert.equal(args.length,2);ordinaryAncestors(args[0]);validateGroundMaterialReceipt(json(args[0]),groundMaterialIdentity(args[1]));console.log('PASS actual ground-material receipt/source identity');}else throw new Error('Expected models, audit or ground-receipt');
}
