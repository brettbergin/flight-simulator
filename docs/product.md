# Product specification

Status: proposed implementation plan for owner review. This document specifies the intended product; it does not assert that the simulator or its fidelity has been implemented or validated.

## Purpose and outcomes

Build a Windows desktop flight simulator that makes the decisions, procedures, workload, and aircraft behavior of a small general aviation airplane tangible. The first two users are a prospective student pilot and an experienced pilot who can no longer fly. A successful session should let the experienced pilot recognize the cockpit, operate familiar controls, plan a flight, notice changing conditions, and explain the consequences of choices to the student.

The first substantial milestone is a complete flight in one accurately defined Cessna 172 configuration at one bounded training airfield: plan, inspect, start, taxi, run up, take off, fly the circuit, land, park, secure, and review. Visual detail serves instrument readability, orientation, and aircraft cues. Flight behavior and correct causal relationships receive priority when cost or schedule forces a choice.

The product provides practice and educational feedback. It makes no claim to replace instruction, confer a pilot certificate, or provide qualifying training time. Any future credit or approval objective requires a separate jurisdiction-specific qualification program. The licensing jurisdiction remains undecided; initial content uses explicitly identified US reference material.

## Decisions and boundaries

| Topic | Initial decision | Expansion path |
|---|---|---|
| Runtime | Windows 11 x64, offline-first desktop application | Other desktop platforms after Windows acceptance |
| Reference computer | Reported Intel i9-12900K, RTX 3090, approximately 64 GB RAM; benchmark before performance claims | Publish tested minimum hardware after measurement |
| Aircraft | Target C172S fuel-injected analog training configuration; serial/configuration and source rights confirmed at the source/model gate | C172 variants through aircraft packages; later other aircraft families |
| Rendering and simulation | Godot 4.7.2 standard precision Forward+, C++20 bridge, dynamically linked JSBSim 1.3.1, SQLite local records, Python offline tooling; architecture ADR confirms integration | Replaceable aircraft models behind stable contracts |
| Controls | Keyboard/mouse and gamepad usable at launch; persistent calibration for yoke, throttle, pedals | TrackIR/head tracking, richer hardware panels, VR after desktop validation |
| Geography | Synthetic validation airfield first; compact north Puget Sound reference region after data verification | Candidate airports Arlington (KAWO), Paine Field (KPAE), and Boeing Field (KBFI), then reviewed regions |
| Connectivity | Complete installed core experience works without login or network | Optional downloaded scenery and dated weather updates |
| Distribution | GitHub Releases with Windows archive, manifest, checksums, licenses, release notes | Installer and signing when delivery needs justify them |
| Cost | Free tooling and freely redistributable data by default | Paid assets/services only after an explicit budget decision |
| Multiplayer | Deferred | Shared cockpit/instructor sessions after reliable single-player state and authority models |
| Project license | Existing MIT license for original project code | Dependencies/data/assets retain their own compatible terms |

Airport selection is a proposed design choice, not an assertion about present airport facilities. Runways, frequencies, airspace, lighting, elevations, traffic rules, and usable procedures must come from dated authoritative data before appearing as validated content. If source rights or scope prevent these airports, the region-selection issue must document the replacement.

The initial JSBSim C172 seed is a prototype surrogate whose exact configuration must be recorded. A carbureted seed cannot be relabeled as the fuel-injected C172S target. Source acquisition, configuration mapping, and quantitative comparison gate the target package. If the C172S source/model gate fails, a documented ADR may select an evidence-supported C172P starter aircraft; all procedures, UI labels, parameters, and scope claims then change together.

## User needs

| User | Need | Evidence of success |
|---|---|---|
| Student | Understand controls, cockpit scanning, planning, procedures, and decisions | Can explain mistakes and repeat a scenario with fewer prompts |
| Experienced pilot | Recognizable handling and cockpit logic, flexible familiar flights | Pilot review identifies no unresolved critical contradiction in supported operations |
| Limited-hardware user | Operate all supported functions with ordinary input devices | Entire circuit completed with keyboard/mouse and with a gamepad profile |
| Returning user | Resume practice without reconstructing setup | Profile, bindings, aircraft state, logs, and scenario context survive supported restarts |
| Future contributor/agent | Implement a bounded task against stable contracts | Issue states dependencies, files owned, evidence, and acceptance requirements |

## Core requirements

Requirement IDs are stable references for issues, acceptance evidence, and release scope. A requirement is complete only when its supported scope and evidence are recorded. Detailed system fidelity criteria belong in the aviation and architecture specifications.

### Aircraft and physical world

