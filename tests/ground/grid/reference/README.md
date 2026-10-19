# Independent resident-grid numerical reference packet: admission revision

Source-only revision, 2026-10-18. The historical gradient-cap2 packet and its
qualified expected artifact remain unchanged. This separate packet proposes only
max_gradient_norm=16 before any provider or consumer exists. Revised contract/header
hashes bind Root's proposed bytes; checked acceptance is still pending. Neither producer nor provider was executed by this
agent. Root must review and execute the producer, retain exact interpreter version
and source hashes separately, and freeze its resulting JSON before implementation
starts. The deterministic JSON deliberately omits interpreter/build metadata.
There are no geographic facts, source licenses, aircraft claims or runtime passes
in these explicitly synthetic fixtures.

`source_oracles.json` fixes the hand-derived inputs and expected exact geometry.
`reference_producer.py` emits outward-rounded reference intervals using only Python
standard-library Decimal. The emitted artifact includes hashes of both source files.
It neither imports nor reads a consumer, and does not compute cells, barycentric
coordinates, ray/triangle intersections or terrain interpolation. Root may adapt
fixture construction to the accepted typed API; expected values must remain bound
to these independent source bytes.

## Independent analytic construction

At the zero-latitude/longitude anchor, EUS(X,Y,Z) maps to ECEF(a+Y,X,-Z), with
a=6378137. Therefore a same-angle query is exactly X=Z=0 and ellipsoid height Y.
NED at that anchor is (-Z,X,-Y). Flat and slope heights and rational normals follow
directly from those planes, independently of any mesh implementation.

For saddle heights [0,2,2,0], the two actual facets are Y=2(v-u) and Y=2(u-v).
At u=v=1/2 the chosen triangle0 height is0, whereas bilinear interpolation gives1.
At (u,v)=(1/4,3/4) and its transpose the actual height is1, while bilinear gives1.25.
The crease has two normals; exact diagonal ownership fixes triangle0's sign.

For the off-anchor equatorial longitude lambda, the geodetic ray is
X=(a+h)sin(lambda), Y=(a+h)cos(lambda)-a. Eliminating h against plane Y=pX gives
a+h=a/(cos(lambda)-p*sin(lambda)). This is the producer's only intersection
calculation. It is a closed-form plane identity, with no triangle or grid search.
The local NED normal is
(0,-(sin(lambda)+p*cos(lambda)), -cos(lambda)+p*sin(lambda))/sqrt(1+p*p).
The exact binary64 longitude is frozen by hex, not a decimal pi approximation or
a mathematical half-angle later rounded by different callers.

The high-latitude operand is the binary64 nearest familiar pi/4 value, also pinned
by hex. It is not claimed to be exact mathematical pi/4. WGS84 eccentricity and
prime-vertical radius are derived from the defining decimal inverse flattening.
The geocentric radial vector has positive canonical south component
e2*sin(phi)*cos(phi)/sqrt(cos(phi)^2+(1-e2)^2*sin(phi)^2), whereas geodetic up has
zero canonical horizontal components. The producer emits both and the incorrect
radial intersection displacement for a flat Y10 plane. The valid same-angle query
still returns exactly ellipsoid height10 and NED(0,0,-1).

## Interval construction and execution boundary

Every Decimal arithmetic operation is outward rounded at110 decimal digits.
Sqrt uses a correctly rounded Decimal sqrt, widened to each adjacent Decimal.
Sin and cos use100 Taylor terms for |input|<=1. A symmetric1/200! remainder
encloses the omitted tail for both sums; interval arithmetic encloses prior
roundoff. No math.sin/cos, Decimal pi approximation, mpmath or external package is
used. The two binary64 angle inputs are converted exactly with Decimal.from_float.
Normal mode writes JSON only to stdout. `--check expected.json` instead reads at
most1MiB UTF-8, rejects duplicate keys/nonfinite constants, and compares parsed JSON
for semantic equality, returning nonzero on mismatch. It writes no file. This
avoids Windows/Linux stdout-newline differences without weakening raw LF source
hash bindings. The executor chooses the initial output path and records its checksum
separately; no generated result is present or claimed yet.

These tight mathematical intervals EXCLUDE the accepted consumer's binary64 ECEF,
trigonometric and frame-rotation error. Before any consumer output, Root approved
off-anchor absolute qualification targets1e-4m for height and1e-9 for each normal
component. These are engineering acceptance targets at the existing0.1mm canonical
frame consistency scale, not rigorous bounds on every MSVC/libm transcendental or
geographic source accuracy. Do not enlarge them after observing a mismatch. Anchor
special-case fixtures avoid that conversion uncertainty and retain1e-10m height
and1e-12 normal-component targets, distinguishing the frozen near-edge and saddle
errors. Original query altitude/header copies remain exact equality checks. The
existing normalized normal contract also remains independently applicable.

