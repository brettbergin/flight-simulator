#!/usr/bin/env node
import fs from 'node:fs';
import { COUPLED_ID, auditCoupledRegister, auditCoupledRelease } from './modified-jsbsim.mjs';
import { auditRuntimeRelease, runtimeNames } from '../export/check-runtime.mjs';
import path from 'node:path';
import crypto from 'node:crypto';
import { fileURLToPath } from 'node:url';

const HASH = /^[a-f0-9]{64}$/;
const ID = /^[a-z0-9][a-z0-9-]*$/;
const CLASSES = new Set(['runtime', 'binding', 'database', 'aircraft-model', 'aircraft-reference', 'geographic-data', 'visual-assets', 'audio-assets']);
const STATES = new Set(['permitted', 'conditional', 'excluded']);
const EVIDENCE = new Set(['source-verified', 'provisional', 'not-acquired', 'synthetic']);
const OBLIGATIONS = new Set(['retain-notices', 'stage-third-party-notices', 'include-corresponding-source', 'allow-library-replacement', 'permit-reverse-engineering', 'record-modifications', 'retain-source-attribution', 'verify-product-rights', 'no-redistribution']);
const ROLES = new Set(['binary', 'content', 'notice', 'source', 'build-instructions', 'evidence']);
const plain = value => value !== null && typeof value === 'object' && !Array.isArray(value);
const nonempty = value => typeof value === 'string' && value.trim().length > 0;
const https = value => {
  try { const url = new URL(value); return url.protocol === 'https:' && !url.username && !url.password; }
  catch { return false; }
};
export const sha256 = data => crypto.createHash('sha256').update(data).digest('hex');

// Portable package paths only. realpath additionally prevents escaping via symlink.
function relativePath(value) {
  return nonempty(value) && !value.includes('\\') && !value.includes(':') &&
    !path.posix.isAbsolute(value) && !path.win32.isAbsolute(value) &&
    !value.split('/').some(part => part === '..' || part === '.' || part === '');
}
function inside(root, target) {
  const rel = path.relative(root, target);
  return rel !== '' && !rel.startsWith(`..${path.sep}`) && rel !== '..' && !path.isAbsolute(rel);
}
function checkedFile(root, relative, errors, context, expected) {
  if (!relativePath(relative)) { errors.push(`${context}: unsafe relative path`); return null; }
  try {
    const canonicalRoot = fs.realpathSync(root);
    const target = path.resolve(canonicalRoot, relative);
    const canonical = fs.realpathSync(target);
    if (!inside(canonicalRoot, canonical) || fs.lstatSync(target).isSymbolicLink()) {
      errors.push(`${context}: path escapes root or is a symlink`); return null;
    }
    const stat = fs.statSync(canonical);
    if (!stat.isFile()) { errors.push(`${context}: not a regular file`); return null; }
    // Hash by streaming bounded chunks, never load a large source archive into memory.
    const hash = crypto.createHash('sha256');
    const fd = fs.openSync(canonical, 'r');
    try {
      const buffer = Buffer.alloc(64 * 1024);
      for (;;) { const length = fs.readSync(fd, buffer, 0, buffer.length, null); if (!length) break; hash.update(buffer.subarray(0, length)); }
    } finally { fs.closeSync(fd); }
    const actual = hash.digest('hex');
    if (!HASH.test(expected ?? '') || actual !== expected) errors.push(`${context}: SHA-256 mismatch or missing digest`);
    return actual;
  } catch { errors.push(`${context}: missing or unreadable file`); return null; }
}

