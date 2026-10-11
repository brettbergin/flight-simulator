// Original MIT. Receipt/source admission only; it does not execute a replay.
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import {createHash} from 'node:crypto';
import {pathToFileURL} from 'node:url';

export const variant='jsbsim-1.3.1-event-aware-coupled-midpoint-local-window-v2';
export const method='event_aware_coupled_midpoint_v1';
export const scope='Actual original298 calls; prospective local-window-v2 completion, full native v1 publications and joined close. No scene, assists, state injection, fitted golden or aircraft validation.';
export const files=Object.freeze({
 'recipe.json':'2ef833b13cab7127b19ae84272f9bfc015133e14c125d781c535b84ad284aba1',
 'argument-binary64.json':'ffb39073782ac1226795df39b0b95512e0f444a4f2284224c9c34af4a5ef9b76',
 'checks.gd':'5689a75e0868067d04b22cd8cfde61f75f0d83d78b5f9a6a1cd37848e34636b8',
 'README.md':'9a333bcce0d17202e9ec2818f7a13227a522764063da7a6a2cd028f38b20a949'});
const world='04bff5a0bcf3509990f6276b2548a28268f57fc96d218a7ca51cab1990ec1ff5';
const axes=['roll','pitch','yaw','throttle','mixture','left_brake','right_brake','trim'];
const rootKeys=['passed','checks','failures','scope','recipe_sha256','argument_binary64_sha256','source_fingerprint','source_variant','angular_integration_method','argument_float_fields','schema_integer_fields','step_integer_fields','final_tick','continuation_completed','joined','calls','publications'];
const replyKeys=['ok','schema_version','aircraft_json','atmosphere_json','held_axes','outcome','completed','live','historical','paused','time_scale','fault','queued','rejection','ground_query_valid','surface_height_m','plane_clearance_m','applied_commands_json','events_json'];
const openKeys=['runtime_modules','named_start','native_source_fingerprint','world_anchor','prepared_world_sha256','wind_profile','angular_integration_method'];
const units={'fuel.total':'kg','engine.throttle':'fraction','engine.mixture':'fraction','propeller.angular_speed':'radps','engine.running':'bool','engine.ignition_left':'bool','engine.ignition_right':'bool','engine.starter':'bool','fuel.feed':'bool','engine.starved':'bool'};
const sha=raw=>createHash('sha256').update(raw).digest('hex');
const plain=value=>value!==null&&typeof value==='object'&&!Array.isArray(value)&&Object.getPrototypeOf(value)===Object.prototype;
function keys(value,wanted,label){assert(plain(value),label+' object');assert.deepEqual(Object.keys(value).sort(),[...wanted].sort(),label+' closed keys');}
function finite(value,label){assert.equal(typeof value,'number',label);assert(Number.isFinite(value),label+' finite');}
function bits(value){finite(value,'binary64');const raw=Buffer.alloc(8);raw.writeDoubleLE(value);return raw.toString('hex');}
function exact(actual,expected,label){
 if(typeof expected==='number'){assert.equal(bits(actual),bits(expected),label+' exact numeric bits');return;}
 if(Array.isArray(expected)){assert(Array.isArray(actual),label+' array');assert.equal(actual.length,expected.length,label+' length');expected.forEach((v,i)=>exact(actual[i],v,label+'/'+i));return;}
 if(plain(expected)){keys(actual,Object.keys(expected),label);for(const key of Object.keys(expected))exact(actual[key],expected[key],label+'/'+key);return;}
 assert.strictEqual(actual,expected,label);
}
function inputFixtures(recipeBytes,argumentBytes){
 assert(Buffer.isBuffer(recipeBytes)&&recipeBytes.length<=262144);assert.equal(sha(recipeBytes),files['recipe.json']);
 assert(Buffer.isBuffer(argumentBytes)&&argumentBytes.length<=32768);assert.equal(sha(argumentBytes),files['argument-binary64.json']);
 const recipe=JSON.parse(recipeBytes),sidecar=JSON.parse(argumentBytes);
 assert.equal(recipe.schema,'PistonMixtureDecayRecipe/v1');assert.equal(recipe.calls.length,298);
 keys(sidecar,['schema','recipe_sha256','argument_binary64_le'],'argument sidecar');
 assert.equal(sidecar.schema,'PistonMixtureDecayArgumentBinary64/v1');assert.equal(sidecar.recipe_sha256,files['recipe.json']);
 let total=0;const expectedKeys=[];
 for(const call of recipe.calls){
  if(!['submit','session_control'].includes(call.method))continue;
  const p=call.arguments[0].payload,wanted=p.kind==='axes'?axes:p.kind==='time_scale'?['scale']:[];
  if(wanted.length){expectedKeys.push(String(call.index));keys(sidecar.argument_binary64_le[String(call.index)],wanted,'sidecar fields');
   for(const key of wanted){const tag=sidecar.argument_binary64_le[String(call.index)][key];assert.match(tag,/^[0-9a-f]{16}$/);assert.equal(tag,bits(p[key]));total++;}}
 }
 keys(sidecar.argument_binary64_le,expectedKeys,'sidecar indices');assert.equal(total,138);
 return recipe;
}

