import fs from 'node:fs';
import { execFileSync } from 'node:child_process';

const args = process.argv.slice(2);
if (args.some(x => !['--apply', '--verify'].includes(x)) || (args.includes('--apply') && args.includes('--verify'))) {
  throw new Error('Usage: node tools/agent-prompts.mjs [--apply | --verify]');
}
const apply = args.includes('--apply');
const verify = args.includes('--verify');
const backlog = JSON.parse(fs.readFileSync('docs/backlog.json', 'utf8'));
const repo = backlog.repository;
if (repo !== 'brettbergin/flight-simulator') throw new Error('Unexpected repository');
const base = `https://github.com/${repo}`;
const index = fs.readFileSync('docs/issue-index.md', 'utf8');
const indexRows = [...index.matchAll(/^\| ([A-Z0-9-]+) \| \[#(\d+)/gm)].map(x => [x[1], Number(x[2])]);
const numbers = new Map(indexRows);
const byKey = new Map(backlog.issues.map(x => [x.key, x]));
if (numbers.size !== backlog.issues.length || indexRows.length !== numbers.size || byKey.size !== backlog.issues.length || [...byKey.keys()].some(key => !numbers.has(key)) || new Set(numbers.values()).size !== numbers.size) throw new Error('Issue index must cover the exact backlog with unique keys and issue numbers');
const phaseFiles = ['p0-foundations','p1-flight-core','p2-first-flight','p3-complete-circuit','p4-region-and-weather','p5-training-and-atc','p6-realism-and-failures','p7-windows-release','p8-expansion'];
const link = (key) => `[${key} #${numbers.get(key)}](${base}/issues/${numbers.get(key)})`;
const doc = (file) => `[${file}](${base}/blob/main/${file})`;
const list = (items) => items.map(x => `- ${x}`).join('\n');
const containers = new Set(['REGIONAL-AIRPORTS', 'LESSON-CURRICULUM', 'FAILURE-SYSTEMS']);
const allAdrs = [
  'docs/decisions/001-engine-and-native-stack.md',
  'docs/decisions/002-dynamics-and-timing.md',
  'docs/decisions/003-geodesy-and-render-origin.md',
  'docs/decisions/004-persistence-and-replay.md',
  'docs/decisions/005-content-and-aircraft-expansion.md'
];
const relevantAdrs = {
  planning: allAdrs, core: [allAdrs[0],allAdrs[1],allAdrs[2]], physics: [allAdrs[1],allAdrs[2]],
  aircraft: [allAdrs[1],allAdrs[4]], world: [allAdrs[2],allAdrs[4]], weather: [allAdrs[1],allAdrs[2],allAdrs[4]],
  cockpit: [allAdrs[0],allAdrs[1]], input: [allAdrs[0],allAdrs[1]], audio: [allAdrs[0],allAdrs[1]],
  persistence: [allAdrs[3]], training: [allAdrs[1],allAdrs[3],allAdrs[4]],
  atc: [allAdrs[1],allAdrs[3],allAdrs[4]], ui: [allAdrs[0],allAdrs[3]],
  validation: [allAdrs[1],allAdrs[3]], delivery: [allAdrs[0],allAdrs[4]], security: [allAdrs[3],allAdrs[4]]
};
const domainNotes = {
  planning: 'Coordinate accepted artifacts and phase evidence. Keep shared decisions consistent across the architecture, contracts, roadmap and canonical backlog. A planning statement is not an implemented feature or measured fidelity result.',
  core: 'Own authoritative state, fixed ticks and ordered commands. Presentation consumes immutable snapshots. Keep the core headless and engine-independent; use explicit SI units, tested frames and schema versions. Shared contracts land before their consumers.',
  physics: 'Use one aircraft dynamics/contact authority. Audit JSBSim units, frame transforms, mass/CG, integration and terrain mappings. Distinguish the provisional seed from the target C172S. Compare independent traces and source definitions; cosmetic effects and arbitrary control bias do not establish aerodynamic behavior.',
  aircraft: 'Identify exact airframe/serial applicability, engine, propeller and installed analog equipment before source-specific behavior. The target is fuel-injected C172S; do not copy carburetor procedures or limits from another variant. Systems, sensed indications, faults and checklists must agree causally and carry provenance.',
  world: 'Keep synthetic fixtures distinct from dated real-world packs. Preserve source rights, effective intervals, checksums, coverage, horizontal/vertical datums and magnetic/true conventions. Visual runway geometry, contact surfaces, taxi graphs and operational airport records must agree; validate one real airport at a time.',
  weather: 'Use the same seeded atmosphere and clock for dynamics, instruments, windsocks, traffic and weather presentation. Preserve spatial frames, source/synthetic status and valid times. Offline presets are the default; visual turbulence alone cannot stand in for sampled air motion.',
  cockpit: 'Derive gauges and controls from installed system/sensor contracts, including flags, power and latency. Check eye point, sight picture, instrument markings, scale and interaction at supported views. Record screenshots/readability and representative performance; do not silently substitute perfect truth for a failed sensor.',
  input: 'Map keyboard/mouse/gamepad and calibrated flight devices into the same ordered command interface. Specify multi-device authority, dead zones, reversal, saturation, disconnect/reconnect and saved calibration. Qualify only hardware actually tested; keep accessibility changes separate from hidden flight assistance.',
  audio: 'Drive engine, airflow, warnings and radio cues from simulated state. Record rights for recordings/assets and avoid unlicensed copied sounds. Support separate channels and captions/visual alternatives; validate pause/reset/loop behavior with supported scenarios.',
  persistence: 'Durable state lives in the native-resolved Windows LocalAppData/FlightSimulator directory. Use transactional SQLite writes, a valid backup strategy for WAL, versioned manifests and recoverable migrations. SAVE-PROOF must establish the full-resume guarantee; later consumers must use its accepted result; snapshot playback and physics re-simulation are distinct capabilities.',
  training: 'Use aircraft- and jurisdiction-specific versioned sources/rubrics. Reward justified cancellation, diversion and go-around, and record assists/interventions. Separate knowledge, decisions and handling evidence. Practice is not regulatory flight time; qualified human review is required before claims of instructional mastery.',
  atc: 'Use bounded deterministic communication/clearance state and dated airport capability. Taxi authorization, crossing, takeoff and landing are distinct. Traffic/ATC share clock/weather and persist through verified continuation. Start with text/menu/caption interactions; open-ended generated instructions cannot become safety authority.',
  ui: 'Support readable, navigable keyboard/gamepad/mouse flows and consistent units/identifiers/source dates across briefing, cockpit, map and debrief. Keep assistance and prototype limits visible. Profiles, history and achievements must reflect actual durable evidence, with optional exports and privacy-preserving defaults.',
  validation: 'Separate software correctness, model/reference agreement and qualitative pilot opinion. Report measured versus provisional thresholds, configuration/source versions, uncertainty and unsupported envelope. A hosted CPU check does not qualify RTX3090 graphics, controller feel, VR or human instruction.',
  delivery: 'Pin exact dependencies, ABI/CRT, engine/export-template pairing and rights. Prove the exported Windows package on a clean environment without development PATH/tools. Ship notices, required JSBSim source/replacement obligations and exact manifests. GitHub Releases uses validated assets and draft-then-publish; documentation archives are not game builds.',
  security: 'Treat content/save/replay imports as untrusted bounded data. Reject path traversal, oversized archives, invalid numeric domains and incompatible schemas. Content cannot load arbitrary native code. Preserve originals during failures; local profiles/logs/crash reports stay private unless sharing is explicitly consented and scrubbed.'
};

function render(item) {
  const area = item.labels.find(x => x.startsWith('area:')).slice(5);
  const phase = Number(item.phase.slice(1));
  const phaseFile = `docs/phases/${phaseFiles[phase]}.md`;
  const children = backlog.issues.filter(x => x.parent === item.key);
  const consumers = backlog.issues.filter(x => x.depends_on.includes(item.key));
  const siblings = backlog.issues.filter(x => x.key !== item.key && x.phase === item.phase && x.kind !== 'epic' && !item.depends_on.includes(x.key) && !consumers.includes(x) && x.labels.includes(`area:${area}`));
  const reads = [...new Set([...item.docs, ...(relevantAdrs[area] ?? [])])].filter(x => !['docs/roadmap.md',phaseFile].includes(x));
  let role;
  if (item.key === 'PLAN-REVIEW') role = 'Act as a review-preparation agent. Audit and summarize the plan, prepare concrete revisions and review evidence, and help the owner make the decision. The acceptance decision and authorization to start P1 belong to the human owner. Do not approve or close this ticket on the owner’s behalf and do not begin product implementation as part of it.';
  else if (item.kind === 'epic') role = `Act as the ${item.phase} phase coordinator/integrator. Coordinate the child tickets below, verify their merged artifacts and collect the phase exit evidence. This epic is a gate, not a single request to implement every subsystem in one PR. ${phase === 0 ? 'P0 acceptance requires the owner’s explicit review; do not manufacture that approval.' : 'Close it only after child acceptance and the integrated scenario pass, including applicable human review. If a gate is unmet, keep it open with a named owned blocker.'}`;
  else if (containers.has(item.key)) role = 'Act as a work-package coordinator. Confirm and reuse the accepted prerequisite interface/schema; coordinate any missing contract or necessary change with its owner and land that before consumers. Then create linked bounded leaf issues with disjoint ownership for each airport, lesson family or failure family. Reference this parent and carry its requirements/evidence into those leaves. Integrate their accepted results; avoid one oversized PR or multiple agents editing the whole content tree.';
  else if (item.kind === 'spike') role = 'Act as the owner of a bounded technical proof. Deliver a runnable minimal experiment, reproducible measurements and a source-supported pass/fail/uncertainty decision. Record the selected interface/fallback in the relevant ADR. A prototype that merely launches does not prove the issue’s acceptance, and a failed proof must remain an explicit architecture decision/blocker.';
  else role = 'Act as the implementation owner for this one task. Deliver the smallest complete, reviewable change that meets all acceptance criteria, with meaningful tests and evidence. Continue through the checked PR and permitted merge when prerequisites and review requirements are satisfied.';

  const sections = [
    `<!-- flight-sim-agent-prompt:${item.key}:v1 -->\n# Copyable agent assignment — ${item.key} / #${numbers.get(item.key)}\n\nThis is a reusable dispatch prompt. Paste this comment into an agent with repository/GitHub access. Read the live issue and latest main before acting; this prompt is context, while current repository instructions, scope and accepted evidence govern the work.`,
    `## Your assignment\n\nRepository: ${base}\n\nTicket: ${link(item.key)} — **${item.title}**\n\nPhase: **${item.phase}**. Area: **${area}**. Work type: **${item.kind}**.\n\n${item.summary}\n\n${role}`,
    '## Understand the overall project\n\nWe are building a serious standalone Windows 11 x64 flight simulator for a new pilot’s practice and an experienced Cessna pilot’s enjoyment. The reference PC is an i9-12900K, RTX3090 and approximately 64 GB RAM. The first target is one explicitly evidenced fuel-injected, conventional-panel C172S configuration, expandable through aircraft capabilities. Synthetic fixtures come first, followed by dated north Puget Sound packs (KAWO, KPAE, KBFI). US/FAA lessons are the first jurisdiction pack; the user’s licensing jurisdiction remains undecided.\n\nThe owner selected account-free Godot authoring via direct downloads. Planned stack: Godot Forward+ and typed GDScript presentation, independent C++20/JSBSim dynamics, SQLite local persistence and Python offline data tooling. Native integration, engine pins, aircraft references and exact save reconstruction require proof. Keep Unreal migration behind explicit owner acceptance of its account requirement. Offline flying, readable cockpit, complete planning-to-shutdown operations and honest debrief/progress matter. VR, new aircraft and networking follow base acceptance; do not add them to an unrelated ticket.',
    `## Traverse the documents\n\n1. Read ${doc('AGENTS.md')} and ${doc('docs/README.md')} for scope and invariants.\n2. Read ${doc('docs/roadmap.md')} and your ${doc(phaseFile)} for outcome, sequencing and exit evidence.\n3. Read ${doc('docs/contracts.md')} for units/frames, clock, ownership, content/session versions and boundary fixtures.\n4. Read the task-specific specifications/decisions below, then ${doc('docs/requirements.md')} to find your requirement definitions and other implementing tickets:\n\n${list(reads.map(doc))}\n\n5. Read ${doc('docs/agent-operations.md')}, ${doc('CONTRIBUTING.md')}, ${doc('docs/delivery.md')} and ${doc('.github/PULL_REQUEST_TEMPLATE.md')} for branch, review, evidence and release rules. Check ${doc('docs/sources.md')} and ${doc('docs/risks.md')} wherever source rights, aircraft evidence or a proof decision matters.`,
    `## Establish readiness and recover prior work\n\n${item.parent ? `Parent phase tracker: ${link(item.parent)}. This parent rolls up the task; its closure is not an extra blocking prerequisite. The explicit dependencies below determine readiness.\n\n` : ''}Blocking prerequisites:\n\n${item.depends_on.length ? list(item.depends_on.map(key => `${link(key)} — ${byKey.get(key).title}`)) : 'No earlier implementation dependency. This issue still respects its human review/phase acceptance scope.'}\n\nRead ${link('PLAN-REVIEW')} and ${link('EPIC-P0')} before any product implementation. Their live acceptance/authorization evidence must be satisfied; merged planning PRs do not supply that approval. Dependency checkboxes and status labels are hints: inspect prerequisite issue comments, linked PRs, merge commits, fixtures and gate reports on main. Do not satisfy a dependency by closing it yourself or inventing missing evidence. If blocked, name the missing prerequisite and resolution condition; continue only independent research/review permitted by the phase.\n\nRecover implementation context from the issue timeline and linked merged PRs, ${doc('docs/issue-index.md')}, ${doc('docs/backlog.json')}, ${doc('docs/requirements.md')}, relevant ADRs, tests and existing code. Foundation [PR #77](${base}/pull/77) and account-free engine decision [PR #80](${base}/pull/80) are historical context; latest main is authoritative. The documentation release is a planning snapshot, not a runnable simulator. Use git log/blame on owned modules and inspect actual build/schema manifests instead of assuming the original proposed paths already exist.`,
    `## Scope and coordination\n\nOwned paths for this packet:\n\n${list(item.owned_paths.map(x => `\`${x}\``))}\n\nRequirement IDs: ${item.requirements.length ? item.requirements.map(x=>`\`${x}\``).join(', ') : 'The phase exit criteria and child requirements in the roadmap govern this coordinator ticket'}.\n\nCoordinate shared schemas/build files/core scenes with their current owner before edits. Use accepted versioned mocks/fixtures when they exist. Land interface changes before consumers; an aircraft, frame, schema, engine or rights change needs the appropriate ADR/contract review. Never broadly reformat unrelated modules or commit another agent’s work.\n\nDomain focus: ${domainNotes[area]}`,
    `## Acceptance — provide observable evidence for every item\n\n${list(item.acceptance.map(x=>`[ ] ${x}`))}\n\nRequired closure artifacts:\n\n${list(item.evidence)}`,
  ];
  if (children.length) sections.push(`## Child work to coordinate\n\n${list(children.map(x=>`${link(x.key)} — ${x.title}`))}\n\nRead each child’s latest scope, comments and evidence. Assign bounded leaf ownership and integrate contracts before consumers; this prompt does not authorize uncontrolled parallel changes.`);
  sections.push(`## Implement, verify and merge\n\n1. Confirm the live issue is still unclaimed/open, read repository status and update from main without discarding others’ changes. Use an isolated managed worktree when available for concurrent work and a branch such as \`codex/${item.key.toLowerCase()}\`. Claim with a concise issue comment naming branch, owned scope, dependencies and evidence plan; use \`status:in-progress\` when actually implementing.\n2. Inspect existing code, fixtures and commands. Implement only this packet’s accepted scope; create linked leaf/follow-up issues for genuinely separate work. Preserve fixed-step physics, source/evidence status, offline behavior, assistance provenance and local privacy. Do not purchase assets/services, create vendor accounts, redistribute restricted documents or claim certified training credit as a routine task.\n3. Verify with the checks appropriate to this task and the acceptance above. Always run \`node tools/check-docs.mjs\` for touched planning documents/backlog. After roadmap/requirements/backlog edits, run \`node tools/render-plan.mjs\` before checking. Discover actual native CMake/CTest presets, Godot import/export checks and scenario/benchmark tools from main; add needed meaningful checks as the assigned phase requires. Do not invent a passing game build while only documentation checks exist. Record Windows exported behavior, trace/source comparisons, screenshots, migration tests or actual pilot observations when applicable. Required domain/human review remains separate from green CI.\n4. Inspect the final diff and whitespace, then commit the owned changes. The owner authorized per-command bypass of interactive GPG signing: \`git -c commit.gpgsign=false commit\`; do not alter global signing settings. Open a focused PR using the repository template, name this issue/phase/requirements, explain the resulting behavior and include actual evidence, source versions and remaining limits. Attach the PR to the agent’s Codex task if that tool is available. Use the authenticated GitHub CLI or connector; keep tokens out of logs.\n5. Update/rebase against current main if necessary, rerun affected checks and resolve review/contract conflicts. The owner’s standing project authorization covers task PR creation and merge once gates and reviews are satisfied. Squash merge through GitHub after required current checks succeed (currently \`docs (ubuntu-24.04)\` and \`docs (windows-2022)\`; honor any checks added since), conversations are resolved and applicable domain evidence is accepted. Never bypass branch protections, force-push main, or treat self-authored evidence as human pilot/owner approval.\n6. Close an implementation ticket only when merged acceptance is complete. ${item.key === 'PLAN-REVIEW' || item.key === 'EPIC-P0' ? `Use \`Refs #${numbers.get(item.key)}\` and leave this human acceptance gate open for the owner; never auto-close it.` : item.kind === 'epic' || containers.has(item.key) ? `Use \`Refs #${numbers.get(item.key)}\` while coordinating; close only after all child and gate evidence is accepted.` : `Use \`Closes #${numbers.get(item.key)}\` only when merged acceptance and required reviews are complete; partial work remains open.`} Move to \`status:needs-review\` while review is pending; preserve an explicit blocked state if required evidence is unavailable. Leave a completion comment linking the PR, merge SHA, checks, evidence, schema/content/source changes, limitations and downstream handoff. Update dependent queue status only after verifying live gates. Do not publish a release unless this issue explicitly owns that delivery.`,
    `## Future work and handoff\n\nDirect downstream tickets consuming this outcome:\n\n${consumers.length ? list(consumers.map(x=>`${link(x.key)} — ${x.title}`)) : 'No direct consumer is listed in the initial backlog; hand the evidence to the parent/phase integrator and link any newly created leaf or follow-up work.'}\n\n${siblings.length ? `Other same-area work in this phase: ${siblings.map(x=>link(x.key)).join(', ')}. Coordinate overlapping paths; shared area does not make another ticket part of your assignment.\n\n` : ''}Use the parent epic’s child list and ${doc('docs/issue-index.md')} for prior/future phase work. Mention the exact accepted fixture/API/schema versions downstream agents should consume and any migration or known limitation. Scope changes belong in the canonical backlog/docs through a reviewed PR; issue bodies and generated prompts are maintained separately. Put working notes/evidence in new comments rather than editing this generated assignment.`,
    '## Final report to the dispatcher\n\nReport: resulting behavior and requirements met; PR URL and merge SHA (or explicit pending blocker); checks and evidence with actual results; configuration/source/schema versions; unresolved limits and their issues; and the next consumer/gate. Stop short of claiming a playable feature, calibrated aircraft, exact resume, completed phase or instructional approval without its evidence.'
  );
  return sections.join('\n\n') + '\n';
}

