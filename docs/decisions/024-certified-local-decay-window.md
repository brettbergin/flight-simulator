# ADR024: One certified local decay window after whole-interval rejection

Status: **proposed under [issue207](https://github.com/brettbergin/flight-simulator/issues/207)**; this contract is a prerequisite of the remaining [issue202](https://github.com/brettbergin/flight-simulator/issues/202) repair. No implementation or source variant is accepted by this draft. See the [contract evidence](../evidence/P3/piston-local-window-contract.md). This amends only [ADR015](015-source-law-coupled-shaft.md)'s negative-drift numerical admission window for the original piston source law. It changes no model coefficient, physical/convergence budget, public tick, engine chronology or aircraft claim.

## Evidence and decision

The source-bound 298-call replay reproduced the original mixture-decay rejection and captured frame SHA256 `01a8cbc256bbc30a5a53265362d5af89a7297cc5d6f5f065cd1b53d9d3458e8b`. Independent exact Fraction/Sturm analysis reconstructs all five derivative coefficients and 16 observed Horner-cell decisions. The whole [0,w0] time map really is nonmonotone, while the requested short step has a strictly certified connected solution in [w0/2,w0]. Increasing interval splits cannot make the whole map monotone. The old guard is consistent with ADR015; its supported-control coverage is too restrictive for this observed ordinary input. This is not a fitted-parameter or arithmetic-error diagnosis.

Preserve whole-endpoint certification **first** and every previously successful path. Only when it returns a structured uncertifiable result, try exactly one deterministic interior half window connected to the current start. Require the original exact sign, time-order, source/noncrossing and arithmetic guards. Otherwise reject visibly. No root guessing, clipping, stop donation, retry under another law or changed public step.

## Exact policy

Use existing notation N(w), T=N/w, H(x)=I*(x-w)/T((x+w)/2) and b(x)=m² times its unscaled derivative numerator. Source/frame/topology, nearest equilibrium/source endpoint classification and drift are computed as before.

1. For negative drift, run the original whole-endpoint b certificate in its original selection/evaluation order. A certified result immediately follows the original event-time/solve path without evaluating a half endpoint. Growth, hold, analytic cases, source-event classification and successful whole-interval paths retain their original behavior.
2. The private certificate returns `certified` or `uncertifiable` with one caller-owned split counter. Only the current algebraic conditions `range.lo>0` or exhausted split allowance on an undecided cell return `uncertifiable`. Invalid source/frame, dyadic capacity, unsupported arithmetic/FP environment, stagnation and unrelated failures still reject immediately. Never catch arbitrary exceptions or compare rejection-message text. Refactoring may not reorder original sign tests or introduce coefficient/state recomputation.
3. After whole-endpoint `uncertifiable`, compute exactly one candidate `half=CoupledRounded(endpoint+(w-endpoint)*0.5)` using the existing checked midpoint expression. Require strict `endpoint<half<w` and every original domain guard. This is an internal numerical boundary, not a CP/starter/source event, physical limit or new speed state.
4. Certify the **same** b polynomial on [half,w], reusing the total split allowance. Preserve negative source torque and connected noncrossing admission on that interval from the original endpoint classification. Require exact `remaining < CTime(p,I,w,half)`, with positive finite supported time and the existing exact ratio comparison. Equality or a larger remaining interval rejects; the fallback cannot reach the half boundary as a fabricated event or stop.
5. If those checks pass, use unchanged CSolve on [half,w] with the exact captured/remaining rational and negative drift. Apply all existing result, monotonicity, conversion and roundoff checks. Return an ordinary completed interior segment: no source event/stop, no remaining-time subtraction, no repeated engine/thermal/fuel/contact call and no extra public/native tick. Otherwise retain the visible coverage rejection. There is no second fallback or adaptive search for a more convenient endpoint.

## Finite work and compatibility

Both certificate attempts share **eight total algebraic splits**. Do not reset the counter. A cell whose exact enclosure already certifies is accepted even when the counter is 8, preserving the existing certificate-test-before-budget-test order. At most two initial cells plus two child cells per split yield **at most 18 interval evaluations** across both attempts. Reuse the existing 9-slot work array sequentially; discard the unsuccessful full attempt's pending cells before the one half-window attempt. No saved partial certificate implies qualification. Root's captured frame uses 8 full splits and 0 half splits.

The existing 64-bisection solve/root bounds, dyadic capacity, rounded midpoint guards, coefficient construction and arithmetic comparison budgets remain unchanged. A previously certified full path returns before any fallback and must match its original output bitwise under the same actual build environment. The new admission is request-dependent but still requires exact monotonicity on the retained connected interval and exact time bracketing. It does not assert uniqueness of arbitrary midpoint roots outside that interval.

The numerical law/method name `event_aware_coupled_midpoint_v1` continues to describe the existing midpoint/source law; **method name alone is not proof of this amended policy**. Bind the additional domain policy to a distinct closed corresponding-source variant, proposed `jsbsim-1.3.1-event-aware-coupled-midpoint-local-window-v2`, separate patch/archive manifest and generated runtime/build fingerprints. Root reviews final identifier allocation before implementation. Preserve the immutable v1 archive/after-images/references and their original rejections. Do not replace an old-source artifact under an old identity or relabel its failed receipt.

Minimum numerical after-image change is private FGPropeller.cpp certificate/status/advance logic. The new corresponding-source package must still include the complete inherited four-file ADR015 modified roster and its pristine before-images; unchanged inherited after-images remain byte-pinned. Materialize independently from pristine upstream, document the narrow new change and retain existing license/replacement/source obligations. No new vendor translation unit, model XML, public wire/session method or UI method selector is required. First-party closed source-variant admission/delivery pins change only after contract/source review.

## Independent references before implementation outputs

Freeze a small versioned amendment packet, preserving all original expected values and rejections. Include:

- The captured actual rational frame: exact N<0, b root/sign proof, exact half-window Horner certificate and remaining<CTime(half). Prove a unique requested connected solution by exact sign and time bracketing; any optional mathematical root/enclosure is diagnosis only, never a native golden or tolerance fitted to output.
- Full-certification success with identical original path, positive-drift/hold/analytic compatibility and no fallback evaluation.
- Local-window sign failure, strict half-time equality/excess, invalid/stagnant half, unsupported/capacity failures, exhausted total splits and exact zero-split certification at budget 8.
- Source/equilibrium/stop boundaries: a rejected fallback cannot cross a knot/equilibrium, consume time, create an event or silently stop. Prove negative torque/connectedness and signed b, not a sampled curve.

Existing R05 and other immutable v1 guard cases remain intact and executed against v1. Explicitly define prospective v2 behavior for those same inputs; a valid expanded domain must be independently specified rather than overwriting an old golden or assuming every old rejection remains equivalent. New invalid/local-uncertifiable/time-bound/resource cases must still reject. Physical/default/coupled suites retain their inputs, exclusions and thresholds.

## Acceptance sequence

1. Independently review this exact policy/work bound, source identity plan and new reference packet; merge the contract before production changes.
2. Review the minimal source/status refactor and corresponding-source closure before any new converter/solver output. Qualify strict actual Windows/Linux builds; compare old successful paths and default methods with exact original evidence.
3. Run independent amendment references and all unchanged physical/convergence/source gates. Re-run the exact 298-call recipe with only approved identity/session/model-path binding changes; prove actual completion past the preserved fault, valid native publications, once-per-public engine/fuel calls and joined shutdown. Keep original expected-failure receipts separately.
4. Only then adopt a new source identity in fresh editor/portable/rebuilt-library delivery and bounded player evidence. Passing a local mathematical witness or contract PR does not close issue202, qualify a C172, establish physical fidelity or pass a phase gate.

The independent diagnosis is a prerequisite, not an implemented solver. No fallback has been executed or accepted.
