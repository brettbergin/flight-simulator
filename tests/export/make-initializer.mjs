import {readFile,writeFile} from 'node:fs/promises';
import {encodeRequest} from '../../tools/run-scenario/runner.mjs';
import {scenario} from '../fdm/fixture.mjs';
const bytes=encodeRequest(await scenario(),[],{duration_s:10,sample_hz:1});
const destination=new URL('./initializer.bin',import.meta.url);
if(process.argv.includes('--check')) {
  if(!bytes.equals(await readFile(destination))) throw new Error('Export initializer fixture drift');
} else await writeFile(destination,bytes);
