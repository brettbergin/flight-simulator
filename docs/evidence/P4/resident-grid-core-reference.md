# Independent resident-grid core references

Proposed component acceptance under [#243](https://github.com/brettbergin/flight-simulator/issues/243),
2026-10-18 Pacific. The [typed contract](../../contracts/world/resident-grid-core-v1.md)
is deliberately smaller than geographic airport admission. There is no grid
provider implementation, native terrain result, renderer or new playable airport
in this evidence.

Root reviewed the independently authored [reference producer](../../../tests/ground/grid/reference/reference_producer.py),
[synthetic hand-derived cases](../../../tests/ground/grid/reference/source_oracles.json)
and [construction explanation](../../../tests/ground/grid/reference/README.md)
before executing them. The producer uses only standard-library Decimal interval
arithmetic at 110 decimal digits, fixed binary64 angular operands and closed-form
plane intersections. It imports no provider, geodesy consumer or project helper.
The exact threshold operands are the header's binary64 hexadecimal values.

Root executed Python 3.12.14, MSC v.1944 x64, with `-I -B`, executable SHA256
`d41bad46673f64e0d02f23797f53f90ccf60f27d6eda8d86dd2d4bbeae5a858c`.
Both initial generation and `--check expected-v1.json` exited 0 with empty stderr.
The [frozen expected artifact](../../../tests/ground/grid/reference/expected-v1.json)
is UTF-8 LF; source hashes in it bind the exact producer and hand-derived cases.
CI compares the reviewed input hashes before independent reproduction on both OSes.

The proposed header passed a standalone C++20 syntax/type check with MSVC
19.40.33813.0, `/permissive- /W4 /WX /fp:strict /MD`, using the bootstrap's compiler
environment. Pinned CMake 3.31.8/Ninja 1.13.1 built the existing headless ground
boundary test; CTest passed 1/1 (`ground_contract`). This checks header integration
and the unchanged boundary, not a grid implementation. Schema generation checked
all 14 existing contracts, their 11 JavaScript contract tests passed, and the
documentation validator passed 137 issues/147 requirements/214 Markdown files.

| Input/artifact | SHA256 |
| --- | --- |
| Typed contract | `9e4ef15be255624405b917efce41fbbb7333c89072d586d75a7cfa0d472197df` |
| Header | `7b7f7dee3875cf67d9df8057405fc729ec72da4570dfcd5f8a4dca755d6e96f3` |
| Producer | `6bccd5b7f3490b29b8ace59ea42acf4f773477730cb9df4b74e31a36d7f31835` |
| Hand-derived cases | `55cb32169a5aa8d07d6008423939e30ae3fa027499f030c162a8e57bac67fc0e` |
| Expected artifact | `54a9c451234b37d2d621492c75ec581a0d0f57698bf3bab3d8fbd573b484bd7d` |

The reproduced lower derivative bound is greater than 0.95, lower surface-normal
dot query-up bound greater than 0.059, and upper horizontal bracket span less than
4.096021 m. These prove the mathematical constraints for the proposed admission
bounds, not the correctness or speed of a nonexistent native search.

The independent cases distinguish actual triangular facets from bilinear smoothing,
geodetic from geocentric rays, higher-index exact edges from lower neighbors, and
both sides of a 2^-24 m edge offset from an epsilon band. They include a missing
fourth vertex despite a valid selected triangle, sentinel/padding/gradient/span
rejections, a separate 4096-cell rectangle budget and exact logical memory sizes.
Full polygon/material conformance and native malformed-input tests remain component
implementation work. Point-query overflow is unreachable under the admitted
cone/span limits; no ordinary fake fixture claims to exercise that guard.

Root also reviewed the independent [material cases](../../../tests/ground/grid/reference/material-oracles.json)
and their [integer/rational construction](../../../tests/ground/grid/reference/materials-README.md).
They freeze actual same-angle provider expectations for convex/concave polygons,
included edges/vertices, priority then ASCII-ID order, default material and exact
friction copies. Explicit malformed rings distinguish nonzero winding from
simplicity. Exact half-mm rational tie cases are separately labelled private
arithmetic tests; no fabricated geodetic half-tie query or new public API is used.
These are reviewed independent expectations, not executed native conformance.

The separate [offline authoring tool lock](../../contracts/world/terrain-tools-v1.md)
fixes acquired wheels, database and grid plus the retained Windows interpreter.
Root rechecked all wheel/grid/database/inventory byte identities against that lock.
No proposed wheel was installed/imported and the sealed authoring environment
has not been qualified. A separate exploratory source assay is recorded below;
it supplies no compiled grid or datum transformation. The original interpreter installer provenance is unavailable; the
lock explicitly supports the retained local runtime rather than claiming a
fresh-machine bootstrap. Coordinate operation and codec contracts remain separate.

Mathematical intervals exclude binary64 consumer conversion error. Engineering
qualification tolerances were fixed before any consumer existed: same-angle
anchor height 1e-10 m and normal components 1e-12; off-anchor height 1e-4 m and
normal components 1e-9. They are not survey accuracy or rigorous bounds on every
CRT transcendental implementation, and must not expand after a failed comparison.

Contract and reference acceptance permits only the standalone native component,
CMake integration and headless component tests. File encoding, datum/tool pins,
real-source transformation, flight/source/history admission, visual mesh adoption,
integrated KAWO circuits, portable delivery and human/pilot evaluation remain open.

## Source-informed input admission before implementation

Root separately decoded the exact pinned USGS tile using existing bundled Pillow
12.3.0/NumPy 2.3.5/Python 3.12.14 as an exploratory source assay. This did not use
or qualify the proposed sealed wheel environment, compile terrain or transform a
datum. It observed 100,240,144 finite source samples, no -999999 NoData values,
and source elevations approximately 9.46 to 181.96 m NAVD88. Uninterpolated source
sample strides of 2 m and 4 m had maximum projected-source facet gradient norms
8.835039 and 5.669850, with 6,226 and 1,476 cells above the initial proposed limit
2. These are source-frame observations, not canonical EUS or geographic accuracy.

The proposed input limit was therefore revised to exactly 16 before any provider
implementation. This supports steep features without requiring flattening or
invented holes; the compiler must still validate its actual canonical output.
The independent producer recomputed the monotonicity and normal lower bounds
above, with the same ray cone, bracket span, search caps and output tolerances.
All prior off-anchor/high-latitude intervals and qualification tolerances compare
exactly equal. New independent cases admit exactly 16 and the former 2+2^-22 case,
and reject 16+2^-19. No consumer failure or output fitting motivated this revision.

The initial proposed reference epoch remains retained in PR246 commit 37adaf3 and
local raw evidence. It is historical source-only proof, not acceptance of a grid
implementation or a geographic world. The revised current-head references must
pass their own checked acceptance before consumers begin.

## Additional exact admission witnesses before implementation

Root reviewed and executed the separately authored [exact-admission packet](../../../tests/ground/grid/exact-admission/reference/README.md)
using the same retained Windows CPython3.12.14. Its stdlib Fraction/struct
producer and bounded --check passed before a native provider or decoder existed.
These cases preserve all current contracts, reference bytes and output tolerances.
They distinguish the already required exact predicates from rounded binary64
comparisons: heights [-2^-149,32,0,32] at spacing2 yield squared gradient
256+2^-300 and 256+2^-145+2^-300, both forbidden; the zero control admits.
A separate 513x2 spacing4 grid admits exact bracket span2048, but replacing
the first height in each row by -2^-149 yields forbidden span2048+2^-149
while every gradient remains below16. The anchor control has independent
height1124 and NED normal(0,-1,-1)/sqrt2. No native pass is claimed.

| Additional artifact | SHA256 |
| --- | --- |
| expected-v1.json | `3df724576eeada629a65a18c23c72abeb08937f7e8d5bae6c3d66d29bda32f3a` |
| hand-oracles.json | `30163ea0c410759a8314d6244b0c07d16affe412888d285bd9ee88b7872dfbdb` |
| README.md | `e32c483bc4aa18bf0c690fa7aa1a6f3b2b2fabb850ed35d8f0c4ab14c6e47b6d` |
| reference_producer.py | `51ff636c606155ce1f8a31d819f07b5f98520f14acb08050daca1e1538a26ae2` |