export function auditRegister(register, { repoRoot } = {}) {
  const errors = [];
  if (!plain(register) || register.schema_version !== 1 || !Array.isArray(register.entries)) return ['register: invalid schema/version/entries'];
  if (!/^\d{4}-\d{2}-\d{2}$/.test(register.reviewed_on ?? '')) errors.push('register: missing review date');
  if (!Array.isArray(register.required_classes) || register.required_classes.length !== CLASSES.size ||
      new Set(register.required_classes).size !== CLASSES.size || register.required_classes.some(item => !CLASSES.has(item))) errors.push('register: required classes must enumerate the complete rights inventory');
  const ids = new Set();
  const classes = new Set();
  for (const entry of register.entries) {
    if (!plain(entry)) { errors.push('register: invalid entry'); continue; }
    const label = nonempty(entry.id) ? entry.id : '<missing-id>';
    if (!ID.test(entry.id ?? '') || ids.has(entry.id)) errors.push(`${label}: invalid or duplicate ID`);
    ids.add(entry.id);
    if (!CLASSES.has(entry.class)) errors.push(`${label}: unknown class`); else classes.add(entry.class);
    for (const field of ['name', 'version', 'owner', 'scope', 'decision', 'license']) {
      if (!nonempty(entry[field])) errors.push(`${label}: missing ${field}`);
    }
    if (!STATES.has(entry.redistribution)) errors.push(`${label}: unknown redistribution state`);
    if (!EVIDENCE.has(entry.evidence)) errors.push(`${label}: unknown evidence status`);
    if (!plain(entry.source) || !https(entry.source.url) || !nonempty(entry.source.revision) ||
        !https(entry.source.rights_url) || !nonempty(entry.source.applicability)) errors.push(`${label}: incomplete source/right/applicability metadata`);
    if (!Array.isArray(entry.obligations) || entry.obligations.length === 0 ||
        new Set(entry.obligations).size !== entry.obligations.length || entry.obligations.some(item => !OBLIGATIONS.has(item))) errors.push(`${label}: missing, duplicate or unknown obligations`);
    if (!Array.isArray(entry.obligations)) continue;
    if (entry.source?.archive_sha256 !== undefined && !HASH.test(entry.source.archive_sha256)) errors.push(`${label}: invalid source archive digest`);
    if (!Array.isArray(entry.notice_files)) { errors.push(`${label}: missing notice inventory`); continue; }
    const notices = new Set();
    for (const notice of entry.notice_files) {
      if (!plain(notice) || !relativePath(notice.path) || !HASH.test(notice.sha256 ?? '') || !https(notice.source_url) || notices.has(notice.path)) {
        errors.push(`${label}: incomplete or duplicate notice record`); continue;
      }
      notices.add(notice.path);
      if (repoRoot) checkedFile(repoRoot, notice.path, errors, `${label} notice ${notice.path}`, notice.sha256);
    }
    if (entry.id === 'microsoft-vc143-crt') {
      const policy=entry.runtime_policy;
      if (!plain(policy)||!Array.isArray(policy.inventories)||policy.inventories.length===0||
          policy.debug_nonredist_allowed!==false||policy.system32_copies_allowed!==false||policy.immutable!==true) errors.push(`${label}: missing exact release-runtime policy`);
      else for(const inventory of policy.inventories) {
        if(!plain(inventory)||!/^14\.\d+\.\d+\.\d+$/.test(inventory.version??'')||!/^14\.\d+\.\d+$/.test(inventory.redist_revision??'')||
          !Array.isArray(inventory.files)||inventory.files.length!==runtimeNames.length||new Set(inventory.files.map(f=>f?.name)).size!==runtimeNames.length||
          inventory.files.some(f=>!plain(f)||!runtimeNames.includes(f.name)||f.version!==inventory.version||!Number.isSafeInteger(f.bytes)||f.bytes<=0||!HASH.test(f.sha256??''))) errors.push(`${label}: malformed reviewed CRT inventory`);
      }
    }
    if (entry.redistribution === 'excluded') {
      if (!nonempty(entry.blocker) || !entry.obligations?.includes('no-redistribution')) errors.push(`${label}: excluded material requires blocker and no-redistribution obligation`);
    } else if (STATES.has(entry.redistribution)) {
      if (entry.evidence !== 'source-verified' && entry.evidence !== 'synthetic') errors.push(`${label}: included rights cannot use provisional or unacquired evidence`);
      if (/unresolved|unknown|unselected/i.test(`${entry.license} ${entry.version} ${entry.source?.revision}`)) errors.push(`${label}: unresolved identity/license cannot be included`);
      if (entry.notice_files.length === 0) errors.push(`${label}: included component requires a notice file`);
      if (entry.obligations?.includes('no-redistribution')) errors.push(`${label}: included component cannot prohibit redistribution`);
    }
    if (entry.obligations?.includes('stage-third-party-notices') && entry.notice_files.length < 2) errors.push(`${label}: bundled third-party notice file missing`);
    const releasePolicy = entry.library_policy?.release_policy;
    if (releasePolicy !== undefined && (releasePolicy !== COUPLED_ID || entry.id !== COUPLED_ID)) errors.push(`${label}: unknown or misplaced release policy`);
    if (entry.id === COUPLED_ID) {
      if (!entry.obligations.includes('include-corresponding-source')) errors.push(`${label}: reserved source obligations missing`);
      auditCoupledRegister(entry, { repoRoot, errors, checkedFile });
    }
    if (entry.obligations?.includes('include-corresponding-source')) {
      if (!plain(entry.library_policy) || entry.library_policy.linkage !== 'dynamic' ||
          !nonempty(entry.library_policy.source_delivery) || !nonempty(entry.library_policy.modification_policy)) errors.push(`${label}: incomplete shared-library/source policy`);
      if (!entry.obligations.includes('allow-library-replacement') || !entry.obligations.includes('permit-reverse-engineering') || !entry.obligations.includes('record-modifications')) errors.push(`${label}: incomplete LGPL release obligations`);
      // A release still requires an exact source digest, even when acquisition is pending.
      if (entry.library_policy?.source_archive_sha256 !== null && !HASH.test(entry.library_policy?.source_archive_sha256 ?? '')) errors.push(`${label}: source archive digest must be verified SHA-256 or explicit null`);
    }
  }
  for (const cls of CLASSES) if (!classes.has(cls)) errors.push(`register: missing ${cls} inventory`);
  return errors;
}

