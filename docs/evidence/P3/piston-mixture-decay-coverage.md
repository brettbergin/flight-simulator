# Ordinary piston mixture-decay continuation

Status: **automated Windows native/player qualification and independent package review passed; protected integration tracked in PR216** under [issue202](https://github.com/brettbergin/flight-simulator/issues/202). This correction targets the original engineering piston profile. It establishes no C172 calibration, pilot evaluation, training credit or P3 acceptance.

## Preserved failure and accepted policy

The original mixture reduction fails after three of 28 requested ticks, retaining tick1582. The unchanged-source replay, independently captured failed certificate and exact-rational diagnosis remain preserved in the [contract evidence](piston-local-window-contract.md). The captured frame is SHA256 `01a8cbc256bbc30a5a53265362d5af89a7297cc5d6f5f065cd1b53d9d3458e8b`. Its global time map is genuinely nonmonotone, while the requested short continuation has a certified connected local-half solution. This is not an aircraft parameter or command correction.

[ADR024](../../decisions/024-certified-local-decay-window.md) / [PR208](https://github.com/brettbergin/flight-simulator/pull/208) merged as `2f7f36ede4356b24e98d7676daab7819c01cc130`. The fourth-source allocation in [ADR016](../../decisions/016-generated-native-build-identity.md) / [PR212](https://github.com/brettbergin/flight-simulator/pull/212) merged as `86dace92bf1ec211016dc85d7fd1df0c1d03e85f`. Exact-decimal publication admission [PR211](https://github.com/brettbergin/flight-simulator/pull/211) merged as `f54fb26f745fb543b7c4f1412fc7e1a2dd252926` and remains a prerequisite. Contract acceptance is separate from executing the new solver.

## Separately identified source

The new source is `jsbsim-1.3.1-event-aware-coupled-midpoint-local-window-v2`. Whole-endpoint certification runs first. Only structured algebraic uncertifiability permits one checked connected half-window. Both attempts share eight splits, nine workspace slots and at most18 interval evaluations. Strict exact remaining-time bracketing, the unchanged64-bisection solve, fatal/resource rejection and once-per-public-tick engine/fuel chronology remain mandatory.

| Source allocation | SHA256 |
|---|---|
| New four-file source identity | `73000fbab720fe8361d65de049a027b6e280e5f835eedaab92df0bdd1746d770` |
| Derived backend identity | `2d633139c38d27ec445ca8357ede0fae526f95da80808b3ef45e1708be4189ea` |
| Corresponding-source archive,3926768 bytes | `7341b8d797082efb2107f12511ac0ecab09fde66423c8bb3b6cd329ddff28177` |

These source-only allocations are not binary hashes or final consumer fingerprints. The current numerical change is confined to FGPropeller.cpp inside the inherited four-file modified-library package. Immutable v1 source, model XML, coefficients, old references and failed artifacts remain unchanged. Build identity retains exactly25 ordered consumer sources and18 unconditional controls. The reviewed implementation entered at `96adddfd908309650a01de64552f563630bdfeea`; two stale fixture counts were corrected separately at `b88218f55a87dfa077a54b4282e8c46d9b252d99`, strengthening explicit four-route admission without changing physics.

## Exact original replay

The public [recipe](../../../tests/engine/local-window-replay/recipe.json) is SHA256 `2ef833b13cab7127b19ae84272f9bfc015133e14c125d781c535b84ad284aba1`. Its [binary64 argument ledger](../../../tests/engine/local-window-replay/argument-binary64.json) preserves138 FLOAT bit patterns;31 schema INTs and265 step INTs retain their types. All298 original calls remain ordered, with only fresh session/model-root and reviewed runtime-identity binding. No RPM injection, altered rate, added setup call, numerical tolerance or physical-budget retuning is allowed.

Successful acceptance requires call296 to complete28 ticks through1607 live/no fault, followed by joined close at call297, in each actual editor, portable and rebuilt-library context. The historical expected failure remains a failure; it is not overwritten by a corrected receipt. Separate full-precision receipts bind complete native publications rather than inferring success from displayed RPM.

## Qualification evidence

The executable route is the additive [local-window workflow](../../../.github/workflows/coupled-local-window-ci.yml): bind pretrial, compile fresh strict source with bindings ON, measure actual source/compiler/binaries, explicitly authorize isolated and physical execution, run all13 CTests, then verify. Follow with fresh export, exact archive reconstruction, rebuilt DLL replacement, whole-flight checks in all three contexts and independent final package review. Preserve prior usable sessions and every failed attempt.

Offline schema validation, contract tests, rights/runtime admission, all-four-route fingerprints,23 synthetic native-identity tests, bindings-ON/headless qualifier tests, fixed mathematical and17-reference regeneration,71 original-replay admission cases and PowerShell staging/guard tests passed locally. Two initial stale route-count assertions failed before their separately reviewed correction. A Windows sandbox temporary-directory access failure was retained; the remaining fixtures passed using an isolated workspace temporary directory. None of these offline checks executes the corrected flight.

The first fresh bindings-ON build at `b88218f55a87dfa077a54b4282e8c46d9b252d99` **failed before native tests**: CMake/Ninja created an empty generated-source directory, and the17-reference preparer's absent-directory guard rejected it. Preserve its verbose log and partial build. Correct only that source-generation integration mismatch; do not erase the failed attempt or relax numerical criteria.

| Gate | Current evidence |
|---|---|
| Frozen17 amendment expectations | Immutable regeneration passes; the exact bound scalar CTest passed. Its individual successful stdout was not retained; no per-case runtime count is claimed |
| Old137/default270/library/chronology12/terminal/full-success compatibility | All137 native rows,270 legacy checks,12 chronology rows and terminal criteria passed with unchanged expectations |
| Strict Windows/Linux actual compilation and measured isolated executable | Fresh successor Windows build and independent actual-source/compiler/binary measurement passed at a2ebb; current-head hosted Linux native jobs also passed |
| Thirteen CTests and unchanged twelve-process60/120/240 physical suite | Fresh successor: all13 CTests passed; unchanged12-process physical suite passed1,618,656 source-bound checks without skips. Earlier failed b66 trial remains preserved |
| Original298 / complete publications / final1607 / joined ownership | Editor, portable and rebuilt-library original298 each passed11,292 receipt checks; call296 completed28 through1607 live/no fault and call297 joined |
| Generated identity, loaded library, source/PCK/model/rights/CRT and replacement closure | Fresh export, source reconstruction, replacement and original public package audit passed; independent saved-packet review passed |
| Independent final package review and current protected/affected hosted CI | Independent saved-packet review passed; current protected/affected checks and merge tracked in PR216 |
| Aircraft, pilot, human/hardware and broad P3 acceptance | Separate open gates |

Close only this coverage issue after the complete corrected continuation and qualification pass. The separate fuel-feed-cutoff movie, camera work, or a green documentation check cannot close this defect.

The source-generation correction accepts only absent or ordinary empty output directories, rejects prior contents and link/reparse paths, and creates every output exclusively. Four added public filesystem regressions pass alongside all16 existing native qualifier fixtures. Actual source preparation in both absent and CMake-created empty directories passes and produces byte-identical driver/helper files to the original preparer; attempting reuse rejects and preserves every output. This is source-generation evidence only. The first failed build remains retained; a fresh successful compile and numerical execution are still required.

The next fresh Windows build at `187118e5dc65d6bb371ed1f0390b12cfa82d3ac2` compiled successfully with bindings ON. Its canonical corresponding-source archive passed all21 source/policy checks. Measured authorization then rejected stale duplicate preparer/README pins in the isolated-unit runner before any numerical test executed. The correction updates those two metadata pins and the runner's public source-manifest row; two offline regressions now compare both qualifier pin sets with actual source and check every public probe/shared manifest entry. All32 qualifier fixtures and29 probe fixtures pass. The workflow selects the single canonical `*-library-source.zip` while retaining the separate reproducibility archive. This successful compilation remains retained as untested evidence; a fresh build and measured execution of the corrected source are still required.

## Preserved native failures and reviewed successor

The fresh bindings-ON Windows build at `b66e9d743b42b626a9d89f26863292e4058f00a5` compiled, passed the 21 archive/source-policy checks and received independent review of its measured actual source, compiler commands and binaries. Its actual fingerprint was `598fea7dd5c0782f0fdbe7fc14f0641891cc52d6c5796b9d7e65059320c3596d`. After explicit unit and physical authorization, CTest passed ten tests and failed two; the dependent physical lifecycle test did not run. Neither compilation nor those ten passes establishes repaired flight behavior.

The original 137-case comparator rejected K15_0's changed error text. Independent exact analysis confirms the requested time remains outside the certified half-window and must still reject; ADR024 requires retaining the historical coverage-rejection category. The frozen 17 numerical expectations passed in the new scalar consumer, but its additional floating-point compatibility check expected the wrong first guard on MSVC. The production environment guard remains byte-identical to the historical implementation; the corrected supplement derives its exact expected guard from installed caller rounding, then requires unchanged rounding and full MXCSR. No numerical predicate, reference expectation, tolerance or accepted rejection set is changed.

The separately reviewed [successor allocation PR217](https://github.com/brettbergin/flight-simulator/pull/217) merged as `18bfd945f902b36ca2a459d068ed92ac0310218e` after independent exact-head review and all four protected checks. It preserves ADR016's initial allocation and allocates only the successor source recorded above. Within its deterministic 293-file archive, exactly FGPropeller.cpp, its recipe and derived manifest change. The production correction is one rejection-message literal; the independently reviewed companion scalar supplement changes only its caller-state expectation. Frozen 17/137 references and all original model/source-rights/resource budgets remain unchanged. Source-only review does not allocate or qualify a new compiled fingerprint.

Hosted Windows checks also exposed an independent checkout problem: Git converted the new build entry's 232 LF endings to CRLF, exactly reproducing the unexpected 20,393-byte hash instead of the pinned 20,161-byte source. An exact-file LF attribute fixes checkout; strict raw-hash validation stays intact. A real private Git checkout regression covers LF success and missing-rule/CRLF-rule rejection with global/system configuration and attributes isolated. The retained hosted Ubuntu run reached CTest and failed the same K15 category comparison; it is a separate failure from Windows checkout drift.

Fresh offline checks pass: 53 mathematical/tamper tests, 33 qualifier fixtures including the actual Windows-style Git checkout, 23 native-identity fixtures, 21 actual archive/source-policy checks and 72 rights checks. Five package-fixture junction cases could not create links inside the Windows sandbox; the complete 21-test package-fixture file then passed in the permitted environment. All other 94 Node cases, 15 replay-staging cases and process guard controls passed. Those offline results preceded the fresh execution below. Every prior failed attempt and usable launch package remains preserved.

## Fresh successor execution

The fresh committed execution head is `a2ebb4b2708f362f35b5401cc9a62f3c6b17ec70`; later evidence-only commits must not be substituted for that actual build head. Public preparation, fresh bindings-ON compilation, measurement and explicit isolated/physical authorization passed. Independent compiler/source review binds all25 ordered sources,18 unconditional controls, seven build witnesses,58 binaries, strict modified/scalar compiler commands and all13 CTest definitions. Actual native fingerprint: `ab51d78a61e0c736e4dd99f5dcf1b39260e6b1d3e04c3637df994866a47441d1`; control identity: `513d6d5a496e6f7270194caaa2c4ed40843c67e9c1f1d3cd92800d0693e326cb`.

All13 actual CTests passed in42.40 seconds, including the unchanged twelve-process physical lifecycle suite. Independent saved-artifact review rehashed authorization, actual binaries, logs and57 physical outputs; independently compared all137 native expected rows; verified270 legacy/12 chronology/terminal checks; and verified the repeated physical trace/commands byte-for-byte. The source-bound physical validator reports1,618,656 passing checks and no skipped cases/comparisons. The scalar target passed its exact measured CTest, but subsequent public show-only discovery reset LastTest.log and individual successful scalar stdout was not retained; its17 frozen expectations and supplement are source-bound, without an invented observed scalar check count.

Fresh export, exact corresponding-source reconstruction and rebuilt DLL replacement passed. The fresh whole-flight runner then terminated with exit0. Its editor, portable and rebuilt-library contexts each preserved the original298 calls,138 binary64 argument fields,31 schema INTs and265 step INTs. Each separate full-precision receipt passed11,292 checks, completed all28 requested continuation ticks through1607 live/no fault, and joined close. A subsequent pure saved-receipt validation passed for all three exact context/model-root bindings; it launched no native process.

| Final artifact | SHA256 |
|---|---|
| Whole-flight manifest | `55cced10203bb820afc9b084368c7c21ec82a717ae21d7748bd2fb335cf73758` |
| Original public package audit | `df22806ba6b88ee0f88c95ce21bce6dce7ee30d21eca6d412be9819841e3010b` |
| Editor original298 receipt | `e4d63c96d8b809d94bd024bcbfdfd1674b643bc10b0551c5cb07cfbf5634e1fc` |
| Portable original298 receipt | `28609036a7e5ed8729322262744c74e7049eada3ad9ace452052bc752b33f9b0` |
| Rebuilt-library original298 receipt | `e1ec23b0d996989e56f9b8fe9ec9f34ec624055c9582d655ebde82b532aac266` |
| Independent actual compilation review | `c60834c76037ed4a6c0a968f121aabbecccce0469fa6b4e22dbb4bf44bc0bd88` |
| Independent actual native-result review | `11f29d2de8fe8b551ce704fa749b4e9e30f8771c2d0a4f60b3b1d5c83390da32` |
| Independent81-path frozen PR source review | `338e1864bfcd62f3ef4ca089d2c169e9c29d03008568b246292bca268f97dd6d` |

The final manifest records556 shipping files and247 authoring bindings. The original public package audit passed source/model/notices/rights, actual seven-module containment, full PE/five-CRT closure, editor/portable exact repetition and actual rebuilt-library replacement. Independent final saved-packet review passed (SHA256 `5ba94b8db726098ac6de89bfdcf5343cf517a3636526deb587f77e7c34531e11`): 556 shipping files, 247 authoring bindings and 195 PCK entries were rehashed. All 29,415 legacy trace records validated; editor/portable normalized records were exact, and replacement records remained within the frozen comparison budgets. Complete original298 histories and source/native/model/rights/CRT/PE closure passed. The reviewer separately classified 21 generated post-copy evidence/notice files; only the two product DLL copies changed. Protected integration and current affected CI are tracked in [PR216](https://github.com/brettbergin/flight-simulator/pull/216).

Two redundant manual audit attempts are retained as command/operation limitations: passing relative roots rejected the exact absolute model-root binding; using absolute roots on the completed packet reached a missing generated proof-evidence counterpart in the replacement tree. This package-audit command authors proof files and is not an idempotent saved-packet verifier. Both attempts stopped before its first write; they did not alter the successful original audit or justify weakening path/closure checks. Independent final review instead rehashes the completed packet and classifies generated proof outputs separately from shipping differences.

These results repair the supported original engineering continuation. GPU appearance, C172 calibration, human hardware/pilot evaluation, training qualification and broad phase gates remain separate. Prior human sessions and historical usable packages are preserved.
