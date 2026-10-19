# Exact dyadic admission witnesses

Private source-only independent fixtures, 2026-10-18. No producer, provider,
consumer, compiler or helper execution occurred. Root must review/execute/freeze
this separate packet before implementation. Existing frozen references and output
tolerances remain unchanged. This adds no ABI or payload and responds to no
consumer failure; it distinguishes the already required exact mathematical
admission predicates from accidentally rounded binary64 comparisons.

The smallest positive binary32 subnormal is epsilon=2^-149; raw80000001 is its
negative. For spacing2 and heights[-epsilon,32,0,32], triangle0 uses P00,P01,P11:
its coefficients are p16 and q=epsilon/2, so squared norm is256+2^-300. Triangle1
uses P00,P11,P10: its coefficients are p=16+epsilon/2,q0, giving squared norm
256+2^-145+2^-300. Both exact positive excesses violate norm<=16. Binary64 may
round32+epsilon to32 and256+2^-300 to256, wrongly admitting both. The positive-zero
control[0,32,0,32] has exact norm16 and MUST admit. With the specified origin and
anchor height100, its anchor-query surface height is116 and normal is
(0,-16,-1)/sqrt257.

For the span fixture, each of two identical rows has513 vertices. Columns0..511
hold exactly4*i; the last value is2048-1/32=2047.96875, raw44ffff00. Thus the
control's exact extrema plus two1/64 margins yield span2048, which MUST admit.
Replacing BOTH rows' first heights (indices0 and513) by-epsilon keeps the rows
identical: q0, first-cell p=1+epsilon/4, intermediate p1, final p127/128. Every
gradient is safely below16. Its exact span alone becomes2048+epsilon and MUST
reject. A rounded binary64 bracket instead loses epsilon at its low endpoint.
Exactly1026 validity bits require16 full uint64 words and final word3,17 total.

At anchor/query angles0,0, height100 and grid origin(-1024,0), the query is exactly
(X,Y,Z)=(0,h-100,0). It owns column256,row0,triangle0: an internal east line and
the included outer south minimum. Up at column256 is1024 and local p1,q0; therefore
ellipsoid surface height is1124 and NED normal(0,-1,-1)/sqrt2. This independently
confirms the optional control sample; caller altitude/header echo and unchanged
frozen height/normal tolerances still apply. Rejected inputs yield no provider.

The stdlib-only producer converts explicit raw binary32 words through struct to
exact Fraction values (binary32 promotion to binary64 is exact). It verifies these
closed-form coefficient/extrema identities and emits the full source vectors and
rational bounds. It performs no generic grid traversal, interpolation, production
validation, encoding or provider query. The fixed integer-height construction uses
only exactly representable multiples of4. Normal mode writes JSON to stdout;
bounded --check compares an expected JSON artifact without writing files. Root
records interpreter and actual generated hashes separately. Source datum accuracy,
licensed geography and runtime adoption remain outside this numerical packet.

Root publication note: the source-only wording above records the independent
authoring state. Root subsequently reviewed the complete packet and exact
closed-form math, confirmed the proposed core/header binding, generated the
expected artifact and ran its bounded --check using retained Windows
CPython3.12.14 before any provider or decoder implementation. Public files use
explicit LF; raw producer/oracle hashes are included in expected-v1.json and CI.
This execution proves the independent arithmetic packet only. Native component
conformance, geography, rendering and flight acceptance remain separate.
