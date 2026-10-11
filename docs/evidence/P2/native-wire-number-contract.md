# Native wire binary64 contract evidence

Status: **accepted documentation/reference contract for [#205](https://github.com/brettbergin/flight-simulator/issues/205)** through [PR206](https://github.com/brettbergin/flight-simulator/pull/206), accepted main `f68d243623a697a6a500052f926cc6f8e203c240`, governed by [ADR023](../../decisions/023-native-wire-binary64-decoding.md). This supports P2 publication correctness under PRD-002/004/015/033. Contract acceptance implements no converter, changes no model and closes neither [readout repair #204](https://github.com/brettbergin/flight-simulator/issues/204) nor [shaft coverage #202](https://github.com/brettbergin/flight-simulator/issues/202). Current limited implementation results are recorded [separately](piston-readings-decimal-admission.md).

## Preserved old failure

Root ran the unchanged pure probe in retained private run `piston-decimal-diagnosis-v1/run-10625ef2c5fb4ad9b9a4fc587e16add7`. It exited 0 and reported `old_fail_reproduced=true`, `pure_no_native_extension=true`, `pinned_engine=true`. Engine identity is Godot 4.7.2-stable official commit `ed1daf0bf001b61586d9930840f2f1394092c079`. No native/physics/GPU behavior was exercised by this probe.

| Artifact | SHA256 |
|---|---|
| Unchanged `probe.gd` | `ab240c7a64a2cf36a69f5f61627fe380ab7a7a2ba4af51ae53c9f7d5f19eaca4` |
| Actual `receipt.json` | `f5c91ca9a04baad98b88520893aaf690080bb4b6396944e2b6837c8e3146941f` |
| Actual `process.json` | `7def6a4c4f37b79880b36e0faafa534bdc01a80034a5399f5b98bc319e07d50f` |
| Actual `process.log` | `73c8e5079218cf528abdc89dbd207275cb189c320302ca61b462d13dae2e3be3` |

The correct little-endian binary64 for both original native decimal `0.059999999999999998` and typed `0.06` is `b81e85eb51b8ae3f`. Godot JSON.parse and String.to_float returned adjacent lower `b71e85eb51b8ae3f` for the original decimal. The pure probe mirrored the current scalar checks: Facade's decoded-wire allowance admitted that discrepancy, while exact NativeReadings comparison rejected it. It did not invoke those production classes. Actual issue204 acceptance therefore needs a later native-backed production-path test, not this pure mirror alone.

The original native held value and full decimal agree; this is not evidence of native FCS drift. Receipt reserialization is unnecessary to reproduce the failure and must not be asserted as its cause. Preserve original movie/parser evidence; no old failed receipt is relabeled successful.

## Primary source basis

Pinned Godot [JSON numeric conversion](https://github.com/godotengine/godot/blob/ed1daf0bf001b61586d9930840f2f1394092c079/core/io/json.cpp#L393) calls String.to_float. Its [string decimal conversion](https://github.com/godotengine/godot/blob/ed1daf0bf001b61586d9930840f2f1394092c079/core/string/ustring.cpp#L2471) limits mantissa digits and then assembles/scales a double. Source-derived truncation of this token yields decimal `0.05999999999999999`, consistent with the observed adjacent result. Both alternate engine parsing entry points share the conversion; switching to String.to_float does not fix it.

| Inspected source | Exact bytes / SHA256 |
|---|---|
| Godot `core/io/json.cpp`, above commit | 41,232 / `3e15e166841d96466ee2890f5e9340f7ffcd9e06c4211229881c019eeeb069d5` |
| Godot `core/string/ustring.cpp`, above commit | 140,220 / `fc403ff50652c5258bcf28d4b5ab5ac377301b656763c7ad87d9cf748bbbb903` |
| Installed MSVC 14.40.33807 `include/charconv` | 122,945 / `7587d63a0b044db9aafd6c5b7ebba6ed53098f0bde8398e2ace305a61cceb3ee` |

The installed MSVC header has decimal conversion at line1340 onward, ties-even rounding logic at1006-1018 and double overload at1952-1954. This is concrete source support for evaluating C++20 from_chars without a new dependency; it is **not** observed Windows/Linux qualification or a proof for all libraries/environments. No native vendor source is changed by this contract. The existing typed Dictionary codec cannot recover lost text digits; the recorded-review archive codec intentionally uses tagged binary64 and has a different scope.

## Independent reference packet

[Reference generator](native-wire-number-reference.py) and [frozen fixture](native-wire-number-reference.json) are original MIT project material. They were authored from numeric text and exact mathematical IEEE encodings before any candidate converter output. There is no import of Godot/native implementation, Python float conversion or decimal-to-float oracle. Python integers/Fraction parse exact decimal rationals; an ordered search over finite IEEE encodings finds the bracketing values; exact rational distances select nearest, with an even significand on a tie. Exact overflow midpoint and nonzero-to-zero rejection are handled explicitly. Expected bytes are the selected integer encoding written little-endian, including signed zero.

There are **49 cases**: 31 admitted finite encodings, 5 nonzero-underflow-to-zero rejections, 3 overflow rejections and 10 strict grammar rejections. They cover the reported token/equivalent/neighbors, normal numbers, integer-looking inexact values, 17-digit max finite/min normal/max and min subnormal, signed zero, exact positive/negative normal/subnormal/boundary ties and zero/overflow midpoint behavior. This is a focused regression/qualification packet, not exhaustive conversion certification.

| Frozen file | SHA256 |
|---|---|
| `native-wire-number-reference.py` | `3783367f8bc110c8f4122187083aeef0e7ef8db49ec27c93b2a67732b65430d1` |
| `native-wire-number-reference.json` | `1cab52841eb0cb063d547bf90e7a50f04a1871a5293bdfee4e0a78ddb8940ff6` |

Read-only regeneration:

```text
python -B docs/evidence/P2/native-wire-number-reference.py --check
```

The generator refuses to overwrite an existing fixture without a read-only check. A mismatching candidate never changes expected bits. Counts, exact Fraction selection and hand-known endian anchors passed reference-generation assertions. Independent review rederived all 49 cases using binade/scaled-significand integer division instead of the author oracle's ordered-bit search; exact bits and rejection categories agree. Its report SHA256 is `d2e0030c7f545860b4eac669996b8deaa49d84858f0f59cf7d5c08069f0807b7`. Independent interface/source review SHA256 is `02ec5c364b7bb1c09041f43663d725619b06dea4cdeb6e876e3c7f97f55b2d70`; its bounds, converter-result admission and Unicode clarifications are incorporated in ADR023. These are oracle observations only, not candidate converter results.

## Historical pre-contract proof and handoff

The following table and handoff text preserve the pre-merge snapshot. References to proposed status, missing implementation and pending contract CI describe that historical point; the acceptance update below supersedes their current-status interpretation.

| Gate | Current evidence / remaining work |
|---|---|
| Contract interfaces, ownership and bounds | Proposed ADR023; canonical map integrated and independent source review passed; checked contract merge pending |
| Independent numeric references | 49 cases generated without candidate output; read-only regeneration and independent rederivation passed; checked contract merge pending |
| Actual pinned Windows/Linux from_chars | Not implemented or executed; exact bits, ties, subnormals, signed zero, unsupported-range/grammar/type/cap atomic failures required |
| Bounded frontend restoration | Not implemented; quoted-string/escape parity, original duplicate keys, placeholder collisions/ownership, illegal key/root, trailing-comma/depth/cap tests required |
| Native-backed readings | Not run; correct original0.06 must qualify, genuinely adjacent contradictory native system value must reject; throttle/trim/commands and lifecycle guards unchanged |
| New source and delivery | Fresh first-party bridge fingerprint, corresponding-source inventory and editor/portable/rebuilt-library proof required; JSBSim/model bytes unchanged |
| Issue204 player outcome | Actual preserved old-fail/new-pass witness and joined shutdown still required; separate #202 remains open |

Root owns the contract maps, source/build identities and delivery. Native/frontend/test assignments use ADR023's disjoint paths after acceptance. Audit native publication readers including the direct proof previews, flight-camera checks, steady-wind bridge checks and native-template mutation tests; do not leave an undisclosed parser path with different numeric semantics. Preserve tagged archives/input/content behavior and exact semantic validators.

Before merging the integrated documentation snapshot, run `node tools/check-docs.mjs`, `npm --prefix schemas run check` and `node --test tests/contracts/schema.test.mjs`. Root integrated checks passed: 124 canonical issues, 147 requirements, nine phases, 160 Markdown files, all 14 generated contracts and all 11 schema tests. Hosted CI and the checked contract merge remain pending. Contract acceptance authorizes the bounded next implementation, not aircraft fidelity, official instruction credit or a P2/P3 exit decision.

## Contract acceptance and implementation handoff update

[PR206](https://github.com/brettbergin/flight-simulator/pull/206) merged as accepted main `f68d243623a697a6a500052f926cc6f8e203c240`, resolving the checked-contract gate for #205. The49-case fixture and original Fraction generator hashes above are unchanged. Historical pending-contract statements do not mean the contract remains proposed.

The [issue204 implementation evidence](piston-readings-decimal-admission.md) now records an actual isolated strict Windows production-core CTest (16,595 checks, zero failures), preserved initial frontend parse failure and corrected pinned-Godot negative-only frontend fixture (ten checks). These are distinct observations: neither core-only checks nor rejecting-Callable negatives prove a positive ClassDB or native-backed repaired publication. Adapter, Linux, full native/player and editor/portable/rebuilt-library qualification remain pending. Source-only integration review is not a delivered-success receipt. #204 and #202 remain separate open work; contract merge implies no aircraft, pilot or phase acceptance.
