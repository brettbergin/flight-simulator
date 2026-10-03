# P0 — Reviewable foundations

Generated from [roadmap](../roadmap.md) and [backlog](../backlog.json). Consult the [issue index](../issue-index.md) for actual GitHub links.

**Outcome:** owner and agents have a coherent plan, usable issue backlog, and clear limits before code work begins.

**Deliverables:** product/experience specifications; architecture and ADRs; aviation evidence and fidelity matrix; phase briefs; risk register; issue labels, milestone/backlog structure, dependency mapping; agent rules; CI and GitHub Releases policy. Record aircraft target, prototype surrogate distinction, source rights, reference region, hardware assumptions, and open decisions.

**Prerequisites:** repository access and high-level user intent. Original code remains MIT; aircraft data/assets/dependencies need separate licensing evidence.

**Parallel lanes:** product/UX, simulation architecture, aviation/source review, and repository/release governance. Root integrates decisions and issues.

**Exit evidence:** documentation links resolve; all first-phase issues have requirements, ownership, dependencies, and testable acceptance; architecture choices and source uncertainties agree across documents; owner can identify the first complete playable outcome and the next implementation task. The owner review is an explicit boundary requested by the user.

**Gate failures:** conflicting aircraft assumptions, unlicensed indispensable sources, unclear numeric units/frames, or a backlog that requires all agents to edit the same core files. Resolve through ADR/content scope changes before implementation.

**Primary requirements:** PRD-001, PRD-026, PRD-032, PRD-034.

## Dispatch queue

| Task | Area | Dependencies | Owned paths |
|---|---|---|---|
| [PLAN-REVIEW](https://github.com/brettbergin/flight-simulator/issues/10) — Owner review of architecture, aircraft target, scope, and phased delivery | planning | Owner review | `docs/`, `docs/backlog.json` |

## Agent handoff

Use the canonical issue acceptance/evidence fields. Claim one task with an isolated branch/worktree; coordinate shared paths before editing. Publish interface changes first, then consumers. Record build/content/source versions, test outputs, unresolved gaps and human-review status in the PR. Prepare `docs/evidence/P0/` gate report only after the integrated scenario is actually run. The integrator changes dependency status labels; agents do not self-certify human pilot or owner review.
