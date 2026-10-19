import { readFile, lstat, realpath } from 'node:fs/promises';
import { TextDecoder } from 'node:util';
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
  'native/godot_bridge/src/bridge.cpp',
  'native/godot_bridge/src/codec.hpp',
  'native/godot_bridge/src/codec.cpp',
  'native/godot_bridge/src/worker.hpp',
  'native/godot_bridge/src/worker.cpp',
  'native/godot_bridge/src/interactive_worker.hpp',
  'native/godot_bridge/src/interactive_worker.cpp',
  'native/godot_bridge/src/interactive_bridge.cpp',
  'native/godot_bridge/src/wire_numbers.hpp',
  'native/godot_bridge/src/wire_numbers.cpp',
]);


export const residentSources = Object.freeze([
  'native/world_core/grid/src/exact.hpp',
  'native/world_core/grid/src/validation.hpp',
  'native/world_core/grid/src/validation.cpp',
  'native/world_core/grid/src/canonical_frame.hpp',
  'native/world_core/grid/src/prepared_grid.cpp',
  'native/world_core/grid/src/grid_payload.cpp',
  'native/world_core/grid/include/flight/ground/prepared_grid.hpp',
  'native/world_core/grid/include/flight/ground/grid_payload.hpp',
  'native/world_core/ground/include/flight/ground/provider.hpp',
  'native/sim_core/contracts/include/flight/contracts/types.hpp',
  'native/sim_core/contracts/include/flight/contracts/boundaries.hpp',
  'native/sim_core/contracts/include/flight/contracts/geodesy.hpp',
  'native/fdm_jsbsim/interactive/include/flight/interactive/prepared_world.hpp',
  'native/fdm_jsbsim/interactive/src/prepared_world.cpp',
  'native/fdm_jsbsim/interactive/src/prepared_world_catalog.hpp',
  'content/world/catalog/kawo-runtime-v1.json',
  'native/fdm_jsbsim/include/flight/fdm/model.hpp',
  'native/fdm_jsbsim/include/flight/fdm/session.hpp',
  'native/fdm_jsbsim/include/flight/fdm/protocol.hpp',
  'native/fdm_jsbsim/src/model.cpp',
  'native/fdm_jsbsim/src/model_hashes.hpp',
  'native/fdm_jsbsim/src/session.cpp',
  'native/fdm_jsbsim/src/protocol.cpp',
]);
export const residentControls = Object.freeze([
  'native/world_core/grid/CMakeLists.txt',
  'native/world_core/ground/CMakeLists.txt',
  'native/sim_core/contracts/CMakeLists.txt',
  'tools/interactive-preview/world-catalog.mjs',
]);
const residentManifestPath = 'native/world_core/resident_world/component-v1.json';
// External reviewed raw pin: this checker is outside the component and 25/18 inputs.
const residentManifestSha256 = 'ad219321c2f867e11cbd49b1a18f513625a4e19b78b2c1cda56155c423f6d6b5';
const utf8 = new TextDecoder('utf-8', { fatal: true, ignoreBOM: true });

