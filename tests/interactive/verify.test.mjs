import test from 'node:test';
import assert from 'node:assert/strict';
import {readFile,writeFile,mkdir,cp,mkdtemp} from 'node:fs/promises';
import {execFileSync} from 'node:child_process';
import {createHash} from 'node:crypto';
import {fileURLToPath} from 'node:url';
import {join} from 'node:path';
import {tmpdir} from 'node:os';
import {validateContract,contractSetSha256} from '../../schemas/validate.mjs';

const root=fileURLToPath(new URL('../../',import.meta.url));
const models=join(root,'native/fdm_jsbsim/models/original-interactive');
const output=join(root,'.local/interactive-proof');
const binary=join(root,'.local/build/native-release/bin',process.platform==='win32'?'interactive_tests.exe':'interactive_tests');
const sha=bytes=>createHash('sha256').update(bytes).digest('hex');
const sourcePaths=[
  'native/fdm_jsbsim/interactive/src/session.cpp',
  'native/fdm_jsbsim/interactive/include/flight/interactive/session.hpp',
  'native/fdm_jsbsim/interactive/include/flight/interactive/surface.hpp',
  'tests/interactive/native.cpp','tests/interactive/negatives.hpp',
  'native/fdm_jsbsim/interactive/src/model-pins.hpp'];
const sources=[];let fingerprintText='';
for(const path of sourcePaths){const bytes=await readFile(join(root,path));const normalized=Buffer.from(bytes.toString('utf8').replaceAll('\r\n','\n'));const hash=sha(normalized);sources.push({path,normalized_sha256:hash});fingerprintText+=`${path}:${hash}\n`;}
const fingerprint=sha(Buffer.from(fingerprintText));
const inventory=JSON.parse(await readFile(join(models,'inventory.json')));
const run=(prefix,mode,modelRoot=models)=>execFileSync(binary,[modelRoot,join(output,prefix),...(mode?[mode]:[])],{encoding:'utf8',env:{...process.env,JSBSIM_DEBUG:'0'},timeout:120000});
const json=async name=>JSON.parse(await readFile(join(output,name),'utf8'));
const lines=async name=>(await readFile(join(output,name),'utf8')).trim().split('\n').map(x=>JSON.parse(x));
await mkdir(output,{recursive:true});

