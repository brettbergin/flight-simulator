import { readFile, writeFile, mkdir, realpath } from 'node:fs/promises';
import { createHash } from 'node:crypto';
import { spawnSync } from 'node:child_process';
import { resolve, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import assert from 'node:assert/strict';
import { scenario } from '../fdm/fixture.mjs';
import { repoRoot, modelRoot, encodeRequest, verifyModel, validateOutput } from '../../tools/run-scenario/runner.mjs';
import { contractSetSha256, validateContract } from '../../schemas/validate.mjs';
import { currentSourceFingerprint } from '../../tools/run-scenario/source-fingerprint.mjs';

const hash = bytes => createHash('sha256').update(bytes).digest('hex');
const json = async path => JSON.parse(await readFile(path, 'utf8'));
const records = async path => (await readFile(path, 'utf8')).trim().split('\n').filter(Boolean).map(line=>JSON.parse(line));
function run(executable,args) {
  const result=spawnSync(executable,args,{encoding:'utf8',env:{...process.env,JSBSIM_DEBUG:'0'},maxBuffer:4*1024*1024,timeout:120000});
  if(result.error||result.status!==0)throw new Error(`Replay proof failed: ${result.error?.message??result.stderr}`);
  return result.stdout;
}
export function identityBytes(values) {
  if(!Array.isArray(values)||values.length!==7||values.some((value,i)=>typeof value!=='string'||value.length<1||value.length>256||/[^\x20-\x7e]/.test(value)||(i<5&&!/^[a-f0-9]{64}$/.test(value))))throw new Error('Invalid trusted replay identity');
  return Buffer.concat(values.map(value=>{const bytes=Buffer.from(value,'ascii'),size=Buffer.alloc(2);size.writeUInt16LE(bytes.length);return Buffer.concat([size,bytes]);}));
}
export function validateDeclarations({manifestBytes,replay,checkpoint,files,identity,scenario:s}) {
  const manifest=JSON.parse(manifestBytes.toString('utf8'));
  for(const value of [manifest,replay,checkpoint])assert.equal(validateContract(value).valid,true,'valid versioned declaration');
  const fingerprint=hash(Buffer.from(JSON.stringify(identity)));identityBytes(identity);
  assert.equal(manifest.restore_capability,'replay-from-start');assert.equal(checkpoint.restore_capability,'replay-from-start');assert.equal(manifest.restore_evidence_id,'p1-original-fixed-step-reconstruction-v1');assert.equal(checkpoint.restore_evidence_id,manifest.restore_evidence_id);
  assert.equal(manifest.contract_set_sha256,contractSetSha256);assert.equal(replay.contract_set_sha256,contractSetSha256);
  assert.equal(manifest.build.fingerprint,fingerprint);assert.equal(checkpoint.build_fingerprint,fingerprint);assert.equal(replay.build_fingerprint,fingerprint);
  assert.equal(checkpoint.session_manifest_sha256,hash(manifestBytes));assert.equal(replay.session.sha256,hash(manifestBytes));assert.equal(checkpoint.session_id,manifest.session_id);assert.equal(replay.session.id,manifest.session_id);
  assert.equal(checkpoint.tick,'72000');assert.equal(checkpoint.replay_until_tick,'72000');assert.equal(replay.determinism,'same-build-tolerances');
  assert.deepEqual(manifest.initial_conditions,s.initial_conditions);assert.deepEqual(manifest.aircraft,s.required_aircraft);assert.deepEqual(manifest.world,s.required_world);assert.deepEqual(manifest.clock,s.clock);assert.deepEqual(replay.clock,s.clock);assert.equal(manifest.seed,s.seed);assert.equal(replay.seed,s.seed);
  assert.equal(manifest.scenario.sha256,hash(Buffer.from(JSON.stringify(s))));assert.equal(manifest.calibration.sha256,identity[4]);assert.deepEqual(manifest.assistance,{profile_id:'unassisted',active:[]});
  assert.equal(manifest.command_log.path,'admissions.ndjson');assert.equal(manifest.event_log.path,'events.ndjson');assert.equal(manifest.command_log.role,'command-log');assert.equal(manifest.event_log.role,'event-log');assert.equal(checkpoint.blobs.length,1);assert.equal(checkpoint.blobs[0].path,'recipe.bin');assert.equal(checkpoint.blobs[0].role,'state');
  for(const entry of [manifest.command_log,manifest.event_log,...checkpoint.blobs]) {const bytes=files.get(entry.path);assert.ok(bytes&&bytes.length<=4*1024*1024);assert.equal(bytes.length,entry.bytes);assert.equal(hash(bytes),entry.sha256);}
  assert.equal(replay.command_log_sha256,manifest.command_log.sha256);assert.equal(replay.record_count,String(files.get('admissions.ndjson').toString('utf8').trim().split('\n').length));
  return manifest;
}
export async function runProof({executable=join(repoRoot,'.local/build/native-release/bin',process.platform==='win32'?'reconstruction_proof.exe':'reconstruction_proof'),output=join(repoRoot,'.local/replay-proof')}={}) {
  executable=await realpath(executable);output=resolve(output);await mkdir(output,{recursive:true});
  const expectedSourceFingerprint=await currentSourceFingerprint(executable);
  const s=await scenario();await verifyModel();const initial=encodeRequest(s,[],{duration_s:600,sample_hz:1});
  const input=join(output,'initial-request.bin'),identityFile=join(output,'identity.bin');await writeFile(input,initial);
  run(executable,['identify',modelRoot,input,join(output,'identify.json')]);const identified=await json(join(output,'identify.json'));
  validateOutput([identified]);
  assert.equal(identified.source_fingerprint,expectedSourceFingerprint,'compiled adapter matches selected backend, build controls and current first-party source');
  const library=await realpath(identified.loaded_library_path);
  const identity=[hash(await readFile(executable)),hash(await readFile(library)),contractSetSha256,identified.source_fingerprint,hash(await readFile(join(modelRoot,'inventory.json'))),identified.compiler,identified.library_version];
  await writeFile(identityFile,identityBytes(identity));
  const baseline=join(output,'baseline'),restored=join(output,'reconstructed');
  assert.match(run(executable,['baseline',modelRoot,input,identityFile,baseline]),/RECONSTRUCTION_PROOF_OK baseline/);
  assert.match(run(executable,['reconstruct',modelRoot,join(baseline,'recipe.bin'),identityFile,restored]),/RECONSTRUCTION_PROOF_OK reconstruct/);
  // Exact binary comparison is selected before running, within the same build.
  for(const name of ['checkpoint.sha256','checkpoint.ndjson','continuation.sha256','continuation.ndjson','final.ndjson','admissions.ndjson','events.ndjson','initialization.json'])assert.deepEqual(await readFile(join(baseline,name)),await readFile(join(restored,name)),name);
  for(const name of ['checkpoint.sha256','continuation.sha256'])assert.match(await readFile(join(restored,name),'utf8'),/^[a-f0-9]{64}\n$/);
  for(const directory of [baseline,restored]) {
    const init=await json(join(directory,'initialization.json'));assert.equal(await realpath(init.loaded_library_path),library);assert.equal(init.source_fingerprint,identity[3]);assert.equal(init.compiler,identity[5]);assert.equal(init.library_version,identity[6]);
    for(const name of ['checkpoint.ndjson','continuation.ndjson','final.ndjson'])validateOutput([init,...await records(join(directory,name))]);
    for(const row of await records(join(directory,'admissions.ndjson'))) {
      if(row.input.type){const checked=validateContract(row.input);assert.equal(checked.valid,true,JSON.stringify(checked.errors));}
    }
    for(const event of await records(join(directory,'events.ndjson')))assert.equal(validateContract(event,'OperationalEvent').valid,true);
  }
  assert.equal(await currentSourceFingerprint(executable),expectedSourceFingerprint,'source and declared build identity stayed identical');
  assert.equal(hash(await readFile(executable)),identity[0],'executable stayed identical');assert.equal(hash(await readFile(library)),identity[1],'actual loaded library stayed identical');await verifyModel();
  const baselineTiming=await json(join(baseline,'timing.json')),restoredTiming=await json(join(restored,'timing.json'));
  assert.ok(baselineTiming.negative_cases>100);assert.equal(restoredTiming.cut_tick,'72000');assert.equal(restoredTiming.continuation_ticks,'7200');
  const before=(await records(join(baseline,'checkpoint.ndjson')))[0],after=(await records(join(restored,'final.ndjson')))[0];assert.equal(before.tick,'72000');assert.equal(after.tick,'79200');assert.ok(after.mass_kg<before.mass_kg,'fuel consumption continues after reconstruction');
  const commands=(await records(join(restored,'continuation.ndjson'))).filter(row=>row.type==='ControlCommand');assert.deepEqual(commands.map(row=>[row.tick,row.source_id,row.sequence]),[['72001','pilot.controls','4'],['72020','pilot.backup','1'],['72030','pilot.controls','6']]);
  const buildFingerprint=hash(Buffer.from(JSON.stringify(identity))),evidenceId='p1-original-fixed-step-reconstruction-v1';
  const fileEntry=async(path,role)=>{const bytes=await readFile(join(baseline,path));return {path,sha256:hash(bytes),bytes:bytes.length,role};};
  const manifest=await json(join(repoRoot,'tests/contracts/fixtures/SessionManifest.json'));
  const commit=spawnSync('git',['-c',`safe.directory=${repoRoot.replaceAll('\\','/')}`,'rev-parse','HEAD'],{encoding:'utf8',cwd:repoRoot});if(commit.status!==0)throw new Error('Missing build git identity');
  Object.assign(manifest,{build:{id:'p1-reconstruction-proof',git_commit:commit.stdout.trim(),fingerprint:buildFingerprint},contract_set_sha256:contractSetSha256,aircraft:s.required_aircraft,world:s.required_world,
    scenario:{id:s.id,version:s.version,sha256:hash(Buffer.from(JSON.stringify(s)))},seed:s.seed,clock:s.clock,initial_conditions:s.initial_conditions,
    calibration:{id:'original-synthetic-uncalibrated',version:'0.1.0-prototype',sha256:identity[4]},command_log:await fileEntry('admissions.ndjson','command-log'),event_log:await fileEntry('events.ndjson','event-log'),restore_capability:'replay-from-start',restore_evidence_id:evidenceId});
  assert.equal(validateContract(manifest,'SessionManifest').valid,true);
  const manifestBytes=Buffer.from(JSON.stringify(manifest,null,2)+'\n');await writeFile(join(baseline,'session-manifest.json'),manifestBytes);
  const checkpoint={type:'Checkpoint',schema_version:1,tick:'72000',session_id:manifest.session_id,id:'original-cut-600s',session_manifest_sha256:hash(manifestBytes),build_fingerprint:buildFingerprint,restore_capability:'replay-from-start',restore_evidence_id:evidenceId,
    blobs:[await fileEntry('recipe.bin','state')],replay_until_tick:'72000'};assert.equal(validateContract(checkpoint,'Checkpoint').valid,true);await writeFile(join(baseline,'checkpoint.json'),JSON.stringify(checkpoint,null,2)+'\n');
  const replay={type:'ReplayHeader',schema_version:1,session:{id:manifest.session_id,version:'0.1.0-prototype',sha256:hash(manifestBytes)},build_fingerprint:buildFingerprint,contract_set_sha256:contractSetSha256,clock:s.clock,seed:s.seed,
    record_count:String((await records(join(baseline,'admissions.ndjson'))).length),command_log_sha256:manifest.command_log.sha256,determinism:'same-build-tolerances'};assert.equal(validateContract(replay,'ReplayHeader').valid,true);await writeFile(join(baseline,'replay-header.json'),JSON.stringify(replay,null,2)+'\n');
  const files=new Map();for(const name of ['recipe.bin','admissions.ndjson','events.ndjson'])files.set(name,await readFile(join(baseline,name)));
  validateDeclarations({manifestBytes,replay,checkpoint,files,identity,scenario:s});
  const report={kind:'reconstruction-proof',version:1,evidence_id:evidenceId,capability:'replay-from-start',configuration:'original-synthetic/0.1.0-prototype; dry ISA, fixed-step 120Hz, canonical paused boundary',
    comparison:'exact same-build canonical telemetry digest at every integrated tick, checkpoint/continuation samples and admitted/event histories',checkpoint_tick:'72000',continuation_ticks:'7200',pending_commands_preserved:2,negative_cases:baselineTiming.negative_cases,
    executable_sha256:identity[0],library_sha256:identity[1],contract_set_sha256:identity[2],source_fingerprint:identity[3],model_inventory_sha256:identity[4],compiler:identity[5],library_version:identity[6],build_fingerprint:buildFingerprint,
    checkpoint_trace_sha256:(await readFile(join(baseline,'checkpoint.sha256'),'utf8')).trim(),continuation_trace_sha256:(await readFile(join(restored,'continuation.sha256'),'utf8')).trim(),
    reconstruction_step_ms:restoredTiming.replayed_step_ns/1e6,total_reconstruction_proof_ms:restoredTiming.total_proof_ms,
    cost_scope:'step time excludes hashing/serialization/initialization; total includes initialization, reconstruction, traces and 60s continuation; engineering budget 30000ms provisional, measured not a portability guarantee',
    unsupported:['complete-checkpoint','wall-budget/fractional debt','render/worker/mailbox state','contact/terrain state','stochastic weather/RNG continuation','C172S/piston/propeller/systems/failures','ATC/scenario scripts','durable saves/crash recovery/migrations']};
  await writeFile(join(output,'report.json'),JSON.stringify(report,null,2)+'\n');return report;
}
if(process.argv[1]&&resolve(process.argv[1])===fileURLToPath(import.meta.url)) {
  const report=await runProof({executable:process.argv[2],output:process.argv[3]});console.log(JSON.stringify(report,null,2));
}
