# Original cold-engine player

Status: implementation under review in [PR156](https://github.com/brettbergin/flight-simulator/pull/156), for [issue127](https://github.com/brettbergin/flight-simulator/issues/127). Automated Windows native, full gameplay, package and bounded exported visual checks below passed on 2026-10-10. The PR records hosted acceptance for its final head. This record does not accept the C172S configuration, a phase, hardware handling or pilot training.

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

The first behavioral run exposed a path-spelling mismatch: inventory admission normalized trailing separators, but the native module-ownership check received the raw path. The facade now supplies the same normalized spelling to admission and native initialization. Model-copy negatives use fresh siblings of the installed model so actual DLL ownership remains valid, then remove only their explicitly created fixture files after joining. Existing missing-inventory scene checks now require the complete paused flight, recording and weather to survive preflight rejection. Pacing retains exact command comparison with JSON-decoded numeric types; oscillator cases use separate real generators instead of clearing an active buffer. These repairs are covered by the complete runs below; failed receipts remain unchanged.

The v4 editor checks passed, but its portable scene could not open a virtual PCK review fixture as an ordinary filesystem file. The test now materializes the exact byte-pinned public fixture into a fresh process-owned userdata directory, uses the unchanged strict Open path and retires only that temporary file/directory. The v5 editor, portable and rebuilt-library gameplay contexts then passed, but rights packaging failed because the renewed raw source identity had not been staged. The packaging correction copies that exact verified identity into its declared evidence location before the unchanged audit. Neither incomplete run is promoted into a complete delivery pass.

## Fresh complete Windows gameplay and package evidence

At source head `590e1ebae707de96262fd68895312bf1c7249982`, fresh v8 run `run-27d31e66e08f4575874be733fa53ea35` completed editor, relocated portable and rebuilt-source-library contexts, followed by the full package audit. Independent saved-output review found no failures. Each context passed 15,909 cold checks and 41,833 existing facade checks; counts include synthetic validation/presentation fixtures and are not all engine-physics observations. The earlier complete v6/v7 runs remain separately bound historical evidence.

| Cold group, each context | Checks |
|---|---:|
| Bridge/profile admission | 258 |
| Facade and recovery | 274 |
| Fixed pacing | 13,411 |
| Input/migration | 66 |
| Panel | 19 |
| Engine status | 1,792 |
| Legacy wind regression | 12 |
| Actual scene lifecycle and presentation fixtures | 77 |

All 25 pacing profiles per context used the same ten applied commands, reached tick120 and zero debt. Starter was false in those pacing schedules: they establish input/command/state invariance, not startup or takeoff performance. Scene adoption and reset stayed at cold tick0 before explicit resume. Legacy initialization remained tick1. Runtime logs were clean and workers joined.

The raw generated identity resource was identical in all three contexts, and actual module witnesses qualified the bridge, selected JSBSim library and five Microsoft CRT modules inside the payload. Replacement changed only `JSBSim.dll` and `bin/JSBSim.dll`; the other payload bytes were preserved. All 16 payload PE files were x64 PE32+ with saved import names matching actual binary bytes and no debug CRT. The closed 451-file package included the exact seven piston-model files, fourteen staged piston sources, 146 native reconstruction files and 187 authoring source files. Source notices, corresponding archive, source identity, inventory and replacement rights passed the package audit.

Each context retained 9,805 trace records. Editor and portable traces were exact after session-ID normalization only; the rebuilt-library trace passed the predeclared absolute1e-9 plus relative1e-12 bound with unchanged structure, commands and units. This is bounded same-source engineering repeatability, not aircraft fidelity or a new numerical tolerance for the separate physical suite.

| Final evidence binding | SHA256 |
|---|---|
| Independent v8 actual-output review | `56a78ca16a6d5d55bf34aaa9a28e955558ca4220d614cc63c7adbec4b8e4ec78` |
| Full gameplay/package manifest | `b6d7afc6632fbd5c1eda351dbcbbbd7d903c23e334bdd7ba0ab05155ec5f57ff` |
| Full package audit | `6369cd3f21c54d97459d27b3510b1e37fdbd3586c66d13a099dff83e0069c777` |
| Preserved v6 complete qualification | `94882c398a5e7cb16ffb25380ac2ed0f19a86563af2e8d8daeee8fc53e80e2af` |
| Preserved v7 functional qualification, visually rejected | `84eca93888517dd9876ed5830f37ad68c0e703896b4488cb15ee88c9c15c9ad1` |
| Generated identity resource, 467 bytes | `b38b2dad83fd24266a9c3b84deeeb80edbf90100fcea9a035c2385d9328b8186` |
| Preserved v4 editor/baseline review | `f35e225ba204f3e17006af412b6216e7760a52c894fd70d96bea0e8a258a1c5a` |
| Preserved v5 gameplay-only/package-failed review | `612785639a8353082fa8043e0288f10ceec5cfaac6b8757501b6ee769afd855a` |

The original eleven-CTest/1,618,656-check native evidence above remains its separately bound earlier trial, not a rerun inferred from these frontend receipts. This v8 record adds complete local functional delivery evidence without modifying its numerical schedules, limits or observations.

The additive Windows coupled-player CI job retains the existing headless qualifier and checks its own fresh bindings-ON pretrial, strict compiler evidence, explicit execution authorizations, all eleven native tests, source replacement, package rights and all eight cold groups in three gameplay contexts. Ten offline admission fixtures passed locally. The local native trial predates this workflow-only adoption; its frozen pretrial/output evidence remains historical rather than being rewritten to describe later CI sources. Hosted checks bind the final checkout afresh.

The first additive hosted Windows player job passed its native tests but failed export: a relative toolchain path was written into a different staged project's export preset. The proof now resolves the toolchain root before selecting the pinned template. An actual local export with the same relative argument passed editor, clean portable and Unicode relocation checks, including missing-module controls. Independent review of that actual result is `94ea29836e8a4939447b6458d6480dea9818bdca3353ef14cfb252a0f38dbd68`. Its new baseline has no inferred source-replacement result; complete gameplay continues to use the separately accepted baseline above.

An external script argument was ignored by the standard release template; both watchdog failures are preserved. The export now embeds a separately selected visual diagnostic which captures its own viewport without advancing the native simulation. The ordinary game does not invoke it. The v7 functional/package run passed, but actual GPU pixels exposed the engine strip obscuring the enlarged dashboard at960x540. That visual result was rejected. The correction moves the strip to the bottom in that camera only and passed the fresh v8 gameplay/package checks above.

The corrected v8 export then produced 33 PNGs on the reference RTX3090 using OpenGL Compatibility: eleven views each at960x540,1920x1080 and2560x1440. They include exterior, cockpit, enlarged dashboard, paused Aircraft menu, actual Controls scrolling and unavailable/historical review. Each view retained the actual original piston profile at native tick0, with no display fixture or native advance. The observer joined native/audio workers; full original/private-copy payload bytes and authoring sources remained unchanged. Capture receipt SHA256 is `134a9a380537fe79432e6f2fb80c17f30aa10d32441ae5a5c403f3c927aa31dd`; the corrected960 dashboard PNG is `db3f6f111ad9a09fcd11a273325f53b39aee67405f5885fab4c713d095f34141`. Automated capture success is separate from pixel review and listening.

Independent pixel review inspected eighteen original PNGs, including the three dashboard/cockpit sizes and critical960 Controls/menu/review views, plus an overview of all33. Four2560 images were tool-scaled for inspection; the other fourteen displayed at native dimensions. The dashboard obstruction is resolved; the scoped review found no cold-engine UI blocker. Payload/source/PNG hashes, clean exit and joined workers were independently checked. Review SHA256 is `a8cf212a79b87300504ec774df54d1319f5492c0ce02471ab1b681f79191bc9d`. This is an exported viewport engineering review, not human pilot evaluation or a listening test.

All required hosted checks must pass the exact final PR head before merge; [PR156](https://github.com/brettbergin/flight-simulator/pull/156) records that outcome. Listening, C172S/electrical/POH calibration, hardware/pilot evaluation, durable saves and phase acceptance remain open.
