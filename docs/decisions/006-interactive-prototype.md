# ADR 006: Bounded interactive flight and ground prototype

Status: proposed contract; normative for the new prototype when this prerequisite PR is merged. It does not accept a runtime consumer or close P1/P2. Issue [#95](https://github.com/brettbergin/flight-simulator/issues/95); supports #20 and the pilot-operated exercise in #27. Requirements: PRD-003, PRD-006–007, PRD-015–020 and PRD-033.

## Problem and decision

The accepted flight proof has no usable landing gear; the accepted ground proof is a separate cart without flight aerodynamics. A pilot needs ground movement, takeoff, flight and touchdown under one authoritative solver. Use a **new original combined model**, one prepared synthetic surface and one caller-owned, synchronous native session. Keep the accepted [v1 records and frames](../contracts.md), historical flight/cart models and `FlightProofSession` unchanged. Land this contract, model identity and rights inventory before implementing its native adapter or Godot consumer.

The first consumer is a bounded engineering pilot loop. Production asynchronous queues, additional wire/acknowledgement records and durable combined-state resume are deferred. This decision creates no new wire schema. It also leaves the aircraft source/fidelity, phase-exit, renderer-performance and release gates intact.

## Model and prepared world

The [package inventory](../../native/fdm_jsbsim/models/original-interactive/inventory.json) identifies `original-interactive-prototype`, version `0.1.0-prototype`. Its three XML files are fixed by byte counts and SHA-256 hashes. The airframe is `original-interactive`; package ID and backend model name are distinct. The XML `fdm_config` version `2.0` is a backend format version.

Preserve the original six aerodynamic polynomials, idealized 2500 N turbine/direct-thrust engine, 1000 kg empty mass, 100 kg initial fuel and flight inertia **800/1200/1600 SLUG*FT2**. Add original tricycle bogeys, 150000 N/m spring and 10000 N·s/m compression/rebound damping. Do not substitute the cart's KG*M2 inertia. Structural aft/right/up locations in meters are nose `(-2,0,-1)`, left `(1,-1.3,-1)`, right `(1,1.3,-1)`. Public initial datum-CG-relative forward/right/down arms are `(2,0,1)`, `(-1,-1.3,1)`, `(-1,1.3,1)` m. Nose maximum steering is 30 degrees; only the mains brake. Gear is fixed and flaps are zero. This model has no validated piston/propeller/RPM, stall/spin, systems-startup or Cessna performance claim.

Both named starts use the same stationary **ECEF tangent plane**, anchored at WGS84 latitude `0.8` rad, longitude `-2` rad, ellipsoid height `0` m. Its local north/east resident rectangle is `[-20000,20000]` m in each direction. The congruent north seam is at `20` m, with both tiles loaded. Slopes are zero; material `original.asphalt` has static friction `0.8`, dynamic `0.6`; rolling friction `0.01` comes from the gear XML. Wind and turbulence are zero. This is synthetic geographic geometry, not a real airport or a surface whose ellipsoid height is zero everywhere.

The public [ground provider boundary](../../native/world_core/ground/include/flight/ground/provider.hpp) remains unchanged. World identity is `original.interactive-plane`, version `1.0.0`, generation `1`, with prepared digest **`04bff5a0bcf3509990f6276b2548a28268f57fc96d218a7ca51cab1990ec1ff5`**. The digest is SHA-256 of ASCII `interactive-plane-v1` followed by a NUL, then little-endian IEEE-754 binary64 values in this order: anchor latitude, longitude, height; north/east slope; north minimum/maximum; east minimum/maximum; seam north; static/dynamic friction; finally one byte `1` for the loaded second tile. `world.sha256` and `prepared_data_sha256` are this digest. Unknown geometry, identity, generation or missing data must fail closed.

For a query, intersect its WGS84 geodetic-height ray with the ECEF plane. Return that intersection's ellipsoid height and the fixed ECEF normal transformed into **query-local NED**, with the material friction above. Ground velocity and angular velocity are zero. AGL is query ellipsoid height minus returned surface height. The renderer, runway cues, camera origin and local maps must derive from this exact prepared anchor/plane; the separate renderer proof at height 1000 m is not this world. Godot collision/rigid-body code must not integrate aircraft or gear a second time.

## Two named initializations

Only these starts are supported. Unknown starts, ground plus trim, nonfinite input or different recipe fields reject. Recipe scalar comparisons allow at most `1e-12` in their declared SI units for evaluating the stated constants; this is an intake arithmetic tolerance, not a flight accuracy budget.

| Field | Ground-ready | Airborne prepared start |
|---|---|---|
| Requested CG ellipsoid height | 1.05 m | 1000 m |
| Body forward/right/down velocity | (0,0,0) m/s | (55 cos(0.02), 0, 55 sin(0.02)) m/s |
| Body-to-NED roll/pitch/yaw | (0,0,0) rad | (0,0.02,0) rad |
| Body relative-to-Earth angular rate | Zero | Zero requested before trim |
| Longitudinal trim | Disabled | Explicitly enabled |
| Initial engine | Already running, idle | Already running, solved throttle |
| Initial brakes | Full left/right | Released |
| Fuel | Full 100 kg | Full 100 kg |
| Default seed | 42 | 42 |

These are ready-to-operate engineering starts, not a cold-and-dark/startup procedure. Before allocating a solver, validate the caller-requested CG, all three gear locations and the resident footprint against the prepared source, including positive real surface clearance. The airborne recipe clears this world's surface; ellipsoid height must never be reinterpreted as AGL or MSL.

IC-only conversion may iteratively solve JSBSim's radial-ASL setter to preserve requested ellipsoid CG height. Ground tick-zero height must agree within `1e-5` m. No completed-state ground snap or hidden settling is allowed. Ground settling occurs through visible fixed ticks. Airborne longitudinal trim is an explicit preparation operation with actual resulting state/controls visible; failure rejects initialization. Freeze fuel during IC/trim, then restore consumption. Do not reset a published clock after hidden physics steps.

## Native lifecycle and owned publications

The native implementation owns one JSBSim executive, callback, contact state and held input sample. Every call and destruction belongs to the construction thread. Wrong-thread operations reject before access or mutation; wrong-thread destruction fails fast. Copying/moving a live session is unsupported. Readback returns **owned value copies** of aircraft, atmosphere, held axes, events and fault text; references into mutable worker state do not cross the boundary.

A native session provides initialization, registered-host control submission, lifecycle submission, one-fixed-tick stepping, copied readback, live/paused/time-scale status and owner-thread close. Step outcomes are `completed`, `paused`, `coverage_blocked`, `discarded`. Only `completed` publishes a new aircraft/atmosphere pair. Retained publication after failure is historical truth at its original tick, not a current or resumed live state.

The authoritative snapshot is `AircraftSnapshot/v1`: actual geodetic/ECEF CG, body-to-NED orientation, body motion, mass/fuel and structural-datum CG. It includes `gear.nose`, `gear.left`, `gear.right` contacts with solved newton force, compressed instantaneous-CG-relative body arm and actual WOW from that completed tick. Its matching `AtmosphereSample/v1` has the same session, position and tick with actual pressure/density/wind/seed. Surface identity is pinned by the native prepared world above; do not invent extra snapshot fields in a closed v1 record.

`close` disposes the executive on its owner thread. Reset requires close/join first, a newly constructed session with a fresh ID and the declared recipe. Historical copied publications may remain readable as historical values. Exact combined resume, solver restoration, durable save and source replacement are unsupported; the historical flight-only reconstruction proof does not establish this model's compatibility.

## Input and clock

Use accepted `ControlCommand/v1`, `SessionControl/v1` and operational events. The synchronous caller stamps each actual next simulation boundary and per-source sequence before submitting pilot intent; it must not guess asynchronously from the latest render frame. Native admission rejects wrong session, stale target, invalid payload, duplicate/nonincreasing sequence, self-elevated authority and capacity before mutation. Applied commands retain their actual tick/sequence/history. Canonical accepted ordering and complete held-axis replacement follow [the core command contract](../contracts.md).

The human bridge registers only `pilot.controls` with pilot authority. Host source registration is a trusted native capability, never a user-supplied Godot property API. Proof-only feedback uses visible `scenario.proof` with scenario authority; it is not evidence of unassisted human handling. Only full normalized pilot axes are supported; mixture must equal 1. Arbitrary system/property writes reject. Positive roll/pitch/yaw request right bank/nose up/nose right; elevator and rudder backend mappings negate public pitch/yaw for this model, and yaw also commands nose steering. Left/right brakes are independent. Trim uses the same public nose-up sign conversion. Assists cannot silently change these controls.

Runtime is fixed **120 Hz**. Tick zero is initial completed state; `step_fixed` advances one tick with `dt=1/120` s. Research-only 60/240 Hz is not a runtime user option or a claim of coupled-model convergence. Use accepted clock-purpose and elapsed-time semantics. Caller batches at most 32 fixed steps per presentation frame. Rendering delta never becomes solver dt.

Pause/resume and scales `0.25/0.5/1/2/4` use the owner `session.owner`, exact current completed boundary and independent ordered lifecycle sequence. Accepted operations emit ordered `OperationalEvent/v1` records. Scale changes only caller wall-time pacing; solver dt stays fixed. Pausing leaves tick, held controls and pending input intact. The caller measures monotonic elapsed time and explicitly pauses on a wall stall over 250 ms; it must not enlarge dt or silently discard accrued simulation debt. UI clocks remain separate. The native adapter alone does not implement this wall scheduler.

Pending controls and lifecycle-event history each have a 4096-entry cap; reject before gate/clock/sequence mutation when full. A discard cannot resume. Unsupported assistance metadata or controls reject explicitly. No autonomous asynchronous mailbox or new acknowledgement protocol is introduced.

## Coverage and numerical guard

Before any control/friction/solver mutation, validate the upcoming boundary and sample current CG plus all gear against the immutable provider. For this convex prepared plane only, require a resident horizontal footprint radius

`2.5 m + (150 m/s + 3 rad/s × 2.5 m) × dt + 0.05 m`.

The post-publication admission domain is finite valid v1 state, body speed at most 150 m/s and body angular rate magnitude at most 3 rad/s. Every actual callback horizontal query must lie within the certified footprint; actual post-step horizontal displacement must fit its travel margin. These are tested query/post-step rejection guards, **not a proven continuous trajectory bound or an aircraft operating envelope**. They do not borrow the cart's provisional 400 m/s² acceleration guard.

A known pure missing result returns `coverage_blocked` before mutation, retaining executive, tick, held controls, pending controls and last publication. Provider/identity/malformed-data exceptions or unexpected callback misses terminally discard the executive and preserve only the previous publication. No partial-solver rollback, zero runway fallback, silent retry or resume is allowed. Callback disposal may use a narrowly scoped vendor-Unbind guard, but that path must perform no provider queries, Run or publication.

## Evidence and next consumer

The [source/rights summary](../../third_party/licenses/evidence/original-interactive.md) and [compact proof receipt](../../third_party/licenses/evidence/original-interactive-proof.json) bind the exact original model, unchanged lineage and private executable investigation. The reviewed source fingerprint is `195d899990cd87bbd5b7ddce56ccb846288b4ee64f195b71b0b3d7391c8f5bd0`; frozen packet SHA-256 is `f0aab13a57fe081323228522670f9bf404a2605e8a91b167a9b928544838873d`.

At 120 Hz, scripted takeoff occurred at tick 3755, touchdown at 7182 and all-WOW braked stop at 8916, speed 0.094998056016063329 m/s. Maximum recorded clearance was 32.751314419487798 m. A repeated build/run matched state, atmosphere, command and CSV bytes; 10406 accepted v1 records validated and 1267 native negative/readback checks passed. Independent review reran the actual checks and full loop with matching traces. This is evidence about the private prototype, not an implementation shipped by this contract PR. Large raw traces remain retained investigation artifacts; a future tracked adapter must reproduce them with its own final-source receipts.

The next consumer must implement the reviewed native API over this exact inventory, actual one-solver ground↔air transitions, negative disposal/pause/order tests, and truthful copied v1 readback before connecting human controls. Its renderer must align this prepared plane and emit no second physics authority. A public package must extend model/notice/inventory integrity checks and source/DLL/CRT staging to this new component before distributing it. Human taxi/takeoff/landing, control readability/latency and appropriate packaged runtime evidence remain required in #27. Cessna calibration and normal systems/procedures remain #29/#31/#32; no phase gate is relaxed here.
