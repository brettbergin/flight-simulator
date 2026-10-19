# Independent resident-grid byte fixture sources: admission revision

Historical source-authoring packet for the proposed codec, 2026-10-18.
Root subsequently qualified these exact producer/oracle bytes; see
[execution evidence](../../../../../docs/evidence/P4/resident-grid-codec-reference.md).
The authoring-time execution-status field below remains a frozen source fact. It changes no frozen
PR246 files and grants no implementation permission. `hand-oracles.json` binds the
revised proposed codec and gradient16 grid contract/header hashes. The preserved
v1 private packet remains read-only historical evidence; no golden bytes changed. Root must review the
literal packing, independently compare the complete offset tables, then execute
and freeze output before a decoder consumes these expectations. No fixture SHA
is guessed or claimed here.

`fixture_producer.py` uses only standard-library explicit little-endian integer
packing, fixed raw IEEE words and literal ASCII bytes. It is two fixed literal
constructors, not a general encoder or an alternate decoder. It never imports
project code, invokes a provider, opens a network or writes a file. Normal mode
prints JSON containing each complete hex string and actual SHA256. `--check`
reads at most1MiB of expected UTF-8 JSON, rejects duplicate keys/nonfinite constants,
compares parsed semantic values and exits nonzero on mismatch. Interpreter/build
metadata is intentionally absent; Root records the qualified interpreter separately.
Output binds exact LF source/oracle hashes without a self-hash cycle.

The195-byte `golden-a` is specified independently by the proposal. Its104-byte
header is followed by24 height bytes,8 validity bytes,22 material bytes and37
polygon bytes. Validity0x1b marks vertices0,1,3,4; columns3/rows2 mean the left cell
is fully valid and the right cell has two missing vertices. The upward slope of
the valid cell is1/2, within the core bound. The triangle's ordered integer points
have signed twice-area -4000000mm2. No generated decoder output supplies any of
these expectations. The shared header table plus each body table covers every
byte, including unaligned friction and polygon fields, with no implicit padding.

The146-byte `signed-zero-b` is independently authored:2x2 heights alternate raw
negative/positive f32 zero; anchor latitude/longitude/height, east origin and static
friction are negative f64 zero. South origin is-2 and dynamic friction is positive
zero. Every zero remains numerically admitted, the single cell is flat/valid, and
the lone material ID is `z`. No polygons occur. Decode must retain the actual raw
sign bits; numeric equality alone cannot prove this fixture. The body ends at the
last dynamic-friction byte, exercising P=0 without a special terminator.

The mutation plan fixes every prefix length of both fixtures, append-with/without
updated total, primitive header failures, counts/remaining-byte bounds, enums,
padding, raw NaN/sentinel cases, ID grammar, friction and ring failures. Every case
starts from its stated original fixture; a list of replacement values means
separate cases. Raw words are packed as unsigned I/Q rather than through Python
float NaNs. There is no required diagnostic order: mutations may violate more
than one invariant, and the span case explicitly does not prove isolated branch
coverage. The large-dimension short-body case must reject before large allocation;
the maximal size formula and over-cap input are hand boundary specifications,
not an assertion that this producer allocated or qualified a276MB payload.

Endian behavior needs two distinct expectations. Swapped marker or a big-endian
column count rejects, and the decoder never repairs them. Swapping only one
height's four bytes can instead create VALID different little-endian data:
wire3f800000 is raw f32 word0000803f, a small positive subnormal. The other heights
keep both facet gradients within16 (they also satisfy the historical2 bound). That mutation must accept those exact bits,
not repair them to1 and not reject merely because bytes resemble another endian.
Likewise all256 values of polygon priority are admissible; endpoint0/255 mutations
exercise preservation without inventing an invalid-priority enum.

This packet proves no executed codec conformance, renderer agreement, licensed
geography, source datum accuracy, file/package binding or runtime adoption. Root
owns execution and the later exact API/header. A future decoder test may construct
the listed mutations directly from these frozen bytes; it must never generate
expected golden bytes by encoding a Definition through production code.

## Exact gradient16 revision

Only the proposed admission bound and its source bindings change. Golden-a and
signed-zero-b retain their complete literal bytes, lengths, offsets, raw vectors
and expected future SHA identities. The producer source is byte-for-byte unchanged;
its artifact's hand-oracle source hash will change after Root freezes this revision.
No decoder implementation, provider output, failed test or widened tolerance
exists behind this revision.

The rejected offset108 word is now0x42000001. Float32 at32 has spacing2^-18, so
its first east facet gradient across2m is16+2^-19, already outside the norm16
bound regardless of the other gradient component. The former0x40800001 case is
explicitly NOW ACCEPTED using matching replacements at offsets108 and120. Both
valid east heights then equal4+2^-21, producing a uniform east plane with gradient
2+2^-22 and south gradient0. Its norm is below16; a decoder secretly retaining
the historical cap2 would reject it. This is source admission conformance only.