async function ordinaryBytes(path, maximum) {
  const stat = await lstat(path);
  if (!stat.isFile() || stat.isSymbolicLink() || stat.size <= 0 || stat.size > maximum ||
      await realpath(path) !== resolve(path))
    throw new Error('Resident component input must be bounded ordinary unaliased file');
  const bytes = await readFile(path);
  if (bytes.length !== stat.size) throw new Error('Resident component input changed while reading');
  return bytes;
}
function exactRoster(cmake, name, expected) {
  const matches = [...cmake.matchAll(new RegExp('set\\(' + name + '\\s+([\\s\\S]*?)\\)', 'g'))];
  if (matches.length !== 1 ||
      JSON.stringify(matches[0][1].trim().split(/\s+/)) !== JSON.stringify(expected))
    throw new Error('Changed or duplicate resident component ' + name + ' roster');
}
async function currentResidentComponent(repositoryRoot, build, cmake) {
  exactRoster(cmake, 'RESIDENT_WORLD_SOURCE_PATHS', residentSources);
  exactRoster(cmake, 'RESIDENT_WORLD_CONTROL_PATHS', residentControls);
  const manifestBytes = await ordinaryBytes(join(repositoryRoot, residentManifestPath), 65536);
  if (sha(manifestBytes) !== residentManifestSha256)
    throw new Error('Resident component manifest raw pin differs');
  const expected = { schema: 'ResidentWorldComponent/v1', sources: [], controls: [] };
  let total = 0, body = 'resident-world-component-v1\n';
  for (const [group, paths] of [['source', residentSources], ['control', residentControls]]) {
    for (const path of paths) {
      const bytes = await ordinaryBytes(join(repositoryRoot, path), 4 * 1024 * 1024);
      total += bytes.length;
      if (total > 16 * 1024 * 1024) throw new Error('Resident component closure exceeds 16MiB');
      const digest = sha(Buffer.from(utf8.decode(bytes).replaceAll('\r\n', '\n')));
      expected[group === 'source' ? 'sources' : 'controls'].push({ path, sha256: digest });
      body += group + ':' + path + ':' + digest + '\n';
    }
  }
  // Reconstruct the entire exact ASCII JSON document. This rejects unknown or
  // duplicate fields/rows, reordered entries and alternative serializations.
  if (!manifestBytes.equals(Buffer.from(JSON.stringify(expected, null, 2) + '\n')))
    throw new Error('Resident component manifest differs from current LF source/control bytes');
  const fingerprint = sha(Buffer.from(body));
  const witness = utf8.decode(await ordinaryBytes(
    join(build, 'resident-world-component-fingerprint.txt'), 65536)).replaceAll('\r\n', '\n');
  if (witness !== fingerprint + '\n' + body)
    throw new Error('Resident component compiled witness is stale or noncanonical');
  return fingerprint;
}

// The build manifest is build-side provenance from the verified bootstrap,
// never a native reply. This source comparison is not full ADR016 facade/package
// qualification: the independent delivery qualifier owns that separate gate.
export async function currentInteractiveIdentity(executable, { repositoryRoot = root } = {}) {
  if (typeof executable !== 'string' || executable.length === 0)
    throw new Error('An explicit interactive executable is required');
  const build = resolve(dirname(executable), '..');
  const manifestBytes = await readFile(join(build, 'jsbsim-source-build-manifest.txt'));
  const identity = parseBuildIdentity(manifestBytes.toString('utf8'));
  const transport = identity.variant === 'jsbsim-1.3.1-event-aware-coupled-midpoint-local-window-v2' ? 'event-aware-coupled-midpoint-local-window-v2'
    : identity.variant === 'jsbsim-1.3.1-event-aware-coupled-midpoint-v1' ? 'event-aware-coupled-midpoint-v1' : 'event-aware-constant-power-v1';
  const accepted = backendIdentities(
    await readFile(join(repositoryRoot, `third_party/patches/jsbsim/${transport}/identity.json`)),
    await readFile(join(repositoryRoot, 'tools/export/jsbsim/upstream-file-inventory.json')));
  if (accepted.get(identity.variant) !== identity.backend)
    throw new Error('Build manifest declares an unknown or stale JSBSim backend identity');
  const cmake = await readFile(join(repositoryRoot, 'native/fdm_jsbsim/interactive/CMakeLists.txt'), 'utf8');
  const rosters = [...cmake.matchAll(/set\(INTERACTIVE_SOURCE_PATHS\s+([\s\S]*?)\)/g)];
  if (rosters.length !== 1 || JSON.stringify(rosters[0][1].trim().split(/\s+/)) !== JSON.stringify(interactiveSources))
    throw new Error('Changed or duplicate interactive source roster');
  const residentComponent = await currentResidentComponent(repositoryRoot, build, cmake);
  const sources = [];
  let body = `verified-jsbsim-backend:${identity.backend}\njsbsim-build-controls:${identity.buildControls}\nresident-world-component:${residentComponent}\n`;
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
    build_manifest_sha256: sha(manifestBytes),
    resident_component_sha256: residentComponent,
    resident_component_manifest_sha256: residentManifestSha256 };
}
