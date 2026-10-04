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

These are development source checks. Exact final source, portable/replacement package, bounded exported viewport and protected CI evidence remain pending; this document does not assert those gates have passed.
