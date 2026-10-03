import fs from 'node:fs';
import path from 'node:path';
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {fileURLToPath} from 'node:url';
export const sha=bytes=>createHash('sha256').update(bytes).digest('hex');
export const runtimeNames=['msvcp140.dll','msvcp140_2.dll','msvcp140_atomic_wait.dll','vcruntime140.dll','vcruntime140_1.dll'];
function compareVersion(a,b){const x=a.split('.').map(Number),y=b.split('.').map(Number);for(let i=0;i<Math.max(x.length,y.length);i++){const delta=(x[i]??0)-(y[i]??0);if(delta)return Math.sign(delta);}return 0;}
function x64(bytes){const header=bytes.readUInt32LE(0x3c);assert.equal(bytes.toString('ascii',header,header+4),'PE\0\0');assert.equal(bytes.readUInt16LE(header+4),0x8664,'Runtime is not PE x64');}
const systemImports=new Set(['advapi32.dll','avrt.dll','bcrypt.dll','crypt32.dll','dwmapi.dll','dwrite.dll','dxgi.dll','gdi32.dll','hid.dll','imm32.dll','iphlpapi.dll','kernel32.dll','msvcrt.dll','ntdll.dll','ole32.dll','oleaut32.dll','shcore.dll','shell32.dll','shlwapi.dll','uiautomationcore.dll','user32.dll','winmm.dll','ws2_32.dll','wsock32.dll']);
export function peImports(bytes) {
  x64(bytes);
  const header=bytes.readUInt32LE(0x3c),optional=header+24;
  assert.equal(bytes.readUInt16LE(optional),0x20b,'PE32+ optional header required');
  assert(bytes.readUInt32LE(optional+108)>=14,'PE directory table incomplete');
  const sections=header+24+bytes.readUInt16LE(header+20),count=bytes.readUInt16LE(header+6);
  assert(count>0&&count<=96&&sections+count*40<=bytes.length,'PE sections exceed bounds');
  const offset=(rva,length)=>{
    for(let i=0;i<count;i++) {
      const section=sections+i*40,base=bytes.readUInt32LE(section+12),raw=bytes.readUInt32LE(section+16),start=bytes.readUInt32LE(section+20);
      if(rva>=base&&rva-base+length<=raw) {const found=start+rva-base;assert(found+length<=bytes.length,'PE RVA beyond file');return found;}
    }
    throw new Error('Unmapped PE RVA');
  };
  const name=rva=>{
    const found=offset(rva,1);let end=found;
    while(end<bytes.length&&end-found<260&&bytes[end]!==0)end++;
    assert(end<bytes.length&&end-found<260,'Unterminated PE import name');
    const result=bytes.toString('ascii',found,end).toLowerCase();
    assert(/^[a-z0-9_.-]+\.dll$/.test(result),'Unsafe PE import name');return result;
  };
  const names=new Set();
  for(const [directory,width,nameField]of [[1,20,12],[13,32,4]]) {
    const entry=optional+112+directory*8,rva=bytes.readUInt32LE(entry),size=bytes.readUInt32LE(entry+4);
    if(rva===0&&size===0)continue;
    assert(rva&&size>=width&&size<=1024*1024,'Invalid PE import directory bounds');
    let terminated=false;
    for(let i=0;i+width<=size;i+=width) {
      const descriptor=offset(rva+i,width);
      if(bytes.subarray(descriptor,descriptor+width).every(value=>value===0)){terminated=true;break;}
      if(directory===13)assert.equal(bytes.readUInt32LE(descriptor),1,'Unsupported non-RVA delay import');
      names.add(name(bytes.readUInt32LE(descriptor+nameField)));
    }
    assert(terminated,'Unterminated PE import directory');
  }
  return [...names].sort();
}
export function checkDependencies(report,{packageRoot}) {
  assert.equal(report.schema_version,1);
  const actual=[];
  function walk(relative='') {
    for(const entry of fs.readdirSync(path.join(packageRoot,relative),{withFileTypes:true})) {
      const file=relative+entry.name;
      if(entry.isDirectory())walk(file+'/');
      else if(/\.(dll|exe)$/i.test(file))actual.push(file);
    }
  }
  walk();actual.sort();assert.deepEqual(report.files.map(row=>row.file).sort(),actual,'PE dependency report omits/adds a binary');
  const observedRuntime=new Set();
  for(const record of report.files) {
    const bytes=fs.readFileSync(path.join(packageRoot,record.file));assert.equal(sha(bytes),record.sha256,'PE dependency file changed');
    const imports=peImports(bytes);assert.deepEqual(record.imports.map(value=>value.toLowerCase()).sort(),imports,'PE import report differs from actual direct/delay import table');
    for(const imported of imports) {
      if(systemImports.has(imported)||/^api-ms-win-(core|crt|security)-[a-z0-9-]+\.dll$/.test(imported))continue;
      assert(imported==='jsbsim.dll'||runtimeNames.includes(imported),'Unreviewed non-system import: '+imported);
      const staged=actual.filter(file=>path.basename(file).toLowerCase()===imported);
      assert(staged.length,'Required non-system import is not staged: '+imported);
      if(runtimeNames.includes(imported))observedRuntime.add(imported);
    }
  }
  assert.deepEqual([...observedRuntime].sort(),runtimeNames,'Reviewed CRT list does not match observed complete dependency closure');
  return {schema_version:1,all_direct_delay_imports_verified:true,non_system_import_closure:runtimeNames,windows_os_baseline:'Windows 11 x64 API-set/UCRT and explicit system import names; not redistributed'};
}
export function checkRuntime(selected,buildManifest,policy,{packageRoot}={}) {
  assert.equal(selected.length,runtimeNames.length,'Require exact complete CRT identities');
  assert.deepEqual(selected.map(f=>f.name.toLowerCase()).sort(),runtimeNames);
  const toolset=buildManifest.match(/Compiler path: .*\/VC\/Tools\/MSVC\/(\d+\.\d+\.\d+)\//i)?.[1];
  assert(toolset,'Actual MSVC toolset path absent from build manifest');
  assert.match(buildManifest,/MSVC runtime: MultiThreadedDLL/);
  const version=selected[0].version;
  assert(selected.every(f=>f.version===version),'Mixed CRT versions');
  assert(compareVersion(version,toolset)>=0,'Runtime older than actual build toolset');
  const approved=policy.inventories?.find(inventory=>inventory.version===version&&selected.every(file=>inventory.files.some(pin=>pin.name===file.name&&pin.sha256===file.sha256&&pin.version===file.version)));
  assert(approved,'Selected runtime identities have no reviewed exact pin');
  assert.equal(policy.debug_nonredist_allowed,false);
  assert.equal(policy.system32_copies_allowed,false);
  for(const file of selected) {
    assert.equal(file.signature,'Valid');
    assert.match(file.signer,/Microsoft/);
    assert(!/debug_nonredist|System32|preview/i.test(file.source),'Forbidden CRT origin');
    const revision=file.source.replaceAll('\\','/').match(/\/VC\/Redist\/MSVC\/([^/]+)\/x64\/Microsoft\.VC143\.CRT\//i)?.[1];
    assert.equal(revision,approved.redist_revision,'CRT source revision differs from reviewed pin');
    const source=fs.readFileSync(file.source);x64(source);assert.equal(sha(source),file.sha256);
    assert.equal(source.length,file.bytes,'Selected CRT byte length changed');
    assert.equal(file.bytes,approved.files.find(pin=>pin.name===file.name).bytes,'CRT length differs from reviewed pin');
    if(packageRoot)for(const relative of [file.name,'bin/'+file.name]) {
      const target=path.join(packageRoot,relative);
      assert(!fs.lstatSync(target).isSymbolicLink());
      assert.equal(sha(fs.readFileSync(target)),file.sha256,'Staged runtime bytes changed');
    }
  }
  const identity={architecture:'x64',version,redist_revision:approved.redist_revision,files:approved.files.map(f=>({name:f.name,version:f.version,bytes:f.bytes,sha256:f.sha256})).sort((a,b)=>a.name<b.name?-1:a.name>b.name?1:0)};
  const selectedIdentity={...identity,compiler_toolset:toolset,signature_verified:true,release_only:true};
  return {schema_version:1,selected_inventory:identity,reviewed_runtime_inventory_sha256:sha(JSON.stringify(identity)),selected_build_inventory_sha256:sha(JSON.stringify(selectedIdentity)),compiler_toolset:toolset,source_verified:true,exact_pins_matched:true,package_bytes_matched:!!packageRoot};
}
export function auditRuntimeRelease(entry,component,{packageRoot}) {
  const errors=[];
  try {
    assert(component.runtime_inventory,'Selected runtime report missing from component');
    const file=component.files.find(f=>f.path===component.runtime_inventory&&f.role==='evidence');
    assert(file,'Selected runtime report must be declared evidence');
    const report=JSON.parse(fs.readFileSync(path.join(packageRoot,file.path),'utf8'));
    assert.equal(report.schema_version,1);
    const identity=report.selected_inventory;
    assert.equal(identity.architecture,'x64');
    const approved=entry.runtime_policy.inventories.find(i=>i.version===identity.version&&i.redist_revision===identity.redist_revision);
    assert(approved,'Runtime report has no reviewed identity');
    const expected=approved.files.map(f=>({name:f.name,version:f.version,bytes:f.bytes,sha256:f.sha256})).sort((a,b)=>a.name<b.name?-1:a.name>b.name?1:0);
    assert.deepEqual(expected.map(f=>f.name),runtimeNames,'Reviewed inventory lacks complete observed CRT closure');
    assert.deepEqual(identity.files,expected,'Runtime report file identities differ from approved pins');
    assert.equal(report.reviewed_runtime_inventory_sha256,sha(JSON.stringify(identity)));
    assert(compareVersion(identity.version,report.compiler_toolset)>=0,'Runtime older than compiled toolset');
    const selectedIdentity={...identity,compiler_toolset:report.compiler_toolset,signature_verified:true,release_only:true};
    assert.equal(report.selected_build_inventory_sha256,sha(JSON.stringify(selectedIdentity)),'Selected-build inventory digest mismatch');
    for(const flag of ['source_verified','exact_pins_matched','package_bytes_matched'])assert.equal(report[flag],true);
    const binaryFiles=component.files.filter(f=>f.role==='binary');
    assert.equal(binaryFiles.length,2*runtimeNames.length,'CRT binary payload allowlist differs');
    for(const pin of expected)for(const relative of [pin.name,'bin/'+pin.name]) {
      const binary=binaryFiles.find(f=>f.path===relative);
      assert(binary&&binary.sha256===pin.sha256,'Missing/changed pinned CRT binary declaration');
      const bytes=fs.readFileSync(path.join(packageRoot,relative));x64(bytes);assert.equal(sha(bytes),pin.sha256);assert.equal(bytes.length,pin.bytes);
    }
    assert(component.dependency_report,'PE dependency closure report missing');
    assert(component.files.some(f=>f.path===component.dependency_report&&f.role==='evidence'),'PE dependency report is not declared evidence');
    checkDependencies(JSON.parse(fs.readFileSync(path.join(packageRoot,component.dependency_report),'utf8')),{packageRoot});
  }catch(error){errors.push('runtime: '+error.message);}
  return errors;
}

if(process.argv[1]&&path.resolve(process.argv[1])===fileURLToPath(import.meta.url)) {
  const [selectedFile,manifestFile,registerFile,packageRoot,output]=process.argv.slice(2);
  const register=JSON.parse(fs.readFileSync(registerFile,'utf8'));
  const report=checkRuntime(JSON.parse(fs.readFileSync(selectedFile,'utf8')),fs.readFileSync(manifestFile,'utf8'),register.entries.find(e=>e.id==='microsoft-vc143-crt').runtime_policy,{packageRoot});
  if(output)fs.writeFileSync(output,JSON.stringify(report,null,2)+'\n');
  console.log(JSON.stringify(report));
}
