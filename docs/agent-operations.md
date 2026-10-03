# Agent fleet operations

Status: proposed execution protocol. Documentation and issues are the authorized work now. Game implementation starts after the owner's review of this plan.

## Execution model

Use an asymmetric fleet: one coordinator/integrator, a small set of contract owners, and multiple independent leaf agents. Contract owners resolve authoritative simulation state, time/units/coordinates, content manifests, save schemas, and event/evaluator interfaces in sequence. Leaf agents build cockpit displays, source packages, test fixtures, lesson data, audio cues, UI flows, and airport packages against those accepted contracts.

The coordinator owns phase gates, issue dependency readiness, assignment, cross-document consistency, integration order, release scope, and evidence. The simulation owner owns physical state and model boundaries. The content/aviation owner owns source provenance, aircraft identity, procedure review status, and declared fidelity. The persistence/event owner owns schema compatibility and evaluator provenance. The delivery owner owns build/package contracts, workflows, and artifact manifests. One contributor may serve several roles at low fleet sizes; authority remains explicit.

An agent can implement and review another agent's work, but cannot substitute for a qualified human reviewer or erase unresolved source/fidelity uncertainty. The user's father provides valuable qualitative assessment if he chooses to participate; a jurisdictional teaching claim needs the appropriate qualified review.

## Repository and worktree discipline

1. Read repository-level instructions, the assigned issue, its phase brief, and relevant ADR/source contracts before editing.
2. Confirm dependency issues have accepted artifacts and interfaces. A branch merely containing proposed code does not establish an accepted contract.
3. Assign one issue owner and list owned files/directories. Each simultaneous implementation agent uses an isolated managed worktree and a `codex/` branch unless repository instructions say otherwise.
4. Agents in a shared checkout must have disjoint ownership. They cannot commit another agent's work or broadly format common directories. Shared schemas, build files, manifests, and central interfaces have one owner at a time.
5. Build against a published fixture/mock adapter when dependencies are stable but not integrated. Do not invent a private incompatible version of a shared contract.
6. Keep each PR focused on its acceptance criteria. Refactoring unrelated interfaces requires a follow-up issue/ADR rather than surprise scope growth.
7. Preserve evidence and attach the created PR to the current Codex task using the available artifact tool. Clean up managed worktrees only after needed files/evidence are preserved and integration is verified.

The user has authorized creating and merging PRs and bypassing interactive GPG signing. Use a per-command signing override such as `git -c commit.gpgsign=false commit` when needed. Do not change global Git settings. Merge only after required checks, review of the final diff, and dependency/phase criteria hold; unresolved owner-input boundaries remain visible.

## Issue readiness and status

The repository delivery policy defines the exact label names. Apply its canonical labels rather than inventing near-duplicates. Every issue needs one work type, one main area, one phase, one priority, and one current status where that policy provides those categories. Source/fidelity/human-review risks are additional explicit metadata.

| State | Meaning | Evidence to move forward |
|---|---|---|
| Backlog | Known work with unresolved detail/dependency | Defined acceptance, scope, owner area, and phase |
| Ready | All prerequisite decisions/artifacts available | Dependency links, requirements, owned paths, test plan |
| In progress | One agent is actively responsible | Branch/worktree and concise progress/risk note |
| Blocked | A named external fact, contract, source, or human input prevents progress | Blocker owner and resolution condition; continue independent work where useful |
| Review | Concrete PR and evidence available | Tests, source provenance, final diff, screenshots/replays as relevant |
| Done | Merged and acceptance met | PR link plus evidence; gate record updated where relevant |

A documentation proposal can be merged with decisions explicitly marked proposed. A fidelity implementation issue cannot close simply because documentation says what it should do. A blocked source issue may force a scoped fallback ADR; it cannot be resolved by guessing an aircraft parameter or copying a source with unknown rights.

## Assignment packet

```text
Issue / phase / requirement IDs:
Outcome and acceptance criteria:
Prerequisite issues, ADRs, and fixture versions:
Branch / worktree:
Owned files and files requiring coordination:
Sources, rights, and reviewer requirements:
Contracts consumed or proposed for change:
Verification commands and evidence outputs:
Included scope / explicitly deferred scope:
Expected handoff to the next owner:
```

