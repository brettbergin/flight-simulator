import fs from 'node:fs';
import path from 'node:path';
import assert from 'node:assert/strict';
import {fileURLToPath} from 'node:url';
import {auditRegister,sha256} from '../license-audit/audit.mjs';

export const UPSTREAM='jsbsim-1.3.1-upstream';
export const COUPLED='jsbsim-1.3.1-event-aware-coupled-midpoint-v1';
const POLICY='jsbsim-coupled-midpoint-v1';
const canonical=value=>Array.isArray(value)?value.map(canonical):value&&typeof value==='object'?Object.fromEntries(Object.keys(value).sort().map(key=>[key,canonical(value[key])])):value;
const json=file=>JSON.parse(fs.readFileSync(file,'utf8').replace(/^\uFEFF/,''));

// The source selector hashes this closed backend object. Reproduce its Python
// sort_keys/separators encoding rather than accepting a release's asserted hash.
export function coupledBackend(identity,raw){
 const verification={schema_version:3,source_variant:identity.source_variant,bundle_files:identity.bundle_files,vendor_files:identity.vendor_files,unchanged_vendor_files:identity.vendor_files-identity.modified_vendor_files,modified_vendor_files:identity.modified_vendor_files,provenance_reconstructed:true,recipe_sha256:identity.recipe_sha256,vendor_tree_sha256:identity.vendor_tree_sha256,materializer_sha256:identity.materializer_sha256};
 return sha256(JSON.stringify(canonical({schema_version:1,identity_file_sha256:sha256(raw),identity,verification})));
}

// Callers must first obtain the independently qualified ADR016 build identity.
// This binds that build to the separately reviewed release policy/source pin.
export function selectedLibrary(register,nativeIdentity,repoRoot){
 assert.deepEqual(auditRegister(register,{repoRoot}),[],'Selected source rights register rejected');
 assert.equal(nativeIdentity.schema,'PreviewNativeBuildIdentity/v2');
 assert.match(nativeIdentity.backend_identity_sha256,/^[a-f0-9]{64}$/);
 const variant=nativeIdentity.source_variant;
 assert([UPSTREAM,COUPLED].includes(variant),'No release policy for selected source variant');
 const id=variant===UPSTREAM?'jsbsim':POLICY;
 const entry=register.entries.find(item=>item.id===id);assert(entry,'Selected source ledger missing');
 const policy=entry.library_policy;
 const result={schema:'SelectedLibraryRelease/v1',component_id:id,source_variant:variant,backend_identity_sha256:nativeIdentity.backend_identity_sha256,source_archive_sha256:policy.source_archive_sha256,source_archive_name:variant===UPSTREAM?'jsbsim-1.3.1-library-source.zip':COUPLED+'-library-source.zip',modified:variant===COUPLED};
 if(variant===COUPLED){
  assert.equal(policy.release_policy,POLICY);
  const raw=fs.readFileSync(path.join(repoRoot,policy.source_identity.path));
  assert.equal(sha256(raw),policy.source_identity.sha256);
  const identity=JSON.parse(raw);
  assert.equal(identity.source_variant,COUPLED);
  assert.equal(identity.source_archive_sha256,policy.source_archive_sha256);
  assert.equal(coupledBackend(identity,raw),nativeIdentity.backend_identity_sha256,'Selected native backend differs from renewed source');
  Object.assign(result,{source_archive_bytes:identity.source_archive_bytes,source_identity:policy.source_identity,source_manifest_schema:3,bundle_files:293,vendor_files:279,unchanged_vendor_files:275,modified_vendor_files:4});
 }else{
  assert.equal(policy.release_policy,undefined,'Pristine policy changed');
  Object.assign(result,{source_manifest_schema:1,bundle_files:286,vendor_files:279,unchanged_vendor_files:279,modified_vendor_files:0});
 }
 return result;
}

export function requireMatchingSelection(expected,actual){
 assert.deepEqual(actual,expected,'Selected source export/replacement provenance differs');
}

export function verifySelectedArchive(selection,archive){
 const raw=fs.readFileSync(archive);
 assert.equal(sha256(raw),selection.source_archive_sha256,'Selected source archive differs');
 if(selection.modified)assert.equal(raw.length,selection.source_archive_bytes,'Selected source archive size differs');
}

export function verifyExportSelection(selection,proofRoot){
 const audit=json(path.join(proofRoot,'evidence/package-audit.json'));
 assert.equal(audit.rights_integrity_passed,true);assert.equal(audit.actual_replacement_passed,true);
 requireMatchingSelection(selection,audit.selected_library);
 requireMatchingSelection(selection,json(path.join(proofRoot,'evidence/selected-library-release.json')));
 const replacement=json(path.join(proofRoot,'evidence/replacement-evidence.json'));
 for(const key of ['source_rebuild_passed','other_payload_unchanged','actual_replacement_module_inside_payload','clean_path','unicode_relocation','command_snapshot_schema_passed','finite_state_units_unchanged','worker_joined','reverse_engineering_permitted'])assert.equal(replacement[key],true,'Matching export replacement gate: '+key);
 requireMatchingSelection(selection,replacement.selected_library);
 assert.equal(replacement.source_variant,selection.source_variant);
 assert.equal(replacement.backend_identity_sha256,selection.backend_identity_sha256);
 assert.equal(replacement.source_archive_sha256,selection.source_archive_sha256);
 if(selection.modified)assert.equal(replacement.source_archive_bytes,selection.source_archive_bytes);
 assert.equal(replacement.baseline_library_sha256,sha256(fs.readFileSync(path.join(proofRoot,'payload/bin/JSBSim.dll'))));
 verifySelectedArchive(selection,path.join(proofRoot,'payload/source',selection.source_archive_name));
}

const repo=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'../..');
if(process.argv[1]&&path.resolve(process.argv[1])===fileURLToPath(import.meta.url)){
 const [mode,identityFile,proofRoot]=process.argv.slice(2);assert(['build','match-export'].includes(mode));assert(identityFile);
 const register=json(path.join(repo,'third_party/licenses/register.json'));
 const selection=selectedLibrary(register,json(identityFile),repo);
 if(mode==='match-export'){assert(proofRoot);verifyExportSelection(selection,proofRoot);}
 process.stdout.write(JSON.stringify(selection)+'\n');
}