- **PRD-001 — Explicit aircraft identity.** Every aircraft package declares model/year/configuration, mass and balance limits, engine/propeller, fuel system, instruments, units, supported operating envelope, sources, assumptions, and unresolved gaps. Variant substitution cannot silently change procedure or performance.
- **PRD-002 — Physical consistency.** Aerodynamic forces, propulsion, gravity, atmosphere, mass, inertia, fuel consumption, control positions, and contact forces evolve through the authoritative simulation. Rendering, instruments, audio, and scoring derive from that state.
- **PRD-003 — Handling validation.** Validate trim, takeoff, climb, cruise, descent, landing, stalls within the supported envelope, wind response, and ground behavior against approved reference evidence. Publish measured tolerances and uncertainty. A supplied model is a seed, not proof of accuracy.
- **PRD-004 — Aircraft systems.** Model supported engine starting, throttle/mixture, ignition, fuel selection, electrical power, pitot/static instruments, brakes, trim, flaps, lights, radio/navigation equipment, and configuration-specific dependencies. Inoperative or approximated controls are visibly documented.
- **PRD-005 — Mass and balance.** Planning changes fuel, occupants, and baggage. Their distribution affects total mass, center of gravity, performance, and consumption throughout a session. Units and datum are explicit.
- **PRD-006 — Contact and airfield behavior.** Tires, steering, differential braking where supported, suspension, ground friction, runway slope/surface, ground effect, collision, parking, and propeller/ground clearance have defined behavior. A collision ends or pauses the learning scenario without implying real-world survivability.
- **PRD-007 — Time and environmental consistency.** Position, date/time, atmosphere, wind, visibility, clouds, sun, precipitation, and terrain agree across planning, simulation, rendering, and debrief to the fidelity available in the release.

### Complete flight lifecycle

- **PRD-008 — Planning.** Choose aircraft, airport, runway, destination/route, departure time, weather preset, loading, fuel, and assistance profile. Inspect airfield information, runway suitability, modeled airspace, navigation legs, alternatives, and estimated performance. Record a briefing snapshot.
- **PRD-009 — Inspection and preparation.** Support a walkaround/checklist representation, maintenance discrepancies, fuel quantity/type assumptions, control freedom, passenger briefing, documents/equipment cues, and cockpit setup. Actions that cannot be physically represented still need an honest educational interaction.
- **PRD-010 — Cold-and-dark operation.** Make starting, power availability, checks, radio tuning, taxi configuration, and engine indications causally consistent with the selected aircraft. A saved preset can place the airplane ready to taxi, but the profile records the skipped steps.
- **PRD-011 — Surface operation.** Display taxiways, signs, markings, hold positions, runway crossings, traffic, and airport status. Checklist and ATC context distinguishes taxi instructions from runway clearance. Early versions may use a quiet synthetic traffic environment and must identify that scope.
- **PRD-012 — Departure and circuit.** Support runway selection, wind assessment, run-up, takeoff briefing, takeoff, climb, circuit entry, downwind/base/final, stabilized approach criteria, go-around, landing, and runway exit. Procedures and circuit geometry depend on aircraft and airport/scenario data.
- **PRD-013 — Arrival and shutdown.** Support destination arrival, appropriate communications, parking, after-landing and securing tasks, and a debrief. Fuel, aircraft state, and practice record are saved at the end of the supported session.
- **PRD-014 — Cross-country.** Add pilotage/dead reckoning, charts/maps, magnetic/true heading distinctions, navigation aids appropriate to the aircraft, fuel planning and progress checks, diversions, alternate selection, and airspace awareness. This is a gated expansion beyond the first circuit.

### Presentation and interaction

- **PRD-015 — Operable cockpit.** Each supported control and instrument has legible, discoverable interaction and correct units/labels. Camera positions support instrument scan, outside reference, side windows, taxi, and landing flare.
- **PRD-016 — Assistance as a profile.** Guided practice offers optional labels, checklist prompts, control visualization, instructor messages, and route cues. Independent practice removes game overlays by default while retaining accessibility settings. Every result records aids used. Discovery, scenario evaluation, and local instructor modes are described in the training specification.
- **PRD-017 — Input accessibility.** Support configurable bindings, joystick axes, dead zones, reversal, sensitivity, calibration, trim, rudder assistance, controller disconnect recovery, mouse interaction, and navigable menus. Input aids cannot be hidden when reviewing handling evidence.
- **PRD-018 — Feedback cues.** Engine, wind, tires, brakes, switch clicks, stall warning where fitted, radio audio, and environmental sound reflect actual state. Sound is supplemented by visible captions or equivalent cues. Camera effects remain adjustable.
- **PRD-019 — Map and orientation.** Provide planning, in-flight, and debrief maps with airports, modeled runways, route, airspace where supported, relevant navigation aids, weather context, legend, and data dates. Optional live aircraft position is an explicit assistance setting.
- **PRD-020 — Comfort and accessibility.** Offer scalable text, readable cockpit zoom, adjustable audio channels, color-independent warnings, remappable inputs, reduced camera motion, and pause/quick recovery. VR is outside initial acceptance.

### Instruction, decisions, and emergencies

