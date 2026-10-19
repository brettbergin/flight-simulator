// Original MIT. Offline first-party catalog reproduction; never runtime authority.
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import assert from 'node:assert/strict';
import {fileURLToPath} from 'node:url';
import {createRequire} from 'node:module';
import {validateSourcePair} from '../ingest/airports/source-contract.mjs';

const ROOT=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'../..');
const require=createRequire(path.join(ROOT,'schemas/package.json'));
const Ajv=require('ajv/dist/2020.js').default;
const addFormats=require('ajv-formats').default;
const SHA=/^[0-9a-f]{64}$/;
const ROLES=['resident-ground-grid-v1','airport-source-record','airport-source-dossier','terrain-compile-receipt-v1','world-start-recipe-v1','source-notice'];
const NAMES=['ground.fgrd','airport.json','dossier.json','compile-receipt.json','start-ready34.json','NOTICE.txt'];
const MODEL={id:'original-interactive-prototype',version:'0.1.0-prototype',backend_model:'original-interactive'};
const ANCHOR={latitude_rad:{$binary64_le:'fdfc84c1e5e5ea3f'},longitude_rad:{$binary64_le:'5eedd3837e0e01c0'},ellipsoid_height_m:{$binary64_le:'0000000000000000'}};
const KNOWN=[
  [25973686,'b2c53308fdc427900d84b541aff51ba66cbb71bc483fcee0ea16d067dbd15cfb'],
  [37101,'63463d30c55f8aba56a3426efd7c2dd61287a99d66d307f3940b589b97fd6c18'],
  [15785,'974345fd8eedff2e339e4eb21b8ac3a09ed69c66c4d2a045b430f9655bd15cee'],
  [22937,'cb1e0b28384aeb1c11173d991b5790a8a16e64953c2c479be6b07136c5f489f0'],
];
export const sha=bytes=>crypto.createHash('sha256').update(bytes).digest('hex');
const plain=value=>JSON.parse(JSON.stringify(value));
const equal=(a,b,message)=>assert.deepEqual(plain(a),plain(b),message);
const keys=(value,names)=>{
  assert(value!==null && typeof value==='object' && !Array.isArray(value));
  equal(Object.keys(value).sort(),[...names].sort(),'Closed object keys required');
};

