# ADR 014: Opt-in event-aware propeller integration

Status: proposed numerical and interface amendment for existing [issue127](https://github.com/brettbergin/flight-simulator/issues/127). Normative only after its independently reviewed contract PR passes protected CI and merges. This contract does not close issue127, authorize consumer observations before the pretrial gates below, or establish aircraft/pilot/phase acceptance. It follows accepted [ADR010](010-original-piston-profile.md) and [ADR013](013-steady-wind-starts.md).

## Problem and source evidence

The original piston candidate failed its frozen startup convergence gates. At 1.1 s the 240 Hz shaft rate was 3.706203744874886 rad/s; the 60 Hz error 0.6861320802971007 exceeded its 0.4318117349318127 budget and the 120 Hz error 0.22790042334652272 exceeded its 0.21590586746590634 budget. At 1.2 s the 60 Hz error 0.6586076961541938 exceeded its 0.6026542957924536 budget. Failed samples, command schedules, model parameters, the original 55-case reference packet and all physical budgets remain unchanged.

The pinned library is JSBSim 1.3.1, commit `3b25f25e49b42d0489c04ac805674fc1450ca579`, acquisition SHA256 `df57467a831cfa3ee3cadcb98d8291ce56bb11976e35dd9e93c94201ff1420d5`. Primary inspected source:

- [FGPiston.cpp](https://github.com/JSBSim-Team/jsbsim/blob/3b25f25e49b42d0489c04ac805674fc1450ca579/src/models/propulsion/FGPiston.cpp), lines 480–529 and 800–818: one engine calculation using pre-propeller RPM, then one propeller calculation; near-zero starter power uses a 1 RPM floor.
- [FGPropeller.cpp](https://github.com/JSBSim-Team/jsbsim/blob/3b25f25e49b42d0489c04ac805674fc1450ca579/src/models/propulsion/FGPropeller.cpp), lines 225–235 and 281–296: pre-step loads and one explicit Euler angular update, with an angular-speed divisor branch at 0.01 rad/s.
- [FGPropulsion.cpp](https://github.com/JSBSim-Team/jsbsim/blob/3b25f25e49b42d0489c04ac805674fc1450ca579/src/models/FGPropulsion.cpp), lines 118–138: one engine Calculate and one fuel consumption per propulsion step.

The first crank increments at 60/120/240 Hz are approximately 0.052361/0.0261805/0.0130902 rad/s. All cross 0.01 rad/s while remaining below 1 RPM. With nearly constant low-RPM starter power, the next Euler increment is approximately independent of the interval: division by an initial speed proportional to the interval cancels that interval. This is a source-supported explanation of the observed bias, not a fitted reference or proof that the proposed method will pass.

Preserved failed-suite receipt SHA256 is `87ad6b630c872ed102e694bbbb93c3d9a9ee2405912b3f37b1359caa1f5a27d2`; the source-bound diagnosis is `e985dc264056e0f100768899e0d48aad7f7c25a352238bf09eddaf8f168ded97`. Private coordination records are retained separately from reproducible source/reference inputs.

### Separate model-loader source prerequisite

Those coupled observations used a corrected-loader candidate, not the original model bytes currently accepted on main. The original piston XML SHA256 `0d1b3eb87f1af2131a495c26ae7a3fb2fdd2a38d3d4309c67a77daaff2cf069e` supplies `unit="DEGK"` on `design-oil-temp-degK`. Pinned FGPiston.cpp line 242 requests DEGK, but FGXMLElement.cpp lines 493–497 reject that nonempty supplied unit before reading its number because the conversion map lacks it. The original v2 source therefore has no successful cold-runtime initialization evidence.

Preserved commit `fdd9c0d319591db69261fb6d440721498c499590` removes exactly that 12-byte attribute, retaining the raw value 350 in the constructor's Kelvin units. Corrected XML SHA256 is `4212b398118be77cdff44f6e41abfded7e4fd8fcfece422dba27fd64ad30b638`; inventory SHA256 is `f7766fda173d8ee83d4c4a8c02f6333124175a1f7064d3f4d8e78df3d17da12a`. Its v3 reference SHA256 `36aac20d85e841743d7eb9a357be8a0d40d8f103c1cbc60e084dde9ef23db63b` differs from v2 only in model binding; all 55 numerical cases and budgets match. The historical one-suite corrected-loader authorization SHA256 is `f3a5a4e349b13bc8341e3f8af37e66fc1d627221642116c9401e8beec0cceb97`. That private review/trial authorization is not a checked source merge or feature acceptance.

Before future coupled consumers/imports, a narrow independently reviewed source-only amendment must accept the exact loader-format correction, model/inventory/ledger pins and v3 metadata binding. Preserve original v2 source/reference/generator bytes and the failed first-load evidence separately; do not overwrite them or claim runtime equivalence to the rejected v2 loader. A new generator/version or explicit historical source input must retain the original generator bytes and make both bindings reproducible. This is the only presently identified format exception to unchanged piston XML; numerical model parameters, all reference values and physical budgets remain unchanged. Do not patch the vendor unit parser, change temperatures, drop provenance checks or treat this prose as an already accepted corrected pack. Pure shaft arithmetic and coupled model-source admission have distinct gates.

## Closed method and profile admission

Add exactly two checked native angular methods: `legacy_euler` and `event_aware_constant_power_v1`. Default library construction stays legacy. The opt-in original piston profile uses event-aware v1. A research constructor may explicitly select legacy to reproduce the preserved failed suite and original discrete references. The direct-thrust profile rejects event-aware selection. First-party method selection occurs only once during fresh initialization, after exact piston/direct-drive/fixed-pitch topology checks and before RunIC. There is no runtime cockpit setter, arbitrary property, hidden RPM injection or replay edit.

The vendor API adds a checked enum, method setter returning rejection for unknown values, and actual getter. For the piston profile, native Session verifies the actual propeller getter at initialization and before completed publication. Successful open metadata adds exactly `angular_integration_method:String|null`: a piston open echoes its verified method ID; the direct-thrust original profile returns null because it has no FGPropeller or angular method. Its Config must still reject nonlegacy method selection. Never fabricate a propeller getter for the direct-thrust aircraft. Source/fingerprint and profile closure must also qualify; an echo alone is insufficient. Other profile/capability fields remain [ADR010](010-original-piston-profile.md); public Result, Readback, v1 wire and observed-review/archive schemas are unchanged.

The deployed third selector is wind. Supersede ADR010's earlier three-argument profile signature with:

```text
open_session(model_root:String, named_start:String,
             wind_profile:Variant="calm",
             profile_id:Variant="original-interactive-prototype")
```

Facade `start` uses the same argument order and defaults. Register both trailing defaults in the actual Godot binding; prove real two-, three- and four-argument calls. Both selectors require actual String Variants. StringName, coercion, null, numeric, boolean and unknown IDs reject. A three-argument `from-west` call retains wind semantics; a three-argument piston ID rejects as an unknown wind.

| Aircraft profile | Supported start | Supported wind |
|---|---|---|
| `original-interactive-prototype` | `ground-ready`, `airborne-prepared` | All four accepted ADR013 profiles |
| `original-piston-prop-v1` | `piston-cold-ground` | `calm` only |

Reject unsupported pairs, method/profile mismatch, wrong roots, source/hash/version/capability identities and wrong types before closing the old worker, allocating a solver or mutating accepted state. Reset retains the accepted aircraft profile, wind and supported recipe. Piston airborne and noncalm requests cannot silently replace the current flight. Current wind draft/current-state separation remains ADR013. The broader ADR010 controls, input-v2 migration, engine status, fuel chronology and scene ownership remain normative.

## Mathematical angular update

Change only the propeller angular update for the opt-in method. Hold the existing once-computed net power P = delivered EnginePower minus pre-step GetPowerRequired and actual loaded inertia I over the actual public integration interval h. Use the existing backend units: P in ft·lbf/s, I in slug·ft², angular speed w in rad/s and h in seconds. The threshold a is the existing binary64 literal 0.01 rad/s; the below-threshold divisor remains 1 rad/s. Do not replace either floor, smooth the discontinuity or change model data.

The declared held-power ODE is the existing numerical surrogate:

- For 0 <= w <= a, dw/dt = P / (I × 1 rad/s).
- For w > a, dw/dt = P / (I × w).
- Angular speed stays nonnegative; attempted negative continuation stops at positive zero.

In the following numerical formulas the backend's 1 rad/s divisor has numeric value 1. For P > 0 below a, time to crossing is tau = I(a−w)/P. Before or exactly at tau, w' = w + Ph/I; after tau, consume tau, set the mathematical boundary to a, and use w' = sqrt(a² + 2P(h−tau)/I). Starting exactly at a with positive power crosses immediately with zero dwell. Above a, w' = sqrt(w² + 2Ph/I).

For P < 0 above a, time to crossing is tau = I(w²−a²)/(2|P|). Before tau, w' = sqrt(w²−2|P|h/I). At or after tau, consume tau, set the boundary to a and continue on the low branch. Below/on a, stopping time is sigma = Iw/|P|; before sigma, w' = w−|P|h/I; at/after sigma, w' is positive zero for the remainder. Each interval has at most one threshold crossing and one stop. There is no unbounded adaptive loop or hidden public tick.

Validate known method and finite nonnegative pre-step RPM/w, finite net/delivered/load power, positive finite I and finite h >= 0 before opt-in angular assignment. **For h == 0 or P == 0, preserve the original RPM bits and perform no angular assignment or RPM↔rad/s round trip.** This includes negative zero RPM and signed zero h/P. With positive h and nonzero power, negative zero speed is treated mathematically as zero; an actual reached stop writes positive zero. No-op semantics apply to the angular field, not to unrelated pre-step thrust or moment calculations.

Compute the entire candidate and checked rad/s-to-RPM conversion before RPM assignment. Unknown mode, invalid input, nonfinite required intermediate/result, zero division, overflow, invalid square root, unsupported finite arithmetic edge or violated monotonic/nonnegative invariant rejects visibly. A damaged executive is destroyed under the existing last-valid-publication contract. FGPiston has already calculated before propeller execution; do not claim rollback of every internal engine variable. Legacy arithmetic and order remain unchanged apart from dispatch; do not apply new guards or clamps to the legacy branch.

The mathematical definition does not prescribe unsafe crossing-time division or subtracting nearly equal squared speeds. Use bounded compensated event predicates/residuals rather than comparisons against a rounded P/I impulse: upward predicate U = Ph−Ia+Iw, downward predicate D = 2|P|h−Iw²+Ia², then stop residual D−2Ia after a downward crossing or |P|h−Iw on the low branch. These denote exact expressions of admitted binary64 operands, not rounded intermediate products. Positive growth can use hypot with a checked power/root path; negative growth uses the positive compensated remainder quotient. Explicit FMA/error-free products and a small fixed expansion are a proposed implementation, not a completed audit. **Exact binary64 operation order, expansion capacity, representability domain, signed-zero handling, event comparison, quotient reduction, operation count and failure policy require a separate independent source review before any new helper/backend output.** Guard the range assumptions of error-free transforms, including underflow; a finite final answer alone does not establish them. MSVC long double has no extra precision; assuming it does is not a portable implementation. Do not claim a universal roundoff proof from the sampled packet or use an arbitrary negative-radicand clamp.

Engine/airframe/contact integration remains once per actual public tick. Keep one piston Calculate, one fuel drain, pre-step aerodynamic/thrust/moment evaluation and the existing requested/supplied-fuel lag. No internal common 240 Hz solver, subcycled combustion/fuel, post-Run RPM write, feedback start controller, new limit, assist or performance tuning is authorized. This is exact integration of a held-power split, not exact coupled continuous energy conservation.

## Reproducible dependency and source closure

The patch is restricted to `FGPropeller.h` and `FGPropeller.cpp`; keep any original helper local to the cpp. Preserve the pinned pristine acquisition and historical caches/builds. After this contract merges, author and independently review exact patch bytes, before/after file sizes and hashes, materializer identity and allowed two-file delta before building or observing it. Do not invent a fork commit or fill pins from unreviewed build output.

Materialize a fresh distinct patched root from verified pristine source. Validate the complete before-tree; apply only the exact declared bytes; reject fuzzy hunks, already-applied patches, duplicate/missing/unknown changes and extra modified files; then verify the complete after-tree and immutable receipt. Patch text is data, not executable code. Bind upstream acquisition plus patch manifest, patch, materializer and relevant consumer inputs into the new dependency/build/native fingerprint. Rebuild matching header consumers; an old ABI/DLL cannot be relabelled as the patched library.

Current unmodified corresponding-source manifests remain schema 1 with `vendor_modified:false`, the exact 279-file vendor roster and 286-member archive. Preserve the accepted unmodified source archive SHA256 `f6ea1c2771de5594f0047e27b2facb605dc958c7c8e0008dd43e73df88bf6a62` and its legacy ledger/verification route. Add a distinct schema 2 source variant `jsbsim-1.3.1-event-aware-constant-power-v1`, `vendor_modified:true`, with this closed 291-regular-file roster:

| Archive paths | Count |
|---|---:|
| `vendor/` plus the existing upstream library inventory paths: 277 pristine and exactly two reviewed modified FGPropeller files | 279 |
| `CMakeLists.txt`, `BUILD.md`, `verify.py`, `pack.py`, `upstream-file-inventory.json`, `LICENSE.first-party.txt`, `manifest.json` | 7 |
| `patches/event-aware-constant-power-v1/FGPropeller.cpp.before`, `patches/event-aware-constant-power-v1/FGPropeller.h.before` | 2 |
| `patches/event-aware-constant-power-v1/recipe.json`, `materialize.py`, `MODIFICATIONS.md` | 3 |

The complete modified vendor tree is the directly editable preferred source; its two before-images and after-images form the authoritative byte-replacement patch. The recipe binds exact before/after sizes/hashes, the unchanged upstream inventory, allowed delta and shared materializer hash. The manifest covers every other member and is covered by the external archive SHA. No extra textual diff/patch parser is admitted under this roster; changing that choice needs an explicit roster review. Archive verification reconstructs pristine and modified closure, rejects missing/extra/symlink/unsafe/duplicate entries and preserves baseline checks for the old variant. Do not bypass the old verifier, change the upstream inventory or fabricate modified source pins.

Rebuilding the archived preferred source must require neither repository checkout nor cache/network access; Python stdlib verifies provenance but compiling the already materialized source needs only its documented native toolchain. A recipient may edit and rebuild the library for debugging/replacement; strict project identity checks cannot revoke that ability or label such an edit as the reviewed variant. No upstream aircraft/engine XML or binaries enter this library-only source bundle. Root CMake, all JSBSim header consumers and source fingerprint inputs must use the selected verified source root; the new fingerprint explicitly includes vendor patch/materializer identity instead of claiming first-party adapter hashes identify the backend.

Retain the accepted LGPL 2.1 source/replacement route, applicable embedded notices and debugging/replacement rights. Mark modifications and authorship/date in modified sources/notices; the rights owner reviews actual new source closure before release. Record the exact patched DLL/source archive/receipt in package inventory and notices. Independently prove actual DLL replacement with all other payload bytes unchanged. Source completeness and redistribution evidence remain separate from numerical success.

## Independent references and pretrial gates

The separate [proposed shaft packet](../../tests/engine/shaft-method/README.md) contains 45 Fraction/Decimal branch cases, nine constant-held-power partition cases, 18 rejection cases and four signed-zero recipes. It imports no native solver or consumer. Decimal precisions 150 and 220 agree on the nearest binary64 expected result. Ideal rational 1/100 and actual binary64 0.01 are explicitly distinct; intervals include genuine 1/60, 1/120 and 1/240. Partition identities apply only to the declared constant-held-power ODE, not the coupled piston solver.

Expected packet SHA256 is `b3b90b35bc9f3bd91e26020e608b32a0c1aa9672467d1dff0efaa5d226d99a85`; generator SHA256 is `771a0b926a486facfcca2968121779652a2db24cd16b3a7b1ccf8c569fae0a57`. Preserve original preparation metadata and the original 55-case expected packet `bd2ec9562308dbb950b684018ff924c4f820278400c7a2664f1342f11f049777` and generator `c81596d5e4155463620687d987838294ef0fa39ce32157df15cbc91a7c51ebb7` unchanged.

The proposed arithmetic error criterion is 64u times the declared case's branch-local scale, u = 2^-53. It is a finite engineering packet criterion, **not a universal gamma32 theorem**, physical convergence allowance or permission to alter an expected zero/event. Near-event subtraction/root conditioning needs actual stable-source review. Stops require positive zero; no-op RPM requires bit preservation. Extreme finite inputs have no invented algorithm-independent overflow expectations. The nine partition recipes freeze mathematical endpoints/events; their composed binary64 comparison budgets must be independently derived and frozen before output. Do not implicitly reuse one single-step allowance or demand a bit-exact floating-point semigroup. Preserve the packet and derive propagation bounds from the specified operations and branch behavior without observed fitting.

Before first new output, Root ratifies the accepted contract, independent packet, actual stable arithmetic source/order/domain, exact reviewed patch/materializer/source closure and unchanged physical schedule/budgets in a distinct chronology receipt. Then run pure helper/default-method guards, a fresh isolated dependency/consumer build, and the unchanged complete 12-process 111-second cold/start/run-up/taxi/brake/shutdown/recovery schedule at genuine 60/120/240 Hz. Keep every failure; correct reviewed implementation defects without fitting references, changing commands or widening limits.

Qualify new profile/selector/default behavior, unsupported pair rejection before replacement, fuel-stage observations, input/status/UI lifecycle and all existing wind/calm regression paths under the actual new source identity. WindCue/reading producers need explicit new model/source-domain review; a new fingerprint alone cannot qualify piston calm cues. Verify editor, exported player and rebuilt/replaced DLL, actual source/rights closure and independently reviewed exported views before issue127 closes. No owner game or prior evidence is disturbed. C172S, electrical/sensor realism, hardware, pilot, full-circuit and phase gates remain open.