// validateContract MUST be the canonical schemas/validate.mjs export at the
// coordinating call site. No optional/permissive validator is supplied here.
export function validateLocalWindowReplayReceipt(receipt,options){
 keys(options,['recipeBytes','argumentBytes','sourceFingerprint','sourceVariant','modelRoot','validateContract'],'receipt options');
 const {recipeBytes,argumentBytes,sourceFingerprint,sourceVariant,modelRoot,validateContract}=options;
 assert.equal(sourceVariant,variant);assert.match(sourceFingerprint,/^[0-9a-f]{64}$/);assert.notEqual(sourceFingerprint,'5e0abfeae9ffd249f8be3f4410d9903f30736698fcb276bdf72f3630132102e5');
 assert.equal(typeof modelRoot,'string');assert(modelRoot.length>0&&modelRoot.length<=4096&&modelRoot!=='@model_root');
 assert.equal(typeof validateContract,'function');const recipe=inputFixtures(recipeBytes,argumentBytes);
 keys(receipt,rootKeys,'local-window replay');assert.equal(receipt.passed,true);assert(Number.isSafeInteger(receipt.checks)&&receipt.checks>0);assert.deepEqual(receipt.failures,[]);assert.equal(receipt.scope,scope);
 for(const [key,value] of Object.entries({recipe_sha256:files['recipe.json'],argument_binary64_sha256:files['argument-binary64.json'],source_fingerprint:sourceFingerprint,source_variant:variant,angular_integration_method:method,argument_float_fields:138,schema_integer_fields:31,step_integer_fields:265,final_tick:'1607',continuation_completed:28,joined:true}))assert.strictEqual(receipt[key],value,key);
 assert(Array.isArray(receipt.calls)&&receipt.calls.length===298);assert(Array.isArray(receipt.publications)&&receipt.publications.length===3);
 let session='',tick=0,paused=false,scale=1,held={kind:'axes',roll:0,pitch:0,yaw:0,throttle:0,mixture:0,left_brake:1,right_brake:1,trim:0};
 const commands=new Map(),controls=new Map(),delivered=new Set(),events=new Set(),publications=[];
 const systems={'engine.ignition_left':false,'engine.ignition_right':false,'engine.starter':false,'fuel.feed':true};
 function wire(text,type){assert.equal(typeof text,'string');assert(Buffer.byteLength(text)<=1048576);const value=JSON.parse(text);assert.equal(validateContract(value,type).valid,true,type+' canonical schema/semantics');return value;}
 for(let index=0;index<298;index++){
  const row=receipt.calls[index],original=recipe.calls[index];keys(row,['index','method','arguments','reply'],'call record');assert.strictEqual(row.index,index);assert.strictEqual(row.method,original.method);
  const args=structuredClone(original.arguments);if(index===0)args[0]=modelRoot;else if(['submit','session_control'].includes(row.method))args[0].session_id=session;
  exact(row.arguments,args,'original arguments/'+index);
  if(row.method==='submit')commands.set(args[0].sequence,args[0]);
  if(row.method==='session_control'){controls.set(args[0].sequence,args[0]);if(args[0].payload.kind==='pause')paused=args[0].payload.paused;else scale=args[0].payload.scale;}
  const reply=row.reply;
  keys(reply,index===297?['ok','joined']:index===0?[...replyKeys,...openKeys]:replyKeys,'native reply/'+index);
  const expected=structuredClone(original.expected);if(index===296)Object.assign(expected,{outcome:'completed',completed:28,live:true,historical:false,fault:''});
  for(const key of Object.keys(expected))exact(reply[key],expected[key],'compact reply/'+index+'/'+key);
  if(index===297){assert.equal(reply.joined,true);continue;}
  tick+=expected.completed;
  assert.equal(reply.schema_version,1);assert.equal(reply.live,true);assert.equal(reply.historical,false);assert.equal(reply.fault,'');assert.equal(reply.paused,paused);exact(reply.time_scale,scale,'scale');
  assert.equal(typeof reply.ground_query_valid,'boolean');finite(reply.surface_height_m,'surface height');finite(reply.plane_clearance_m,'plane clearance');
  const aircraft=wire(reply.aircraft_json,'AircraftSnapshot'),weather=wire(reply.atmosphere_json,'AtmosphereSample');
  if(index===0){session=aircraft.session_id;assert.notEqual(session,'@session_id');assert.equal(reply.native_source_fingerprint,sourceFingerprint);assert.equal(reply.angular_integration_method,method);assert.equal(reply.prepared_world_sha256,world);assert.equal(reply.named_start,'piston-cold-ground');assert.equal(reply.wind_profile,'calm');
   exact(reply.world_anchor,{latitude_rad:0.8,longitude_rad:-2,ellipsoid_height_m:0},'prepared anchor');assert(plain(reply.runtime_modules)&&Object.keys(reply.runtime_modules).length>0);for(const location of Object.values(reply.runtime_modules))assert(typeof location==='string'&&location.length>0&&location.length<=4096);}
  assert.equal(aircraft.session_id,session);assert.equal(weather.session_id,session);assert.equal(aircraft.tick,String(tick));assert.equal(weather.tick,String(tick));assert.equal(aircraft.validity,'valid');exact(aircraft.clock,{tick_rate_hz:120,purpose:'runtime'},'runtime clock');exact(weather.position,aircraft.position,'native pair position');assert.equal(weather.seed,'42');assert.equal(weather.model_id,'jsbsim-dry-isa');
  assert(Array.isArray(reply.applied_commands_json)&&reply.applied_commands_json.length<=32);assert(Array.isArray(reply.events_json)&&reply.events_json.length<=4096);
  for(const text of reply.applied_commands_json){const command=wire(text,'ControlCommand');assert(commands.has(command.sequence)&&!delivered.has(command.sequence),'actual submitted command exactly once');exact(command,commands.get(command.sequence),'actual applied command');assert(BigInt(command.tick)<=BigInt(tick));delivered.add(command.sequence);if(command.payload.kind==='axes')held=structuredClone(command.payload);else if(command.payload.kind==='system'){assert(Object.hasOwn(systems,command.payload.control_id));systems[command.payload.control_id]=command.payload.value;}}
  for(const text of reply.events_json){const event=wire(text,'OperationalEvent');assert(controls.has(event.sequence)&&!events.has(event.sequence),'actual lifecycle event exactly once');const control=controls.get(event.sequence);const payload=structuredClone(control.payload);if(payload.kind==='time_scale')payload.kind='time-scale';exact(event,{type:'OperationalEvent',schema_version:1,tick:control.tick,session_id:session,sequence:control.sequence,source_id:control.source_id,confidence:'observed',content_version:'0.1.0-prototype',payload},'actual lifecycle event');assert(BigInt(event.tick)<=BigInt(tick));events.add(event.sequence);}
  exact(reply.held_axes,held,'actual held axes/'+index);
  keys(Object.fromEntries(aircraft.systems.map(row=>[row.id,row])),Object.keys(units),'piston channels');assert.equal(aircraft.systems.length,10);
  for(const channel of aircraft.systems){assert.equal(channel.quantity,units[channel.id]);assert.equal(channel.validity,'valid');if(channel.quantity==='bool')assert.equal(typeof channel.value,'boolean');else finite(channel.value,'piston scalar');if(['fuel.total','propeller.angular_speed'].includes(channel.id))assert(channel.value>=0);if(Object.hasOwn(systems,channel.id))exact(channel.value,systems[channel.id],'native held system');if(channel.id==='engine.throttle')exact(channel.value,held.throttle,'native throttle');if(channel.id==='engine.mixture')exact(channel.value,held.mixture,'native mixture');}
  if([0,295,296].includes(index))publications.push({index,tick:String(tick),aircraft_json:reply.aircraft_json,atmosphere_json:reply.atmosphere_json,held_axes:reply.held_axes});
 }
 assert.equal(commands.size,21);assert.equal(delivered.size,21);assert.equal(controls.size,10);assert.equal(events.size,10);assert.equal(tick,1607);
 exact(receipt.publications,publications,'three actual checkpoint records');
 return {checks:receipt.checks,calls:298,final_tick:'1607',continuation_completed:28,joined:true};
}

