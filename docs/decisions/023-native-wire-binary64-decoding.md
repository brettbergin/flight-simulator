# ADR023: Exact binary64 native wire decoding

Status: **proposed for [contract #205](https://github.com/brettbergin/flight-simulator/issues/205)**. P2 publication correctness; partial support for PRD-002/004/015/033. ADR023 was unallocated in the inspected source. Root must verify allocation and integrate the canonical maps before acceptance. The subsequent [repair #204](https://github.com/brettbergin/flight-simulator/issues/204) waits for this contract. Aircraft, pilot and phase acceptance remain separate.

## Problem and authority

The pinned Godot parser turns native decimal `0.059999999999999998` into an adjacent binary64 value; the full decimal correctly rounds to the same bits as native held `0.06`. The preserved pure old-failure probe reproduced this without simulation or receipt serialization. NativeReadings correctly rejects the resulting contradiction. Godot `String.to_float` shares the same conversion and is not a remedy. The [source/reference evidence](../evidence/P2/native-wire-number-contract.md) distinguishes observed failure from future qualification.

Keep the six FlightInteractiveSession methods, wire schemas, numeric JSON publication format, simulation/model/vendor bytes and typed control authority unchanged. NativeReadings, EngineStatus, recorded-review contradiction checks and existing physical budgets stay unchanged. No epsilon, snapping to held controls, decimal rewriting or fallback parsing may conceal a conversion error. This decision adds a separate pure conversion utility and a private frontend decoding seam; it does not add a session method or general serialization framework.

## Closed numeric utility

Register stateless RefCounted ClassDB utility `FlightWireNumbers` with sole project-defined method:

`decode_binary64(tokens: Variant) -> {ok: bool, error: String, value: Array[float] | null}`

Exact success is `{ok:true,error:"",value:[...]}`; exact failure is `{ok:false,error:<nonempty String at most 256 characters>,value:null}`. Keys are exact Strings. Results own their arrays, retain order and expose no partial conversion. Exact ARRAY and exact STRING elements only; reject StringName, coercion and every other Variant type. Empty batch succeeds. No session/model/file/process/tick capability, project signals or retained mutable state.

The utility itself enforces at most 8,192 tokens, 2,048 ASCII bytes per token and 1,048,576 combined token bytes, including direct calls that bypass the frontend. Check complete batch types/bounds before publishing any conversion; any failed token rejects the whole batch.

For each bounded ASCII token, validate the whole RFC8259 numeric grammar before C++20 `std::from_chars(..., std::chars_format::general)` to double:

`-?(0|[1-9][0-9]*)(\.[0-9]+)?([eE][+-]?[0-9]+)?`

Consume the entire token and require successful conversion to finite binary64. Every admitted number becomes Godot FLOAT, including integer-looking numeric tokens; this preserves existing JSON.parse number types. Canonical tick/sequence/seed strings stay Strings. True decimal zero preserves sign, including `-0`, `-0.0` and `-0e-300`. Admit finite subnormals, including minimum nonzero, with exact expected bits. Reject conversion errors, overflow, nonzero decimal rounded to zero and wrong zero sign. The exact midpoint between zero and minimum subnormal is therefore rejected rather than published as zero. No FP-mode mutation or alternative converter on failure.

Required native domain: finite binary64 values serialized by the existing 17-significant-digit native serializers round back to their original bits, including subnormals and signed zero. Longer finite tokens within the fixed bounds are admitted only when the reviewed conversion succeeds and meets nearest/ties-to-even references. Arbitrary decimal ranges outside binary64 are not supported. Neither API availability nor standard-library source comments qualify actual compiler behavior: pinned Windows and Linux implementations must pass independent bit-level subnormal/tie/range tests before production use. Compiler/runtime assumptions and any unsupported FP environment must be explicit, fail closed and preserve caller state; no silently changing the worker's environment.

## Private frontend decoding

`app/simulation/native_wire_decoder.gd` provides `decode(encoded: Variant, converter: Callable = Callable()) -> {ok: bool, error: String, value: Dictionary | null}` with the same exact success/error conventions. Exact STRING input and Dictionary root only. Production resolves the real numeric utility and fails closed when unavailable. An explicitly supplied Callable is only a pure fault-test seam, with the same batch/result validation; fake-converter tests do not count as compiled-helper evidence. Facade `_decode` delegates and maps failure to its existing null/rejection path; all semantic admission still runs afterward.

Use one bounded lexical transduction and one owned restoration, with the existing Godot JSON parser handling container/literal grammar:

1. Scan quoted strings/keys and numeric tokens. Replace **all** original strings (including keys) and all numbers with unique quoted ASCII ordinal placeholders. Store exact original numeric text and decoded string values in a private side table. Parse each original quoted string token alone through Godot JSON, after checking escape parity, permitted escapes, raw controls and Unicode scalar/surrogate validity; that isolated parse contains no numeric token. Original value strings remain opaque after restoration.
2. Outside strings accept only RFC whitespace, punctuation and `true`/`false`/`null`; reject malformed tokens, loose number grammar, trailing commas and excess nesting before transformed parse. Existing parser validates complete transformed container grammar. Numeric text never reaches that parser. Do not build a second recursive JSON grammar/object model.
3. Invoke the native batch once for collected numeric strings. Validate its closed result, exact count, finite FLOAT elements, zero-sign requirements and ownership before restoration. Restore parsed placeholders exactly once by their side-table kind/ordinal. An object key must come from a STRING slot; replacing an illegal original numeric key must not make it admissible.
4. Reject duplicate decoded original keys (including alternate escaped spellings), unknown/repeated/missing placeholders, unused side entries, wrong shapes and any failed admission. Unique temporary keys preserve duplicate originals for rejection instead of Godot's last-key-wins behavior. Since every original string was replaced, even an original value identical to a generated placeholder cannot collide. Preserve insertion order, arrays, bool/null and owned String values; publish only a complete owned Dictionary.

The input is already an engine String: reject surrogate/non-scalar contents, and bound the actual encoded UTF8 length. This does not retrospectively repair invalid bytes replaced before this boundary; native publication strings are generated from the existing serializer. No raw file parsing is introduced.

| Resource | Inclusive hard maximum |
|---|---:|
| Input UTF8 bytes and input characters, independently | 1,048,576 each |
| Container depth (root container = 1) | 24 |
| Lexical entries and restored nodes, independently | 32,768 each |
| Side-table entries | 32,768 |
| Members per object and elements per array, independently | 8,192 |
| Numeric batch count | 8,192 |
| One numeric token ASCII bytes | 2,048 |
| Combined numeric-token ASCII bytes | 1,048,576 |
| Transformed UTF8 bytes | 4,194,304 |

Count lexical entries as each container, key token or scalar token; restored nodes count each container, key and scalar. Check caps during scan/build and before parser invocation; check restored caps again. Placeholder storage remains bounded by the same entries/input caps. These are publication limits, not archive-policy changes. Existing schema-specific string/range/content/version limits continue to apply.

## Consumer scope and ownership

Decode all affected AircraftSnapshot, AtmosphereSample, applied ControlCommand and OperationalEvent numbers, not mixture alone. Audit direct native JSON reads in `app/proof/proof.gd`, `app/proof/airborne/preview.gd`, `app/proof/interactive/preview.gd`, `flight_camera_checks.gd`, actual bridge checks, native-template mutation tests and Facade. Migrate affected production publication paths together; explicitly identify any remaining diagnostic-only legacy parser. Do not change manifests, input presets, tagged review archives or native JSON layouts.

- Native owner: new `native/godot_bridge/src/wire_numbers.hpp`/`.cpp`, coordinated registration in `bridge.cpp`. No JSBSim/session/model changes.
- Frontend owner: private decoder, narrow Facade delegation and affected publication readers. No weakening of NativeReadings/EngineStatus semantic checks.
- Independent test owner: promote the frozen contract oracle/fixture without regenerating expected values from candidate output; add focused `tests/wire_codec/native.cpp` and `checks.gd` under agreed targets.
- Root delivery owner: bridge CMake, CI/staging, corresponding-source rosters, new first-party source fingerprint/runtime inventory and editor/portable/rebuilt-library checks. Include new files in all source-bundle/loaded-source closure. A new bridge identity is mandatory; unchanged JSBSim physics/source evidence cannot be retagged as converter qualification.

## Acceptance and implementation gates

Contract acceptance requires reviewed exact interfaces/bounds, frozen independent rational references, canonical maps, and documentation/schema checks. It does not require or claim a converter implementation. Consumer implementation starts only after this contract merges and Root ratifies the reference bytes.

The later repair must demonstrate actual Windows/Linux converter bits and atomic grammar/type/bound failures; string/key/escape/collision/duplicate/root/depth/cap rejection; one valid large bounded publication and one cap failure; and actual native-backed Facade/NativeReadings/EngineStatus acceptance of the correct original token with exact held bits. A genuinely adjacent conflicting system value must still reject. Cover throttle/trim/applied-command values and unchanged session/tick/sequence/terminal/weather guards. Source-only/fake tests cannot substitute for actual utility binding.

Finally run the source-bound old-fail/new-pass issue204 witness through fresh editor/portable/rebuilt-library delivery with observed joined close. Preserve original failing artifacts. Contract merge closes only #205; helper-only proof does not close #204. The independent uncertified shaft coverage gap [#202](https://github.com/brettbergin/flight-simulator/issues/202) remains separate, as do aircraft and pilot/phase gates.
