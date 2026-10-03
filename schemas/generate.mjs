import { mkdir, readFile, writeFile } from 'node:fs/promises';
import { createHash } from 'node:crypto';
import { contractNames, schemaFor } from './definitions.mjs';

const check = process.argv.includes('--check');
const entries = [];
const definitionsBytes = JSON.stringify({
  $schema: 'https://json-schema.org/draft/2020-12/schema',
  $id: 'https://flight-simulator.invalid/contracts/v1/definitions.schema.json',
  $defs: (await import('./definitions.mjs')).definitions
}, null, 2) + '\n';
const definitionsUrl = new URL('v1/definitions.schema.json', import.meta.url);
if (check) { if (await readFile(definitionsUrl, 'utf8') !== definitionsBytes) throw new Error('Stale definitions'); }
else { await mkdir(new URL('v1/', import.meta.url), { recursive: true }); await writeFile(definitionsUrl, definitionsBytes); }
for (const name of contractNames) {
  const path = `v1/${name}.schema.json`;
  const bytes = JSON.stringify(schemaFor(name), null, 2) + '\n';
  entries.push({ type: name, schema_version: 1, path, sha256: createHash('sha256').update(bytes).digest('hex') });
  const url = new URL(path, import.meta.url);
  if (check) { if (await readFile(url, 'utf8') !== bytes) throw new Error(`Stale schema: ${path}`); }
  else { await mkdir(new URL('v1/', import.meta.url), { recursive: true }); await writeFile(url, bytes); }
}
const bytes = JSON.stringify({ registry_version: 1, dialect: 'https://json-schema.org/draft/2020-12/schema',
  definitions: { path: 'v1/definitions.schema.json', sha256: createHash('sha256').update(definitionsBytes).digest('hex') }, contracts: entries }, null, 2) + '\n';
if (check) { if (await readFile(new URL('registry.json', import.meta.url), 'utf8') !== bytes) throw new Error('Stale registry'); }
else await writeFile(new URL('registry.json', import.meta.url), bytes);
console.log(`${check ? 'Checked' : 'Generated'} ${entries.length} versioned contracts`);
