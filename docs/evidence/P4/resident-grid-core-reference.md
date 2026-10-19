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
| Typed contract | `7c4dae103811d178117bb423d2c9bf82d42830985157b870002c274d1d3010c8` |
| Header | `de37194ce0613ee5b1e0cc603e8885092bced5adab7aa3835e29c9471868ee86` |
| Producer | `b7b2048bce0d468d77941395de4cd838905b6cbb8e7ef5fd07dd02b234e1400e` |
| Hand-derived cases | `36edd42c7a140d5f5b2930a6d30d48dba95a8f7526816882ce3a498034a92857` |
| Expected artifact | `251c01cd286b946b46d0422be53d251d47274403696b31892a5995f293103a8a` |

The reproduced lower derivative bound is greater than 0.994, lower surface-normal
dot query-up bound greater than 0.44, and upper horizontal bracket span less than
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
No wheel was installed/imported and no terrain tile decoded or transformed under
this evidence. The original interpreter installer provenance is unavailable; the
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
