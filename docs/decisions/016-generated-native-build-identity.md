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

Shape alone never establishes a reviewed backend: the existing corresponding-source selector must verify the complete selected source closure and derive its canonical identity. Include the fixed template in declared build-control inputs. Do not include generated output in those inputs or create a fingerprint cycle. Preserve existing selected-backend/materializer derivation, compiler/configuration controls, prefix spelling and ordered LF source hashing. The canonical interactive body begins `verified-jsbsim-backend:<digest>\njsbsim-build-controls:<digest>\n`, followed by the fifteen path/hash lines below; SHA256 of that UTF-8 body is SOURCE_FINGERPRINT. The compiled definition and `interactive-source-fingerprint.txt` must match it exactly.

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

Source-list changes require explicit review, rather than replacing the old count with an arbitrary new count. This LF/ordered identity is distinct from the FDM adapter's raw/sorted identity; do not interchange the algorithms.

## PreviewNativeBuildIdentity/v2 evidence

New staging evidence uses this exact closed top-level shape. All SHA256 values are lowercase64hex; byte counts are nonnegative integers. This is build-side provenance, not a native self-report or persistent flight format.

| Field | Type and fixed meaning |
|---|---|
| schema | String `PreviewNativeBuildIdentity/v2` |
| root | String absolute selected build directory; evidence only |
| source_variant | String, one of the three IDs above |
| backend_identity_sha256 | String, independently derived selected backend digest |
| build_control_sha256 | String, independently reproduced accepted compiler/build-control digest |
| declared_source_fingerprint | String, independently reproduced interactive digest |
| source_bindings | Array of exactly fifteen records in the ordered roster above |
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
