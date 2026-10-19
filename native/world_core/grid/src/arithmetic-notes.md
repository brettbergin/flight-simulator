# Private resident-grid arithmetic and admission inventory

Implementation review notes for issue249; not a public interface or an executed
conformance result. Source-only authoring; Root owns compilation and execution.

`exact.hpp` stores a signed dyadic as a normalized integer magnitude (96 fixed
uint32 limbs,3072bits) and a power-of-two exponent. Raw IEEE words are decoded
without float arithmetic. Addition aligns without dropping bits, multiplication
uses checked32x32→64 products/carries, and every overflow throws a private empty
ArithmeticFailure. There is no allocation, generic dependency, dynamic limb
growth, mutable cache or public arithmetic API. Used limbs bound every loop.

Admission builds exact Float32 differences/slopes and checks p²+q²<=256 and
Ymax-Ymin+1/32<=2048. In particular, neither 1-2^-149 nor a subnormal span excess
is rounded away. FP32 sample bits are validated before promotion/arithmetic.
The shared validation.cpp is called by both decode and prepare. Accounted
capacity includes the actual Storage/Impl controls and PreparedGrid wrapper,
each owned vector capacity, string capacity+1 and polygon vertex capacity.
Definition is counted once inside Storage; allocation headers/control blocks,
input payloads, caller copies and RSS/peak are separate resource measurements.

Sample interprets the actual finite binary64 geodesy A,D as exact dyadics. Exact
bracket coordinate numerators are A.x*D.y+D.x*(level-A.y), denominator D.y>0.
Comparisons with exact grid lines certify physical support/floor indices without
rounding an exact included outer minimum below zero. Root ownership uses exact
N/B, with B=D.y-p*D.x-q*D.z and N=y00+p*(A.x-x0)+q*(A.z-z0)-A.y. Bounds and
diagonal tests cross-multiply; no divided coordinate decides ownership.

The finite expression inventory has lowest possible bits no lower than2^-2450
and a loose largest magnitude below2^80, requiring at most2531bits. Slopes have
lowest possible bit2^-151, A/D operands2^-1074, source X/Z lie on2^-32 lattice,
and only the documented products (at most two slopes, A and D) are constructed.
Canonical coordinate/root millimeter comparisons add a bounded integer factor.
Rounded height conversion searches only existing GroundSample[-2000,100000],
never maxfinite. The sum of adjacent binary64 operands has lowest bit2^-1074;
the midpoint itself could have bit2^-1075. The implementation compares2*abs(N)
with(l+u)*B instead of explicitly forming that midpoint. B's lowest possible bit
is2^-1225 (one slope factor2^-151 and one D factor2^-1074), so the actual product
has lowest bit2^-2299. Even explicitly forming a midpoint would give2^-2300,
still above the conservative2^-2450 inventory minimum. Denormal next-to-zero
midpoints therefore do not require another limb or silently underflow a tie.
Accepted geodesy Earth-scale differences are <2^30 and rotated unit components
<4: ECEF Earth radius plus admitted anchor heights are <2^24, a subtraction is
<2^25 and the three-component rotation is <3*2^25<2^27. Those are proof bounds,
not new input clamps. Exact kernel storage/exponent checks still fail closed.

Final root rounding first tries an approximate quotient and an exact certificate
within four positive binary64 bit neighbors. Uncertainty uses bounded bit-order
binary search (at most63 comparisons) and exact nearest-even midpoint comparison.
No uncapped nextafter loop, long-double assumption or libm precision claim occurs.
Millimeters use exact numerator*1000/denominator integer comparisons and exact
half ties away from zero. Private tests may cover these helpers separately from
actual provider tests, with access arranged only by Root.

Coverage uses finite ordered-bit comparisons (signed zeros equal), including for
rectangle reversal/bounds and binary search against canonical lattice vertices.
Thus a subnormal query coordinate is not erased by DAZ. It checks4096 touched cells before any height
read and neither allocates nor throws. Query strings in returned values may
allocate under the accepted contract; arithmetic scratch remains fixed local
storage. Actual stack, preparation/query timing, allocation, RSS and peak remain
unmeasured until Root's reviewed builds/tests. No real-time/resource pass is
claimed by this source packet.

Definition admission has no caller-FENV precondition: origin lattice and finite
friction ordering use raw-bit exact tests; valid f32 heights are promoted to
normal binary64 values without consuming f32 arithmetic. Query geodesy/normal
calculation fails invalid_data if rounding is not nearest or x86 FTZ/DAZ is set,
without changing caller state. Numerical frame operands are constructed per query
only after that check; preparation cannot cache a bad frame for later queries.
Qualification must record its actual FP environment and retain targeted mode
checks separately from ordinary conformance, without treating another mode as
an extra public Definition-admission rule.
