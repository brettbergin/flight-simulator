import {readFile,stat,writeFile,mkdir} from 'node:fs/promises';
import {createHash} from 'node:crypto';import {resolve,dirname,join} from 'node:path';import {fileURLToPath,pathToFileURL}from'node:url';
import {evaluate,unsignedTerms,outputKeys,bodyForce}from'./equations.mjs';import{validateCorpus,validateMatrix,modelPin}from'./validate.mjs';
import{validateOutput,encodeRequest,verifyModel}from'../run-scenario/runner.mjs';
import {contractSetSha256} from '../../schemas/validate.mjs';
import {isDeepStrictEqual} from 'node:util';
// Reports retain file digests, not machine-local library paths or user data.
const root=resolve(dirname(fileURLToPath(import.meta.url)),'../..');export const sha=b=>createHash('sha256').update(b).digest('hex');
const within=(a,b,abs,rel)=>Math.abs(a-b)<=abs+rel*Math.abs(b);
export function compareCorpus(c){validateCorpus(c);return c.cases.map(row=>{const values=evaluate(Object.fromEntries(Object.entries(row.inputs).map(([k,v])=>[k,Number(v)])));const errors=outputKeys.filter(k=>!within(values[k],Number(row.expected_decimal[k]),c.threshold.absolute,c.threshold.relative));return{id:row.id,status:errors.length?'failed':'passed',classification:c.classification,failed_quantities:errors};});}
export function compareDiagnostic(d,w,budget){
 const x={rho_kg_m3:w.density_kgpm3,tas_mps:d.airspeed_mps,alpha_rad:d.alpha_rad,beta_rad:d.beta_rad,p_aero_rad_s:d.air_relative_rate_radps.x,q_aero_rad_s:d.air_relative_rate_radps.y,r_aero_rad_s:d.air_relative_rate_radps.z,jsb_aileron:d.jsbsim_controls.aileron,jsb_elevator:d.jsbsim_controls.elevator,jsb_trim:d.jsbsim_controls.pitch_trim,jsb_rudder:d.jsbsim_controls.rudder};
 const e=evaluate(x),terms=unsignedTerms(x,e),observed={drag_wind_n:d.drag_side_lift_n[0],side_wind_n:d.drag_side_lift_n[1],lift_wind_n:d.drag_side_lift_n[2],roll_body_nm:d.aerodynamic_moment_cg_body_nm[0],pitch_body_nm:d.aerodynamic_moment_cg_body_nm[1],yaw_body_nm:d.aerodynamic_moment_cg_body_nm[2]};
 const errors=[];for(const[k,v]of Object.entries(observed)){const limit=budget.absolute+budget.relative*terms[k];if(!Number.isFinite(v)||Math.abs(v-e[k])>limit)errors.push({quantity:k,observed:v,expected:e[k],absolute_error:Math.abs(v-e[k]),allowed_absolute_error:limit});}
 const body=bodyForce(x,e);
 // Each direction-cosine magnitude is <=1; propagate the unsigned force bounds.
 const forceBudget=budget.absolute+budget.relative*(terms.drag_wind_n+terms.side_wind_n+terms.lift_wind_n);
 for(const axis of ['x','y','z'])if(!Number.isFinite(d.aerodynamic_force_body_n?.[axis])||Math.abs(d.aerodynamic_force_body_n[axis]-body[axis])>forceBudget)
  errors.push({quantity:'aerodynamic_force_body_n.'+axis,observed:d.aerodynamic_force_body_n?.[axis],expected:body[axis],allowed_absolute_error:forceBudget});
 if(!within(d.dynamic_pressure_pa,e.qbar_pa,1e-8,1e-12))errors.push({quantity:'dynamic_pressure_pa',observed:d.dynamic_pressure_pa,expected:e.qbar_pa});
 return{tick:d.tick,status:errors.length?'failed':'passed',errors};
}
async function bytes(path,max=100*1024*1024){if((await stat(path)).size>max)throw Error('Validation input exceeds byte bound');return readFile(path);}
export async function inspectRun(folder,matrix){
 const [telemetry,provenanceBytes,scenarioBytes,commandBytes]=await Promise.all(['telemetry.ndjson','provenance.json','scenario.json','commands.json'].map(n=>bytes(join(folder,n))));
 const records=telemetry.toString('utf8').trim().split('\n').map(JSON.parse),provenance=JSON.parse(provenanceBytes),scenario=JSON.parse(scenarioBytes),commands=JSON.parse(commandBytes);
 if(provenance.version!==1||provenance.model?.inventory_sha256!==modelPin||sha(telemetry)!==provenance.telemetry_sha256||sha(scenarioBytes)!==provenance.input_scenario_sha256||sha(commandBytes)!==provenance.input_commands_sha256||! /^[a-f0-9]{64}$/.test(provenance.source_fingerprint)||!/^1\.3\.1(?: [\x20-\x7e]{1,192})?$/.test(provenance.loaded_jsbsim?.version??''))throw Error('Incompatible/unbound run provenance');
 const hashFields=['contract_set_sha256','request_sha256','executable_sha256','dependency_lock_sha256','build_manifest_sha256'];
 if(hashFields.some(k=>typeof provenance[k]!=='string'||!/^[0-9a-f]{64}$/.test(provenance[k]))||
   !/^[0-9a-f]{64}$/.test(provenance.loaded_jsbsim.sha256??'')||
   provenance.contract_set_sha256!==contractSetSha256||
   !['win32','linux'].includes(provenance.platform)||provenance.architecture!=='x64'||
   // JSON serialization normalizes -0 to 0; compare the serialized receipt semantics.
   !isDeepStrictEqual(provenance.initialization,JSON.parse(JSON.stringify(records[0])))||
   provenance.compiler!==records[0].compiler||provenance.loaded_jsbsim.version!==records[0].library_version||
   provenance.tick_rate_hz!==scenario.clock.tick_rate_hz||provenance.seed!==scenario.seed||
   !isDeepStrictEqual(provenance.model,await verifyModel()))throw Error('Incomplete/conflicting run provenance');
 const states=records.filter(r=>r.type==='AircraftSnapshot'),rate=scenario.clock.tick_rate_hz;
 if(states.length<2)throw Error('Incomplete sampled run');const duration=Number(BigInt(states.at(-1).tick))/rate,interval=Number(BigInt(states[1].tick));
 const options={duration_s:duration,sample_hz:rate/interval,trim_longitudinal:records[0].trim.longitudinal};
 if(sha(encodeRequest(scenario,commands,options))!==provenance.request_sha256)throw Error('Request/provenance differs');
 validateOutput(records,{scenario,commands,options,expectedSourceFingerprint:provenance.source_fingerprint});
 if(states.some(s=>s.center_of_gravity_body_m.x!==0||s.center_of_gravity_body_m.y!==0||s.center_of_gravity_body_m.z!==0||s.contacts.length))throw Error('Unsupported model datum/contact configuration');
 const weather=new Map(records.filter(r=>r.type==='AtmosphereSample').map(r=>[r.tick,r]));weather.set('0',records[0].accepted_atmosphere);
 const comparisons=records.filter(r=>r.kind==='fdm-diagnostics').map(d=>compareDiagnostic(d,weather.get(d.tick),matrix.rows.find(r=>r.id==='original-force-identities').uncertainty));
 return{id:'original-force-identities',status:comparisons.some(r=>r.status==='failed')?'failed':'passed',classification:'independent-equation-comparison',samples:comparisons.length,failed_samples:comparisons.filter(r=>r.status==='failed'),build:{platform:provenance.platform,architecture:provenance.architecture,executable_sha256:provenance.executable_sha256,loaded_jsbsim:provenance.loaded_jsbsim,compiler:provenance.compiler,source_fingerprint:provenance.source_fingerprint,contract_set_sha256:provenance.contract_set_sha256,request_sha256:provenance.request_sha256,dependency_lock_sha256:provenance.dependency_lock_sha256,build_manifest_sha256:provenance.build_manifest_sha256},inputs:{telemetry_sha256:sha(telemetry),provenance_sha256:sha(provenanceBytes),scenario_sha256:sha(scenarioBytes),commands_sha256:sha(commandBytes)},hardware_input_profile:'scripted-headless-no-peripheral'};
}
export async function runValidation({matrixPath=join(root,'tests/reference/matrix-v1.json'),corpusPath=join(root,'tests/reference/original-polynomial-v1.json'),runDir=null,output=null}={}){
 const mb=await bytes(matrixPath,1024*1024),cb=await bytes(corpusPath,1024*1024),m=validateMatrix(JSON.parse(mb)),c=validateCorpus(JSON.parse(cb));
 const results=compareCorpus(c);if(runDir)results.push(await inspectRun(resolve(runDir),m));else results.push({id:'original-force-identities',status:'unsupported',reason:'No observed run supplied; algebra checks cannot establish backend agreement'});
 results.push(...m.rows.filter(r=>r.status==='unsupported').map(r=>({id:r.id,status:'unsupported',reason:r.reason,quantity:r.quantity,unit:r.unit,airspeed_domain:r.airspeed_domain,distance_endpoint:r.distance_endpoint})));
 const report={schema_version:1,matrix_revision:m.revision,scope:'original synthetic algebra and sampled backend comparison; no aircraft qualification or training credit',matrix_sha256:sha(mb),corpus_sha256:sha(cb),model_inventory_sha256:modelPin,results,counts:Object.fromEntries(['passed','failed','unsupported'].map(k=>[k,results.filter(r=>r.status===k).length])),aircraft_qualified:false,automatically_fitted:false};
 if(output){await mkdir(dirname(resolve(output)),{recursive:true});await writeFile(output,JSON.stringify(report,null,2)+'\n');}return report;
}
if(process.argv[1]&&import.meta.url===pathToFileURL(process.argv[1]).href){const args=process.argv.slice(2);if(args.some((a,i)=>i%2===0&&!['--run-dir','--output'].includes(a))||args.length%2)throw Error('Usage: node tools/validation/runner.mjs [--run-dir artifact-folder] [--output report.json]');const options={};for(let i=0;i<args.length;i+=2)options[args[i]==='--run-dir'?'runDir':'output']=args[i+1];const r=await runValidation(options);console.log(JSON.stringify(r));if(r.counts.failed)process.exitCode=1;}
