# Independent material polygon fixture delta

Source only, 2026-10-18. This small corpus supplements the frozen geometry
reference and changes neither its bytes nor the public contract. No producer,
provider, helper or process was executed. Root must review and hash these LF
sources before implementation. All coordinates, identities and friction values
are explicitly synthetic.

`material-oracles.json` separates actual provider samples from internal arithmetic.
For every ready provider case the anchor and query angles match at0,0, the surface
is flat Y10 and the actual root is exactly X=Z=0. Thus integer-mm polygons can
independently establish cover, exclusion, edge/vertex inclusion and material order
without inventing a geographic position that happens to land at a chosen point.
The height stays10 and NED normal stays(0,0,-1). Material IDs and both friction
coefficients must copy the selected material exactly; all coefficients were chosen
dyadic so that binary64 introduces no decimal conversion dispute. Existing exact
header/request-position/world-identity checks still apply to ready samples.

Every accepted ring has negative shoelace sum in ordered(east,south), implicit
closure and distinct points. The L-shaped ring contains the origin in its left
arm; the larger notched ring excludes the origin inside its removed middle notch.
Their bounding boxes both contain the origin, exposing bounding-box-only tests.
Forward collinear segments are accepted because they share only their common
endpoint; reversing over an adjacent segment is rejected. The self-crossing ring
has nonzero NEGATIVE twice-area -360000mm2, so it cannot pass merely because an
implementation checked winding and nonzero area. Its nonadjacent edges1 and3
intersect at(-600/7,-600/7)mm, strictly inside both segments. No epsilon is needed
for any sign or boundary decision in these integer fixtures.

Priority0 versus255 establishes the entire uint8 ordering. The equal-priority
case intentionally places a boundary-containing `a-pavement` after strictly
containing `b-grass`; ASCII ID wins independently of array order or boundary type.
Repeat that case with reversed input order. Default applies when no polygon
contains the point, including a high-priority polygon elsewhere. The missing
support fixture retains a separate fully valid cell so preparation succeeds; each
of the three explicit missing reasons must survive even beneath a covering
high-priority material polygon. Material classification cannot fill terrain holes.

The half-millimeter cases are exact rational INTERNAL arithmetic tests. They do
not describe actual provider sample inputs. The six signed half/neighbor values
are +/-1/2000m and neighbors differing by1/2^40m. Their common denominator is
125*2^40=137438953472000; the half numerator is2^36=68719476736 and each neighbor
changes it by125. Multiplying by1000 gives exact signed half-mm values and
neighbors, proving nearest ties away from zero. Positive and negative narrow
integer polygon strips then show how the quantized point's included boundary
differs from its toward-zero neighbor. These may exercise a private implementation
seam or exact arithmetic unit after the contract merges; they grant no new public
API and no geodetic half-tie guarantee. Source uncertainty and float conversion
qualification remain separate from these exact integer/rational proofs.

This delta does not claim executable conformance, runtime friction application,
licensed geographic pavement, tire calibration or flight integration. It does not
provide a parser or a second polygon implementation. Parent native tests should
construct the listed definitions directly and assert the frozen outcomes.
