import { readFile, readdir } from 'node:fs/promises';
import { createHash } from 'node:crypto';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const hash = bytes => createHash('sha256').update(bytes).digest('hex');
const defaultRepositoryRoot = resolve(dirname(fileURLToPath(import.meta.url)), '../..');
const defaultAdapterRoot = join(defaultRepositoryRoot, 'native/fdm_jsbsim');
const digestPattern = /^[a-f0-9]{64}$/;

// Match source-variant.py fingerprint(): sorted JSON keys, ASCII metadata, no spaces.
function canonical(value) {
  if (Array.isArray(value)) return `[${value.map(canonical).join(',')}]`;
  if (value !== null && typeof value === 'object')
    return `{${Object.keys(value).sort().map(key => `${JSON.stringify(key)}:${canonical(value[key])}`).join(',')}}`;
  const text = JSON.stringify(value);
  if (typeof text !== 'string' || /[^\x00-\x7f]/.test(text)) throw new Error('Noncanonical backend metadata');
  return text;
}

// Derive accepted declarations from reviewed public metadata, not the build
// manifest or native receipt. This does not replace complete vendor verification
// performed by source-selection.cmake/source-variant.py before compilation.
export function backendIdentities(identityBytes, inventoryBytes) {
  const identity = JSON.parse(identityBytes), inventory = JSON.parse(inventoryBytes);
  const variants = new Map([
    ['jsbsim-1.3.1-event-aware-constant-power-v1', {schema: 2, files: 291, modified: 2}],
    ['jsbsim-1.3.1-event-aware-coupled-midpoint-v1', {schema: 3, files: 293, modified: 4}],
  ]);
  const variant = variants.get(identity?.source_variant);
  if (!variant) throw new Error('Unsupported public backend source variant');
  const identityKeys = ['schema_version', 'source_variant', 'upstream_commit', 'acquisition_sha256',
    'upstream_inventory_sha256', 'recipe_sha256', 'materializer_sha256', 'vendor_tree_sha256',
    'source_archive_sha256', 'source_archive_bytes', 'bundle_files', 'vendor_files', 'modified_vendor_files', 'changes'];
  if (!identity || Object.keys(identity).sort().join(',') !== identityKeys.sort().join(',') ||
      !Number.isSafeInteger(identity.source_archive_bytes) || identity.source_archive_bytes <= 0 ||
      identity.source_archive_bytes >= 16 * 1024 * 1024 || !Array.isArray(identity.changes) || identity.changes.length !== variant.modified ||
      identity.schema_version !== 1 ||
      identity.bundle_files !== variant.files || identity.vendor_files !== 279 || identity.modified_vendor_files !== variant.modified ||
      !/^[a-f0-9]{40}$/.test(identity.upstream_commit) ||
      ['acquisition_sha256', 'upstream_inventory_sha256', 'recipe_sha256', 'materializer_sha256',
       'vendor_tree_sha256', 'source_archive_sha256'].some(key => typeof identity[key] !== 'string' || !digestPattern.test(identity[key])) ||
      hash(inventoryBytes) !== identity.upstream_inventory_sha256 || inventory.upstream_file_count !== 279 ||
      !Array.isArray(inventory.files) || inventory.files.length !== 279 ||
      inventory.upstream_commit !== identity.upstream_commit || inventory.acquisition_sha256 !== identity.acquisition_sha256)
    throw new Error('Unsupported public backend identity or inventory');
  const names = new Set(), inventoryParts = [];
  for (const entry of [...inventory.files].sort((a, b) => a.path < b.path ? -1 : a.path > b.path ? 1 : 0)) {
    if (typeof entry.path !== 'string' || !/^[A-Za-z0-9_.+/-]+$/.test(entry.path) ||
        entry.path.split('/').some(part => !part || part === '.' || part === '..') || names.has(entry.path) ||
        typeof entry.sha256 !== 'string' || !digestPattern.test(entry.sha256))
      throw new Error('Noncanonical public source inventory');
    names.add(entry.path);
    inventoryParts.push(Buffer.from(entry.path + '\0'), Buffer.from(entry.sha256, 'hex'), Buffer.from('\n'));
  }
  const upstreamVariant = 'jsbsim-1.3.1-upstream';
  const upstream = { schema_version: 1, source_variant: upstreamVariant, upstream_commit: identity.upstream_commit,
    acquisition_sha256: identity.acquisition_sha256, upstream_inventory_sha256: identity.upstream_inventory_sha256,
    vendor_tree_sha256: hash(Buffer.concat(inventoryParts)) };
  // Exact selected verify.py result, reconstructed from its checked public pins.
  const verification = { schema_version: variant.schema, source_variant: identity.source_variant, bundle_files: variant.files, vendor_files: 279,
    unchanged_vendor_files: 279 - variant.modified, modified_vendor_files: variant.modified, provenance_reconstructed: true, recipe_sha256: identity.recipe_sha256,
    vendor_tree_sha256: identity.vendor_tree_sha256, materializer_sha256: identity.materializer_sha256 };
  const eventAware = { schema_version: 1, identity_file_sha256: hash(identityBytes), identity, verification };
  return new Map([[upstreamVariant, hash(canonical(upstream))], [identity.source_variant, hash(canonical(eventAware))]]);
}

