import fs from 'node:fs';
import path from 'node:path';
import { spawnSync } from 'node:child_process';

const root = process.cwd();
const errors = [];
const required = ['AGENTS.md', 'README.md', 'CONTRIBUTING.md', 'SECURITY.md',
  'docs/README.md', 'docs/product.md', 'docs/architecture.md', 'docs/contracts.md',
  'docs/realism-and-validation.md', 'docs/training-and-safety.md', 'docs/world-and-data.md',
  'docs/experience-and-progress.md', 'docs/roadmap.md', 'docs/agent-operations.md',
  'docs/delivery.md', 'docs/sources.md', 'docs/risks.md', 'docs/requirements.md', 'docs/phases/README.md',
  'docs/backlog.md', 'docs/backlog.json', 'docs/issue-index.md'];
for (const file of required) if (!fs.existsSync(path.join(root, file))) errors.push(`Missing ${file}`);

function walk(dir) {
  return fs.readdirSync(dir, { withFileTypes: true }).flatMap(entry => {
    if (['.git', '.local', 'dist', 'node_modules', '.godot', 'build', 'out'].includes(entry.name)) return [];
    const full = path.join(dir, entry.name);
    return entry.isDirectory() ? walk(full) : [full];
  });
}
const files = walk(root);
const markdown = files.filter(file => file.endsWith('.md'));
for (const file of markdown) {
  const raw = fs.readFileSync(file, 'utf8');
  if (raw.includes('\uFFFD')) errors.push(`Invalid text encoding in ${path.relative(root, file)}`);
  // Ignore examples in fenced code; validate actual local Markdown links and images.
  const text = raw.replace(/^```[^\n]*\n[\s\S]*?^```\s*$/gm, '');
  for (const match of text.matchAll(/!?\[[^\]\n]*\]\((<[^>]+>|[^\s)]+)(?:\s+"[^"]*")?\)/g)) {
    const target = match[1].replace(/^<|>$/g, '');
    if (/^(?:https?:|mailto:|app:|codex:)/i.test(target) || target.startsWith('#')) continue;
    const local = decodeURIComponent(target.split('#')[0]);
    if (!local) continue;
    if (path.isAbsolute(local) || /^[A-Za-z]:/.test(local)) {
      errors.push(`Nonportable local link ${target} in ${path.relative(root, file)}`);
      continue;
    }
    const resolved = path.resolve(path.dirname(file), local);
    if (!resolved.startsWith(root + path.sep) || !fs.existsSync(resolved)) {
      errors.push(`Broken/escaping link ${target} in ${path.relative(root, file)}`);
    }
  }
}

const backlogPath = path.join(root, 'docs/backlog.json');
if (fs.existsSync(backlogPath)) {
  try {
    const backlog = JSON.parse(fs.readFileSync(backlogPath, 'utf8'));
    if (backlog.schema_version !== 1 || backlog.repository !== 'brettbergin/flight-simulator') errors.push('Invalid backlog schema/repository');
    const labels = new Set(backlog.labels.map(x => x.name));
    const milestones = new Set(backlog.milestones.map(x => x.key));
    const issues = new Map(backlog.issues.map(x => [x.key, x]));
    const requirementIds = new Set();
    for (const source of ['product.md','experience-and-progress.md','realism-and-validation.md','training-and-safety.md','world-and-data.md']) {
      const sourcePath = path.join(root,'docs',source);
      if (fs.existsSync(sourcePath)) for (const match of fs.readFileSync(sourcePath,'utf8').matchAll(/\b(?:PRD|UX|REAL|SAFE|WORLD)-\d{3}\b/g)) requirementIds.add(match[0]);
    }
    const mappedIds = new Set(backlog.issues.flatMap(x=>x.requirements ?? []));
    for (const id of requirementIds) if (!mappedIds.has(id)) errors.push(`Unmapped requirement ${id}`);
    for (const id of mappedIds) if (!requirementIds.has(id)) errors.push(`Unknown requirement ${id}`);
    if (issues.size !== backlog.issues.length) errors.push('Duplicate issue keys');
    if (labels.size !== backlog.labels.length) errors.push('Duplicate labels');
    for (const item of backlog.issues) {
      if (!/^[A-Z0-9-]+$/.test(item.key)) errors.push(`Invalid key ${item.key}`);
      if (!item.title || !item.summary || !item.acceptance?.length || !item.evidence?.length || !item.owned_paths?.length || !item.docs?.length) errors.push(`Incomplete issue ${item.key}`);
      if (!milestones.has(item.phase)) errors.push(`Unknown phase ${item.key}`);
      for (const label of item.labels) if (!labels.has(label)) errors.push(`Unknown label ${label} on ${item.key}`);
      for (const prefix of ['type:', 'priority:', 'phase:', 'status:']) {
        if (item.labels.filter(x => x.startsWith(prefix)).length !== 1) errors.push(`Need one ${prefix} label on ${item.key}`);
      }
      if (!item.labels.includes(`phase:${item.phase}`)) errors.push(`Phase label mismatch ${item.key}`);
      if (!item.labels.some(x => x.startsWith('area:'))) errors.push(`Missing area on ${item.key}`);
      for (const dependency of item.depends_on) if (!issues.has(dependency) || dependency === item.key) errors.push(`Invalid dependency ${dependency} on ${item.key}`);
      if (item.parent && (issues.get(item.parent)?.kind !== 'epic' || issues.get(item.parent)?.phase !== item.phase)) errors.push(`Invalid parent ${item.key}`);
      for (const doc of item.docs) if (!fs.existsSync(path.join(root, doc.split('#')[0]))) errors.push(`Missing issue doc ${doc} on ${item.key}`);
    }
    const active = new Set(); const visited = new Set();
    function visit(key) {
      if (active.has(key)) { errors.push(`Dependency cycle at ${key}`); return; }
      if (visited.has(key) || !issues.has(key)) return;
      active.add(key);
      for (const dep of issues.get(key).depends_on) visit(dep);
      active.delete(key); visited.add(key);
    }
    for (const key of issues.keys()) visit(key);
    if (!errors.length) console.log(`Validated ${issues.size} planned issues, ${labels.size} labels, ${milestones.size} phases.`);
  } catch (error) { errors.push(`Backlog parse/validation: ${error.message}`); }
}

for (const file of files.filter(x => x.includes(`${path.sep}.github${path.sep}workflows${path.sep}`))) {
  const text = fs.readFileSync(file, 'utf8');
  for (const match of text.matchAll(/^\s*-?\s*uses:\s*([^\s#]+)/gm)) {
    if (!match[1].startsWith('./') && !/@[a-f0-9]{40}$/.test(match[1])) errors.push(`Unpinned action ${match[1]}`);
  }
}
if (!errors.length && fs.existsSync('tools/render-plan.mjs')) {
  const generated = spawnSync(process.execPath,['tools/render-plan.mjs','--check'],{encoding:'utf8'});
  if (generated.stdout) process.stdout.write(generated.stdout);
  if (generated.stderr) process.stderr.write(generated.stderr);
  if (generated.status !== 0) errors.push('Generated plan is stale; run node tools/render-plan.mjs');
}
if (errors.length) {
  for (const error of errors) console.error(error);
  process.exitCode = 1;
} else console.log(`Foundation checks passed (${markdown.length} Markdown files). External URLs, Markdown anchors, workflow execution, and aviation fidelity require their separate review evidence.`);
