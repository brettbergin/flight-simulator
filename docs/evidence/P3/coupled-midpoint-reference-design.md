# Independent coupled-midpoint reference design v1

Status: Prospective source-only reference design. No generator, native method, reference values, compiler or backend has been executed for this proposal. This document accompanies [ADR015](../../decisions/015-source-law-coupled-shaft.md); it does not establish implementation or numerical acceptance. The implementation/reference arithmetic enclosure and numerical comparison thresholds must be ratified before new outputs. Existing held-power/legacy packets, original 12 coupled cases, their schedules and their physical budgets remain immutable.

## Deliverable and independence

Publish one versioned packet for `event_aware_coupled_midpoint_v1` with a small standard-library Python generator and independently reviewed derivation notes. Proposed eventual paths are `tests/engine/shaft-method/coupled-midpoint-v1/{generate.py,cases.json,references.json,README.md}`. This proposal creates none of those tracked files. Do not import vendor/helper code, parse a native result, or infer expectations from the preserved failed traces. Source-derived coefficient fixtures, abstract scalar fixtures and chronology fixtures are explicitly different categories. Abstract polynomial fixtures are mathematical kernel tests, not a claim they are physically attainable engine frames.

The generator owns exact rational polynomial construction and root classification, rather than implementing the production H-map/bisection algorithm a second time. Use Python `fractions.Fraction`, integer polynomial Euclidean division/Sturm root counts and `decimal` only for displaying certified intervals. Rational isolating intervals and exact sign tests are authoritative. Report the selected root's connected drift interval, other real roots, rejected branches and residual enclosure, not merely a golden decimal. Isolate each finite nonzero root to relative rational width at most 2^-192 (absolute 2^-192 for magnitude below1); a second 384-bit-equivalent enclosure must refine the first 192-bit-equivalent enclosure and prove the same binary64 rounding cell before a scalar expected double is frozen. Precision agreement alone is not a certificate. Roots on a rounding-cell boundary retain an interval expectation or require an exact tie proof; do not guess a last bit.

All values below are prospective inputs and formulas, not generated outputs. A generator source review precedes permission to generate the packet; packet review precedes native output comparisons. Root owns those gates. Keep one compact binding of the final design/roster, accepted ADR and pinned model/source files. Do not expand this into a separate receipt hierarchy for every case.

## Input semantics and coefficient derivation

Separate the ideal source algebra from binary64 execution. Parse XML decimals as exact rationals, derive correctly rounded loader constants independently, and record their binary64 bit patterns as exact dyadic rationals in the packet. Use the reviewed backend `M_PI` binary64 constant, lifted exactly, for the backend numerical oracle; a mathematical-pi calculation may be an informational sensitivity check and must not silently replace that oracle. Source constants `550`, `5252`, `22371`, `60`, `360`, `2.2046`, `14.7`, `0.3048`, `287.3` and table decimals must retain their source meanings. Coefficient construction roundoff and loader rounding are separate from midpoint root roundoff. Do not equate an ideal coefficient with a rounded native coefficient without the prospective audit bound.

Let kR=60/(2*pi), displacement d in m3, reduced efficiency e, manifold density r=MAP/(287.3*T), frozen equivalence ratio q and original Stroke S in inches. Original airflow hardcodes /2, while pumping uses configured Cycles; retain this distinction:

```
a_air = d*e*r/(4*pi)
a_fuel_pph = a_air*(q/14.7)*2.2046*3600
ME = original MIXTURE(q/14.7), clamped piecewise linear
spark = 1 if Magnetos==3 else source SparkFailDrop
c0_running = -550*StaticFriction_HP
c1_running = 550*a_fuel_pph*ME*spark/ISFC
             +550*(PMEP-FMEPStatic)*d*kR/(Cycles*22371)
c2_running = -550*FMEPDynamic*(S/360)*0.3048*d*kR^2/(Cycles*22371)
c0_stopped = -550*StaticFriction_HP
c1_stopped = 550*PMEP*d*kR/(Cycles*22371)
c2_stopped = 0
c0_cranking = 0
c1_cranking_base = c1_stopped
c2_cranking_base = 0
t0 = (550*60/(5252*2*pi))*StarterTorque*StarterGain
ws = StarterRPM*2*pi/60
cranking below ws: add t0 to c1, subtract t0/ws from c2
cranking at/above ws: no starter addition
```

