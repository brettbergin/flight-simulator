# Fixed packed synthetic taxi observer v1

Proposed companion to [ADR027](../../decisions/027-synthetic-taxi-navigation.md) for [#225](https://github.com/brettbergin/flight-simulator/issues/225). This contract precedes implementation. It defines engineering observation transport for the actual exported player; it introduces no normal-flight API, user setting, native control, aircraft definition or acceptance claim.

## Entry and fixed resources

The existing root `--camera-checks` branch in `app/simulation/flight_scene.gd` remains unchanged: disable process/physics, instantiate fixed `res://camera_checks.gd`, then return before ordinary flight initialization. The generated Node gains a closed observer dispatch before its original checks. Without an observer selector, the existing renderer/capture checks, immutable132 references, source-qualified35 rows, receipts, failures and cleanup remain byte-exact. No-flag ordinary flight stays unchanged.

Three original MIT authored test resources are copied through the closed `tests/world/taxi/` source group:

| Authored source | Fixed packed path | Role |
| --- | --- | --- |
| `tests/world/taxi/shipping_probe.gd` | `res://taxi_tests/shipping_probe.gd` | Node transport/render/resource prerequisite; no flight session |
| `tests/world/taxi/shipping_observer.gd` | `res://taxi_tests/shipping_observer.gd` | Node visual observer with complete authority and lifetime checks |
| `tests/world/taxi/pilot_journey.gd` | `res://taxi_tests/pilot_journey.gd` | Frozen reviewed six-journey controller and awaited measured checkpoint callbacks |

Source versions/hashes are frozen and independently reviewed before consumer output. The journey's existing pilot commands, spatial/dwell/recording/source/lifetime gates remain exact. The observer/probe adaptations change only the SceneTree-to-Node shell, access to the same actual tree/root, and fixed resource/data transport. No source is loaded from outside the PCK, from a binding field, or from a user-selected resource name.

`tools/interactive-preview/camera-staging.ps1` owns the generated dispatch. Existing simulation staging and tests append exactly the three sources to required snapshots; source/UID/no-extra rules remain. Existing run tooling imports/compiles all three exact resources and includes them through the existing `taxi_tests/*` export rule. All generated harness and authored sources participate in actual source/resource/PCK/corresponding-source manifests and rights attribution. They are not appended to native25/control18/build9 membership. No engine build option, custom executable, PCK rewrite/overlay or alternate native/model API is permitted.

## Closed diagnostic arguments

Root launches the actual copied `WholeFlightPreview.exe` with its normal adjacent same-basename PCK and payload working directory. No `--path`, `--main-pack`, `--script` or custom main loop is used. Existing explicit engine renderer, resolution and diagnostic Dummy audio invocation are retained.

The observer user tail, after the engine `--` separator, consists of exactly these six strings in this order:

1. `--camera-checks`
2. `--taxi-observer=probe` or `--taxi-observer=capture`
3. `--taxi-observer-binding=<absolute JSON file path>`
4. `--taxi-observer-binding-sha256=<64 lowercase hexadecimal characters>`
5. `--camera-request-method=gl_compatibility`
6. `--camera-request-driver=opengl3` or `--camera-request-driver=opengl3_angle`

The generated harness validates the complete tail before loading either fixed observer or opening a flight session. Unknown/duplicate/conflicting selectors, other diagnostic modes, malformed/empty/relative data paths, invalid raw hashes, invalid renderer combinations, missing arguments and extras fail with a nonzero exit. It must use a literal two-case dispatch, not dynamic code-path construction. A binding/output path is data IO only. The trusted host rejects observer tokens without `--camera-checks` before launch; this does not add a global user-argument parser to the unchanged normal-flight Scene.

The host emits the binding as unambiguous closed JSON, rejecting duplicate object keys in its input admission. The harness checks the exact independently admitted raw binding digest before decoding; then checks closed keys/types and all applicable pins before passing it to a fixed Node. No self-consistent binding is its own source, inventory or qualification authority. Host preparation and independent review bind actual prior evidence separately.

## Binding and output ownership

The binding schema is `QualifiedTaxiPackedCameraPreparation/v1`. It preserves the prior preparation's source/native/module/resource/full-payload/matrix/prerequisite semantics and adds a fresh external output location. The exact top-level keys are:

| Key | Domain |
| --- | --- |
| `schema` | Exact schema String above |
| `context` | `portable` or `replacement` |
| `source_head`, `native_source_head` | Actual lowercase40 Git commit Strings; historical/native correspondence explicit |
| `native_predecessor_admission` | Raw file pin to the exact independently reviewed historical-to-current native continuity record; host admits its full semantics before launch |
| `payload` | Actual absolute copied payload directory |
| `executable`, `pck` | Actual absolute `{path:String,bytes:INT,sha256:String}` raw file pins; nonnegative bytes and lowercase64 digest |
| `source_variant`, `source_fingerprint` | Actual qualified generated native identity Strings, not an invented successor fingerprint |
| `expected_modules` | Complete exact seven-module basename-to-bytes/digest map from the qualified payload/native receipt |
| `resource_files` | Complete required packed relative path/bytes/digest rows, including all three fixed test resources |
| `source_files` | Complete actual copied source/payload rows and immutable source pins used by the observer; no external observer code rows |
| `expected_matrix` | Exact independently frozen142 unique name/context/profile/start/page/width/height/tick-zero rows |
| `expected_images` | Actual INT142 |
| `qualification_manifest`, `whole_flight_result`, `payload_inventory` | Exact raw pins to actual current full qualification and independently attributed same-run complete payload evidence |
| `editor_preparation`, `editor_visual_receipt` | Exact actual editor evidence raw pins, with independently reviewed equivalence when historical reuse applies |
| `output_root` | Absolute fresh host-owned diagnostic evidence directory, external to payload/source/profile/prior evidence |
| `scope` | Explicit engineering-only observation scope String; no execution authority |

A raw file pin has exactly `{path:String,bytes:INT,sha256:String}`; its absolute path is ordinary and its nonnegative finite integral bytes/digest match actual raw data. Packed resource rows have exactly `{path:String,bytes:INT,sha256:String}` with unique closed relative packed paths. Each expected module has exactly `{bytes:INT,sha256:String}` under its actual closed basename. Matrix rows have exactly `{name:String,width:INT,height:INT,profile:String,start:String,page:String,tick_zero:BOOL}`. All142 rows and the five matrix groups (25 original,42 apron views,18 Taxi/Back/map-hide,12 rebase,45 actual approaches) preserve the independently frozen original matrix; no changed name, missing row, duplicated row or substituted scene qualifies. Source rows are exact absolute raw file pins. Evidence pins identify complete retained records, not a successful-looking projection. No unknown top-level or nested pin/matrix keys qualify.

Paths, nested pin rows, source/module membership and matrix values are derived from the exact actual admitted preparation, not accepted merely for matching field types. Metadata numeric cells are restored only after finite integral/range checking; do not round an imprecise JSON value into a pin. Digests compare exact lowercase raw bytes. The JSON raw pin, host source/inventory/identity admission and actual resource checks must all agree. The source/raw roster expands by the actual added files; do not retain an obsolete869 count as a gate.

Before launch, Root preparation validates ordinary nonreparse/nonalias binding and output ancestors, complete actual payload/source and fresh output ownership. It preserves full EXE/PCK and inventory bytes before/after. Output is limited to fixed receipt, matrix PNG and before/after binary names under `output_root`, with fresh-file/no-overwrite checks. No arbitrary deletion, profile save or owner-game handling is added. Binding data may not choose a script, resource, callable, command, physics interval or arbitrary test plan. Host raw bindings and full output remain retained evidence, not shortened receipt projections.

## Execution and closure

Both fixed resources extend Node. The generated harness attaches one resource, then invokes its internal `execute(binding_path:String, output_root:String, requested_driver:String)` after validation. `_ready` must not launch a second execution. Use the actual `get_tree()`/root Window for frames, rendering and quit. The journey is a fixed preload. There is no external script-directory discovery or external Journey load.

Probe checks actual release EXE/PCK, generated native identity, required ClassDB registration, exact packed resource pins and actual Windows renderer/driver. It observes a real nonempty rendered image without opening an aircraft session or advancing simulation. Its receipt is explicitly a packed transport prerequisite. Actual probe exit0, join, stream drain, clean error/leak log, raw receipt pins and capture are independently verified before launching capture. Source checks, launch success, a timer or a requested driver cannot substitute.

Capture preserves all142 images at the original matrix sizes, actual complete before/after binary authority, held controls/recorder/map/sign/page/rebase predicates, actual seven loaded modules/bytes, same native identity and six complete measured pilot journeys. Checkpoint observers remain awaited. No teleport, pose/control injection, direct solver step, hidden assist, reduced journey or alternate camera is permitted. Actual session close and audio shutdown joins, pointer visibility cleanup and source-after checks are required on success and failure. Exceptions fail the process and retain raw output; they cannot justify unloading a live worker or fabricate a joined receipt.

The reviewed transport120-second and capture1800-second bounds remain unchanged. Probe/capture are separate supervised processes; all actual process joins/drains and bridge termination are observed. Timeout/forced termination is a failed campaign. The copied EXE/PCK/source payload remains byte-exact during each campaign. A newly exported PCK containing these resources is a new artifact requiring qualification; it cannot be labeled the old unchanged PCK.

## Source review and actual acceptance

Before implementation output: checked contract merge, explicit ownership, independent source review of the parser, exact Node-shell changes, journey preservation, data/path admission, cleanup and source/resource/rights closure. Meaningful negatives cover missing/duplicate/unknown/conflicting selectors, invalid binding/hash, injected resource path, stale native/source/module/resource pin, absent/extra resources, existing/outside output, failed probe and unjoined workers. Preserve the original camera branch and no-flag game; staging negatives remove/drift/add each new resource without a generic allowlist or ignored extras.

After implementation: freeze actual committed/raw sources; run fresh normal export/replacement/full wholeflight qualification at that head with original35 camera checks in all three contexts. Independently attribute every project and both payload row, packed entry, producer and rights. Current protected CI, exact native/source continuity and existing checks remain mandatory. Old failed external transport, inventories and receipts remain historical; do not rebind them to a new head.

Then both actual shipping contexts must pass their own packed probe and complete142-image/six-journey capture using those exact independently reviewed payloads. Independent image readability, geometry, visibility and complete binary authority review remains mandatory. This contract, camera35 checks or a successful probe does not itself approve those pixels.

Historical editor142 may be reused only after an independent explicit audit proves all actual relevant Scene/UI/camera/world/map/input/controller/native/model/renderer/EXE/resource/settings and image dimensions unchanged, except unused added packed diagnostic resources. Pin the original editor preparation/observer/receipts/images/binary snapshots and six actual joined journeys. Any relevant change requires fresh editor capture. Reuse retains the original head/run attribution; report142 historical-equivalent editor plus142 fresh portable plus142 fresh replacement, never426 freshly captured at the successor head. This is a concrete final review choice, not automatic equivalence or a generic reuse protocol.

Normal pilot use, installed-user performance, hardware comfort, quantitative C172 handling, real airport procedure, training credit and owner phase acceptance remain separate. This amendment closes no runtime or phase gate.
