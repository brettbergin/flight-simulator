import fs from 'node:fs';
import path from 'node:path';
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {validateContract,contractSetSha256} from '../../schemas/validate.mjs';
import {runtimeNames} from '../../tools/export/check-runtime.mjs';
const [log,packageRoot,expectedLibraryHash,selectedRuntimeFile]=process.argv.slice(2);
const records=fs.readFileSync(log,'utf8').split(/\r?\n/).filter(line=>line.startsWith('FLIGHT_PROOF_RECORD ')).map(line=>JSON.parse(line.slice('FLIGHT_PROOF_RECORD '.length)));
assert(records.length>=5,'Missing actual native records');
for(const record of records) {
  const types={initial_aircraft:'AircraftSnapshot',aircraft:'AircraftSnapshot',atmosphere:'AtmosphereSample',applied_command:'ControlCommand',event:'OperationalEvent'};
  if(types[record.kind]) {
    const result=validateContract(record.value,types[record.kind]);
    assert(result.valid,JSON.stringify(result.errors));
  }
}
const init=records.find(r=>r.kind==='initialization')?.value;
assert(init?.library_version?.startsWith('1.3.1'),'Wrong runtime library version');
assert.match(init.source_fingerprint,/^[a-f0-9]{64}$/);
const loadedLibrarySha256=createHash('sha256').update(fs.readFileSync(init.loaded_library_path)).digest('hex');
if(packageRoot) {
  assert.match(expectedLibraryHash??'',/^[a-f0-9]{64}$/,'Portable baseline/replacement must supply expected staged JSBSim identity');
  const rel=path.relative(fs.realpathSync(packageRoot),fs.realpathSync(init.loaded_library_path));
  assert(rel&&!rel.startsWith('..')&&!path.isAbsolute(rel),'Actual loaded JSBSim module escaped portable payload');
}
const loadedRuntime=[];
if(packageRoot) {
  assert(selectedRuntimeFile,'Portable proof must supply selected runtime identities');
  const selected=JSON.parse(fs.readFileSync(selectedRuntimeFile,'utf8'));
  assert.equal(selected.length,runtimeNames.length);
  const modules=records.find(r=>r.kind==='runtime_modules')?.value;
  assert(modules&&Object.keys(modules).length===runtimeNames.length,'Actual CRT module paths missing');
  for(const [name,loaded]of Object.entries(modules)) {
    assert(runtimeNames.includes(name.toLowerCase()),'Unexpected CRT module name');
    const rel=path.relative(fs.realpathSync(packageRoot),fs.realpathSync(loaded));
    assert(rel&&!rel.startsWith('..')&&!path.isAbsolute(rel),'CRT loaded outside portable payload');
    const digest=createHash('sha256').update(fs.readFileSync(loaded)).digest('hex');
    const pin=selected.find(file=>file.name.toLowerCase()===name.toLowerCase());
    assert(pin&&digest===pin.sha256,'Actually loaded CRT differs from selected/staged runtime');
    loadedRuntime.push({name:pin.name,relative_path:rel.replaceAll('\\','/'),sha256:digest,version:pin.version});
  }
}
if(expectedLibraryHash) assert.equal(loadedLibrarySha256,expectedLibraryHash,'Actual loaded JSBSim DLL hash mismatch');
const applied=records.find(r=>r.kind==='applied_command').value;
assert.equal(applied.sequence,'9007199254740993');
assert.equal(records.find(r=>r.kind==='aircraft').value.tick,'121');
const report={schema_version:1,validated_contracts:records.filter(r=>!['initialization','runtime_modules'].includes(r.kind)).length,contract_set_sha256:contractSetSha256,uint64_sequence_exact:true,actual_library_path_inside_payload:!!packageRoot,loaded_library_sha256:loadedLibrarySha256,loaded_runtime:loadedRuntime};
fs.writeFileSync(log+'.modules.json',JSON.stringify(report,null,2)+'\n');
console.log(JSON.stringify(report));
