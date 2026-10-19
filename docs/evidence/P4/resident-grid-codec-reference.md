# Resident grid byte-reference qualification

Prepared under [#243](https://github.com/brettbergin/flight-simulator/issues/243)
for the proposed [payload contract](../../contracts/world/resident-grid-codec-v1.md)
and [typed header](../../../native/world_core/grid/include/flight/ground/grid_payload.hpp).
This is reference construction and header syntax, not a working decoder, provider,
renderer or admitted geographic world. Checked contract acceptance precedes consumers.

Root reviewed the complete source specification and independent literal producer,
hand offsets and raw-word expectations before running any producer. The producer
uses only standard-library explicit little-endian packing of two fixed fixtures;
no production encoder, decoder, provider or data tool supplies expected values.
The independent owner's source-only status remains historical in the frozen oracle.

Root executed generation and `--check` with the frozen Windows CPython3.12.14
(executable SHA256 `d41bad46673f64e0d02f23797f53f90ccf60f27d6eda8d86dd2d4bbeae5a858c`).
A separate reviewed verifier matched every literal hex block and every contiguous
header/body field offset, raw numeric word and complete length across all341bytes.
It independently checked the maximum structural-size formula and gradient16
mutation arithmetic before any decoder implementation. Both commands and the
literal/offset verification passed. Exact execution receipts remain local.

The complete pure decode header passed an MSVC19.40.33813.0 C++20 syntax check
with `/permissive- /W4 /WX /fp:strict /MD /EHsc`, including exact function-pointer
type and constant assertions. No decoder/provider was linked or run. Header SHA256
is `625c89c99f284d6cfcaa826470f27457958670bd6cdc3e2662791599eb73d61f`.

| Input or fixture | SHA256 |
| --- | --- |
| Codec specification | `060f267d64bb058059791c762db724d39f9c99d907926868d2f9c2634ffeb0e3` |
| Independent producer | `91107b6502f761d3fc928508f4496460dee3b91e9d2acd0bff529321db4fb6d2` |
| Hand-derived oracles | `d84825f145a24755b48028de2546df2bb411103627459619ee2b5e68e4d80c59` |
| Generated expected JSON | `966744c0120b7e66c072c6034aa1c54b9871df44825fc66e5de0cf55190fee0c` |
| golden-a,195bytes | `7abb9551cf82cea00dc382c01bd3d675f91a1306cb9b09b0b039c1bf5fb5aa17` |
| signed-zero-b,146bytes | `df832af1c57d060299135d16b7bfedd59e66a4611a8337f9cac2693f24a155e3` |

The [reference packet](../../../tests/ground/grid/codec/reference/README.md)
freezes complete decoded raw-bit expectations, every truncation position, reserved/
count/size/endian/enum/ID/sentinel/mask/gradient/span/origin/ring/friction mutations
and honest large-size boundary specifications. A single swapped height can be
valid different little-endian data; no endian repair or invented priority enum is
allowed. Signed zeros must survive decode. Large-count declarations do not justify
large allocations before remaining-byte checks; no fabricated oversized span is a
valid resource test. These are future conformance inputs, not executed rejection
or memory-limit results.

The proposed cap16 update changed only core bindings and gradient admission cases.
Golden fixture bytes and all other limits/tolerances remain unchanged. The former
cap2 over-limit uniform east plane is explicitly admitted; raw32+2^-18 over2m
remains rejected. No provider/decoder failure or tolerance fitting caused the change.

After checked acceptance this seam permits standalone native decoding/conformance
and a separately reviewed standalone Godot byte reader using the same payload.
It does not select a world file, datum transform, compiler, source/start/history
tuple, native Session or gameplay renderer. Those remain #243 work with separate
complete contracts and integrated evidence. Source rights, WORLD016 accuracy,
aircraft, human/pilot, installed delivery and P3/P4 gates remain open.

The first local JSON stdout capture used Windows CRLF and is retained as historical
execution output (SHA256 `64bf9d4e5ac84373cc9ab6f25b83fef3315127358d8d4eb1dd49d9ef48390980`). Before consumers, the public expected JSON
was normalized to repository LF, with parsed values and both complete payload hex
strings verified identical. Its table above and CI use the canonical LF hash.
Explicit attributes also preserve the producer/header bytes on Windows checkouts.
No fixture payload, oracle value, API or tolerance changed during this publishing fix.