test('actual one-executive ground→flight→touchdown→all-WOW stop, strict v1 and exact same-build repeat',async()=>{
  run('ground');run('repeat');run('checks','negatives');
  const ground=await json('ground.json'),repeat=await json('repeat.json'),negative=await json('checks.json');
  for(const receipt of [ground,repeat,negative]){assert.equal(receipt.passed,true);assert.equal(receipt.compiled_source_fingerprint,fingerprint,'Public compiled source matches normalized source bytes');}
  assert.equal(ground.engineering_prototype,true);assert.equal(ground.stopped_all_wow,true);assert.ok(negative.checks>=1281);
  assert.equal(ground.prepared_surface_sha256,'04bff5a0bcf3509990f6276b2548a28268f57fc96d218a7ca51cab1990ec1ff5');
  assert.ok(ground.takeoff_tick>0&&ground.touchdown_tick>ground.takeoff_tick&&ground.final_tick>ground.touchdown_tick);
  const states=await lines('ground.ndjson'),weather=await lines('ground.atmosphere.ndjson'),commands=await lines('ground.commands.ndjson'),events=await lines('checks.events.ndjson');let records=0;
  assert.equal(states.length,weather.length);
  const validate=record=>{const result=validateContract(record);assert.equal(result.valid,true,JSON.stringify(result.errors));records++;};
  for(const [index,state] of states.entries()){
    validate(state);validate(weather[index]);assert.equal(state.contacts.length,3);assert.deepEqual(state.contacts.map(x=>x.id),['gear.nose','gear.left','gear.right']);
    assert.deepEqual(state.clock,{tick_rate_hz:120,purpose:'runtime'});assert.equal(state.validity,'valid');
    if(index)assert.ok(BigInt(state.tick)>BigInt(states[index-1].tick),'Unique increasing completed observations');
    assert.equal(state.tick,weather[index].tick);assert.equal(state.session_id,weather[index].session_id);assert.deepEqual(state.position,weather[index].position);
    assert.ok(Math.hypot(...Object.values(state.velocity_body_mps))<=150);assert.ok(Math.hypot(...Object.values(state.angular_rate_body_radps))<=3);
    assert.ok(state.contacts.every(contact=>Object.values(contact.force_body_n).every(Number.isFinite)));
  }
  assert.ok(states.some(s=>s.contacts.every(x=>x.on_ground)));assert.ok(states.some(s=>s.contacts.every(x=>!x.on_ground)));
  for(const [index,cmd] of commands.entries()){validate(cmd);assert.equal(cmd.source_id,'scenario.proof');assert.equal(cmd.authority,'scenario');assert.equal(cmd.sequence,String(index+1));assert.equal(cmd.tick,String(index+1));}
  assert.equal(commands.length,ground.final_tick);
  for(const [index,event] of events.entries()){validate(event);assert.equal(event.source_id,'session.owner');assert.equal(event.sequence,String(index+1));}
  assert.equal(events.length,3);
  const brakes=await lines('checks.brakes.ndjson');assert.equal(brakes.length,1);validate(brakes[0]);assert.equal(brakes[0].payload.left_brake,.2);assert.equal(brakes[0].payload.right_brake,.8);
  const final=states.at(-1);assert.equal(final.tick,String(ground.final_tick));assert.ok(final.contacts.every(x=>x.on_ground));
  const finalSpeed=Math.hypot(...['x','y','z'].map(k=>final.velocity_body_mps[k]));assert.ok(finalSpeed<.1);
  // Same arithmetic allowance as the reviewed precursor: C++/JS hypot differ by
  // one ULP. Selected after that observation; not a physics/reference tolerance.
  const normRoundoff=4*Number.EPSILON*Math.max(1,Math.abs(ground.final_speed_mps));assert.ok(Math.abs(finalSpeed-ground.final_speed_mps)<=normRoundoff);
  const artifacts=[];
  for(const suffix of ['ndjson','atmosphere.ndjson','commands.ndjson','csv']){const bytes=await readFile(join(output,`ground.${suffix}`));assert.equal(sha(bytes),sha(await readFile(join(output,`repeat.${suffix}`))),`Exact same-build ${suffix} repeat`);artifacts.push({path:`ground.${suffix}`,sha256:sha(bytes),bytes:bytes.length});}
  for(const path of ['ground.json','repeat.json','checks.json','checks.events.ndjson','checks.brakes.ndjson']){const bytes=await readFile(join(output,path));artifacts.push({path,sha256:sha(bytes),bytes:bytes.length});}
  for(const file of inventory.files){const bytes=await readFile(join(models,file.path));assert.equal(bytes.length,file.bytes);assert.equal(sha(bytes),file.sha256);}
  for(const file of inventory.lineage)assert.equal(sha(await readFile(join(root,file.path))),file.sha256,'Historical source lineage unchanged');
  const inventoryHash=sha(await readFile(join(models,'inventory.json')));assert.equal(inventoryHash,'98b30b5641ce86cc6f0af6298424606aa96a1e4a35ef3e9fcaf377bebb3f00cd');
  const register=JSON.parse(await readFile(join(root,'third_party/licenses/register.json')));assert.equal(register.entries.find(x=>x.id===inventory.id).content_policy.inventory_sha256,inventoryHash);
  await writeFile(join(output,'public-source-receipt.json'),JSON.stringify({classification:'Original scripted engineering prototype; no human/Cessna/phase/export acceptance',source_fingerprint:fingerprint,sources,verifier_sha256:sha(await readFile(fileURLToPath(import.meta.url))),contract_set_sha256:contractSetSha256,dependency_lock_sha256:sha(await readFile(join(root,'third_party/dependencies.lock.json'))),inventory_sha256:inventoryHash,executable_sha256:sha(await readFile(binary)),schema_records_validated:records,native_checks:negative.checks,exact_same_build_repeat:true,ground,artifacts},null,2)+'\n');
});

test('changed inventory or airframe bytes fail closed before backend model parsing',async()=>{
  const temp=await mkdtemp(join(tmpdir(),'flight-interactive-model-'));
  for(const path of ['inventory.json','aircraft/original-interactive/original-interactive.xml']){
    const altered=join(temp,path==='inventory.json'?'inventory':'airframe');await cp(models,altered,{recursive:true});
    await writeFile(join(altered,path),(await readFile(join(altered,path))).subarray(1));
    assert.throws(()=>run('tampered','negatives',altered),error=>error.status!==0&&/model pin\/path mismatch/.test(error.stderr),'Altered exact model bytes cannot initialize');
  }
});
