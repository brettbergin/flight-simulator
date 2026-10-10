import { readFile } from 'node:fs/promises';
import { createHash } from 'node:crypto';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { backendIdentities, parseBuildIdentity } from '../../tools/run-scenario/source-fingerprint.mjs';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '../..');
const sha = bytes => createHash('sha256').update(bytes).digest('hex');
export const interactiveSources = Object.freeze([
  'native/fdm_jsbsim/interactive/src/session.cpp',
  'native/fdm_jsbsim/interactive/include/flight/interactive/session.hpp',
  'native/fdm_jsbsim/interactive/include/flight/interactive/surface.hpp',
  'tests/interactive/native.cpp', 'tests/interactive/negatives.hpp',
  'native/fdm_jsbsim/interactive/src/model-pins.hpp',
  'native/fdm_jsbsim/interactive/src/piston-model-pins.hpp',
  'tests/engine/CMakeLists.txt', 'tests/engine/loaded-library.hpp',
  'tests/engine/native.cpp', 'tests/engine/native-mechanism.cpp',
  'tests/engine/native-validate.py', 'tests/engine/native-generate.py',
  'tests/engine/native-limits.hpp', 'tests/engine/native-limits.json',
]);

// The build manifest is build-side provenance from the verified bootstrap,
// never a native reply. This source comparison is not full ADR016 facade/package
// qualification: the independent delivery qualifier owns that separate gate.
export async function currentInteractiveIdentity(executable, { repositoryRoot = root } = {}) {
  if (typeof executable !== 'string' || executable.length === 0)
    throw new Error('An explicit interactive executable is required');
  const build = resolve(dirname(executable), '..');
  const manifestBytes = await readFile(join(build, 'jsbsim-source-build-manifest.txt'));
  const identity = parseBuildIdentity(manifestBytes.toString('utf8'));
  const transport = identity.variant === 'jsbsim-1.3.1-event-aware-coupled-midpoint-v1'
    ? 'event-aware-coupled-midpoint-v1' : 'event-aware-constant-power-v1';
  const accepted = backendIdentities(
    await readFile(join(repositoryRoot, `third_party/patches/jsbsim/${transport}/identity.json`)),
    await readFile(join(repositoryRoot, 'tools/export/jsbsim/upstream-file-inventory.json')));
  if (accepted.get(identity.variant) !== identity.backend)
    throw new Error('Build manifest declares an unknown or stale JSBSim backend identity');
  const cmake = await readFile(join(repositoryRoot, 'native/fdm_jsbsim/interactive/CMakeLists.txt'), 'utf8');
  const rosters = [...cmake.matchAll(/set\(INTERACTIVE_SOURCE_PATHS\s+([\s\S]*?)\)/g)];
  if (rosters.length !== 1 || JSON.stringify(rosters[0][1].trim().split(/\s+/)) !== JSON.stringify(interactiveSources))
    throw new Error('Changed or duplicate interactive source roster');
  const sources = [];
  let body = `verified-jsbsim-backend:${identity.backend}\njsbsim-build-controls:${identity.buildControls}\n`;
  for (const path of interactiveSources) {
    const bytes = await readFile(join(repositoryRoot, path));
    const normalized_sha256 = sha(Buffer.from(bytes.toString('utf8').replaceAll('\r\n', '\n')));
    sources.push({ path, normalized_sha256 });
    body += `${path}:${normalized_sha256}\n`;
  }
  const fingerprint = sha(Buffer.from(body));
  // CMake text metadata uses native line endings on Windows; source hashes and
  // the canonical body remain LF, while the build manifest witness stays raw.
  const declared = (await readFile(join(build, 'interactive-source-fingerprint.txt'), 'utf8')).replaceAll('\r\n', '\n');
  if (fingerprint + '\n' + body !== declared)
    throw new Error('Compiled interactive source declaration is stale or noncanonical');
  return { fingerprint, sources, source_variant: identity.variant,
    backend_identity_sha256: identity.backend, build_control_sha256: identity.buildControls,
    build_manifest_sha256: sha(manifestBytes) };
}
