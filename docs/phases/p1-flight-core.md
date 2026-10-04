# P1 — Flight core and delivery feasibility

Generated from [roadmap](../roadmap.md) and [backlog](../backlog.json). Consult the [issue index](../issue-index.md) for actual GitHub links.

**Outcome:** a small numerical flight simulation runs repeatably, and a native Windows client package can load it on the reference PC.

**Deliverables:** pinned toolchain; flight tick/state/input contracts with explicit units and frames; headless JSBSim integration; recorded prototype configuration; atmosphere/control/load interfaces; reference-run fixtures; Godot/C++ extension loading; early ground-contact integration spike; minimal exported Windows archive that loads the extension and JSBSim DLL; dependency/license staging; telemetry and replay format prototype; complete solver-state restore/reconstruction proof and fallback checkpoint decision.

**Prerequisites:** P0 architecture and prototype identity contracts. This phase does not confer target-C172S fidelity on a supplied JSBSim model.

**Parallel lanes:** bridge owner implements authoritative tick/state contract; a validation owner builds reference fixtures; a package owner proves exported loading/DLL redistributability; a contact owner investigates ground-contact authority and runway coordinate conversion. Contract edits remain sequential. Source reviewers pursue target aircraft evidence in parallel.

**Exit evidence:** repeatable seeded runs on the declared platform/version; numerical states use documented units and ranges; pause/time-scale/input scheduling behave as designed; a clean Windows exported build starts with staged DLLs and license notices; a recorded ground-contact case shows one coherent contact authority; known seed-model discrepancies are listed; 60-second continuation and ten-minute reconstruction cases assess exact resume, otherwise select reviewed checkpoints. Record simulation tick and native integration costs before picking scenery budgets.

**Gate failures:** unstable integration, transform/unit mismatch, duplicate ground-contact solvers, native extension/export incompatibility, missing DLL or conflicting redistribution obligations. These are early architecture blockers and cannot be postponed to release week.

**Primary requirements:** PRD-001–007, PRD-025, PRD-032–034, UX-017, UX-020–021.

## Dispatch queue

| Task | Area | Dependencies | Owned paths |
|---|---|---|---|
| [CORE-CONTRACTS](https://github.com/brettbergin/flight-simulator/issues/11) — Ratify units, coordinate frames, clock, event and content schemas | core | EPIC-P0, PLAN-REVIEW | `schemas/`, `native/sim_core/contracts/`, `tests/contracts/`, `docs/contracts.md` |
| [TOOLCHAIN](https://github.com/brettbergin/flight-simulator/issues/12) — Lock reproducible Windows native and Godot build toolchain | delivery | EPIC-P0, PLAN-REVIEW | `CMakeLists.txt`, `CMakePresets.json`, `third_party/`, `tools/bootstrap/`, `.github/workflows/native-ci.yml` |
| [LICENSE-REGISTER](https://github.com/brettbergin/flight-simulator/issues/13) — Establish dependency, aircraft-reference and asset rights register | delivery | EPIC-P0, PLAN-REVIEW | `third_party/licenses/`, `docs/sources.md`, `tools/license-audit/` |
| [FDM-HARNESS](https://github.com/brettbergin/flight-simulator/issues/14) — Build headless fixed-tick JSBSim adapter and scripted runner | physics | EPIC-P0, CORE-CONTRACTS, TOOLCHAIN | `native/fdm_jsbsim/`, `native/sim_core/`, `tests/fdm/`, `tools/run-scenario/` |
| [NATIVE-EXPORT](https://github.com/brettbergin/flight-simulator/issues/15) — Prove GDExtension and JSBSim DLL loading in a portable Windows export | delivery | EPIC-P0, CORE-CONTRACTS, TOOLCHAIN, FDM-HARNESS | `native/godot_bridge/`, `app/proof/`, `tools/export/`, `tests/export/` |
| [GROUND-PROOF](https://github.com/brettbergin/flight-simulator/issues/16) — Prove JSBSim ground contacts against external terrain queries | physics | EPIC-P0, CORE-CONTRACTS, FDM-HARNESS | `native/fdm_jsbsim/ground/`, `native/world_core/ground/`, `tests/ground/` |
| [SAVE-PROOF](https://github.com/brettbergin/flight-simulator/issues/17) — Prove full-state restore or deterministic reconstruction strategy | persistence | EPIC-P0, CORE-CONTRACTS, FDM-HARNESS | `native/persistence/proof/`, `tests/replay/`, `docs/decisions/004-persistence-and-replay.md` |
| [RENDER-PROOF](https://github.com/brettbergin/flight-simulator/issues/18) — Benchmark representative cockpit readability and regional rendering | cockpit | EPIC-P0, TOOLCHAIN, NATIVE-EXPORT | `app/proof/`, `assets_source/proof/`, `tools/benchmark/` |
| [VALIDATION-CORPUS](https://github.com/brettbergin/flight-simulator/issues/19) — Create versioned aircraft reference matrix and regression corpus | validation | EPIC-P0, LICENSE-REGISTER, CORE-CONTRACTS, FDM-HARNESS | `tests/reference/`, `tools/validation/`, `docs/evidence/P1/` |
| [AIRBORNE-PREVIEW](https://github.com/brettbergin/flight-simulator/issues/94) — Deliver a human-controllable Windows airborne engineering preview | cockpit | EPIC-P0, CORE-CONTRACTS, FDM-HARNESS, NATIVE-EXPORT | `app/proof/airborne/`, `tools/preview/` |
| [INTERACTIVE-CONTRACT](https://github.com/brettbergin/flight-simulator/issues/95) — Ratify the bounded original ground-to-flight prototype contract and model | physics | EPIC-P0, CORE-CONTRACTS, FDM-HARNESS, GROUND-PROOF, LICENSE-REGISTER | `docs/decisions/006-interactive-prototype.md`, `native/fdm_jsbsim/models/original-interactive/`, `third_party/licenses/` |
| [WHOLE-FLIGHT-PREVIEW](https://github.com/brettbergin/flight-simulator/issues/98) — Deliver a Windows taxi-to-landing engineering preview | physics | EPIC-P0, CORE-CONTRACTS, FDM-HARNESS, GROUND-PROOF, NATIVE-EXPORT, INTERACTIVE-CONTRACT | `native/fdm_jsbsim/interactive/`, `native/godot_bridge/src/interactive*`, `app/proof/interactive/`, `tools/interactive-preview/`, `tests/interactive/`, `CMakeLists.txt` |
| [FLIGHT-UX](https://github.com/brettbergin/flight-simulator/issues/100) — Replace debug presentation with a usable visual flight experience | ui | WHOLE-FLIGHT-PREVIEW | `app/proof/interactive/`, `tools/interactive-preview/`, `docs/evidence/P1/flight-ux.md` |
| [COCKPIT-UX](https://github.com/brettbergin/flight-simulator/issues/102) — Add a physical prototype cockpit, focused panel view and local flight map | ui | FLIGHT-UX | `app/proof/interactive/`, `tools/interactive-preview/`, `docs/evidence/P1/cockpit-ux.md` |

## Agent handoff

Use the canonical issue acceptance/evidence fields. Claim one task with an isolated branch/worktree; coordinate shared paths before editing. Publish interface changes first, then consumers. Record build/content/source versions, test outputs, unresolved gaps and human-review status in the PR. Prepare `docs/evidence/P1/` gate report only after the integrated scenario is actually run. The integrator changes dependency status labels; agents do not self-certify human pilot or owner review.
