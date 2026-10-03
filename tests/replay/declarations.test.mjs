import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { createHash } from 'node:crypto';
import { identityBytes, validateDeclarations } from './proof.mjs';
import { scenario } from '../fdm/fixture.mjs';
import { contractSetSha256 } from '../../schemas/validate.mjs';
const hash=bytes=>createHash('sha256').update(bytes).digest('hex');
test('trusted replay identity preserves exact binary/compiler identity and rejects malformed data',()=>{
  const values=[...Array(5).fill('a'.repeat(64)),'MSVC-19.40.33813.0','1.3.1 test'];
  const bytes=identityBytes(values);assert.equal(bytes.readUInt16LE(),64);assert.equal(bytes.subarray(2,66).toString(),'a'.repeat(64));
  for(const change of [[],[...values,'extra'],values.map((v,i)=>i===0?'A'.repeat(64):v),values.map((v,i)=>i===5?'a\n':v),values.map((v,i)=>i===6?'a'.repeat(257):v),values.map((v,i)=>i===5?'':v)])assert.throws(()=>identityBytes(change));
});
test('cross-file save declarations reject incompatible identity, corruption and unsupported claims',async()=>{
  const s=await scenario(),identity=[...Array(5).fill('a'.repeat(64)),'MSVC-19.40.33813.0','1.3.1 test'];
  const files=new Map([['admissions.ndjson',Buffer.from('{}\n')],['events.ndjson',Buffer.from('{}\n')],['recipe.bin',Buffer.from('private native recipe')]]);
  const entry=(path,role)=>({path,role,bytes:files.get(path).length,sha256:hash(files.get(path))});
  const manifest=JSON.parse(await readFile(new URL('../contracts/fixtures/SessionManifest.json',import.meta.url))),fingerprint=hash(Buffer.from(JSON.stringify(identity))),evidence='p1-original-fixed-step-reconstruction-v1';
  Object.assign(manifest,{build:{id:'proof-fixture',git_commit:'0'.repeat(40),fingerprint},contract_set_sha256:contractSetSha256,clock:s.clock,seed:s.seed,initial_conditions:s.initial_conditions,
    aircraft:s.required_aircraft,world:s.required_world,scenario:{id:s.id,version:s.version,sha256:hash(Buffer.from(JSON.stringify(s)))},calibration:{id:'original-synthetic-uncalibrated',version:'0.1.0-prototype',sha256:identity[4]},
    command_log:entry('admissions.ndjson','command-log'),event_log:entry('events.ndjson','event-log'),restore_capability:'replay-from-start',restore_evidence_id:evidence});
  const manifestBytes=Buffer.from(JSON.stringify(manifest)),manifestHash=hash(manifestBytes);
  const checkpoint={type:'Checkpoint',schema_version:1,tick:'72000',session_id:manifest.session_id,id:'proof-cut',session_manifest_sha256:manifestHash,build_fingerprint:fingerprint,restore_capability:'replay-from-start',restore_evidence_id:evidence,blobs:[entry('recipe.bin','state')],replay_until_tick:'72000'};
  const replay={type:'ReplayHeader',schema_version:1,session:{id:manifest.session_id,version:'0.1.0-prototype',sha256:manifestHash},build_fingerprint:fingerprint,contract_set_sha256:contractSetSha256,clock:s.clock,seed:s.seed,record_count:'1',command_log_sha256:manifest.command_log.sha256,determinism:'same-build-tolerances'};
  const packet={manifestBytes,replay,checkpoint,files,identity,scenario:s};validateDeclarations(packet);
  for(const mutation of [p=>p.checkpoint.restore_capability='complete-checkpoint',p=>p.checkpoint.replay_until_tick='71999',p=>p.replay.seed='1',p=>p.replay.record_count='2',p=>p.replay.build_fingerprint='b'.repeat(64),p=>p.replay.session.sha256='b'.repeat(64),p=>p.checkpoint.session_id='other-session',p=>p.checkpoint.contract_set_sha256='b'.repeat(64),p=>p.identity[0]='b'.repeat(64),p=>p.files.set('recipe.bin',Buffer.from('corrupted recipe')),p=>p.files.delete('events.ndjson'),p=>p.checkpoint.blobs[0].path='../escape.bin',p=>p.replay.determinism='unproven',p=>p.checkpoint.schema_version=2]) {
    const changed=structuredClone(packet);changed.manifestBytes=Buffer.from(changed.manifestBytes);mutation(changed);assert.throws(()=>validateDeclarations(changed));
  }
  const changed=structuredClone(packet);const wrong=JSON.parse(manifestBytes);wrong.initial_conditions.aircraft.mass_kg=1000;changed.manifestBytes=Buffer.from(JSON.stringify(wrong));changed.replay.session.sha256=hash(changed.manifestBytes);changed.checkpoint.session_manifest_sha256=hash(changed.manifestBytes);assert.throws(()=>validateDeclarations(changed),'valid shape cannot replace accepted recipe');
});