export function strictJson(bytes,maxBytes,maxDepth,maxValues) {
  assert(bytes instanceof Uint8Array && bytes.length>0 && bytes.length<=maxBytes,'JSON byte bound');
  assert(!(bytes[0]===239&&bytes[1]===187&&bytes[2]===191),'BOM refused');
  const text=new TextDecoder('utf-8',{fatal:true}).decode(bytes);
  let at=0,values=0;
  const ws=()=>{while(at<text.length&&/[\x20\x09\x0a\x0d]/.test(text[at]))at++;};
  const strings=/"(?:[^"\\\u0000-\u001f]|\\(?:["\\/bfnrt]|u[0-9a-fA-F]{4}))*"/y;
  const numbers=/-?(?:0|[1-9][0-9]*)(?:\.[0-9]+)?(?:[eE][+-]?[0-9]+)?/y;
  function string(){
    strings.lastIndex=at; const found=strings.exec(text); assert(found,'JSON string'); at=strings.lastIndex;
    const result=JSON.parse(found[0]);
    for(let i=0;i<result.length;i++){
      const c=result.charCodeAt(i);
      if(c>=0xd800&&c<=0xdbff){const d=result.charCodeAt(++i);assert(d>=0xdc00&&d<=0xdfff,'Surrogate pair');}
      else assert(!(c>=0xdc00&&c<=0xdfff),'Lone surrogate');
    }
    return result;
  }
  function value(depth){
    assert(depth<=maxDepth&&++values<=maxValues,'JSON structure bound'); ws();
    if(text[at]==='"')return string();
    if(text[at]==='{'){
      at++;ws();const object=Object.create(null),seen=new Set();if(text[at]==='}'){at++;return object;}
      while(true){const key=string();assert(!seen.has(key),'Duplicate key');seen.add(key);ws();assert(text[at++]===':','Colon');object[key]=value(depth+1);ws();const d=text[at++];if(d==='}')return object;assert(d===',','Object delimiter');ws();}
    }
    if(text[at]==='['){
      at++;ws();const array=[];if(text[at]===']'){at++;return array;}
      while(true){array.push(value(depth+1));ws();const d=text[at++];if(d===']')return array;assert(d===',','Array delimiter');}
    }
    for(const [token,result] of [['true',true],['false',false],['null',null]])if(text.startsWith(token,at)){at+=token.length;return result;}
    numbers.lastIndex=at;const found=numbers.exec(text);assert(found,'JSON value');at=numbers.lastIndex;const result=Number(found[0]);assert(Number.isFinite(result),'Nonfinite JSON number');return result;
  }
  const result=value(0);ws();assert.equal(at,text.length,'Trailing JSON bytes');return result;
}
function readJson(file,bytes=4*1024*1024,depth=16,values=20000){return strictJson(readBounded(file,bytes),bytes,depth,values);}
function ordinary(file,directory=false){
  const resolved=path.resolve(file);let current=path.parse(resolved).root;
  for(const part of resolved.slice(current.length).split(path.sep).filter(Boolean)){current=path.join(current,part);assert(!fs.lstatSync(current).isSymbolicLink(),'Alias refused');}
  const stat=fs.statSync(resolved);assert(directory?stat.isDirectory():stat.isFile(),'Ordinary path required');
  assert.equal(fs.realpathSync.native(resolved).toLowerCase(),resolved.toLowerCase(),'Physical path mismatch');return stat;
}
function readBounded(file,maximum){
  ordinary(file);const fd=fs.openSync(file,'r');
  try{
    const stat=fs.fstatSync(fd);assert(stat.isFile()&&Number.isSafeInteger(stat.size)&&stat.size>0&&stat.size<=maximum,'Bounded ordinary read');
    const bytes=Buffer.alloc(stat.size);let at=0;
    while(at<bytes.length){const count=fs.readSync(fd,bytes,at,bytes.length-at,at);assert(count>0,'Short read');at+=count;}
    assert.equal(fs.readSync(fd,Buffer.alloc(1),0,1,bytes.length),0,'Growing input refused');assert.equal(fs.fstatSync(fd).size,stat.size,'Read size changed');return bytes;
  }finally{fs.closeSync(fd);}
}
const ajv=new Ajv({strict:true,strictNumbers:true,allErrors:true,coerceTypes:false,useDefaults:false,removeAdditional:false});addFormats(ajv);
for(const relative of ['schemas/v1/definitions.schema.json','schemas/world/kawo-terrain/v1/airport-geometry.schema.json',
  'schemas/world/kawo-terrain/v1/compile-receipt.schema.json','schemas/world/resident-runtime/v1/start-recipe.schema.json',
  'schemas/world/resident-runtime/v1/world-runtime-entry.schema.json'])ajv.addSchema(plain(readJson(path.join(ROOT,relative),4*1024*1024,32,200000)));
const worldSchema=ajv.compile(plain(readJson(path.join(ROOT,'schemas/v1/WorldPackage.schema.json'))));
// AJV's object-const comparator requires ordinary JSON object prototypes. The
// bounded duplicate-aware lexical parser remains the admission gate; adapt only
// its owned validation copy, preserving original bytes/tags/parsed values.
function schema(id,value){const check=ajv.getSchema(id);assert(check&&check(plain(value)),'Closed schema admission failed');}
function word(tag){keys(tag,['$binary64_le']);assert(typeof tag.$binary64_le==='string'&&/^[0-9a-f]{16}$/.test(tag.$binary64_le));const raw=Buffer.from(tag.$binary64_le,'hex');assert(Number.isFinite(raw.readDoubleLE()),'Nonfinite binary64 tag');return raw;}
function finiteTags(value){if(value&&typeof value==='object'){if(Object.hasOwn(value,'$binary64_le'))word(value);else for(const child of Object.values(value))finiteTags(child);}}

// Join fixed accepted payload metadata. This is not a replacement for either
// native or Godot's independent complete Definition semantic admission.
function payloadMetadata(bytes){
  assert.equal(bytes.subarray(0,8).toString('hex'),'464752444c453100');assert.equal(bytes.readUInt32LE(8),1);assert.equal(bytes.readUInt32LE(12),0x01020304);
  assert.equal(bytes.readBigUInt64LE(16),BigInt(bytes.length));
  const columns=bytes.readUInt32LE(24),rows=bytes.readUInt32LE(28),n=bytes.readUInt32LE(32),w=bytes.readUInt32LE(36);
  equal([columns,rows,n,w],[3073,2049,6296577,98385]);assert.equal(bytes[56],4);assert.equal(bytes.readUInt16LE(58),0);assert.equal(bytes.readUInt32LE(60),0);
  equal([bytes.readDoubleLE(88),bytes.readDoubleLE(96)],[-6144,-4096]);
  const anchor={latitude_rad:{$binary64_le:bytes.subarray(64,72).toString('hex')},longitude_rad:{$binary64_le:bytes.subarray(72,80).toString('hex')},ellipsoid_height_m:{$binary64_le:bytes.subarray(80,88).toString('hex')}};
  equal(anchor,ANCHOR);
  const materials=bytes.readUInt32LE(40),polygons=bytes.readUInt32LE(44),vertexTotal=bytes.readUInt32LE(48);
  assert(materials>=1&&materials<=32&&polygons===2&&vertexTotal===8);
  let at=104+4*n+8*w;
  const take=count=>{assert(Number.isSafeInteger(count)&&count>=0&&count<=bytes.length-at,'Payload cursor');const result=bytes.subarray(at,at+count);at+=count;return result;};
  const id=()=>{const count=take(1)[0];assert(count>=1&&count<=128);const b=take(count);assert(b.every(x=>x>=32&&x<127));const result=b.toString('ascii');assert(/^[a-z][a-z0-9]*(?:[._-][a-z0-9]+)*$/.test(result));return result;};
  const mats=[];for(let i=0;i<materials;i++){const name=id(),coeff=take(16);mats.push({id:name,static_friction:coeff.readDoubleLE(0),dynamic_friction:coeff.readDoubleLE(8)});}
  const rings=[];for(let i=0;i<polygons;i++){const name=id(),head=take(9),count=head.readUInt32LE(5);assert.equal(count,4);const vertices=[];for(let j=0;j<count;j++){const v=take(8);vertices.push([v.readInt32LE(0),v.readInt32LE(4)]);}rings.push({id:name,material_index:head.readUInt32LE(0),priority:head[4],vertices_mm:vertices});}
  assert.equal(at,bytes.length);assert.equal(mats[1].id,'original.asphalt');return {anchor,rings};
}

export function loadBundle(root=ROOT){
  const pack=path.join(root,'content/world/airports/kawo/runtime-v1');ordinary(pack,true);
  const catalogFile=path.join(root,'content/world/catalog/kawo-runtime-v1.json');assert(ordinary(catalogFile).size<=65536);
  const catalogBytes=readBounded(catalogFile,65536),entry=strictJson(catalogBytes,65536,8,2048);
  schema('https://flight-simulator.invalid/contracts/world/resident-runtime/v1/world-runtime-entry.schema.json',entry);finiteTags(entry);
  equal(fs.readdirSync(pack).sort(),['world.json',...NAMES].sort(),'Exact seven-file pack required');
  const manifestFile=path.join(pack,'world.json');assert(ordinary(manifestFile).size<=4*1024*1024);
  const manifestBytes=readBounded(manifestFile,4*1024*1024),world=strictJson(manifestBytes,4*1024*1024,16,20000);
  assert(worldSchema(plain(world)),'WorldPackage/v1 shape');equal([world.id,world.version,world.evidence.status,world.products],['kawo.prototype','0.1.0-prototype','prototype',['terrain','airport']]);
  equal(entry.world,{id:world.id,version:world.version,sha256:sha(manifestBytes),bytes:manifestBytes.length});equal(entry.files,world.files);
  equal(entry.world_anchor,ANCHOR);equal(entry.model_identity,MODEL);
  assert.equal(entry.model_inventory_sha256,'98b30b5641ce86cc6f0af6298424606aa96a1e4a35ef3e9fcaf377bebb3f00cd');
  const buffers={};let total=manifestBytes.length;
  for(let i=0;i<NAMES.length;i++){
    const file=entry.files[i];equal([file.path,file.role],[NAMES[i],ROLES[i]]);assert(SHA.test(file.sha256));
    const maximum=i===0?276946836:i===4?16384:i===5?65536:4*1024*1024;
    assert(Number.isSafeInteger(file.bytes)&&file.bytes>0&&file.bytes<=maximum);const filePath=path.join(pack,NAMES[i]);assert.equal(ordinary(filePath).size,file.bytes);
    const bytes=readBounded(filePath,maximum);assert.equal(bytes.length,file.bytes);assert.equal(sha(bytes),file.sha256);total+=bytes.length;assert(total<=288*1024*1024);buffers[NAMES[i]]=bytes;
    if(i<KNOWN.length)equal([bytes.length,sha(bytes)],KNOWN[i],'Approved compiler/source input required');
  }
  const receipt=strictJson(buffers['compile-receipt.json'],4*1024*1024,16,20000),start=strictJson(buffers['start-ready34.json'],16384,8,512);
  schema('https://flight-simulator.invalid/contracts/world/kawo-terrain/v1/compile-receipt.schema.json',receipt);
  schema('https://flight-simulator.invalid/contracts/world/resident-runtime/v1/start-recipe.schema.json',start);finiteTags(receipt);finiteTags(start);
  strictJson(buffers['airport.json'],4*1024*1024,16,20000);strictJson(buffers['dossier.json'],4*1024*1024,16,20000);
  const pair=validateSourcePair(buffers['dossier.json'],buffers['airport.json']);assert(pair.ok,'Approved source-pair conformance');
  equal(start.model_identity,entry.model_identity);equal(start.clock,entry.clock);equal([start.selector,start.named_start,start.wind_profile,start.seed],[entry.selector,entry.named_start,entry.wind_profile,entry.seed]);
  const angles=start.orientation_rpy_ned_rad;assert(Math.abs(word(angles.roll).readDoubleLE())<=.2&&Math.abs(word(angles.pitch).readDoubleLE())<=.2);const yaw=word(angles.yaw).readDoubleLE();assert(yaw>=0&&yaw<2*Math.PI);
  assert(Math.abs(word(start.position.latitude_rad).readDoubleLE())<=Math.PI/2&&Math.abs(word(start.position.longitude_rad).readDoubleLE())<=Math.PI,'Canonical geodetic angles');
  const ground=payloadMetadata(buffers['ground.fgrd']),geometry=receipt.airport_geometry;
  equal(receipt.frame.world_anchor,entry.world_anchor);equal(geometry.world_anchor,entry.world_anchor);
  assert.equal(geometry.source_airport_sha256,entry.files[1].sha256);assert.equal(geometry.ground_payload_sha256,entry.files[0].sha256);equal(receipt.outputs,[{bytes:entry.files[0].bytes,path:'ground.fgrd',sha256:entry.files[0].sha256}]);
  equal(geometry.runways.map(x=>x.id),['kawo.runway.11-29','kawo.runway.16-34']);equal(geometry.runways.flatMap(x=>x.ends.map(e=>e.designator)),['11','29','16','34']);
  for(let i=0;i<2;i++){const r=geometry.runways[i];equal([ground.rings[i].id,ground.rings[i].material_index,ground.rings[i].priority,ground.rings[i].vertices_mm],[r.material_polygon_id,1,100,r.footprint_mm]);}
  equal(receipt.inputs.slice(0,2).map(x=>[x.bytes,x.sha256]),entry.files.slice(1,3).map(x=>[x.bytes,x.sha256]));
  equal(world.evidence.source_ids,pair.dossier.sources.map(x=>x.id));equal(world.sources.map(x=>[x.id,x.sha256,x.rights,x.effective_from,x.effective_until]),pair.dossier.sources.map(x=>[x.id,x.artifact.sha256,x.rights.status,x.effective_from,x.effective_until]));
  const notice=new TextDecoder('utf-8',{fatal:true}).decode(buffers['NOTICE.txt']);for(const term of ['FAA','USGS','NOAA','PROJ-data','UNKNOWN','not a validated Cessna'])assert(notice.includes(term),'Source/prototype notice required');
  return {entry,start,geometry,catalogSha:sha(catalogBytes),world,buffers,total};
}

const cppString=value=>JSON.stringify(value);
const cppWord=value=>'0x'+word(value).readBigUInt64LE().toString(16).padStart(16,'0')+'ULL';
const geo=value=>`GeoWords{${['latitude_rad','longitude_rad','ellipsoid_height_m'].map(x=>cppWord(value[x])).join(',')}}`;
const model=value=>`Model{${[value.id,value.version,value.backend_model].map(cppString).join(',')}}`;
const clock=value=>`Clock{${cppString(value.purpose)},${value.tick_rate_hz}}`;
export function nativeHeader(bundle){
  const {entry:e,start:s,geometry:g,catalogSha}=bundle;
  const file=f=>`File{${cppString(f.path)},${cppString(f.sha256)},${f.bytes}ULL,${cppString(f.role)}}`;
  const end=e=>`End{${cppString(e.designator)},std::array<std::uint64_t,3>{${e.eus_m.map(cppWord).join(',')}},${cppWord(e.published_true_bearing_deg)}}`;
  const runway=r=>`Runway{${cppString(r.id)},${cppString(r.material_polygon_id)},${cppWord(r.published_length_m)},${cppWord(r.width_m)},std::array<std::array<std::int32_t,2>,4>{{${r.footprint_mm.map(p=>`std::array<std::int32_t,2>{${p.join(',')}}`).join(',')}}},std::array<End,2>{{${r.ends.map(end).join(',')}}}}`;
  return `#pragma once
// Generated by tools/interactive-preview/world-catalog.mjs; do not edit.
#include <array>
#include <cstddef>
#include <cstdint>
#include <string_view>
namespace flight::interactive::generated_world {
struct GeoWords { std::uint64_t latitude_rad,longitude_rad,ellipsoid_height_m; };
struct RpyWords { std::uint64_t roll,pitch,yaw; };
struct World { std::string_view id,version,sha256; std::uint64_t bytes; };
struct File { std::string_view path,sha256; std::uint64_t bytes; std::string_view role; };
struct Model { std::string_view id,version,backend_model; };
struct Clock { std::string_view purpose; std::uint32_t tick_rate_hz; };
struct Entry { std::string_view schema,selector; World world; std::array<File,6> files; GeoWords world_anchor; Model model_identity; std::string_view model_inventory_sha256,named_start,wind_profile,seed; Clock clock; std::nullptr_t angular_integration_method; std::uint32_t recording_version; };
struct StartRecipe { std::string_view schema,id,selector; Model model_identity; std::string_view named_start,wind_profile,seed; Clock clock; GeoWords position; RpyWords orientation_rpy_ned_rad; };
struct End { std::string_view designator; std::array<std::uint64_t,3> eus_m; std::uint64_t published_true_bearing_deg; };
struct Runway { std::string_view id,material_polygon_id; std::uint64_t published_length_m,width_m; std::array<std::array<std::int32_t,2>,4> footprint_mm; std::array<End,2> ends; };
struct AirportGeometry { std::string_view schema,position_frame,bearing_reference; GeoWords world_anchor; std::string_view source_airport_sha256,ground_payload_sha256; std::array<Runway,2> runways; };
inline constexpr std::string_view catalog_source_sha256=${cppString(catalogSha)};
inline constexpr Entry kawo_entry{${cppString(e.schema)},${cppString(e.selector)},World{${[e.world.id,e.world.version,e.world.sha256].map(cppString).join(',')},${e.world.bytes}ULL},std::array<File,6>{{${e.files.map(file).join(',')}}},${geo(e.world_anchor)},${model(e.model_identity)},${[e.model_inventory_sha256,e.named_start,e.wind_profile,e.seed].map(cppString).join(',')},${clock(e.clock)},nullptr,${e.recording_version}};
inline constexpr StartRecipe kawo_start{${[s.schema,s.id,s.selector].map(cppString).join(',')},${model(s.model_identity)},${[s.named_start,s.wind_profile,s.seed].map(cppString).join(',')},${clock(s.clock)},${geo(s.position)},RpyWords{${['roll','pitch','yaw'].map(k=>cppWord(s.orientation_rpy_ned_rad[k])).join(',')}}};
inline constexpr AirportGeometry kawo_geometry{${[g.schema,g.position_frame,g.bearing_reference].map(cppString).join(',')},${geo(g.world_anchor)},${[g.source_airport_sha256,g.ground_payload_sha256].map(cppString).join(',')},std::array<Runway,2>{{${g.runways.map(runway).join(',')}}}};
} // namespace flight::interactive::generated_world
`;
}

export function godotRegistry({entry,catalogSha}){
  return `extends RefCounted
# Generated by tools/interactive-preview/world-catalog.mjs; no runtime native authority.
const CATALOG_SOURCE_SHA256: String = ${JSON.stringify(catalogSha)}
const _KAWO: Dictionary = ${JSON.stringify(entry)}
const _MODEL: Dictionary = {"id":"original-interactive-prototype","version":"0.1.0-prototype","backend_model":"original-interactive"}
const _PISTON: Dictionary = {"id":"original-piston-prop-v1","version":"0.1.0-prototype","backend_model":"original-piston-prop"}
const _WORLD: String = "04bff5a0bcf3509990f6276b2548a28268f57fc96d218a7ca51cab1990ec1ff5"
const _INVENTORY: String = "98b30b5641ce86cc6f0af6298424606aa96a1e4a35ef3e9fcaf377bebb3f00cd"
const _PISTON_INVENTORY: String = "f7766fda173d8ee83d4c4a8c02f6333124175a1f7064d3f4d8e78df3d17da12a"

static func _keys(value: Variant, expected: Array) -> bool:
	if not value is Dictionary or value.size()!=expected.size(): return false
	for key in value:
		if typeof(key)!=TYPE_STRING or not key in expected: return false
	return true

static func _same_model(value: Variant, expected: Dictionary) -> bool:
	if not _keys(value,["id","version","backend_model"]): return false
	for key in expected:
		if typeof(value[key])!=TYPE_STRING or value[key]!=expected[key]: return false
	return true

static func _same_anchor(value: Variant, expected: Dictionary) -> bool:
	if not _keys(value,["latitude_rad","longitude_rad","ellipsoid_height_m"]): return false
	for key in expected:
		if typeof(value[key])!=TYPE_FLOAT or not is_finite(value[key]): return false
		var bytes:=PackedByteArray()
		bytes.resize(8)
		bytes.encode_double(0,value[key])
		if bytes.hex_encode()!=expected[key]["$binary64_le"]: return false
	return true

static func _kawo_entry() -> Dictionary:
	var result: Dictionary=_KAWO.duplicate(true)
	for key in result.world_anchor:
		result.world_anchor[key]=String(result.world_anchor[key]["$binary64_le"]).hex_decode().decode_double(0)
	return result

static func _recipe(profile: String, start: String) -> bool:
	return start in (["ground-ready","airborne-prepared","apron-ready"] if profile==_MODEL.id else ["piston-cold-ground","piston-cold-apron"])

static func selection(world_selector: Variant, profile_id: Variant, named_start: Variant, wind_profile: Variant) -> Dictionary:
	var failure: Dictionary={"ok":false,"error":"Unsupported world/model/start/wind selection","entry":null}
	for value in [world_selector,profile_id,named_start,wind_profile]:
		if typeof(value)!=TYPE_STRING: return failure
	if world_selector=="kawo-prototype-v1":
		if profile_id!=_MODEL.id or named_start!="ground-ready" or wind_profile!="calm": return failure
		return {"ok":true,"error":"","entry":_kawo_entry()}
	if world_selector!="original-synthetic" or not profile_id in [_MODEL.id,_PISTON.id] or not wind_profile in ["calm","from-north","from-west","from-east"] or not _recipe(profile_id,named_start): return failure
	if (profile_id==_PISTON.id or named_start in ["apron-ready","piston-cold-apron"]) and wind_profile!="calm": return failure
	var piston: bool=profile_id==_PISTON.id
	var result: Dictionary={"schema":"WorldRuntimeEntry/v1","selector":"original-synthetic","world":{"id":"original.interactive-plane","version":"1.0.0","sha256":_WORLD,"bytes":null},"files":[],"world_anchor":{"latitude_rad":0.8,"longitude_rad":-2.0,"ellipsoid_height_m":0.0},"model_identity":(_PISTON if piston else _MODEL).duplicate(true),"model_inventory_sha256":_PISTON_INVENTORY if piston else _INVENTORY,"named_start":named_start,"wind_profile":wind_profile,"seed":"42","clock":{"purpose":"runtime","tick_rate_hz":120},"angular_integration_method":"event_aware_coupled_midpoint_v1" if piston else null,"recording_version":2 if piston else 1}
	return {"ok":true,"error":"","entry":result}

static func source(model_identity: Variant, named_start: Variant, prepared_world_sha256: Variant, world_anchor: Variant) -> Dictionary:
	var failure: Dictionary={"ok":false,"error":"Unsupported world source relation","selector":null,"recording_version":null}
	if typeof(named_start)!=TYPE_STRING or typeof(prepared_world_sha256)!=TYPE_STRING: return failure
	if prepared_world_sha256==_KAWO.files[0].sha256 and _same_model(model_identity,_MODEL) and named_start=="ground-ready" and _same_anchor(world_anchor,_KAWO.world_anchor):
		return {"ok":true,"error":"","selector":"kawo-prototype-v1","recording_version":3}
	var original_anchor: Dictionary={"latitude_rad":{"$binary64_le":"9a9999999999e93f"},"longitude_rad":{"$binary64_le":"00000000000000c0"},"ellipsoid_height_m":{"$binary64_le":"0000000000000000"}}
	if prepared_world_sha256!=_WORLD or not _keys(world_anchor,["latitude_rad","longitude_rad","ellipsoid_height_m"]): return failure
\t# Preserve the old historical1/2 FLOAT numerical anchor relation, including -0.
\tfor key in original_anchor:
\t\tif typeof(world_anchor[key])!=TYPE_FLOAT or not is_finite(world_anchor[key]) or world_anchor[key]!=(0.8 if key=="latitude_rad" else (-2.0 if key=="longitude_rad" else 0.0)): return failure
	var piston: bool=_same_model(model_identity,_PISTON)
	if not piston and not _same_model(model_identity,_MODEL): return failure
	if not _recipe(_PISTON.id if piston else _MODEL.id,named_start): return failure
	return {"ok":true,"error":"","selector":"original-synthetic","recording_version":2 if piston else 1}
`;
}

export function reproduce(root=ROOT,write=false){
  const bundle=loadBundle(root);
  const outputs=[['native/fdm_jsbsim/interactive/src/prepared_world_catalog.hpp',nativeHeader(bundle)],['app/world/world_admission.gd',godotRegistry(bundle)]];
  for(const [relative,text] of outputs){const file=path.join(root,relative);if(write){fs.mkdirSync(path.dirname(file),{recursive:true});fs.writeFileSync(file,text);}else{assert(readBounded(file,4*1024*1024).equals(Buffer.from(text)),'Generated catalog bytes differ');}}
  return {catalog_sha256:bundle.catalogSha,world_sha256:bundle.entry.world.sha256,pack_bytes:bundle.total,outputs:outputs.map(([file,text])=>({path:file,bytes:Buffer.byteLength(text),sha256:sha(text)}))};
}
if(process.argv[1]&&path.resolve(process.argv[1])===fileURLToPath(import.meta.url)){
  assert(process.argv.length===3&&['--check','--write'].includes(process.argv[2]),'Use --check or --write');
  console.log(JSON.stringify(reproduce(ROOT,process.argv[2]==='--write'),null,2));
}
