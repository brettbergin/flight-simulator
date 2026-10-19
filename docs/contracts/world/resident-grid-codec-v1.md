# Resident grid payload v1

Proposed byte-codec contract for #243. Depends on checked acceptance of the unchanged resident-grid core contract/header from PR246 (doc SHA256 `9e4ef15be255624405b917efce41fbbb7333c89072d586d75a7cfa0d472197df`, header SHA256 `7b7f7dee3875cf67d9df8057405fc729ec72da4570dfcd5f8a4dca755d6e96f3`). This proposal permits no implementation until its own checked merge. It then permits only standalone byte decoding/conformance and a separately reviewed renderer byte reader. Geographic compilation, world/start/catalog admission, Session contact adoption and gameplay remain separate contracts.

The payload serializes exactly `flight::ground::grid::v1::Definition`. It contains no world identity, path, code, URL, datum resolver, transform, texture, streaming instruction or physics setting. Existing WorldPackage/v1 continues to own source rights/dates, coverage/datums/conversion references and files `{path,sha256,bytes,role}`. A future package contract must bind its payload file, world ContentRef, start and provider identity; this codec does not select a file role or infer those bindings.

## Primitive rules and fixed header

Every multibyte integer and IEEE754 float is little endian. `u8/u16/u32/u64` are unsigned widths; `i32` is two's-complement signed 32-bit. `f32/f64` are exact IEEE754 binary32/binary64 bit patterns, not decimal text or host struct representations. Read with byte assembly plus bit-preserving conversion; never reinterpret an unaligned byte pointer as a packed C++ struct. IEEE754 binary32/binary64 host support is required. Preserve permitted signed zeros and all admitted numeric bits; no rounding, normalization or NaN canonicalization.

Offsets are absolute byte offsets. The fixed header is exactly 104 bytes, with no padding beyond the explicitly zero reserved fields:

| Offset | Type | Value / Definition field |
| --- | --- | --- |
| 0 | 8 bytes | Magic hex `46 47 52 44 4c 45 31 00` (`FGRDLE1` plus NUL) |
| 8 | u32 | Payload version exactly 1 |
| 12 | u32 | Endian marker exactly `0x01020304` (bytes `04 03 02 01`) |
| 16 | u64 | Exact complete payload byte count, including header |
| 24 | u32 | columns |
| 28 | u32 | rows |
| 32 | u32 | N, exactly columns * rows |
| 36 | u32 | W, exactly ceil(N / 64) |
| 40 | u32 | M, material count |
| 44 | u32 | P, polygon count |
| 48 | u32 | V, total polygon vertex count |
| 52 | u32 | default_material_index |
| 56 | u8 | spacing: exactly 2 or 4, meters |
| 57 | u8 | missing_vertices: 0 not_loaded, 1 datum_unresolved, 2 invalid_data |
| 58 | u16 | Reserved, exactly 0 |
| 60 | u32 | Reserved, exactly 0 |
| 64 | f64 | anchor.latitude_rad |
| 72 | f64 | anchor.longitude_rad |
| 80 | f64 | anchor.ellipsoid_height_m |
| 88 | f64 | east_origin_m |
| 96 | f64 | south_origin_m |

No endian autodetection/byteswap repair, version negotiation, flags, extensions, offset table or compression exists. Unknown magic/version/marker, nonzero reserved bytes or unsupported enum rejects.

## Single sequential body

Immediately after the header, in this exact order:

1. N `f32` up_m values, vertex n = row * columns + column; rows increase south, columns east.
2. W `u64` valid_words. Vertex n uses bit n % 64 of word n / 64, low bit first. Unused high bits of the last word are zero.
3. M material records: `u8 id_byte_count`, that many ASCII ID bytes, `f64 static_friction`, `f64 dynamic_friction`.
4. P polygon records: `u8 id_byte_count`, that many ASCII ID bytes, `u32 material_index`, `u8 priority`, `u32 vertex_count`, then vertex_count consecutive points, each `i32 east_mm`, `i32 south_mm`.

