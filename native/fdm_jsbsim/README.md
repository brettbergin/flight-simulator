# P1 authoritative headless dynamics

Issue #14 implements the native JSBSim adapter and an offline scenario runner. This is an original synthetic numerical aircraft, with no C172S calibration or playable cockpit. P1's export, ground, persistence and independent reference gates remain separate. [Public contracts](../../docs/contracts.md), [model rights](../../third_party/licenses/evidence/original-synthetic.md), [test evidence](../../tests/fdm/evidence.md).

## Build and run

Use the [accepted pinned bootstrap](../../tools/bootstrap/README.md). On Windows:

```powershell
./tools/bootstrap/build.ps1 -Python python
npm ci --ignore-scripts --prefix schemas
node tests/fdm/make-transport-fixture.mjs --check
node --test tests/fdm/frontend.test.mjs tests/fdm/integration.test.mjs
node tests/fdm/proof.mjs
```

The proof creates `.local/fdm-proof/{trim,hz60,hz120,hz240,repeat,long}/`: full validated scenario/arrival-order command inputs, private request bytes, authoritative NDJSON, a separate timing receipt and provenance hashes. It also writes `.local/fdm-proof/report.json`. For a custom supported fixture, the development CLI is:

```powershell
node tools/run-scenario/runner.mjs .local/fdm-proof/trim/scenario.json .local/fdm-proof/trim/commands.json .local/my-flight
```

That CLI defaults to ten seconds, longitudinal trim and one sample/second. The imported `runScenario` accepts explicit duration ≤600 seconds, trim mode and integral sample cadence. No Node/Python is required by the portable game: the native library is the in-process runtime API; Node/Ajv is the reviewed development scenario boundary. CLI diagnostics and paths stay in local engineering output, never pilot profiles or game UI.

## Native API and ownership

Link `flight::fdm_jsbsim`; include [session.hpp](include/flight/fdm/session.hpp). A `Session` owns one private executive and is called on exactly one host-owned thread. There is no hidden worker. The Godot host must join its worker before destroying the session or unloading native code. Initialization failures and failed/nonfinite solver steps throw; a failed session cannot publish further state and must be recreated. `close()` is explicit and idempotent; all other operations reject after close.

`SessionConfig` contains immutable typed v1 initial conditions, session/lifecycle source IDs, clock/seed, reviewed model root, SI trim settings and finite capacities. The only installed model in this spike is the frozen `original-synthetic/0.1.0-prototype` inventory. Every referenced XML path, size and SHA-256 is checked natively before JSBSim parses it; external model downloads/scripts/property writers are unsupported. The SHA implementation has independent empty/abc/million-a known vectors. The frontend independently checks the exact inventory and rejects aircraft ID/version/hash mismatches. The scenario's world reference is the schema fixture descriptor only: it has no operational world loader or ground surface.

| Operation | Behavior |
|---|---|
| `register_host_source(id, authority)` | Host assigns trusted authority; received packets cannot register themselves |
| `submit(ControlCommand)` | Validates supported capabilities, session/source/sequence/target and capacity; returns queued/rejected receipt |
| `apply(SessionControl)` | Separate completed-boundary lane remains available while paused; host lifecycle owner only |
| `step_fixed()` | One unchanged solver step; owned aircraft/weather and newly applied commands publish after full validation |
| `advance_wall_budget(nanoseconds)` | Exact integer rational budget, at most32 steps per call; no frame delta enters physics |
| `events_after(sequence, limit)` | Owned bounded event batch; caller retains cursor; scheduler never consumes events |
| `latest_snapshot/atmosphere`, `initialization`, `diagnostics` | Owned samples or immutable initialization recipe; no engine/scene pointers |
| `admitted_command_history()` | Receiving boundary and original admission order, including pending commands |
| `applied_command_log()` | Execution order after successful physics steps; distinct from admission order |
| `accepted_session_controls()` / `event_log()` | Original lifecycle source sequences versus independently sequenced observed events |

Default pending capacity4096 and horizon72000 ticks are bounded. Total admitted/applied command history and event history have a configurable hard cap1..65536; submissions reserve total history before gate mutation. History exhaustion rejects new work without evicting records. Lifecycle/event capacity is checked before changing pause/scale, including automatic overruns. This finite prototype needs a streaming recorder seam before unlimited sessions; no silent discard is supported. CLI duration sets its horizon to the complete bounded run (up to144000 ticks at240 Hz).

Commands apply at their target tick's beginning, and axes hold until replaced. Tick0 is accepted initialized state; tick1 integrates `[0,1/Hz]`. To start a pulse at1 second, target `Hz+1` at each convergence rate. Execution sorts `(tick, authority_rank, source_id, sequence)`, ascending pilot→avionics→scenario→instructor; the final applicable packet wins. Source sequences are monotonic in successful arrival order, independently of scheduling. Thus future seq1/tick500 followed by seq2/tick10 is admissible, and its execution log reverses sequence order. The separate admission log retains this distinction; an execution log alone cannot reproduce gate state.

