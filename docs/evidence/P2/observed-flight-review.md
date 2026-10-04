# Recorded flight review implementation evidence

Issue [#134](https://github.com/brettbergin/flight-simulator/issues/134) implements accepted [ADR011](../../decisions/011-observed-flight-review.md), merged in [PR133](https://github.com/brettbergin/flight-simulator/pull/133). This is partial PRD-025/UX-017/UX-021 engineering coverage. Aggregate replay/debrief, durable flight logs, aircraft/hardware/pilot and phase gates remain open.

## Player outcome and authority

Flight review opens at a verified pause or joined stop. It shows a separate recorded north-up path, actual-sample scrubber, speed/ellipsoid-height/vertical-speed/fuel graphs and native-held controls. One memory-only record targets2Hz and retains at most2401 actual observations over144000 relative native ticks. Late observations, missing targets and uncaptured tails remain distinct. Review never seeks physics, moves the actual ownship/camera, modifies the native held axes or changes the live locator.

Stored observations remain binary64 SI. The review uses the accepted dashboard conversions for knots, feet and ft/min; it still labels ellipsoid height, true airspeed and prototype native truth explicitly. Fuel stays kg. These display conversions introduce no new sensor, datum or aircraft model.

Restart/named-start/quit after verified native time advances requires an explicit Discard action. Cancel is default. Successful old-worker close seals its valid prefix truthfully; failed new initialization keeps the old metadata, observations and endpoint available. Replacement occurs only after a qualified fresh initialization. Exit/process loss discards memory; no persistence, full event history, combined-flight resume, procedural inference, scoring or C172 fidelity is established.

## Independent references and development checks

Before consumer observations, Python arbitrary-precision integers, Fraction and Decimal80 froze24 full-range arithmetic cases and18 sampling schedules with exact tick/count/rational expectations and an absolute1e-10m chord allowance. The dense schedule expands all2401 samples. Frozen expectation SHA256 `a4c3184c46f2eb76c85ff4ba43fc8aac49e772a447576eeec5663fff1ac78844` and generator SHA256 `212ad8eac94b43db801ada0597b8a3e07982151bd8baa03ca75cbc04605e874c` remain unchanged; published preparation bindings distinguish original/published newline hashes.

An initial pure run found one malformed-fingerprint classification defect; valid changed seed/model assertions were corrected to identity-change semantics. Strict StringName/type rejection then received14 additional closed-value mutants. Preserved failing evidence precedes the final24,927/24,927 pure checks, including foreign-thread owner preservation and copied status/selection. Numerical expectations and tolerances were not fitted to failures.

Fresh isolated project `b7caa186571f4aa0af11466e3f7012ba` passed24,927 recorder checks and42 new actual-native scene checks over120 actual flight ticks, plus the affected Controls,107 scan,146 geometric and51 route checks. Scrub/dismiss/default-Cancel preserves complete native Readback, held axes/debt, mapper, camera, origin and counted commands/lifecycle. The reset failure uses a real rejected model-inventory path; only its expected error logging is suppressed in the test subclass, and no native reply is fabricated. Earlier scan regression failures identified a fixture's newly required explicit confirmed reset; its prior assertions remain intact.

## Frozen portable and exported verification

Runtime source `ec205f077eeddb5fe3c4f7edd2b0681aebf98248` and final package source `e689c3d38f657ae76b9a94a7b87faff59c18dca1` have independent source reviews. The latter changes only four explicit confirmed-reset calls in the existing origin fixture and its ownership mapping. The earlier package `run-929061c647ef4c59a776f281b85fa3b6` failed those fixtures; its receipt and raw log remain retained. The corrected fixture admits replacement at an already verified pause or initialization-only joined boundary, retaining all origin transaction/callback invariance assertions.

The passing isolated packet `run-4854f052a3bc4570b372a86d047ea026` binds the exact source and all staged/package bytes. Editor, portable and source-rebuilt JSBSim replacement runs each passed all24,927 recorder and42 new native scene checks, including the unchanged independent42-case reference digest. The combined ground/takeoff/flight/landing/braking traces compared9,805 records per run; baseline/replacement tolerances remain absolute1e-9 and relative1e-12. Mandatory source closure, rights notices, compiler/runtime pins and actual loaded modules passed. No native source or accepted baseline build changed.

| Frozen artifact | SHA256 |
|---|---|
| Package manifest | `3fc1ba348ac1d5192fc4680b52ecbc6f8a7c42fd29fcef3608ba628bbabbe33e` |
| Package audit | `204ff4cf79ef0c9b3bb3d6f5888420a88bc3d9a4dfccd6cc7230859669bb0b49` |
| Exported game PCK | `2834e2c61d4c1d9b398f528afd365c023872037d824d5f771bf8db4afc8206e2` |
| Exported game EXE | `d34d36f3be1a6c49c56525ae86469b92e4f417ddf0b43cf00dd80c385c4b0562` |
| Accepted native bridge | `5fa8c9ff0bf82ce79b8110b625c17c8d62c589acc746ee05d6f785d2f6a7d256` |
| Accepted JSBSim library | `7963d908c74a039e0e8d0664090fad33b777c60e38e9e6e9bb5d85d5da6f7948` |
| Exported visual receipt | `053eb246eeea06b1c1b34bfe4e9ca23c3501ee7ff783627d589f99110768cb54` |

The bounded exported GPU observer passed15 captures: actual recorded flight, selected first-sample height, synthetic gaps/unavailable fuel, synthetic sealed limit and default-Cancel discard at960x540,1920x1080 and2560x1440. Each viewport uses75 actual simulated seconds,9,000 native ticks and151 observations. Gap/limit examples are conspicuously labeled synthetic display fixtures, kept separate from the actual recorder. Declared payload hashes are unchanged before/after observation; workers/audio join and exit succeeds. Root checked all image dimensions/hashes and visually inspected representative views. Independent final review approved all15 images,193 exact payload files,105 source bindings,114 PCK integrity entries, actual module/CRT identity and corresponding-source archive (receipt SHA256 `0c731681c599a1f3f0cfece69913e73262b9e0bc4e41fbab5726ba7ab6755c8a`). Generated observer images/receipt live under separate evidence; strict payload inventory remains unchanged.

This is scripted engineering evidence, not a human flight, device, sensed-instrument, C172 or phase acceptance. The existing owner game is preserved. [PR135](https://github.com/brettbergin/flight-simulator/pull/135) merged the exact reviewed source after all four protected checks passed: [native Windows/Linux](https://github.com/brettbergin/flight-simulator/actions/runs/37201996693) and [documentation Windows/Linux](https://github.com/brettbergin/flight-simulator/actions/runs/37201996672). Accepted main is `8bba7c7412154337cd9c566b05e5addc6eb479c9`; issue134 closed. The separate documentation follow-up records these receipts without changing the frozen runtime. Aggregate requirements and phase gates remain open.