For the exact nonboosted original frame TMAP=MAP and PMEP=(MAP-p_amb)*volumetric_efficiency. Compute e using the actual source compression-ratio expression, including its clamp and MAP<1 branch; do not infer it from a sampled fuel flow. At w=0, q/14.7 defines the canceled fuel/air ratio limit used for ME; no 0/0. Starved frames force q and actual fuel flow to zero under existing chronology. Running eligibility is independently checked, so a requested running label with contradictory fuel/spark must not be accepted by the production frame builder.

The source-derived fixture set uses the pinned original XML (Cycles4, StaticFriction1HP, ISFC0.4, Stroke4.5IN, StarterTorque60, StarterRPM1200, FMEPStatic45000Pa, FMEPDynamic18000Pa, original displacement decimal and tables). Freeze p_amb=101325Pa, T=288.15K, MAP in {60000,101325}Pa, mixture command in {0,1/2,1}, Magnetos in {0,1,3}, StarterGain in {0,1}. These are synthetic held thermodynamic inputs, not replay samples or an operational-aircraft reference. Use only combinations required by the finite roster. C07 separately supplies an exact q/table-knot fixture and is not limited to that base mixture set.

For aero, use exact loaded D=6ft, I=2slug*ft2, rho=1/512slug/ft3, V in {-10,0,30}ft/s. L=rho*D^5/(2*pi)^3 and A=2*pi*V/D. For V<=0 subtract .06*L*w^3. For V>0, below k=A/2 subtract .02*L*w^3; above k subtract .06*L*w^3-.02*A*L*w^2. Prove continuity at k and T_aero(0)=0 algebraically. Check J=1 is not a genuine polynomial breakpoint: the two source table slopes agree. Starter knot is ws. The source torque derivative can jump upward at ws; every certificate stays within one segment.

All admitted production/source cases have c0<=0,c3<=0. Positive constant power is explicitly excluded. Some abstract fixtures intentionally violate a precondition to test rejection; they cannot be routed as accepted production engine frames. SI boundary conversions remain a separate native interface test.

## Discrete oracle and branch decisions

For I>0, h>=0 and w0>=0, construct exact polynomial F(x)=I*(x-w0)*(x+w0)/2-h*N((x+w0)/2). If c0=0 instead construct canceled F(x)=I*(x-w0)-h*Q((x+w0)/2), Q=c1+c2*w+c3*w^2. Compute exact real root counts with Sturm chains after square-free factorization. A repeated root is reported explicitly. Do not include the canceled artificial x=-w0 factor, particularly the spurious x=0 root at rest.

Classify torque equilibria from Q for c0=0 and N otherwise, using effective degree including constant/linear cases. Establish nearest physical equilibrium and CP/taper endpoint in the drift direction. Independently derive H's derivative numerator B on that interval. Exact polynomial sign isolation proves H monotonicity; the reference need not copy the production eight-split certificate, but must distinguish mathematical admissibility from whether the bounded implementation can prove it. An accepted mathematical root still cannot authorize a native result if its production arithmetic/resource certificate fails.

Choose only the root on the certified continuation interval. At a source knot derive its time algebraically, land on the outgoing side selected by torque direction and consume exact rational/interval time. Never count an initial zero-time knot again. At initial exact equilibrium hold. Incoming finite discrete arrival at equilibrium rejects even though the continuous ODE approaches asymptotically. Constant torque/power-loss use their analytic limits, not a special root selected by proximity to a native answer.

Finite rest admission requires c0<0 or c0=0,c1<0 plus a connected negative-drift path to zero without another equilibrium and the unique continuation certificate. Otherwise zero is a constrained initial hold or an asymptotic equilibrium, not a clipped finite stop. Record the exact stopping-time expression, positive-zero output, remaining-time interval and event counts. Reaching a production work ceiling is rejection, never an approximate successful answer.

## Finite case roster

`C` rows are source-derived coefficient fixtures; `K/E/R` rows are scalar mathematical fixtures; `M` rows are native chronology/admission assertions. Values are exact rationals unless stated in source units. Scalar tuples below are (I,w0,h;c0,c1,c2,c3). Only explicitly parameterized sided triples expand; no random sweep is required.

