import test from 'node:test';
import assert from 'node:assert/strict';
import {nearestRank,parseTrace,reduceTrace} from './reduce.mjs';
import {comparePNG,crc32,decodePNG} from './png.mjs';
import {deflateSync} from 'node:zlib';
const header='process_frame,wall_us,frame_ms,gpu_timestamp_frame,new_gpu_sample,gpu_render_ms,cpu_render_ms,video_bytes,origin_version\n';
const trace=header+'1,1000000,10,0,1,2,1,1000,1\n2,1020000,20,1,1,4,2,2000,1\n3,1050000,30,2,1,6,3,3000,2\n';
test('nearest rank and elapsed-weighted FPS agree with hand-calculated uneven intervals',()=>{
  assert.equal(nearestRank([9,1,4,6],.75),6);
  const result=reduceTrace(parseTrace(trace));
  assert.equal(result.average_fps,50);
  assert.equal(result.measured_wall_s,.06);
  assert.equal(result.engine_callback_interval_ms.p95,30);
  assert.equal(result.gpu_render_ms.p95,6);
  assert.equal(result.origin_version,2);
});
test('truncation, duplicate frames, wrong intervals, nonfinite data and regressed origins reject',()=>{
  for(const corrupted of [header,trace.replace('2,1020000','1,1020000'),trace.replace('1020000,20','1020000,19'),trace.replace('4,2,2000','NaN,2,2000'),trace.replace('3000,2','3000,0')]) assert.throws(()=>parseTrace(corrupted));
});
test('delayed GPU observations are not manufactured into new samples',()=>{
  const delayed=trace.replace('2,1020000,20,1,1,4','2,1020000,20,0,0,2');
  assert.equal(reduceTrace(parseTrace(delayed)).gpu_render_ms.unique_frames,2);
  assert.throws(()=>parseTrace(trace.replace('2,1020000,20,1,1','2,1020000,20,0,1')));
  assert.throws(()=>parseTrace(trace.replace('1,1000000,10,0,1,2','1,1000000,10,0,1,0')));
});

function chunk(name,data) {
  const kind=Buffer.from(name),size=Buffer.alloc(4),crc=Buffer.alloc(4);
  size.writeUInt32BE(data.length); crc.writeUInt32BE(crc32(Buffer.concat([kind,data])));
  return Buffer.concat([size,kind,data,crc]);
}
function png(channels,pixels) {
  const header=Buffer.alloc(13); header.writeUInt32BE(2,0); header.writeUInt32BE(1,4);
  header[8]=8; header[9]=channels===4?6:2;
  return Buffer.concat([Buffer.from([137,80,78,71,13,10,26,10]),chunk('IHDR',header),chunk('IDAT',deflateSync(Buffer.from([0,...pixels]))),chunk('IEND',Buffer.alloc(0))]);
}
test('actual PNG bytes determine the image delta independent of RGBA alpha and summaries',()=>{
  const before=png(4,[0,0,0,255,100,100,100,255]);
  const after=png(3,[0,0,0,100,109,100]);
  const result=comparePNG(before,after,8);
  assert.equal(result.changed_pixels,1); assert.equal(result.changed_fraction,.5);
  assert.equal(result.maximum_channel_delta,9);
  assert.equal(comparePNG(before,before,8).changed_pixels,0);
  assert.throws(()=>decodePNG(Buffer.from(before).fill(0,29,30)),/CRC/);
  assert.throws(()=>decodePNG(before.subarray(0,-1)),/Truncated|Bounded/);
});