Pause invokes no solver, fuel, atmosphere or clock advance. Scale `.25/.5/1/2/4` changes future wall budget only. Budget units are `wall_ns * scale_quarters * Hz`, with4e9 units per tick. A debt over250 simulated milliseconds causes an observed `scheduler.overrun` pause with all debt retained. Resume explicitly, then call `advance_wall_budget(0ns)` until debt clears; added wall time is rejected during drain. Debt/capacity exhaustion requires a visible host policy. Restoring scheduler debt, source gates and hidden solver state is not implemented here.

Fresh construction repeats a fixed120-Hz initialization/trim recipe, even for60/240-Hz convergence. Fuel is frozen only through initialization/trim; actual flight consumption is active. The receipt captures requested/accepted conditions, solved controls, explicit trim limits/tolerance/fallback policy, complete seed and its31-bit engine fold, and actual loaded library path/version/compiler/source fingerprint. `simulation/randomseed` is the public pinned seed property; private `SRand` is not called. Fold: `(seed ^ (seed>>31) ^ (seed>>62)) & 0x7fffffff`. No stochastic model is enabled; dry ISA/constant wind and no turbulence are explicit. JSBSim's version string includes build time; full library bytes are separately hashed.

Reconstruction can create a fresh executive and replay original admissions/lifecycle inputs at their receiving boundaries. #17 must prove compatibility/continuation, including outstanding inputs and scheduler state. No `GetVState/SetVState` or visible snapshot is advertised as complete solver serialization. `restore_capability` remains unproven/unsupported for this deliverable.

## SI, frames and control mapping

| Accepted field | Pinned JSBSim source and conversion |
|---|---|
| Geodetic/ECEF position | Instantaneous CG; geodetic latitude/longitude, `GetGeodeticAltitude()*0.3048`, `GetLocation()` feet→meters |
| Requested ellipsoid height | Iteratively invert `SetAltitudeASLFtIC` radial-ASL import until immediate geodetic height residual <1µm; record post-trim height separately |
| Orientation | Checked proper `GetTb2l` row-major matrix→normalized Hamilton active body→NED; canonical nonnegativew |
| Velocity/rate | `GetUVW()*0.3048` is Earth/ground-relative FRD; `GetPQR()` is Earth-relative body rate, not inertialPQRi |
| Acceleration | Convert `GetUVWdot` to SI, then add `PQR × UVW` in SI to get Earth-relative kinematic acceleration in body |
| Mass | `GetMass()` slugs→kg with exact `4.4482216152605/0.3048`; preserve backend conversion rounding as an explicit source budget |
| CG | `GetXYZcg()` structuralIN, fixed S0datum; `(-X,+Y,-Z)*0.0254` gives datumFRDmeters; contact arms will be CG-relative |
| Atmosphere | PressurePSF→Pa with exactlbf/ft², Rankine→Kelvin×5/9, densityslug/ft³→kg/m³; NED wind points toward |
| Pilot roll | Positive→positive `fcs/aileron-cmd-norm`; actual positive right-bank rate response tested |
| Pilot pitch/trim | Positive nose-up→negative elevator/pitch-trim normalized trailing-edge-down commands |
| Pilot yaw | Positive nose-right→negative rudder for this model's original negative rudder yaw coefficient; actual signed response tested |
| Throttle | Absolute0..1 normalized command; mixture must1 and brakes0 until their real systems exist |

The pure acceleration adapter consumes SI framed values, never feet hidden inside SI types. `GetBodyAccel` force/mass is not substituted for kinematic acceleration. The raw engine quaternion components are not conjugated based on getter labels: pinned passive `GetT` and active Hamilton component conventions differ. Actual yaw/roll/pitch/mixed-vector tests establish the mapping, while matrix extraction avoids assuming it. Near-identity output roundoff is normalized after verifying a proper matrix; strict public bounds remain unchanged.

Initial conditions support dry standard atmosphere and constant asymmetric wind. Requested atmosphere must match the backend within1Pa/.02K/.0001kg/m³; humidity/turbulence, nonzero initial acceleration, systems/contacts, other mass/CG, flaps, brake/mixture behavior, assists and authored scenario actions are rejected. Initial snapshot validity must be initializing. Trim can change orientation/velocity/controls; it is explicit in both requested and accepted provenance. Longitudinal trim does not prove zero lateral acceleration. API units and per-field origins are normative in [contracts](../../docs/contracts.md).

Intake guards bound original numerical experiments to initial height100..10000m, ground speed20..200m/s, body-rate magnitude≤2rad/s and wind magnitude≤100m/s. These are overflow/solver-input guards; they are not a validated aircraft envelope or a guarantee that every admitted experiment will trim or remain stable. Failed trim/state fails closed.

