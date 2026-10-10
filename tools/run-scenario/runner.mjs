import { readFile, writeFile, mkdir, stat, realpath } from 'node:fs/promises';
import { createHash } from 'node:crypto';
import { spawnSync } from 'node:child_process';
import { isDeepStrictEqual } from 'node:util';
import { resolve, dirname, join, relative, isAbsolute } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { validateContract, contractSetSha256 } from '../../schemas/validate.mjs';
import { currentSourceFingerprint } from './source-fingerprint.mjs';

export const repoRoot = resolve(dirname(fileURLToPath(import.meta.url)), '../..');
export const modelRoot = join(repoRoot, 'native/fdm_jsbsim/models/original-synthetic');
export const modelInventorySha256='1ccadb2e3d5aefe79f5a8f316631744ab4de18084469d2cf1817fb622cfabf7a';
const expectedFiles=[
  {path:'aircraft/original-synthetic/original-synthetic.xml',bytes:4691,sha256:'e271188986517f459197bb2a4573d5e912a1eeb31e9ad92593ed0ab43424136c'},
  {path:'engine/original-synthetic-direct.xml',bytes:100,sha256:'30c8dbec55a756c71d639aef1cf720decff0ba6730af5ec2062608a08d24d00b'},
  {path:'engine/original-synthetic-thrust.xml',bytes:561,sha256:'547581e279e9b3f383422ddff7991b0ff1cef6f02054bf0a979cd6859d9ef073'}];
