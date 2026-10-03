# Agent instructions

This repository is a Windows-first flight simulator. Start with [docs/README.md](docs/README.md), the relevant phase in [docs/roadmap.md](docs/roadmap.md), and your assigned GitHub issue.

## Current scope

The owner approved the plan and authorized the implementation fleet on 2026-10-03. See [P0 acceptance evidence](docs/evidence/P0/acceptance.md). Implement through the issue dependency graph and phase gates. Do not interpret a merged documentation PR as aircraft validation or acceptance of later phases.

## Working rules

- Use the issue's acceptance criteria, dependencies, phase, and owned paths. Read [docs/agent-operations.md](docs/agent-operations.md) before coordinating multiple agents.
- Use branches prefixed `codex/`. One issue or cohesive dependency group per PR. Never force-push main.
- Shared interfaces, coordinate conventions, schema versions, dependency pins, and aircraft definitions need a contract PR before consumers implement them. Independent modules can proceed in parallel after those contracts land.
- Simulation owns authoritative aircraft state. Rendering, training overlays, achievements, and UI must not silently modify physics or hide assists.
- Keep provenance for aircraft parameters, procedures, geographic data, assets, licenses, and test references. Prototype data must be visibly marked as such. Never mix variant limits or claim fidelity from subjective impressions alone.
- Keep core tests headless, offline, and independent of frame rate. Keep real airport operational data separate from synthetic fixtures.
- Use explicit SI units and documented frames at module boundaries. Reject invalid states and incompatible content versions.
- Update documentation and requirement-to-issue mapping when scope changes. Report evidence and remaining limits in PRs.
- Run `node tools/check-docs.mjs` for documentation/foundation changes. For native work, use [the pinned bootstrap](tools/bootstrap/README.md) and CTest; contract changes also require `npm --prefix schemas run check` and `node --test tests/contracts/schema.test.mjs`. Run checks appropriate to the changed module and retain phase-specific evidence.
- Do not spend money, provision paid infrastructure, redistribute restricted source material, or publish aviation training-credit claims without explicit owner authorization.
- Never log credentials or upload local pilot profiles, flight logs, or crash dumps by default.

## Reviews and completion

CI passing is necessary, but physics realism, licensed content, and pilot evaluation have separate evidence gates. Do not close an epic until its child work and documented exit evidence are complete. The owner decides the project review gate; contributors may prepare all evidence first.