| ID | Input construction | Required result or independent assertion |
|---|---|---|
| C01 | Original frame, MAP60000, mixture1, Magnetos3, running; V0 | Derive all engine/aero coefficients and pre-step power; do not obtain coefficients by dividing sampled power by w. |
| C02 | C01 with Magnetos1 | Combustion term gets source SparkFailDrop=0.9; FMEP/pumping unchanged. |
| C03 | Original stopped frame, MAP60000, mixture0, Starter false | c0=-550, c1 from PMEP, c2=0 before aero. |
| C04 | Original cranking frame, MAP60000, mixture1, StarterGain1; w0=0 | c0=0 and finite positive t0 plus pumping torque; no 1RPM power. |
| C05 | C04 evaluated just below/at/above ws (three exact source-relative speeds) | Two source polynomials match at ws; outgoing ownership and taper derivative change. |
| C06 | C01 with MAP101325 and V in {-10,0,30} | Zero PMEP and exact V<=0/positive-V CP collapse. Negative V is no windmill-fidelity claim. |
| C07 | Original fuel/ME construction q/14.7 at source table knot .08 and adjacent dyadic offsets | Clamp/interpolation and canceled zero-RPM ratio limit, independently of native samples. |
| K01 | (1,0,1/8;0,2,0,0) | Constant positive torque: x=1/4, no spurious zero root. Abstract zero-aero kernel. |
| K02 | (1,1,1/8;0,-2,0,0) | Constant negative torque: x=3/4. |
| K03 | K02 with h in {1/2-2^-12,1/2,1/2+2^-12} | Before/exact/after finite stop; exact stop1/2, positive zero and rest remainder. |
| K04 | (2,3,1/4;-2,0,0,0) | Constant-power loss x=sqrt(17/2), source-domain-compatible c0<0; no c3 division. |
| K05 | K04 with h in {9/2-2^-12,9/2,9/2+2^-12} | Exact analytic constant-power stop9/2; no hidden negative speed. |
| K06 | (1,0,1/8;0,0,0,-1) | Rest hold for zero starting torque, despite canceled polynomial's other possible algebra. |
| K07 | (1,2,1/8;0,0,-1,0) | Linear drag x=2*(1-h/2)/(1+h/2), positive branch. |
| K08 | (1,2,2;0,0,-1,0) and h=2+2^-12 | Incoming asymptotic zero equilibrium finite discrete boundary rejects; no finite stop/clipping. |
| K09 | (1,2,1/8;0,0,0,-1) | Pure quadratic drag positive root, continuous x=2/(1+2h); finite-time zero prohibited. |
| K10 | (1,2,2;0,0,0,-1) | H(0)=2 for this fixture; reject equilibrium arrival, rather than call it a friction stop. |
| K11 | (1,1,1/8;0,0,0,0) | Identically zero polynomial/derivative holds; effective degree absent. |
| K12 | (1,2,1/8;0,1,-1,0) | Linear torque toward equilibrium1: admissible connected branch; derivative/root degree1. |
| K13 | K12 with h=2 and h=2+2^-12 | H(1)=2; finite discrete equilibrium arrival/crossing rejects. |
| K14 | (1,1,1/8;0,1,-1,0) | Initial exact equilibrium holds, no root search. |
| K15 | (1,1/4,21/500;-1,2,0,0) | Multiple positive algebraic continuations. F=x^2-(21/250)x+1/2000; B changes sign on zero-connected drift branch. Reject, never nearest-root guessing. |
| K16 | (1,0,1/8;-1,2,0,0) | Nonstarter constrained rest: c0<0 division never evaluated at zero, no spontaneous rotation. |
| E01 | Original CP coefficients V30; w0=k/2; constant drive torque u=1 ft*lbf+.06*L*(3k/2)^2, engine c0=0,c1=u,c2=0 | One increasing CP crossing: aero torque<=.06*L*(3k/2)^2, so net drive>=1 ft*lbf over that interval. This is an abstract scalar drive, not original engine combustion. Let h=H(k)+H_next(3k/2) using exact source coefficient intervals. Native receives rounded certified input; reference solves that exact rounded h, not ideal endpoint snapping. |
| E02 | Same CP law; constant-power-loss plus aero, w0=3k/2 | One decreasing CP crossing, h=H(k)+H_next(k/2), exact source-derived topology. |
| E03 | Exact k, positive and negative drift | Outgoing CP ownership and zero initial crossing count. |
| E04 | Original starter t0/ws and V0 CP; w0=ws/2; add constant pump surrogate b=1 ft*lbf+.06*L*(3ws/2)^2 to c1 | One taper crossing: below ws use c1=b+t0,c2=-t0/ws; above use c1=b,c2=0, and c3=-.06*L throughout. Net drive>=1 ft*lbf through3ws/2. Set h=H(ws)+H_next(3ws/2). Derivative jump needs fresh certificate. Abstract pump surrogate, not ordinary engine chronology. |
| E05 | Exact ws, positive/negative/zero drift | Outgoing taper ownership; initial equilibrium has priority. |
| E06 | Construct k=ws from V=D*ws/pi; two coincident knots, monotone positive drift | Coalesce same-time events deterministically; both counts1, no repeated zero-time segment. Rounding must preserve or explicitly separate the declared exact dyadic knot identities. |
| E07 | CP loss case E02 extended to certified zero stop | CP then finite stop, positive zero and exact remainder enclosure; no repeated engine update. |
| R01 | h=+0 with w0=+0,-0,positive dyadic | Preserve original RPM bits and signed zero; no assignment/conversion round trip. |
| R02 | NaN, infinity, negative I/h/w; c0>0 production descriptor | Reject invalid inputs/domain, retain last completed publication. |
| R03 | Unsupported engine/gear/pitch/table/scale/Mach correction, stale frame RPM/h, scalar Calculate under new method | Reject actual unsupported topology/frame; no permissive fallback. |
| R04 | Coefficient/domain overflow and subnormal/FTZ/DAZ policy boundary | Compare the prospectively accepted arithmetic domain; no universal guarantee inferred from old helper. Exact inputs selected only after arithmetic audit, before outputs. |
| R05 | Certified bracket requiring more than64 bisections or negative-drift certificate exceeding8 total splits | Fail visibly; resource tests use independent constructed arithmetic witnesses or source-level counters. No fabricated production-success expectation. |
| M01 | Current mixture/spark cutoff from running at fixed pre-RPM | Choose no-combustion/FMEP before actual power on that boundary; no stale FMEP pulse. |
| M02 | Feed request unavailable but previous supplied fuel available, then Starved on next public step | Retain actual ConsumeFuel/supplied-fuel lag; do not trust feed command as immediate fuel oracle. |
| M03 | Prior Running both states; pre-RPM at 480 and dyadic sides, indicated HP at .125 and dyadic sides | Source strict inequalities/equality retention; do not convert equality into a transition. |
| M04 | Shaft crosses480 within one public interval while mode initially not-running | Mode unchanged until next actual public engine call; no hypothetical intrastep combustion. |
| M05 | CP/taper/stop segmented scalar solve within actual engine fixture | Exactly one Calculate, one MAP/air/fuel/thermal update, one ConsumeFuel; scalar trial has no stateful callback. |
| M06 | Fresh actual FGPropeller, unknown selector, each supported closed method, reset, before RunIC/publication | Default legacy preserved, unknown rejected unchanged, selected method retained/read back; old methods and references unchanged. |

