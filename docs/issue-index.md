# Issue index

Generated from [backlog.json](backlog.json). All links refer to planned work; the owner review gate remains open until the owner accepts the plan.

## P0 — Reviewable foundations

| Key | Issue | Dependencies |
|---|---|---|
| EPIC-P0 | [#1 Reviewable foundations](https://github.com/brettbergin/flight-simulator/issues/1) | Owner review |
| PLAN-REVIEW | [#10 Owner review of architecture, aircraft target, scope, and phased delivery](https://github.com/brettbergin/flight-simulator/issues/10) | Owner review |

## P1 — Flight core and delivery feasibility

| Key | Issue | Dependencies |
|---|---|---|
| EPIC-P1 | [#2 Flight core and delivery feasibility](https://github.com/brettbergin/flight-simulator/issues/2) | EPIC-P0 |
| CORE-CONTRACTS | [#11 Ratify units, coordinate frames, clock, event and content schemas](https://github.com/brettbergin/flight-simulator/issues/11) | EPIC-P0, PLAN-REVIEW |
| TOOLCHAIN | [#12 Lock reproducible Windows native and Godot build toolchain](https://github.com/brettbergin/flight-simulator/issues/12) | EPIC-P0, PLAN-REVIEW |
| LICENSE-REGISTER | [#13 Establish dependency, aircraft-reference and asset rights register](https://github.com/brettbergin/flight-simulator/issues/13) | EPIC-P0, PLAN-REVIEW |
| FDM-HARNESS | [#14 Build headless fixed-tick JSBSim adapter and scripted runner](https://github.com/brettbergin/flight-simulator/issues/14) | EPIC-P0, CORE-CONTRACTS, TOOLCHAIN |
| NATIVE-EXPORT | [#15 Prove GDExtension and JSBSim DLL loading in a portable Windows export](https://github.com/brettbergin/flight-simulator/issues/15) | EPIC-P0, CORE-CONTRACTS, TOOLCHAIN, FDM-HARNESS |
| GROUND-PROOF | [#16 Prove JSBSim ground contacts against external terrain queries](https://github.com/brettbergin/flight-simulator/issues/16) | EPIC-P0, CORE-CONTRACTS, FDM-HARNESS |
| SAVE-PROOF | [#17 Prove full-state restore or deterministic reconstruction strategy](https://github.com/brettbergin/flight-simulator/issues/17) | EPIC-P0, CORE-CONTRACTS, FDM-HARNESS |
| RENDER-PROOF | [#18 Benchmark representative cockpit readability and regional rendering](https://github.com/brettbergin/flight-simulator/issues/18) | EPIC-P0, TOOLCHAIN, NATIVE-EXPORT |
| VALIDATION-CORPUS | [#19 Create versioned aircraft reference matrix and regression corpus](https://github.com/brettbergin/flight-simulator/issues/19) | EPIC-P0, LICENSE-REGISTER, CORE-CONTRACTS, FDM-HARNESS |

| AIRBORNE-PREVIEW | [#94 Deliver a human-controllable Windows airborne engineering preview](https://github.com/brettbergin/flight-simulator/issues/94) | EPIC-P0, CORE-CONTRACTS, FDM-HARNESS, NATIVE-EXPORT |

| INTERACTIVE-CONTRACT | [#95 Ratify the bounded original ground-to-flight prototype contract and model](https://github.com/brettbergin/flight-simulator/issues/95) | EPIC-P0, CORE-CONTRACTS, FDM-HARNESS, GROUND-PROOF, LICENSE-REGISTER |

| WHOLE-FLIGHT-PREVIEW | [#98 Deliver a Windows taxi-to-landing engineering preview](https://github.com/brettbergin/flight-simulator/issues/98) | EPIC-P0, CORE-CONTRACTS, FDM-HARNESS, GROUND-PROOF, NATIVE-EXPORT, INTERACTIVE-CONTRACT |

| FLIGHT-UX | [#100 Replace debug presentation with a usable visual flight experience](https://github.com/brettbergin/flight-simulator/issues/100) | WHOLE-FLIGHT-PREVIEW |

| COCKPIT-UX | [#102 Add a physical prototype cockpit, focused panel view and local flight map](https://github.com/brettbergin/flight-simulator/issues/102) | FLIGHT-UX |

| ENVIRONMENT-STABILITY | [#104 Eliminate terrain and airfield surface flicker in the playable preview](https://github.com/brettbergin/flight-simulator/issues/104) | COCKPIT-UX |

| AIRFIELD-LANDMARKS | [#106 Enrich the rural airfield scenery and add a selectable runway-end locator](https://github.com/brettbergin/flight-simulator/issues/106) | ENVIRONMENT-STABILITY |

| AIRCRAFT-GROUND-UX | [#108 Fix intersecting cabin glazing and clarify rollout controls](https://github.com/brettbergin/flight-simulator/issues/108) | AIRFIELD-LANDMARKS |

| THIRD-PERSON-STABILITY | [#110 Smooth third-person aircraft motion and keep camera tracking in the same frame](https://github.com/brettbergin/flight-simulator/issues/110) | AIRCRAFT-GROUND-UX |

| DOCS-NATIVE-CI-SCOPE | [#124 Bound native CI work for documentation-only PRs](https://github.com/brettbergin/flight-simulator/issues/124) | CORE-CONTRACTS, TOOLCHAIN, NATIVE-EXPORT |

## P2 — First cockpit and synthetic airfield

| Key | Issue | Dependencies |
|---|---|---|
| EPIC-P2 | [#3 First cockpit and synthetic airfield](https://github.com/brettbergin/flight-simulator/issues/3) | EPIC-P1 |
| INPUT-CONTROLS-CONTRACT | [#116 Ratify pilot input presets and paused calibration](https://github.com/brettbergin/flight-simulator/issues/116) | CORE-CONTRACTS, SIM-LOOP-CONTRACT, INTERACTIVE-CONTRACT |
| SIM-LOOP-CONTRACT | [#112 Ratify the synchronous flight-loop and render-origin interface](https://github.com/brettbergin/flight-simulator/issues/112) | CORE-CONTRACTS, NATIVE-EXPORT, INTERACTIVE-CONTRACT |
| SIM-LOOP | [#20 Integrate fixed-tick core, interpolation, terrain queries and pause](https://github.com/brettbergin/flight-simulator/issues/20) | EPIC-P1, NATIVE-EXPORT, GROUND-PROOF, SIM-LOOP-CONTRACT |
| INPUT-PROFILES | [#21 Implement keyboard, mouse, gamepad and calibrated flight-device bindings](https://github.com/brettbergin/flight-simulator/issues/21) | EPIC-P1, CORE-CONTRACTS, INPUT-CONTROLS-CONTRACT |
| SYNTHETIC-AIRFIELD | [#22 Build deterministic runway, markings and ground collision fixture](https://github.com/brettbergin/flight-simulator/issues/22) | EPIC-P1, GROUND-PROOF, SIM-LOOP |
| COCKPIT-ASSET | [#23 Create correctly scaled interactive conventional-panel cockpit](https://github.com/brettbergin/flight-simulator/issues/23) | EPIC-P1, LICENSE-REGISTER, RENDER-PROOF, COCKPIT-READINGS-CONTRACT |
| SIX-PACK | [#24 Drive six-pack and engine indicators through sensor bindings](https://github.com/brettbergin/flight-simulator/issues/24) | EPIC-P1, COCKPIT-ASSET, SIM-LOOP, COCKPIT-READINGS-CONTRACT |
| FLIGHT-AUDIO | [#25 Implement state-driven engine, wind and warning sound with captions](https://github.com/brettbergin/flight-simulator/issues/25) | EPIC-P1, SIM-LOOP, LICENSE-REGISTER |
| HUD-CAMERA | [#26 Implement cockpit views, optional training HUD and assistance visibility](https://github.com/brettbergin/flight-simulator/issues/26) | EPIC-P1, COCKPIT-ASSET, SIX-PACK, INPUT-PROFILES |
| FIRST-FLIGHT | [#27 Validate first pilot-operable takeoff, circuit and landing prototype](https://github.com/brettbergin/flight-simulator/issues/27) | EPIC-P1, SYNTHETIC-AIRFIELD, HUD-CAMERA, FLIGHT-AUDIO |
| COCKPIT-READINGS-CONTRACT | [#119 Ratify native-truth cockpit readings and view-only scan focus](https://github.com/brettbergin/flight-simulator/issues/119) | CORE-CONTRACTS, SIM-LOOP-CONTRACT, INPUT-CONTROLS-CONTRACT |
| LANDMARK-FREE-FLIGHT | [#130 Add a synthetic landmark itinerary and optional target card](https://github.com/brettbergin/flight-simulator/issues/130) | AIRFIELD-LANDMARKS, SIM-LOOP, INPUT-CONTROLS-CONTRACT, COCKPIT-READINGS-CONTRACT |
| OBSERVED-REVIEW-CONTRACT | [#132 Ratify bounded recorded flight observations and read-only review](https://github.com/brettbergin/flight-simulator/issues/132) | SIM-LOOP-CONTRACT, INPUT-CONTROLS-CONTRACT, COCKPIT-READINGS-CONTRACT |
| OBSERVED-FLIGHT-REVIEW | [#134 Add paused recorded path and instrument timeline](https://github.com/brettbergin/flight-simulator/issues/134) | OBSERVED-REVIEW-CONTRACT, LANDMARK-FREE-FLIGHT |
| OBSERVED-ARCHIVE-CONTRACT | [#136 Define exact recorded-review Save/Open interchange](https://github.com/brettbergin/flight-simulator/issues/136) | OBSERVED-REVIEW-CONTRACT, OBSERVED-FLIGHT-REVIEW, INPUT-CONTROLS-CONTRACT |
| OBSERVED-REVIEW-FILES | [#138 Save and reopen exact paused flight reviews](https://github.com/brettbergin/flight-simulator/issues/138) | OBSERVED-ARCHIVE-CONTRACT, OBSERVED-FLIGHT-REVIEW |
| STEADY-WIND-CONTRACT | [#140 Define selectable steady-wind starts and native-truth cues](https://github.com/brettbergin/flight-simulator/issues/140) | INTERACTIVE-CONTRACT, SIM-LOOP-CONTRACT, COCKPIT-READINGS-CONTRACT, OBSERVED-REVIEW-CONTRACT, OBSERVED-ARCHIVE-CONTRACT |
| STEADY-WIND-FLIGHT | [#142 Add selectable steady wind and native-truth flight cues](https://github.com/brettbergin/flight-simulator/issues/142) | STEADY-WIND-CONTRACT, OBSERVED-REVIEW-FILES |

## P3 — Complete circuit and durable progress

| Key | Issue | Dependencies |
|---|---|---|
| ORIGINAL-PISTON-CONTRACT | [#122 Ratify an opt-in original piston and fixed-pitch profile](https://github.com/brettbergin/flight-simulator/issues/122) | CORE-CONTRACTS, INTERACTIVE-CONTRACT, SIM-LOOP-CONTRACT, INPUT-CONTROLS-CONTRACT, COCKPIT-READINGS-CONTRACT |
| EPIC-P3 | [#4 Complete circuit and durable progress](https://github.com/brettbergin/flight-simulator/issues/4) | EPIC-P2 |
| AIRCRAFT-EVIDENCE | [#28 Freeze exact analog C172S configuration and source applicability](https://github.com/brettbergin/flight-simulator/issues/28) | EPIC-P2, LICENSE-REGISTER, VALIDATION-CORPUS |
| ENGINE-FUEL | [#29 Implement sourced fuel-injected engine and fuel-system lifecycle](https://github.com/brettbergin/flight-simulator/issues/29) | EPIC-P2, AIRCRAFT-EVIDENCE |
| ELECTRICAL-SENSORS | [#30 Implement electrical buses, instrument power and pitot/vacuum sources](https://github.com/brettbergin/flight-simulator/issues/30) | EPIC-P2, AIRCRAFT-EVIDENCE, SIX-PACK |
| CONTROLS-GROUND | [#31 Complete trim, flaps, steering, struts and differential braking](https://github.com/brettbergin/flight-simulator/issues/31) | EPIC-P2, AIRCRAFT-EVIDENCE, GROUND-PROOF, INPUT-PROFILES |
| PREFLIGHT-CHECKLISTS | [#32 Implement walkaround, checklist state and procedural cockpit flow](https://github.com/brettbergin/flight-simulator/issues/32) | EPIC-P2, AIRCRAFT-EVIDENCE, ENGINE-FUEL, ELECTRICAL-SENSORS |
| FLIGHT-PLANNING | [#33 Implement payload, fuel, CG and takeoff/landing planning](https://github.com/brettbergin/flight-simulator/issues/33) | EPIC-P2, AIRCRAFT-EVIDENCE, ENGINE-FUEL |
| LOCAL-PERSISTENCE | [#34 Implement SQLite profiles, migrations, atomic saves and recovery](https://github.com/brettbergin/flight-simulator/issues/34) | EPIC-P2, SAVE-PROOF |
| REPLAY-RESUME | [#35 Implement command replay and verified session continuation](https://github.com/brettbergin/flight-simulator/issues/35) | EPIC-P2, LOCAL-PERSISTENCE, SAVE-PROOF, ENGINE-FUEL, ELECTRICAL-SENSORS |
| ASSIST-PROFILES | [#36 Implement discover, practice and assessment policies with intervention tags](https://github.com/brettbergin/flight-simulator/issues/36) | EPIC-P2, LOCAL-PERSISTENCE, HUD-CAMERA |
| FULL-CIRCUIT | [#37 Validate cold-and-dark to shutdown normal circuit and recovery](https://github.com/brettbergin/flight-simulator/issues/37) | EPIC-P2, PREFLIGHT-CHECKLISTS, CONTROLS-GROUND, FLIGHT-PLANNING, REPLAY-RESUME, ASSIST-PROFILES, BASELINE-PERFORMANCE, PROFILE-SESSION-UI, BASIC-DEBRIEF |
| PROFILE-SESSION-UI | [#74 Implement profile selection, local practice log and retention/export controls](https://github.com/brettbergin/flight-simulator/issues/74) | EPIC-P2, LOCAL-PERSISTENCE, ASSIST-PROFILES |
| BASIC-DEBRIEF | [#75 Implement first circuit event review, basic map and recorded playback](https://github.com/brettbergin/flight-simulator/issues/75) | EPIC-P2, PROFILE-SESSION-UI, REPLAY-RESUME |
| BASELINE-PERFORMANCE | [#76 Validate normal C172S performance before scored maneuver curriculum](https://github.com/brettbergin/flight-simulator/issues/76) | EPIC-P2, AIRCRAFT-EVIDENCE, VALIDATION-CORPUS, ENGINE-FUEL, CONTROLS-GROUND |

| ORIGINAL-PISTON-MODEL | [#125 Publish original piston model and independent reference source](https://github.com/brettbergin/flight-simulator/issues/125) | ORIGINAL-PISTON-CONTRACT, CORE-CONTRACTS, INTERACTIVE-CONTRACT, LICENSE-REGISTER |

## P4 — Regional navigation and environment

| Key | Issue | Dependencies |
|---|---|---|
| EPIC-P4 | [#5 Regional navigation and environment](https://github.com/brettbergin/flight-simulator/issues/5) | EPIC-P3 |
| WORLD-PROVENANCE | [#38 Build dated world-pack manifests and ingestion rights audit](https://github.com/brettbergin/flight-simulator/issues/38) | EPIC-P3, LICENSE-REGISTER |
| GEODESY | [#39 Implement WGS84/ECEF/NED, vertical datum and magnetic conversions](https://github.com/brettbergin/flight-simulator/issues/39) | EPIC-P3, CORE-CONTRACTS, WORLD-PROVENANCE |
| TERRAIN-STREAMING | [#40 Implement bounded offline terrain tiles, LOD and surface queries](https://github.com/brettbergin/flight-simulator/issues/40) | EPIC-P3, GEODESY, GROUND-PROOF, WORLD-PROVENANCE |
| REGIONAL-AIRPORTS | [#41 Build dated KAWO, KPAE and KBFI airport operational packs](https://github.com/brettbergin/flight-simulator/issues/41) | EPIC-P3, WORLD-PROVENANCE, TERRAIN-STREAMING |
| NAV-AVIONICS | [#42 Implement configured COM/NAV, VOR/ILS, transponder and compass](https://github.com/brettbergin/flight-simulator/issues/42) | EPIC-P3, AIRCRAFT-EVIDENCE, ELECTRICAL-SENSORS, GEODESY, WORLD-PROVENANCE |
| MAP-ROUTES | [#43 Implement route planner, map layers and offline cross-country preparation](https://github.com/brettbergin/flight-simulator/issues/43) | EPIC-P3, REGIONAL-AIRPORTS, NAV-AVIONICS, FLIGHT-PLANNING |
| WEATHER-PROFILES | [#44 Implement offline atmosphere, winds, pressure and weather presets](https://github.com/brettbergin/flight-simulator/issues/44) | EPIC-P3, CORE-CONTRACTS, WORLD-PROVENANCE |
| GUSTS-TURBULENCE | [#45 Implement reproducible spatial gusts, turbulence and bounded shear](https://github.com/brettbergin/flight-simulator/issues/45) | EPIC-P3, WEATHER-PROFILES, FDM-HARNESS |
| LIGHT-VISIBILITY | [#46 Implement daylight/night, clouds, visibility and airport lighting](https://github.com/brettbergin/flight-simulator/issues/46) | EPIC-P3, TERRAIN-STREAMING, WEATHER-PROFILES, RENDER-PROOF |
| REGIONAL-FLIGHT | [#47 Validate offline regional cross-country, diversion and return](https://github.com/brettbergin/flight-simulator/issues/47) | EPIC-P3, REGIONAL-AIRPORTS, MAP-ROUTES, GUSTS-TURBULENCE, LIGHT-VISIBILITY |

## P5 — Lessons, ATC, and debrief

| Key | Issue | Dependencies |
|---|---|---|
| EPIC-P5 | [#6 Lessons, ATC, and debrief](https://github.com/brettbergin/flight-simulator/issues/6) | EPIC-P4 |
| LESSON-CURRICULUM | [#48 Create versioned FAA-reference beginner and returning-pilot lessons](https://github.com/brettbergin/flight-simulator/issues/48) | EPIC-P4, PREFLIGHT-CHECKLISTS, REGIONAL-FLIGHT |
| TRAINING-EVALUATOR | [#49 Implement reproducible objectives, intervention policy and safe scoring](https://github.com/brettbergin/flight-simulator/issues/49) | EPIC-P4, LESSON-CURRICULUM, ASSIST-PROFILES, REPLAY-RESUME |
| ATC-RADIO | [#50 Implement deterministic ATC/CTAF phraseology and clearance state](https://github.com/brettbergin/flight-simulator/issues/50) | EPIC-P4, REGIONAL-AIRPORTS, NAV-AVIONICS, LESSON-CURRICULUM |
| AI-TRAFFIC | [#51 Implement seeded pattern/ground traffic and separation encounters](https://github.com/brettbergin/flight-simulator/issues/51) | EPIC-P4, ATC-RADIO, WEATHER-PROFILES |
| DEBRIEF | [#52 Build timeline/map/replay debrief tied to objective observations](https://github.com/brettbergin/flight-simulator/issues/52) | EPIC-P4, TRAINING-EVALUATOR, ATC-RADIO, AI-TRAFFIC, BASIC-DEBRIEF |
| ACHIEVEMENTS | [#53 Implement honest practice history, goals and safe achievements](https://github.com/brettbergin/flight-simulator/issues/53) | EPIC-P4, TRAINING-EVALUATOR, LOCAL-PERSISTENCE, DEBRIEF |
| INSTRUCTOR-TOOLS | [#54 Implement local instructor controls and qualified curriculum review gate](https://github.com/brettbergin/flight-simulator/issues/54) | EPIC-P4, DEBRIEF, ACHIEVEMENTS |

## P6 — Advanced realism and failures

| Key | Issue | Dependencies |
|---|---|---|
| EPIC-P6 | [#7 Advanced realism and failures](https://github.com/brettbergin/flight-simulator/issues/7) | EPIC-P5 |
| FDM-CALIBRATION | [#55 Calibrate C172S performance across mass, CG and atmosphere](https://github.com/brettbergin/flight-simulator/issues/55) | EPIC-P5, AIRCRAFT-EVIDENCE, VALIDATION-CORPUS, BASELINE-PERFORMANCE |
| STALL-HANDLING | [#56 Validate stalls, coordination, ground effect and crosswind response](https://github.com/brettbergin/flight-simulator/issues/56) | EPIC-P5, FDM-CALIBRATION, GUSTS-TURBULENCE |
| FAILURE-SYSTEMS | [#57 Implement causal engine, electrical, fuel and instrument failures](https://github.com/brettbergin/flight-simulator/issues/57) | EPIC-P5, ENGINE-FUEL, ELECTRICAL-SENSORS, ATC-RADIO |
| DAMAGE-LIMITS | [#58 Implement bounded structural/engine limits and inspectable consequences](https://github.com/brettbergin/flight-simulator/issues/58) | EPIC-P5, AIRCRAFT-EVIDENCE, FDM-CALIBRATION |
| EMERGENCY-LESSONS | [#59 Create reviewed emergency decision and landing practice](https://github.com/brettbergin/flight-simulator/issues/59) | EPIC-P5, FAILURE-SYSTEMS, DAMAGE-LIMITS, STALL-HANDLING, INSTRUCTOR-TOOLS |
| REALISM-REPORT | [#60 Publish full configuration, envelope, source and pilot validation report](https://github.com/brettbergin/flight-simulator/issues/60) | EPIC-P5, FDM-CALIBRATION, STALL-HANDLING, FAILURE-SYSTEMS, DAMAGE-LIMITS, EMERGENCY-LESSONS |

## P7 — Windows release and pilot acceptance

| Key | Issue | Dependencies |
|---|---|---|
| EPIC-P7 | [#8 Windows release and pilot acceptance](https://github.com/brettbergin/flight-simulator/issues/8) | EPIC-P6 |
| WINDOWS-PACKAGING | [#61 Build clean Windows ZIP delivery and simulator release workflow](https://github.com/brettbergin/flight-simulator/issues/61) | EPIC-P6, NATIVE-EXPORT, REALISM-REPORT |
| SAVE-UPGRADE | [#62 Validate upgrade, rollback, incompatible saves and crash recovery](https://github.com/brettbergin/flight-simulator/issues/62) | EPIC-P6, WINDOWS-PACKAGING, LOCAL-PERSISTENCE, REPLAY-RESUME |
| REFERENCE-PERFORMANCE | [#63 Measure reference-PC frame pacing, memory, latency and loading](https://github.com/brettbergin/flight-simulator/issues/63) | EPIC-P6, WINDOWS-PACKAGING, LIGHT-VISIBILITY |
| ACCESSIBILITY-QA | [#64 Validate readable cockpit, UI focus, captions and comfort settings](https://github.com/brettbergin/flight-simulator/issues/64) | EPIC-P6, WINDOWS-PACKAGING, HUD-CAMERA, FLIGHT-AUDIO |
| CONTROLLER-QA | [#65 Validate hardware calibration, reconnect and first-run defaults](https://github.com/brettbergin/flight-simulator/issues/65) | EPIC-P6, WINDOWS-PACKAGING, INPUT-PROFILES |
| CONTENT-SECURITY | [#66 Harden content/save/replay parsing and optional crash reporting](https://github.com/brettbergin/flight-simulator/issues/66) | EPIC-P6, WORLD-PROVENANCE, LOCAL-PERSISTENCE, WINDOWS-PACKAGING |
| SOAK-STABILITY | [#67 Run extended flights, reset/reload loops and failure recovery soak](https://github.com/brettbergin/flight-simulator/issues/67) | EPIC-P6, SAVE-UPGRADE, REFERENCE-PERFORMANCE, CONTENT-SECURITY |
| PILOT-ACCEPTANCE | [#68 Complete returning-pilot feedback and qualified instruction acceptance](https://github.com/brettbergin/flight-simulator/issues/68) | EPIC-P6, SOAK-STABILITY, ACCESSIBILITY-QA, CONTROLLER-QA, REALISM-REPORT |
| RELEASE-CANDIDATE | [#69 Ratify release evidence, signing decision and publish first simulator alpha](https://github.com/brettbergin/flight-simulator/issues/69) | EPIC-P6, PILOT-ACCEPTANCE, WINDOWS-PACKAGING |

## P8 — Validated expansion

| Key | Issue | Dependencies |
|---|---|---|
| EPIC-P8 | [#9 Validated expansion](https://github.com/brettbergin/flight-simulator/issues/9) | EPIC-P7 |
| AIRCRAFT-EXPANSION | [#70 Add a second validated Cessna through capabilities and package contracts](https://github.com/brettbergin/flight-simulator/issues/70) | EPIC-P7 |
| VR-EXPANSION | [#71 Evaluate and implement VR after desktop readability/performance acceptance](https://github.com/brettbergin/flight-simulator/issues/71) | EPIC-P7 |
| REGION-LIVE-DATA | [#72 Evaluate new regions and optional live weather/navdata adapters](https://github.com/brettbergin/flight-simulator/issues/72) | EPIC-P7 |
| INSTRUCTOR-NETWORK | [#73 Evaluate instructor networking and cooperative multiplayer architecture](https://github.com/brettbergin/flight-simulator/issues/73) | EPIC-P7 |
