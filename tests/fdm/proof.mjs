import assert from 'node:assert/strict';
import { writeFile, mkdir, readFile } from 'node:fs/promises';
import { join } from 'node:path';
import { runScenario, repoRoot, sha } from '../../tools/run-scenario/runner.mjs';
import { scenario, command } from './fixture.mjs';
const evidenceRoot=join(repoRoot,'.local/fdm-proof');await mkdir(evidenceRoot,{recursive:true});
// Thresholds declared before first measured traces; solver acceptance, no aircraft references.
const thresholds={60:{position_m:2,velocity_mps:.05,attitude_rad:.002,rate_radps:.002},120:{position_m:.5,velocity_mps:.02,attitude_rad:.001,rate_radps:.001}};
const normDiff=(a,b)=>Math.hypot(a.x-b.x,a.y-b.y,a.z-b.z);
const comparison=(a,b)=>{const qa=a.orientation_body_to_ned,qb=b.orientation_body_to_ned;const dot=Math.abs(['w','x','y','z'].reduce((sum,key)=>sum+qa[key]*qb[key],0));
  return {position_m:normDiff(a.ecef_position_m,b.ecef_position_m),velocity_mps:normDiff(a.velocity_body_mps,b.velocity_body_mps),
    attitude_rad:2*Math.acos(Math.min(1,dot)),rate_radps:normDiff(a.angular_rate_body_radps,b.angular_rate_body_radps)};};
const s=await scenario(); const trimmed=await runScenario(s,[],{out_dir:join(evidenceRoot,'trim'),duration_s:10});
const controls={...trimmed.records[0].solved_controls};delete controls.kind;
const pulses=rateScenario=>[
  command(rateScenario,1,1,{...controls,roll:.02}),command(rateScenario,2,2,controls),
  command(rateScenario,3,3,{...controls,pitch:controls.pitch+.025}),command(rateScenario,4,4,controls),
  command(rateScenario,5,5,{...controls,yaw:.04}),command(rateScenario,6,6,controls)];
const runs={};for(const hz of [60,120,240]){const input=await scenario(hz);runs[hz]=await runScenario(input,pulses(input),{out_dir:join(evidenceRoot,`hz${hz}`),duration_s:10,sample_hz:2});}
const repeat=await runScenario(s,pulses(s),{out_dir:join(evidenceRoot,'repeat'),duration_s:10,sample_hz:2});
assert.equal(repeat.provenance.telemetry_sha256,runs[120].provenance.telemetry_sha256,'Same build/seed full telemetry exact repeat');
const errors={},sampledMaxima={};for(const hz of [60,120]){
  errors[hz]=comparison(runs[hz].states.at(-1),runs[240].states.at(-1));sampledMaxima[hz]=Object.fromEntries(Object.keys(thresholds[hz]).map(key=>[key,0]));
  assert.equal(runs[hz].states.length,runs[240].states.length);
  runs[hz].states.forEach((state,index)=>{assert.equal(state.elapsed_s,runs[240].states[index].elapsed_s);const difference=comparison(state,runs[240].states[index]);
    for(const key of Object.keys(thresholds[hz]))sampledMaxima[hz][key]=Math.max(sampledMaxima[hz][key],difference[key]);});
  for(const key of Object.keys(thresholds[hz]))assert.ok(sampledMaxima[hz][key]<=thresholds[hz][key],`${hz}Hz sampled ${key} ${sampledMaxima[hz][key]} exceeds ${thresholds[hz][key]}`);
}
const referencePath=join(repoRoot,'tests/fdm/reference/windows-msvc-19.40.json');
if(process.argv.includes('--capture-reference')) {
  if(process.platform!=='win32')throw new Error('Reference capture is explicit Windows-only');
  await writeFile(referencePath,JSON.stringify({version:1,classification:'observed numerical regression trace; not independent aircraft truth',
    model_inventory_sha256:runs[120].provenance.model.inventory_sha256,loaded_jsbsim:runs[120].provenance.loaded_jsbsim,
    compiler:runs[120].provenance.compiler,source_fingerprint:runs[120].provenance.source_fingerprint,
    scenario:await scenario(),commands:pulses(await scenario()),states:runs[120].states},null,2)+'\n');
}
const reference=JSON.parse(await readFile(referencePath,'utf8'));
const crossPlatformTolerance={position_m:.001,velocity_mps:.00001,attitude_rad:.000001,rate_radps:.000001};
assert.equal(reference.model_inventory_sha256,runs[120].provenance.model.inventory_sha256);
assert.equal(reference.states.length,runs[120].states.length);const crossPlatformMaxima=Object.fromEntries(Object.keys(crossPlatformTolerance).map(key=>[key,0]));
runs[120].states.forEach((state,index)=>{const difference=comparison(state,reference.states[index]);for(const key of Object.keys(crossPlatformTolerance)){
  crossPlatformMaxima[key]=Math.max(crossPlatformMaxima[key],difference[key]);assert.ok(difference[key]<=crossPlatformTolerance[key],`Cross-build sample${index} ${key} exceeds declared budget`);}});
const long=await runScenario(s,[],{out_dir:join(evidenceRoot,'long'),duration_s:600});
for(const state of long.states){assert.ok(state.position.ellipsoid_height_m>100&&state.position.ellipsoid_height_m<20000);const speed=Math.hypot(...Object.values(state.velocity_body_mps));assert.ok(speed>20&&speed<200);}
assert.ok(long.states.at(-1).mass_kg<long.states[0].mass_kg,'Fuel consumption changes actual flight mass');
// Frozen original equations can now be independently verified from diagnostic inputs/outputs in #19.
const receipt={version:1,scope:'original synthetic solver/adapter only; no C172S, ground or pilot acceptance',thresholds,same_build_repeat:{bit_equal_telemetry:true,sha256:repeat.provenance.telemetry_sha256},
  convergence_errors:errors,aligned_sampled_maxima:sampledMaxima,sample_hz:2,continuous_time_error_bound:false,clock_rates:[60,120,240],control_onset_seconds:[1,2,3,4,5,6],trim:trimmed.records[0],
  cross_platform:{classification:'numerical regression, no bit-identity guarantee',reference_sha256:sha(await readFile(referencePath)),tolerances:crossPlatformTolerance,sampled_maxima:crossPlatformMaxima},
  long_run:{duration_s:600,initial_mass_kg:long.states[0].mass_kg,final_mass_kg:long.states.at(-1).mass_kg,final_height_m:long.states.at(-1).position.ellipsoid_height_m},
  run_provenance:Object.fromEntries(Object.entries(runs).map(([hz,run])=>[hz,run.provenance])),long_provenance:long.provenance};
await writeFile(join(evidenceRoot,'report.json'),JSON.stringify(receipt,null,2)+'\n');
console.log(JSON.stringify({same_build_exact:true,convergence:errors,sampled_maxima:sampledMaxima,long_run:receipt.long_run,report_sha256:sha(await readFile(join(evidenceRoot,'report.json')))},null,2));
