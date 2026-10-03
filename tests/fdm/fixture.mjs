import { readFile } from 'node:fs/promises';
import { join } from 'node:path';
import { repoRoot, modelRoot, sha } from '../../tools/run-scenario/runner.mjs';
export async function scenario(rate=120) {
  const s=JSON.parse(await readFile(join(repoRoot,'tests/contracts/fixtures/ScenarioManifest.json'),'utf8'));
  const inventory=await readFile(join(modelRoot,'inventory.json')); const digest=sha(inventory);
  s.id='synthetic-flight-probe';s.clock={tick_rate_hz:rate,purpose:rate===120?'runtime':'convergence'};
  s.sources=[{id:'original-fixture',revision:'0.1.0-prototype',locator:'urn:flight-simulator:original-synthetic-model',sha256:digest,rights:'redistributable',license:'MIT',
    applicability:'Original synthetic numerical fixture; no aircraft calibration.',effective_from:null,effective_until:null}];
  s.files=[{path:'inventory.json',sha256:digest,bytes:inventory.length,role:'dynamics'}];s.required_aircraft={id:'original-synthetic',version:'0.1.0-prototype',sha256:digest};
  const a=s.initial_conditions.aircraft;a.clock=s.clock;a.position={latitude_rad:.8,longitude_rad:-2,ellipsoid_height_m:1000};
  const e2=(1/298.257223563)*(2-1/298.257223563),sin=Math.sin(.8),cos=Math.cos(.8),n=6378137/Math.sqrt(1-e2*sin*sin);
  a.ecef_position_m={x:(n+1000)*cos*Math.cos(-2),y:(n+1000)*cos*Math.sin(-2),z:(n*(1-e2)+1000)*sin};
  a.orientation_body_to_ned={w:Math.cos(.01),x:0,y:Math.sin(.01),z:0};a.velocity_body_mps={x:55*Math.cos(.02),y:0,z:55*Math.sin(.02)};
  a.mass_kg=1100;a.systems=[];
  const w=s.initial_conditions.atmosphere;w.position=a.position;w.model_id='jsbsim-dry-isa';
  const geopotential=6356766*1000/(6356766+1000);w.temperature_k=288.15-.0065*geopotential;
  w.pressure_pa=101325*(w.temperature_k/288.15)**(9.80665/(287.05287*.0065));w.density_kgpm3=w.pressure_pa/(287.05287*w.temperature_k);return s;
}
export function command(s,seconds,sequence,axes) {
  // Command tick t applies over [(t-1)/Hz,t/Hz]; same physical onset across rates.
  return {type:'ControlCommand',schema_version:1,tick:String(seconds*s.clock.tick_rate_hz+1),session_id:s.initial_conditions.aircraft.session_id,
    sequence:String(sequence),source_id:'pilot.controls',authority:'pilot',assistance:{profile_id:'unassisted',active:[]},payload:{kind:'axes',...axes}};
}
