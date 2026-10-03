import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {checkRuntime,checkDependencies,peImports,auditRuntimeRelease,sha,runtimeNames} from '../../tools/export/check-runtime.mjs';
const root=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'../../.local/export-runtime-tests');
fs.mkdirSync(root,{recursive:true});
const fixture=fs.mkdtempSync(path.join(root,'case-'));
const source=path.join(fixture,'VC/Redist/MSVC/14.40.33807/x64/Microsoft.VC143.CRT');
fs.mkdirSync(source,{recursive:true});
function pe(direct=[],delay=[]) {
 const bytes=Buffer.alloc(4096),header=128,optional=header+24;
 bytes.writeUInt32LE(header,0x3c);bytes.write('PE\0\0',header,'ascii');bytes.writeUInt16LE(0x8664,header+4);bytes.writeUInt16LE(1,header+6);bytes.writeUInt16LE(240,header+20);
 bytes.writeUInt16LE(0x20b,optional);bytes.writeUInt32LE(16,optional+108);
 const section=optional+240;bytes.writeUInt32LE(3584,section+8);bytes.writeUInt32LE(4096,section+12);bytes.writeUInt32LE(3584,section+16);bytes.writeUInt32LE(512,section+20);
 let nextName=2048;
 for(const [index,list,start,width,field]of [[1,direct,512,20,12],[13,delay,1024,32,4]]) {
  if(!list.length)continue;
  bytes.writeUInt32LE(4096+start-512,optional+112+index*8);bytes.writeUInt32LE((list.length+1)*width,optional+112+index*8+4);
  for(let i=0;i<list.length;i++) {if(index===13)bytes.writeUInt32LE(1,start+i*width);bytes.writeUInt32LE(4096+nextName-512,start+i*width+field);bytes.write(list[i],nextName,'ascii');nextName+=list[i].length+1;}
 }
 return bytes;
}
const selected=runtimeNames.map((name,index)=>{
 const bytes=pe();bytes[4000]=index;
 const file=path.join(source,name);fs.writeFileSync(file,bytes);
 return {name,source:file,version:'14.40.33810.0',bytes:bytes.length,sha256:sha(bytes),signature:'Valid',signer:'Microsoft Corporation'};
});
const policy={inventories:[{version:'14.40.33810.0',redist_revision:'14.40.33807',files:selected.map(({name,version,bytes,sha256})=>({name,version,bytes,sha256}))}],debug_nonredist_allowed:false,system32_copies_allowed:false};
const manifest='Compiler path: C:/VS/VC/Tools/MSVC/14.40.33807/bin/Hostx64/x64/cl.exe\nMSVC runtime: MultiThreadedDLL\n';
test('Exact reviewed x64 runtime pins pass without requiring a real Microsoft fixture',()=>assert.equal(checkRuntime(selected,manifest,policy).exact_pins_matched,true));
test('Unreviewed hosted runtime remains blocked',()=>{const rows=structuredClone(selected);rows[0].sha256='0'.repeat(64);assert.throws(()=>checkRuntime(rows,manifest,policy),/reviewed exact pin/);});
test('A newer actual compiler cannot use an older reviewed runtime',()=>assert.throws(()=>checkRuntime(selected,manifest.replace('14.40.33807','14.44.35207'),policy),/older/));
test('Unsigned source cannot pass the runtime gate',()=>{const rows=structuredClone(selected);rows[0].signature='UnknownError';assert.throws(()=>checkRuntime(rows,manifest,policy));});
test('Debug/System32 origin cannot be declared release CRT',()=>{const rows=structuredClone(selected);rows[0].source='C:/Windows/System32/msvcp140.dll';assert.throws(()=>checkRuntime(rows,manifest,policy),/Forbidden/);});
test('Changed source bytes cannot pass original pins',()=>{const original=fs.readFileSync(selected[0].source);try{fs.appendFileSync(selected[0].source,Buffer.from([0]));assert.throws(()=>checkRuntime(selected,manifest,policy));}finally{fs.writeFileSync(selected[0].source,original);}});
test('Generic release audit requires selected-runtime evidence',()=>assert.match(auditRuntimeRelease({runtime_policy:policy},{files:[]},{packageRoot:fixture})[0],/report missing/));
test('Inventory digest mutation cannot bypass generic release gate',()=>{
 const payload=path.join(fixture,'payload');fs.mkdirSync(path.join(payload,'bin'),{recursive:true});
 for(const row of selected)for(const relative of [row.name,'bin/'+row.name])fs.copyFileSync(row.source,path.join(payload,relative));
 const report=checkRuntime(selected,manifest,policy,{packageRoot:payload});report.selected_build_inventory_sha256='0'.repeat(64);
 fs.writeFileSync(path.join(payload,'runtime.json'),JSON.stringify(report));
 const files=selected.flatMap(row=>[row.name,'bin/'+row.name].map(file=>({path:file,role:'binary',sha256:row.sha256})));
 files.push({path:'runtime.json',role:'evidence',sha256:sha(fs.readFileSync(path.join(payload,'runtime.json')))});
 const errors=auditRuntimeRelease({runtime_policy:policy},{runtime_inventory:'runtime.json',files},{packageRoot:payload});
 assert.match(errors[0],/inventory digest mismatch/);
});
test('Actual direct and deferred PE imports are both read',()=>assert.deepEqual(peImports(pe(['MSVCP140_2.dll'],['MSVCP140_ATOMIC_WAIT.dll'])),['msvcp140_2.dll','msvcp140_atomic_wait.dll']));
test('Complete five-file CRT closure passes and each omitted import fails without System32 fallback',()=>{
 const payload=fs.mkdtempSync(path.join(fixture,'closure-'));
 for(const row of selected)fs.copyFileSync(row.source,path.join(payload,row.name));
 fs.writeFileSync(path.join(payload,'bridge.dll'),pe(runtimeNames.slice(0,4),runtimeNames.slice(4)));
 const report=()=>({schema_version:1,files:fs.readdirSync(payload).map(file=>{const bytes=fs.readFileSync(path.join(payload,file));return {file,sha256:sha(bytes),imports:peImports(bytes)};})});
 assert.equal(checkDependencies(report(),{packageRoot:payload}).all_direct_delay_imports_verified,true);
 for(const row of selected) {const file=path.join(payload,row.name),original=fs.readFileSync(file);fs.unlinkSync(file);try{assert.throws(()=>checkDependencies(report(),{packageRoot:payload}),/not staged/);}finally{fs.writeFileSync(file,original);}}
 fs.writeFileSync(path.join(payload,'bridge.dll'),pe([...runtimeNames,'undeclared-third-party.dll']));
 assert.throws(()=>checkDependencies(report(),{packageRoot:payload}),/Unreviewed non-system import/);
});
test('PE report cannot omit a real deferred dependency',()=>{
 const payload=fs.mkdtempSync(path.join(fixture,'delay-')),file='bridge.dll',bytes=pe([],['MSVCP140_ATOMIC_WAIT.dll']);fs.writeFileSync(path.join(payload,file),bytes);
 assert.throws(()=>checkDependencies({schema_version:1,files:[{file,sha256:sha(bytes),imports:[]}]},{packageRoot:payload}),/actual direct\/delay/);
});
test('Reviewed bytes with wrong machine architecture still reject',()=>{
 const row=selected[0],original=fs.readFileSync(row.source),changed=Buffer.from(original);changed.writeUInt16LE(0xaa64,132);
 const rows=structuredClone(selected),pins=structuredClone(policy);rows[0].sha256=sha(changed);pins.inventories[0].files[0].sha256=sha(changed);
 try{fs.writeFileSync(row.source,changed);assert.throws(()=>checkRuntime(rows,manifest,pins),/not PE x64/);}finally{fs.writeFileSync(row.source,original);}
});
