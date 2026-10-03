import test from 'node:test';
import assert from 'node:assert/strict';
import { encodeRequest, checkInput, validateOutput } from '../../tools/run-scenario/runner.mjs';
import { scenario, command } from './fixture.mjs';
const base=await scenario();const axes={roll:0,pitch:0,yaw:0,throttle:.65,mixture:1,left_brake:0,right_brake:0,trim:0};
test('wire scenario and all64seedbits become bounded LE native request',()=>{
  const bytes=encodeRequest(base,[command(base,0,'9007199254740993',axes)]);assert.equal(bytes.subarray(0,8).toString(),'FSFDM001');
  assert.equal(bytes.readBigUInt64LE(30),9007199254740993n);assert.ok(bytes.length<1024);
});
test('generic valid wire cannot silently omit unsupported initial state, assistance or actions',()=>{
  for(const edit of [s=>s.initial_conditions.aircraft.acceleration_body_mps2.x=1,s=>s.initial_conditions.aircraft.validity='valid',
    s=>s.initial_conditions.aircraft.systems.push({id:'engine.running',quantity:'boolean',value:true,validity:'valid'}),
    s=>s.initial_conditions.aircraft.contacts.push({id:'left.gear',point_body_m:{x:1,y:2,z:3},force_body_n:{x:0,y:0,z:0},on_ground:true}),
    s=>s.allowed_assists.push('auto-rudder'),s=>s.scheduled_actions.push({tick:'1',action_id:'engine.fail',target_id:'ownship'}),
    s=>s.initial_conditions.atmosphere.relative_humidity=.5,s=>s.initial_conditions.atmosphere.turbulence_ned_mps.x=1,
    s=>s.initial_conditions.atmosphere.seed='1',s=>s.initial_conditions.atmosphere.position.longitude_rad=1,
    s=>s.initial_conditions.atmosphere.position.ellipsoid_height_m+=.01,s=>s.initial_conditions.aircraft.mass_kg=1000]) {const value=structuredClone(base);edit(value);assert.throws(()=>encodeRequest(value,[]));}
  const assisted=command(base,0,1,axes);assisted.assistance.active=['auto-rudder'];assert.throws(()=>encodeRequest(base,[assisted]));
});
test('incompatible, nonfinite, unauthorized, late, duplicate and unsupported controls fail',()=>{
  const edits=[c=>c.schema_version=2,c=>c.payload.pitch=Infinity,c=>c.authority='instructor',c=>c.source_id='unknown.controls',
    c=>c.tick='0',c=>c.tick='1201',c=>c.payload.mixture=.5,c=>c.payload.left_brake=.5,c=>c.assistance.profile_id='assisted'];
  for(const edit of edits){const value=command(base,0,1,axes);edit(value);assert.throws(()=>encodeRequest(base,[value]));}
  assert.throws(()=>encodeRequest(base,[command(base,0,2,axes),command(base,1,1,axes)]));
  assert.throws(()=>checkInput(base,[],{duration_s:601}));assert.throws(()=>checkInput(base,[],{trim_longitudinal:'yes'}));
  for(const [key,value]of [['id','cessna-172s'],['version','9.9.9'],['sha256','0'.repeat(64)]]){const s=structuredClone(base);s.required_aircraft[key]=value;assert.throws(()=>encodeRequest(s,[]));}
});
test('full output wire validation rejects wrong type/NaN/quaternion rather than trusting native JSON',()=>{
  assert.throws(()=>validateOutput([]));const a=structuredClone(base.initial_conditions.aircraft);a.validity='valid';
  a.systems=[{id:'fuel.total',quantity:'kg',value:100,validity:'valid'},{id:'engine.throttle',quantity:'fraction',value:.65,validity:'valid'}];
  const init={kind:'fdm-initialization',version:1,engine_seed:4194305,accepted_aircraft:a,accepted_atmosphere:base.initial_conditions.atmosphere,
    loaded_library_path:'/synthetic/JSBSim.dll',library_version:'1.3.1',compiler:'MSVC-19.40.33813.0',source_fingerprint:'0'.repeat(64),requested_seed:base.seed,
    trim:{longitudinal:true,gamma_fallback:false,max_cycles:60,max_cycles_per_axis:100,acceleration_tolerance_mps2:.0003048},
    solved_controls:{kind:'axes',...axes},fuel_frozen_during_trim:true,initial_fuel_kg:100,initialization_step_s:1/120};
  validateOutput([init]);
  const ci=structuredClone(init);ci.library_version='1.3.1 [GitHub build 42/commit '+ 'a'.repeat(40)+'] Oct  3 2026 20:31:32';ci.compiler='GNU-13.3.0';validateOutput([ci]);
  for(const version of ['1.3.2','1.3.1 '+ 'x'.repeat(193),'1.3.1 bad\nmetadata']) {const invalid=structuredClone(ci);invalid.library_version=version;assert.throws(()=>validateOutput([invalid]));}
  const bad=structuredClone(init);bad.accepted_aircraft.orientation_body_to_ned.w=5;assert.throws(()=>validateOutput([bad]));
  assert.throws(()=>validateOutput([init,{kind:'unexpected',version:1}]));assert.throws(()=>validateOutput([init,{kind:'fdm-diagnostics',version:1,airspeed_mps:NaN}]));
});
