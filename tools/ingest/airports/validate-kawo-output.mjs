import { openSync, readSync, closeSync } from 'node:fs';
import { resolve, join } from 'node:path';
import { createHash } from 'node:crypto';
import { validateSourcePair } from './source-contract.mjs';

// Separate, explicit final contract check. The Python ingester never spawns Node.
const args = process.argv.slice(2);
if (args.length !== 2 || args[0] !== '--directory') {
  console.error('Usage: node tools/ingest/airports/validate-kawo-output.mjs --directory OUTPUT');
  process.exitCode = 2;
} else {
  const boundedRead = (path) => {
    const fd = openSync(path, 'r');
    try {
      const bytes = Buffer.alloc(4194305);
      let length = 0;
      while (length < bytes.length) {
        const count = readSync(fd, bytes, length, bytes.length - length, null);
        if (count === 0) break;
        length += count;
      }
      return bytes.subarray(0, length);
    } finally { closeSync(fd); }
  };
  try {
    const directory = resolve(args[1]);
    const dossier = boundedRead(join(directory, 'dossier.json'));
    const airport = boundedRead(join(directory, 'airport.json'));
    const result = validateSourcePair(dossier, airport);
    if (!result.ok) {
      console.log(JSON.stringify({ ok: false, errors: result.errors }));
      process.exitCode = 1;
    } else {
      const sha = bytes => createHash('sha256').update(bytes).digest('hex');
      console.log(JSON.stringify({ ok: true, validator: 'validateSourcePair',
        dossier_sha256: sha(dossier), airport_sha256: sha(airport),
        dossier_bytes: dossier.length, airport_bytes: airport.length,
        review_state: result.airport.review_state, purpose: result.airport.purpose,
        scope: 'Source-pair contract conformance only; no geographic/runtime acceptance' }));
    }
  } catch {
    console.error('Source pair validation failed to read bounded local inputs.');
    process.exitCode = 2;
  }
}
