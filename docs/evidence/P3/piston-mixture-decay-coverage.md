# Ordinary piston mixture-decay continuation

Status: **implementation integrated; native and player qualification pending** under [issue202](https://github.com/brettbergin/flight-simulator/issues/202). This correction targets the original engineering piston profile. It establishes no C172 calibration, pilot evaluation, training credit or P3 acceptance.

## Preserved failure and accepted policy

The original mixture reduction fails after three of 28 requested ticks, retaining tick1582. The unchanged-source replay, independently captured failed certificate and exact-rational diagnosis remain preserved in the [contract evidence](piston-local-window-contract.md). The captured frame is SHA256 `01a8cbc256bbc30a5a53265362d5af89a7297cc5d6f5f065cd1b53d9d3458e8b`. Its global time map is genuinely nonmonotone, while the requested short continuation has a certified connected local-half solution. This is not an aircraft parameter or command correction.

[ADR024](../../decisions/024-certified-local-decay-window.md) / [PR208](https://github.com/brettbergin/flight-simulator/pull/208) merged as `2f7f36ede4356b24e98d7676daab7819c01cc130`. The fourth-source allocation in [ADR016](../../decisions/016-generated-native-build-identity.md) / [PR212](https://github.com/brettbergin/flight-simulator/pull/212) merged as `86dace92bf1ec211016dc85d7fd1df0c1d03e85f`. Exact-decimal publication admission [PR211](https://github.com/brettbergin/flight-simulator/pull/211) merged as `f54fb26f745fb543b7c4f1412fc7e1a2dd252926` and remains a prerequisite. Contract acceptance is separate from executing the new solver.

## Separately identified source

The new source is `jsbsim-1.3.1-event-aware-coupled-midpoint-local-window-v2`. Whole-endpoint certification runs first. Only structured algebraic uncertifiability permits one checked connected half-window. Both attempts share eight splits, nine workspace slots and at most18 interval evaluations. Strict exact remaining-time bracketing, the unchanged64-bisection solve, fatal/resource rejection and once-per-public-tick engine/fuel chronology remain mandatory.

| Source allocation | SHA256 |
|---|---|
| New four-file source identity | `c6f96834a166d72300c999e84d95b1bc1da9127c097773e9731e25a094bba233` |
| Derived backend identity | `3d445058dca744fe44811fc02977b2722b42c7eabd861ecf5335ab50ee7db743` |
| Corresponding-source archive,3926779 bytes | `3b50427ed55b9f9ed0e1e5b48876813b34a5de743203b76b141f1c3839e5b1bb` |

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
| Frozen17 amendment expectations | Accepted independently authored references; regeneration passes; new compiled consumer pending |
| Old137/default270/library/chronology12/terminal/full-success compatibility | Unchanged criteria; new-source execution pending |
| Strict Windows/Linux actual compilation and measured isolated executable | First Windows build failed in source generation; fresh successful qualification pending |
| Thirteen CTests and unchanged twelve-process60/120/240 physical suite | Pending |
| Original298 / complete publications / final1607 / joined ownership | Mandatory in all three actual contexts; pending |
| Generated identity, loaded library, source/PCK/model/rights/CRT and replacement closure | Fresh qualification pending |
| Independent final package review and current protected/affected hosted CI | Pending |
| Aircraft, pilot, human/hardware and broad P3 acceptance | Separate open gates |

Close only this coverage issue after the complete corrected continuation and qualification pass. The separate fuel-feed-cutoff movie, camera work, or a green documentation check cannot close this defect.

The source-generation correction accepts only absent or ordinary empty output directories, rejects prior contents and link/reparse paths, and creates every output exclusively. Four added public filesystem regressions pass alongside all16 existing native qualifier fixtures. Actual source preparation in both absent and CMake-created empty directories passes and produces byte-identical driver/helper files to the original preparer; attempting reuse rejects and preserves every output. This is source-generation evidence only. The first failed build remains retained; a fresh successful compile and numerical execution are still required.
