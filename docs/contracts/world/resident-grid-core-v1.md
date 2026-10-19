# Immutable resident ground grid core v1

Proposed component contract for #243, 2026-10-18. Checked acceptance plus its
independent numerical fixtures permits the native grid COMPONENT and tests only.
It does not permit a file compiler/loader, geographic pack, native flight/start
admission, Scene/render consumer, datum conversion or source/history change.
Those receive separate exact contracts. No runtime/fidelity/phase pass is claimed.

The complete typed C++20 seam is [prepared_grid.hpp](../../../native/world_core/grid/include/flight/ground/prepared_grid.hpp).
It derives from the existing immutable SurfaceProvider; GroundSample/v1, Boundary,
WorldPackage/v1 and their fingerprints/behaviors remain unchanged. No new ClassDB,
DLL export or durable byte format exists. Definition is an in-process owned C++
value, NOT a packed file struct or cross-toolchain ABI.

## Exact preparation and ownership

`PreparedGrid::prepare(Definition, Identity)` validates and owns its by-value input,
then returns `shared_ptr<const PreparedGrid>`. Callers should move their vectors
rather than retain a second full copy. After a move, the trusted caller must retain
no mutable aliases to transferred buffers; const ownership cannot prove a caller's
honesty. An lvalue pass copies its vectors normally. The provider does not add a
hidden whole-grid deep copy to defend against a caller violating that precondition.
Invalid input throws std::invalid_argument;
allocation failure throws std::bad_alloc. No partial provider is returned.
Preparation may allocate and scan all cells; sample/coverage never do I/O, wait,
access a scene, mutate caches, resize geometry or change identity. Returned samples
and identity strings are owned copies; bounded result-string allocation may fail.
Read-only calls may run concurrently against the immutable object; each caller's
existing Boundary and simulation authority remain separately owned. No mutable
reference to the owned definition is exposed.

Identity obeys the existing ground::v1 validator, including nonzero generation.
The trusted caller supplies the declared exact world/surface identity; this core
validates its grammar, not a cryptographic relation to a nonexistent file codec.
A future loader/catalog MUST separately prove actual payload/definition hashes
before flight use. Core fixtures use explicitly synthetic identities. Accepting a
syntactically valid hash never certifies geographic source or aircraft authority.

Admission is closed:

- IEEE754 binary32 float and binary64 double are required. Spacing is exactly the
  declared enum2m or4m. Columns/rows each2..8193; all multiplications/additions are
  checked before size comparisons or indexing. Vertex n=row*columns+column.
- Up vector length equals columns*rows. valid_words length is ceil(vertices/64);
  vertex n uses bit n%64 in word n/64. All unused high bits in the last word are0.
  At least one cell has four valid vertices. Valid heights are finite and within
  [-1000,4096]m. Invalid vertices have EXACT Float32 bits0x7fc00000 and are never
  used in arithmetic. Any other invalid encoding or valid NaN/Inf rejects.
- Anchor is valid WGS84 geodetic radians/meters under accepted geodesy, with
  ellipsoid_height_m in[-500,10000]. East/south origins and final grid endpoints
  are finite in[-8192,8192]m. Endpoint=origin+(axis_vertices-1)*spacing, strictly
  greater than origin. Origins are exact multiples of2^-32m (ldexp(origin,32)
  must be an exact integer). This retains nonintegral inputs such as2^-24m while
  ensuring every origin+index*spacing coordinate is exactly representable under
  these bounds; nominal2m cells do not become subtly nonuniform rounded vertices.
  Reject nonconforming origins, never snap them during preparation. A future
  compiler must explicitly author this subnanometer numerical grid convention;
  it is not geographic source accuracy or a renderer epsilon.
- Compute Ymin/Ymax from valid promoted heights only. The query bracket is
  [Ymin-1/64,Ymax+1/64]m, using the exact binary margin1/64. Total bracket span
  must be<=2048m. Every fully valid cell's two triangle gradients have Euclidean
  magnitude<=2. Partly invalid cells do not define a usable triangle.
- MissingVertices is one of its three enumerators. All invalid vertices in this
  component share that supplied missing reason; no new nodata wire enum exists.
- Materials1..32, default index valid. IDs use accepted stable_id and are unique
  within each namespace. Each coefficient is finite,0<=dynamic<=static<=5.
  These are supplied effective prototype parameters, not calibrated tire evidence.
- Polygons0..128 with total vertices<=4096; each has3..4096 distinct integer-mm
  points, implicit closure, no repeated terminal point, simple nonzero-area ring
  with NEGATIVE signed area in ordered(east,south), no holes. Each coordinate is
  in[-8192000,8192000]mm. No self intersection/collinear overlap; adjacent segments
  may share only their common endpoint. Material index is valid. Priority is the
  actual uint8 value. Polygon/material IDs are immutable ASCII stable IDs.
