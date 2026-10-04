import fs from 'node:fs';
import path from 'node:path';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const SHA = /^[0-9a-f]{40}$/;
const ROOT_DOCS = new Set(['README.md', 'AGENTS.md', 'CONTRIBUTING.md', 'SECURITY.md']);
export function allowedPath(name) {
  if (typeof name !== 'string' || /[\x00-\x1f\x7f\\]/u.test(name) || name.startsWith('/')) return false;
  const segments = name.split('/');
  if (segments.some(x => !x || x === '.' || x === '..')) return false;
  if (ROOT_DOCS.has(name) || name === 'docs/backlog.json') return true;
  return /^docs\/(?:[A-Za-z0-9][A-Za-z0-9_. -]*\/)*[A-Za-z0-9][A-Za-z0-9_. -]*\.md$/u.test(name);
}
export function classifyRaw(raw) {
  const records = new TextDecoder('utf-8', {fatal: true}).decode(raw).split('\0');
  if (records.pop() !== '') throw new Error('diff-not-nul-terminated');
  if (!records.length) return {docs_only: false, reason: 'empty-diff', files: []};
  if (records.length % 2 !== 0) throw new Error('malformed-raw-diff');
  const files = [];
  for (let i = 0; i < records.length; i += 2) {
    const match = /^:([0-7]{6}) ([0-7]{6}) ([0-9a-f]{40}) ([0-9a-f]{40}) ([A-Z][0-9]*)$/u.exec(records[i]);
    if (!match) throw new Error('malformed-raw-header');
    const [, old_mode, new_mode, old_blob, new_blob, status] = match;
    const file = {path: records[i + 1], status, old_mode, new_mode, old_blob, new_blob};
    files.push(file);
    const regular = new_mode === '100644' && ((status === 'A' && old_mode === '000000') || (status === 'M' && old_mode === '100644'));
    if (!regular || !allowedPath(file.path)) return {docs_only: false, reason: 'outside-docs-admission', files};
  }
  return {docs_only: true, reason: 'only-added-or-modified-regular-documentation', files};
}
function git(repo, args) {
  const result = spawnSync('git', ['-C', repo, ...args], {encoding: null, maxBuffer: 16 * 1024 * 1024});
  if (result.error || result.status !== 0) throw new Error('git-evidence-unavailable');
  return result.stdout;
}
export function classifyContext({repo, eventName, event, checkoutSHA, repository}) {
  const evidence = {version: 1, docs_only: false, reason: 'default-full', event: eventName, base: null, head: null, checkout: checkoutSHA, files: [], merge_files: [], runtime_proof_executed: null};
  try {
    if (eventName !== 'pull_request') return {...evidence, reason: 'non-pr-full'};
    const pr = event?.pull_request;
    if (!pr || !SHA.test(pr.base?.sha) || !SHA.test(pr.head?.sha) || !SHA.test(checkoutSHA) || pr.base?.repo?.full_name !== repository) return {...evidence, reason: 'invalid-event-binding'};
    evidence.base = pr.base.sha; evidence.head = pr.head.sha;
    const resolve = value => git(repo, ['rev-parse', '--verify', value + '^{commit}']).toString('utf8').trim();
    if (resolve('HEAD') !== checkoutSHA || resolve(evidence.base) !== evidence.base || resolve(evidence.head) !== evidence.head) return {...evidence, reason: 'checkout-or-object-mismatch'};
    const parents = git(repo, ['rev-list', '--parents', '-n', '1', checkoutSHA]).toString('utf8').trim().split(' ');
    if (parents.length !== 3 || parents[1] !== evidence.base || parents[2] !== evidence.head) return {...evidence, reason: 'merge-parent-mismatch'};
    git(repo, ['diff', '--quiet', '--']); git(repo, ['diff', '--cached', '--quiet', '--']);
    const raw = (from, to) => git(repo, ['diff', '--raw', '-z', '--no-abbrev', '--no-renames', '--no-ext-diff', '--no-textconv', from, to, '--']);
    const source = classifyRaw(raw(evidence.base, evidence.head));
    evidence.files = source.files;
    if (!source.docs_only) return {...evidence, reason: source.reason};
    // Also inspect the actual tested merge tree; merge-only edits cannot escape head comparison.
    const merged = classifyRaw(raw(evidence.base, checkoutSHA));
    evidence.merge_files = merged.files;
    if (!merged.docs_only) return {...evidence, reason: 'actual-merge-outside-docs-admission'};
    return {...evidence, docs_only: true, reason: source.reason, runtime_proof_executed: false};
  } catch { return {...evidence, reason: 'evidence-unavailable-full'}; }
}
if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  let receipt;
  try {
    const event = JSON.parse(fs.readFileSync(process.env.GITHUB_EVENT_PATH, 'utf8'));
    receipt = classifyContext({repo: process.cwd(), eventName: process.env.GITHUB_EVENT_NAME, event, checkoutSHA: process.env.GITHUB_SHA, repository: process.env.GITHUB_REPOSITORY});
  } catch { receipt = {version: 1, docs_only: false, reason: 'event-unavailable-full', runtime_proof_executed: null}; }
  fs.mkdirSync('.local/native-ci-scope', {recursive: true});
  fs.writeFileSync('.local/native-ci-scope/receipt.json', JSON.stringify(receipt, null, 2) + '\n');
  if (process.env.GITHUB_OUTPUT) fs.appendFileSync(process.env.GITHUB_OUTPUT, 'docs_only=' + String(receipt.docs_only) + '\n');
  console.log(JSON.stringify(receipt));
}
