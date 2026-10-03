import fs from 'node:fs';
import path from 'node:path';
import assert from 'node:assert/strict';
import {fileURLToPath} from 'node:url';
import {auditRelease,auditDependencyLock} from '../license-audit/audit.mjs';
import {checkRuntime,checkDependencies,sha,runtimeNames} from './check-runtime.mjs';
const repo=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'../..');
const run=JSON.parse(fs.readFileSync(path.join(repo,'.local/export-proof/latest-run.json'),'utf8'));
assert.equal(run.source_replacement,'passed','Source replacement gate incomplete');
const register=JSON.parse(fs.readFileSync(path.join(repo,'third_party/licenses/register.json'),'utf8'));
const sourceRoot=path.resolve(process.argv[2]);
const sourceEvidence=JSON.parse(fs.readFileSync(path.join(sourceRoot,'source-bundle-evidence.json'),'utf8'));
const sourceArchive=path.join(sourceRoot,'jsbsim-1.3.1-library-source.zip');
const jsb=register.entries.find(e=>e.id==='jsbsim');
assert.equal(sourceEvidence.source_archive_sha256,jsb.library_policy.source_archive_sha256);
assert.equal(sha(fs.readFileSync(sourceArchive)),jsb.library_policy.source_archive_sha256);
const replacement=JSON.parse(fs.readFileSync(path.join(run.evidence,'replacement-evidence.json'),'utf8'));
assert.equal(replacement.source_archive_sha256,jsb.library_policy.source_archive_sha256);
for(const field of ['source_rebuild_passed','other_payload_unchanged','actual_replacement_module_inside_payload','clean_path','unicode_relocation','command_snapshot_schema_passed','finite_state_units_unchanged','worker_joined'])assert.equal(replacement[field],true,field);
const baselineModules=JSON.parse(fs.readFileSync(path.join(run.evidence,'portable-unicode.log.modules.json'),'utf8'));
const replacementModules=JSON.parse(fs.readFileSync(path.join(run.evidence,'replacement.log.modules.json'),'utf8'));
assert.equal(baselineModules.loaded_library_sha256,replacement.baseline_library_sha256);
assert.equal(replacementModules.loaded_library_sha256,replacement.replaced_library_sha256);
for(const report of [baselineModules,replacementModules]) {
 assert.equal(report.actual_library_path_inside_payload,true);
 assert.equal(report.loaded_runtime.length,runtimeNames.length);
}
assert.deepEqual(replacementModules.loaded_runtime,baselineModules.loaded_runtime,'Replacement changed selected CRT module identities');
const payload=run.payload;
const components=new Map();
function component(id){if(!components.has(id)){const entry=register.entries.find(e=>e.id===id);assert(entry);components.set(id,{id,version:entry.version,source_revision:entry.source.revision,files:[],notices:[]});}return components.get(id);}
function declared(id,relative,role){const file=path.join(payload,relative);component(id).files.push({path:relative,sha256:sha(fs.readFileSync(file)),role});}
function stage(id,source,relative,role){const destination=path.join(payload,relative);fs.mkdirSync(path.dirname(destination),{recursive:true});fs.copyFileSync(source,destination);declared(id,relative,role);}
for(const relative of fs.readdirSync(payload)) {
 const file=path.join(payload,relative);
 if(!fs.statSync(file).isFile()||relative==='README.txt')continue;
 if(relative==='flight_godot_bridge.dll'){declared('native-export-proof',relative,'binary');declared('godot-cpp',relative,'binary');}
 else if(relative==='JSBSim.dll')declared('jsbsim',relative,'binary');
 else if(relative.toLowerCase().endsWith('.dll'))declared('microsoft-vc143-crt',relative,'binary');
 else if(relative.endsWith('.pck'))declared('native-export-proof',relative,'content');
 else if(relative.endsWith('.exe'))declared('godot',relative,'binary');
 else throw new Error('Unexpected payload root file '+relative);
}
for(const relative of fs.readdirSync(path.join(payload,'bin'))) {
 if(relative==='flight_godot_bridge.dll'){declared('native-export-proof','bin/'+relative,'binary');declared('godot-cpp','bin/'+relative,'binary');}
 else if(relative==='JSBSim.dll')declared('jsbsim','bin/'+relative,'binary');
 else declared('microsoft-vc143-crt','bin/'+relative,'binary');
}
function walk(root,prefix=''){for(const entry of fs.readdirSync(root,{withFileTypes:true})){const relative=prefix+entry.name;if(entry.isDirectory())walk(path.join(root,entry.name),relative+'/');else declared('prototype-aircraft','models/'+relative,'content');}}
walk(path.join(payload,'models'));
stage('jsbsim',sourceArchive,'source/jsbsim-1.3.1-library-source.zip','source');
stage('jsbsim',path.join(sourceRoot,'source/BUILD.md'),'source/BUILD.md','build-instructions');
stage('jsbsim',path.join(run.evidence,'replacement-evidence.json'),'evidence/jsbsim-replacement.json','evidence');
stage('jsbsim',path.join(run.evidence,'portable-unicode.log.modules.json'),'evidence/baseline-modules.json','evidence');
stage('jsbsim',path.join(run.evidence,'replacement.log.modules.json'),'evidence/replacement-modules.json','evidence');
Object.assign(component('jsbsim'),{linkage:'dynamic',shared_library:'bin/JSBSim.dll',source_archive:'source/jsbsim-1.3.1-library-source.zip',build_instructions:'source/BUILD.md',replacement_test:'evidence/jsbsim-replacement.json',reverse_engineering_permitted:true,modified:false});
const runtimeReport=checkRuntime(JSON.parse(fs.readFileSync(path.join(run.evidence,'selected-crt.json'),'utf8')),fs.readFileSync(path.join(repo,'.local/build/native-release/toolchain-build-manifest.txt'),'utf8'),register.entries.find(e=>e.id==='microsoft-vc143-crt').runtime_policy,{packageRoot:payload});
const runtimeFile=path.join(run.evidence,'runtime-verification.json');fs.writeFileSync(runtimeFile,JSON.stringify(runtimeReport,null,2)+'\n');
stage('microsoft-vc143-crt',runtimeFile,'evidence/selected-runtime.json','evidence');
component('microsoft-vc143-crt').runtime_inventory='evidence/selected-runtime.json';
const dependencyFile=path.join(run.evidence,'native-dependencies.json');
checkDependencies(JSON.parse(fs.readFileSync(dependencyFile,'utf8')),{packageRoot:payload});
stage('microsoft-vc143-crt',dependencyFile,'evidence/native-dependencies.json','evidence');
component('microsoft-vc143-crt').dependency_report='evidence/native-dependencies.json';
for(const [id,entry]of components)for(const notice of register.entries.find(e=>e.id===id).notice_files){
 const relative='notices/'+path.basename(notice.path);stage(id,path.join(repo,notice.path),relative,'notice');entry.notices.push({register_path:notice.path,package_path:relative});
}
const readme='This is an unsigned native integration proof using an original synthetic model. It is not a playable simulator, calibrated aircraft or qualified training device.\nRun flight-proof.exe; no Python/Node/compiler is required at runtime.\nThe JSBSim library is dynamically replaceable. Source/BUILD.md explains rebuild/replacement and LGPL debugging rights.\nMicrosoft components retain their separate Community distributable-code terms. These components are unmodified, supplied only with this application, and not relicensed under MIT. No Microsoft endorsement or warranty is offered by this project; applicable Microsoft component rights and restrictions remain in notices. Distributors must retain those terms and protect those components. LGPL library replacement/debugging rights remain separate.\nThis project is responsible for future app-local CRT servicing; proof packaging does not install a global runtime.\n';
fs.writeFileSync(path.join(payload,'README.txt'),readme);declared('native-export-proof','README.txt','content');
const manifest={schema_version:1,components:[...components.values()]};
const errors=auditRelease(register,manifest,{repoRoot:repo,packageRoot:payload});
errors.push(...auditDependencyLock(register,JSON.parse(fs.readFileSync(path.join(repo,'third_party/dependencies.lock.json'),'utf8'))));
assert.deepEqual(errors,[],'Package rights/integrity audit failed');
const manifestFile=path.join(run.evidence,'package-inventory.json');fs.writeFileSync(manifestFile,JSON.stringify(manifest,null,2)+'\n');
fs.writeFileSync(path.join(run.evidence,'package-audit.json'),JSON.stringify({schema_version:1,rights_integrity_passed:true,runtime_verification:runtimeReport,components:manifest.components.map(c=>c.id),payload_files:manifest.components.reduce((n,c)=>n+c.files.length,0),source_archive_sha256:jsb.library_policy.source_archive_sha256,actual_replacement_passed:true},null,2)+'\n');
console.log('PASS portable proof payload rights, source/replacement and exact selected CRT inventory');
