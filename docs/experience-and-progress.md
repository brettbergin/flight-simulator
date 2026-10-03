# Experience, HUD, practice records, and progress

Status: proposed product and data behavior. Requirement IDs extend the product specification and should be cited by issues that implement these flows.

## Session journeys

### First launch

**UX-001.** Create a local profile or start as guest. Offer readable display/audio defaults, input selection, calibration, and short cockpit interaction practice. The application must not require a network connection or account. User-facing language clearly describes the supported airplane, current fidelity scope, and practice purpose.

**UX-002.** A first-flight path begins with a guided cockpit orientation and a short repeatable flight exercise. An experienced-pilot path allows choosing aircraft configuration, airport, weather, and start state directly. Users can change paths without losing their record. Both paths retain the same aircraft state and physics.

### Plan, fly, and review

**UX-003.** The flight planner follows the pilot's actual questions: where and when to fly, what aircraft and load, whether conditions and runway are suitable, fuel/performance, route and airspace, alternatives, and intended procedures. It shows assumptions, dates, and limitations at the point where they affect a decision. Planning can deliberately end with cancellation and still record useful practice.

**UX-004.** Starting positions include cold-and-dark, ready-to-taxi, and predefined airborne practice states where appropriate. The briefing displays skipped procedures and initial aircraft/environment state. Independent sessions default to cold-and-dark after introductory practice; fast setup remains available for familiar flights with the user's father.

**UX-005.** A supported circuit carries context through inspection, start, taxi, run-up, departure, pattern, approach, go-around when needed, landing, parking, and shutdown. A checklist can be consulted without destroying situational awareness. The user chooses whether an overlay pauses simulation; pause is visibly indicated and recorded.

**UX-006.** End-of-session review contains a map, event timeline, configuration changes, selected measurements, decision points, and scenario-specific objectives. It allows scrubbing and bookmarks for a circuit turn, unstable approach, stall warning, runway crossing, or excellent go-around. Feedback describes what the system measured and the scope of the evaluator.

### Resume and repetition

**UX-007.** Quit offers the supported snapshot or reviewed checkpoint and records the session as unfinished. Continue restores supported state, including weather/clock and scenario context, or explains the restart boundary. The UI clearly distinguishes exact continuation from checkpoint restart. Aborting safely preserves an honest partial record.

**UX-008.** Repeat uses the same versioned initial conditions and random seed. Change-one-factor practice lets the user change wind, load, or assistance while retaining the briefing. Comparisons identify changed conditions; score differences alone cannot imply improved skill.

## Cockpit, HUD, and maps

The cockpit is the primary flight display. A generic game HUD is optional assistance, with deliberate separation between cockpit instruments, instructor cues, navigation aids, and accessibility tools.

| Display | Guided practice | Independent practice | Required behavior |
|---|---|---|---|
| Cockpit instruments | Always present; optional labels | Always present | Actual simulated sensor output, unit and limit markings |
| Core flight overlay | User-selectable speed/altitude/heading and controls | Off by default | Declare source: sensor indication or world truth |
| Checklist | Available, with prompts | User-invoked, no automatic completion | Readable, sourced, aircraft-specific, completion provenance |
| Instructor messages | Objective-focused contextual prompts | Suppressed unless requested | Bounded reviewed text and recorded assistance |
| Route/circuit ribbons | Optional | Off by default | Training cue, does not imply real airfield authority |
| Aircraft-on-map | Optional | User-configurable aid | Recorded assistance; dated map sources |
| Captions and scalable UI | Available | Available | Accessibility does not silently change aircraft physics |
| Pause and replay | Available | Available | Clearly visible state, consistent time accounting |

**UX-009.** Instrument readability is tested at planned output resolutions, window sizes, cockpit views, and font scaling. A useful scan requires the airspeed indicator, attitude indicator, altimeter, turn instrument, heading indicator/compass, vertical speed indicator, and relevant engine/fuel indications to be readable in the configured panel. Instrument selection and layout must follow the chosen variant.

