# P1 synthetic dynamics evidence

Local proof on 2026-10-03: Windows x64, MSVC 19.40.33813.0, `/MD`, pinned CMake 3.31.8/Ninja 1.13.1 and actual shared JSBSim 1.3.1. Native CTest 3/3 passed, including 239 accepted-contract checks and 7680 FDM checks. Node 7/7 FDM boundary tests passed. Per-platform CI repeats these proofs and archives generated traces/provenance. Root review and the other P1 issues remain separate acceptance gates.

The only flight model is the [MIT original synthetic inventory](../../native/fdm_jsbsim/models/original-synthetic/inventory.json), digest `1ccadb2e3d5aefe79f5a8f316631744ab4de18084469d2cf1817fb622cfabf7a`. Its six polynomials, arbitrary inertia and ideal turbine/direct thrust are numerical fixtures. The test-only [asymmetric mass XML](models/aircraft/asymmetric-cg/asymmetric-cg.xml) verifies nonzero weighted structural CG and datum/CG-relative distinctions. No upstream C172 XML, manufacturer calibration, operational airport data or licensing-credit claim belongs to this evidence.

## Repeatability and scheduling

`proof.mjs` ran identical accepted initial recipe, full seed `9007199254740993`, library/build and physical control schedule twice. Canonical complete telemetry matched byte-for-byte on this build. Timing/profiling are separate sidecars and do not enter that comparison. Fresh construction always initializes/trims at 120 Hz, freezes fuel during trim, then runs with its chosen unchanged dt and active fuel consumption.

Native actual-engine tests produce identical final observable state after exactly 1200 ticks under virtual 30/60/120 Hz frame cadence, scales `.25/.5/1/2/4` and mid-flight pause/resume. This proves the scheduler's arithmetic and solver independence from synthetic host cadence; actual Godot render/export/thread behavior remains #15/#20. Overrun tests retain 120 owed ticks, pause before any solver advance, explicitly resume and drain in batches≤32 without discarding time. Finite command/event capacity tests reject before authority/clock/budget mutation.

Original admission order and receiving boundary, pending commands and original lifecycle sequences remain distinct from execution/event order. No complete hidden-state or scheduler save is claimed. #17 must prove fresh-executive reconstruction/continuation from those inputs before ratifying restore capability.

## Convergence

Thresholds were declared before observed traces. Pulses start at physical seconds 1/3/5 and release at 2/4/6; target tick is `seconds*Hz+1`. Roll request `.02`, pitch delta `.025`, yaw request `.04`; other controls preserve solved trim. Samples align at 2 Hz over 10 seconds. This is one exercised numerical schedule, with no continuous-time error bound or real-aircraft envelope inference.

| Quantity | 60vs240 threshold | Observed sampled maximum | 120vs240 threshold | Observed sampled maximum |
|---|---:|---:|---:|---:|
| ECEF position distance | 2 m | .021214875m | .5 m | .007076940m |
| Body velocity distance | .05 m/s | .014685413m/s | .02 m/s | .004831106m/s |
| Quaternion rotation distance | .002 rad | .000355413rad | .001 rad | .000118435rad |
| Body-rate distance | .002 rad/s | .001682087rad/s | .001 rad/s | .000519067rad/s |

Endpoint errors are smaller for velocity/attitude/rates; reports retain both endpoints and maxima so transient cancellation cannot hide error. The 120 Hz baseline passes this synthetic schedule and remains a prototype integration choice; ground/gear/stall/new aircraft need their own convergence evidence.

The checked [Windows trace](reference/windows-msvc-19.40.json) is an **observed numerical regression reference**, not independent aircraft truth. Normal proof never regenerates it; explicit `--capture-reference` is Windows-only and requires reviewed baseline changes. Cross-build/platform sampled budgets are 1 mm position, `1e-5 m/s` velocity, `1e-6 rad` attitude and `1e-6 rad/s` rate. CI compares to this reference numerically; it never assumes platform bit identity. Independent model equations/reference provenance remain #19.

## Ten-minute and mapping evidence

The 600-second trimmed run stayed finite, with guarded speed 20..200 m/s and height 100..20000 m across one-second samples. Mass changed from 1099.999984835kg to 1071.302276301kg; final ellipsoid height 1038.223931213m. Immediate post-trim height was 999.999999970m for a 1000 m request, so later drift is not mislabeled an initialization datum offset. Longitudinal trim does not eliminate every lateral/Earth-rotation term.

Local measured `Session::step_fixed` p50 was 5300 ns, p99 was 12600 ns and maximum 1639100 ns over 72000 steps. Output serialization/Node/rendering/contacts are excluded. This is headless prototype performance on the target machine, not a graphics/runtime guarantee; CI retains its own timing rather than imposing hardware-dependent equality.

Actual library tests establish positive/negative pilot roll/pitch/yaw response; `GetTb2l` matches public yaw+90°, roll+90°, pitch+30° and mixed-vector transforms. A no-trim identity/quasi-identity case preserves strict quaternion component bounds after checked matrix conversion. Nonzero asymmetric wind preserves requested ground velocity and matches `|UVW - NEDwind→body|` true airspeed at initialization and after stepping. Independent nonzero rotating-frame acceleration verifies `UVWdot + PQR×UVW`. A KG/IN mass inventory tests all CG signs/units at 100/50/0 kg fuel; `StructuralToBody(CG)=0` is explicitly different from fixed-datum CG.

Wire/native intake rejects malformed versions, omitted unsupported state/assists/actions, wrong aircraft identity/hash, unauthorized/late/duplicate commands and every truncated private request boundary. Actual output corruption cases cover receipt fuel/controls/weather/source fingerprint, wrong session/clock/seed/tick/order/count and extra/nonfinite/out-of-bounds diagnostics. Full schema validation runs again before provenance is accepted.

## Coverage and limits

| Requirement area | #14 evidence | Remaining gate |
|---|---|---|
| PRD-002/003 authority/repeatability | Fixed-step owned state, bounded input/lifecycle, exact same-build synthetic telemetry and numeric cross-build regression | Real client/thread/device/scenario behavior |
| REAL-003 mass/CG/inertia | Original mass/fuel update, typed SI conversion and asymmetric backend CG algebra | Target C172S loading/inertia/consumption references |
| REAL-004/005 aero trends | Original force/moment polynomial diagnostics and small signed-response/convergence schedule | Independent corpus and real-airframe envelope/stall/handling |
| REAL-006/007 propulsion effects | Ideal thrust/fuel wrapper only; prototype simplification | Piston/propeller/P-factor/slipstream/torque/system calibration |
| Ground/terrain/save/render | Explicit seam origins, owned API and reconstructible input recipe | #16/#17/#15 plus independent exit evidence |

Reproduce with the [adapter commands](../../native/fdm_jsbsim/README.md). Generated raw artifacts remain in ignored `.local/fdm-proof/` and CI evidence artifacts; the [compact local receipt](windows-proof.json) accompanies this document. No phase completion is inferred solely from green CI.
