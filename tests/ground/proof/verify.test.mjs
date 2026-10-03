import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile, writeFile, mkdir } from 'node:fs/promises';
import { execFileSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import { fileURLToPath } from 'node:url';
import { join } from 'node:path';
import { validateContract, contractSetSha256 } from '../../../schemas/validate.mjs';

const root=fileURLToPath(new URL('../../../',import.meta.url));
const fixtureRoot=join(root,'tests/ground/fixtures');
const evidenceRoot=join(root,'.local/ground-proof');
const binary=join(root,'.local/build/native-release/bin',process.platform==='win32'?'ground_contact_tests.exe':'ground_contact_tests');
const sha=bytes=>createHash('sha256').update(bytes).digest('hex');
const analytical=JSON.parse(await readFile(join(fixtureRoot,'analytical-reference.json'),'utf8'));
const vector=value=>['x','y','z'].map(key=>value[key]);
const dot=(a,b)=>a.reduce((sum,value,index)=>sum+value*b[index],0);
const add=(a,b)=>a.map((value,index)=>value+b[index]);
const subtract=(a,b)=>a.map((value,index)=>value-b[index]);
const scale=(a,b)=>a.map(value=>value*b);
const norm=values=>Math.hypot(...values);
const basis=({latitude_rad:p,longitude_rad:l})=>({north:[-Math.sin(p)*Math.cos(l),-Math.sin(p)*Math.sin(l),Math.cos(p)],east:[-Math.sin(l),Math.cos(l),0],up:[Math.cos(p)*Math.cos(l),Math.cos(p)*Math.sin(l),Math.sin(p)]});
const ecef=p=>{
  const f=1/298.257223563,e2=f*(2-f),n=6378137/Math.sqrt(1-e2*Math.sin(p.latitude_rad)**2);
  return [(n+p.ellipsoid_height_m)*Math.cos(p.latitude_rad)*Math.cos(p.longitude_rad),(n+p.ellipsoid_height_m)*Math.cos(p.latitude_rad)*Math.sin(p.longitude_rad),(n*(1-e2)+p.ellipsoid_height_m)*Math.sin(p.latitude_rad)];
};
const rotate=(q,v)=>{const u=[q.x,q.y,q.z],cross=(a,b)=>[a[1]*b[2]-a[2]*b[1],a[2]*b[0]-a[0]*b[2],a[0]*b[1]-a[1]*b[0]],t=scale(cross(u,v),2);return add(add(v,scale(t,q.w)),cross(u,t));};
const nedToEcef=(v,p)=>{const b=basis(p);return add(add(scale(b.north,v[0]),scale(b.east,v[1])),scale(b.up,-v[2]));};
const anchor={latitude_rad:.8,longitude_rad:-2,ellipsoid_height_m:1000};
const anchorEcef=ecef(anchor);
function plane(slope) {
  const b=basis(anchor),raw=subtract(subtract(b.up,scale(b.north,slope?.03:0)),scale(b.east,slope?.02:0));
  return scale(raw,1/norm(raw));
}
function identity(slope) {
  const values=[.8,-2,1000,slope?.03:0,slope?.02:0,-200,200,-200,200,20,.8,.8*.75];
  const prefix=Buffer.from('ground-plane-v1\0'),bytes=Buffer.alloc(prefix.length+values.length*8+1);prefix.copy(bytes);
  values.forEach((value,index)=>bytes.writeDoubleLE(value,prefix.length+index*8));bytes[bytes.length-1]=1;return sha(bytes);
}
function compare(a,b) {
  const q=a.orientation_body_to_ned,r=b.orientation_body_to_ned;
  return {position_m:norm(subtract(vector(a.ecef_position_m),vector(b.ecef_position_m))),velocity_mps:norm(subtract(vector(a.velocity_body_mps),vector(b.velocity_body_mps))),attitude_rad:2*Math.acos(Math.min(1,Math.abs(q.w*r.w+q.x*r.x+q.y*r.y+q.z*r.z))),rate_radps:norm(subtract(vector(a.angular_rate_body_radps),vector(b.angular_rate_body_radps)))};
}
const thresholds={position_m:.15,velocity_mps:.15,attitude_rad:.02,rate_radps:.05};
function verify(receipt) {
  assert.equal(receipt.type,'GroundProofReceipt');assert.equal(receipt.version,1);assert.equal(receipt.failures,0);assert.ok(receipt.checks>0);
  assert.equal(receipt.fixture_sha256,'c546dc4791fc830e6f656b13c7a564322d51fba8f46b43da10af3d2f7ff041a1');
  assert.equal(receipt.trials.length,30);const results=[];const names=new Set();
  for(const trial of receipt.trials) {
    const key=`${trial.name}.${trial.hz}`;assert.ok(!names.has(key));names.add(key);
    assert.match(trial.name,/^(flat|slope)\.(stationary|coast|steer|brake|touchdown)$/);assert.ok([60,120,240].includes(trial.hz));
    assert.equal(trial.samples.length,17);assert.equal(trial.diagnostics.length,17);const slope=trial.name.startsWith('slope.');
    assert.equal(trial.surface_identity_sha256,identity(slope));
    assert.ok(trial.peak_compression_m>0&&trial.peak_compression_m<.25);assert.ok(trial.minimum_clearance_m>.65);
    assert.ok(trial.max_height_step_m<.1);assert.ok(trial.max_acceleration_mps2<=400);assert.ok(trial.queries>8*trial.hz);
    const normal=plane(slope);
    trial.samples.forEach((state,index)=>{
      assert.deepEqual(validateContract(state,'AircraftSnapshot'),{valid:true,errors:[]});assert.equal(state.session_id,'ground-proof');
      assert.equal(state.tick,String(index*trial.hz/2));assert.equal(state.elapsed_s,index/2);assert.deepEqual(state.clock,{tick_rate_hz:trial.hz,purpose:'convergence'});
      assert.equal(state.contacts.length,3);assert.deepEqual(state.contacts.map(contact=>contact.id),['gear.nose','gear.left','gear.right']);
      assert.equal(state.validity,'valid');assert.ok(Math.abs(state.mass_kg-1100)<.001);assert.equal(norm(vector(state.center_of_gravity_body_m)),0);
      assert.ok(norm(vector(state.velocity_body_mps))<=20);assert.ok(norm(vector(state.angular_rate_body_radps))<=2);
      const diagnostic=trial.diagnostics[index];assert.equal(diagnostic.compression_m.length,3);assert.equal(diagnostic.compression_rate_mps.length,3);
      for(let gear=0;gear<3;gear++) {
        const contact=state.contacts[gear];assert.ok(Number.isFinite(diagnostic.compression_m[gear])&&Number.isFinite(diagnostic.compression_rate_mps[gear]));
        if(!contact.on_ground)continue;
        const point=add(vector(state.ecef_position_m),nedToEcef(rotate(state.orientation_body_to_ned,vector(contact.point_body_m)),state.position));
        assert.ok(Math.abs(dot(normal,subtract(point,anchorEcef)))<analytical.provisional_budgets.default_ellipsoid_adapter_geometry_m,'Published compressed contact point lies on independent ECEF plane');
        const force=nedToEcef(rotate(state.orientation_body_to_ned,vector(contact.force_body_n)),state.position),normalBody=rotate({w:state.orientation_body_to_ned.w,x:-state.orientation_body_to_ned.x,y:-state.orientation_body_to_ned.y,z:-state.orientation_body_to_ned.z},[dot(normal,basis(state.position).north),dot(normal,basis(state.position).east),-dot(normal,basis(state.position).up)]);
        const expected=Math.max(0,analytical.model.spring_n_per_m*diagnostic.compression_m[gear]+analytical.model.linear_damping_n_per_mps*diagnostic.compression_rate_mps[gear])/(-normalBody[2]);
        assert.ok(Math.abs(dot(force,normal)-expected)<.02+Math.abs(expected)*.00001,'Backend normal force agrees with independent spring/damper equation and leg projection');
      }
    });
  }
  for(const family of ['flat','slope'])for(const operation of ['stationary','coast','steer','brake','touchdown'])for(const hz of [60,120]) {
    const a=receipt.trials.find(trial=>trial.name===`${family}.${operation}`&&trial.hz===hz),b=receipt.trials.find(trial=>trial.name===`${family}.${operation}`&&trial.hz===240);
    const maxima=Object.fromEntries(Object.keys(thresholds).map(key=>[key,0]));a.samples.forEach((state,index)=>{const differences=compare(state,b.samples[index]);for(const key of Object.keys(thresholds))maxima[key]=Math.max(maxima[key],differences[key]);});
    for(const key of Object.keys(thresholds))assert.ok(maxima[key]<thresholds[key],`${a.name} ${hz}Hz ${key}`);results.push({name:a.name,hz,maxima});
  }
  return results;
}
let receipt,comparisons;
test('original ground fixture bytes and independent pre-observation packet retain exact identity',async()=>{
  const inventory=JSON.parse(await readFile(join(fixtureRoot,'inventory.json'),'utf8'));assert.equal(inventory.license,'MIT');
  for(const file of inventory.files){const bytes=await readFile(join(fixtureRoot,file.path));assert.equal(sha(bytes),file.sha256);if(file.bytes)assert.equal(bytes.length,file.bytes);assert.ok(!bytes.includes(13),'Canonical LF content');}
  for(const item of analytical.planes) {
    const [p,l,h]=item.anchor_geodetic_rad_m,point=ecef({latitude_rad:p,longitude_rad:l,ellipsoid_height_m:h});assert.ok(norm(subtract(point,item.plane_point_ecef_m))<1e-7);
    const [latitude_rad,longitude_rad]=item.query_rad,base=ecef({latitude_rad,longitude_rad,ellipsoid_height_m:0}),up=basis({latitude_rad,longitude_rad}).up;
    const height=dot(item.normal_ecef,subtract(point,base))/dot(item.normal_ecef,up);assert.ok(Math.abs(height-item.surface_height_ellipsoid_m)<1e-7);
  }
});
test('actual pinned JSBSim contacts validate SI snapshots, compressed arms, force equations and 60/120/240 convergence',async()=>{
  await mkdir(evidenceRoot,{recursive:true});const output=join(evidenceRoot,'receipt.json');
  const log=execFileSync(binary,[fixtureRoot,output],{encoding:'utf8',timeout:120000,maxBuffer:4*1024*1024,env:{...process.env,JSBSIM_DEBUG:'0'}});
  await writeFile(join(evidenceRoot,'native-log.txt'),log);receipt=JSON.parse(await readFile(output,'utf8'));comparisons=verify(receipt);
  assert.match(receipt.library_version,/^1\.3\.1(?:$|[ -][ -~]{1,186}$)/);assert.match(receipt.compiler,/^(MSVC|GNU|Clang)-/);
  const report={version:1,classification:'Original ground numerical proof; no C172S, airport, save or playable acceptance',compiler:receipt.compiler,library_version:receipt.library_version,
    actual_loaded_jsbsim_sha256:sha(await readFile(receipt.loaded_library_path)),executable_sha256:sha(await readFile(binary)),contract_set_sha256:contractSetSha256,
    inventory_sha256:sha(await readFile(join(fixtureRoot,'inventory.json'))),native_receipt_sha256:sha(await readFile(output)),checks:receipt.checks,trials:30,
    sample_hz:2,continuous_time_error_bound:false,thresholds,comparisons};
  await writeFile(join(evidenceRoot,'report.json'),JSON.stringify(report,null,2)+'\n');console.log(JSON.stringify({checks:receipt.checks,trials:30,report_sha256:sha(await readFile(join(evidenceRoot,'report.json')))}));
});
test('receipt verifier rejects wrong surface identity, missing contacts, forged force and incompatible tick/schema',()=>{
  assert.ok(receipt);for(const mutate of [r=>r.trials[0].surface_identity_sha256='a'.repeat(64),r=>r.trials[0].samples[4].contacts.pop(),r=>r.trials[0].samples[4].contacts[0].force_body_n.z+=100,r=>r.trials[0].samples[4].tick='3',r=>r.trials[0].samples[4].schema_version=2]) {
    const bad=structuredClone(receipt);mutate(bad);assert.throws(()=>verify(bad));
  }
});
