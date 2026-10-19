// Original MIT. Offline lexical, complete fixed-pack and reproduction controls.
import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {strictJson,loadBundle,reproduce} from './world-catalog.mjs';
const root=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'../..');
test('strict bounded JSON refuses extensions, duplicate decoded keys and invalid scalars',()=>{
  const parse=s=>strictJson(Buffer.from(s),4096,8,64);
  for(const input of ['{"x":1,"x":2}','{"x":1,"\\u0078":2}','{"x":1,}','[1,]','{"x" 1}','[1,,2]','{} {}','01','+1','1.','NaN','1e309','"\\ud800"','"\\udc00"','\ufeff{}'])assert.throws(()=>parse(input),input);
  assert.throws(()=>strictJson(Buffer.from([34,0xc0,0xaf,34]),4096,8,64));
  assert.deepEqual(JSON.parse(JSON.stringify(parse('{"x":-125.5e-2,"y":[null,true,"\\ud83c\\udf32"]}'))),{x:-1.255,y:[null,true,'🌲']});
  assert.throws(()=>strictJson(Buffer.from('[[0]]'),4096,1,64));
  assert.throws(()=>strictJson(Buffer.from('[0,1]'),4096,8,2));
  assert.throws(()=>strictJson(Buffer.from('{}'),1,8,64));
});
test('complete retained product and both generated representations agree',()=>{
  const bundle=loadBundle(root);
  assert.equal(bundle.catalogSha,'c097d91e6c8263e75f2ca3339f60d5bd3c387ea22e90f6093e02169757f94799');
  assert.equal(bundle.total,26059579);
  assert.equal(bundle.start.position.latitude_rad.$binary64_le,'a0f390632ae5ea3f');
  assert.equal(bundle.start.orientation_rpy_ned_rad.pitch.$binary64_le,'d3552f7b5a31723f');
  assert.equal(reproduce(root,false).outputs.length,2);
});
test('missing, extra, changed and crossed fixed-pack inputs refuse',()=>{
  const parent=path.join(root,'.local','world-catalog-negative-tests');
  fs.mkdirSync(parent,{recursive:true});
  const scratch=fs.mkdtempSync(path.join(parent,'attempt-'));
  const pack=path.join(scratch,'content/world/airports/kawo/runtime-v1');
  const original=path.join(root,'content/world/airports/kawo/runtime-v1');
  fs.mkdirSync(pack,{recursive:true});
  for(const name of fs.readdirSync(original))fs.copyFileSync(path.join(original,name),path.join(pack,name));
  const catalog='content/world/catalog/kawo-runtime-v1.json';
  fs.mkdirSync(path.dirname(path.join(scratch,catalog)),{recursive:true});
  fs.copyFileSync(path.join(root,catalog),path.join(scratch,catalog));
  assert.equal(loadBundle(scratch).catalogSha,loadBundle(root).catalogSha);
  const start=path.join(pack,'start-ready34.json');
  fs.renameSync(start,start+'.missing');
  assert.throws(()=>loadBundle(scratch));
  fs.renameSync(start+'.missing',start);
  fs.writeFileSync(path.join(pack,'extra.txt'),'extra');
  assert.throws(()=>loadBundle(scratch));
  fs.unlinkSync(path.join(pack,'extra.txt'));
  const bytes=fs.readFileSync(start);
  const changed=Buffer.from(bytes);changed[0]=32;fs.writeFileSync(start,changed);
  assert.throws(()=>loadBundle(scratch));
  fs.writeFileSync(start,bytes);
  const entry=JSON.parse(fs.readFileSync(path.join(scratch,catalog),'utf8'));
  entry.world_anchor.ellipsoid_height_m.$binary64_le='0000000000000080';
  fs.writeFileSync(path.join(scratch,catalog),JSON.stringify(entry));
  assert.throws(()=>loadBundle(scratch));
  // Retain the small isolated negative fixture; never delete repository inputs.
});