Agents acknowledge conflicts before editing. A coordinator may split a large issue into implementation and independent evidence work, but accepts their joint outcome only after integration. Labels and issue descriptions remain the canonical record; transient chat messages do not replace them.

Broad airport, curriculum, and failure-family work packages are coordination containers. Before implementation agents claim them, the coordinator creates bounded leaf issues with separate owned paths, sources, prerequisites, and evidence—for example one airport pack, one lesson family, or one failure family. The parent closes only after its leaf evidence and integrated acceptance are reviewed. A broad package does not authorize one agent to modify every child module in parallel.

## Safe parallelism by phase

| Phase | Sequential spine | Independent leaf work after contract readiness |
|---|---|---|
| P0 | Aircraft identity, core architecture, scope decisions | Source research, experience specification, backlog/CI design |
| P1 | State/tick/frames/contact authority, native boundary | Numerical fixtures, Windows package spike, source rights |
| P2 | Input and cockpit state adapter | Instruments, camera, audio, synthetic airfield, readability QA |
| P3 | Systems dependencies and save/event schemas | Checklist UI/data, planner, profile UI, circuit evaluator, recovery fixtures |
| P4 | Datum, map/environment/region manifest | Airport packages, scenery preparation, weather visuals, route lessons |
| P5 | ATC authority, evaluator/event contracts | Lesson families, debrief panels, captions, achievement definitions |
| P6 | Failure state/system cause relationships | Individual reviewed failures, indications/audio, evidence fixtures |
| P7 | Version freeze and release integration | Regression scenarios, clean-user checks, accessibility/performance review |
| P8 | Each expansion's ADR and compatibility plan | Self-contained aircraft/region/hardware/content packages |

Concurrency is earned by stable interfaces. More agents on a shared file create coordination work. Prefer a small integration spine and many bounded source/content/evidence tasks over a fleet making simultaneous architecture changes.

## PR review and integration

The PR description leads with the user's resulting behavior and cites the issue/requirement IDs. Include configuration/source versions, meaningful validation, known limitations, compatibility consequences, and representative evidence. All generated prose or content must be reviewed for invented facts and accidentally unsupported claims.

Reviewer checks depend on the work:

- Simulation changes: numerical assumptions, units/frames, causal behavior, repeatable fixtures, contact authority, envelope/regression evidence.
- Cockpit/UX: actual state semantics, legibility, accessible input, camera behavior, screenshots or captured scenarios, assistance provenance.
- Content: exact aircraft/jurisdiction/configuration, dated primary sources, redistribution terms, human review status, no fabricated authority.
- Persistence/evaluation: atomicity, corruption/migration recovery, compatible resume, honest provenance, idempotency, bounded measurable rules.
- Delivery: exported runtime/native DLL loading, locked versions, permissions, artifact/licenses/checksums, offline startup, release notes.

Integrate contract PRs before dependents. Rebase or update leaf branches against accepted changes and rerun affected checks. Do not auto-merge a stale green branch after its contracts changed. Conflicts in physics/schemas/content provenance require semantic review, not a blind choice of one side.

After merge, update issue state and dependency readiness, attach evidence, and note phase acceptance. Only a successful integrated scenario advances the gate. A failing gate opens owned defects or revises explicit scope; it does not reset unrelated completed work.

## Evidence and reporting

Reports use a small, factual structure: outcome completed; requirements addressed; checks and evidence; outstanding risk; next dependency. Avoid repeated unchanged status notifications. Blockers name their condition and owner. Distinguish an engineering hypothesis, a sourced fact, a simulation measurement, and a pilot opinion.

Maintain evidence tied to build/model/content versions, scenario seed/configuration, hardware, and input/assistance profile. Large binary captures belong in release/test artifact storage referenced by the issue, not ordinary source history unless an accepted repository policy requires fixtures there. Logs must avoid exposing local private paths or other personal data in public artifacts.

## Changes to the plan

An ADR is required when a change affects engine/model integration, aircraft identity, physics/contact authority, units/frames, persistent schema policy, region/data rights, support platforms, or release qualification claims. It records the problem, evidence, choices, decision, consequences, migration impact, and affected requirements/issues.

Routine reversible UI/content choices within accepted scope can proceed without owner confirmation. Budget commitments, new licensing obligations, formal training-device approval, or changes that contradict the owner's outcome need an explicit decision. The user asked to review the docs/issues before implementation; that boundary remains in force even though PR creation/merging is authorized.
