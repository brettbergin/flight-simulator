import assert from 'node:assert/strict';
import {inflateSync} from 'node:zlib';

export function crc32(bytes) {
  let crc=0xffffffff;
  for(const byte of bytes) {
    crc^=byte;
    for(let bit=0;bit<8;bit++) crc=(crc>>>1)^((crc&1)?0xedb88320:0);
  }
  return (crc^0xffffffff)>>>0;
}

export function decodePNG(bytes) {
  assert(bytes.subarray(0,8).equals(Buffer.from([137,80,78,71,13,10,26,10])),'PNG signature');
  let offset=8,width,height,channels,ended=false;
  const compressed=[];
  while(offset<bytes.length) {
    assert(offset+12<=bytes.length,'Truncated PNG chunk');
    const length=bytes.readUInt32BE(offset);
    assert(length<=64*1024*1024 && offset+12+length<=bytes.length,'Bounded PNG chunk');
    const type=bytes.toString('ascii',offset+4,offset+8);
    const data=bytes.subarray(offset+8,offset+8+length);
    assert.equal(crc32(bytes.subarray(offset+4,offset+8+length)),bytes.readUInt32BE(offset+8+length),'PNG CRC');
    if(type==='IHDR') {
      assert.equal(offset,8); assert.equal(length,13);
      width=data.readUInt32BE(0); height=data.readUInt32BE(4);
      assert(width>0 && width<=3840 && height>0 && height<=2160,'Bounded PNG dimensions');
      assert.equal(data[8],8,'Eight-bit PNG required');
      assert(data[9]===2 || data[9]===6,'RGB/RGBA PNG required');
      channels=data[9]===6?4:3;
      assert(data.subarray(10).every(value=>value===0),'Noninterlaced standard PNG required');
    } else if(type==='IDAT') {
      assert(width && !ended); compressed.push(data);
    } else if(type==='IEND') {
      assert.equal(length,0); ended=true;
      assert.equal(offset+12,bytes.length,'Trailing PNG data');
    } else assert(type[0]===type[0].toLowerCase(),'Unsupported critical PNG chunk');
    offset+=length+12;
  }
  assert(ended && compressed.length && width,'Incomplete PNG');
  const stride=width*channels;
  const raw=inflateSync(Buffer.concat(compressed),{maxOutputLength:(stride+1)*height});
  assert.equal(raw.length,(stride+1)*height,'PNG decoded size');
  const pixels=Buffer.alloc(stride*height);
  for(let y=0;y<height;y++) {
    const filter=raw[y*(stride+1)]; assert(filter<=4,'Unknown PNG filter');
    for(let x=0;x<stride;x++) {
      const left=x>=channels?pixels[y*stride+x-channels]:0;
      const above=y>0?pixels[(y-1)*stride+x]:0;
      const corner=y>0 && x>=channels?pixels[(y-1)*stride+x-channels]:0;
      let prediction=0;
      if(filter===1) prediction=left;
      if(filter===2) prediction=above;
      if(filter===3) prediction=Math.floor((left+above)/2);
      if(filter===4) {
        const p=left+above-corner, a=Math.abs(p-left), b=Math.abs(p-above), c=Math.abs(p-corner);
        prediction=a<=b && a<=c?left:b<=c?above:corner;
      }
      pixels[y*stride+x]=(raw[y*(stride+1)+1+x]+prediction)&255;
    }
  }
  return {width,height,channels,pixels};
}

export function comparePNG(beforeBytes,afterBytes,threshold) {
  const before=decodePNG(beforeBytes),after=decodePNG(afterBytes);
  assert.equal(before.width,after.width); assert.equal(before.height,after.height);
  assert(Number.isInteger(threshold) && threshold>=0 && threshold<=255);
  let changed=0,maximum=0;
  for(let i=0;i<before.width*before.height;i++) {
    let delta=0;
    for(let channel=0;channel<3;channel++) delta=Math.max(delta,Math.abs(before.pixels[i*before.channels+channel]-after.pixels[i*after.channels+channel]));
    maximum=Math.max(maximum,delta);
    if(delta>threshold) changed++;
  }
  return {width:before.width,height:before.height,pixels:before.width*before.height,changed_pixels:changed,changed_fraction:changed/(before.width*before.height),maximum_channel_delta:maximum,channel_delta_threshold:threshold};
}
