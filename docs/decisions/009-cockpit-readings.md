# ADR 009: Native-truth cockpit readings and scan focus

Status: proposed contract; normative only after its checked contract PR merges. Contract [#119](https://github.com/brettbergin/flight-simulator/issues/119); consumers [#23](https://github.com/brettbergin/flight-simulator/issues/23) and [#24](https://github.com/brettbergin/flight-simulator/issues/24) also wait for checked [PR118](https://github.com/brettbergin/flight-simulator/pull/118) controls delivery. This app seam supports REAL-019, PRD-015 and UX-009/010/011. It establishes no sensor, C172, GLB, hardware, pilot or phase acceptance. Basis: [v1 contracts](../contracts.md), [ADR006](006-interactive-prototype.md), [ADR007](007-sim-loop-facade.md) and [ADR008](008-input-presets.md).

## Decision and ownership

Derive the existing original cockpit's native-truth readings once for its physical dashboard, ordinary overlay and enlarged scan. A small view-only focus control improves readability without changing flight. No new wire record, native field/model, input action, persistence authority, aircraft feedback, artificial lag or powered instrument is introduced. These values are explicitly **NATIVE TRUTH / PROTOTYPE**, separate from sensed InstrumentSnapshot/v1. Contacts and the native-held throttle/brake strip retain their existing source and are not new reading channels.

The reading leaf is pure scalar binary64 arithmetic over owned values. It calls no facade, native, device, clock or scene API. The scene owns the copied input, camera, mapper and render-origin adoption. UI/focus operations belong to the main thread and cannot send pilot intent or lifecycle commands. Preserve the historical proof path; the ordinary scene adopts the shared derivation rather than keeping a second production formula.

## Exact reading API and validation

`NativeReadings.from_readback(readback:Variant)->Dictionary` validates before deriving and returns recursively owned copies. No objects/resources, unknown fields, implicit defaults, float32 Vector3/Quaternion calculations, tick-to-number conversion, or input mutation. Reuse `Wire.aircraft` and `Wire.atmosphere` from `app/simulation/wire_validation.gd` for full bounded v1 shape **and semantic** validation; validating only selected numeric fields is insufficient. Reuse canonical uint64-string checks; never parse absolute ticks into signed int or float.

Validate the entire exact ADR007 Readback shape/types/null relationships, not merely aircraft/weather. Its enum fields, booleans, finite five-value time_scale, nonnegative representable debt, strings and nullable metadata use ADR007 bounds/identities. When present, model_identity/world_anchor/canonical have that contract's closed keys and finite array/rigid rotation checks; canonical ECEF agrees with the aircraft ECEF point. Source fingerprint/hash strings use existing64-lowercase-hex rules. Current publications require the exact ADR006 model/prepared-world identity, native_live=true, historical=false and coherent live/unpaused or paused host flags. The leaf does not query or reconstruct a native executive to establish identity.

Aircraft and atmosphere must be both null or both valid records. A pair must match Readback session_id/tick and each other exactly, including position, and use the accepted runtime120Hz clock. An aircraft validity other than valid, missing required source, malformed/nonfinite v1 record, mismatched pair/identity, invalid metadata or contradictory current flags invalidates the whole result. Do not normalize a bad quaternion or replace missing weather with zero wind. Confirmed closed/terminal historical Readback may retain verified pair/metadata with canonical=null; no render coordinate is needed for these readings. Valid empty closed Readback has no pair and nullable session/tick. Channel-specific fuel absence or Euler singularity below does not invalidate other valid channels.

| Value | Exact keys/types |
|---|---|
| ReadingSet | `session_id:String|null,tick:String|null,state:String,native_truth:bool,readings:Dictionary,error:String`. native_truth always true; state is empty/live/paused/historical/invalid. |
| Channel | `value:float|null,unit:String,valid:bool,error:String`. A valid channel has a finite value and empty error; invalid has null and an explicit nonempty reason. Unit is the fixed unit below, including when unavailable. |

Every output always contains all six ReadingSet keys and all nine named channels. Empty/invalid sets null identity/tick, all channels invalid/null and a nonempty error; invalid never preserves earlier numeric values. Live/paused/historical sets preserve validated canonical decimal tick/session. Historical takes precedence whenever Readback.historical=true or host is closed/stalled/coverage_blocked/discarded; it is never relabeled current. Ordinary pause is current fixed-tick truth. Valid sets have empty top-level error; individual unavailable channels retain their own reasons.

## Source formulas and units

Let q=(w,x,y,z) be the accepted Hamilton active body-to-NED quaternion and v the ground-relative body velocity. Derive V=R(q)v with scalar binary64 coefficients, without intermediate Godot float32 vectors. The three row-major rows of R are `(1-2(y²+z²),2(xy-wz),2(xz+wy))`, `(2(xy+wz),1-2(x²+z²),2(yz-wx))`, `(2(xz-wy),2(yz+wx),1-2(x²+y²))`. World NED uses north/east/down; copied wind/turbulence point toward NED.

| Channel ID | Unit | Exact derivation / persistent display meaning |
|---|---|---|
| tas | m/s | length(V - wind_toward_ned_mps - turbulence_ned_mps); DERIVED TAS, never IAS |
| ground_speed | m/s | hypot(V.north,V.east); GS |
| pitch | rad | asin(clamp(2(wy-zx),-1,1)); Euler attitude native truth |
| bank | rad | atan2(2(wx+yz),1-2(x²+y²)); Euler bank |
| heading_true | rad | atan2(R[1,0],R[0,0]), wrapped to[0,2pi); TRUE |
| ellipsoid_height | m | position.ellipsoid_height_m; WGS84 ELLIPSOID, never MSL/barometric altitude |
| vertical_speed | m/s | -V.down; KINEMATIC VSI |
| body_yaw_rate | rad/s | angular_rate_body_radps.z; BODY YAW RATE, not turn/slip or heading derivative |
| fuel_total | kg | the unique native system id fuel.total with validity valid and quantity kg; copied value |

Heading is unavailable when hypot(R[0,0],R[1,0])<=1e-6; bank is unavailable when abs(cos(pitch))<=1e-6. These dimensionless preselected numerical singularity guards do not model instrument errors. Pitch remains valid; an attitude drawing requiring bank must show unavailable rather than invent a zero bank. Wire validation already rejects duplicate system IDs; do not choose first/last. Missing fuel.total, invalid system validity or a different quantity makes only fuel_total unavailable. Validated wire bounds do not establish an operating envelope.

Any nonfinite derived arithmetic produces an invalid whole ReadingSet, with null channels and an explicit overflow error, rather than saturating or displaying an overflow. Display conversions happen at the final drawing boundary: knots=m/s*3600/1852; feet=m/0.3048; feet/min=m/s*60/0.3048; degrees=rad*180/pi. Pin/test these constants once. Same Readback at different render cadences has the same ReadingSet. No source-specific arcs, V-speeds, IAS/CAS, magnetic compass, RPM, suction, pressure-altimeter setting, sensor failure/power/lag or C172 indication is fabricated. Historical channels can appear only with persistent RETAINED labeling; empty/invalid channels show unavailable, never stale numeric fallback.

## View-only scan API

`ScanPanel.set_readings(value:Dictionary,info:Dictionary)->void` deep-copies the exact validated ReadingSet; exact info keys are `view_name:String,paused:bool,historical:bool,status:String`. Bound strings to128/1024 characters respectively; booleans are actual bool. ReadingSet state governs validity, retention and live/paused labeling. info.historical must agree with state historical; current live requires info.paused=false and paused requires true. Contradictory flags or malformed input clear displayed values and show unavailable/error. The panel cannot infer or modify native pause. It has no facade/mapper reference.

`focus(instrument:String)->bool` accepts only tas, attitude, ellipsoid_height, heading_true, body_yaw_rate, vertical_speed and only while the current ReadingSet is paused with matching info.paused=true; unknown/live/historical/invalid rejects without changing focus. Attitude consumes pitch+bank from one set. `clear_focus()->void` returns to ordinary scan during ordinary pause, and is a no-op during live flight; invalid/empty or a new session clears focus automatically. `focused()->String|null` returns an owned scalar. Focused readings may remain visible after explicit scene-owned Resume; values then follow the same live publications. These methods change presentation only and never obtain pause/resume themselves.

Visible selection/Back/click-outside dismissal operate only in the paused UI. The user first pauses through the existing scene, selects or dismisses, then explicitly resumes through the existing mapper/native gates. During flight, selecting/dismissing requires that normal pause first; Escape keeps its reserved pause/menu meaning. This rule prevents a UI click from simultaneously commanding an explicitly remapped mouse-button flight action. Do not suppress Raw samples or clear mapper edges to hide such a conflict. No new InputPreset action IDs are created; mouse motion never becomes a flight axis.

Root coordinates any whole-panel/outside/side-view eye/FOV choices, capture/release and restoration of the preceding view. Focus/dismiss cannot change native tick/state/held controls, debt, mapper filter/edges/latch, session, raw map, prepared plane or origin registry. Camera and ownship still share ADR007's presentation phase and participant transaction. Enlarged views retain readable status/fault controls; default outside view remains clear. Geometry/view choices are original finite presentation parameters, not manufacturer sight-picture evidence.

## Consumer handoff and evidence

Consumers wait for this contract and checked PR118 merge, with owner-coordinated phase dispatch. Leaf ownership is `app/cockpit/instruments/{native_readings,scan_panel}.gd` and `tests/instruments/`. Root owns scene/physical-dashboard/overlay adoption and camera routing; delivery stages the same leaf and original notices. A compact original `content/aircraft/prototype/cockpit-presentation.json` records exact dimensions, eye/FOV choices, generic procedural status, author/license and source paths. It is prototype provenance, not a new loader schema or GLB acceptance.

Before code observation, prepare independent arithmetic/source fixtures for mixed quaternion/vector/wind, units, horizontal heading, vertical singularity, fuel presence/validity, full uint64 identity, mismatch/unknown fields/nonfinite/overflow, missing-not-zero and historical/closed inputs. Assert copies and no same-tick cadence dependence. Short actual exported views at960x540,1920x1080 and2560x1440 verify all six enlarged/ordinary labels and invalid/retained states, shared dashboard/overlay values, outside runway/horizon and explicit default eye/FOV. Focus/dismiss/view fixtures prove native readback, held axes, debt, map and mapper state unchanged. No native rebuild or long renderer benchmark is needed for this presentation extraction unless an affected failure warrants it.

Contract acceptance closes only #119's seam. #23 GLB/material/animation/export and source-specific cockpit/sight picture, #24 sensed instruments/power/failure/lag, REAL-016/017/018 systems, real hardware/manual pilot review and P1/P2 gates retain their original requirements and separate evidence.
