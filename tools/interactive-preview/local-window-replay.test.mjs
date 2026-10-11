// Original MIT. Authored synthetic wire histories only: no simulator execution.
import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import os from 'node:os';
import {createHash,randomUUID} from 'node:crypto';
import {fileURLToPath,pathToFileURL} from 'node:url';
import {variant,method,scope,files,validateLocalWindowReplayReceipt as validate,validateLocalWindowReplaySources as sources} from './local-window-replay.mjs';
const here=path.dirname(fileURLToPath(import.meta.url));
const repository=process.env.LOCAL_WINDOW_REPLAY_TEST_REPOSITORY??path.resolve(here,'../..');
const fixtureRoot=process.env.LOCAL_WINDOW_REPLAY_FIXTURE_ROOT??path.join(repository,'tests/engine/local-window-replay');
const {validateContract}=await import(pathToFileURL(path.join(repository,'schemas/validate.mjs')));
const recipeBytes=fs.readFileSync(path.join(fixtureRoot,'recipe.json'));
const argumentBytes=fs.readFileSync(path.join(fixtureRoot,'argument-binary64.json'));
const recipe=JSON.parse(recipeBytes),fp='f'.repeat(64),modelRoot='C:/synthetic/local-window-models',session='synthetic-session-1';
const options={recipeBytes,argumentBytes,sourceFingerprint:fp,sourceVariant:variant,modelRoot,validateContract};
const unit={'fuel.total':'kg','engine.throttle':'fraction','engine.mixture':'fraction','propeller.angular_speed':'radps','engine.running':'bool','engine.ignition_left':'bool','engine.ignition_right':'bool','engine.starter':'bool','fuel.feed':'bool','engine.starved':'bool'};
const clone=structuredClone,zero=()=>({x:0,y:0,z:0});
function synthetic(){
 let tick=0,paused=false,scale=1,held={kind:'axes',roll:0,pitch:0,yaw:0,throttle:0,mixture:0,left_brake:1,right_brake:1,trim:0},pending=[];
 const calls=[],publications=[],systems={'engine.ignition_left':false,'engine.ignition_right':false,'engine.starter':false,'fuel.feed':true};
 for(const original of recipe.calls){
  const index=original.index,args=clone(original.arguments),events=[],applied=[];
  if(index===0)args[0]=modelRoot;else if(['submit','session_control'].includes(original.method))args[0].session_id=session;
  if(original.method==='submit')pending.push(clone(args[0]));
  if(original.method==='session_control'){
   const control=args[0],payload=clone(control.payload);
   if(payload.kind==='pause')paused=payload.paused;else {scale=payload.scale;payload.kind='time-scale';}
   events.push(JSON.stringify({type:'OperationalEvent',schema_version:1,tick:control.tick,session_id:session,sequence:control.sequence,source_id:control.source_id,confidence:'observed',content_version:'0.1.0-prototype',payload}));
  }
  const expected=clone(original.expected);
  if(index===296)Object.assign(expected,{completed:28,outcome:'completed',live:true,historical:false,fault:''});
  if(expected.completed>0){for(const command of pending){applied.push(JSON.stringify(command));if(command.payload.kind==='axes')held=clone(command.payload);else if(command.payload.kind==='system')systems[command.payload.control_id]=command.payload.value;}pending=[];}
  tick+=expected.completed??0;
  if(index===297){calls.push({index,method:original.method,arguments:args,reply:{ok:true,joined:true}});continue;}
  const position={latitude_rad:0,longitude_rad:0,ellipsoid_height_m:0};
  const aircraft={type:'AircraftSnapshot',schema_version:1,tick:String(tick),session_id:session,clock:{tick_rate_hz:120,purpose:'runtime'},elapsed_s:tick/120,position,ecef_position_m:{x:6378137,y:0,z:0},orientation_body_to_ned:{w:1,x:0,y:0,z:0},velocity_body_mps:zero(),angular_rate_body_radps:zero(),acceleration_body_mps2:zero(),mass_kg:1000,center_of_gravity_body_m:zero(),configuration:{flap_fraction:0,gear_fraction:1,trim_fraction:held.trim},systems:Object.entries(unit).map(([id,quantity])=>({id,quantity,value:id==='fuel.total'?100:id==='engine.throttle'?held.throttle:id==='engine.mixture'?held.mixture:quantity==='bool'?(systems[id]??false):0,validity:'valid'})),contacts:[],validity:'valid'};
  const weather={type:'AtmosphereSample',schema_version:1,tick:String(tick),session_id:session,position,pressure_pa:101325,temperature_k:288.15,density_kgpm3:1.225,relative_humidity:0,wind_toward_ned_mps:zero(),turbulence_ned_mps:zero(),seed:'42',model_id:'jsbsim-dry-isa'};
  const reply={...expected,schema_version:1,aircraft_json:JSON.stringify(aircraft),atmosphere_json:JSON.stringify(weather),held_axes:clone(held),paused,time_scale:scale,ground_query_valid:true,surface_height_m:0,plane_clearance_m:1,applied_commands_json:applied,events_json:events};
  if(index===0)Object.assign(reply,{runtime_modules:{'synthetic.dll':'C:/synthetic/synthetic.dll'},named_start:'piston-cold-ground',native_source_fingerprint:fp,world_anchor:{latitude_rad:0.8,longitude_rad:-2,ellipsoid_height_m:0},prepared_world_sha256:'04bff5a0bcf3509990f6276b2548a28268f57fc96d218a7ca51cab1990ec1ff5',wind_profile:'calm',angular_integration_method:method});
  calls.push({index,method:original.method,arguments:args,reply});
  if([0,295,296].includes(index))publications.push({index,tick:String(tick),aircraft_json:reply.aircraft_json,atmosphere_json:reply.atmosphere_json,held_axes:clone(held)});
 }
 return {passed:true,checks:12345,failures:[],scope,recipe_sha256:files['recipe.json'],argument_binary64_sha256:files['argument-binary64.json'],source_fingerprint:fp,source_variant:variant,angular_integration_method:method,argument_float_fields:138,schema_integer_fields:31,step_integer_fields:265,final_tick:'1607',continuation_completed:28,joined:true,calls,publications};
}
const baseline=synthetic();
test('authored synthetic full history meets canonical schemas and closed receipt',()=>{
 assert.deepEqual(validate(baseline,options),{checks:12345,calls:298,final_tick:'1607',continuation_completed:28,joined:true});
 const before=JSON.stringify(baseline);validate(baseline,options);assert.equal(JSON.stringify(baseline),before);
});
const commandIndex=baseline.calls.findIndex(row=>row.reply.applied_commands_json?.length);
const eventIndex=baseline.calls.findIndex(row=>row.reply.events_json?.length);
function wireMutate(receipt,index,field,mutate){const value=JSON.parse(receipt.calls[index].reply[field]);mutate(value);receipt.calls[index].reply[field]=JSON.stringify(value);}
const mutants={
 'failed result':r=>r.passed=false,
 'vacuous checks':r=>r.checks=0,
 'fractional checks':r=>r.checks=0.5,
 'false failure list':r=>r.failures=['synthetic'],
 'extra root key':r=>r.extra=1,
 'missing root key':r=>delete r.scope,
 'wrong scope':r=>r.scope='copied passing JSON',
 'legacy variant':r=>r.source_variant='jsbsim-1.3.1-event-aware-coupled-midpoint-v1',
 'foreign fingerprint':r=>r.source_fingerprint='a'.repeat(64),
 'wrong method':r=>r.angular_integration_method='legacy',
 'recipe hash':r=>r.recipe_sha256='0'.repeat(64),
 'sidecar hash':r=>r.argument_binary64_sha256='0'.repeat(64),
 'float restoration count':r=>r.argument_float_fields=137,
 'schema integer count':r=>r.schema_integer_fields='31',
 'step integer count':r=>r.step_integer_fields=264,
 'numeric final tick':r=>r.final_tick=1607,
 'continuation count':r=>r.continuation_completed=3,
 'unjoined summary':r=>r.joined=false,
 'missing actual call':r=>r.calls.splice(10,1),
 'duplicate call':r=>r.calls[10]=clone(r.calls[9]),
 'reordered calls':r=>[r.calls[10],r.calls[11]]=[r.calls[11],r.calls[10]],
 'call index':r=>r.calls[10].index='10',
 'call method':r=>r.calls[10].method='read_state',
 'call extra key':r=>r.calls[10].extra=true,
 'step string':r=>r.calls[2].arguments[0]='1',
 'schema string':r=>r.calls[1].arguments[0].schema_version='1',
 'numeric tick':r=>r.calls[1].arguments[0].tick=0,
 'numeric sequence':r=>r.calls[1].arguments[0].sequence=1,
 'numeric boolean':r=>r.calls[1].arguments[0].payload.paused=1,
 'wrong session binding':r=>r.calls[1].arguments[0].session_id='foreign',
 'wrong model binding':r=>r.calls[0].arguments[0]='C:/foreign',
 'one bit original mixture loss':r=>r.calls[295].arguments[0].payload.mixture=0.66,
 'old partial completion':r=>r.calls[296].reply.completed=3,
 'old discarded outcome':r=>r.calls[296].reply.outcome='discarded',
 'old continuation fault':r=>r.calls[296].reply.fault='coupled-shaft-decay-continuation-uncertified',
 'false native live':r=>r.calls[296].reply.live=false,
 'retained native snapshot':r=>r.calls[296].reply.historical=true,
 'unjoined actual close':r=>r.calls[297].reply.joined=false,
 'missing actual close':r=>r.calls[297].reply={ok:true},
 'extra native reply key':r=>r.calls[10].reply.extra=true,
 'wrong pause truth':r=>r.calls[1].reply.paused=false,
 'wrong native scale':r=>r.calls[1].reply.time_scale=4,
 'wrong open source':r=>r.calls[0].reply.native_source_fingerprint='0'.repeat(64),
 'wrong prepared anchor':r=>r.calls[0].reply.world_anchor.latitude_rad=0.9,
 'missing loaded module witness':r=>r.calls[0].reply.runtime_modules={},
 'malformed native JSON':r=>r.calls[20].reply.aircraft_json='{',
 'unknown snapshot key':r=>wireMutate(r,20,'aircraft_json',v=>v.extra=0),
 'invalid snapshot':r=>wireMutate(r,20,'aircraft_json',v=>v.validity='invalid'),
 'foreign weather identity':r=>wireMutate(r,20,'atmosphere_json',v=>v.session_id='foreign'),
 'wrong snapshot tick':r=>wireMutate(r,296,'aircraft_json',v=>v.tick='1582'),
 'wrong seed':r=>wireMutate(r,20,'atmosphere_json',v=>v.seed='43'),
 'wrong weather position':r=>wireMutate(r,20,'atmosphere_json',v=>v.position.latitude_rad=0.1),
 'duplicate channels':r=>wireMutate(r,20,'aircraft_json',v=>v.systems[1]=clone(v.systems[0])),
 'invalid channel':r=>wireMutate(r,20,'aircraft_json',v=>v.systems[0].validity='unavailable'),
 'adjacent native mixture':r=>wireMutate(r,296,'aircraft_json',v=>v.systems.find(c=>c.id==='engine.mixture').value=0.66),
 'wrong held ignition':r=>wireMutate(r,296,'aircraft_json',v=>v.systems.find(c=>c.id==='engine.ignition_left').value=false),
 'wrong held starter':r=>wireMutate(r,296,'aircraft_json',v=>v.systems.find(c=>c.id==='engine.starter').value=true),
 'missing delivered command':r=>r.calls[commandIndex].reply.applied_commands_json=[],
 'duplicate delivered command':r=>r.calls[commandIndex].reply.applied_commands_json.push(r.calls[commandIndex].reply.applied_commands_json[0]),
 'wrong applied payload':r=>{const v=JSON.parse(r.calls[commandIndex].reply.applied_commands_json[0]);v.payload.enabled=!v.payload.enabled;r.calls[commandIndex].reply.applied_commands_json[0]=JSON.stringify(v);},
 'missing lifecycle event':r=>r.calls[eventIndex].reply.events_json=[],
 'duplicate lifecycle event':r=>r.calls[eventIndex].reply.events_json.push(r.calls[eventIndex].reply.events_json[0]),
 'changed event source':r=>{const v=JSON.parse(r.calls[eventIndex].reply.events_json[0]);v.source_id='foreign';r.calls[eventIndex].reply.events_json[0]=JSON.stringify(v);},
 'held mixture mismatch':r=>r.calls[296].reply.held_axes.mixture=0.66,
 'missing checkpoint':r=>r.publications.pop(),
 'reordered checkpoints':r=>r.publications.reverse(),
 'checkpoint text changed':r=>r.publications[1].aircraft_json+=' ',
 'checkpoint held changed':r=>r.publications[2].held_axes.throttle=0.25,
};
for(const [name,mutate] of Object.entries(mutants))test('reject '+name,()=>{const value=clone(baseline);mutate(value);assert.throws(()=>validate(value,options));});
test('bound frozen source inputs and required canonical validator',()=>{
 for(const field of ['recipeBytes','argumentBytes']){const bad={...options,[field]:Buffer.from(options[field])};bad[field][10]^=1;assert.throws(()=>validate(baseline,bad));}
 assert.throws(()=>validate(baseline,{...options,validateContract:undefined}));
 assert.throws(()=>validate(baseline,{...options,sourceVariant:'legacy'}));
});
test('exact authored/staged/corresponding source copies and imported UID policy',()=>{
 const parent=process.env.LOCAL_WINDOW_REPLAY_TEST_WORK??os.tmpdir(),root=path.join(parent,'local-window-replay-source-'+randomUUID());
 const authored=path.join(root,'repo/tests/engine/local-window-replay'),project=path.join(root,'project'),sourceRoot=path.join(root,'source');
 const mapped=path.join(project,'local_window_replay_tests'),corresponding=path.join(sourceRoot,'local_window_replay_tests'),preserved=path.join(sourceRoot,'tests/engine/local-window-replay');
 fs.mkdirSync(root,{recursive:false});
 try{
  for(const base of [authored,mapped,corresponding,preserved]){fs.mkdirSync(base,{recursive:true});for(const name of Object.keys(files))fs.copyFileSync(path.join(fixtureRoot,name),path.join(base,name));}
  const resource=Buffer.from('extends RefCounted\nconst SCHEMA: String = "flight-native-build-identity-v1"\nconst SOURCE_VARIANT: String = "'+variant+'"\nconst BACKEND_IDENTITY_SHA256: String = "'+'a'.repeat(64)+'"\nconst BUILD_CONTROL_SHA256: String = "'+'b'.repeat(64)+'"\nconst SOURCE_FINGERPRINT: String = "'+fp+'"\n');
  for(const base of [project,sourceRoot]){fs.mkdirSync(path.join(base,'build'));fs.writeFileSync(path.join(base,'build/native_identity.gd'),resource);}
  const nativeIdentity={source_variant:variant,declared_source_fingerprint:fp,resource:{bytes:resource.length,sha256:createHash('sha256').update(resource).digest('hex')}};
  const opts={repository:path.join(root,'repo'),project,sourceRoot,nativeIdentity};
  assert.equal(sources(opts).length,4);
  fs.writeFileSync(path.join(mapped,'checks.gd.uid'),'uid://abc123\n');assert.equal(sources(opts).length,4);
  fs.writeFileSync(path.join(mapped,'checks.gd.uid'),'arbitrary');assert.throws(()=>sources(opts));fs.unlinkSync(path.join(mapped,'checks.gd.uid'));
  for(const base of [authored,mapped,corresponding,preserved]){
   fs.writeFileSync(path.join(base,'extra.txt'),'x');assert.throws(()=>sources(opts));fs.unlinkSync(path.join(base,'extra.txt'));
   const file=path.join(base,'checks.gd'),raw=fs.readFileSync(file);fs.appendFileSync(file,'\n');assert.throws(()=>sources(opts));fs.writeFileSync(file,raw);
   fs.renameSync(file,file+'.missing');assert.throws(()=>sources(opts));fs.renameSync(file+'.missing',file);
  }
  assert.throws(()=>sources({...opts,nativeIdentity:{...nativeIdentity,source_variant:'legacy'}}));
  assert.throws(()=>sources({...opts,nativeIdentity:{...nativeIdentity,declared_source_fingerprint:'c'.repeat(64)}}));
  fs.appendFileSync(path.join(project,'build/native_identity.gd'),'\n');assert.throws(()=>sources(opts));
 }finally{assert(root.startsWith(path.resolve(parent)+path.sep));fs.rmSync(root,{recursive:true,force:true});}
});