IDs have 1..128 bytes and match existing ASCII stable_id grammar `^[a-z][a-z0-9]*(?:[._-][a-z0-9]+)*$`. No NUL, UTF-8 multibyte sequence, length terminator, alignment padding or trailing whitespace is present. IDs are unique within material and polygon namespaces separately. Records retain their given vector order; never sort IDs, rotate/reverse polygon rings or deduplicate points while decoding. Indexes refer to that unchanged material order. The final polygon's last point is the final payload byte; P=0 ends after the last material. No trailing bytes are allowed.

If material ID lengths are Lm and polygon ID lengths Lp with polygon vertex counts kp, exact total size is `104 + 4*N + 8*W + sum(17+Lm) + sum(10+Lp+8*kp)`. Require total V = sum(kp). All size/count/cursor arithmetic is overflow-checked unsigned 64-bit before conversion to host size_t, allocation, pointer addition or read. Every read first proves `width <= input_size - cursor`; no declared offset may redirect the cursor.

## Closed admission, ownership and pure API

Reject input larger than 276946836 bytes before parsing or allocation. This is the format's maximal structural size at 8193 squared vertices, 1048833 words, 32 maximum-length material IDs, 128 maximum-length polygon IDs and 4096 polygon vertices; it does not enlarge the core's 536870912-byte accounted owned-definition cap. Reject input shorter than the fixed header or whose actual size differs from the header total. Check dimensions 2..8193, M 1..32, P 0..128, V 0..4096, all exact derived counts and minimum remaining byte counts before allocating large vectors. Walk variable record lengths and prove exact final cursor/total V before returning any result. Decoder implementation must reserve bounded exact counts, not grow allocations from unchecked lengths. Caller bytes and peak/RSS remain separate from the core owned-capacity accounting.

All core Definition invariants remain mandatory, with no stricter replacement of permitted values: valid WGS84 anchor and height [-500,10000] m; finite origins/endpoints within [-8192,8192] m; exact 2^-32 m origin quantum; endpoints computed without snapping; valid heights finite in [-1000,4096] m; at least one four-valid-vertex cell; Y bracket margin 1/64 m/span <=2048 m; every fully valid facet gradient magnitude <=16 (exact core max_gradient_norm=16.0); material bounds `0 <= dynamic <= static <=5`; valid default/material indexes; simple, negative-area integer-mm polygon rings with distinct vertices/implicit closure/no holes/no overlapping segments, each 3..4096 points in [-8192000,8192000] mm and <=4096 total. Preserve actual uint8 priorities. Validate the decoded owned-capacity budget under the unchanged core accounting, including its control objects.

Inspect validity and raw height bits together: a valid bit requires finite/in-range f32; an invalid bit requires exactly `0x7fc00000`. No other sentinel, quiet/signalling NaN, infinity or arbitrary finite invalid height is accepted. Invalid sentinels are never used in height arithmetic. Nonfinite anchor/origin/friction, nonzero validity padding, invalid rings/IDs/counts, nonuniform snapped origins and any core semantic failure reject the whole payload. No partial grid, accepted prefix, defaulted missing field or fallback plane is returned.

Proposed standalone native seam, in new header `native/world_core/grid/include/flight/ground/grid_payload.hpp`, with implementation owned by the grid component and tests under `tests/ground/grid/codec/`:

```cpp
#include <flight/ground/prepared_grid.hpp>
#include <cstdint>
#include <span>
namespace flight::ground::grid::payload::v1 {
inline constexpr std::uint32_t payload_version = 1;
inline constexpr std::uint64_t max_payload_bytes = 276946836;
[[nodiscard]] flight::ground::grid::v1::Definition decode(
    std::span<const std::uint8_t> bytes);
}
```

`decode` borrows immutable bytes only during the call and returns one fully validated owned Definition by value. Caller must keep the input span stable/alive during the call. No retained span, mutable alias, provider, identity, file handle, thread, I/O, arbitrary filesystem/network access or Godot object crosses this seam. Concurrent independent calls are permitted. Invalid bytes/unsupported format/semantic bounds throw `std::invalid_argument`; allocation failure throws `std::bad_alloc`. Diagnostics are bounded fixed messages without source bytes/paths. No caller-supplied budgets, retry parser or partial result. Core/decoder may share private validation code; no Definition/header field or core observable change is authorized.