Proof bounds use the EXACT binary64 values of the header's frozen hexadecimal
thresholds, converted with Decimal.from_float, rather than nearby mathematical
decimal0.002/0.999995 values. Thus the emitted derivative, normal and bracket-span
intervals enclose the actual admission thresholds. Their useful rounded limits
remain greater than0.95, greater than0.059 and less than4.096021m respectively.
The derivative bound is minUp-16*sqrt(2)*maxHorizontal and the unit-normal bound
is that numerator divided by sqrt(257). The horizontal bracket span uses the
unchanged direction/bracket constraints and therefore does not change.

## Ownership, missing support and boundedness

The internal edge/vertex fixtures use one flat cell adjacent to an east slope.
Their different normals expose lower-index or arbitrary earliest-triangle choices
without adding a diagnostic triangle-index API. The two2^-24m fixtures place the
actual anchor query strictly on each side; neither may be snapped by a1e-7m band.
They depend on the author's proposed exact2^-32m origin lattice. If Root instead
freezes integral-only origins, these two are intentionally NOT admissible provider
fixtures; retain their mathematical counterexample but replace them with separately
frozen off-anchor closed-form inputs. Binary64 origin0.1 MUST be rejected under
either restriction. At most46 significant bits represent a bounded2^-32m lattice
origin plus an integral grid displacement, so canonical vertices remain exact.

The missing-fourth-vertex fixture has an extra fully valid spare cell. A2x2 grid
with one invalid vertex would reject during prepare and could not test sample's
all-four-vertices support rule. The4x2 construction is admissible and exposes a
consumer that considers only the selected triangle. NoData source uncertainty is
separate from the reference arithmetic: unknown geographic vertical registration
cannot be converted into a numerical confidence interval by this reference.

The4096-cell coverage fixture ends at63 rather than64 because an exact closed
maximum64 owns the next cell. Its companion rectangle tests the explicit budget
failure. This does not assert a flight-motion footprint or readiness theorem.
Memory figures include actual uint64 validity-word rounding, not byte-packed bits.
They exclude vector capacity and allocator overhead; the full definition cap must
also account for capacities, strings and control objects. Maximum query candidate
range6x6 and the derivative/normal lower bounds follow the contract proof; the
producer independently evaluates those closed forms but does not run a search.

## Deliberately unproved cases

This packet does not yet provide executable C++ conformance adapters, a rigorous
binary64 consumer conversion bound (the fixed engineering targets above apply),
full material polygon classification fixtures,
all malformed-definition cases, memory-capacity rejection allocation fixtures, or
actual query-budget overflow instrumentation. Those require separate focused
tests after the typed contract is frozen. The constrained2m/4m query geometry makes
64-cell overflow unreachable for an admitted finite input satisfying the stated
cone/span bounds; no fake ordinary geographic input should be invented to claim
that internal guard was exercised.

## Why this admission revision is independent of consumer results

Root reported a retained source raster assay before any grid provider exists:
100240144 valid samples,0 NoData and0 nonfinite; maximum projected-source facet gradients
at2m/4m decimation were8.835039/5.66985, with6226/1476 cells over the historical2
limit. The proposed cap16 is chosen to support steep features without inventing holes
or flattening source terrain; the actual compiled grid still requires admission. It remains an engineering admission bound, not an
aircraft slope capability or a geographic accuracy claim. No implementation
output, test failure or tolerance fitting motivated this source-only revision.

All prior flat/slope/saddle/ownership/missing/memory fixtures, frozen binary64 input
angles and qualification tolerances remain unchanged. The rejected gradient
fixture changes only its two positive heights to32.000003814697265625: Float32
spacing at32 is2^-18, so dividing the height difference by2m gives16+2^-19,
strictly over16. The former rejected4.000000476837158203125 heights are explicitly
NOW ADMITTED; their slope is2+2^-22 and anchor height is2.0000002384185791015625.
Their NED normal is(0,-8388609,-4194304)/sqrt(87960946999297), obtained by clearing
the slope's exact denominator2^22. This guards against silently retaining cap2.
An exact-boundary acceptance case uses heights[0,32,0,32], so the east gradient
is exactly16, the anchor height16 and normal(0,-16,-1)/sqrt(257). This prevents
mistakenly replacing the inclusive bound with a strict less-than comparison.
