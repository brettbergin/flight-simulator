# Original cold-engine player

Status: implementation under review in [PR156](https://github.com/brettbergin/flight-simulator/pull/156), for [issue127](https://github.com/brettbergin/flight-simulator/issues/127). Native and baseline delivery checks below passed on 2026-10-10. Full gameplay, exported visual review and final hosted checks remain pending. This record does not accept the C172S configuration, a phase, hardware handling or pilot training.

## Supported interaction

Pause and use the Aircraft button to select **Original piston prototype — cold engine**. A confirmed fresh attempt starts in calm conditions with brakes held, 100 kg fuel, mixture zero, ignition off, starter released, fuel feed on and a stopped shaft at native tick0. Selection and reset perform no hidden warm-up. The ready-to-fly direct-thrust prototype remains the default; the piston profile admits no airborne or non-calm start.

The separate version2 keyboard preset uses period/comma for increasing/decreasing mixture, F8/F9 for independent ignition toggles, F10 for fuel feed and momentary F12 for starter. Throttle, steering and brakes retain their ordinary bindings, including X idle, B brake hold and Space momentary brakes. The strip displays copied native RPM, combustion, applied controls, fuel and starvation. Cranking, running and coasting remain distinct; propeller motion and combustion audio follow native shaft/running state. These bindings describe the original simulator prototype, not a manufacturer procedure.

Controls support explicit version1 migration into a version2 draft; Apply remains deliberate and missing engine bindings stay unbound. Resume requires a released starter input and admits its native release before Run resumes; clearing local intent alone does not change native-held state. Unsupported profile/wind/start requests preserve the current session before replacement admission. The piston profile does not create a misleading saved flight review: recording/Save is visibly unavailable, while previously saved legacy reviews remain historical observations. Durable profiles, resumable physics and electrical systems are separate backlog work.

See [usage and package instructions](../../../tools/interactive-preview/README.md), [ADR010](../../decisions/010-original-piston-profile.md), [ADR014](../../decisions/014-event-aware-shaft.md), [ADR015](../../decisions/015-source-law-coupled-shaft.md) and [ADR016](../../decisions/016-generated-native-build-identity.md).

## Native and source evidence

The accepted [coupled implementation](coupled-midpoint-shaft.md) merged through [PR154](https://github.com/brettbergin/flight-simulator/pull/154), followed by the closed release/receipt amendment [PR155](https://github.com/brettbergin/flight-simulator/pull/155). This player renews source notices without changing the reviewed numerical expressions, parameters, fixed references, schedules or acceptance limits.

The fresh Windows MSVC19.40 bindings-ON build passed all eleven CTests in 34.60 seconds. Its isolated comparisons passed 137 numerical rows, 270 legacy checks, twelve chronology rows and terminal-retention checks. The original twelve-process physical lifecycle suite passed 1,618,656 checks with zero failures or skips. Independent review checked saved raw outputs and actual loaded DLL identity against the unchanged references and source/build/model bindings. These engineering results do not establish real-aircraft performance.

The first metadata measurement rejected valid MSVC `-c` invocations because its selector expected `/c`. The compiler log already contained the required strict floating-point flags on both modified numerical units. A separately reviewed external checker admitted either exact spelling while retaining every original source/pretrial pin and strict flag check. The failed log, frozen helper and build were preserved; the native build was not altered. Both forms now have CI admission fixtures.

| Binding | SHA256 |
|---|---|
| Renewed corresponding-source archive (3,922,800 bytes) | `39181ba60397fe5c2ad74d14c02150a2488bc8c96dc29529a0a0396cfc1e3b2d` |
| Raw public source identity | `8b3793f79e86760795a0cf5ea3454a62bbdc49ed82bbf9c1a5adc6e007ed1f00` |
| Selected backend identity | `c066b744b180edf04c94ace89edec1d6bdd64018bbcc58d9e630ef0ae3449a6d` |
| Fresh native consumer fingerprint | `5e0abfeae9ffd249f8be3f4410d9903f30736698fcb276bdf72f3630132102e5` |
| Actual baseline JSBSim DLL | `4c8d039ac96de9ea93ebf5e00becfd991dc8ed95261a17c3353607f7ee89883e` |
| Actual bridge DLL | `a6d4caa5712d94ab469decdcd73d2aac120c67f2c46f148560917ff897c1cb5b` |
| Independent compile review | `0756293120bfa7001a285cdc9637d3e23a3bef92579a3d486aa704c3b2f73f6f` |
| Independent saved native-output review | `19295c892295ec476f8240baa95911cd6b2378f895d5cc93e42dbe7bcf7b7147` |

The archive contains 293 files: 279 vendor paths, 275 unchanged vendor files and exactly four modified vendor files. Modified-file notices are dated, original headers/grants remain, and the separate ledger policy preserves corresponding-source, dynamic linkage, replacement and debugging rights. Historical issue149 archives remain unchanged and are not relabelled as release source.

## Windows delivery and current limits

Fresh baseline `run-a3449b0e15f14da78ef1c629c5ecdd3a` passed actual editor, portable clean-path and Unicode relocation checks. Its corresponding source independently rebuilt an ABI-compatible DLL, and the portable replacement loaded that actual module while preserving other payload files and all five selected Microsoft CRT identities. Replacement DLL SHA256 is `efa3da0f2bb79ea28aa9714a820049ca3ce62cc04aa6513b1fc171ccf0281a5e`. Package rights, selected archive and source-replacement audit passed.

The first full gameplay compile found old observed/wind test-scene model-selector overrides missing the parent's new optional argument. The next compile found a new engine test fixture named `Panel`, colliding with Godot's native class. Both failed runs remain preserved; corrections are limited to test signatures/argument forwarding and the fixture preload name. Passing the basic export does not establish full gameplay acceptance.

The first behavioral run exposed a path-spelling mismatch: inventory admission normalized trailing separators, but the native module-ownership check received the raw path. The facade now supplies the same normalized spelling to admission and native initialization. Model-copy negatives use fresh siblings of the installed model so actual DLL ownership remains valid, then remove only their explicitly created fixture files after joining. Existing missing-inventory scene checks now require the complete paused flight, recording and weather to survive preflight rejection. Pacing retains exact command comparison with JSON-decoded numeric types; oscillator cases use separate real generators instead of clearing an active buffer. These corrections await a fresh full runtime run; the failed receipts remain unchanged.

The additive Windows coupled-player CI job retains the existing headless qualifier and checks its own fresh bindings-ON pretrial, strict compiler evidence, explicit execution authorizations, all eleven native tests, source replacement, package rights and all eight cold groups in three gameplay contexts. Ten offline admission fixtures passed locally. The local native trial predates this workflow-only adoption; its frozen pretrial/output evidence remains historical rather than being rewritten to describe later CI sources. Hosted checks bind the final checkout afresh.

Remaining gates: full editor/portable/rebuilt-library gameplay receipts, actual exported layout/readability review, final independent integration review and hosted CI on the final PR head. C172S/electrical/POH calibration, hardware/pilot evaluation, durable saves and phase acceptance remain open.