function ordinary(file){for(let at=path.resolve(file);;at=path.dirname(at)){const stat=fs.lstatSync(at);assert(!stat.isSymbolicLink(),'No linked source ancestor');assert(stat.isFile()||stat.isDirectory(),'Ordinary source only');if(path.dirname(at)===at)break;}}
function roster(root){ordinary(root);const found=[];for(const item of fs.readdirSync(root,{withFileTypes:true})){assert(item.isFile()&&!item.isSymbolicLink(),'Exact flat four-file source roster');found.push(item.name);}return found.sort();}
export function validateLocalWindowReplaySources({repository,project,sourceRoot,nativeIdentity}){
 assert.equal(nativeIdentity.source_variant,variant);assert.match(nativeIdentity.declared_source_fingerprint,/^[0-9a-f]{64}$/);
 const authored=path.join(repository,'tests/engine/local-window-replay'),mapped='local_window_replay_tests';
 const expected=Object.keys(files).sort();assert.deepEqual(roster(authored),expected);
 for(const base of [path.join(sourceRoot,mapped),path.join(sourceRoot,'tests/engine/local-window-replay')])assert.deepEqual(roster(base),expected);
 const staged=roster(path.join(project,mapped));assert.deepEqual(staged.filter(name=>name!=='checks.gd.uid'),expected);
 if(staged.includes('checks.gd.uid')){const raw=fs.readFileSync(path.join(project,mapped,'checks.gd.uid'));assert(raw.length<=64);assert.match(raw.toString('utf8'),/^uid:\/\/[a-z0-9]{1,20}\r?\n?$/);}
 for(const name of expected){const original=fs.readFileSync(path.join(authored,name));assert.equal(sha(original),files[name]);for(const base of [project,sourceRoot]){const file=path.join(base,mapped,name);ordinary(file);assert(fs.readFileSync(file).equals(original));}assert(fs.readFileSync(path.join(sourceRoot,'tests/engine/local-window-replay',name)).equals(original));}
 inputFixtures(fs.readFileSync(path.join(authored,'recipe.json')),fs.readFileSync(path.join(authored,'argument-binary64.json')));
 for(const base of [project,sourceRoot]){const file=path.join(base,'build/native_identity.gd');ordinary(file);const raw=fs.readFileSync(file);assert.equal(raw.length,nativeIdentity.resource.bytes);assert.equal(sha(raw),nativeIdentity.resource.sha256);
  const match=/^extends RefCounted\nconst SCHEMA: String = "flight-native-build-identity-v1"\nconst SOURCE_VARIANT: String = "([a-z0-9.-]+)"\nconst BACKEND_IDENTITY_SHA256: String = "([0-9a-f]{64})"\nconst BUILD_CONTROL_SHA256: String = "([0-9a-f]{64})"\nconst SOURCE_FINGERPRINT: String = "([0-9a-f]{64})"\n$/.exec(raw.toString('utf8'));assert(match,'Exact generated identity resource');assert.equal(match[1],variant);assert.equal(match[4],nativeIdentity.declared_source_fingerprint);}
 return expected.map(name=>({path:'tests/engine/local-window-replay/'+name,sha256:files[name]}));
}

if(process.argv[1]&&import.meta.url===pathToFileURL(process.argv[1]).href){
 const [mode,receiptPath,repository,sourceFingerprint,sourceVariant,modelRoot,...extra]=process.argv.slice(2);
 assert.equal(mode,'receipt');assert.equal(extra.length,0);assert(modelRoot!==undefined);
 ordinary(receiptPath);const raw=fs.readFileSync(receiptPath);assert(raw.length>0&&raw.length<=16777216,'Bounded full replay receipt');
 const schemaFile=path.join(repository,'schemas/validate.mjs');ordinary(schemaFile);
 const {validateContract}=await import(pathToFileURL(schemaFile));
 const inputRoot=path.join(repository,'tests/engine/local-window-replay');
 const result=validateLocalWindowReplayReceipt(JSON.parse(raw),{recipeBytes:fs.readFileSync(path.join(inputRoot,'recipe.json')),argumentBytes:fs.readFileSync(path.join(inputRoot,'argument-binary64.json')),sourceFingerprint,sourceVariant,modelRoot,validateContract});
 console.log(JSON.stringify({scope:'Validated receipt bytes; actual execution/source qualification requires coordinating evidence',...result}));
}
