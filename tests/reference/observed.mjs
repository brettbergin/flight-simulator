// Integration check requires an actual accepted harness run; missing artifacts fail.
import assert from 'node:assert/strict';
import {mkdtemp,copyFile,readFile,writeFile,unlink,rmdir} from 'node:fs/promises';
import {join,resolve} from 'node:path';import {tmpdir} from 'node:os';
import {runValidation,inspectRun,sha} from '../../tools/validation/runner.mjs';
import {validateMatrix} from '../../tools/validation/validate.mjs';
const folder=resolve(process.argv[2]??'.local/fdm-proof/hz120');
const report=await runValidation({runDir:folder,output:'.local/validation/observed-report.json'});
assert.deepEqual(report.counts,{passed:25,failed:0,unsupported:9});
const observed=report.results.find(r=>r.classification==='independent-equation-comparison');
assert.ok(observed.samples>=2);
const matrix=validateMatrix(JSON.parse(await readFile(new URL('./matrix-v1.json',import.meta.url))));
const temporary=await mkdtemp(join(tmpdir(),'flight-reference-'));
const names=['telemetry.ndjson','provenance.json','scenario.json','commands.json'];
try {
 for(const name of names)await copyFile(join(folder,name),join(temporary,name));
 const lines=(await readFile(join(temporary,names[0]),'utf8')).trim().split('\n').map(JSON.parse);
 const d=lines.find(r=>r.kind==='fdm-diagnostics');d.drag_side_lift_n[2]+=1000;
 const changed=Buffer.from(lines.map(JSON.stringify).join('\n')+'\n');
 await writeFile(join(temporary,names[0]),changed);
 await assert.rejects(()=>inspectRun(temporary,matrix),/provenance/);
 const provenance=JSON.parse(await readFile(join(temporary,names[1])));
 provenance.telemetry_sha256=sha(changed);await writeFile(join(temporary,names[1]),JSON.stringify(provenance));
 const wrongPhysics=await inspectRun(temporary,matrix);
 assert.equal(wrongPhysics.status,'failed');assert.ok(wrongPhysics.failed_samples.some(r=>r.errors.some(e=>e.quantity==='lift_wind_n')));
  const saved=structuredClone(provenance);
 for(const change of [
  p=>p.request_sha256='0'.repeat(64),
  p=>delete p.executable_sha256,
  p=>p.compiler='made-up',
  p=>p.loaded_jsbsim.sha256='invalid',
  p=>p.model.inventory.files[0].sha256='0'.repeat(64),
  p=>p.tick_rate_hz=60,
  p=>p.initialization.accepted_aircraft.mass_kg=999
 ]){
  const corrupted=structuredClone(saved);change(corrupted);
  await writeFile(join(temporary,names[1]),JSON.stringify(corrupted));
  await assert.rejects(()=>inspectRun(temporary,matrix),/provenance/);
 }
 provenance.model.inventory_sha256='0'.repeat(64);await writeFile(join(temporary,names[1]),JSON.stringify(provenance));
 await assert.rejects(()=>inspectRun(temporary,matrix),/provenance/);
}finally{
 // Only the four known files are removed; no recursive deletion or computed shell command.
 for(const name of names)await unlink(join(temporary,name)).catch(e=>{if(e.code!=='ENOENT')throw e;});
 await rmdir(temporary);
}
console.log(JSON.stringify({status:'passed',actual_samples:observed.samples,checks:['actual-equations','stale-digest-rejected','rehashed-wrong-force-failed','wrong-model-rejected','request-build-receipt-corruption-rejected']}));
