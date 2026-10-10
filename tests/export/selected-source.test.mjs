// Source/policy fixtures only. These do not qualify a native DLL or flight.
// Supply the independently reviewed renewed source archive as the sole argument.
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import assert from 'node:assert/strict';
import {fileURLToPath} from 'node:url';
import {selectedLibrary,requireMatchingSelection,verifySelectedArchive,verifyExportSelection,UPSTREAM,COUPLED} from '../../tools/export/selected-source.mjs';
import {sha256} from '../../tools/license-audit/audit.mjs';
const repo=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'../..');
const read=file=>JSON.parse(fs.readFileSync(file,'utf8'));
const register=read(path.join(repo,'third_party/licenses/register.json'));
const archive=process.argv[2];assert(archive,'Require actual reviewed renewed corresponding-source archive');
const native={schema:'PreviewNativeBuildIdentity/v2',source_variant:COUPLED,backend_identity_sha256:'c066b744b180edf04c94ace89edec1d6bdd64018bbcc58d9e630ef0ae3449a6d'};
let checks=0;
const check=(name,action)=>{action();checks++;process.stdout.write('PASS '+name+'\n');};
const reject=(name,action)=>check(name,()=>assert.throws(action));
const selection=selectedLibrary(register,native,repo);
const parent=fs.realpathSync(os.tmpdir()),scratch=fs.mkdtempSync(path.join(parent,'flight-selected-source-'));
const write=(file,value)=>{fs.mkdirSync(path.dirname(file),{recursive:true});fs.writeFileSync(file,JSON.stringify(value,null,2)+'\n');};
try{
 check('reviewed source-derived backend differs from raw identity digest',()=>assert.notEqual(selection.backend_identity_sha256,selection.source_identity.sha256));
 check('coupled receipt has exact twelve common and two extra keys',()=>assert.deepEqual(Object.keys(selection).sort(),['schema','component_id','source_variant','backend_identity_sha256','source_archive_sha256','source_archive_name','modified','source_manifest_schema','bundle_files','vendor_files','unchanged_vendor_files','modified_vendor_files','source_archive_bytes','source_identity'].sort()));
 check('actual renewed archive bytes and hash',()=>verifySelectedArchive(selection,archive));
 reject('historical backend cannot claim renewed delivery',()=>selectedLibrary(register,{...native,backend_identity_sha256:'8f86f63d4f1a23d1f8a09476e72ce391ed0310c8e34751aa080d74c203d7949b'},repo));
 reject('raw identity hash is not the native backend',()=>selectedLibrary(register,{...native,backend_identity_sha256:selection.source_identity.sha256},repo));
 reject('held-power source has no release fallback',()=>selectedLibrary(register,{...native,source_variant:'jsbsim-1.3.1-event-aware-constant-power-v1'},repo));
 reject('unknown source has no release fallback',()=>selectedLibrary(register,{...native,source_variant:'unknown'},repo));
 reject('unqualified native schema rejected',()=>selectedLibrary(register,{...native,schema:'PreviewNativeBuildIdentity/v1'},repo));
 check('pristine selection remains distinct',()=>{
  const pristine=selectedLibrary(register,{...native,source_variant:UPSTREAM},repo);
  assert.equal(pristine.component_id,'jsbsim');assert.equal(pristine.modified,false);assert.equal(pristine.source_manifest_schema,1);assert.equal(pristine.bundle_files,286);assert.equal(pristine.source_identity,undefined);assert.equal(Object.keys(pristine).length,12);
 });
 reject('missing modified ledger cannot fall back to pristine',()=>selectedLibrary({...register,entries:register.entries.filter(e=>e.id!==selection.component_id)},native,repo));
 reject('unknown register release policy cannot select modified source',()=>{const bad=structuredClone(register);bad.entries.find(e=>e.id===selection.component_id).library_policy.release_policy='unreviewed-policy';selectedLibrary(bad,native,repo);});
 reject('archive byte count checked independently of correct hash',()=>verifySelectedArchive({...selection,source_archive_bytes:selection.source_archive_bytes-1},archive));
 reject('old archive pin cannot match renewed source',()=>verifySelectedArchive({...selection,source_archive_sha256:'9b1b9c5bf5da4dd6514c590570486c3920915ea80fcf3a29713f5bac137d3492'},archive));
 reject('selection extra field rejected',()=>requireMatchingSelection(selection,{...selection,unreviewed:true}));
 reject('selection missing field rejected',()=>{const copy=structuredClone(selection);delete copy.source_identity;requireMatchingSelection(selection,copy);});
 const proof=path.join(scratch,'TEST ONLY export metadata');
 const binary=path.join(proof,'payload/bin/JSBSim.dll');fs.mkdirSync(path.dirname(binary),{recursive:true});fs.writeFileSync(binary,'TEST ONLY: no executable module');
 const sourceTarget=path.join(proof,'payload/source',selection.source_archive_name);fs.mkdirSync(path.dirname(sourceTarget),{recursive:true});fs.copyFileSync(archive,sourceTarget);
 const replacement={selected_library:selection,source_variant:selection.source_variant,backend_identity_sha256:selection.backend_identity_sha256,source_archive_sha256:selection.source_archive_sha256,source_archive_bytes:selection.source_archive_bytes,baseline_library_sha256:sha256(fs.readFileSync(binary))};
 const flags=['source_rebuild_passed','other_payload_unchanged','actual_replacement_module_inside_payload','clean_path','unicode_relocation','command_snapshot_schema_passed','finite_state_units_unchanged','worker_joined','reverse_engineering_permitted'];for(const key of flags)replacement[key]=true;
 const auditFile=path.join(proof,'evidence/package-audit.json'),selectionFile=path.join(proof,'evidence/selected-library-release.json'),replacementFile=path.join(proof,'evidence/replacement-evidence.json');
 write(auditFile,{rights_integrity_passed:true,actual_replacement_passed:true,selected_library:selection});write(selectionFile,selection);write(replacementFile,replacement);
 check('matching synthetic metadata binds actual reviewed source archive',()=>verifyExportSelection(selection,proof));
 for(const key of flags){
  reject('missing replacement evidence flag '+key,()=>{const bad={...replacement};delete bad[key];write(replacementFile,bad);verifyExportSelection(selection,proof);});write(replacementFile,replacement);
 }
 for(const [name,mutate] of [
  ['different source variant',r=>r.source_variant=UPSTREAM],
  ['different backend identity',r=>r.backend_identity_sha256='0'.repeat(64)],
  ['wrong actual baseline bytes',r=>r.baseline_library_sha256='0'.repeat(64)],
  ['wrong archive byte count',r=>r.source_archive_bytes--],
  ['incomplete nested selection',r=>delete r.selected_library.source_identity]
 ]){reject(name,()=>{const bad=structuredClone(replacement);mutate(bad);write(replacementFile,bad);verifyExportSelection(selection,proof);});write(replacementFile,replacement);}
 reject('old pristine export receipt cannot qualify coupled delivery',()=>{
  const pristine=selectedLibrary(register,{...native,source_variant:UPSTREAM},repo);write(selectionFile,pristine);verifyExportSelection(selection,proof);
 });write(selectionFile,selection);
 reject('metadata-only baseline success cannot omit actual reviewed archive',()=>{fs.renameSync(sourceTarget,sourceTarget+'.held');try{verifyExportSelection(selection,proof);}finally{fs.renameSync(sourceTarget+'.held',sourceTarget);}});
 process.stdout.write(`PASS ${checks} selected-source policy/source-fixture checks; no native execution or Windows export qualification\n`);
}finally{
 const target=fs.realpathSync(scratch);assert.equal(path.dirname(target),parent);assert(path.basename(target).startsWith('flight-selected-source-'));fs.rmSync(target,{recursive:true,force:true});
}
