import fs from 'node:fs';
import assert from 'node:assert/strict';
function read(file){return fs.readFileSync(file,'utf8').split(/\r?\n/).filter(l=>l.startsWith('FLIGHT_PROOF_RECORD ')).map(l=>JSON.parse(l.slice(20))).filter(r=>!['initialization','runtime_modules'].includes(r.kind));}
const [baseline,replacement]=process.argv.slice(2);
const first=read(baseline),second=read(replacement);
assert.equal(first.length,second.length);
function compare(a,b,path='root') {
  if(typeof a==='number') {assert(Number.isFinite(a)&&Number.isFinite(b));assert(Math.abs(a-b)<=Math.max(1e-9,Math.abs(a)*1e-12),path);return;}
  if(a&&typeof a==='object') {assert.deepEqual(Object.keys(a).sort(),Object.keys(b).sort(),path);for(const k of Object.keys(a))compare(a[k],b[k],path+'.'+k);return;}
  assert.equal(a,b,path);
}
compare(first,second);
console.log('PASS independent DLL replacement command/snapshot invariants');
