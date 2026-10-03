# GitHub backlog

The canonical planned work is [backlog.json](backlog.json). [Issue index](issue-index.md) maps stable keys to created GitHub issues. Milestones P0-P8 match [the gated roadmap](roadmap.md). The owner reviews the foundation before implementation; only that review task starts ready.

## Preview and publication

```powershell
node tools/check-docs.mjs
node tools/sync-github.mjs
# Explicit mutation of labels, milestones, and planned issues:
node tools/sync-github.mjs --apply
```

Requires Node 20+ and an authenticated GitHub CLI for apply. No dependencies or shell interpolation are used by the publication tool. CI only runs preview. Repository identity is fixed in the checked-in manifest. Apply creates missing planned labels/milestones/issues, discovers existing issues by an embedded stable-key marker, and uses a second pass to add real issue-number dependency and parent/child links. It preserves existing issue state and labels, and updates bodies only when explicitly applied. It does not close issues, assign users, auto-claim work, or publish releases.

After changing the requirement documents, roadmap, or JSON, run `node tools/render-plan.mjs` to refresh the traceability matrix and nine per-phase dispatch briefs before validation. `REGIONAL-AIRPORTS`, `LESSON-CURRICULUM`, and `FAILURE-SYSTEMS` are explicitly coordinator-owned work packages; their acceptance requires bounded leaf issues after shared schemas land. This keeps the initial backlog useful without inventing final leaf details before their contracts exist.

An ignored `.local/github-sync.json` ledger is atomically replaced after each successful mutation. A malformed ledger is preserved under a quarantine filename and recovered through remote stable markers. After interruption, rerun with identical backlog and let discovery recover created issues; never blindly duplicate a partially published backlog. If stable-key titles/markers conflict or GitHub access fails, investigate before proceeding. Manual issue scope edits should be reflected in the JSON before applying again because generated bodies are authoritative for planned fields. Unchanged completed checkboxes are preserved; put working notes and closure evidence in issue comments or linked reports rather than appending them to generated bodies.

## Picking work

Every task names its parent phase, area, priority, dependency keys, owned paths, requirements/documents, observable acceptance criteria, and closure evidence. Claim a task only after its dependencies and preceding phase gate close. The phase epic body links all child tasks; task bodies link their parent and prerequisites. An issue task list makes progress visible, but closing a checkbox is not independent validation evidence.

Start with plan review, then P1 contract/toolchain/dynamics proof work. Parallel leaf work becomes useful after module contracts land. P8 is deliberately deferred expansion; it is not part of the initial realistic Cessna acceptance promise.

`priority:P0` means a prerequisite or critical correctness gate, not a fabricated deadline. `P1` is normal current-phase work and `P2` is deferred expansion. Keep status labels accurate as dependency states change; publication does not automatically recalculate the live queue.