// These values come from CMake's independently generated build declaration,
// never from the native receipt being checked. Missing/old manifests fail closed.
export function parseBuildIdentity(text) {
  if (typeof text !== 'string' || Buffer.byteLength(text, 'utf8') > 65536)
    throw new Error('Invalid JSBSim source/build manifest');
  const lines = text.replaceAll('\r\n', '\n').split('\n');
  const value = label => {
    const rows = lines.filter(line => line.startsWith(`${label}:`));
    if (rows.length !== 1) throw new Error(`Missing or duplicate ${label}`);
    const match = rows[0].match(new RegExp(`^${label}: ([a-f0-9]{64})$`));
    if (!match) throw new Error(`Malformed ${label}`);
    return match[1];
  };
  const variantRows = lines.filter(line => line.startsWith('Source variant:'));
  if (variantRows.length !== 1 || !/^Source variant: [a-z0-9][a-z0-9.-]{0,127}$/.test(variantRows[0]))
    throw new Error('Missing, duplicate or malformed source variant');
  return { variant: variantRows[0].slice('Source variant: '.length),
    backend: value('Backend identity SHA256'), buildControls: value('Build controls SHA256') };
}

export async function currentSourceFingerprint(executable, { adapterRoot = defaultAdapterRoot, repositoryRoot = defaultRepositoryRoot } = {}) {
  if (typeof executable !== 'string' || executable.length === 0)
    throw new Error('An explicit native executable path is required for its build identity');
  // Native targets are emitted to <build>/bin, including standalone CLI defaults.
  const manifest = join(dirname(resolve(executable)), '..', 'jsbsim-source-build-manifest.txt');
  const identity = parseBuildIdentity(await readFile(manifest, 'utf8'));
  const transport = identity.variant === 'jsbsim-1.3.1-event-aware-coupled-midpoint-v1'
    ? 'event-aware-coupled-midpoint-v1' : 'event-aware-constant-power-v1';
  const [identityBytes, inventoryBytes] = await Promise.all([
    readFile(join(repositoryRoot, `third_party/patches/jsbsim/${transport}/identity.json`)),
    readFile(join(repositoryRoot, 'tools/export/jsbsim/upstream-file-inventory.json')),
  ]);
  const accepted = backendIdentities(identityBytes, inventoryBytes);
  if (accepted.get(identity.variant) !== identity.backend)
    throw new Error('Build manifest declares an unknown or stale JSBSim backend identity');
  const paths = [];
  async function visit(path) {
    for (const entry of await readdir(join(adapterRoot, path), { withFileTypes: true })) {
      const child = `${path}/${entry.name}`;
      if (entry.isDirectory()) await visit(child);
      else if (entry.isFile()) paths.push(child);
      else throw new Error('Unexpected adapter source object');
    }
  }
  await visit('src');
  await visit('include');
  paths.sort();
  // Match native/fdm_jsbsim/CMakeLists.txt exactly, including raw file bytes,
  // LF separators and backend/build-control prefix order.
  let text = `jsbsim-backend:${identity.backend}\njsbsim-build-controls:${identity.buildControls}\n`;
  for (const path of paths) text += `${path}:${hash(await readFile(join(adapterRoot, path)))}\n`;
  return hash(Buffer.from(text));
}
