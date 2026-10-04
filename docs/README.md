# Flight simulator project plan

This is a serious Windows desktop flight simulator for realistic Cessna flying, thoughtful practice, and enjoyment by an experienced pilot. The first delivery establishes the implementation plan and GitHub work queue. The owner approved the plan and authorized implementation on 2026-10-03; see [P0 acceptance](evidence/P0/acceptance.md). P1 now establishes executable contracts, native flight dynamics and Windows delivery proofs. A playable simulator requires the subsequent cockpit and flight-operation phases.

## Decisions made for this project

| Decision | Initial choice |
|---|---|
| Runtime | Windows 11 x64; desktop first, VR later |
| Reference PC | i9-12900K, RTX3090, approximately 64 GB RAM; measured performance gate on this machine |
| First aircraft | Explicit C172S fuel-injected conventional-panel target; variant/serial/POH provenance gate; generic models remain labeled prototypes |
| Stack | Godot 4 Forward+ presentation, C++20 native core, JSBSim flight dynamics, SQLite persistence, Python offline data tools |
| Engine account | Owner selected Godot for account-free authoring using its direct download |
| Scope | Offline single-player; synthetic validation airfield followed by dated north Puget Sound region |
| Operations | US/FAA reference lessons first; jurisdiction-neutral core and future jurisdiction packs |
| Controls | Keyboard/mouse and gamepad initially; calibrated yoke/throttle/pedals are core design requirements |
| Business/cost | Public open-source foundation; zero mandatory subscriptions, locally stored profiles |
| Distribution | GitHub Releases; documentation prereleases now, Windows simulator packages after proof gates |
| Realism proof | Reference comparisons, repeatable telemetry, pilot evaluations, and explicitly visible limits |

Complete aircraft configuration, airport source dates, assist settings, and training rubric versions travel with each recorded session. Accepted P1 work includes original synthetic dynamics, external ground-contact experiments, exact same-build flight reconstruction, and a portable native Windows export. The [whole-flight preview](../tools/interactive-preview/README.md) combines ground steering, takeoff, flight, touchdown and braking in one native simulation; [its evidence](evidence/P1/interactive-preview.md) distinguishes automated operation from pilot evaluation. The earlier airborne preview remains reproducible. The [renderer proof](evidence/P1/render-proof.md) records its separate visual-load experiment; the three final ten-minute load captures passed their frozen proxy checks and independent review. The P1 phase gate remains open.

The latest [rural scenery and runway locator iteration](evidence/P1/airfield-landmarks.md) adds original farms, woodland, roads, water and six named references. The optional map selects either synthetic runway end and shows native-truth geometry; scenery remains cosmetic over the same flat native plane.

The [aircraft and rollout-control correction](evidence/P1/aircraft-ground-ux.md) replaces intersecting glazing and adds an explicit idle shortcut with persistent native-held brake/throttle feedback. Its unchanged-model diagnosis is bounded engineering evidence; C172 and phase review remain open.

The [third-person motion correction](evidence/P1/third-person-stability.md) presents adjacent native ticks and follows their translation in the same render frame. Its nominal8.333ms visual delay does not change physics, instrument readings or map state; frozen delivery and visual review remain separate gates.

The [reusable flight-loop integration](evidence/P2/sim-loop.md) prepares the accepted facade/origin contract for ordinary interactive flight, with five explicit speeds, copied native truth and coordinated scene origins. Its exported verification and phase review remain separate from development checks and prototype handling.

The [paused Controls and preset iteration](evidence/P2/input-controls.md) prepares explicit remapping, observed-device calibration and safe takeover over the same native flight loop. Presets remain guest interchange files; manual hardware and phase qualification remain separate.

The [shared native-truth cockpit and instrument scan](evidence/P2/cockpit-readability.md) adds a paused readability view and one reading source for the physical dashboard, overlay and focused dial. Sensed instruments and aircraft qualification remain separate requirements.

The [optional landmark route board](evidence/P2/landmark-free-flight.md) gives free flight a local destination: choose a short itinerary while paused, use the target card or map, manually select the next leg, and choose a return to either synthetic runway end. Its session-local geometric aids use the original native anchor.

The accepted [original piston profile contract](decisions/010-original-piston-profile.md) defines the next opt-in cold-engine engineering slice, including native ignition/starter/feed/mixture controls and versioned input migration. Its model/reference and runtime consumers have separate evidence gates; the selected C172S configuration remains source-dependent.

The [original piston source and independent references](evidence/P3/original-piston-source.md) supply the next cold-engine prerequisite. Native controls and coupled engine behavior remain separate implementation work.

## Read in this order

1. [Product scope and requirements](product.md): expected pilot experience and initial boundaries.
2. [Roadmap and iteration gates](roadmap.md) and [individual phase dispatch briefs](phases/README.md): what gets built first and what evidence unlocks the next phase.
3. [Architecture](architecture.md) and [contracts](contracts.md): stack, components, units, ownership, persistence, and extension boundaries.
4. [Aircraft realism and validation](realism-and-validation.md), [training and safety](training-and-safety.md), and [world/data](world-and-data.md): evidence and operational behavior.
5. [Cockpit, HUD, progress, and accessibility](experience-and-progress.md): presentation and learning experience.
6. [Agent execution](agent-operations.md), [copyable issue prompts](agent-prompts.md), and [CI/releases](delivery.md): how a fleet can deliver reviewable work.
7. [Backlog guide](backlog.md), [GitHub issue index](issue-index.md), [requirement traceability](requirements.md), [risks](risks.md), and [source register](sources.md).

## Review focus

The [P1 engineering gate report](evidence/P1/gate-review.md) collects accepted child/build evidence and the proposed next backlog handoff. Phase acceptance remains pending owner review; the report distinguishes bounded proof results from production saves, C172 systems and pilot qualification.

Review the aircraft target, desktop/offline priorities, regional scope, phase gates, and what first meaningful flying will include. Budget defaults avoid paid tools and services. Technical unknowns have early proof tasks and fallback decisions. Phase targets are not promised dates. [The owner-review issue](https://github.com/brettbergin/flight-simulator/issues/10) must close before implementation starts.

Simulator practice is recorded as practice. Formal training/device approval and jurisdiction-specific license credit have their own regulatory and instructor requirements; this project has not established those. The plan supports transfer of useful habits through evidence-reviewed scenarios and makes prototype limits visible.

## Current automation

Run `node tools/check-docs.mjs` to validate local documentation/backlog consistency. `node tools/sync-github.mjs` previews the issue plan. Apply is explicit and described in [backlog.md](backlog.md). The [native bootstrap](../tools/bootstrap/README.md) builds the locked dependencies and contract tests; both platforms also verify actual Godot native loading in CI. See [P1 foundation evidence](evidence/P1/bootstrap.md), [native export](evidence/P1/native-export.md), [ground contacts](evidence/P1/ground-proof.md), [reconstruction](evidence/P1/save-proof.md), [independent references](evidence/P1/validation-corpus.md) and [airborne-preview evidence](evidence/P1/airborne-preview.md). A complete cockpit remains P2 work.
