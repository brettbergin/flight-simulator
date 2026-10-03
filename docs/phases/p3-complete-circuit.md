# P3 — Complete circuit and durable progress

Generated from [roadmap](../roadmap.md) and [backlog](../backlog.json). Consult the [issue index](../issue-index.md) for actual GitHub links.

**Outcome:** father and student can each complete and review a full normal flight in a defined aircraft configuration.

**Deliverables:** aircraft source/configuration decision; validated basic systems; initial quantitative normal-flight performance baseline; loading/fuel planner; inspection representation; cold-and-dark/start/run-up/after-landing/shutdown flows; checklist provenance; complete synthetic circuit and go-around; separate profiles and session UI; atomic save/restore and migrations; practice log; event debrief/basic map replay; offline session; packaged release candidate suitable for pilot feedback.

**Prerequisites:** P2 cockpit/input/contact acceptance; aircraft source rights and target-versus-fallback ADR decision. A surrogate may continue for engineering experiments, but product acceptance identifies its actual configuration.

**Parallel lanes:** aircraft systems; planner/checklists; profile/session UI; persistence/replay; basic debrief; normal-flight numerical baseline; circuit scenario; cockpit/audio completion. Root owns shared state/schema evolution. Schema consumers use accepted fixtures.

**Exit evidence:** recorded planning-to-shutdown scenario with cold-and-dark and ready-to-taxi starts; negative cases for fuel/power/configuration; a justified go-around; normal-flight numerical comparisons at identified source-supported loading/atmosphere/configuration points for takeoff, climb, cruise, approach/landing, and fuel use, with declared uncertainties/tolerances; continuation or checkpoint behavior passes the verified mode selected by SAVE-PROOF; interrupted-save and migration recovery tests; two profiles preserve separate bindings/logs; a user can access the practice record and basic map/event debrief; installed experience runs disconnected; pilot reviews procedure/indication consistency within supported scope. The broader mass/CG/atmosphere and maneuver envelope remains a P6 calibration gate.

**Gate failures:** incorrect aircraft-specific checklist, unsourced or failing baseline normal-flight performance, silently skipped procedures, invented official flight hours, corrupted progress, resume against incompatible model state, or score incentives that punish safe decisions. A normal-flight baseline may establish only its tested envelope; it cannot stand in for P6 advanced handling validation.

**Primary requirements:** PRD-004–013, PRD-016, PRD-022, PRD-025–031; UX-003–008, UX-016–023, UX-025–028.

## Dispatch queue

