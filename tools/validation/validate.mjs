import {inputKeys,outputKeys} from './equations.mjs';
export const modelPin='1ccadb2e3d5aefe79f5a8f316631744ab4de18084469d2cf1817fb622cfabf7a';
const id=x=>typeof x==='string'&&/^[A-Za-z0-9][A-Za-z0-9._:-]{0,127}$/.test(x);
const string=x=>typeof x==='string'&&x.length>0&&x.length<=2048&&!/[\x00-\x1f]/.test(x);
export function requireKeys(v,keys){if(!v||Array.isArray(v)||typeof v!=='object'||Object.keys(v).sort().join(',')!==[...keys].sort().join(','))throw Error('Unknown/missing reference fields');}
const requireTrue=(v,s)=>{if(!v)throw Error(s);};
export function validateCorpus(c){
 requireKeys(c,['schema_version','id','classification','model_inventory_sha256','source_revision','frozen_research_sha256','precision','threshold','cases']);
 requireTrue(c.schema_version===1&&c.id==='original-polynomial-v1'&&c.classification==='independent-original-algebra'&&c.model_inventory_sha256===modelPin,'Incompatible corpus');
 requireTrue(c.source_revision==='f09ac4035bbd5c27fe6ba6d995e878dc5ce2dd4d'&&c.frozen_research_sha256==='74f500b759f741ba5a9db47776e7352975ee06de1fe62fa632bd3d4a385cf31d'&&string(c.precision),'Missing/unreviewed frozen provenance');
 requireKeys(c.threshold,['absolute','relative']);requireTrue(c.threshold.absolute===1e-9&&c.threshold.relative===1e-12,'Unreviewed algebra threshold');
 requireTrue(Array.isArray(c.cases)&&c.cases.length===24,'Incomplete frozen corpus');const ids=new Set();
 for(const row of c.cases){requireKeys(row,['id','inputs','expected_decimal']);requireTrue(id(row.id)&&!ids.has(row.id),'Duplicate/invalid case');ids.add(row.id);requireKeys(row.inputs,inputKeys);requireKeys(row.expected_decimal,outputKeys);
  for(const v of [...Object.values(row.inputs),...Object.values(row.expected_decimal)])requireTrue(typeof v==='string'&&v.length<100&&/^-?(?:[0-9]+(?:\.[0-9]*)?|\.[0-9]+)(?:[Ee][+-]?[0-9]+)?$/.test(v)&&Number.isFinite(Number(v)),'Nonfinite/nondecimal reference');
  requireTrue(Number(row.inputs.rho_kg_m3)>=0&&Number(row.inputs.tas_mps)>=0,'Invalid physical scalar');}
 return c;
}
const rowKeys=['id','maneuver','configuration','source_ids','method','status','quantity','unit','airspeed_domain','distance_endpoint','conditions','uncertainty','expected','threshold_status','reason'];
const configKeys=['package','version','serial','poh_revision','engine','propeller','panel'];
const conditionKeys=['mass_kg','cg_datum_m','pressure_altitude_m','temperature_k','wind_toward_ned_mps','runway_surface','runway_slope','power_setting','mixture','flap_fraction','gear_fraction','technique','obstacle_height_m','distance_origin','distance_end'];
const measurementDefinitions={
 'original-force-identities':['numerical','six-axis-force-moment','N-and-Nm','TAS','not-applicable'],
 'c172s-trim-tas':['trim','longitudinal-equilibrium','mps2','TAS','not-applicable'],
 'c172s-cruise-tas':['cruise','cruise-speed','mps','TAS','not-applicable'],
 'c172s-climb-ias':['climb','climb-reference-speed','mps','IAS','not-applicable'],
 'c172s-takeoff-ground-roll':['takeoff','runway-distance','m','IAS','ground-roll'],
 'c172s-takeoff-over-obstacle':['takeoff','runway-distance','m','IAS','over-obstacle'],
 'c172s-landing-ground-roll':['landing','runway-distance','m','IAS','ground-roll'],
 'c172s-landing-over-obstacle':['landing','runway-distance','m','IAS','over-obstacle'],
 'c172s-stall-ias':['stall','stall-speed','mps','IAS','not-applicable'],
 'c172s-stall-cas':['stall','stall-speed','mps','CAS','not-applicable']
};
export function validateMatrix(m){
 requireKeys(m,['schema_version','id','revision','sources','rows']);requireTrue(m.schema_version===1&&m.id==='validation-matrix-v1'&&m.revision==='1.0.0','Incompatible matrix');
 requireTrue(Array.isArray(m.sources)&&m.sources.length>0&&m.sources.length<=32&&Array.isArray(m.rows)&&m.rows.length>0&&m.rows.length<=128,'Reference count');
 const sources=new Set();for(const s of m.sources){requireKeys(s,['id','revision','section','url','rights','use']);requireTrue(id(s.id)&&!sources.has(s.id),'Duplicate source');sources.add(s.id);for(const k of ['revision','section','rights','use'])requireTrue(string(s[k]),'Source metadata missing');requireTrue(typeof s.url==='string'&&/^https:\/\/(?:www\.faa\.gov|github\.com)\//.test(s.url),'Unknown primary source locator');}
 const ids=new Set();for(const r of m.rows){requireKeys(r,rowKeys);requireTrue(id(r.id)&&!ids.has(r.id),'Duplicate row');ids.add(r.id);requireKeys(r.configuration,configKeys);requireKeys(r.conditions,conditionKeys);
  requireTrue(JSON.stringify([r.maneuver,r.quantity,r.unit,r.airspeed_domain,r.distance_endpoint])===JSON.stringify(measurementDefinitions[r.id]),'Incompatible measurement identity');
  requireTrue(['numerical','trim','cruise','climb','takeoff','landing','stall'].includes(r.maneuver)&&['supported','unsupported'].includes(r.status)&&['TAS','IAS','CAS'].includes(r.airspeed_domain),'Unknown status/maneuver/airspeed domain');
  requireTrue(Array.isArray(r.source_ids)&&r.source_ids.length>0&&new Set(r.source_ids).size===r.source_ids.length&&r.source_ids.every(x=>sources.has(x)),'Unresolved source');
  requireTrue(string(r.quantity)&&['N-and-Nm','mps','mps2','m'].includes(r.unit)&&['not-applicable','ground-roll','over-obstacle'].includes(r.distance_endpoint),'Invalid measurement');
  requireTrue((r.quantity==='runway-distance')===(r.unit==='m'&&r.distance_endpoint!=='not-applicable'),'Distance endpoint/unit mixed');
  if(r.status==='unsupported'){requireTrue(r.method==='aircraft-performance'&&r.expected===null&&r.uncertainty===null&&r.threshold_status==='unratified-awaiting-source'&&string(r.reason),'Unsupported cannot carry invented reference/threshold');requireTrue(r.configuration.package==='c172s-analog-v1'&&Object.entries(r.configuration).every(([k,v])=>k==='package'||v===null),'Invented pending configuration');requireTrue(Object.values(r.conditions).every(v=>v===null),'Invented pending conditions');}
  else{requireTrue(r.id==='original-force-identities'&&r.method==='independent-coefficients'&&r.expected==='original-polynomial-v1'&&r.quantity==='six-axis-force-moment'&&r.unit==='N-and-Nm'&&r.airspeed_domain==='TAS'&&r.reason===null&&r.threshold_status==='provisional-numerical-only','Unsupported promoted method');
   const config={package:'original-synthetic',version:'0.1.0-prototype',serial:'original-no-serial',poh_revision:'not-applicable',engine:'original ideal turbine/direct',propeller:'none',panel:'none'};
   requireTrue(configKeys.every(k=>r.configuration[k]===config[k])&&JSON.stringify(r.source_ids)==='["original-equations","jsbsim-units"]','Unreviewed configuration/source roles');
   requireTrue(['pressure_altitude_m','temperature_k','wind_toward_ned_mps','runway_surface','runway_slope','obstacle_height_m','distance_origin','distance_end'].every(k=>r.conditions[k]===null)&&string(r.conditions.power_setting)&&string(r.conditions.mixture)&&string(r.conditions.technique),'Invented numerical conditions');
   requireKeys(r.uncertainty,['kind','absolute','relative','basis']);requireTrue(r.uncertainty.kind==='source-rounding-bound'&&r.uncertainty.absolute===1e-6&&r.uncertainty.relative===1e-7&&string(r.uncertainty.basis),'Unreviewed comparison budget');
   requireTrue(r.conditions.mass_kg===1100&&JSON.stringify(r.conditions.cg_datum_m)==='[0,0,0]'&&r.conditions.flap_fraction===0&&r.conditions.gear_fraction===1,'Wrong original configuration');}
 }
 requireTrue(m.rows.length===10&&m.rows.filter(r=>r.status==='supported').length===1,'Missing supported numerical row');
 for(const r of m.rows){
  if(r.maneuver==='stall')requireTrue(r.id===('c172s-stall-'+r.airspeed_domain.toLowerCase()),'IAS/CAS identity changed');
  if(r.quantity==='runway-distance')requireTrue(r.id===('c172s-'+r.maneuver+'-'+r.distance_endpoint),'Ground/obstacle identity changed');
 }
 const required=['trim','cruise','climb','takeoff','landing'];requireTrue(required.every(k=>m.rows.some(r=>r.maneuver===k)),'Incomplete maneuver coverage');
 for(const kind of ['takeoff','landing'])requireTrue(['ground-roll','over-obstacle'].every(e=>m.rows.some(r=>r.maneuver===kind&&r.distance_endpoint===e)),'Ground/obstacle coverage missing');
 return m;
}
