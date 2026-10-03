import test from 'node:test';
import assert from 'node:assert/strict';
import { runScenario, validateOutput, verifyModel, modelRoot } from '../../tools/run-scenario/runner.mjs';
import { scenario } from './fixture.mjs';
import { mkdtemp, cp, writeFile, readFile } from 'node:fs/promises';
import { join } from 'node:path';
import { tmpdir } from 'node:os';
const s=await scenario();const options={duration_s:1/120,trim_longitudinal:false,out_dir:join(modelRoot,'../../../../.local/fdm-context-test')};
s.initial_conditions.aircraft.orientation_body_to_ned={w:1,x:0,y:0,z:0};s.initial_conditions.aircraft.velocity_body_mps={x:55,y:3,z:2};
s.initial_conditions.atmosphere.wind_toward_ned_mps={x:7,y:-4,z:1};
const run=await runScenario(s,[],options);const context={scenario:s,commands:[],options,expectedSourceFingerprint:run.records[0].source_fingerprint};
test('actual nearidentity no-trim/wind output passes strict v1 bounds and complete context',()=>{validateOutput(run.records,context);assert.equal(run.states.at(-1).tick,'1');});
test('actual output corruption of receipt/context/order/count/diagnostics fails',()=>{
  const changes=[records=>records[0].initial_fuel_kg=1,records=>records[0].solved_controls.mixture=.5,
    records=>records[0].accepted_atmosphere.temperature_k=300,records=>records[0].source_fingerprint='0'.repeat(64),
    records=>records[0].requested_seed='1',records=>records[1].session_id='other-session',records=>records[3].clock={tick_rate_hz:60,purpose:'convergence'},
    records=>records[4].seed='1',records=>records[3].tick='0',records=>records[2].extra='hidden-value',records=>records[2].airspeed_mps=1e10,
    records=>records[5].tick='0',records=>records.pop(),records=>records.push(structuredClone(records.at(-1))),
    records=>[records[3],records[4]]=[records[4],records[3]]];
  for(const change of changes){const records=structuredClone(run.records);change(records);assert.throws(()=>validateOutput(records,context));}
});
test('exact inventory and bytes bind the author-approved model before native parser load',async()=>{
  const root=await mkdtemp(join(tmpdir(),'flight-fdm-model-check-'));await cp(modelRoot,root,{recursive:true});await verifyModel(root);
  const inventory=JSON.parse(await readFile(join(root,'inventory.json'),'utf8'));inventory.files[0].path='other.xml';await writeFile(join(root,'inventory.json'),JSON.stringify(inventory));
  await assert.rejects(()=>verifyModel(root));await cp(join(modelRoot,'inventory.json'),join(root,'inventory.json'));
  const file=join(root,'aircraft/original-synthetic/original-synthetic.xml');const bytes=await readFile(file);bytes[100]^=1;await writeFile(file,bytes);
  await assert.rejects(()=>verifyModel(root));
});
