# P6 — Advanced realism and failures

Generated from [roadmap](../roadmap.md) and [backlog](../backlog.json). Consult the [issue index](../issue-index.md) for actual GitHub links.

**Outcome:** abnormal conditions arise from modeled causes and produce credible indications and decisions within a documented envelope.

**Deliverables:** higher-confidence handling calibration; engine/fuel/electrical/sensor detail justified by source evidence; failure framework; selected engine/power/electrical/pitot-static scenarios; failure-specific checklists/recovery envelopes; appropriate weather limitations and effects; richer ground/runway conditions where validated; instrument-navigation familiarization when installed equipment and jurisdictional sources support it.

**Prerequisites:** P5 evaluation and event contracts; aircraft operating/reference rights; P3 normal-flight quantitative baseline and normal systems/indications validated before related failures. P6 expands calibration across supported mass, CG, atmosphere, configurations, and maneuvers; it does not postpone all normal-flight comparison until this phase. Complex icing, spins, and structural damage are separate evidence gates, not assumed consequences of adding an effects system.

**Parallel lanes:** individual system/failure packages; handling-validation fixtures; cockpit indicators/audio; reviewed lesson data; regression/performance. Shared system dependencies and damage authority remain sequential.

**Exit evidence:** each shipped failure has trigger, cause, indications, physical effect, source, procedure, recovery scope, and tests; normal flight regression holds; quantitative envelope/tolerances recorded; pilot reviews a bounded failure session; exclusions appear in application and release notes. Visual/audio effects correspond to actual state.

**Gate failures:** failure represented only by animation, incorrect common-mode interactions, unsourced exact emergency procedure, plausible-looking stall/spin/icing claims without evidence, or excessive confidence in emergency scoring.

**Primary requirements:** PRD-001–007, PRD-021–026; UX-023–026.

## Dispatch queue

| Task | Area | Dependencies | Owned paths |
|---|---|---|---|
| [FDM-CALIBRATION](https://github.com/brettbergin/flight-simulator/issues/55) — Calibrate C172S performance across mass, CG and atmosphere | physics | EPIC-P5, AIRCRAFT-EVIDENCE, VALIDATION-CORPUS, BASELINE-PERFORMANCE | `content/aircraft/c172s/fdm/`, `tests/reference/c172s/`, `tools/validation/` |
| [STALL-HANDLING](https://github.com/brettbergin/flight-simulator/issues/56) — Validate stalls, coordination, ground effect and crosswind response | physics | EPIC-P5, FDM-CALIBRATION, GUSTS-TURBULENCE | `tests/maneuvers/`, `content/aircraft/c172s/fdm/`, `docs/evidence/handling/` |
| [FAILURE-SYSTEMS](https://github.com/brettbergin/flight-simulator/issues/57) — Implement causal engine, electrical, fuel and instrument failures | aircraft | EPIC-P5, ENGINE-FUEL, ELECTRICAL-SENSORS, ATC-RADIO | `native/sim_core/failures/`, `content/failures/c172s/`, `tests/failures/` |
| [DAMAGE-LIMITS](https://github.com/brettbergin/flight-simulator/issues/58) — Implement bounded structural/engine limits and inspectable consequences | aircraft | EPIC-P5, AIRCRAFT-EVIDENCE, FDM-CALIBRATION | `native/sim_core/damage/`, `content/aircraft/c172s/limits/`, `tests/damage/` |
| [EMERGENCY-LESSONS](https://github.com/brettbergin/flight-simulator/issues/59) — Create reviewed emergency decision and landing practice | training | EPIC-P5, FAILURE-SYSTEMS, DAMAGE-LIMITS, STALL-HANDLING, INSTRUCTOR-TOOLS | `content/lessons/emergency/`, `tests/scenarios/emergency/`, `docs/lesson-review/` |
| [REALISM-REPORT](https://github.com/brettbergin/flight-simulator/issues/60) — Publish full configuration, envelope, source and pilot validation report | validation | EPIC-P5, FDM-CALIBRATION, STALL-HANDLING, FAILURE-SYSTEMS, DAMAGE-LIMITS, EMERGENCY-LESSONS | `docs/evidence/P6/`, `tools/validation/report/` |

## Agent handoff

Use the canonical issue acceptance/evidence fields. Claim one task with an isolated branch/worktree; coordinate shared paths before editing. Publish interface changes first, then consumers. Record build/content/source versions, test outputs, unresolved gaps and human-review status in the PR. Prepare `docs/evidence/P6/` gate report only after the integrated scenario is actually run. The integrator changes dependency status labels; agents do not self-certify human pilot or owner review.
