# Gated implementation roadmap and iteration briefs

Status: proposed. The current request lands documentation, issue structure, and delivery planning. Game implementation begins after the owner reviews this foundation.

Phases are ordered by evidence dependencies, not calendar promises. A phase can contain parallel tasks, but cannot pass its exit gate by accumulating issue completions. The coordinator records the build, review artifacts, unresolved gaps, and decision at each gate. Fidelity is scoped to the validated aircraft, environment, procedures, and data available in that release.

## Dependency shape

```mermaid
flowchart LR
    P0["P0: reviewed foundations"] --> P1["P1: core and Windows package spike"]
    P1 --> P2["P2: first cockpit and airfield"]
    P2 --> P3["P3: complete circuit lifecycle"]
    P3 --> P4["P4: regional navigation and weather"]
    P4 --> P5["P5: curriculum, communications, debrief"]
    P5 --> P6["P6: advanced systems and failures"]
    P6 --> P7["P7: validated Windows release"]
    P7 --> P8["P8: measured expansion"]
```

UI concepts, legal/source investigation, data provenance, test fixture design, and future content research may run ahead. Tasks that assume unaccepted simulation state, schemas, or behavior wait for the associated contract. Each phase ends with one integrated scenario and evidence that it remains possible to install, operate, and save supported functionality.

## P0 — Reviewable foundations

**Outcome:** owner and agents have a coherent plan, usable issue backlog, and clear limits before code work begins.

**Deliverables:** product/experience specifications; architecture and ADRs; aviation evidence and fidelity matrix; phase briefs; risk register; issue labels, milestone/backlog structure, dependency mapping; agent rules; CI and GitHub Releases policy. Record aircraft target, prototype surrogate distinction, source rights, reference region, hardware assumptions, and open decisions.

**Prerequisites:** repository access and high-level user intent. Original code remains MIT; aircraft data/assets/dependencies need separate licensing evidence.

**Parallel lanes:** product/UX, simulation architecture, aviation/source review, and repository/release governance. Root integrates decisions and issues.

**Exit evidence:** documentation links resolve; all first-phase issues have requirements, ownership, dependencies, and testable acceptance; architecture choices and source uncertainties agree across documents; owner can identify the first complete playable outcome and the next implementation task. The owner review is an explicit boundary requested by the user.

**Gate failures:** conflicting aircraft assumptions, unlicensed indispensable sources, unclear numeric units/frames, or a backlog that requires all agents to edit the same core files. Resolve through ADR/content scope changes before implementation.

**Primary requirements:** PRD-001, PRD-026, PRD-032, PRD-034.

## P1 — Authoritative flight core and delivery feasibility

**Outcome:** a small numerical flight simulation runs repeatably, and a native Windows client package can load it on the reference PC.

**Deliverables:** pinned toolchain; flight tick/state/input contracts with explicit units and frames; headless JSBSim integration; recorded prototype configuration; atmosphere/control/load interfaces; reference-run fixtures; Godot/C++ extension loading; early ground-contact integration spike; minimal exported Windows archive that loads the extension and JSBSim DLL; dependency/license staging; telemetry and replay format prototype; complete solver-state restore/reconstruction proof and fallback checkpoint decision.

**Prerequisites:** P0 architecture and prototype identity contracts. This phase does not confer target-C172S fidelity on a supplied JSBSim model.

**Parallel lanes:** bridge owner implements authoritative tick/state contract; a validation owner builds reference fixtures; a package owner proves exported loading/DLL redistributability; a contact owner investigates ground-contact authority and runway coordinate conversion. Contract edits remain sequential. Source reviewers pursue target aircraft evidence in parallel.

**Exit evidence:** repeatable seeded runs on the declared platform/version; numerical states use documented units and ranges; pause/time-scale/input scheduling behave as designed; a clean Windows exported build starts with staged DLLs and license notices; a recorded ground-contact case shows one coherent contact authority; known seed-model discrepancies are listed; 60-second continuation and ten-minute reconstruction cases assess exact resume, otherwise select reviewed checkpoints. Record simulation tick and native integration costs before picking scenery budgets.

**Gate failures:** unstable integration, transform/unit mismatch, duplicate ground-contact solvers, native extension/export incompatibility, missing DLL or conflicting redistribution obligations. These are early architecture blockers and cannot be postponed to release week.

