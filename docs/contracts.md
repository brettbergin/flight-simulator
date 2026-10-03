# Contracts to ratify before parallel implementation

These are planning contracts, not existing runtime APIs. P1 produces versioned schemas, a lock manifest, conformance fixtures, and executable boundary tests. Change the document through a contract PR before dependent modules drift.

## Simulation clock and units

The core advances fixed simulation ticks (initial candidate 120 Hz). Commands carry `session_id`, monotonic `sequence`, target `tick`, typed payload, and explicit source. Rendering consumes read-only snapshots and interpolates between ticks. Pause stops simulation time; real-time UI clocks remain separate. Time acceleration scales scheduled ticks, never integration step size. Reject late/invalid command policies explicitly; define pause/resume behavior and overload handling in the integration spike.

Public API uses SI: meters, seconds, kilograms, radians, kelvin, pascals, newtons. The UI converts to knots, feet, nautical miles, inches Hg, Celsius, gallons/pounds only at display/input boundaries. Reference temperature must identify absolute vs delta. Every aerodynamic/engine parameter has source units and a conversion record. JSBSim property mappings are explicit; no implicit mixed-unit defaults.

Use WGS84 geodetic latitude/longitude and ellipsoidal height for canonical position, double-precision ECEF for world position, NED for local navigation, body axes X forward/Y right/Z down, and Godot's renderer axes via a tested named transform. Orthometric airport/terrain elevations use an explicit vertical datum/geoid conversion. Distinguish true/magnetic headings, air/ground-relative velocities, indicated/calibrated/true/ground speed, MSL/AGL/pressure altitude, and wind-from conventions. A render-origin shift must not alter physics or navigation.

## Core boundaries

| Contract | Producer → consumers | Minimum content |
|---|---|---|
| `ControlCommand/v1` | Input/avionics/instructor → sim | tick, sequence, normalized pilot axes or named system control, assistance metadata |
| `AircraftSnapshot/v1` | Sim → render/audio/instruments/recorder | tick/time, position/orientation, body velocities/rates, accelerations, configuration, mass/CG, engines/systems, contact state, validity flags |
| `InstrumentSnapshot/v1` | System models → cockpit/HUD | sensed values, latency/filtering, power/failure flags; no direct truth substitution |
| `AtmosphereSample/v1` | Weather → sim | pressure, temperature, density/humidity policy, 3D wind/turbulence, sample position/time/seed |
| `GroundSample/v1` | World collision service → dynamics | location, datum, surface elevation/normal/friction, validity; terrain ownership and contact algorithm tested |
| `OperationalEvent/v1` | Sim/world/ATC → training/debrief | tick, stable event type, payload, source, confidence, content version; no nondeterministic wall clock scoring |
| `SessionManifest/v1` | Session → persistence/replay | sim/aircraft/world/scenario/schema versions + hashes, seed, calibration/assist profile, initial conditions, commands, snapshot capability |
| `TrainingResult/v1` | Evaluator → progress | lesson/rubric versions, objective observations, evidence ranges, assists, repeatability, incomplete/invalid status |

Flight dynamics owns aircraft rigid-body motion and aircraft/runway contacts. Godot collision geometry is a query service for the aircraft and may drive non-aircraft scenery animation; it must not apply a second aircraft force solver. Instrument needles and engine sounds read simulated systems, including failures. Navigation/ATC/evaluation must use the appropriate sensed/operational information, rather than grant pilots hidden truth.

## Content manifests

Aircraft manifest: stable id/version, exact airframe/engine/propeller/panel configuration, geometry/mass/CG envelopes, configuration-specific checklists/limits, JSBSim model mapping, asset references, units, citations/rights, evidence status (`prototype`, `reference-reviewed`, `validated`) and compatible core schema.

World manifest: coverage bounds, coordinate/vertical datums, source providers/versions/checksums/licenses, effective dates, elevation/vector/airport/navaid products, magnetic model epoch, optional imagery permissions, update policy, synthetic vs historical status, and scenario closures separate from permanent airport data.

Scenario manifest: id/version/jurisdiction, prerequisites, aircraft/world requirements, fixed starting conditions, weather/seed, traffic/ATC scripts, objectives/rubric, allowed assists, failure schedule, restore points, and debrief evidence requirements. Scenarios reference published source editions without embedding restricted text.

Asset packs use bounded declarative formats. Validate schemas, sizes, paths, checksum and license manifest before install; reject traversal, malicious archives, invalid numeric domains, and unsupported versions. Code plugins are built/reviewed separately; content packs cannot load arbitrary native DLLs or scripts.

## Persistence and replay guarantees

Separate practice profile/history from full flight state. SQLite commits profile/results/settings transactionally; replay files may be larger independently checksummed assets referenced by the database. Stable IDs and schema migrations are required. Never overwrite a corrupt original during repair. Newer incompatible formats fail clearly and leave originals intact.

Command-log deterministic replay within an exact build/content/seed is the minimum. Cross-platform bit-identical results are not assumed; document quantitative tolerances and fingerprints. Exact mid-flight restoration must serialize hidden integration/engine/weather/contact state or reconstruct it through verified replay. If JSBSim state capture fails the proof, provide replay-from-start/checkpoint reconstruction and named safe restart points; do not call visible-position teleport a full restore.

## Ownership and evolution

Core integrator owns schema/units/clock; aircraft/avionics specialist owns airframe definition; world specialist owns geodesy/data; persistence specialist owns migrations/replays; product/training owns evaluation rules. Each owns its boundary fixtures jointly with consumers. Version schema-breaking changes explicitly, supply migration/conformance fixtures, and schedule consumer PRs after the contract PR merges.