- **PRD-021 — Scenario curriculum.** Sequence cockpit familiarization, straight-and-level flight, turns, climbs/descents, trim, planning, taxi, takeoff, circuits, go-arounds, wind, navigation, abnormal situations, and emergencies. Each lesson defines prerequisites, sources, supported aircraft, assistance, observable objectives, and review status.
- **PRD-022 — Decision practice.** Scenarios include choices to delay, cancel, divert, use a different runway, request help, or go around. Achievements and scores reward those decisions when appropriate instead of rewarding completion at any cost.
- **PRD-023 — Communications.** Teach airport/airspace context and applicable radio phraseology through bounded deterministic ATC scenarios. Text/menu interaction is sufficient initially. Voice recognition and synthesis are optional later inputs, with no claim that unrestricted conversation matches real controllers.
- **PRD-024 — Failure scope.** Each introduced failure declares trigger conditions, indications, physical consequences, checklist references, recovery scope, and verification evidence. A visually dramatic effect alone is not a modeled failure. Unsupported emergencies cannot be scored as faithful procedure practice.
- **PRD-025 — Debrief evidence.** Record flight path, key aircraft parameters, configuration, weather, inputs, communications, assistance, and events. Explain deviations in context with uncertainty and actionable replay bookmarks. Distinguish observed behavior from an inferred cause.
- **PRD-026 — Review discipline.** Procedure content and fidelity claims need source review; an experienced pilot's qualitative assessment supplements quantitative evidence. Certification-oriented teaching requires an appropriately qualified reviewer in the chosen jurisdiction.

### Persistence, motivation, and delivery

- **PRD-027 — Separate users.** Local profiles isolate bindings, accessibility, preferred aircraft/airport, practice history, achievements, and current session. Guest practice works without accounts.
- **PRD-028 — Durable saves.** Transactional SQLite updates, atomic recording/snapshot writes, last-good backup, migrations, integrity checks, recovery, export/import, and clear unsupported-version messages protect progress. Define exactly which aircraft and scenario state may resume.
- **PRD-029 — Honest records.** Practice time, proficiency indicators, achievements, and instructor feedback are simulation records. They cannot be presented as official flight hours or proof of qualification. Resumed, assisted, or modified flights retain provenance.
- **PRD-030 — Meaningful motivation.** Achievements recognize practice milestones, well-executed procedures, planning, safe diversion/go-around decisions, and improvement. Avoid streak penalties, risk-taking incentives, or rewards for surviving unsupported dangerous behavior.
- **PRD-031 — Offline delivery.** Install, start, choose a scenario, fly, save, review, and restore a supported profile without network access. Optional online data cannot prevent offline operation.
- **PRD-032 — Release trust.** GitHub Releases identify application/model/content versions, known limitations, source/data dates, supported hardware, tests, checksums, license notices, migration notes, and regression evidence. Development snapshots are visibly identified.
- **PRD-033 — Performance budgets.** Measure frame time, simulation tick completion, input latency, loading, memory, and storage on the reference PC. At 2560×1440 default quality, the provisional reference-PC target is average ≥60 fps, p95 frame time ≤20 ms, and p99 ≤33 ms over a ten-minute representative warm run. Verify instrument readability at 1080p and 1440p and capture behavior at the owner's smaller window/display dimensions, including the reported 1360×768 surface. Broader minimum hardware and 4K capability require separate measurements. Physics cannot silently run slower because scenery is expensive. The [architecture budgets](architecture.md) define the full benchmark contract.
- **PRD-034 — Expandable content.** Aircraft, regions, checklists, lessons, and weather scenarios have versioned manifests and validation tools. Shared mechanics remain separate from variant-specific data and jurisdiction-specific teaching.

## First complete experience

The first reviewable flying release supports one airplane configuration, one verified synthetic airfield, clear daylight, a few deterministic wind presets, quiet traffic, full circuit, cold-and-dark and ready-to-taxi presets, local saves, basic event replay, and a readable conventional panel. It includes guided and independent practice. A pilot can inspect a documented handling envelope and repeat scenarios. Unsupported weather, equipment, procedures, and aircraft behavior are listed inside the build and release notes. Real-airport content follows the regional data gate.

Subsequent gates introduce regional cross-country flight, weather complexity, communications, lesson breadth, richer failures, instrument navigation where installed, night flight, and more aircraft. Worldwide scenery, photo-real global terrain, airliner systems, VR, online multiplayer, and certification are substantial independent programs. They enter the backlog after the base experience earns evidence of fidelity and usability.

## Product acceptance and traceability

Each issue must identify relevant requirement IDs and a phase. Acceptance evidence includes automated numerical checks where appropriate, screenshots/video for cockpit and surface cues, replay/log artifacts for procedural flows, licensed-source provenance, and pilot feedback tied to a specific build. A attractive screenshot cannot close a handling requirement; a numerical test cannot close readability or cockpit usability.

Critical gaps include physical instability, misleading instruments, incorrect aircraft-specific procedures, inconsistent units, corrupted saves, mismatched collision/runway surfaces, invisible assistance, and confusion between simulation records and qualifying flight time. Release scope contracts around unresolved gaps. Gates in [roadmap.md](roadmap.md) define the sequence; [experience-and-progress.md](experience-and-progress.md) specifies user journeys and records; [agent-operations.md](agent-operations.md) governs fleet work. The detailed evidence and content obligations are in [aircraft realism](realism-and-validation.md), [training and safety](training-and-safety.md), [world and data](world-and-data.md), and the [source register](sources.md).