**Primary requirements:** PRD-001–007, PRD-025, PRD-032–034, UX-017, UX-020–021.

## P2 — First pilot-operable cockpit and synthetic airfield

**Outcome:** a user can control the airplane from a readable conventional cockpit and fly a repeatable basic exercise over a bounded airfield.

**Deliverables:** legal prototype visual assets; panel/instrument presentation driven by simulation state; essential cockpit interaction; keyboard/mouse/gamepad profiles; camera presets; control calibration; basic engine and environmental audio; synthetic runway/taxi geometry with deterministic metadata; ready-to-fly scenario; state-to-map alignment; performance capture. Evaluate the aircraft source/configuration gate before claiming the target C172S package.

**Prerequisites:** accepted P1 transform/state/contact/input contracts and exported-build feasibility. Art can proceed against a mock state adapter while core contracts are stabilized.

**Parallel lanes:** cockpit instruments and interaction; camera/input/accessibility; airfield visual/surface cues; audio; quantitative handling comparisons; packaging/performance. Assign separate owned files and shared mock fixtures.

**Exit evidence:** exported application completes start, taxi/ground movement, takeoff, climb, turns, descent, and landing within the stated prototype envelope; instrument readings agree with their sensor/state contract; controls and runway surfaces align; complete keyboard/mouse and gamepad exercises captured; reference-PC frame/tick measurements at 2560×1440 recorded against the provisional architecture budgets; instrument readability at 1080p/1440p and smaller captured window dimensions reviewed; pilot provides initial cockpit/handling observations.

**Gate failures:** mislabeled target aircraft, unreadable primary instruments, display/simulation disagreement, uncontrollable default input, unreliable contact, or unbounded scenery load. A synthetic airfield is explicitly labeled and receives no real-airport fidelity claim.

**Primary requirements:** PRD-003, PRD-006–007, PRD-015–020, PRD-033; UX-001–002, UX-009–015.

## P3 — Complete normal circuit and durable local progress

**Outcome:** father and student can each complete and review a full normal flight in a defined aircraft configuration.

**Deliverables:** aircraft source/configuration decision; validated basic systems; initial quantitative normal-flight performance baseline; loading/fuel planner; inspection representation; cold-and-dark/start/run-up/after-landing/shutdown flows; checklist provenance; complete synthetic circuit and go-around; separate profiles and session UI; atomic save/restore and migrations; practice log; event debrief/basic map replay; offline session; packaged release candidate suitable for pilot feedback.

**Prerequisites:** P2 cockpit/input/contact acceptance; aircraft source rights and target-versus-fallback ADR decision. A surrogate may continue for engineering experiments, but product acceptance identifies its actual configuration.

**Parallel lanes:** aircraft systems; planner/checklists; profile/session UI; persistence/replay; basic debrief; normal-flight numerical baseline; circuit scenario; cockpit/audio completion. Root owns shared state/schema evolution. Schema consumers use accepted fixtures.

**Exit evidence:** recorded planning-to-shutdown scenario with cold-and-dark and ready-to-taxi starts; negative cases for fuel/power/configuration; a justified go-around; normal-flight numerical comparisons at identified source-supported loading/atmosphere/configuration points for takeoff, climb, cruise, approach/landing, and fuel use, with declared uncertainties/tolerances; continuation or checkpoint behavior passes the verified mode selected by SAVE-PROOF; interrupted-save and migration recovery tests; two profiles preserve separate bindings/logs; a user can access the practice record and basic map/event debrief; installed experience runs disconnected; pilot reviews procedure/indication consistency within supported scope. The broader mass/CG/atmosphere and maneuver envelope remains a P6 calibration gate.

**Gate failures:** incorrect aircraft-specific checklist, unsourced or failing baseline normal-flight performance, silently skipped procedures, invented official flight hours, corrupted progress, resume against incompatible model state, or score incentives that punish safe decisions. A normal-flight baseline may establish only its tested envelope; it cannot stand in for P6 advanced handling validation.

**Primary requirements:** PRD-004–013, PRD-016, PRD-022, PRD-025–031; UX-003–008, UX-016–023, UX-025–028.

## P4 — Bounded real region, navigation, and environmental challenge

**Outcome:** a planned regional flight demands navigation, weather/load judgment, and a credible arrival or diversion.