export const sha = bytes => createHash('sha256').update(bytes).digest('hex');
const axesKeys = ['roll','pitch','yaw','throttle','mixture','left_brake','right_brake','trim'];
const vector = value => [value.x,value.y,value.z];
function requireContract(value,type) { const result=validateContract(value,type); if(!result.valid) throw new Error(`${type} rejected: ${JSON.stringify(result.errors)}`); }
function zero(value) { return Object.values(value).every(number=>number===0); }
export function checkInput(scenario,commands,{duration_s=10,trim_longitudinal=true,sample_hz=1}={}) {
  requireContract(scenario,'ScenarioManifest');
  if(scenario.required_aircraft.id!=='original-synthetic'||scenario.required_aircraft.version!=='0.1.0-prototype'||scenario.required_aircraft.sha256!==modelInventorySha256)
    throw new Error('Scenario requests an uninstalled/unreviewed aircraft package');
  if(scenario.required_world.id!=='synthetic-world'||scenario.required_world.version!=='0.1.0-prototype'||scenario.required_world.sha256!=='18df20b6fffc7295090455c0fadae0af0028d8711cee691b5aae53c9e06a10b6')
    throw new Error('Headless probe supports only the schema fixture world descriptor; operational world loading is unsupported');
  if(!Array.isArray(commands)||commands.length>4096) throw new Error('Command list exceeds bound');
  const a=scenario.initial_conditions.aircraft, w=scenario.initial_conditions.atmosphere;
  if(a.validity!=='initializing'||!zero(a.acceleration_body_mps2)||a.systems.length||a.contacts.length||scenario.allowed_assists.length||
     scenario.scheduled_actions.length||a.configuration.flap_fraction!==0||a.configuration.gear_fraction!==1||!zero(a.center_of_gravity_body_m)||
     Math.abs(a.mass_kg-1100)>.0001||w.relative_humidity!==0||!zero(w.turbulence_ned_mps)||w.model_id!=='jsbsim-dry-isa'||w.seed!==scenario.seed||!isDeepStrictEqual(w.position,a.position))
    throw new Error('Unsupported initial state, weather, assist or scheduled action; no omitted field is silently defaulted');
  if(Math.hypot(...vector(a.velocity_body_mps))<20||Math.hypot(...vector(a.velocity_body_mps))>200||Math.hypot(...vector(a.angular_rate_body_radps))>2||
     a.position.ellipsoid_height_m<100||a.position.ellipsoid_height_m>10000||Math.hypot(...vector(w.wind_toward_ned_mps))>100)throw new Error('Initial state outside bounded synthetic numerical domain');
  if(typeof trim_longitudinal!=='boolean'||!Number.isFinite(duration_s)||duration_s<=0||duration_s>600||!Number.isInteger(duration_s*scenario.clock.tick_rate_hz)||
     !Number.isInteger(sample_hz)||sample_hz<1||sample_hz>scenario.clock.tick_rate_hz||scenario.clock.tick_rate_hz%sample_hz)
    throw new Error('Unsupported duration/trim/sample options');
  const duration=BigInt(duration_s*scenario.clock.tick_rate_hz); let sequence=-1n;
  for(const command of commands) {
    requireContract(command,'ControlCommand');
    if(command.session_id!==a.session_id||command.authority!=='pilot'||command.source_id!=='pilot.controls'||command.assistance.profile_id!=='unassisted'||
       command.assistance.active.length||command.payload.kind!=='axes'||command.payload.mixture!==1||command.payload.left_brake!==0||command.payload.right_brake!==0||
       BigInt(command.tick)<1n||BigInt(command.tick)>duration||BigInt(command.sequence)<=sequence)
      throw new Error('Unsupported, out-of-range or nonmonotonic command');
    sequence=BigInt(command.sequence);
  }
  return {duration_ticks:duration,sample_interval_ticks:scenario.clock.tick_rate_hz/sample_hz,trim_longitudinal};
}
export function encodeRequest(scenario,commands,options={}) {
  const settings=checkInput(scenario,commands,options); const parts=[];
  const u=(value,size)=>{const b=Buffer.alloc(size);if(size===8)b.writeBigUInt64LE(BigInt(value));else if(size===4)b.writeUInt32LE(value);else if(size===2)b.writeUInt16LE(value);else b.writeUInt8(value);parts.push(b);};
  const d=value=>{const b=Buffer.alloc(8);b.writeDoubleLE(value);parts.push(b);};
  const id=value=>{const b=Buffer.from(value,'ascii');u(b.length,2);parts.push(b);};
  const a=scenario.initial_conditions.aircraft,w=scenario.initial_conditions.atmosphere;
  parts.push(Buffer.from('FSFDM001','ascii')); u(1,4);u(scenario.clock.tick_rate_hz,4);u(scenario.clock.purpose==='runtime'?0:1,1);u(settings.trim_longitudinal?1:0,1);
  u(settings.duration_ticks,8);u(settings.sample_interval_ticks,4);u(scenario.seed,8);id(a.session_id);
  for(const value of [a.position.latitude_rad,a.position.longitude_rad,a.position.ellipsoid_height_m,...vector(a.ecef_position_m),
    ...['w','x','y','z'].map(key=>a.orientation_body_to_ned[key]),...vector(a.velocity_body_mps),...vector(a.angular_rate_body_radps),a.mass_kg,
    ...vector(a.center_of_gravity_body_m),a.configuration.flap_fraction,a.configuration.gear_fraction,a.configuration.trim_fraction,
    w.pressure_pa,w.temperature_k,w.density_kgpm3,w.relative_humidity,...vector(w.wind_toward_ned_mps),...vector(w.turbulence_ned_mps)]) d(value);
  id(w.model_id);u(commands.length,4);
  for(const command of commands) { u(command.tick,8);u(command.sequence,8);id(command.source_id);u(0,1);id(command.assistance.profile_id);for(const key of axesKeys)d(command.payload[key]); }
  const bytes=Buffer.concat(parts);if(bytes.length>4*1024*1024)throw new Error('Transport exceeds bound');return bytes;
}
export async function verifyModel(root=modelRoot) {
  // The checked-in original inventory is also compared with compiled native pins before parser load.
  const inventoryBytes=await readFile(join(root,'inventory.json')); const inventory=JSON.parse(inventoryBytes);
  if(sha(inventoryBytes)!==modelInventorySha256||!isDeepStrictEqual(inventory.files,expectedFiles)) throw new Error('Wrong prototype inventory');
  const canonicalRoot=await realpath(root);
  for(const file of inventory.files) {
    const path=await realpath(join(root,file.path)); const rel=relative(canonicalRoot,path);
    if(rel.startsWith('..')||isAbsolute(rel))throw new Error('Model file outside root');
    const bytes=await readFile(path);if(bytes.length!==file.bytes||sha(bytes)!==file.sha256)throw new Error(`Model hash mismatch: ${file.path}`);
  }
  return {inventory,inventory_sha256:sha(inventoryBytes)};
}
function finiteTree(value) {
  if(typeof value==='number'&&!Number.isFinite(value))throw new Error('Nonfinite diagnostic record');
  if(value&&typeof value==='object')for(const nested of Object.values(value))finiteTree(nested);
}
function keys(value,expected) {
  if(!value||Array.isArray(value)||typeof value!=='object'||Object.keys(value).sort().join(',')!==[...expected].sort().join(','))throw new Error('Unexpected diagnostic shape');
}
function finiteRange(value,min,max) {if(typeof value!=='number'||!Number.isFinite(value)||value<min||value>max)throw new Error('Diagnostic outside finite bounds');}
function diagnosticVector(value,bound) {keys(value,['x','y','z']);for(const component of Object.values(value))finiteRange(component,-bound,bound);}
function uint64(value) {if(typeof value!=='string'||! /^(0|[1-9][0-9]{0,19})$/.test(value)||BigInt(value)>18446744073709551615n)throw new Error('Invalid diagnostic uint64');}
export function validateOutput(records,context) {
  if(!records.length||records[0].kind!=='fdm-initialization'||records[0].version!==1)throw new Error('Missing initialization receipt');
  keys(records[0],['kind','version','loaded_library_path','library_version','compiler','source_fingerprint','requested_seed','engine_seed','trim','solved_controls',
    'fuel_frozen_during_trim','initial_fuel_kg','initialization_step_s','accepted_aircraft','accepted_atmosphere']);
  requireContract(records[0].accepted_aircraft,'AircraftSnapshot');requireContract(records[0].accepted_atmosphere,'AtmosphereSample');
  if(records[0].accepted_aircraft.tick!=='0'||!Number.isInteger(records[0].engine_seed)||records[0].engine_seed<0||records[0].engine_seed>2147483647)throw new Error('Invalid initialized boundary');
  const init=records[0];uint64(init.requested_seed);
  if(typeof init.loaded_library_path!=='string'||init.loaded_library_path.length<1||init.loaded_library_path.length>32768||/[\x00-\x1f]/.test(init.loaded_library_path)||
     typeof init.library_version!=='string'||! /^1\.3\.1(?: [\x20-\x7e]{1,192})?$/.test(init.library_version)||typeof init.compiler!=='string'||!/^(MSVC|GNU)-[0-9.]+$/.test(init.compiler)||! /^[0-9a-f]{64}$/.test(init.source_fingerprint)||
     init.fuel_frozen_during_trim!==true||init.initialization_step_s!==1/120)throw new Error('Invalid native build/initialization receipt');
  finiteRange(init.initial_fuel_kg,0,100.0001);keys(init.trim,['longitudinal','gamma_fallback','max_cycles','max_cycles_per_axis','acceleration_tolerance_mps2']);
  if(typeof init.trim.longitudinal!=='boolean'||init.trim.gamma_fallback!==false||!Number.isInteger(init.trim.max_cycles)||!Number.isInteger(init.trim.max_cycles_per_axis))throw new Error('Invalid trim receipt');
  finiteRange(init.trim.max_cycles,1,1000);finiteRange(init.trim.max_cycles_per_axis,1,1000);finiteRange(init.trim.acceleration_tolerance_mps2,.0000003048,.003048);
  keys(init.solved_controls,['kind',...axesKeys]);if(init.solved_controls.kind!=='axes')throw new Error('Invalid solved controls');
  for(const key of axesKeys)finiteRange(init.solved_controls[key],['roll','pitch','yaw','trim'].includes(key)?-1:0,1);
  if(init.solved_controls.mixture!==1||init.solved_controls.left_brake!==0||init.solved_controls.right_brake!==0)throw new Error('Unsupported solved controls');
  const fuel=init.accepted_aircraft.systems.find(channel=>channel.id==='fuel.total');const throttle=init.accepted_aircraft.systems.find(channel=>channel.id==='engine.throttle');
  if(!fuel||fuel.quantity!=='kg'||Math.abs(fuel.value-init.initial_fuel_kg)>1e-9||Math.abs(init.initial_fuel_kg-100)>.0001||
     !throttle||throttle.quantity!=='fraction'||throttle.value!==init.solved_controls.throttle||init.accepted_aircraft.configuration.trim_fraction!==init.solved_controls.trim)
    throw new Error('Initialization controls/fuel receipt conflicts with accepted state');
  for(const record of records) {
    if(record.type) {
      if(!['AircraftSnapshot','AtmosphereSample','ControlCommand','OperationalEvent'].includes(record.type))throw new Error('Unexpected output boundary');
      requireContract(record,record.type);
    } else if(record.kind==='fdm-diagnostics'&&record.version===1) {
      keys(record,['kind','version','tick','session_id','alpha_rad','beta_rad','dynamic_pressure_pa','airspeed_mps','air_relative_rate_radps','aerodynamic_force_body_n',
        'aerodynamic_moment_cg_body_nm','drag_side_lift_n','fuel_kg','jsbsim_controls']);uint64(record.tick);
      if(typeof record.session_id!=='string'||record.session_id.length>128)throw new Error('Invalid diagnostic session');
      finiteRange(record.alpha_rad,-Math.PI,Math.PI);finiteRange(record.beta_rad,-Math.PI,Math.PI);finiteRange(record.dynamic_pressure_pa,0,1e9);finiteRange(record.airspeed_mps,0,2000);
      diagnosticVector(record.air_relative_rate_radps,100);diagnosticVector(record.aerodynamic_force_body_n,1e12);
      for(const key of ['aerodynamic_moment_cg_body_nm','drag_side_lift_n']){
        if(!Array.isArray(record[key])||record[key].length!==3)throw new Error('Invalid diagnostic force/moment shape');for(const value of record[key])finiteRange(value,-1e12,1e12);
      }
      finiteRange(record.fuel_kg,0,100.0001);keys(record.jsbsim_controls,['aileron','elevator','rudder','pitch_trim','throttle']);
      for(const [key,value]of Object.entries(record.jsbsim_controls))finiteRange(value,key==='throttle'?0:-1,1);
    } else if(record!==init)throw new Error('Unknown/repeated diagnostic record');
    finiteTree(record);
  }
  if(context) {
    const {scenario,commands,options={}}=context;const settings=checkInput(scenario,commands,options),session=scenario.initial_conditions.aircraft.session_id;
    if(init.requested_seed!==scenario.seed||init.trim.longitudinal!==settings.trim_longitudinal)throw new Error('Initialization differs from request');
    if(context.expectedSourceFingerprint&&init.source_fingerprint!==context.expectedSourceFingerprint)throw new Error('Compiled adapter differs from current source fingerprint');
    const requested=scenario.initial_conditions,accepted=init.accepted_atmosphere;
    if(Math.abs(accepted.pressure_pa-requested.atmosphere.pressure_pa)>1||Math.abs(accepted.temperature_k-requested.atmosphere.temperature_k)>.02||
       Math.abs(accepted.density_kgpm3-requested.atmosphere.density_kgpm3)>.0001||accepted.relative_humidity!==0||!zero(accepted.turbulence_ned_mps)||
       vector(accepted.wind_toward_ned_mps).some((v,i)=>Math.abs(v-vector(requested.atmosphere.wind_toward_ned_mps)[i])>1e-9)||
       Math.abs(init.accepted_aircraft.mass_kg-requested.aircraft.mass_kg)>.0001||!zero(init.accepted_aircraft.center_of_gravity_body_m)||
       Math.abs(init.accepted_aircraft.position.latitude_rad-requested.aircraft.position.latitude_rad)>1e-10||
       Math.abs(init.accepted_aircraft.position.longitude_rad-requested.aircraft.position.longitude_rad)>1e-10||
       Math.abs(init.accepted_aircraft.position.ellipsoid_height_m-requested.aircraft.position.ellipsoid_height_m)>1e-5)
      throw new Error('Accepted initialization differs from supported request');
    const seed=BigInt(scenario.seed);if(init.engine_seed!==Number((seed^(seed>>31n)^(seed>>62n))&2147483647n))throw new Error('Wrong engine seed fold');
    const boundary=(record,type,tick)=>{
      if(!record||record.type!==type||record.tick!==String(tick)||record.session_id!==session)throw new Error('Output session/tick/type differs from scheduled boundary');
      if(type==='AircraftSnapshot'&&(!isDeepStrictEqual(record.clock,scenario.clock)||record.validity!=='valid'||record.systems.some(channel=>channel.validity!=='valid')))throw new Error('Output clock/validity differs from supported context');
      if(type==='AtmosphereSample'&&(record.seed!==scenario.seed||record.model_id!=='jsbsim-dry-isa'))throw new Error('Output atmosphere identity differs from request');
    };
    boundary(init.accepted_aircraft,'AircraftSnapshot',0);boundary(init.accepted_atmosphere,'AtmosphereSample',0);
    const diagnostic=(record,tick)=>{if(!record||record.kind!=='fdm-diagnostics'||record.tick!==String(tick)||record.session_id!==session)throw new Error('Diagnostic context differs from snapshot');};
    boundary(records[1],'AircraftSnapshot',0);diagnostic(records[2],0);if(!isDeepStrictEqual(init.accepted_aircraft,records[1]))throw new Error('Tick-zero state differs from initialization');
    const sorted=[...commands].sort((a,b)=>BigInt(a.tick)<BigInt(b.tick)?-1:BigInt(a.tick)>BigInt(b.tick)?1:BigInt(a.sequence)<BigInt(b.sequence)?-1:1);
    let index=3,commandIndex=0;
    for(let tick=1n;tick<=settings.duration_ticks;++tick) {
      while(commandIndex<sorted.length&&BigInt(sorted[commandIndex].tick)===tick){if(!isDeepStrictEqual(records[index++],sorted[commandIndex++]))throw new Error('Applied command differs from validated scheduled command');}
      if(tick%BigInt(settings.sample_interval_ticks)===0n||tick===settings.duration_ticks){boundary(records[index++],'AircraftSnapshot',tick);boundary(records[index++],'AtmosphereSample',tick);diagnostic(records[index++],tick);}
    }
    if(index!==records.length||commandIndex!==sorted.length)throw new Error('Missing/excess/out-of-order output records');
  }
}
export async function runScenario(scenario,commands=[],options={}) {
  const bytes=encodeRequest(scenario,commands,options); const model=await verifyModel();
  const outDir=resolve(options.out_dir??join(repoRoot,'.local/fdm-run'));await mkdir(outDir,{recursive:true});
  const scenarioBytes=JSON.stringify(scenario,null,2)+'\n',commandBytes=JSON.stringify(commands,null,2)+'\n';
  await writeFile(join(outDir,'scenario.json'),scenarioBytes);await writeFile(join(outDir,'commands.json'),commandBytes);
  const requestPath=join(outDir,'request.bin'),outputPath=join(outDir,'telemetry.ndjson'); await writeFile(requestPath,bytes);
  const executable=resolve(options.executable??join(repoRoot,'.local/build/native-release/bin',process.platform==='win32'?'fdm_harness.exe':'fdm_harness'));
  const expectedSourceFingerprint=await currentSourceFingerprint(executable);
  const result=spawnSync(executable,[modelRoot,requestPath,outputPath],{encoding:'utf8',env:{...process.env,JSBSIM_DEBUG:'0'},timeout:120000,maxBuffer:1024*1024});
  await writeFile(join(outDir,'native-log.txt'),`${result.stdout??''}${result.stderr??''}`);
  if(result.error||result.status!==0)throw new Error(`Native runner failed: ${result.error?.message??result.stderr??result.status}`);
  if((await stat(outputPath)).size>100*1024*1024)throw new Error('Telemetry exceeds bound');
  const output=await readFile(outputPath);const records=output.toString('utf8').trim().split('\n').map(line=>JSON.parse(line));
  validateOutput(records,{scenario,commands,options,expectedSourceFingerprint});
  const states=records.filter(record=>record.type==='AircraftSnapshot');
  if(BigInt(states.at(-1).tick)!==BigInt((options.duration_s??10)*scenario.clock.tick_rate_hz))throw new Error('Incomplete runner output');
  const performance=JSON.parse(await readFile(outputPath+'.timing.json','utf8'));
  keys(performance,['kind','version','steps','step_scope','p50_ns','p99_ns','max_ns']);
  if(performance.kind!=='fdm-performance'||performance.version!==1||performance.step_scope!=='session.step_fixed-no-output-serialization'||performance.steps!==Number(states.at(-1).tick))throw new Error('Invalid step performance receipt');
  for(const key of ['p50_ns','p99_ns','max_ns'])if(!Number.isSafeInteger(performance[key])||performance[key]<0)throw new Error('Invalid performance number');
  if(performance.p50_ns>performance.p99_ns||performance.p99_ns>performance.max_ns)throw new Error('Invalid performance ordering');
  const provenance={version:1,model,contract_set_sha256:contractSetSha256,request_sha256:sha(bytes),input_scenario_sha256:sha(scenarioBytes),
    input_commands_sha256:sha(commandBytes),executable_sha256:sha(await readFile(executable)),telemetry_sha256:sha(output),
    platform:process.platform,architecture:process.arch,tick_rate_hz:scenario.clock.tick_rate_hz,seed:scenario.seed,restoration:'fresh-executive-replay-only-unproven',
    loaded_jsbsim:{sha256:sha(await readFile(records[0].loaded_library_path)),version:records[0].library_version},
    compiler:records[0].compiler,source_fingerprint:records[0].source_fingerprint,performance,dependency_lock_sha256:sha(await readFile(join(repoRoot,'third_party/dependencies.lock.json'))),
    build_manifest_sha256:sha(await readFile(join(dirname(executable),'../toolchain-build-manifest.txt'))),
    initialization:records[0],limitations:['original-synthetic-no-aircraft-calibration','no-ground-contacts','no-stall-envelope','no-propeller','no-mixture-brakes','dry-isa-constant-wind']};
  if(await currentSourceFingerprint(executable)!==expectedSourceFingerprint)throw new Error('Source or declared build identity changed during the native run');
  await writeFile(join(outDir,'provenance.json'),JSON.stringify(provenance,null,2)+'\n');
  return {records,states,provenance,out_dir:outDir};
}
if(process.argv[1]&&import.meta.url===pathToFileURL(process.argv[1]).href) {
  const [, ,scenarioPath,commandPath,outPath]=process.argv;if(!scenarioPath||!commandPath||!outPath)throw new Error('Usage: node tools/run-scenario/runner.mjs <ScenarioManifest.json> <commands.json> <output-dir>');
  const result=await runScenario(JSON.parse(await readFile(scenarioPath,'utf8')),JSON.parse(await readFile(commandPath,'utf8')),{out_dir:outPath});
  console.log(`Validated ${result.states.length} authoritative snapshots; provenance in ${result.out_dir}`);
}
