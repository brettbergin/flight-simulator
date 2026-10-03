# Aircraft realism and validation

Status: design baseline, 2026-10-03. Requirement IDs in this document are stable work references. Numerical targets marked **proposed** are project acceptance criteria, not certified-device tolerances or aircraft operating limitations.

## The aircraft we will build first

Build one **Cessna 172S, fuel-injected, fixed-pitch propeller, fixed tricycle gear, conventional analog instrument panel** configuration. Internally identify it as `c172s-analog-v1`. This is a configuration selection, pending an identified model year, serial applicability, equipment list, POH/AFM revision and avionics supplements. Do not label a generic 172 model as an exact aircraft. C152, other 172 variants and C182 become separate aircraft packages after this profile passes its evidence gates.

The [manufacturer's current Skyhawk page](https://cessna.txtav.com/en/piston/cessna-skyhawk) describes an IO-360-L2A engine, a fixed-pitch propeller and G1000 NXi avionics. That confirms the aircraft family and distinguishes the current product from our proposed analog panel; its headline performance numbers do not establish the operating envelope of the selected historic configuration. [Textron 1View](https://txtav.com/en/apps) provides access to flight and technical documents. Exact aircraft documents and rights to use derived data remain an acquisition task.

**REAL-001 — Variant provenance:** every operating limitation, checklist action, performance table, instrument marking and system-specific failure must point to the applicable source section/revision. Specify installed engine, propeller, instruments, electrical equipment and optional equipment. Reject a carburetor-heat control or carburetor-icing lesson for this fuel-injected baseline; alternate induction-air behavior is variant-specific. Reject copying a 172N, 172R, G1000 172S or C182 limitation into this package without applicability evidence.

**REAL-002 — Evidence status:** attach `synthetic`, `estimated`, `source-derived`, or `validated` to each data group. A public-domain generic model can support engineering prototypes; it must display its provisional status. An agent may not resolve a missing coefficient by silently describing it as manufacturer data. Preserve available work while documenting the unresolved fidelity item.

## Flight dynamics requirements

| ID | Required behavior | Evidence and test approach |
| --- | --- | --- |
| REAL-003 | Six-degree-of-freedom motion with mass, CG and inertia changing with payload and fuel | Unit/frame contract; mass inventory; reference acceleration and torque cases |
| REAL-004 | Lift/drag/moments vary with angle of attack, sideslip, flap setting, density and control deflection | Curves with provenance; trim grid over weight, altitude and configuration |
| REAL-005 | Adverse yaw, coordination, dihedral response, stability, slip/skid, stall onset and recovery | Signed step inputs; qualitative pilot review plus recorded traces |
| REAL-006 | Propeller thrust/drag and engine torque respond to RPM, throttle, mixture, density and airspeed | Engine/propeller map tests; steady cruise/climb and windmilling cases |
| REAL-007 | P-factor, torque, slipstream and applicable gyroscopic effects influence low-speed/high-power handling | Directional trend tests; do not substitute arbitrary rudder bias |
| REAL-008 | Ground effect changes the flare and takeoff transition continuously | Height sweep; compare behavior at consistent mass/configuration |
| REAL-009 | Stall depends on aerodynamic state; load factor and bank affect margin | Coordinated/uncoordinated tests; high/low mass; forward/aft CG |
| REAL-010 | Tire, strut, brake, nosewheel steering and runway contact produce credible taxi/takeoff/landing | Braking/coasting tests; crosswind ground handling; no invisible runway attraction |
| REAL-011 | Wind field, gusts, shear and turbulence act on air-relative motion | Identical wind drives windsock, aircraft, weather presentation and traffic |
| REAL-012 | POH envelope, structural/engine damage and overstress have reproducible consequences | Boundary tests with resettable damage; limit exceedance trace records |

Normal pitch/roll/yaw controls must not command an attitude or path directly. Assistance is an explicit input layer with its own recorded status. Ground collision must never supply aerodynamic lift. Camera shakes and sound effects must not masquerade as forces.

Store position in geodetic/global coordinates with an explicitly defined local physics frame. Use SI in the simulation kernel and typed conversions at aircraft-data and display boundaries. Define body axes, rotation ordering, NED/ENU conversion, angular units, positive control direction and wind convention once. IAS, CAS, TAS, ground speed, pressure altitude, indicated altitude, geometric altitude, MSL and AGL are distinct quantities. AGL queries include terrain and the selected reference point; radar-altimeter readout is not invented for an aircraft without that instrument.

Use a fixed simulation step and render interpolation. A proposed initial dynamics rate of 120 Hz is subject to integration stability and CPU profiling; faster substeps are permitted for contact or validated aircraft needs. Seed stochastic processes and keep authoritative clocks independent of frame rate. Do not promise bit-identical cross-platform floating-point replay: exact replay is tested on the same supported build/platform, while cross-build comparison uses documented tolerances and replay compatibility flags.

## Systems, instruments and cockpit

| ID | Deliverable | Observable consequences |
| --- | --- | --- |
| REAL-013 | Two fuel tanks, usable/unusable quantities, selector, shutoff, vents, pump and applicable fuel-feed paths | Consumption, imbalance where applicable, starvation, contamination and quantity indications follow the selected system |
| REAL-014 | Fuel-injected piston-engine startup/run-up/shutdown model | Cold/hot/flooded starts, starter duty, magnetos, spark/combustion, oil pressure/temperature, leaning, fouling and loss of power are sourced and causal |
| REAL-015 | Battery, alternator, buses, breakers, avionics switch and loads | Current/voltage and load shedding matter; battery depletion affects the correct instruments/radios |
| REAL-016 | Pitot-static, vacuum and instrument sources applicable to the analog panel | Blocked ports, pitot heat and suction faults produce instrument-specific indications; sensor truth is not displayed directly |
| REAL-017 | Mechanical flight controls, trim, flaps and brakes | Deflection/rate limits and flap transit; trim changes equilibrium and control demand; left/right toe brakes work independently |
| REAL-018 | Working six-pack and engine instruments, magnetic compass, COM/NAV, transponder and audio panel | Knobs, tuning, OBS/CDI, ident, modes, lighting, flags, lag, compass errors and calibration reflect installed equipment |
| REAL-019 | Interactable preflight and cockpit | Fuel/oil inspection, contamination check, control movement, chocks/tiedowns, doors, belts and parking brake have state; checks can discover discrepancies |
| REAL-020 | Acoustic/visual cues grounded in aircraft state | RPM/load-dependent sound, stall warning, airflow, vibration, radio interference and night lighting; captions and volume controls |

The first release need not implement every deterioration mechanism. Each capability matrix cell states **implemented**, **simplified**, or **unsupported**, with an explanation. Scenarios cannot require an unsupported system. For example, if electrical load shedding is simplified, do not score the user as having mastered a detailed alternator-failure procedure.

**REAL-021 — Cockpit fidelity:** instrument artwork, needle scale, markings, placement, view position and sight picture receive independent review. At the supported default display/FOV, required gauges and runway alignment cues must be readable. Windows input profiles include keyboard/mouse and gamepad at first play, followed by USB yoke/stick/throttle/rudder support with calibration, dead zones, reversible axes, disconnect handling and saved bindings. Hardware without force feedback cannot reproduce actual control forces; document that limitation in the fidelity report.

**REAL-022 — Aircraft expansion:** packages expose geometry, force model configuration, systems graph, instrument source bindings, limitations, checklists, sounds and lesson compatibility. Fixed-pitch versus constant-speed propeller, carbureted versus injected engine, fixed versus retractable gear and analog versus glass avionics are capabilities, not aircraft-name conditionals scattered throughout the game. A later C182 package owns propeller/engine-management differences and its own evidence.

## Quantitative acceptance framework

Separate three questions: does software calculate correctly; does the configured model agree with defensible aircraft evidence; and does a pilot handle it credibly? Passing one does not establish the others.

**REAL-023 — Proposed engineering targets**, to be finalized after reference acquisition:

| Measurement | Proposed acceptance | Required setup |
| --- | --- | --- |
| POH interpolation/conversion | Reproduces table nodes within rounding; automated interior and out-of-range tests | Same definitions/units; explicit treatment of prohibited extrapolation |
| Trimmed cruise TAS | Within 5 kt of applicable reference | Stabilized, specified weight/CG, pressure altitude, temperature, power, mixture and configuration |
| Steady climb rate | Within greater of 10% or 75 ft/min | Applicable climb table, stated speed/power and atmosphere |
| Stall reference speed | Within 3 kt in the correct IAS/CAS domain | Same weight, CG, flap state, power and deceleration procedure |
| Takeoff/landing distance | Within 10% of reference under reproducible standard technique | Same runway surface/slope/wind, mass, density, braking, crossing height and reference endpoint |
| Fuel flow | Within greater of 5% or 0.5 US gal/h | Validated operating point, stated mixture procedure |
| Instrument display versus sensor | Within display resolution plus specified lag/model error | Healthy instrument; errors are separate intentional fixtures |
| Frame-rate independence | Under 1% difference in scalar maneuver endpoints at 30/60/120 render FPS | Identical fixed-step build, inputs, seed and contact conditions |
| Save/resume continuity | Same supported build reproduces serialized discrete state; continuous state meets documented round-trip tolerance | Fuel, damage, buses, weather, traffic, ATC, clocks and RNG included |

These are candidate product gates, not sourced C172 facts. Tighten targets where evidence supports it; relax only through a reviewed decision explaining data uncertainty and training consequences. A POH often specifies static performance without the derivatives necessary to identify the complete aerodynamic model. Record that gap instead of claiming full aerodynamic validation from a handful of table matches. No numeric target permits the wrong response direction or a dangerous procedure.

**REAL-024 — Maneuver evidence:** record takeoff, rotation, climb, cruise, descent, approach, landing, go-around, slow flight, stalls, steep turns, slips and crosswind recovery at multiple masses/CGs and atmospheres. Evaluate each within the supported envelope. Spin entry/recovery and severe icing need dedicated evidence and review before scored handling instruction. An unsupported edge of the envelope is visibly labeled; it is not a blank check to teach recovery technique.

**REAL-025 — Reference matrix:** each row contains aircraft package/version; source ID, section and revision; test method; initial conditions; control script; build/hash; hardware/input profile; observed trace; uncertainty; threshold; result; reviewer and date. Distinguish ground roll from distance over an obstacle and IAS from CAS. A developer cannot calibrate with one definition and test against another.

## Pilot and instructor review

**REAL-026:** invite the user's father to optional structured sessions: cold start/run-up, straight-and-level trim, pattern and landing, crosswind/go-around, and one system-failure scenario. Record specific observations such as excessive float, incorrect rudder demand or unreadable needle markings. His familiarity is valuable qualitative evidence; it cannot substitute for source acquisition or instrumented comparisons. Accessibility adjustments stay independent of aerodynamic realism.

**REAL-027:** a currently qualified instructor familiar with the modeled configuration should review scored instruction and abnormal/emergency content before it is promoted as training content. Capture scope and configuration reviewed; budget and availability are open risks. If a reviewer is unavailable, publish those lessons as unreviewed previews and withhold mastery claims. Learning transfers must be discussed with an actual instructor.

**REAL-028:** preserve a release fidelity report listing supported operating envelope, reference coverage, known mismatches, peripheral limitations, subjective reviews, unsupported functions and data provenance. A release cannot inherit a previous validation result after a relevant physics/system/lesson change without impact analysis and selected regression runs.

## Required test layers and first evidence gate

1. Unit tests: units/frames, atmosphere, mass/inertia, instrument transforms, engine/fuel conservation and boundary cases.
2. Headless integration: deterministic control scripts, steady-state performance, failure propagation, collision and time stepping.
3. Content validation: references, equipment applicability, checklists, limitations and executable scenario conditions.
4. Visual/audio checks: analog readability, markings, night visibility, stall/radio cues and accessibility.
5. Pilot evaluation: controlled sessions tied to measurable reports, followed by corrections and focused regression.

Before aircraft work begins, land a source manifest schema and acquire or explicitly defer the applicable documents. Before the first credible normal-flight release, populate at least takeoff, climb, cruise, stall and landing reference rows. Before emergency lessons, validate the required causal systems and content. These gates are tracked through the phased roadmap and the issues that reference these IDs.

The [FAA Pilot's Handbook of Aeronautical Knowledge](https://www.faa.gov/regulations_policies/handbooks_manuals/aviation/phak) supplies background on aircraft systems, instruments, performance and human factors. The [Airplane Flying Handbook](https://www.faa.gov/regulations_policies/handbooks_manuals/aviation/airplane_handbook) supplies maneuver context. Use current addenda from the [handbook index](https://www.faa.gov/regulations_policies/handbooks_manuals/aviation). They inform lesson research; the exact aircraft POH/AFM controls aircraft-specific procedures and limits.