const prompts = new Map(backlog.issues.map(item => [item.key, render(item)]));
fs.mkdirSync('.local/agent-prompts', { recursive: true });
for (const [key, body] of prompts) {
  if (body.length > 60000) throw new Error(`Prompt too long: ${key}`);
  for (const match of body.matchAll(/https:\/\/github\.com\/brettbergin\/flight-simulator\/blob\/main\/([^\s)]+)/g)) {
    if (!fs.existsSync(match[1])) throw new Error(`Missing document in ${key}: ${match[1]}`);
  }
  fs.writeFileSync(`.local/agent-prompts/${key}.md`, body);
}
if (!apply && !verify) {
  console.log(`Rendered ${prompts.size} tailored agent prompts; no GitHub requests or mutations.`);
  console.log('Inspect .local/agent-prompts/*.md. Publish with --apply; audit live comments with --verify.');
  process.exit(0);
}
execFileSync(process.execPath, ['tools/check-docs.mjs'], { stdio: 'inherit' });
function api(endpoint, method='GET', payload) {
  const argv = ['api', endpoint, '--method', method];
  if (payload) argv.push('--input', '-');
  return JSON.parse(execFileSync('gh',argv,{ input: payload ? JSON.stringify(payload) : undefined, encoding:'utf8', maxBuffer:30*1024*1024 }));
}
function paged(endpoint) {
  return JSON.parse(execFileSync('gh',['api',endpoint,'--paginate','--slurp'],{encoding:'utf8',maxBuffer:40*1024*1024})).flat();
}
const issues = paged(`repos/${repo}/issues?state=all&per_page=100`).filter(x=>!x.pull_request);
const comments = paged(`repos/${repo}/issues/comments?per_page=100`);
const login = apply ? api('user').login : undefined;
const matched = new Map();
// All targets and ownership are checked before any write. Live issue state is preserved.
for (const item of backlog.issues) {
  const issue = issues.find(x=>x.number===numbers.get(item.key));
  if (!issue?.body?.includes(`<!-- flight-sim-backlog:${item.key} -->`)) throw new Error(`Live issue mismatch: ${item.key}`);
  const prefix = `<!-- flight-sim-agent-prompt:${item.key}:`;
  const existing = comments.filter(x=>x.body?.trimStart().startsWith(prefix));
  if (existing.length > 1 || existing.some(x=>x.issue_url !== `https://api.github.com/repos/${repo}/issues/${issue.number}`)) throw new Error(`Duplicate/misplaced prompt: ${item.key}`);
  if (apply && existing.length && existing[0].user.login !== login) throw new Error(`Prompt owned by another account: ${item.key}`);
  matched.set(item.key, existing[0]);
}
const report = [];
for (const item of backlog.issues) {
  const number = numbers.get(item.key);
  const body = prompts.get(item.key);
  let comment = matched.get(item.key);
  if (apply && !comment) {
    comment = api(`repos/${repo}/issues/${number}/comments`, 'POST', {body});
    console.log(`Created agent prompt ${item.key}: #${number}`);
  } else if (apply && comment.body.replaceAll('\r\n','\n') !== body) {
    comment = api(`repos/${repo}/issues/comments/${comment.id}`, 'PATCH', {body});
    console.log(`Updated agent prompt ${item.key}: #${number}`);
  }
  const exact = !!comment && comment.body.replaceAll('\r\n','\n') === body;
  report.push({key:item.key,issue:number,comment_id:comment?.id,url:comment?.html_url,exact});
  // Recovery uses remote markers; this atomic report is optional local audit evidence.
  fs.writeFileSync('.local/agent-prompt-report.json.tmp',JSON.stringify(report,null,2)+'\n');
  fs.renameSync('.local/agent-prompt-report.json.tmp','.local/agent-prompt-report.json');
}
const missing = report.filter(x=>!x.exact);
if (missing.length) {
  console.error(`Missing/stale prompts: ${missing.map(x=>x.key).join(', ')}`);
  process.exitCode=1;
} else console.log(`${apply?'Published':'Verified'} exactly one current prompt on each of ${report.length} planned issues. Issue bodies, labels, states, assignees and other comments were preserved.`);
