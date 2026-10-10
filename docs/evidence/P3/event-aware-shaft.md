# Event-aware propeller engineering evidence

Issue: [ORIGINAL-PISTON-FLIGHT #127](https://github.com/brettbergin/flight-simulator/issues/127). Contract: [accepted ADR014](../../decisions/014-event-aware-shaft.md). Status: source package and isolated arithmetic verified; actual native lifecycle, exported player, aircraft and phase acceptance remain open.

The [loader source amendment](original-piston-loader-source.md) merged as PR147, `a3e2fb6d96489eea7af2454f66412f6a1d76f5c0`, at 2026-10-10T03:30:42Z after all four protected checks passed. Its 55 original numerical cases and budgets remain unchanged. This iteration supplies the separately reviewed propeller amendment; it does not retune that model.

## Source and numerical chronology

The original candidate was preserved after source review identified three defects: a tiny progressing original RPM could be lost during conversion; upward crossing lacked its explicit output boundary check; and a C rounding check alone missed SSE FTZ/DAZ controls. The revised source corrects those admission/boundary checks before any new method output. Event equations, expected values and comparison budgets were unchanged.

The [two-file source transport](../../../third_party/patches/jsbsim/event-aware-constant-power-v1/identity.json) binds pristine before-images, complete preferred editable after-images, the exact materializer and original upstream inventory. Only FGPropeller.cpp and FGPropeller.h change. The source retains original notices and dated project modifications. Fresh objects default to legacy Euler; the checked native setter/getter and opt-in method are separate from cockpit controls. Legacy expressions remain in their original order, which still requires actual rebuilt default regression evidence.

Independent review inspected exact event predicates, error-free product/sum ranges, fixed expansion capacity, quotient order, admitted normal source exponents [-100,100], rejection-before-RPM-assignment and signed-zero holds/stops. The method requires binary64 x64, round-to-nearest, gradual underflow, strict compiler order and explicit FMA. It observes floating-point settings and rejects unsupported settings without repairing them. The finite 64u criterion and composed partition envelopes remain engineering acceptance criteria, not universal libm error theorems.

Root recorded the distinct [pretrial ratification](event-aware-shaft/pretrial-ratification-v1.json) at 2026-10-10T03:26:08Z, before new method output. It binds source and independent reviews, the immutable 45/9/18/4 packet, independently composed partition criteria, actual source closure and the original physical schedule/limits. Compilation then used MSVC 19.40.33813.0 HostX64/x64 with `/O2 /fp:strict /MD /W4 /WX`; actual `/Bv` output confirmed compiler passes, and both implicit `CL` flag variables were unset.

The first [isolated trial receipt](event-aware-shaft/helper-first-trial-v1.json) passed 87 requests with zero comparison failures: 45 arithmetic references; 18 rejected malformed/method/extreme inputs; four signed-zero helper and four RPM-wrapper checks; three subnormal RPM hold/progress checks; four explicit floating-point environment rejection probes; nine kernel partition comparisons at genuine 60/120/240 Hz. Input, output and intermediate partition trace bits are retained. Request SHA256: `ec58fd3eb2469a50229f50212fb11f64f8ae9ce0311684cf1d4c8c148980be66`; tested helper executable SHA256: `e9c630b17aee06e0dda0b7a52c86e40c2baf20da926b69de6ea2cc4e2bea44d1`.

The harness extracted exact helper, wrapper and method declarations from the reviewed source; it did not construct FGPropeller or reproduce engine/fuel chronology. Wrapper scaffolding used held delivered power and zero load. Partitions compare omega-kernel endpoints; native RPM partitions and intermediate-stage acceptance are not claimed. This evidence cannot substitute for actual library default guards or the unchanged complete coupled schedule.

## Corresponding source and corruption checks

The separate [schema2 producer](../../../tools/export/source-bundle-schema2.py) and [trusted extractor](../../../tools/export/extract-source-schema2.py) preserve the historical schema1 route. The exact 291-member source package contains 279 vendor files, including 277 unchanged files and two reviewed modifications, two pristine before-images, the byte-replacement recipe, editable source, build controls and license notices. Verification reconstructs the full pristine tree, rematerializes the full modified tree and compares all bytes. No fuzzy patch parser or archive-supplied code is executed.

The [measured source receipt](event-aware-shaft/source-bundle-v1.json) records two byte-identical archives: 3,826,603 bytes, SHA256 `8053e5a34b45d791b6eba7fa67c1a77cacf9202794b73ea42845dea32a6aa3ec`; complete modified vendor digest `81a0233611154263bfa4ebeded8a1b34331a3e2f8ce97c52b70de82647ebad2e`. Independent review verified every archive member, original notices, before/after bytes and trusted fresh extraction. A prior attempt failed because the Windows sandbox denied a temporary verification directory; that incomplete output was retained and a fresh output passed under narrow escalation.

Ten [source-tool test groups](../../../tests/export/test_source_variant.py) passed against the repository installation. They cover exact reconstruction/repacking/extraction; changed pristine inputs and already-applied source; reused/overlapping roots; duplicate JSON, aliases, links and unknown transport; rehashed corrupt manifests; reviewed archive digests; unsafe ZIP paths including controls and Windows-invalid characters; and unchanged legacy schema1 verification. Fixtures are synthetic text, never a solver trial.

```sh
python tests/export/test_source_variant.py
node tools/check-docs.mjs
```

Actual shared-library/source selection, matching headers and consumer fingerprints, strict compile commands, default-method guards, the unchanged 12-process lifecycle/convergence schedule, worker environment, new profile controls/status, wind regressions, exported views and real DLL replacement remain required. No new playable package, C172 qualification, pilot acceptance, training credit or phase closure is established here.
