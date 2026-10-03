import test from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {evaluate,bodyForce} from '../../tools/validation/equations.mjs';
import {validateCorpus,validateMatrix} from '../../tools/validation/validate.mjs';
import {compareCorpus,compareDiagnostic,runValidation} from '../../tools/validation/runner.mjs';
const corpus=JSON.parse(await readFile(new URL('./original-polynomial-v1.json',import.meta.url)));
const matrix=JSON.parse(await readFile(new URL('./matrix-v1.json',import.meta.url)));
const clone=x=>structuredClone(x);
const x=Object.fromEntries(Object.entries(corpus.cases[0].inputs).map(([k,v])=>[k,Number(v)]));
test('frozen independent decimal identities cover all 24 perturbations',()=>{
 assert.equal(compareCorpus(corpus).filter(r=>r.status==='passed').length,24);
 const e=evaluate(x);assert.ok(Math.abs(e.lift_wind_n-5726.875)<1e-9);assert.ok(Math.abs(e.pitch_body_nm-885.0625)<1e-9);
});
test('changed reference fails without fitting coefficients',()=>{
 const c=clone(corpus);c.cases[0].expected_decimal.lift_wind_n='5000';
 assert.equal(compareCorpus(c)[0].status,'failed');
 assert.ok(Math.abs(evaluate(x).lift_wind_n-5726.875)<1e-9);
});
test('strict corpus rejects shape, provenance, duplicates and nonfinite references',()=>{
 const mutations=[
 c=>c.schema_version=2,c=>c.extra=true,c=>c.model_inventory_sha256='0'.repeat(64),
 c=>c.cases.pop(),c=>c.cases[1].id=c.cases[0].id,
 c=>c.cases[0].inputs.rho_kg_m3='NaN',c=>c.cases[0].inputs.rho_kg_m3='1e999',
 c=>c.cases[0].inputs.extra='1',c=>c.threshold.absolute=1,c=>c.source_revision='0'.repeat(40),c=>c.frozen_research_sha256='0'.repeat(64),
 ];
 for(const mutate of mutations){const c=clone(corpus);mutate(c);assert.throws(()=>validateCorpus(c));}
});
test('matrix rejects relabeling, invented pending data and mixed speed/distance definitions',()=>{
 const mutations=[
 m=>m.schema_version=2,m=>m.extra=true,m=>m.rows[0].source_ids=['missing'],
 m=>m.sources[1].id=m.sources[0].id,m=>m.rows[0].uncertainty.relative=1,
 m=>m.rows[0].configuration.package='c172s-analog-v1',
 m=>m.rows[1].status='supported',m=>m.rows[1].expected=100,
 m=>m.rows[1].configuration.serial='invented',m=>m.rows[1].conditions.mass_kg=1100,
 m=>m.rows.find(r=>r.id==='c172s-takeoff-ground-roll').distance_endpoint='over-obstacle',
 m=>m.rows.find(r=>r.id==='c172s-stall-cas').airspeed_domain='IAS',
 m=>m.rows=m.rows.filter(r=>r.maneuver!=='landing'),
 m=>m.rows=m.rows.filter(r=>r.status!=='supported'),
 m=>m.rows[0].conditions.extra=null,m=>m.rows[0].source_ids=['faa-instruments'],m=>m.rows[0].configuration.engine='real-piston',m=>m.rows[0].conditions.wind_toward_ned_mps={x:1,y:2,z:3},m=>m.rows.find(r=>r.id==='c172s-cruise-tas').airspeed_domain='IAS',
 ];
 for(const mutate of mutations){const m=clone(matrix);mutate(m);assert.throws(()=>validateMatrix(m));}
});
function diagnostic(){
 const e=evaluate(x);
 return {tick:'0',airspeed_mps:x.tas_mps,alpha_rad:x.alpha_rad,beta_rad:x.beta_rad,
 air_relative_rate_radps:{x:x.p_aero_rad_s,y:x.q_aero_rad_s,z:x.r_aero_rad_s},
 jsbsim_controls:{aileron:x.jsb_aileron,elevator:x.jsb_elevator,pitch_trim:x.jsb_trim,rudder:x.jsb_rudder},
 drag_side_lift_n:[e.drag_wind_n,e.side_wind_n,e.lift_wind_n],aerodynamic_force_body_n:bodyForce(x,e),
 aerodynamic_moment_cg_body_nm:[e.roll_body_nm,e.pitch_body_nm,e.yaw_body_nm],dynamic_pressure_pa:e.qbar_pa};
}
test('equation comparator detects signs, magnitudes and independent dynamic pressure errors',()=>{
 const w={density_kgpm3:x.rho_kg_m3},budget=matrix.rows[0].uncertainty;
 assert.equal(compareDiagnostic(diagnostic(),w,budget).status,'passed');
 for(const mutate of [d=>d.drag_side_lift_n[2]*=-1,d=>d.aerodynamic_moment_cg_body_nm[1]+=100,d=>d.aerodynamic_force_body_n.x*=-1,d=>d.dynamic_pressure_pa*=2,d=>d.drag_side_lift_n[0]=NaN]){
  const d=diagnostic();mutate(d);assert.equal(compareDiagnostic(d,w,budget).status,'failed');
 }
});
test('missing backend and C172S sources remain explicitly unsupported',async()=>{
 const report=await runValidation();
 assert.deepEqual(report.counts,{passed:24,failed:0,unsupported:10});
 assert.equal(report.aircraft_qualified,false);assert.equal(report.automatically_fitted,false);
 assert.equal(report.results.filter(r=>r.id.startsWith('c172s-')&&r.status==='unsupported').length,9);
});

test('wind/body transform has independently known cardinal signs',()=>{
 const e=evaluate(x),body=bodyForce(x,e);
 assert.ok(Math.abs(body.x+780.9375)<1e-9);assert.equal(body.y,0);assert.ok(Math.abs(body.z+5726.875)<1e-9);
 const a=bodyForce({...x,alpha_rad:Math.PI/2},e);
 assert.ok(Math.abs(a.x-5726.875)<1e-9);assert.ok(Math.abs(a.z+780.9375)<1e-9);
 const b=bodyForce({...x,beta_rad:Math.PI/2},{...e,side_wind_n:100});
 assert.ok(Math.abs(b.x+100)<1e-9);assert.ok(Math.abs(b.y+780.9375)<1e-9);
});