function scanFiles(root, errors) {
  const result = new Set();
  function visit(directory, prefix = '') {
    for (const item of fs.readdirSync(directory, { withFileTypes: true })) {
      const rel = prefix + item.name;
      if (item.isSymbolicLink()) { errors.push(`package: symlink ${rel} is prohibited`); continue; }
      if (item.isDirectory()) visit(path.join(directory, item.name), rel + '/');
      else if (item.isFile()) result.add(rel);
      else errors.push(`package: unsupported filesystem object ${rel}`);
    }
  }
  try { visit(root); } catch { errors.push('package: missing or unreadable staging directory'); }
  return result;
}

export function auditRelease(register, manifest, { repoRoot, packageRoot } = {}) {
  const errors = auditRegister(register, { repoRoot });
  if (errors.length) return errors;
  if (!plain(manifest) || manifest.schema_version !== 1 || !Array.isArray(manifest.components) || manifest.components.length === 0) return ['release: invalid schema/version or empty components'];
  if (!packageRoot) return ['release: packageRoot required'];
  const registry = new Map(register.entries.map(entry => [entry.id, entry]));
  const components = new Set();
  const declared = new Map();
  for (const component of manifest.components) {
    if (!plain(component)) { errors.push('release: invalid component'); continue; }
    const label = component.id ?? '<missing-id>';
    const entry = registry.get(component.id);
    if (!entry) { errors.push(`${label}: unregistered release component`); continue; }
    if (components.has(component.id)) errors.push(`${label}: duplicate release component`);
    components.add(component.id);
    if (entry.redistribution === 'excluded') errors.push(`${label}: excluded material cannot be packaged`);
    if (component.version !== entry.version || component.source_revision !== entry.source.revision) errors.push(`${label}: version/revision differs from rights review`);
    if (!Array.isArray(component.files) || component.files.length === 0) { errors.push(`${label}: missing file inventory`); continue; }
    const componentFiles = new Map();
    for (const file of component.files) {
      if (!plain(file) || !relativePath(file.path) || !HASH.test(file.sha256 ?? '') || !ROLES.has(file.role)) { errors.push(`${label}: invalid file record`); continue; }
      if (componentFiles.has(file.path)) errors.push(`${label}: duplicate file ${file.path}`);
      componentFiles.set(file.path, file);
      // Shared notices can belong to multiple components only with identical integrity/role.
      const previous = declared.get(file.path);
      if (previous && (previous.sha256 !== file.sha256 || previous.role !== file.role)) errors.push(`${label}: conflicting ownership for ${file.path}`);
      declared.set(file.path, file);
      checkedFile(packageRoot, file.path, errors, `${label} file ${file.path}`, file.sha256);
    }
    if (!Array.isArray(component.notices)) errors.push(`${label}: missing staged notice mapping`);
    else {
      for (const expected of entry.notice_files) {
        const matching = component.notices.filter(item => plain(item) && item.register_path === expected.path);
        const file = matching.length === 1 ? componentFiles.get(matching[0].package_path) : null;
        if (!file || file.role !== 'notice' || file.sha256 !== expected.sha256) errors.push(`${label}: required staged notice missing or changed: ${expected.path}`);
      }
      for (const notice of component.notices) if (!plain(notice) || !entry.notice_files.some(item => item.path === notice.register_path)) errors.push(`${label}: unknown staged notice mapping`);
    }
    if (entry.runtime_policy) errors.push(...auditRuntimeRelease(entry,component,{packageRoot}));
    if (entry.obligations.includes('include-corresponding-source')) {
      const source = componentFiles.get(component.source_archive);
      if (!HASH.test(entry.library_policy.source_archive_sha256 ?? '') || !source || source.role !== 'source' || source.sha256 !== entry.library_policy.source_archive_sha256) errors.push(`${label}: exact corresponding-source archive missing or not pinned`);
      const instructions = componentFiles.get(component.build_instructions);
      if (!instructions || instructions.role !== 'build-instructions') errors.push(`${label}: source build/replacement instructions missing`);
      const sharedLibrary = componentFiles.get(component.shared_library);
      if (component.linkage !== 'dynamic' || !sharedLibrary || sharedLibrary.role !== 'binary') errors.push(`${label}: replaceable shared-library package required`);
      const replacement = componentFiles.get(component.replacement_test);
      if (!replacement || replacement.role !== 'evidence') errors.push(`${label}: DLL replacement test evidence missing`);
      if (component.reverse_engineering_permitted !== true) errors.push(`${label}: modification/debugging permission not recorded`);
      if (component.id === COUPLED_ID) auditCoupledRelease(entry, component, { repoRoot, packageRoot, componentFiles, errors, checkedFile });
      else if (component.modified !== false) errors.push(`${label}: modified library needs new reviewed source digest and modification policy`);
    }
  }
  if (components.has('jsbsim') && components.has(COUPLED_ID)) errors.push('release: pristine and coupled JSBSim components cannot coexist');
  for (const file of scanFiles(packageRoot, errors)) {
    if (!declared.has(file)) errors.push(`package: undeclared file ${file}`);
    if (/^(?:msvcp|vcruntime).*\\.dll$/i.test(path.posix.basename(file)) && !components.has('microsoft-vc143-crt')) errors.push('package: Microsoft CRT requires exact-runtime policy component');
  }
  return errors;
}