The trusted caller may independently hash the exact complete payload and require an expected lowercase SHA256 before decode. No hash field occurs inside the payload, so no self-hash cycle exists. Hash matching proves bytes, not truth/authenticity. A later loader must bind that exact verified digest to existing `ground::v1::Identity.prepared_surface_sha256`, validate the unchanged world/version/hash/nonzero-generation grammar, then call `PreparedGrid::prepare(std::move(definition), identity)`. No new identity grammar or manifest-self-hash convention is introduced here; this paragraph specifies the required future relation rather than admitting runtime use.

## Renderer agreement

A future standalone Godot reader must validate the same complete bytes/invariants before exposing geometry and produce the same numeric values, IDs, validity and polygons. It consumes the exact same externally verified payload digest as the native reader, never a second independent height export. Canonical vertex n is `(east_origin+column*s, promoted f32 up[n], south_origin+row*s)`. A cell with any invalid corner emits neither canonical triangle; otherwise diagonal P00-P11, triangle0 `(P00,P01,P11)` and triangle1 `(P00,P11,P10)` are unchanged. No resampling, flattening, smoothing displacement, independent datum offset or decorative collision substitute is admitted. Camera/origin rebasing may translate presentation only; actual renderer precision/normal/LOD limits need separate measured acceptance. Godot does not own aircraft/contact physics, and this byte contract adds no Scene/runtime consumer.

## Hand-authored golden fixture specification

Proposed synthetic fixture `golden-a`: exactly 195 bytes. This table is a hand-derived specification, not a generated or executed fixture and has no invented SHA. All unspecified fixed-header numeric fields are explicitly listed below; only the two reserved fields are zero by definition.

- Header: version 1, marker 0x01020304, total 195, columns 3, rows 2, N 6, W 1, M 1, P 1, V 3, default 0, spacing 2, missing reason 2, anchor `(0,0,100)`, origins `(-2,-2)`.
- Offsets 104..127: six f32 raw words `[0x00000000,0x3f800000,0x7fc00000,0x00000000,0x3f800000,0x7fc00000]`.
- Offsets 128..135: one u64 `0x000000000000001b` (vertices 0,1,3,4 valid; 2,5 missing). The first cell is usable; the second is missing.
- Offset 136: u8 5; offsets 137..141 ASCII `grass`; offsets 142..149 f64 0.5; offsets 150..157 f64 0.25.
- Offset 158: u8 3; offsets 159..161 ASCII `pad`; offsets 162..165 u32 material 0; offset 166 u8 priority 7; offsets 167..170 u32 count 3.
- Offsets 171..194: i32 point pairs `(-1000,-1000),(-1000,1000),(1000,-1000)`, negative signed area. No repeated closure point.

Useful independently checked little-endian atoms: f32 1=`00 00 80 3f`; invalid=`00 00 c0 7f`; f64 100=`00 00 00 00 00 00 59 40`; -2=`00 00 00 00 00 00 00 c0`; 0.5=`00 00 00 00 00 00 e0 3f`; 0.25=`00 00 00 00 00 00 d0 3f`; i32 -1000=`18 fc ff ff`; 1000=`e8 03 00 00`. Zero anchor operands are positive zero. Reserved bytes are zero.

Before consumers, an independent fixture owner constructs literal fixture bytes from this specification with standard-library integer/IEEE packing, separately reviews a complete offset/hex dump and computes actual SHA256 only after byte construction. A second independent literal-byte/offset review must agree; no production encoder/decoder generates expected bytes. Freeze expected decoded bit patterns/vectors and rejection mutations before implementation. Include every truncation position, one appended byte, swapped marker/endian data, wrong magic/version/reserved/total/counts/enums, invalid ID/index, changed sentinel/validity padding, nonfinite/range/gradient/span/origin/ring failures and size/overflow declarations. Add separately hand-authored signed-zero and large-count boundary cases. All rejected cases must leave no result/provider. This establishes byte conformance only; source/datum accuracy and runtime acceptance remain unclaimed.