**UX-010.** Provide preset views for full panel, close instrument scan, outside horizon, each side window, overhead/side controls where relevant, and taxi/landing reference. Mouse look can be disengaged quickly. Support a consistent field-of-view policy; changing zoom cannot masquerade as a flight maneuver. Camera shake and head-motion effects are independently adjustable.

**UX-011.** Mouse control hit targets support precise knobs, switches, levers, and guarded actions. Hotkeys and gamepad focus expose the same functions. A visible interaction hint identifies the target before action; invalid actions explain the relevant modeled reason. Avoid modal confirmation for every cockpit action.

**UX-012.** Calibration shows raw and mapped axes, stable neutral values, dead zones, reversal, saturation, and trim response. One action has a documented authority rule if several devices are connected. Disconnecting the device pauses or offers a controlled recovery instead of leaving a stale maximum input. Rudder/trim assistance is visible in the briefing and debrief.

**UX-013.** All warnings use text or shape in addition to color. Offer audio channel controls for engine/environment/radio/instructor/interface, visual alternatives to critical audible indications, adjustable text, reduced camera motion, and keyboard/controller menu navigation. Accessibility settings and flight assistance are stored independently.

**UX-014.** Planning, flight, and debrief maps share coordinates and identifiers. Each map has a legend, scale, orientation, source dates, selected layers, magnetic/true labeling where relevant, elevation units, and a distinction between modeled facilities and decorative scenery. Do not visually imply complete airspace or navigation coverage when only a subset is loaded.

**UX-015.** Use traffic pattern terminology in US content and localize it for later jurisdictions. Map and briefing show airport-specific pattern direction/altitude where evidence supports them, selected runway, weather, and communications context. Synthetic training geometry is labeled as such. Traffic overlays are assistance with known sensor/visibility scope.

## Local profiles and practice records

Store user data in the Windows per-user application data location, separated from installation files and content packages. Path names and schema details are confirmed by the persistence architecture issue. No mandatory cloud account, telemetry, or background uploads are part of the initial product.

**UX-016.** A profile includes a stable identifier, display name, preferences, input profiles, assistance defaults, accessibility settings, preferred aircraft/location, lesson progress, achievements, and references to session records. The father and student can use separate profiles on the same computer. Guest data is transient unless explicitly saved.

**UX-017.** A session record contains:

- Profile/session identifiers, schema version, start/end timestamps, paused and active simulation durations.
- Application build, aircraft/model/configuration versions, content/data dates, and evaluator version.
- Initial briefing, load/fuel, route, start preset, environmental conditions, random seed, and jurisdiction/reference-pack version.
- Assistance and calibration identifiers, changes during flight, camera/display modes relevant to evaluation.
- Completion/aborted/crash/recovered/resumed status, evaluator outcomes, pilot notes, and known limitations.
- Event and replay references, their integrity hashes, and retention status.

A local simulation practice log is distinct from a legal pilot logbook. UI labels use “simulation practice” and explain what active duration measures. Export preserves this classification and provenance.

**UX-018.** Save components independently where practical: transactional SQLite profile/preferences/session index, immutable session/replay files, resumable state, and cache. One asynchronous writer commits the database and durable recording references; success is shown after a committed receipt. Validate temporary recording/snapshot files before atomic replacement. Back up SQLite using its backup API or tested checkpoint/closed-copy procedure so WAL content is preserved. Keep a last-good backup. A broken replay cannot make all profiles unreadable; a corrupt profile offers recovery without deleting the original. [ADR-004](decisions/004-persistence-and-replay.md) defines the storage authority.

**UX-019.** Version every persistent schema. Maintain migration fixtures from released versions, backup before migration, and define rollback/downgrade behavior. Content update or aircraft configuration mismatch can require starting a new session; do not silently resume against different physics. A migration error preserves source data and explains recovery/export options.

**UX-020.** The initial save proof investigates finite trusted snapshots of the selected aircraft, environment, integrator/model state, scenario/ATC state, lesson evaluator state, and clocks. Validate ranges and referenced packages before loading. Tests compare supported continuation to uninterrupted execution. If full restoration cannot be proven, test matching-runtime reconstruction from complete accepted logs. If neither path meets equivalence/time criteria, limit resume to reviewed ground/scenario restart checkpoints and preserve recordings/progress. Do not promise arbitrary midair continuation before the P1 proof gate.