- Reject if accounted owned definition capacity exceeds536870912bytes. Count
  vector capacities*sizeof(element), all material/polygon string capacities+1,
  polygon vertex-vector capacities and sizeof(Definition)/Impl control objects,
  using overflow-checked uint64 arithmetic. Allocation bookkeeping/RSS, caller
  copies and peak preparation are measured separately; this cap is not total RSS.

No runtime datum resolver exists in this core. Definition coordinates already
represent one declared canonical working surface. Root's approximate-geographic
registration can supply it only after its separate transform/data contract;
source accuracy unknown does not become a missing vertex when a reproducible
working coordinate is actually defined. Conversely an absent datum/grid cannot
be filled with invented height merely to make this component prepare successfully.

## Canonical triangles and exact ownership

P(column,row)=(east_origin+column*s, promoted up[n], south_origin+row*s).
Rows increase south, columns east. For one cell, define local u,v from X,Z.
The diagonal is P00-P11. Triangle0=(P00,P01,P11), for v>=u; triangle1=(P00,P11,P10),
for v<u. Both wind up. Their planar facets, including creases, are THE surface;
no bilinear interpolation or smoothing normal may replace them.

Point ownership is mathematical half-open X/Z cells: floor((coordinate-origin)/s),
including the outer minimum and excluding outer maximum. Internal grid-edge and
vertex points belong to the higher-index column/row. Exact diagonal belongs to
triangle0. No epsilon widens those geometric regions. A point +/-2^-24m from an
edge keeps its own cell and normal. The previously suggested1e-7m ownership band
is explicitly rejected: it can change a normal by45degrees for tiny height error.

Use robust sign/floor predicates over the canonical binary64 operands (or exact
expansion fallback) to certify ownership. A bounded arithmetic-error interval may
pad candidates or establish a numerical-ambiguity failure, never move geometry.
If the implementation cannot certify a query's ownership/intersection, return
MissingGround::invalid_data. Mandatory independent exact/near-edge fixtures MUST
succeed; ambiguity is not permission to skip those conformance cases. No iteration
or increasing epsilon until a hit is found. Numeric algorithm choice is internal;
observable geometry and failures are fixed here.

## Exact query semantics and bounded search

`sample(Query)` requires valid existing SampleHeader session and geodetic position;
invalid inputs throw std::invalid_argument. Tick may be full uint64. The returned
GroundSample echoes header and requested geodetic position EXACTLY, irrespective
of caller height. Surface height/normal/material depend on latitude/longitude,
not on the aircraft's current height. No external world lookup is performed.

Let U be WGS84 geodetic up at the query latitude/longitude. Let A be the anchor-EUS
projection of ECEF(query latitude,longitude,ellipsoid height0). Let D be U rotated
ECEF->anchor EUS. The line Q(h)=A+hD is affine in ellipsoid height h; it is NOT
parallel to anchor-up except at matching angular positions. At exact matching
anchor latitude/longitude, use the algebraic line (0,h-anchor_height,0), avoiding
unnecessary cancellation. Other transforms use the accepted WGS84 constants and
binary64 geodesy. The independent mathematical intervals exclude consumer
conversion error; the separately frozen engineering tolerances cover qualification,
not a rigorous bound on every CRT/transcendental implementation.

Require finite A,D. Compare abs(D.x) and abs(D.z) against the header's exact
binary64 `max_ray_horizontal_component` (0x1.0624dd2f1a9fcp-9), and D.y against
`min_ray_up_component` (0x1.ffff583a53b8ep-1). These hexadecimal constants
are the exact operands of the <=/>= comparisons; do not substitute exact-decimal
0.002/0.999995 in reference proofs. The independent producer converts these hex
operands exactly with Decimal.from_float. A finite direction outside that cone
returns outside_coverage. Nonfinite conversion returns invalid_data.
Compute hLo=(Ylo-A.y)/D.y and hHi=(Yhi-A.y)/D.y and the horizontal X/Z bounds of
Q(hLo),Q(hHi), using outward arithmetic bounds for search certification.

The PHYSICAL closed bracket rectangle must lie inside [origin,outermax) in X/Z;
otherwise outside_coverage. Exact outer-minimum equality is allowed. If arithmetic
cannot certify that relation, invalid_data. All physical support cells touched by
the closed bracket rectangle must have four valid vertices. For this support check,
first=floor((minimum-origin)/s), last=floor((maximum-origin)/s), inclusive. Missing
support returns the Definition's selected missing reason, without height/normal/
friction. A supported point inside a larger missing bracket is conservatively
missing; do not skip a hole and select a more convenient root.