export function auditDependencyLock(register, lock) {
  if (!plain(lock) || lock.schema_version !== 1 || !Array.isArray(lock.sources) || !Array.isArray(lock.tools)) return ['dependency lock: invalid schema'];
  const errors = [];
  const registry = new Map(register.entries.map(entry => [entry.id, entry]));
  const checked = new Set();
  for (const item of [...lock.sources, ...lock.tools]) {
    if (!plain(item)) { errors.push('dependency lock: invalid item'); continue; }
    if (!item.license_id) {
      // Build-only tools are not released. Packaging one requires a rights entry.
      if (!lock.sources.includes(item)) continue;
      errors.push(`dependency lock: source ${item.id} missing license_id`); continue;
    }
    const entry = registry.get(item.license_id);
    if (!entry || entry.redistribution === 'excluded') { errors.push(`dependency lock: ${item.id} rights missing or excluded`); continue; }
    checked.add(entry.id);
    if (item.version !== entry.version) errors.push(`dependency lock: ${item.id} version differs from rights review`);
    if (lock.sources.includes(item)) {
      if ((item.commit ?? item.source_id) !== entry.source.revision || item.sha256 !== entry.source.archive_sha256) errors.push(`dependency lock: ${item.id} revision/digest differs from rights review`);
    }
  }
  for (const id of ['jsbsim', 'godot-cpp', 'sqlite', 'godot']) if (!checked.has(id)) errors.push(`dependency lock: ${id} not checked`);
  return errors;
}

function readJSON(filename) {
  if (fs.statSync(filename).size > 8 * 1024 * 1024) throw new Error('JSON inventory exceeds 8 MiB limit');
  return JSON.parse(fs.readFileSync(filename, 'utf8'));
}
function cli(args) {
  const options = {};
  for (let i = 0; i < args.length; i += 2) {
    if (!['--register', '--repo-root', '--release', '--package-root', '--dependency-lock'].includes(args[i]) || !args[i + 1] || args[i + 1].startsWith('--') || options[args[i]]) throw new Error('usage: node tools/license-audit/audit.mjs [--register FILE] [--repo-root DIR] [--dependency-lock FILE] [--release FILE --package-root DIR]');
    options[args[i]] = args[i + 1];
  }
  const repoRoot = path.resolve(options['--repo-root'] ?? path.join(path.dirname(fileURLToPath(import.meta.url)), '../..'));
  const registerPath = path.resolve(options['--register'] ?? path.join(repoRoot, 'third_party/licenses/register.json'));
  const register = readJSON(registerPath);
  let errors;
  if (options['--release'] || options['--package-root']) {
    if (!options['--release'] || !options['--package-root']) throw new Error('--release and --package-root must be used together');
    const packageRoot = fs.realpathSync(path.resolve(options['--package-root']));
    const releasePath = fs.realpathSync(path.resolve(options['--release']));
    if (inside(packageRoot, releasePath)) throw new Error('keep the release inventory outside its payload staging directory');
    errors = auditRelease(register, readJSON(releasePath), { repoRoot, packageRoot });
  } else errors = auditRegister(register, { repoRoot });
  if (!errors.length && options['--dependency-lock']) errors.push(...auditDependencyLock(register, readJSON(path.resolve(options['--dependency-lock']))));
  if (errors.length) { for (const error of errors) process.stderr.write(`FAIL ${error}\n`); process.exitCode = 1; }
  else process.stdout.write(`PASS ${options['--release'] ? 'release payload rights/integrity' : 'rights inventory and notice integrity'} (${register.entries.length} entries)\n`);
}
if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  try { cli(process.argv.slice(2)); } catch (error) { process.stderr.write(`FAIL ${error.message}\n`); process.exitCode = 1; }
}