**UX-021.** Replay is a recorded presentation and diagnostic tool first. State samples and events permit scrubbing independently of current physics; deterministic command replay is a separate tested capability with build/model/seed constraints. Replaying or branching cannot create a second completion reward from the same achievement event. A branched practice flight gets a new session linked to its source.

**UX-022.** Retention controls show estimated disk use, preserve compact practice records when bulky replay data is removed, and support export/import of profile and session bundles. Export manifests include schema/content versions and checksums. Import never overwrites a different profile without an explicit user action.

## Learning, assessment, and achievements

**UX-023.** A lesson has a versioned objective, prerequisites, aircraft/environment envelope, briefing, event triggers, assistance options, observable assessment rules, review/source status, and known limits. “Not evaluated” is a valid outcome for absent or uncertain evidence. Free flight remains available when lessons require prerequisites.

**UX-024.** The initial curriculum follows cockpit orientation; controls/trim; straight-and-level flight and basic turns; climbs/descents; planning/loading; surface operations; normal departure; circuit/approach; go-around; landing/shutdown. Crosswind, short/soft-field techniques, navigation, night/instrument familiarization, and abnormalities enter only when the relevant physics and content have passed their gates.

**UX-025.** Evaluation uses phase-aware, aircraft/scenario-specific criteria. Speed, altitude, configuration, runway alignment, checklist events, clearance context, and approach energy are evaluated with declared tolerances and grace periods. Checklists must distinguish a user check mark from evidence that the relevant state was actually verified. Scoring cannot claim to observe cockpit scan, physical inspection, or judgment that it does not measure.

**UX-026.** Debrief prioritizes material events and explains the consequence and a practical next exercise. It does not bury a runway incursion beneath a high numerical score. Weather/load/assistance changes qualify comparisons. The user can annotate a disagreement or attach pilot feedback for review without changing the original telemetry.

**UX-027.** Achievements are optional and local. Candidate milestones include a first complete circuit, checklist-supported cold-and-dark flight, deliberate go-around, correctly selected diversion, fuel planning exercise, consistent stabilized approaches within a validated envelope, and completing a lesson with reduced assistance. They do not reward dangerous low flight, reckless weather penetration, or pushing unvalidated limits.

**UX-028.** Achievement definitions have stable IDs and versions; award events are idempotent. Changing an evaluator does not rewrite historical results silently. Show “recorded under an earlier evaluator” where appropriate. Progress measures practice and documented simulator objectives, with no labels such as “licensed,” “certified pilot,” or “ready for solo” based on game progress.

## Acceptance examples

| Scenario | Expected result |
|---|---|
| Student begins with gamepad, father later uses yoke | Separate calibration and profiles; both can complete the same supported flight |
| User starts ready-to-taxi and finishes a circuit | Skipped stages recorded; flight counts as that scoped practice |
| Approach becomes unsuitable and pilot goes around | Scenario recognizes appropriate decision; no failure for abandoning the landing |
| Application closes during a save | Last valid snapshot or backup restores; original corrupted file retained for diagnosis |
| New content changes aircraft model | Completed record retains old metadata; incompatible resume is explained |
| User resumes/replays an old circuit | Assistance/version/context remain visible; rewards cannot duplicate |
| Map source covers only selected airspace | Coverage and dates clear in briefing/map; no implied global completeness |
| Network unavailable | Installed flights, saves, practice records, maps, and debrief continue |

These examples are candidates for scenario-based acceptance tests, not a request to write tests for every label or trivial preference. Data integrity, recovery, and evaluation provenance require meaningful automated coverage; readability and full-flight interaction require visual and pilot review. Modes and curriculum evidence align with [training-and-safety.md](training-and-safety.md); persistence and replay behavior align with [ADR-004](decisions/004-persistence-and-replay.md).