For triangle search use first-1 through last+1 inclusive per axis, clamped to
valid cell indices. These are CANDIDATE neighbors, not extra required coverage;
a padded neighbor outside the physical support need not be valid. At spacing2m,
normal-cone and bracket limits bound horizontal span to4.096021m per axis and
candidate range to at most6x6cells. Enforce64cells/128triangle tests. Overflow or
larger certified count returns invalid_data; never run an unbounded search.
Intersect candidate planes against Q(h), retain h in the bracket and exact owning
cell/triangle, and return the one owned intersection. Conflicting/nonunique or
uncertifiable intersections return invalid_data. Do not select lowest h/index as
a substitute for the ownership rule.

On fully valid continuous support, F(h)=Q.y(h)-gridUp(Q.xz(h)) has directional
slope >= min_ray_up_component - 2*sqrt(2)*max_ray_horizontal_component >.994
on every facet. Thus its root is unique, and
unit surface-normal dot query-up>.44. Exact ownership preserves continuity; fuzzy
edge extrapolation does not. These bounds preclude near-parallel plane division.
No derivative/Newton/bilinear root solver is needed.

Compute the owning facet's unit upward normal from its exact promoted vertices;
rotate anchor EUS->ECEF->query-local NED. Result has unit norm within existing
1e-9 contract tolerance and negative down component. Return solved h as ellipsoid
surface_height_m, never anchor Y or radial ASL. A result outside existing valid
GroundSample representable bounds returns invalid_data. Shared physical/render
agreement concerns these canonical facets; GPU precision/LOD is outside this core.

## Material classification

Use the solved root's X/Z, separately from triangle membership. Quantize each to
nearest integer millimeter with exact half ties AWAY from zero. This is an explicit
<=0.5mm material-classification quantization only; it cannot move height geometry.
Robust predicates must certify the mm tie or fail invalid_data. All polygon tests
use integer-mm coordinates and overflow-checked int64 orientations/winding. The
coordinate/vertex limits above keep cross products and accumulated ring areas
inside int64. Query coordinates lie inside the bounded grid before conversion.

A polygon boundary is included. Among containing polygons choose highest priority,
then lexicographically smallest ASCII polygon ID. If none, use default material.
Copy that material ID/static/dynamic coefficients into GroundSample with the exact
world ContentRef supplied at prepare. No texture color, object name or height-grid
cell selects pavement. Polygons classify only material, not protected airspace,
water damage or physical obstacle collision. Core material output does not assert
when a flight integrator applies it; current per-gear120Hz friction policy remains
outside this component and must be specified at Session adoption.

## Exact coverage API and separation from motion safety

`coverage(Rectangle)` is a pure conservative geometric readiness query. Inputs are
finite with min<=max in both axes; a zero-area point rectangle is permitted.
Invalid/reversed inputs return Coverage::invalid_data. A rectangle leaving the
same half-open outer bounds returns outside_coverage. Otherwise use the same
first/last floor indices above and examine EVERY touched cell, including cells
owning exact maximum endpoints. More than4096cells returns invalid_data BEFORE
reading their heights. Any missing cell returns the selected Definition missing
reason; all valid cells returns ready. No allocations, exceptions, identity or
state changes occur. Fixed caller/data arrays remain resident.

The4096-cell coverage cap is independent of the64-cell point-query cap. A projected
3.8625m motion footprint plus normal-ray reach can need9x9cells, which exceeds64.
The caller must construct/certify the actual gear/CG/sweep and ray-padding rectangle;
coverage does not construct it or prove motion/force bounds. The old Session guard
is explicitly an engineering policy, not a continuous-motion theorem. No Session
may adopt this core by silently reusing analytic-plane covers() assumptions.

## Independent proof and allowed next leaf

Freeze independent flat/east/south/saddle, exact diagonal, internal edge/vertex,
+/-2^-24edge offsets, outer min/max, invalid fourth vertex, all-invalid, bad sentinel,
count/padding/enum/gradient/span/capacity, non-dyadic origin0.1 rejection, missing
reason and material overlap/tie
cases. Surface height must be unchanged for query altitudes-50,25,1000m. At anchor0,
the hand-derived EUS->ECEF map is(a+Y,X,-Z), a=6378137; expected NED normals are
independent of the producer. Off-anchor normal-ray cases require frozen binary64
angles and independently rounded output intervals before claiming their pass;
the mathematical half-angle ratio alone is not a frozen float input.

The accepted leaf may add `native/world_core/grid/src/` implementation, component
CMake and headless `tests/ground/grid/` conformance only. It may not change Session,
bridge, native fingerprints/rosters, models, loader, file compiler, Scene or saves.
Root reviews final contract+independent fixture bytes, runs appropriate native and
schema/docs checks and merges before that implementation starts. A later exact
payload/compiler contract can materialize Definition; a later world/start/Session
contract can adopt the provider. This checked component alone closes none of the
geographic, runtime, aircraft or parent phase gates.