**Deliverables:** dated/redistributable region pipeline; verified KAWO/KPAE/KBFI candidates or documented replacement; terrain/obstacles and airport diagrams within defined scope; runway/taxi metadata; airspace and navigation layers; route/fuel plan; compass/navigation equipment relevant to configuration; wind/pressure/temperature/visibility/cloud presets; crosswind validation; alternate/diversion scenario; day/night progression when lighting and visibility evidence is ready.

**Prerequisites:** P3 complete session/persistence; airport/source approval; position/altitude datum and magnetic/true contracts; environmental model fidelity sufficient for the scenario. Live weather is optional and not a dependency.

**Parallel lanes:** region-data tooling/provenance; airport leaf packages; weather visuals and sound; modeled atmosphere/visibility; map/navigation; cross-country lesson data. A single owner integrates geography/datum contracts and coverage manifests.

**Exit evidence:** one airport-to-airport flight and one supported diversion with consistent planner/cockpit/map/debrief positions; dated airfield/airspace source checks; terrain/runway alignment; demonstrated response to wind, load, density, and visibility changes; offline installed map/data; source terms and coverage gaps visible; performance on the reference PC.

**Gate failures:** decorative terrain represented as complete obstacle coverage, inconsistent altitude datum or magnetic variation, stale data hidden from users, or weather visuals that disagree with the force/visibility model.

**Primary requirements:** PRD-005, PRD-007–008, PRD-014, PRD-019, PRD-022, PRD-031, PRD-034; UX-003, UX-008, UX-014–015.

## P5 — Reviewed lessons, communications, and evidence-rich debrief

**Outcome:** a repeatable curriculum helps users improve supported procedures and decisions without hiding simulator limitations.

**Deliverables:** lesson schema/evaluators; progressive basic curriculum; checklists and decision scenarios; deterministic towered/untowered communications; taxi/runway clearance state; basic traffic for scenario interactions with declared coverage; expanded debrief timeline/graphs/bookmarks; assistance provenance; idempotent achievements; review export; pilot/qualified instructional review where appropriate.

**Prerequisites:** P4 region, flight phases, and navigation data; accepted event/evaluator/persistence contracts. A few introductory P3 lessons may exist earlier, but a curriculum claim awaits systematic review.

**Parallel lanes:** content authors work one lesson family per issue; evaluator owner implements shared rules; ATC owner handles communication authority/context; debrief/achievement owners consume stable events. Human review is a scheduled gate, not a task agents can self-certify.

**Exit evidence:** same scenario produces consistent events; clearance and phase transitions are tested for misuse; radio content sources reviewed; appropriate go-around/cancellation/diversion recognized; unsupported scan/inspection/judgment marked unevaluated; resumed/replayed awards cannot duplicate; assistance and earlier evaluator versions remain visible; pilot can replay and explain a meaningful event.

**Gate failures:** open-ended generated instruction presented as authoritative, ATC contradictions, high scores masking material events, unsafe achievement incentives, or evaluator claims beyond observed evidence.

**Primary requirements:** PRD-011–014, PRD-021–023, PRD-025–030; UX-006, UX-021–028.

## P6 — Advanced aircraft realism and bounded failures

**Outcome:** abnormal conditions arise from modeled causes and produce credible indications and decisions within a documented envelope.

**Deliverables:** higher-confidence handling calibration; engine/fuel/electrical/sensor detail justified by source evidence; failure framework; selected engine/power/electrical/pitot-static scenarios; failure-specific checklists/recovery envelopes; appropriate weather limitations and effects; richer ground/runway conditions where validated; instrument-navigation familiarization when installed equipment and jurisdictional sources support it.

**Prerequisites:** P5 evaluation and event contracts; aircraft operating/reference rights; P3 normal-flight quantitative baseline and normal systems/indications validated before related failures. P6 expands calibration across supported mass, CG, atmosphere, configurations, and maneuvers; it does not postpone all normal-flight comparison until this phase. Complex icing, spins, and structural damage are separate evidence gates, not assumed consequences of adding an effects system.

**Parallel lanes:** individual system/failure packages; handling-validation fixtures; cockpit indicators/audio; reviewed lesson data; regression/performance. Shared system dependencies and damage authority remain sequential.

