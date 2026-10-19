# Standalone resident-grid component

Implementation for [#249](https://github.com/brettbergin/flight-simulator/issues/249)
consumes the checked [core](../../contracts/world/resident-grid-core-v1.md) and
[payload](../../contracts/world/resident-grid-codec-v1.md) contracts from PR246.
Root integrated separately authored implementation and independent native tests,
reviewed their complete sources before execution, and obtained an independent
implementation review with no actionable correctness findings. The accepted
public headers, three reference packets and engineering tolerances are unchanged.

This provides an owned immutable physical grid and a pure byte decoder. It does
not install a world, compile USGS data, evaluate a datum transform, alter the
flight library or render terrain. Current game, profiles and the human package
remain unchanged. Airport, aircraft, pilot and phase gates remain open.

## Executed Windows qualification

Root used CMake3.31.8, Ninja1.13.1 and MSVC19.40.33813.0 on Windows x64 with
C++20, `/MD /W4 /WX /permissive- /fp:strict /EHsc`, RelWithDebInfo.
The first compilation refused an implicit int-to-byte `std::fill` in the codec
test under warnings-as-errors. That attempt is preserved. The only correction
made the zero explicitly `std::uint8_t{0}`; expected values did not change.
A fresh build passed all four CTests, as did a fresh run through the public
[CI entry point](../../../tools/ci/resident-grid.ps1):

| CTest | Independent checks | Result |
| --- | ---: | --- |
| resident_grid | 784 | PASS |
| grid_payload | 1554 | PASS |
| grid_private_arithmetic | 24 | PASS |
| ground_contract, existing unchanged suite | 41 | PASS |

Tests include frozen facet/off-anchor and exact gradient/span controls, internal
and outer edges, material rings/ties, physical missing support versus irrelevant
padded candidates, 4096-cell coverage bound, ownership/lifetime and concurrent
const queries. FENV tests restore complete caller state before concurrency and
distinguish raw subnormal origins/friction/coverage under FTZ/DAZ. Preparation
does not impose a new FENV admission rule; sampling refuses an unsupported
environment without silently changing it. The private arithmetic suite checks
nearest-even binary64 rational ties/subnormal zeros and exact half-away
millimetres, including the predeclared anti-double-rounding witness.

The codec checks both literal payloads, every strict prefix, appended bytes,
unaligned input, counts/remaining spans, raw signed-zero ownership, sentinel and
semantic failures. A complete structural pass precedes height/mask allocations;
the short-body/max-dimension case owns its actual small byte buffer. No fake
large span or enormous stress allocation is used. Exception tests distinguish
`invalid_argument` from unrelated failures.

## Source and execution identity

The implementation is a standalone static `flight::resident_grid` target, using
one private semantic validator. Its fixed-stack 96-limb dyadic arithmetic and
exact rational certificates are documented in
[arithmetic notes](../../../native/world_core/grid/src/arithmetic-notes.md).
The private arithmetic include is confined to its separate qualification target.
No new external dependency or public testing seam is introduced.

| Reviewed implementation source | SHA256 |
| --- | --- |
| src/exact.hpp | `97542cbf0a8a14c24c759765f5b43da1864ff87060adce5d0777668c36e2720c` |
| src/validation.hpp | `a7603f9b9d8897a661414c4b6514d462858ed33e7546be6f33b4f690f26b7f93` |
| src/validation.cpp | `02bc38d1b9bcf8f22db1d62d4c2e90301d8f37db014c6fc7d8f2f1b7fab33b14` |
| src/prepared_grid.cpp | `a489dca3e7b7aa23574cdf5df43debd2b8e3971650d6d8af54e0d2982a314edd` |
| src/grid_payload.cpp | `a761569a80f96db9a8b0997fcad9d05c21d0573814d7cfd5e6e841e5374fb960` |

Local raw build, compiler commands, test output and failed-attempt logs are
retained. Hosted Windows/Linux results belong to the final PR head and remain
pending until the actual checks complete. CI builds this component separately
after the pinned bootstrap and retains its logs, cache and compile commands.
Root native source rosters/fingerprints, Session, bridge, Scene, models and saves
are unchanged; linking this component into a future flight/world requires its
separate source-closure and runtime acceptance.

## Bounded resource observation

Root separately source-reviewed and ran the optional
[resource observer](../../../tests/ground/grid/resource-observer.cpp) on the same
Windows toolchain in another fresh build. The observer's first compilation
refused a constant-condition warning; changing `if` to `if constexpr` preserved
its fixed grid and loops. Both failed and successful attempts remain retained.
The successful source SHA256 is
`8bd19440c2fe4b23b039c03595edb601b11c70a0752ade3d46323ed7227d3db2`.

The fixed synthetic flat grid is3073x2049 at4m, with6,296,577 vertices and98,385
validity words (25,973,388 logical height/mask bytes). It moves once into the
provider. This is the proposed airport compiler's grid size, not compiled terrain.

| Actual single-process observation | Result |
| --- | ---: |
| Allocate/initialize | 4.6078ms |
| Prepare | 771.4431ms |
| Surface calls, half exact-anchor / half off-anchor | 64valid /0missing |
| End-to-end surface mean | 12.8734375us |
| Closed80m coverage rectangles | 1024ready /0other |
| End-to-end coverage mean | 1.8826171875us |
| Process peak working set | 31,035,392bytes |
| Final process private commit | 26,849,280bytes |

The observer consumes results and reports actual counts. Times include loop,
query construction and returned copies; memory includes process/runtime overhead.
Private commit is distinct from RSS and contractual owned capacity. Flat terrain
is not a worst-case geographic workload. There is no timing pass threshold,
allocation instrumentation, stack measurement, hard real-time or frame-budget
qualification. Coverage's no-allocation/no-throw property has a separate reviewed
source path; these observations do not replace that conformance review.
