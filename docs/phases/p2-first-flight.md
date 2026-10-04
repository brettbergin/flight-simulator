# P2 — First cockpit and synthetic airfield

Generated from [roadmap](../roadmap.md) and [backlog](../backlog.json). Consult the [issue index](../issue-index.md) for actual GitHub links.

**Outcome:** a user can control the airplane from a readable conventional cockpit and fly a repeatable basic exercise over a bounded airfield.

**Deliverables:** legal prototype visual assets; panel/instrument presentation driven by simulation state; essential cockpit interaction; keyboard/mouse/gamepad profiles; camera presets; control calibration; basic engine and environmental audio; synthetic runway/taxi geometry with deterministic metadata; ready-to-fly scenario; state-to-map alignment; performance capture. Evaluate the aircraft source/configuration gate before claiming the target C172S package.

**Prerequisites:** accepted P1 transform/state/contact/input contracts and exported-build feasibility. Art can proceed against a mock state adapter while core contracts are stabilized.

**Parallel lanes:** cockpit instruments and interaction; camera/input/accessibility; airfield visual/surface cues; audio; quantitative handling comparisons; packaging/performance. Assign separate owned files and shared mock fixtures.

**Exit evidence:** exported application completes start, taxi/ground movement, takeoff, climb, turns, descent, and landing within the stated prototype envelope; instrument readings agree with their sensor/state contract; controls and runway surfaces align; complete keyboard/mouse and gamepad exercises captured; reference-PC frame/tick measurements at 2560×1440 recorded against the provisional architecture budgets; instrument readability at 1080p/1440p and smaller captured window dimensions reviewed; pilot provides initial cockpit/handling observations.

**Gate failures:** mislabeled target aircraft, unreadable primary instruments, display/simulation disagreement, uncontrollable default input, unreliable contact, or unbounded scenery load. A synthetic airfield is explicitly labeled and receives no real-airport fidelity claim.

**Primary requirements:** PRD-003, PRD-006–007, PRD-015–020, PRD-033; UX-001–002, UX-009–015.

## Dispatch queue

| Task | Area | Dependencies | Owned paths |
|---|---|---|---|
| [SIM-LOOP](https://github.com/brettbergin/flight-simulator/issues/20) — Integrate fixed-tick core, interpolation, terrain queries and pause | core | EPIC-P1, NATIVE-EXPORT, GROUND-PROOF, SIM-LOOP-CONTRACT | `app/simulation/`, `native/godot_bridge/`, `tests/integration/` |
| [INPUT-PROFILES](https://github.com/brettbergin/flight-simulator/issues/21) — Implement keyboard, mouse, gamepad and calibrated flight-device bindings | input | EPIC-P1, CORE-CONTRACTS, INPUT-CONTROLS-CONTRACT | `app/input/`, `app/ui/controls/`, `tests/input/` |
| [SYNTHETIC-AIRFIELD](https://github.com/brettbergin/flight-simulator/issues/22) — Build deterministic runway, markings and ground collision fixture | world | EPIC-P1, GROUND-PROOF, SIM-LOOP | `content/world/synthetic/`, `app/world/`, `tests/world/` |
| [COCKPIT-ASSET](https://github.com/brettbergin/flight-simulator/issues/23) — Create correctly scaled interactive conventional-panel cockpit | cockpit | EPIC-P1, LICENSE-REGISTER, RENDER-PROOF, COCKPIT-READINGS-CONTRACT | `assets_source/c172/`, `app/cockpit/`, `content/aircraft/prototype/` |
| [SIX-PACK](https://github.com/brettbergin/flight-simulator/issues/24) — Drive six-pack and engine indicators through sensor bindings | cockpit | EPIC-P1, COCKPIT-ASSET, SIM-LOOP, COCKPIT-READINGS-CONTRACT | `app/cockpit/instruments/`, `native/sim_core/instruments/`, `tests/instruments/` |
| [FLIGHT-AUDIO](https://github.com/brettbergin/flight-simulator/issues/25) — Implement state-driven engine, wind and warning sound with captions | audio | EPIC-P1, SIM-LOOP, LICENSE-REGISTER | `app/audio/`, `assets_source/audio/`, `tests/audio/` |
| [HUD-CAMERA](https://github.com/brettbergin/flight-simulator/issues/26) — Implement cockpit views, optional training HUD and assistance visibility | ui | EPIC-P1, COCKPIT-ASSET, SIX-PACK, INPUT-PROFILES | `app/ui/hud/`, `app/camera/`, `tests/ui/` |
| [FIRST-FLIGHT](https://github.com/brettbergin/flight-simulator/issues/27) — Validate first pilot-operable takeoff, circuit and landing prototype | validation | EPIC-P1, SYNTHETIC-AIRFIELD, HUD-CAMERA, FLIGHT-AUDIO | `content/scenarios/first-flight/`, `tests/scenarios/first-flight/`, `docs/evidence/P2/` |
| [SIM-LOOP-CONTRACT](https://github.com/brettbergin/flight-simulator/issues/112) — Ratify the synchronous flight-loop and render-origin interface | core | CORE-CONTRACTS, NATIVE-EXPORT, INTERACTIVE-CONTRACT | `docs/decisions/007-sim-loop-facade.md`, `docs/contracts.md`, `docs/backlog.json`, `docs/issue-index.md`, `docs/requirements.md`, `docs/phases/p2-first-flight.md` |
| [INPUT-CONTROLS-CONTRACT](https://github.com/brettbergin/flight-simulator/issues/116) — Ratify pilot input presets and paused calibration | input | CORE-CONTRACTS, SIM-LOOP-CONTRACT, INTERACTIVE-CONTRACT | `docs/decisions/008-input-presets.md`, `docs/contracts.md`, `docs/backlog.json`, `docs/issue-index.md`, `docs/requirements.md`, `docs/phases/p2-first-flight.md` |
| [COCKPIT-READINGS-CONTRACT](https://github.com/brettbergin/flight-simulator/issues/119) — Ratify native-truth cockpit readings and view-only scan focus | cockpit | CORE-CONTRACTS, SIM-LOOP-CONTRACT, INPUT-CONTROLS-CONTRACT | `docs/decisions/009-cockpit-readings.md`, `docs/contracts.md`, `docs/backlog.json`, `docs/issue-index.md`, `docs/requirements.md`, `docs/phases/p2-first-flight.md` |

## Agent handoff

Use the canonical issue acceptance/evidence fields. Claim one task with an isolated branch/worktree; coordinate shared paths before editing. Publish interface changes first, then consumers. Record build/content/source versions, test outputs, unresolved gaps and human-review status in the PR. Prepare `docs/evidence/P2/` gate report only after the integrated scenario is actually run. The integrator changes dependency status labels; agents do not self-certify human pilot or owner review.
