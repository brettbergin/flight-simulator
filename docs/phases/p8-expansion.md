# P8 — Validated expansion

Generated from [roadmap](../roadmap.md) and [backlog](../backlog.json). Consult the [issue index](../issue-index.md) for actual GitHub links.

**Outcome:** expand a proven simulator in response to user/pilot feedback without destabilizing validated experiences.

**Candidate programs:** additional C172 configurations; other aircraft architectures; new reviewed regions; fuller traffic/ATC; optional current weather ingestion; multi-monitor/hardware panels/head tracking; VR; shared cockpit/instructor mode; richer instrument/weather training; additional jurisdictions; community content tools; installer/code-signing improvements.

**Prerequisites:** P7 stable release, versioned packages, evidence of the need, a source/rights plan, and an ADR describing new assumptions. VR, multiplayer, worldwide scenery, and formal training-device qualification each require their own scope, budget, and validation plan.

**Parallel lanes:** self-contained expansion packages after central contracts are reviewed. Backward compatibility, save provenance, existing lesson expectations, and original aircraft regression are mandatory integration concerns.

**Exit evidence:** program-specific acceptance, compatibility tests, performance impact, pilot review, and release limitations. There is no universal “everything is realistic” completion gate.

## Dispatch queue

| Task | Area | Dependencies | Owned paths |
|---|---|---|---|
| [AIRCRAFT-EXPANSION](https://github.com/brettbergin/flight-simulator/issues/70) — Add a second validated Cessna through capabilities and package contracts | aircraft | EPIC-P7 | `content/aircraft/`, `native/sim_core/capabilities/`, `tests/reference/` |
| [VR-EXPANSION](https://github.com/brettbergin/flight-simulator/issues/71) — Evaluate and implement VR after desktop readability/performance acceptance | cockpit | EPIC-P7 | `app/vr/`, `tests/vr/`, `docs/decisions/` |
| [REGION-LIVE-DATA](https://github.com/brettbergin/flight-simulator/issues/72) — Evaluate new regions and optional live weather/navdata adapters | world | EPIC-P7 | `tools/ingest/`, `content/world/`, `native/adapters/` |
| [INSTRUCTOR-NETWORK](https://github.com/brettbergin/flight-simulator/issues/73) — Evaluate instructor networking and cooperative multiplayer architecture | core | EPIC-P7 | `native/network/`, `app/ui/network/`, `docs/decisions/` |

## Agent handoff

Use the canonical issue acceptance/evidence fields. Claim one task with an isolated branch/worktree; coordinate shared paths before editing. Publish interface changes first, then consumers. Record build/content/source versions, test outputs, unresolved gaps and human-review status in the PR. Prepare `docs/evidence/P8/` gate report only after the integrated scenario is actually run. The integrator changes dependency status labels; agents do not self-certify human pilot or owner review.
