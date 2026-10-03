import { readFile, writeFile } from 'node:fs/promises';
import { encodeRequest } from '../../tools/run-scenario/runner.mjs';
import { scenario, command } from './fixture.mjs';
const s=await scenario();const axes={roll:.02,pitch:.025,yaw:.04,throttle:.65,mixture:1,left_brake:0,right_brake:0,trim:0};
const bytes=encodeRequest(s,[command(s,0,'9007199254740993',axes)]);
const file=new URL('./transport-request.bin',import.meta.url);
if(process.argv.includes('--check')) {if(!bytes.equals(await readFile(file)))throw new Error('Transport fixture is stale');}
else await writeFile(file,bytes);