This is 41 named groups, with only declared sided/selection expansions. R04/R05 are deliberately not fake fully specified numerical cases before the arithmetic implementation exists: their acceptance is rejection according to an independently reviewed prospective domain/resource witness. Do not count such placeholders as executed evidence. E04 deliberately isolates the taper polynomial from actual mode chronology; an actual original cold engine changes Running much earlier under public rules. E06 must be constructed in the actual coefficient representation: approximate V that merely makes knots close must not be mislabeled coincident.

## Continuous oracle and refinement

The second oracle solves the continuous **frozen scalar law**, not the coupled engine: elapsed time is the oriented integral integral(I*w/N(w),dw), or integral(I/Q(w),dw) after symbolic cancellation. Split only at known CP/taper events. Use exact rational interval arithmetic and composite Simpson quadrature with a rigorous bound length*delta^4*sup|g''''|/180 on each closed nonsingular subinterval. Derive g'''' symbolically as a rational function, bound its denominator away from zero, and enclose its numerator by rational interval/Bernstein arithmetic. Double panel count up to a prospective4096-panel work ceiling; lack of the requested certified enclosure is failure, not permission to trust two nearby decimals. Independently repeat the quadrature with half its prospective time-error target and overlapping certified interval results. The 192/384-bit root-isolation targets apply only to the exact discrete polynomial oracle; they do not apply to continuous quadrature or imply correctly rounded continuous endpoints. Root isolation and quadrature share source laws but not the production H solver.

For c0<0, I*w/N extends smoothly to zero and permits stop-time quadrature if no equilibrium intervenes. For c0=0,c1<0, canceled I/Q is finite at zero. For c0=c1=0 approaching a drag equilibrium, prove divergence analytically; do not integrate through an artificial endpoint cutoff. Constant torque/loss and linear/quadratic drag have independent analytic solutions and must cross-check quadrature. Continuous results and midpoint results are separate packet fields. In particular, a variable-law discrete stop time is not silently equated to the continuous quadrature stop.

