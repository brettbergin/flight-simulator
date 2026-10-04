import fs from 'node:fs';
import {validateContract} from '../../schemas/validate.mjs';
const packet=JSON.parse(fs.readFileSync(new URL('./reference.json',import.meta.url),'utf8'));
let checked=0;const failures=[];
const deliberatelyBadAircraft=new Set(['ecef-position-mismatch','duplicate-fuel-source']);
for(const fixture of packet.cases){
 for(const [key,type] of [['aircraft','AircraftSnapshot'],['atmosphere','AtmosphereSample']]){
  const value=fixture.input[key];if(value===null)continue;
  const result=validateContract(value,type);
  const expected=!(key==='aircraft'&&deliberatelyBadAircraft.has(fixture.id));
  checked++;if(result.valid!==expected)failures.push({id:fixture.id,key,expected,errors:result.errors});
 }
}
const report={passed:failures.length===0,checked_v1_records:checked,failures,scope:'Accepted schema+semantic validation of independent input records only; no NativeReadings consumer import or observation'};
fs.writeFileSync(new URL('./input-validation.json',import.meta.url),JSON.stringify(report,null,2)+'\n');
console.log(JSON.stringify(report));process.exitCode=report.passed?0:1;