**Exit evidence:** each shipped failure has trigger, cause, indications, physical effect, source, procedure, recovery scope, and tests; normal flight regression holds; quantitative envelope/tolerances recorded; pilot reviews a bounded failure session; exclusions appear in application and release notes. Visual/audio effects correspond to actual state.

**Gate failures:** failure represented only by animation, incorrect common-mode interactions, unsourced exact emergency procedure, plausible-looking stall/spin/icing claims without evidence, or excessive confidence in emergency scoring.

**Primary requirements:** PRD-001–007, PRD-021–026; UX-023–026.

## P7 — Windows release, stability, and pilot acceptance

**Outcome:** a downloadable build reliably supports its declared flying/practice scope on the reference machine.

**Deliverables:** release automation; full packaged dependency/license manifest; clean-machine launch checks; checksums; release notes and known fidelity gaps; final performance/settings matrix; save compatibility report; accessibility/usability review; regression scenario pack; crash recovery/offline verification; pilot evaluation report with resolved critical findings. Broader minimum specifications are published only after tests on additional hardware.

**Prerequisites:** accepted P6 scoped features, or explicit documented release scope selecting a narrower earlier-phase build. Every included feature has evidence; postponement does not erase its requirement.

**Parallel lanes:** regression/reliability; visual/readability QA; license/source audit; performance/scenery settings; pilot session preparation; release packaging. Integrator freezes core/content versions and owns the release candidate.

**Exit evidence:** clean Windows user profile/download/archive run without developer environment; installed offline full flight/save/debrief; migration/interruption recovery; repeatable package/build manifest; tests and pilot feedback linked to exact artifact; critical safety/content contradictions resolved or removed from supported scope; provisional 2560×1440 default-quality reference-PC target assessed over a ten-minute representative warm run (average ≥60 fps, p95 frame time ≤20 ms, p99 ≤33 ms), with simulation tick behavior measured independently; instrument readability at 1080p/1440p plus captured smaller window dimensions reviewed; tag/release approved under repository delivery policy. No general minimum-spec claim follows from testing this one PC.

**Gate failures:** DLL dependence on development machine, hidden release permissions/secrets, unusable update/downgrade, missing licenses, significant flight/instrument discrepancies, or publishing realism claims beyond evidence.

**Primary requirements:** PRD-017–020, PRD-026–034; UX-001, UX-009, UX-012–022, UX-028.

## P8 — Expansion selected by observed value

**Outcome:** expand a proven simulator in response to user/pilot feedback without destabilizing validated experiences.

**Candidate programs:** additional C172 configurations; other aircraft architectures; new reviewed regions; fuller traffic/ATC; optional current weather ingestion; multi-monitor/hardware panels/head tracking; VR; shared cockpit/instructor mode; richer instrument/weather training; additional jurisdictions; community content tools; installer/code-signing improvements.

**Prerequisites:** P7 stable release, versioned packages, evidence of the need, a source/rights plan, and an ADR describing new assumptions. VR, multiplayer, worldwide scenery, and formal training-device qualification each require their own scope, budget, and validation plan.

**Parallel lanes:** self-contained expansion packages after central contracts are reviewed. Backward compatibility, save provenance, existing lesson expectations, and original aircraft regression are mandatory integration concerns.

**Exit evidence:** program-specific acceptance, compatibility tests, performance impact, pilot review, and release limitations. There is no universal “everything is realistic” completion gate.

## Work packet for each implementation issue

Every packet contains: phase and requirement IDs; user-observable outcome; prerequisite issues/contracts; exact files/directories owned; input/source licenses; state and event interfaces; included/excluded behavior; acceptance criteria; evidence artifacts; test instructions; known risks; human review needed; and estimated relative size. Keep a task small enough for one agent to deliver a coherent reviewable PR.

Use the following handoff in each phase gate record:

```text
Phase and build/content/model identifiers:
Integrated scenario performed:
Requirements accepted, partial, or deferred:
Numerical/visual/pilot evidence links:
Source/data versions and licensing status:
Critical gaps and their owned issues:
Contract changes required for the next phase:
Gate decision, reviewer, and date:
```

Calendar forecasts follow the first measured iteration. Agent count increases independent leaf capacity, not the rate at which core contracts or human pilot reviews can be decided. See [agent-operations.md](agent-operations.md) for scheduling and integration rules.
