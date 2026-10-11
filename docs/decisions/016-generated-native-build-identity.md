# ADR016: Generated expected native build identity

Status: proposed contract; consumers begin only after its independently reviewed protected merge. This bounded packaging prerequisite belongs to [issue149](https://github.com/brettbergin/flight-simulator/issues/149) and the subsequent [issue127](https://github.com/brettbergin/flight-simulator/issues/127) adoption. It partially supports PRD-002, PRD-004, PRD-010, PRD-032, PRD-033, REAL-013, REAL-014 and SAFE-030 through their existing issue mappings. It changes no numerical method, profile default or aircraft acceptance. Basis: [ADR007](007-sim-loop-facade.md), [ADR010](010-original-piston-profile.md), [ADR013](013-steady-wind-starts.md), [ADR014](014-event-aware-shaft.md) and [ADR015](015-source-law-coupled-shaft.md).

## Problem and decision

The qualified interactive native fingerprint includes the selected backend/materializer identity, compiler/build controls and ordered LF-normalized consumer sources. Compiler/platform/configuration differences therefore produce different correct Windows and Linux fingerprints. A single tracked facade literal cannot identify every qualified build. The current preview's six-source-only reconstruction and package count checks also predate the reviewed cold consumer closure.

Generate the facade's expected identity per build, qualify it independently before staging, and compare every actual native open fingerprint exactly against that expectation. Never adopt an actual native reply as its own expected value. There is no arbitrary digest allowlist, environment override, caller identity parameter, user preference, old-literal fallback or silently rewritten tracked facade. This contract adds neither native operations nor public wire/Readback fields.

## Exact generated resource

For every selected source route that builds the interactive target, CMake emits `native-identity.gd` at the build root using its verified canonical variables and a fixed reviewed template. Stage it only at `res://build/native_identity.gd`, outside the authored `simulation/` snapshot tree. Its exact grammar is these six lines, UTF-8 without BOM, LF only, one final LF, no blank lines, comments, methods, extra constants or executable statements:

```gdscript
extends RefCounted
const SCHEMA: String = "flight-native-build-identity-v1"
const SOURCE_VARIANT: String = "<selected-source-variant>"
const BACKEND_IDENTITY_SHA256: String = "<verified-backend-digest>"
const BUILD_CONTROL_SHA256: String = "<canonical-build-control-digest>"
const SOURCE_FINGERPRINT: String = "<compiled-interactive-consumer-digest>"
```

Placeholders above are substituted with one closed variant ID and three lowercase64hex SHA256 strings. They are not literal resource values. The only admitted variant IDs are:

- `jsbsim-1.3.1-upstream`
- `jsbsim-1.3.1-event-aware-constant-power-v1`
- `jsbsim-1.3.1-event-aware-coupled-midpoint-v1`
- `jsbsim-1.3.1-event-aware-coupled-midpoint-local-window-v2`

Shape alone never establishes a reviewed backend: the existing corresponding-source selector must verify the complete selected source closure and derive its canonical identity. Include the fixed template in declared build-control inputs. Do not include generated output in those inputs or create a fingerprint cycle. Preserve existing selected-backend/materializer derivation, compiler/configuration controls, prefix spelling and ordered LF source hashing. The canonical interactive body begins `verified-jsbsim-backend:<digest>\njsbsim-build-controls:<digest>\n`, followed by the twenty-five path/hash lines below; SHA256 of that UTF-8 body is SOURCE_FINGERPRINT. The compiled definition and `interactive-source-fingerprint.txt` must match it exactly.

Facade preloads the generated resource and validates its schema, variant and digest shapes before constructing the bridge. `NATIVE` becomes a constant alias of its SOURCE_FINGERPRINT, preserving the WindCue constant alias. Missing, malformed or unstaged resources fail visibly at build/import/start before native allocation; no claimed live Readback is published. The native open reply must still match the expected source fingerprint, current profile/model/inventory, prepared world, wind, clock and other accepted metadata exactly. Copied Readback records the matched actual identity. Subsequent reply/admission/fault/retention rules remain unchanged.

The resource contains no model root, absolute build path, DLL hash or runtime module path. Loading it supplies an expectation, not source qualification or actual-loaded-library evidence.

## Closed source and build qualification

Before staging, independently verify the current selected backend with existing public selectors; reproduce accepted build-control hashing and ordered LF consumer hashing from current source; require matching build/source manifests, compiled definition, selected bridge bytes and exact resource grammar/bytes. A stale generated resource with plausible digest strings is rejected. Never derive trust solely from generated CMake output, a bridge byte substring, a successful open echo or a self-declared source subset. Reject missing/extra/conflicting identity declarations, unknown variants, changed source/configuration and unsafe escaped/reparse paths. Generate compile_commands.json on both platform binding routes so selected compiled definitions have a consistent read-only witness. Native execution then separately proves actual bridge/library loading and package-relative module identity.

The ordered closed interactive source roster is:

1. `native/fdm_jsbsim/interactive/src/session.cpp`
2. `native/fdm_jsbsim/interactive/include/flight/interactive/session.hpp`
3. `native/fdm_jsbsim/interactive/include/flight/interactive/surface.hpp`
4. `tests/interactive/native.cpp`
5. `tests/interactive/negatives.hpp`
6. `native/fdm_jsbsim/interactive/src/model-pins.hpp`
7. `native/fdm_jsbsim/interactive/src/piston-model-pins.hpp`
8. `tests/engine/CMakeLists.txt`
9. `tests/engine/loaded-library.hpp`
10. `tests/engine/native.cpp`
11. `tests/engine/native-mechanism.cpp`
12. `tests/engine/native-validate.py`
13. `tests/engine/native-generate.py`
14. `tests/engine/native-limits.hpp`
15. `tests/engine/native-limits.json`
16. `native/godot_bridge/src/bridge.cpp`
17. `native/godot_bridge/src/codec.hpp`
18. `native/godot_bridge/src/codec.cpp`
19. `native/godot_bridge/src/worker.hpp`
20. `native/godot_bridge/src/worker.cpp`
21. `native/godot_bridge/src/interactive_worker.hpp`
22. `native/godot_bridge/src/interactive_worker.cpp`
23. `native/godot_bridge/src/interactive_bridge.cpp`
24. `native/godot_bridge/src/wire_numbers.hpp`
25. `native/godot_bridge/src/wire_numbers.cpp`

### ADR023 first-party closure amendment (issue204)

This proposed amendment consumes the accepted [ADR023](023-native-wire-binary64-decoding.md) contract and belongs to [repair #204](https://github.com/brettbergin/flight-simulator/issues/204). Its reviewed integration merge, not this private draft, authorizes the expanded qualification policy. Preserve the original ordered fifteen-source prefix byte for byte; append exactly the ten bridge/header source paths 16–25 above. This binds actual ClassDB registration, its codec/worker dependencies and the new stateless number utility. It does not add a session operation or alter vendor/model/physics source authority.

The ordered build-control file roster expands from thirteen to fifteen. Preserve the original thirteen-path prefix and append only bridge CMake and wire-test CMake:

1. `CMakeLists.txt`
2. `CMakePresets.json`
3. `third_party/dependencies.lock.json`
4. `tools/bootstrap/source-selection.cmake`
5. `tools/bootstrap/source-variant.py`
6. `tools/bootstrap/coupled-source-variant.py`
7. `tools/bootstrap/build.ps1`
8. `tools/bootstrap/bootstrap.py`
9. `native/fdm_jsbsim/CMakeLists.txt`
10. `native/fdm_jsbsim/ground/CMakeLists.txt`
11. `native/fdm_jsbsim/interactive/CMakeLists.txt`
12. `tests/fdm/CMakeLists.txt`
13. `native/fdm_jsbsim/interactive/native_identity.gd.in`
14. `native/godot_bridge/CMakeLists.txt`
15. `tests/wire_codec/CMakeLists.txt`

These file inputs retain the existing LF-normalized path/hash concatenation and existing compiler/configuration scalar suffix. The template remains an input; generated output remains excluded. No schema identifier, generated six-line grammar, seven-build-witness roster, selected-backend derivation or source/archive rights policy changes. `PreviewNativeBuildIdentity/v2` retains its exact field names/types; its reviewed `source_bindings` policy now requires exactly these twenty-five ordered records. This is an explicit bounded roster amendment, not a general count override or acceptance of arbitrary source subsets.

New builds must freshly reproduce the expanded build/source digests and stage their canonical generated resource. Historical fifteen-source v2 records/packages remain immutable historical evidence; the new qualifier must not reinterpret them as current twenty-five-source qualification. A new bridge fingerprint proves neither number-conversion correctness nor new physics validity. Actual strict Windows/Linux converter qualification, 49 independent bit references, atomic rejection/FENV preservation, migrated reader checks and separate editor/export/rebuilt-replacement WireCodec receipts remain repair acceptance gates. Existing native JSON serializer bytes, public wire schemas, method defaults, aircraft/model inventories, numerical references and budgets stay unchanged.

Source-list changes require explicit review, rather than replacing the old count with an arbitrary new count. This LF/ordered identity is distinct from the FDM adapter's raw/sorted identity; do not interchange the algorithms.

## ADR024 source allocation and build-control amendment (issue202)

Status: **proposed, contract first**. This narrow [issue202](https://github.com/brettbergin/flight-simulator/issues/202) allocation consumes the accepted [ADR024](024-certified-local-decay-window.md) numerical policy. ADR024 requires a distinct source/patch/archive/runtime identity and final identifier review; it does not allocate this exact eighteen-file build-control roster. This amendment must receive its own independently reviewed protected documentation merge after the ADR023 twenty-five-source/fifteen-control integration and before consumer adoption. Private source materialization or review alone does not authorize tracked consumers or native execution.

Allocate only the fourth closed variant listed above: `jsbsim-1.3.1-event-aware-coupled-midpoint-local-window-v2`. Its bootstrap selector is exactly `event-aware-coupled-midpoint-local-window-v2`, rights component exactly `jsbsim-coupled-midpoint-local-window-v2`, and separately versioned corresponding-source directory `third_party/patches/jsbsim/event-aware-coupled-midpoint-local-window-v2/`. Preserve all three historical variants, every v1 patch/archive/reference byte, and their historical evidence. The numerical law/method ID remains `event_aware_coupled_midpoint_v1`; it cannot by itself identify this new domain policy.

Keep the ordered twenty-five interactive source paths unchanged. Keep build controls1–15 in their exact existing order and append **only**:

16. `tools/bootstrap/coupled-local-window-source-variant.py`
17. `tools/bootstrap/build-local-window.ps1`
18. `tests/engine/local-window-v2/CMakeLists.txt`

The existing `tools/bootstrap/build.ps1`, `tests/engine/CMakeLists.txt`, all v1 probe/manifest files and reference packets remain unchanged. A distinct v2 bootstrap/suite/extraction/authorization route consumes the new source, keeping the old manifest's shared-source pins reproducible. These three paths are unconditional members of the new closed build-control identity; do not infer a variable roster from the selected backend, accept a subset, or relax exact consumers to a numeric count alone.

The initial allocation is bound to these independently materialized **source-only** identities; none is an executable hash or runtime acceptance:

| Item | Exact allocated value |
|---|---|
| Identity file raw SHA256 | `c6f96834a166d72300c999e84d95b1bc1da9127c097773e9731e25a094bba233` |
| Derived selected-backend digest | `3d445058dca744fe44811fc02977b2722b42c7eabd861ecf5335ab50ee7db743` |
| Corresponding-source archive SHA256 | `3b50427ed55b9f9ed0e1e5b48876813b34a5de743203b76b141f1c3839e5b1bb` |
| Archive byte count | `3926779` |
| Materializer SHA256 | `645fe299d160137b1e7dd4ace2d077ca26389253fa9242c4be5182451d01f42a` |
| Source recipe SHA256 | `ef1fe03694d3ba9a6b4bd1999b5f6dfcf6b0ce0fa4ad61a6c9288a0372b3cf6d` |
| Materialized vendor-tree SHA256 | `788186628d31d5ff314c5f11511010b94d59fa404d91488901989a3512d971bc` |

Preserve the existing selected-backend derivation, LF-normalized path/hash concatenation, compiler/configuration suffix, twenty-five source records, six-line generated resource grammar, seven build witnesses and `PreviewNativeBuildIdentity/v2` closed fields. The identity-file hash and derived backend digest are different values with different roles. No final bridge/DLL/source-fingerprint/build-control digest is allocated in this contract: those depend on the final reviewed first-party source and actual toolchain and must be independently reproduced from a fresh build. A different archive/recipe/materializer/vendor allocation needs explicit source-contract review; replacement rights remain unchanged.

Consumer integration must update each explicit closed variant/control consumer consistently, preserve unknown/extra/omitted/duplicate/conflicting rejection, and require actual source reconstruction and fresh generated resources. An old twenty-five-source/fifteen-control resource or old v1 package is immutable historical evidence and cannot be relabelled as eighteen-control/new-source qualification. Keep the separately approved ADR023 exact numeric decoder admission; the only Facade change for this allocation is the new closed source-variant token, never restoration of a superseded epsilon allowance.

Source allocation does not prove repaired behavior. Require actual strict Windows/Linux compilation, the frozen17 scalar references **and** unchanged137/library/270-default/12-chronology/12-process physical criteria, original298-call replay, fresh editor/portable/rebuilt-replacement actual-module evidence and joined shutdown. Qualification must bind the scalar target's actual executable hash and exact CTest command rather than only discover its name. No model, coefficient, public schema/session method, profile selector, clock, wind domain, tolerance, default-source adoption, aircraft claim or phase gate changes through this documentation merge.

## Successor source-only allocation for issue202

The initial allocation above remains historical. A fresh source-only renewal for [issue202](https://github.com/brettbergin/flight-simulator/issues/202) changes exactly one FGPropeller.cpp rejection message: when the requested remaining time is not strictly inside the certified local window, retain the historical `coupled shaft: decay continuation uncertified` category. The exact comparison, fatal rejection, split and evaluation budgets, solver expressions, chronology, model data and frozen 17/137 reference bytes remain unchanged. This is a diagnostic-text correction, not evidence of repaired flight behavior.

The companion scalar test now derives the expected first floating-point guard from caller `fegetround()` after installing each unsupported SSE mask, requires that mask to be installed and requires unchanged rounding and full MXCSR after rejection. It does not infer an expected answer from candidate output or broaden accepted failure categories. The retained b66 compilation and failed CTest outputs are not relabelled as this new source.

| Renewed source-only item | Exact allocated value |
|---|---|
| Identity file raw SHA256 | `73000fbab720fe8361d65de049a027b6e280e5f835eedaab92df0bdd1746d770` |
| Derived selected-backend digest | `2d633139c38d27ec445ca8357ede0fae526f95da80808b3ef45e1708be4189ea` |
| Corresponding-source archive SHA256 | `7341b8d797082efb2107f12511ac0ecab09fde66423c8bb3b6cd329ddff28177` |
| Archive byte count | `3926768` |
| Materializer SHA256 | `645fe299d160137b1e7dd4ace2d077ca26389253fa9242c4be5182451d01f42a` |
| Source recipe SHA256 | `603c3f042d8225a32ce067eaaa1deca00ac327240eef6538e7a9e340df3cbe4c` |
| Materialized vendor-tree SHA256 | `97652c3d57537b5eede8216b3f696a60e260f3a8a15672f4b65b4d93a887c237` |
| FGPropeller.cpp SHA256 | `bc8414bfd86d482e32c7c3edd5e73352ffa7209b9daec74cf6ac19f1421a6d17` |

The deterministic source archive still contains 293 regular files: 279 library files with 275 pristine and four reviewed replacements, plus 14 wrapper/provenance members. Relative to the initial archive, only FGPropeller.cpp, its exact recipe and the derived manifest change. The four-target recipe order, before-images, other three after-images, canonical LF MIT notice and source-tool bytes stay exact.

This successor allocation requires explicit contract review before consumer pins are adopted. Preserve the same 25 ordered consumer-source records, 18 unconditional build controls, seven witnesses and closed identity/resource grammars. No compiled fingerprint, build-control digest or executable identity is allocated here. Require a fresh independently measured strict build, 13 CTests, unchanged 137/library/default/chronology and 12-process physical criteria, original 298-call replay and all three editor/portable/rebuilt-library delivery contexts before claiming the defect repaired. No aircraft, pilot, phase, default-profile or replacement-rights gate changes.

## PreviewNativeBuildIdentity/v2 evidence

New staging evidence uses this exact closed top-level shape. All SHA256 values are lowercase64hex; byte counts are nonnegative integers. This is build-side provenance, not a native self-report or persistent flight format.

| Field | Type and fixed meaning |
|---|---|
| schema | String `PreviewNativeBuildIdentity/v2` |
| root | String absolute selected build directory; evidence only |
| source_variant | String, one of the four IDs above |
| backend_identity_sha256 | String, independently derived selected backend digest |
| build_control_sha256 | String, independently reproduced accepted compiler/build-control digest |
| declared_source_fingerprint | String, independently reproduced interactive digest |
| source_bindings | Array of exactly twenty-five records in the ordered roster above |
| build_witnesses | Array of exactly seven records in the ordered build roster below |
| resource | Exactly `{build_path:String,staged_path:String,bytes:int,sha256:String}` |
| scope | String `Qualified declared source/build/resource identity; actual loaded facade and library identity require runtime evidence` |

Each source_bindings record has exactly `{path:String,bytes:int,raw_sha256:String,lf_sha256:String}`. `path` is the exact repository-relative roster member; raw bytes bind staging evidence, LF bytes reproduce the native identity. Each build_witnesses record has exactly `{path:String,bytes:int,sha256:String}`, relative to root. Ordered build witnesses are:

1. `bin/flight_godot_bridge.dll` on Windows, or `bin/libflight_godot_bridge.so` on Linux
2. `build.ninja`
3. `CMakeCache.txt`
4. `toolchain-build-manifest.txt`
5. `jsbsim-source-build-manifest.txt`
6. `interactive-source-fingerprint.txt`
7. `compile_commands.json`

resource.build_path is exactly `native-identity.gd`; resource.staged_path is exactly `build/native_identity.gd`. Its bytes/hash bind the canonical generated script at the selected build, staged project, export package and corresponding-source locations. The evidence has no extra identity/resource records or optional fallback fields. Actual native bridge/library paths and pre/post binary hashes remain in their existing separate runtime/package receipts. Do not infer module identity from this declaration.

## Staging, history and replacement rights

Keep authored simulation snapshots exact. The generated resource is a separately declared bounded build resource; do not weaken recursive equality with a generic generated-file wildcard. Existing Godot script UID handling remains narrow. Copy the same canonical bytes into the editor project and corresponding-source `build/` directory before Godot import. Ensure the preloaded resource is included in the PCK, and independently check its identity through editor, export, relocation and replacement runs. Package inventory and source-reconstruction instructions identify it and its generator/template inputs. Rebuilding generates the identity for that new selected toolchain; an old resource cannot relabel a newly built backend or adapter.

Historical launch directories, packages, archives, source evidence and identity records remain immutable. Existing unversioned PreviewNativeBuildIdentity evidence stays historical with its old semantics; new helpers must not silently accept or migrate it as v2, rewrite old packages, or overwrite the owner's current launch. A new qualified package is staged in a fresh directory and adopted explicitly only after its applicable gates pass.

Preserve LGPL source, debugging and replacement rights. Runtime expected identity contains no DLL byte pin. Corresponding-source delivery, replacement compilation and actual-module proofs continue separately, with every other package byte unchanged in the replacement comparison. An edited/rebuilt replacement is not relabelled as the reviewed source variant merely because the first-party bridge still reports its own compiled fingerprint. Do not use provenance checks to revoke replacement rights.

## Preserved behavior, ownership and gates

This changes expected build provenance only. Preserve ADR007 wall pacing/origin/retention, ADR008 input ownership, ADR009 readings, ADR010/014 profile/source/method admission, two/three-argument legacy bridge defaults, accepted original aircraft/world/model inventories, all four steady-wind starts and ADR013 fixed-anchor semantics. WindCue's identity alias may follow the qualified resource; a new fingerprint alone does not admit a new profile or validate piston wind cues. Existing pure numerical/reference packets, original physical schedules/budgets and observed-review/archive contracts are unchanged. No UI method dropdown or default/profile adoption follows from this contract merge.

Root owns the contract, shared facade and workflow integration. Native owns deterministic CMake/template production. Delivery owns independent qualification, staging, evidence/package closure and tests. Implement only after this contract's protected merge; keep native headless coupled CI independent of Godot resources and preserve the pristine protected NativeCI route.

Required evidence: synthetic Windows/Linux identity construction with intentionally different compiler controls; missing/extra/unknown schema/variant/digest/resource rejection; changed backend/materializer/source/cache/compiled definition/bridge/resource and duplicate/conflicting identity negatives; traversal/reparse rejection; exact authored snapshots plus separately bound generated bytes; an actual facade wrong-fingerprint reply rejected before any tick/live publication with worker joined; unchanged wind/calms/default/input/retained-record regressions; protected Windows/Linux NativeCI and Windows editor/export/relocation/rebuilt-DLL checks. New-profile runtime/source/domain acceptance remains separate. Neither issue149 nor issue127, aircraft validation, owner pilot review or a phase gate closes from a documentation merge or this identity mechanism alone.

## Prospective ADR027 additive apron-domain amendment

PROPOSED, effective only after the checked [ADR027](027-synthetic-taxi-navigation.md) contract merges. ADR027 keeps the exact ordered25source/18control roster membership while changing only assigned first-party start/admission code. Fresh content hashes/generated pins/full fingerprint/rebuilt binary qualification are required. New layout/schema/test references are reconstruction/staged-resource closure, not appended compilation sources. Backend local-window-v2/model/vendor/prepared-surface identity remains unchanged; source_variant alone does not prove new start support.