| Task | Area | Dependencies | Owned paths |
|---|---|---|---|
| [AIRCRAFT-EVIDENCE](https://github.com/brettbergin/flight-simulator/issues/28) — Freeze exact analog C172S configuration and source applicability | aircraft | EPIC-P2, LICENSE-REGISTER, VALIDATION-CORPUS | `content/aircraft/c172s/`, `docs/sources.md`, `tests/reference/c172s/` |
| [ENGINE-FUEL](https://github.com/brettbergin/flight-simulator/issues/29) — Implement sourced fuel-injected engine and fuel-system lifecycle | aircraft | EPIC-P2, AIRCRAFT-EVIDENCE | `native/sim_core/systems/engine/`, `native/sim_core/systems/fuel/`, `content/aircraft/c172s/` |
| [ELECTRICAL-SENSORS](https://github.com/brettbergin/flight-simulator/issues/30) — Implement electrical buses, instrument power and pitot/vacuum sources | aircraft | EPIC-P2, AIRCRAFT-EVIDENCE, SIX-PACK | `native/sim_core/systems/electrical/`, `native/sim_core/systems/sensors/`, `tests/systems/` |
| [CONTROLS-GROUND](https://github.com/brettbergin/flight-simulator/issues/31) — Complete trim, flaps, steering, struts and differential braking | physics | EPIC-P2, AIRCRAFT-EVIDENCE, GROUND-PROOF, INPUT-PROFILES | `native/sim_core/systems/controls/`, `native/fdm_jsbsim/ground/`, `tests/ground/` |
| [PREFLIGHT-CHECKLISTS](https://github.com/brettbergin/flight-simulator/issues/32) — Implement walkaround, checklist state and procedural cockpit flow | training | EPIC-P2, AIRCRAFT-EVIDENCE, ENGINE-FUEL, ELECTRICAL-SENSORS | `app/preflight/`, `content/checklists/c172s/`, `content/scenarios/circuit/` |
| [FLIGHT-PLANNING](https://github.com/brettbergin/flight-simulator/issues/33) — Implement payload, fuel, CG and takeoff/landing planning | aircraft | EPIC-P2, AIRCRAFT-EVIDENCE, ENGINE-FUEL | `app/ui/planning/`, `native/sim_core/mass/`, `tests/planning/` |
| [LOCAL-PERSISTENCE](https://github.com/brettbergin/flight-simulator/issues/34) — Implement SQLite profiles, migrations, atomic saves and recovery | persistence | EPIC-P2, SAVE-PROOF | `native/persistence/`, `schemas/save/`, `tests/persistence/` |
| [REPLAY-RESUME](https://github.com/brettbergin/flight-simulator/issues/35) — Implement command replay and verified session continuation | persistence | EPIC-P2, LOCAL-PERSISTENCE, SAVE-PROOF, ENGINE-FUEL, ELECTRICAL-SENSORS | `native/persistence/replay/`, `app/replay/`, `tests/replay/` |
| [ASSIST-PROFILES](https://github.com/brettbergin/flight-simulator/issues/36) — Implement discover, practice and assessment policies with intervention tags | training | EPIC-P2, LOCAL-PERSISTENCE, HUD-CAMERA | `content/assist-profiles/`, `app/ui/modes/`, `native/sim_core/interventions/` |
| [FULL-CIRCUIT](https://github.com/brettbergin/flight-simulator/issues/37) — Validate cold-and-dark to shutdown normal circuit and recovery | validation | EPIC-P2, PREFLIGHT-CHECKLISTS, CONTROLS-GROUND, FLIGHT-PLANNING, REPLAY-RESUME, ASSIST-PROFILES, BASELINE-PERFORMANCE, PROFILE-SESSION-UI, BASIC-DEBRIEF | `tests/scenarios/circuit/`, `docs/evidence/P3/` |
| [PROFILE-SESSION-UI](https://github.com/brettbergin/flight-simulator/issues/74) — Implement profile selection, local practice log and retention/export controls | ui | EPIC-P2, LOCAL-PERSISTENCE, ASSIST-PROFILES | `app/ui/profiles/`, `app/ui/history/`, `tests/ui/profiles/` |
| [BASIC-DEBRIEF](https://github.com/brettbergin/flight-simulator/issues/75) — Implement first circuit event review, basic map and recorded playback | ui | EPIC-P2, PROFILE-SESSION-UI, REPLAY-RESUME | `app/ui/debrief/basic/`, `app/replay/playback/`, `tests/debrief/basic/` |
| [BASELINE-PERFORMANCE](https://github.com/brettbergin/flight-simulator/issues/76) — Validate normal C172S performance before scored maneuver curriculum | validation | EPIC-P2, AIRCRAFT-EVIDENCE, VALIDATION-CORPUS, ENGINE-FUEL, CONTROLS-GROUND | `tests/reference/c172s/normal/`, `content/aircraft/c172s/fdm/`, `docs/evidence/P3/performance/` |

## Agent handoff

Use the canonical issue acceptance/evidence fields. Claim one task with an isolated branch/worktree; coordinate shared paths before editing. Publish interface changes first, then consumers. Record build/content/source versions, test outputs, unresolved gaps and human-review status in the PR. Prepare `docs/evidence/P3/` gate report only after the integrated scenario is actually run. The integrator changes dependency status labels; agents do not self-certify human pilot or owner review.