Pinned implementation evidence: [quaternion matrices](https://github.com/JSBSim-Team/jsbsim/blob/3b25f25e49b42d0489c04ac805674fc1450ca579/src/math/FGQuaternion.cpp), [propagation state](https://github.com/JSBSim-Team/jsbsim/blob/3b25f25e49b42d0489c04ac805674fc1450ca579/src/models/FGPropagate.h), [acceleration equations](https://github.com/JSBSim-Team/jsbsim/blob/3b25f25e49b42d0489c04ac805674fc1450ca579/src/models/FGAccelerations.cpp), [mass/CG mapping](https://github.com/JSBSim-Team/jsbsim/blob/3b25f25e49b42d0489c04ac805674fc1450ca579/src/models/FGMassBalance.cpp), [initial altitude import](https://github.com/JSBSim-Team/jsbsim/blob/3b25f25e49b42d0489c04ac805674fc1450ca579/src/initialization/FGInitialCondition.cpp), [trim](https://github.com/JSBSim-Team/jsbsim/blob/3b25f25e49b42d0489c04ac805674fc1450ca579/src/initialization/FGTrim.cpp).

## Original model capabilities

Authored geometryS17m²/b10m/c1.7m, empty1000kg plus100kg fuel at S0; original diagonal inertia800/1200/1600slug·ft². No upstream aircraft XML is used. With alpha/beta in radians and air-relative body rates, the six original coefficient functions are:

```text
CL = .22 + 5 alpha                 CD = .03 + .08 alpha²
CY = -.5 beta + .15 rudder
Cl = -.05 beta - .6 p*b/max(2,2V) + .08 aileron
Cm = .02 - alpha - 8 q*c/max(2,2V) - .7(elevator+trim)
Cn = .1 beta - 2 r*b/max(2,2V) - .08 rudder
```

The low-speed denominator's literal2 is in the model's source-feet domain (2ft/s), not SI2m/s. Forces useqS in wind axes (positive drag/side/lift); moments useqSb orqSc in body axes about CG. Original thrust is a2500N ideal turbine wrapper/direct thruster, with source-defined fuel consumption. It is not a piston/propeller calibration. Stall, spin, P-factor, slipstream, carburetor/fuel-injection behavior, aircraft limits/procedures, contacts/taxi/landing, damage, sensors and electrical systems remain unsupported. Alpha limits in XML do not establish a stall envelope. The numerical proof exercises a small10-second pulse schedule and a600-second trimmed run, not an aircraft handling envelope.

Diagnostics v1 are separate engineering records, never extra public AircraftSnapshot fields. They expose tick/session, alpha/beta, dynamic pressurePa, true airspeedm/s, air-relative body rates, aerodynamic body forceN, body moments aboutCG inN·m, positive drag/side/liftN, fuelkg and raw signed normalized control mappings. Backend functions/getters feed these samples; #19 can compare frozen independent equations against these inputs/outputs. They cannot substitute for a validated sensor channel. Every shape/finite bound/context is checked by the frontend; unknown records/fields fail.

## Proof and consumer handoff

CTest exercises actual engine sign responses, cardinal/mixed rotations, nonzero asymmetric wind at initialization/step, rotating-frame acceleration, backend asymmetric CG weighting at three fuel levels, pause/cadence/scale, bounded overrun recovery/history, rejected closed operations and every truncated transport boundary. Node tests reject unsupported wire fields/packages and corrupted receipt/session/clock/seed/order/count/diagnostic output. The proof measures exact same-build telemetry repeatability,60/120/240-Hz endpoint and2-Hz sampled maxima,600-second finite fuel-consuming flight, and cross-build numerical comparison to a clearly labeled observed Windows regression trace. Sampling is not a continuous-time error bound. CI retains per-platform report/traces; it does not assume cross-platform byte equality. Frozen thresholds and honest limits are in [evidence](../../tests/fdm/evidence.md).

| Consumer | Ready seam and remaining acceptance |
|---|---|
| #15 native export | Typed library, replaceable JSBSim linkage, verified three-file model; must prove actual Godot/editor/export controls/shutdown/source replacement/package rights |
| #16 ground | Explicit absoluteCG position and CG-relative contact origins; ground callback/provider and actual contact solver proof still need implementation |
| #17 save/replay | Immutable requested/accepted recipe plus distinct admission/execution/lifecycle history; hidden-state/debt/source-gate reconstruction must be measured |
| #19 validation | Frozen original coefficients and SI diagnostics, asymmetric test-only mass fixture; independent reference corpus/model fidelity remains a separate gate |
| #20 simulation scheduling | Caller-owned API and bounded rational scheduler; threaded host/mailboxes/recorder streaming/interpolation need runtime proof |
