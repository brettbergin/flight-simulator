import fs from 'node:fs';
import path from 'node:path';
import { execFileSync } from 'node:child_process';

const backlog = JSON.parse(fs.readFileSync('docs/backlog.json', 'utf8'));
const apply = process.argv.includes('--apply');
if (process.argv.slice(2).some(x => x !== '--apply')) throw new Error('Usage: node tools/sync-github.mjs [--apply]');
if (!/^[A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+$/.test(backlog.repository)) throw new Error('Invalid repository identity');
if (!apply) {
  console.log(`Preview only: ${backlog.repository}; ${backlog.labels.length} labels, ${backlog.milestones.length} milestones, ${backlog.issues.length} issues.`);
  for (const phase of backlog.milestones) console.log(`${phase.key}: ${backlog.issues.filter(x => x.phase === phase.key).length} issues — ${phase.title}`);
  process.exit(0);
}
execFileSync(process.execPath, ['tools/check-docs.mjs'], { stdio: 'inherit' });
const repo = backlog.repository;
const ledgerPath = '.local/github-sync.json';
fs.mkdirSync('.local', { recursive: true });
let ledger;
try {
  ledger = fs.existsSync(ledgerPath) ? JSON.parse(fs.readFileSync(ledgerPath, 'utf8')) : undefined;
} catch {
  const quarantined = `${ledgerPath}.corrupt-${Date.now()}`;
  fs.renameSync(ledgerPath, quarantined);
  console.log(`Preserved invalid ledger at ${quarantined}; recovering from remote stable markers.`);
}
ledger ??= { repository: repo, issues: {}, milestones: {} };
if (ledger.repository !== repo) throw new Error('Ledger repository mismatch');
const save = () => {
  const temporary = `${ledgerPath}.tmp`;
  fs.writeFileSync(temporary, JSON.stringify(ledger, null, 2) + '\n');
  fs.renameSync(temporary, ledgerPath);
};
function api(endpoint, method = 'GET', payload) {
  const args = ['api', endpoint, '--method', method];
  if (payload) args.push('--input', '-');
  const result = execFileSync('gh', args, { input: payload ? JSON.stringify(payload) : undefined, encoding: 'utf8', maxBuffer: 20 * 1024 * 1024 });
  return result.trim() ? JSON.parse(result) : null;
}
function paged(endpoint) {
  return JSON.parse(execFileSync('gh', ['api', endpoint, '--paginate', '--slurp'], { encoding: 'utf8', maxBuffer: 30 * 1024 * 1024 })).flat();
}

const existingLabels = new Set(paged(`repos/${repo}/labels?per_page=100`).map(x => x.name));
for (const label of backlog.labels) if (!existingLabels.has(label.name)) {
  api(`repos/${repo}/labels`, 'POST', label);
  console.log(`Created label ${label.name}`);
}
const milestones = paged(`repos/${repo}/milestones?state=all&per_page=100`);
for (const phase of backlog.milestones) {
  let existing = milestones.find(x => x.title === phase.title);
  if (!existing) {
    existing = api(`repos/${repo}/milestones`, 'POST', { title: phase.title, description: phase.description });
    console.log(`Created milestone ${phase.key}`);
  }
  ledger.milestones[phase.key] = existing.number; save();
}

const remoteIssues = paged(`repos/${repo}/issues?state=all&per_page=100`).filter(x => !x.pull_request);
const marker = key => `<!-- flight-sim-backlog:${key} -->`;
const lookup = new Map();
for (const item of backlog.issues) {
  const matches = remoteIssues.filter(x => (x.body ?? '').includes(marker(item.key)));
  if (matches.length > 1) throw new Error(`Duplicate marker ${item.key}; investigate before mutation`);
  const titleConflicts = remoteIssues.filter(x => x.title.startsWith(`[${item.key}] `) && !(x.body ?? '').includes(marker(item.key)));
  if (titleConflicts.length) throw new Error(`Stable-key title collision ${item.key} on #${titleConflicts[0].number}; investigate before issue creation`);
  if (matches.length) {
    lookup.set(item.key, matches[0].number);
    ledger.issues[item.key] = matches[0].number;
  } else if (ledger.issues[item.key]) throw new Error(`Ledger issue ${item.key} lost its marker or no longer exists; investigate`);
}
save();
const link = key => lookup.has(key) ? `#${lookup.get(key)} (${key})` : `\`${key}\` (publication pending)`;
function body(item) {
  const lines = [marker(item.key), `## Outcome\n\n${item.summary}`, `Phase: **${item.phase}**. Stable key: \`${item.key}\`.`];
  if (item.parent) lines.push(`Parent gate: ${link(item.parent)}.`);
  lines.push(`## Dependencies\n\n${item.depends_on.length ? item.depends_on.map(key => `- [ ] ${link(key)}`).join('\n') : 'No prior implementation dependency; owner review is required where specified.'}`);
  const children = backlog.issues.filter(x => x.parent === item.key);
  if (children.length) lines.push(`## Child work\n\n${children.map(x => `- [ ] ${link(x.key)} — ${x.title}`).join('\n')}`);
  lines.push(`## Owned paths\n\n${item.owned_paths.map(x => `- \`${x}\``).join('\n')}`);
  lines.push(`## Plan and requirements\n\n${item.docs.map(x => `- [${x}](https://github.com/${repo}/blob/main/${x})`).join('\n')}`);
  if (item.requirements?.length) lines.push(`Requirement references: ${item.requirements.map(x => `\`${x}\``).join(', ')}.`);
  lines.push(`## Acceptance\n\n${item.acceptance.map(x => `- [ ] ${x}`).join('\n')}`);
  lines.push(`## Closure evidence\n\n${item.evidence.map(x => `- ${x}`).join('\n')}`);
  lines.push('Claim work only after linked dependencies and phase gates are satisfied. A merged PR or green CI alone does not establish aircraft fidelity. Keep the generated plan fields in docs/backlog.json synchronized with scope changes.');
  return lines.join('\n\n') + '\n';
}
for (const item of backlog.issues) if (!lookup.has(item.key)) {
  const issue = api(`repos/${repo}/issues`, 'POST', { title: `[${item.key}] ${item.title}`, body: body(item), labels: item.labels, milestone: ledger.milestones[item.phase] });
  lookup.set(item.key, issue.number); ledger.issues[item.key] = issue.number; save();
  console.log(`Created ${item.key}: #${issue.number}`);
}
for (const item of backlog.issues) {
  const number = lookup.get(item.key);
  const existing = remoteIssues.find(x => x.number === number);
  let desired = body(item);
  // Preserve completed checkboxes for unchanged generated criteria/dependencies.
  for (const match of (existing?.body ?? '').matchAll(/^- \[[xX]\] (.+)$/gm)) {
    desired = desired.replace(`- [ ] ${match[1]}\n`, `- [x] ${match[1]}\n`);
  }
  // Preserve live labels/state/assignees; generated text and milestone reflect the plan.
  if (existing?.body !== desired || existing?.title !== `[${item.key}] ${item.title}` || existing?.milestone?.number !== ledger.milestones[item.phase]) {
    api(`repos/${repo}/issues/${number}`, 'PATCH', { title: `[${item.key}] ${item.title}`, body: desired, milestone: ledger.milestones[item.phase] });
    console.log(`Linked ${item.key}: #${number}`);
  }
}
let index = '# Issue index\n\nGenerated from [backlog.json](backlog.json). All links refer to planned work; the owner review gate remains open until the owner accepts the plan.\n\n';
for (const phase of backlog.milestones) {
  index += `## ${phase.title}\n\n| Key | Issue | Dependencies |\n|---|---|---|\n`;
  for (const item of backlog.issues.filter(x => x.phase === phase.key)) {
    index += `| ${item.key} | [#${lookup.get(item.key)} ${item.title}](https://github.com/${repo}/issues/${lookup.get(item.key)}) | ${item.depends_on.length ? item.depends_on.join(', ') : 'Owner review'} |\n`;
  }
  index += '\n';
}
fs.writeFileSync(path.join('docs', 'issue-index.md'), index.trimEnd() + '\n');
console.log(`Publication complete: ${lookup.size} issues. No issues were closed or assigned. Live status labels need integrator updates as dependencies close.`);
