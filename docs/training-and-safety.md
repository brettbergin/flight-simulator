# Training, pilot decisions and safety

Status: design baseline, 2026-10-03. This is a curriculum and product specification, not a real-aircraft checklist. The user's licensing jurisdiction remains undecided. Start with a versioned **US FAA private-pilot, airplane single-engine land** content pack; keep curriculum, legal rules, phraseology and units replaceable by jurisdiction.

The product supports practice, familiarization and enjoyment. It does not award a pilot certificate, authorize real flight, establish fitness/currency or provide approved-device training credit. [FAA AC 61-136B](https://www.faa.gov/regulations_policies/advisory_circulars/index.cfm/go/document.information/documentID/1034348) describes a separate approval process for aviation training devices. Device approval and credit would be a future product/regulatory program, with its own requirements and evidence. Simulated log entries must explicitly identify simulated practice.

## Experience modes

| Mode | Purpose | Assistance and evaluation |
| --- | --- | --- |
| Discovery | Comfortable first flight and returning-pilot enjoyment | Optional hints, checklist support, simplified radio choices, recovery/reset and adjustable camera; assist state recorded |
| Guided practice | Learn one skill or decision in context | Briefing, demonstration/replay, prompts that can fade and feedback tied to observed events |
| Independent practice | Rehearse a complete flight with responsibility | Realistic instrument view, full checklists and planning, no default path markers; debrief after flight |
| Scenario evaluation | Repeatable assessment against a defined lesson rubric | Fixed initial conditions/seed and versioned rules; hints/restarts labeled; unresolved evidence yields ungraded output |
| Instructor session | A knowledgeable person observes and controls scenarios locally | Pause, reposition, inject supported faults, set weather, review traces; every intervention recorded |

**SAFE-001:** keep assist settings independent: auto-rudder, throttle/help, navigation overlay, checklist confirmation, camera stabilization, damage, radio menus and instructor prompts. Difficulty is a preset over these controls, not hidden alteration of aircraft physics. A user may enjoy relaxed flying while keeping a credible aircraft model.

**SAFE-002:** cockpit instruments are the primary information in independent practice. HUD overlays are optional training aids with assistance badges; configurable instrument enlargement is an accessibility feature. Debrief may reveal ground-truth values; normal flight instruments retain their actual sensor errors and failures.

**SAFE-003:** no game system requires reckless conduct to progress. Reward planning, consistent aircraft control, checklist discipline, useful radio communication, a timely go-around, diversion and a justified cancellation. Do not reward flying under bridges, squeezing fuel reserves, surviving weather beyond the modeled aircraft's limits or landing despite an unstable approach. Achievements label the aid profile and lesson/version they used.

## Curriculum coverage and traceability

Use [FAA-S-ACS-6C](https://www.faa.gov/training_testing/testing/acs/private_airplane_acs_6.pdf) as a traceability framework. Its knowledge, risk and skill components belong together; a simulator exercise cannot establish every component of a real practical test. The following area references identify coverage candidates for the selected land-airplane class, rather than claiming a complete approved course.

| ACS area | Simulator coverage candidate |
| --- | --- |
| I–II | Planning, pilot/aircraft readiness, weather, performance, systems, human factors, inspection and ground preparation |
| III–IV | Radio and airport operations; patterns, normal/short/soft-field flight, slips and go-arounds |
| V–VII | Turns, ground-reference work, visual/radio navigation, diversion/lost scenarios, slow flight and stall awareness |
| VIII–IX | Basic instrument reference, unusual-attitude awareness and supported emergency/system scenarios |
| XI–XII | Night planning/operation and after-landing/parking/securing |

**SAFE-004:** lessons contain objective, prerequisite, scope, source references, aircraft/jurisdiction versions, demonstration, initial conditions, success/failure rubric, expected hazards, assistance policy, debrief and remediation. Map individual ACS codes during content implementation and verify their exact version; do not manufacture codes from memory.

**SAFE-005:** track knowledge checks, decisions and aircraft handling separately. A successful touchdown alone cannot imply weather competence, radio competence or checklist completion. Mastery requires repeatable performance in multiple conditions and review status; personal progress is descriptive, not a real-world proficiency endorsement.

**SAFE-006:** ACS maneuver thresholds are imported task by task from the applicable source and stored separately from aircraft-model validation tolerances. Do not use one universal altitude/heading/airspeed tolerance for every maneuver. Preserve each threshold's reference and domain; unavailable evidence means ungraded assessment. Scoring records duration/severity and context, not just a boolean threshold crossing.

## Full flight lifecycle

This lifecycle is the proposed simulator's scenario inventory. It provides backlog scope; every item requires aircraft/source verification before being turned into instructions.

| ID | Phase | Required decisions and interactions |
| --- | --- | --- |
| SAFE-007 | Before accepting a flight | Readiness, proficiency, familiar equipment, external pressure, passengers and mission constraints; set personal minimums; choose to postpone |
| SAFE-008 | Dispatch/planning | Weather briefing and trends, airspace, terrain/obstacles, route/checkpoints, altitude, fuel/reserves, weight/CG, performance, alternate/diversion choices, airport availability and simulated notices |
| SAFE-009 | Walkaround/preflight | Aircraft documents/discrepancies, fuel/oil/contamination, tires/brakes, control surfaces, ports, lights, tiedowns/chocks, baggage and loading |
| SAFE-010 | Before start/start | Cabin organization, seats/belts/doors, controls, passenger briefing, propeller-area check, applicable startup, abnormal indications, radio/ATIS and departure preparation |
| SAFE-011 | Taxi/run-up | Surface chart, position and heading verification, signs/markings/hold lines, steering/brakes, wind-control positioning, run-up and applicable engine/control checks |
| SAFE-012 | Takeoff/departure | Clearance versus taxi authorization, correct runway, remaining distance, takeoff briefing, reject/go decisions, climb energy, wind correction, departure routing and airspace |
| SAFE-013 | En route | Trim/coordination, scan, terrain, radio, checkpoints, navigation error, heading versus track, fuel/time crosschecks and evolving weather |
| SAFE-014 | Arrival/pattern | Weather/runway selection, local procedures, traffic integration, speed/configuration, descent planning and stabilized approach criteria |
| SAFE-015 | Landing/go-around | Correct runway/surface, crosswind/flare/touchdown, bounce recognition, rejected landing, runway exit and clearance of protected areas |
| SAFE-016 | Shutdown/postflight | Parking, securing, electrical/engine shutdown, fuel/accounting, defects, simulated flight-plan closure and debrief |

US preflight content should cover the topics in [14 CFR 91.103](https://www.ecfr.gov/current/title-14/chapter-I/subchapter-F/part-91/subpart-B/section-91.103), including information relevant to the planned flight and applicable runway/performance planning. A lesson's legal rules must retain their effective version. If the final jurisdiction changes, replace the content pack and re-review scenarios.

## Airport operations, ATC and traffic

**SAFE-017:** airport rules are data driven. Tower schedules, runway-specific traffic direction, altitude/reference, noise procedures, closures and ATC instructions influence the scenario. A pattern is adaptable to traffic/wind and local procedure, not a mandatory glowing rectangle. The [AIM airport-operations section](https://www.faa.gov/air_traffic/publications/aim_html/chap4_section_3.html) provides general pattern guidance, including published exceptions. [AC 90-66C](https://www.faa.gov/regulations_policies/advisory_circulars/index.cfm/go/document.information/documentID/1041885) addresses non-towered operations; identify recommendation versus rule in lesson content.

**SAFE-018:** provide simulated clearance delivery where applicable, ground, tower, approach/departure, flight following, CTAF and ATIS/AWOS services by scenario capability. Start with deterministic text/voice menus and optional synthesized audio; later speech recognition must show confidence and allow correction. No cloud language model independently grants runway clearances, changes separation or invents a procedure.

**SAFE-019:** ATC is an explicit state machine. Taxi routes, runway crossings, hold-short requirements, line-up/wait, takeoff, landing, option and go-around instructions have distinct authorization states. Readbacks validate safety-critical fields and require correction if wrong. Queued, blocked or stepped-on transmissions and wrong-frequency calls affect reception. Text accessibility reveals exactly the radio message received, not additional unspoken guidance.

**SAFE-020:** aircraft and ground traffic have motion/state, right-of-way context and occupancy; they cannot teleport through the user's final or vanish to make an unsafe landing succeed. Controller schedule changes and unavailable services are scenario data. Simulated traffic advisories cannot guarantee the pilot sees all aircraft. Develop encounter fixtures for overtaking, converging traffic, opposite-direction use, base/final conflict, wake exposure and vehicle incursion.

**SAFE-021:** model runway incursions using signed hold areas and surface geometry plus clearance state, including aircraft footprint. Test a nose crossing a hold line, a cleared taxi route without a crossing clearance, wrong-runway alignment, ambiguous readback and landing on a parallel taxiway. Debrief explains the observed event and authorization. [FAA runway-safety publications](https://www.faa.gov/airports/runway_safety/publications) are source material for reviewed lesson research.

## Weather, human factors and emergencies

**SAFE-022:** first weather lessons use authored deterministic scenarios with wind, visibility, ceiling, temperature/pressure and time of day. Weather visuals and aircraft atmosphere must agree. Later scenarios include fronts, gusts/shear, terrain influence, fog, rain, night visibility, convective hazards, freezing risk and deteriorating VFR. Live station reports provide limited observations; they do not constitute a complete three-dimensional weather field.

**SAFE-023:** scenarios include fatigue/distraction, unfamiliar airport/equipment, passenger pressure, fixation on an instrument, plan continuation and delayed decisions. Use role-play/context and explain limitations; do not collect medical records or diagnose fitness. Simulate reduced outside cues and night illusions only after visual QA demonstrates credible conditions. Do not turn a randomly dark screen into a claim of realistic spatial disorientation.

**SAFE-024:** abnormal scenarios follow causal aircraft state: fuel starvation versus exhaustion, rough-running engine, oil-pressure/temperature problems, ignition fault, alternator/battery depletion, vacuum/pitot-static faults, radio failure, stuck flaps/brake problems, fire and engine failure at different phases. Faults can be scripted or instructor-selected; failure probability is deterministic/seeded and disabled by default in discovery. No unsupported emergency is introduced merely because a checklist mentions it.

**SAFE-025:** emergency exercises prioritize preserving control, assessing available options and executing source-reviewed aircraft procedures. Landing-site choice considers reachable geography, surface, obstacles, wind and energy. Engine failure shortly after departure must not teach a universal turnback altitude or automatic return maneuver. Uncertain performance/sight-picture evidence restricts scoring. Fire, spins, severe icing and other complex cases stay in reviewed later capability releases.

**SAFE-026:** private-pilot basic instrument work and weather-escape awareness are initially distinct from an instrument-rating curriculum. Full IFR clearance/approach/holding/missed-approach training requires additional aircraft equipment, navigation/procedure fidelity, sources and instructor review. Future expansion includes instrument rating, complex/high-performance transitions and additional jurisdictions without blending their privileges into the initial pack.

## Feedback, progress and saved sessions

**SAFE-027:** every debrief exposes lesson/build, aircraft, world, rubric and assistance versions; route; time/weather; phase events; control/airspeed/altitude traces; checklist and radio actions; hazards; and the reason for each evaluation. Distinguish user error, unsupported capability, data uncertainty and a simulator fault. Give the user one or two actionable practice suggestions; link source context and allow replay from before the event.

**SAFE-028:** simulator log records contain practice duration, takeoffs/landings, scenario, aircraft and aid profile. They are separate from real pilot logbooks and never claim instructor signatures or credit. Achievements and personal bests preserve the original rubric; changed content does not silently upgrade old attempts. Users can export and delete local history.

**SAFE-029:** saving includes scenario phase, failures/damage, fuel, electrical/engine/instrument state, aircraft state, weather/random generators, traffic, ATC/clearances, checklist progress and scoring. Resuming cannot refill fuel, clear faults or grant a clearance. Interrupted attempts retain their status; continuing after a restart/reposition is valid practice but labeled accordingly. Rolling autosave and crash recovery must never overwrite the last valid session with a corrupt file.

**SAFE-030:** instructor pause freezes simulation time and traffic/weather/ATC consistently. Menus that intentionally keep time running must clearly indicate it. Time acceleration, replay control and repositioning are recorded interventions. Discovery and practice are always available; an assessment unlock cannot trap the user away from desired flying.

## Accessibility and returning-pilot enjoyment

Provide scalable instruments/text, remappable controls, readable colors, radio captions, separate audio channels, reduced camera motion, seated viewpoints, quick resume and optional short sessions. Physical effort, eyesight or hearing adjustments do not imply lowered aircraft fidelity. No diagnosis about the user's father is assumed.

Enjoyment features include a familiar cold-and-dark cockpit, quiet local flights, route bookmarks, sightseeing, a personal aircraft log, optional curated challenges and replay sharing. Later aircraft variants may recreate the father's preferred experience after he identifies them. Keep content encouraging without turning the app into a competitive penalty system.

## Safety acceptance gate

**SAFE-031:** reviewed scenarios must prove: cancellation/diversion/go-around can achieve success; no achievement requires breaking a scenario's limits; assistance and unsupported content are visible; missing/stale evidence prevents authoritative grades; incorrect runway authorization is caught; saved/resumed state preserves hazards; aircraft-specific procedures have applicable sources; and debriefs accurately explain observed actions. Training claims are reviewed alongside release notes and UI text, not merely a startup disclaimer.

Handbook background comes from the [PHAK](https://www.faa.gov/regulations_policies/handbooks_manuals/aviation/phak) and [Airplane Flying Handbook](https://www.faa.gov/regulations_policies/handbooks_manuals/aviation/airplane_handbook), with current addenda. Curriculum content is authored in small reviewed lessons; importing whole manuals or making a comprehensive practical-test claim is outside this specification.
