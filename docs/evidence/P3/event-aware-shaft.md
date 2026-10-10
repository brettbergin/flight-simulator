# Event-aware propeller engineering evidence

Issue: [ORIGINAL-PISTON-FLIGHT #127](https://github.com/brettbergin/flight-simulator/issues/127). Contract: [accepted ADR014](../../decisions/014-event-aware-shaft.md). Status: source package, isolated arithmetic and actual-library legacy regression verified; the first actual coupled lifecycle trial failed its unchanged convergence gate. Exported player, aircraft and phase acceptance remain open.

The [loader source amendment](original-piston-loader-source.md) merged as PR147, `a3e2fb6d96489eea7af2454f66412f6a1d76f5c0`, at 2026-10-10T03:30:42Z after all four protected checks passed. Its 55 original numerical cases and budgets remain unchanged. This iteration supplies the separately reviewed propeller amendment; it does not retune that model.

## Source and numerical chronology

The original candidate was preserved after source review identified three defects: a tiny progressing original RPM could be lost during conversion; upward crossing lacked its explicit output boundary check; and a C rounding check alone missed SSE FTZ/DAZ controls. The revised source corrects those admission/boundary checks before any new method output. Event equations, expected values and comparison budgets were unchanged.

The [two-file source transport](../../../third_party/patches/jsbsim/event-aware-constant-power-v1/identity.json) binds pristine before-images, complete preferred editable after-images, the exact materializer and original upstream inventory. Only FGPropeller.cpp and FGPropeller.h change. The source retains original notices and dated project modifications. Fresh objects default to legacy Euler; the checked native setter/getter and opt-in method are separate from cockpit controls. Legacy expressions remain in their original order. The actual rebuilt default regression below provides bounded unit-fixture evidence for that route.

Independent review inspected exact event predicates, error-free product/sum ranges, fixed expansion capacity, quotient order, admitted normal source exponents [-100,100], rejection-before-RPM-assignment and signed-zero holds/stops. The method requires binary64 x64, round-to-nearest, gradual underflow, strict compiler order and explicit FMA. It observes floating-point settings and rejects unsupported settings without repairing them. The finite 64u criterion and composed partition envelopes remain engineering acceptance criteria, not universal libm error theorems.

Root recorded the distinct [pretrial ratification](event-aware-shaft/pretrial-ratification-v1.json) at 2026-10-10T03:26:08Z, before new method output. It binds source and independent reviews, the immutable 45/9/18/4 packet, independently composed partition criteria, actual source closure and the original physical schedule/limits. Compilation then used MSVC 19.40.33813.0 HostX64/x64 with `/O2 /fp:strict /MD /W4 /WX`; actual `/Bv` output confirmed compiler passes, and both implicit `CL` flag variables were unset.

The first [isolated trial receipt](event-aware-shaft/helper-first-trial-v1.json) passed 87 requests with zero comparison failures: 45 arithmetic references; 18 rejected malformed/method/extreme inputs; four signed-zero helper and four RPM-wrapper checks; three subnormal RPM hold/progress checks; four explicit floating-point environment rejection probes; nine kernel partition comparisons at genuine 60/120/240 Hz. Input, output and intermediate partition trace bits are retained. Request SHA256: `ec58fd3eb2469a50229f50212fb11f64f8ae9ce0311684cf1d4c8c148980be66`; tested helper executable SHA256: `e9c630b17aee06e0dda0b7a52c86e40c2baf20da926b69de6ea2cc4e2bea44d1`.

The harness extracted exact helper, wrapper and method declarations from the reviewed source; it did not construct FGPropeller or reproduce engine/fuel chronology. Wrapper scaffolding used held delivered power and zero load. Partitions compare omega-kernel endpoints; native RPM partitions and intermediate-stage acceptance are not claimed. This evidence cannot substitute for actual library default guards or the unchanged complete coupled schedule.

## Corresponding source and corruption checks

The separate [schema2 producer](../../../tools/export/source-bundle-schema2.py) and [trusted extractor](../../../tools/export/extract-source-schema2.py) preserve the historical schema1 route. The exact 291-member source package contains 279 vendor files, including 277 unchanged files and two reviewed modifications, two pristine before-images, the byte-replacement recipe, editable source, build controls and license notices. Verification reconstructs the full pristine tree, rematerializes the full modified tree and compares all bytes. No fuzzy patch parser or archive-supplied code is executed.

The [measured source receipt](event-aware-shaft/source-bundle-v1.json) records two byte-identical archives: 3,826,603 bytes, SHA256 `8053e5a34b45d791b6eba7fa67c1a77cacf9202794b73ea42845dea32a6aa3ec`; complete modified vendor digest `81a0233611154263bfa4ebeded8a1b34331a3e2f8ce97c52b70de82647ebad2e`. Independent review verified every archive member, original notices, before/after bytes and trusted fresh extraction. A prior attempt failed because the Windows sandbox denied a temporary verification directory; that incomplete output was retained and a fresh output passed under narrow escalation.

That first archive is preserved as historical source evidence. Actual consumer compilation exposed an incorrect compiler-option scope: upstream compiles FGPropeller.cpp in the `Propulsion` object target, so assigning its source option in `libJSBSim`'s directory did not apply `/fp:strict`. A separate test-header Windows `ERROR` macro conflict also stopped that build before any engine trial. The failed build and compiler commands are retained; no numerical result qualifies that build.

The [corrected source receipt](event-aware-shaft/source-bundle-v2.json) records the current two byte-identical archives: 3,827,121 bytes, SHA256 `461aba72cd91ae806bcbfaacb6e257d01f258c25b096d0be83d2a12e9a82bde1`. Independent comparison found exactly three changed archive members: CMakeLists.txt, BUILD.md and manifest.json. The wrapper now checks the actual `Propulsion` object target and applies its strict source option there; the instructions require checking the unique configured command and actual compiler invocation. All 279 vendor files, recipe, materializer, notices and reference values remain unchanged. Actual strict compilation and native qualification remain separate gates.

Ten [source-tool test groups](../../../tests/export/test_source_variant.py) passed against the repository installation. They cover exact reconstruction/repacking/extraction; changed pristine inputs and already-applied source; reused/overlapping roots; duplicate JSON, aliases, links and unknown transport; rehashed corrupt manifests; reviewed archive digests; unsafe ZIP paths including controls and Windows-invalid characters; and unchanged legacy schema1 verification. Fixtures are synthetic text, never a solver trial.

```sh
python tests/export/test_source_variant.py
node tools/check-docs.mjs
```

## Actual native first trial: coupled gate failed

The [compact measured receipt](event-aware-shaft/native-first-trial-v1.json) binds the corrected source archive, backend/build-control and consumer fingerprints, exact executables and loaded DLL, authorizations and raw result hashes. A fresh explicit opt-in build completed with MSVC 19.40.33813.0 x64. Independent review checked the unique FGPropeller.cpp configured command and the actual verbose compiler invocation: both apply `/fp:strict` in the `Propulsion` object target, with no conflicting floating-point mode or implicit `CL` flags. The first failed build remains preserved.

Compilation was followed by separate measured-artifact authorization for the actual-library default probe. It passed 270 checks across all 13 original prop-discrete cases and 18 unchanged fields per case, using the original reference and budgets. Actual getters verified fresh legacy defaults, unknown-enum rejection without mutation, reset retention of explicit selection and return to legacy. A separate fresh unset object executed all legacy cases. This is a seeded RPM/held-input unit fixture; five algebraic fields and four conversions are disclosed in the receipt. It executes no Run/RunIC or event-method Calculate and does not qualify coupled behavior.

After that result, a distinct authorization admitted the unchanged 12-process native suite. All 12 children completed with exit 0 and the exact address-resolved loaded DLL identity; no cases or dependent comparisons were skipped. The 120 Hz lifecycle trace and admitted commands were identical on repetition. Nevertheless, CTest correctly failed: 1,618,656 checks included three shaft convergence failures. Each failed check combines the 60 Hz/120 Hz absolute envelopes and refinement condition. The exact numeric values and unchanged limits hash are in the receipt; the table rounds values for readability.

| Time(s) | 60 Hz error/budget(rad/s) | 120 Hz error/budget(rad/s) | Failed constraint |
| --- | --- | --- | --- |
|1.1|0.4586895/0.3731891|0.1541221/0.1865946|60 Hz absolute envelope|
|1.2|0.5851887/0.5434191|0.1929859/0.2717096|60 Hz absolute envelope|
|53.8|2.1829604/0.3404171|0.8060834/0.1702086|60 Hz and 120 Hz absolute envelopes|

The refinement inequality passes at all three samples. Independent offline review recomputed the frozen observation checks against preserved rows and reproduced exactly these failures and metrics. No budget, expected value, event exclusion or source was changed after observation. Trace completion and the other passing checks do not turn the numerical gate into a pass. The follow-up defect is [#149](https://github.com/brettbergin/flight-simulator/issues/149); issue 127 remains open.

Recorded stages bound the investigation. The 1.1 s/1.2 s failures occur during starter-only cranking, with Running false. At 53.8 s combustion is off at all rates, but their first literal-zero shaft times differ: 53.8 s,53.8083333 s and 53.8125 s at 60/120/240 Hz. The source samples engine-minus-load power before the held-power angular solve. These observations suggest timestep-dependent coupling and stop timing; they do not establish an error-free arithmetic defect or justify extra exclusions. Changing power/load chronology, substeps or state ownership requires a separately reviewed coupling contract. The held-power kernel and the complete coupled engine/airframe have distinct acceptance obligations.

The failed coupled gate, native consumer/profile controls, wind and interactive regressions, exported views and actual DLL replacement remain open. No new playable package, C172 qualification, pilot acceptance, training credit or phase closure is established here.

A separate run of the eight existing native CTests against this build passed seven. Replay reconstruction initially rejected a stale source-fingerprint calculation before its scenario. A separately reviewed correction subsequently passed the fresh standalone reconstruction regression against the same DLL: checkpoint72000,7200 continuation ticks,1939 rejection cases and identical baseline/reconstructed artifacts. The corrected frontend calculation is pending cohesive native/build integration; this does not change the failed coupled gate. This run excluded the separately preserved failed engine lifecycle test and does not establish a full CTest pass.

The prospective [corrective contract](../../decisions/015-source-law-coupled-shaft.md) and [independent reference design](coupled-midpoint-reference-design.md) specify source-law coupling and the finite reference cases before implementation. No new method outputs or adoption evidence are claimed.
