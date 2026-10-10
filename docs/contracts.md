# Core contracts v1

P1 CORE-CONTRACTS [#11](https://github.com/brettbergin/flight-simulator/issues/11) supplies executable engine-independent interfaces. The checked-in [schema registry](../schemas/registry.json), [native headers](../native/sim_core/contracts/include/flight/contracts/boundaries.hpp) and [original fixture manifest](../tests/contracts/fixtures/manifest.json) define v1. These interfaces support PRD-001, PRD-002, PRD-007 and PRD-034. They do not implement flight dynamics, establish C172S fidelity or prove restoration; later phase gates require measured integration evidence.

## Encoding and compatibility

Every record has an exact `type` discriminator and numeric `schema_version: 1`. Objects reject unknown properties; required fields never receive implicit defaults. SI values are finite binary64 numbers. Tick, sequence, seed, event-sequence and record-count fields are **canonical decimal uint64 strings**: `0` or a nonzero leading digit, no sign/leading zeros/exponent, maximum `18446744073709551615`. Native types use C++ `uint64_t` wrapped in distinct `Tick`, `Sequence` and `Seed` types. Do not pass these wire integers through JavaScript `Number`: values above `2^53 - 1` lose precision.

Schemas use [JSON Schema 2020-12](https://json-schema.org/draft/2020-12/schema) and [Ajv's separate 2020 implementation](https://ajv.js.org/json-schema.html). [validateContract](../schemas/validate.mjs) runs strict shape validation **and** cross-field semantic checks. Consumers must use both stages before decoding; shape validation alone is insufficient. All schema references are preloaded locally; the reserved `.invalid` schema IDs identify records and are never fetched. Validation does not coerce, default, remove fields, modify input or execute content.

C++ headers provide typed in-process records and numerical/command validators; **this deliverable does not include a native JSON codec**. Adapters must implement named fields/discriminators and run the same fixture corpus, rather than serialize C++ memory layout, enum ordinals or variant indices. Untrusted JSON must pass strict wire validation before construction; native helper validation is supplementary, not a complete substitute for every manifest/semantic constraint.

The registry pins exact schema SHA-256 hashes; SHA-256 of its UTF-8 bytes identifies the contract set in sessions/replays. Unsupported versions or a required fingerprint mismatch fail without overwriting input. Since objects are closed, adding fields/discriminators/enum values or changing meanings requires a coordinated new version. Migrations identify source/destination versions, retain originals and supply positive/rejection fixtures. This initial v1 can change during review before consumers ship; after acceptance, changes require a contract PR ahead of consumer PRs.

Stable IDs are bounded lowercase ASCII segments separated by `-`, `_` or `.`. Versions use `major.minor.patch` with optional lowercase prerelease. Hashes are 64 lowercase hex characters. UTC ISO 8601 dates end in `Z`; invalid calendar dates and reversed effective intervals fail. Unknown data uses explicit null/validity status. Transport ranges and sizes are guards, not aircraft operating envelopes.

## Clock, commands and lifecycle

Runtime uses fixed **120 Hz** ticks. Explicit `convergence` purpose allows 60/120/240 Hz for the P1 integration study, not runtime user selection. Tick zero is the initial completed state; commands for tick `t` apply before advancing to/publishing completed tick `t`. Derived elapsed time is `tick / rate`; ticks remain authoritative. Validators allow `max(1e-9 s, 4 * binary64 epsilon * elapsed)` rounding error. Rendering delta never becomes integration `dt`.

`ControlCommand` carries session, target tick, accepted-arrival sequence, registered source ID, authority, typed payload and assistance metadata. Native `CommandGate` rejects wrong session, late commands, duplicate/nonincreasing sequences, invalid axes, unknown controls, and unregistered or self-elevated authority. Rejections do not consume sequence. The host registers source authority and aircraft capabilities; the record cannot grant itself instructor privilege.

Sequence monotonicity is **per source in accepted arrival order**. A future-tick packet arriving first can cause a later-arriving smaller sequence to be rejected; producers must submit increasing sequences even when scheduling different future ticks. Target tick does not replace arrival sequence. The worker owns a bounded queue, future horizon and explicit capacity rejection; acceptance by `CommandGate` does not mean queued/executed and its capacity rejection enum is reserved for consumer reporting.

Within one tick, sort ascending **`(tick, authority rank, source_id, sequence)`**, with `pilot=0`, `avionics=1`, `scenario=2`, `instructor=3`. ASCII source ID is the equal-rank tie-breaker before sequence. Higher authority applies last to a shared channel; arrival order across sources cannot decide outcome. Independent system controls merge by control ID. The complete axes payload replaces the held sample; absent a new applied sample, hold the last one. Disconnect/focus-loss policy generates an explicit recorded replacement, rather than silently neutralizing controls.

| Axis | Range | Positive request |
|---|---|---|
| roll | [-1,1] | Right bank |
| pitch | [-1,1] | Nose up |
| yaw | [-1,1] | Nose right |
| trim | [-1,1] | Nose-up trim |
| throttle/mixture | [0,1] | Closed/idle cutoff toward full/open/rich as aircraft mapping declares |
| left/right brake | [0,1] | Released toward full braking |

These are pilot intent, not guaranteed aerodynamic response. `pitch_to_elevator_trailing_edge_down` returns `-pitch` for a declared model whose positive elevator means trailing-edge down. Never blindly apply it to another model. All control signs require aircraft-specific mapping/provenance and live-model tests in #14. A system command uses a known capability ID and declared boolean or normalized scalar type/range, not an arbitrary JSBSim property write.

`SessionControl` is a separate lifecycle lane pumped at the **current completed boundary, including while paused**. It accepts ordered pause/resume or explicit scales 0.25/0.5/1/2/4. Host ownership and sequences are independent of pilot controls; its tick must equal the completed boundary. `SessionControlGate` can resume while physics is stopped. Accepted changes produce operational events. Scale changes wall-time scheduling budget, never integration `dt`; UI clocks remain separate. #14 owns actual bounded scheduling/backpressure, the architecture's >250 ms overload pause and replay ordering evidence.

## SI units and frames

Public quantities use meters, seconds, kilograms, radians, kelvin, pascals, newtons, amperes and volts. Absolute temperature needs an offset; temperature differences do not. UI adapters convert knots/feet/nautical miles/inches Hg/Celsius/gallons/pounds. Named native conversions distinguish pound mass/force and absolute/delta temperature. Model parameters retain source units and explicit conversion records; a generic double never establishes JSBSim units.

| Frame | Definition |
|---|---|
| Geodetic | WGS84 latitude/longitude radians, ellipsoid height meters |
| ECEF | Double meters: X equator/prime meridian, Y equator/east90°, Z north pole |
| NED | Local X north, Y east, Z down at declared geodetic origin |
| Body | Aircraft X forward, Y right, Z down |
| Render | Godot local X east, Y up, Z south; `(north,east,down)` maps to `(east,-down,-north)` |

`orientation_body_to_ned` is the normalized Hamilton active quaternion **(w,x,y,z)** rotating a body vector into local NED; norm error ≤1e-9. Positive roll lowers the right wing; positive pitch raises the nose; positive yaw turns north toward east. The #14 adapter derives this rotation from checked `GetTb2l`, then normalizes only matrix-conversion roundoff. Pinned JSBSim's raw quaternion uses a passive `GetT` convention: its components represent the public active body→NED rotation without conjugation. A getter's local→body label does not establish component convention. Actual-library yaw+90°, roll+90°, pitch+30° and mixed-vector fixtures compare the public transform with `GetTb2l`. The distinct `QuaternionNedToBody` type describes a mathematical Hamilton active inverse, not an unchecked raw JSBSim tuple. [Pinned quaternion implementation](https://github.com/JSBSim-Team/jsbsim/blob/3b25f25e49b42d0489c04ac805674fc1450ca579/src/math/FGQuaternion.cpp), [adapter mappings](../native/fdm_jsbsim/README.md).

Snapshots include geodetic and ECEF representations of the same point; semantic/native validators reject disagreement >**0.1 mm**. Atmospheric wind vectors point **toward** NED; weather UI wind-from bearings require sign conversion. `velocity_body_mps` is ground-relative body velocity, not air-relative velocity. `angular_rate_body_radps` is body-relative-to-Earth/ECEF rate expressed in body; inertial JSBSim PQR requires conversion. `acceleration_body_mps2` is Earth-relative kinematic acceleration expressed in body, not accelerometer-specific force. #14 documents/tests property mappings and Earth rotation terms.

Per-field origins are explicit: aircraft geodetic/ECEF position locates the instantaneous CG; `center_of_gravity_body_m` and manifest CG-envelope bounds use forward/right/down meters from the fixed authored structural datum S0; a contact's `point_body_m` is an instantaneous-CG-relative body arm. `GetXYZcg` returns structural inches (aft/right/up), so datum CG is `(-X,+Y,-Z)*0.0254`. `StructuralToBody(CG)` is zero and cannot supply that datum position. Independent asymmetric KG/IN inventory fixtures test the backend and conversion at full, half and empty fuel. This clarifies field origins without changing v1 layouts. [Pinned mass mapping](https://github.com/JSBSim-Team/jsbsim/blob/3b25f25e49b42d0489c04ac805674fc1450ca579/src/models/FGMassBalance.cpp).

Instrument values are sensed channels, not a hidden truth snapshot. Normal requires a value; off/unavailable requires null; a failed sensor may retain a frozen value with failure status. Sensor tick cannot exceed publication tick. Avionics definitions bind channel ID to operational meaning (indicated/true speed, true/magnetic heading, MSL/indicated altitude); an SI unit alone is insufficient. Failed sensors never silently substitute GPS/physics truth.

The minimal [geodesy seam](../native/sim_core/contracts/include/flight/contracts/geodesy.hpp) uses [NGA WGS84 constants](https://earth-info.nga.mil/?action=wgs84&dir=wgs84), `a=6378137 m`, `1/f=298.257223563`. Independent analytical cases cover equator, poles, dateline, elevated and mixed45° positions; frame cases cover ECEF→NED cardinal vectors, body rotations and render basis. Earth center/nonfinite input is rejected. Full geoid/MSL, magnetic variation, realization/epoch and world coverage remain #39/P4. JSBSim radial ASL must not be relabeled geodetic ellipsoid height. Render rebasing changes local translation only; physics/navigation keeps absolute doubles.

## Registry and ownership

Every boundary has a local versioned schema, original JSON fixture and named native record in `flight::contracts::v1`.

| Contract | Producer → consumers | Required content |
|---|---|---|
| ControlCommand/v1 | Input/avionics/instructor → sim | Session/tick/sequence/source/authority, held axes/capability control, assists |
| SessionControl/v1 | Session owner → boundary | Ordered pause/resume or wall-budget scale, processed while paused |
| AircraftSnapshot/v1 | Sim → render/audio/instruments/recorder | Clock/time/position/orientation, body motion, config/mass/CG, systems/contacts/validity |
| InstrumentSnapshot/v1 | Sensors/systems → cockpit/HUD | Sensed channel/value/unit/sample tick, latency/filter/power/failure |
| AtmosphereSample/v1 | Weather → sim | Position/tick/seed/model, pressure/absolute temperature/density/humidity, wind/turbulence |
| GroundSample/v1 | World query → dynamics | Explicit ellipsoid datum and valid height/normal/friction/material/world ref or missing reason |
| OperationalEvent/v1 | Sim/world/ATC → debrief | Tick/sequence/source/confidence/content version, typed rejection/system/failure/procedure/clearance/assist/pause/branch/save event |
| SessionManifest/v1 | Session → persistence/replay | Exact build/contract/content hashes, clock/seed/calibration/assists, tick-zero initial state/weather/logs, restore declaration/evidence |
| ReplayHeader/v1 | Recorder → replay | Exact identity/clock/seed/count/log hash, determinism declaration |
| Checkpoint/v1 | Persistence → restore | Session/tick/build/manifest identity, capability/evidence, blobs or reconstruction target |
| TrainingResult/v1 | Evaluator → progress | Lesson/rubric versions, objective/tick/event evidence/assists, completion/invalidity/repeatability |
| AircraftManifest/v1 | Aircraft author → loader | Exact config/serial/POH applicability, model/mapping/provenance, geometry/mass/CG/capabilities/controls/checklists/limit sources/files |
| WorldPackage/v1 | World author → loader | Coverage/antimeridian/datums/conversion reference, sources/hashes/effective interval/magnetic epoch/products/currency/update policy |
| ScenarioManifest/v1 | Scenario author → session | Jurisdiction/prerequisites/content, fixed initial template/weather/seed/clock, objectives/rubric/assists/declarative actions/restarts/evidence/source editions |

Ground normal points from surface into free space: horizontal terrain uses `(0,0,-1)` NED, unit norm tolerance1e-9. Dynamic friction cannot exceed static. Missing/unloaded/datum-unresolved ground has no fabricated elevation. Dynamics owns motion/contact forces; Godot supplies queries and cannot add a second aircraft solver. #16 proves actual callbacks/contact stability.

The separate [stationary provider API v1](../native/world_core/ground/README.md) reuses this wire record without changing its layout or registry fingerprint. Its synchronous caller-thread boundary owns an immutable prepared provider, exact world/surface identity and bounded queries. Known missing data blocks before controls/solver/clock mutation; an unexpected callback failure during integration requires immediate executive disposal, retaining only the prior completed publication. This is fail-closed termination, not solver rollback or ground save/replay support. Actual contact and geometric continuity evidence remains #16.

Channel, system and contact IDs must be unique within their snapshot, including aircraft snapshots nested in initial conditions. Conflicting duplicates fail rather than choosing the first/last record. Training objective IDs must also be unique; a complete result requires at least one observed objective. A world's optional magnetic model must cite a source declared in that world's source list. These rules run in wire semantic validation and the corresponding native helpers.

Published snapshots/events are immutable owned values. Headers depend only on C++ standard library; no Godot/JSBSim/SQLite/UI-owned resources cross boundaries. Worker owns authoritative clock/state/commands, main thread renderer/UI, recorder I/O. Explicit copies or publication buffers establish lifetime; published vectors cannot be mutated. Schema/native bounds limit records but do not prove allocation-free ticks. Queue/lifetime/allocation budgets require consumer measurements.

Core owns clock/units/version lock; aviation identity/config/limits/provenance; world datum/data; persistence migration/replay; product/training rubrics. Consumers jointly review their fixtures. Boundary changes need a contract PR and reviewed compatibility/migration/conformance updates before consumer merges. #14 adds live FDM property/sign/clock tests; #15 bridge/export/codec; #16 ground; #17 save proof; #19 independent aircraft reference validation; #21 calibrated device safety; #39 full geodesy; #44 weather. Passing a schema does not satisfy those gates.

The proposed [simulation facade and render-origin adoption contract](decisions/007-sim-loop-facade.md) specifies synchronous app methods, exact rational wall pacing, pilot-intent admission, copied native readback and separate canonical/render poses for #20. It adds no wire fields or native model/API changes. A merged contract alone does not authorize its consumer or accept P1/P2, terrain streaming, aircraft fidelity or human qualification.

## Content, session and save policy

All initial fixtures are **original synthetic prototype** examples: no bundled JSBSim C172 model, copied POH, real airport, validated aircraft envelope, current nav data or accepted restore proof. A future fuel-injected analog C172S requires exact serial/configuration/POH provenance; it cannot inherit identity/fidelity from the supplied carbureted C172P model. Sources, evidence status and report references are declarations requiring specialist review.

Manifests include source revision/applicability/rights/license/hash/effective interval and evidence status. Nonprototype evidence needs report IDs; local source IDs must resolve. Model/mapping paths must appear in files. Duplicate IDs/paths and reversed mass/CG bounds fail. Orthometric data requires a conversion reference; antimeridian crossing is explicit. Content path/size checks are strict, but validating a manifest grants no rights and does not verify actual referenced bytes.

Pack paths are bounded ASCII relative slash paths with no empty, `.`/`..`, drive, leading slash or backslash segments. V1 allows JSON/XML/GLB/PNG/JPEG/WebP/OGG/WAV/BIN/TIFF; excludes DLLs/executables/scripts/scripted scenes/SQL. XML/GLB/binary readers need separate parser/resource review: extension checking is not a sandbox. Content installation must enforce archive/decompression/count limits, filesystem containment, no symlinks/aliases, actual file hashes and approved redistribution rights. `reference-only`/`pending` rights do not authorize shipping. Code plugins are reviewed compiled dependencies, never downloaded content.

Session hashes/identity are mandatory. Branches use new session IDs plus parent events. Visible position is never a complete restore. Supported restore declarations need evidence IDs; complete checkpoints need hidden-state blobs; replay reconstruction must target exactly the saved tick. These reject inconsistent declarations but do not prove continuation. #17 must measure hidden solver/engine/weather/contact restoration or reconstruction, then ratify the capability. Same-build numerical tolerances/fingerprints do not promise cross-platform bit identity.

Profile/results/settings are separate from flight logs/blobs and use transactional SQLite migration. Incompatible/corrupt inputs fail intact. Native persistence resolves Windows Known Folder `FOLDERID_LocalAppData` to `%LOCALAPPDATA%/FlightSimulator/` and shares that root with client; portable install is read-only. Default roaming Godot `user://` is not this contract. Training results cannot reverse evidence ranges, mark unobserved objectives complete or claim invalid without reasons. Achievements cannot modify physics or erase assists.

## Verification

From repository root:

```text
npm ci --ignore-scripts --prefix schemas
npm --prefix schemas run check
node --test tests/contracts/schema.test.mjs
cmake -S tests/contracts -B build/contracts
cmake --build build/contracts --config Release
ctest --test-dir build/contracts -C Release --output-on-failure
node tools/check-docs.mjs
```

Tests are also a standalone CMake project; #12 integrates `flight_contracts` (alias `flight::contracts`) and `contract_boundary_tests`, CTest `contract_boundary`. Checks remain enabled in Release (no disabled `assert`); MSVC uses `/W4 /WX`, other compilers warnings-as-errors. Ajv8.20.0/ajv-formats3.0.1 are exact lockfile-pinned MIT development dependencies, not simulator runtime dependencies. Schema/fixture generators provide read-only `--check`.

The schema suite checks all14 boundaries/hash fixtures, incompatible/unknown payloads, uint64 overflow/round-trip, finite/range/frame/clock invariants, sensed availability, terrain missingness, session identity/restore declarations, content paths/effective intervals/source references and result completeness. Native tests independently check SI constants/strong frame types/WGS84 analytical values/quaternion/control signs, fixed ticks/pause/resume/scale, ordering/authority/duplicates and state validity. These headless offline checks load no aircraft data or pilot profiles and make no FDM or aviation-validity claim.

## Pilot input preset and calibration seam

[ADR008](decisions/008-input-presets.md) defines the proposed copied preset/raw/mapper interface before [#21](https://github.com/brettbergin/flight-simulator/issues/21) consumers; it becomes normative after [#116](https://github.com/brettbergin/flight-simulator/issues/116)'s contract PR merges. Input mapping owns pilot intent only, with one selected source per axis, paused calibration and generation-safe takeover. The flight facade retains native clock/admission/pause authority. Explicit user-selected preset interchange preserves ADR004 SQLite settings ownership; it adds no automatic profile store or native/wire schema. Current mixture capability remains1, and actual hardware/phase acceptance stays separate.

## Native-truth cockpit reading and scan seam

[ADR009](decisions/009-cockpit-readings.md), proposed by [#119](https://github.com/brettbergin/flight-simulator/issues/119), defines copied binary64 SI readings from the verified facade Readback and view-only scan focus before cockpit consumers. It reuses full v1 validation, preserves canonical tick identities and explicitly marks unavailable/singular/historical data. This original prototype seam does not supply InstrumentSnapshot sensors, C172 geometry, power/failure/lag, native or input authority, or phase acceptance. Consumers wait its checked contract merge and checked [PR118](https://github.com/brettbergin/flight-simulator/pull/118) controls delivery.

## Original piston profile extension

[ADR010](decisions/010-original-piston-profile.md), proposed by [#122](https://github.com/brettbergin/flight-simulator/issues/122), adds a distinct opt-in original cold-engine profile while retaining legacy identity/default/fixtures and public wire v1. It specifies strict boolean system commands, movable axes-only mixture, native shaft/system observations, fuel/solver chronology, exact InputPreset/v2 migration and capability-qualified facade/mapper/status values. Consumers wait both the checked contract and independently frozen original model/parameter/reference package. Starter release is recorded before a resumed solver step; UI never fabricates engine truth. C172S source applicability, injected-system realism, electrical/sensors, actual hardware/pilot and phase gates remain separate.

[ADR014](decisions/014-event-aware-shaft.md), proposed under existing [#127](https://github.com/brettbergin/flight-simulator/issues/127), keeps the deployed third wind selector and adds a fourth profile selector. It specifies an opt-in held-power angular method following failed startup convergence, exact no-op/stopped-shaft semantics, independent source-only references and a separate modified-library/source archive identity. Mathematical contract acceptance does not authorize output before exact patch, stable operations, packet and trial criteria are independently reviewed and ratified. Existing default method, legacy aircraft bytes, numerical prototype parameters, historical 55-reference bytes and physical budgets remain unchanged. A separately checked piston-loader format correction is required before coupled consumers; its previously observed failures belong to the corrected source binding.

## Transient pointer engine-control seam

The proposed [ADR017 pointer extension](decisions/017-frontend-pointer-engine-controls.md), [#157](https://github.com/brettbergin/flight-simulator/issues/157), specifies transient mouse ownership for six original engine controls through the existing mapper. Complete Raw validation and conflict admission precede mutation; requested intent and native-held feedback stay separate. It changes no preset, native or wire schema. Qualified [#127](https://github.com/brettbergin/flight-simulator/issues/127) delivery and this contract's checked merge precede [#158](https://github.com/brettbergin/flight-simulator/issues/158) consumers.

## Bounded observed flight review seam

[ADR011](decisions/011-observed-flight-review.md), proposed by [#132](https://github.com/brettbergin/flight-simulator/issues/132), defines one copied in-memory recording and a paused read-only path/timeline review. Two-hertz target sampling retains actual native ticks and explicit lateness/gaps; efficient decimal arithmetic preserves uint64 order. Scene-owned pause/discard/reset admission keeps review separate from physics, input, origins and camera. These private app values leave public schemas and durable replay/persistence contracts unchanged. Consumers wait for the checked contract merge; aircraft, pilot and phase gates remain separate.

## Explicit recorded-review interchange seam

[ADR012](decisions/012-observed-review-interchange.md), proposed by [#136](https://github.com/brettbergin/flight-simulator/issues/136), defines exact bounded guest Save new review/Open semantics before consumers. Schema-qualified binary64 tags, canonical tick strings, strict UTF8/JSON and an exact payload digest preserve historical observations. The scene owns verified pause and isolated imported review; new-file local NTFS creation never overwrites an existing target. ADR004 automatic storage and public wire contracts remain unchanged. Consumers wait for the checked contract and their own delivery gates; profiles, resume, aircraft/pilot and phase acceptance remain separate.

## Synthetic steady-wind start seam

[ADR013](decisions/013-steady-wind-starts.md), proposed by [#140](https://github.com/brettbergin/flight-simulator/issues/140), defines closed initialization-only Calm/from-north/from-west/from-east choices for the existing combined prototype. Checked native setup and published weather drive source-qualified wind cues; draft choices cannot alter a current flight. It preserves original model/world/seed/rate, public schemas and recorded-review versions. Native signs, trim, deterministic repeats, scene admission and new-build package/visual evidence remain separate consumer gates. Saved reviews do not retain wind setup or resume a flight; real weather, C172/hardware/pilot and phase acceptance remain open.

## Source-law coupled shaft correction

[ADR015](decisions/015-source-law-coupled-shaft.md) defines the closed internal `event_aware_coupled_midpoint_v1` method, owned source frame, public engine/fuel chronology and schema-3 corresponding-source variant for [issue149](https://github.com/brettbergin/flight-simulator/issues/149). It preserves the legacy default, held-power method, public wire layouts, actual public tick rate, existing aircraft parameters and original physical/convergence limits. The [reference design](evidence/P3/coupled-midpoint-reference-design.md) separates exact discrete algebra, continuous-law consistency and source coefficient construction. Implementation, prospective arithmetic budgets, strict source compilation, original coupled trials and runtime adoption remain separate gates.

## First-flight briefing and optional circuit reference

[ADR018](decisions/018-first-flight-briefing-and-circuit-aid.md) defines a bounded paused briefing over three existing starts, copied remap-aware hints, and an optional original synthetic runway36 circuit reference. The scene retains pause/discard/adoption authority; first-flight selections end paused at tick0. A pure geometry view supplies an ordinarily clipped map layer and a separate full fixed schematic. No aircraft commands, procedures, evaluation, preset actions or recording formats are added. Disjoint briefing and guide leaves may proceed after this contract and issue158 are accepted, then join in one cohesive dependency-group PR with both leaves' evidence and integrated lifecycle checks. Broad P1/P2, source, hardware and pilot gates remain open.

## Ordinary flight overlay layout

[ADR019](decisions/019-ordinary-flight-overlay-layout.md), [#177](https://github.com/brettbergin/flight-simulator/issues/177), proposes Scene-owned fixed docks, a copied piston-feedback rectangle and a separate full-view manual-summary admission/accessor. Original permissive current geographic route admission and ADR017 gestures remain unchanged. Persistent remapped release guidance survives collapsed/absent engine UI and Help off. Its narrow ADR018 presentation supersession accepts no native/readings/preset/schema or saved flag. [#178](https://github.com/brettbergin/flight-simulator/issues/178) waits for checked contract acceptance; [changed-gaze layout #179](https://github.com/brettbergin/flight-simulator/issues/179) remains separate.