Use three nontrivial smooth refinement families: K07 linear drag, K09 quadratic drag and an event-free interval of C01 lying strictly within one drift/equilibrium/source segment. Add E02 as an event-timing consistency example without promising global order across it. Fixed total duration T is chosen algebraically inside a certified source/domain interval before native outputs; N in {8,16,32} uses h=T/N, with optional64 only if independently required to resolve the reference enclosure. Refine the same frozen descriptor; never re-evaluate combustion/fuel/MAP on each scalar partition.

For an event-free compact enclosure let f=torque(w)/I, L=sup|f'|, M2=sup|f'*f| and M3=sup|f''*f^2+(f')^2*f|. The exact-solution midpoint residual is at most C*h^3, C=M3/24+L*M2/8. If h*L/2<1, the single-step error is at most C*h^3/(1-h*L/2), and propagation is at most q=(1+h*L/2)/(1-h*L/2). Therefore the N-step global error is bounded by C*h^3/(1-h*L/2)*sum(q^j,j=0..N-1), with q=1 handled by N. Bound L/M2/M3 before observing outputs. Add a separately derived floating implementation enclosure, not a fitted margin. This yields O(h^2) on a fixed smooth interval and provides an actual finite bound; do not require an unjustified exactly-four error ratio. Linear drag additionally supplies the analytic expansion of the repeated rational midpoint factor, showing a nonzero order-two leading term and ruling out a vacuous constant-torque order test.

Continuous quadrature has a separate prospective tolerance. For a smooth refinement family, derive the a-priori global bound E_N above for N=8,16,32 before outputs, let E_min be its smallest positive value, and Fmax=sup|f| on the certified compact interval. Set the absolute time-enclosure target tau=min(T/2^24,E_min/(64*Fmax)) when Fmax>0. Analytic zero-error/hold fixtures use their analytic oracle instead of this division. For a standalone event/stop-time row use tau=T_scale/2^24, where T_scale is its exact positive source/analytic event-time scale specified by the fixture; freeze that value in the packet before generation. This is an accuracy target for the mathematical reference, not an aircraft/native acceptance budget. The4096-panel ceiling may fail to establish it, in which case report reference generation failure and review a different quadrature technique prospectively. Do not loosen tau by observing outputs.

On certified nonsingular event-free compact intervals only, invert continuous time enclosures as intervals: the time-to-speed Lipschitz bound is |Delta w|<=Fmax*|Delta t|; use Fmax*tau as conservative enclosure padding, plus certified inversion uncertainty. Stop interval refinement when that uncertainty dominates; do not biselect a display endpoint to192bits or emit a supposedly correctly rounded continuous double. Return the certified enclosing speed/time interval, including quadrature and inversion uncertainty, and compare the discrete error interval plus its prospective floating bound against the a-priori error bound. Refinement must not turn a coarse continuous oracle into fake exact expectations. For a c0<0 finite stop, f=torque/I diverges near zero, so there is no finite Fmax for an enclosure containing that endpoint. Report the certified continuous stopping-time interval and the known zero endpoint instead; do not apply the smooth-interval inversion formula there. Initial equilibrium and constant analytic cases bypass division by zero Fmax or a zero global error bound. The analytic drag fixtures provide nonvacuous order checks without requiring extreme quadrature precision.

Event and equilibrium rows test the declared event policy directly. They do not assert smooth second order at knots, at stop, at public Running switches, through MAP/fuel sampling or for the full aircraft. The original coupled physical gate remains decisive and unchanged.

## Comparisons and unresolved gates

Expected scalar values are exact expressions or certified intervals. A correctly rounded expected double is a reference representation, not automatically a one-ULP native tolerance. Native coefficient construction, residual evaluation, RPM encode/decode, event-time consumption and final rounded selection require a separate operation audit; freeze that arithmetic bound and each input-domain limit before any new native outputs. Chronology assertions are exact structural/state assertions, not tunable numeric comparisons. Preserve invalid-state behavior and last-valid publication.

Open work: merge the reviewed ADR015 contract; review generator source/Sturm and rational quadrature logic; pin exact backend constants/loader operations; ratify coefficient/operation bounds and R04/R05 witnesses; generate/review immutable packet; review actual vendor implementation and corresponding-source scope; strict compile both modified units; authorize actual-library probes; run original complete coupled suite without edits. No packet output, hardware/compiler claim or production default adoption is made by this document.
