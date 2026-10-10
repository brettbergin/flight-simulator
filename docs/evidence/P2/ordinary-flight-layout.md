# Ordinary flight layout implementation evidence

Status: **runtime merged; bounded delivery and presentation evidence independently reviewed**. [Issue178](https://github.com/brettbergin/flight-simulator/issues/178) consumes [ADR019](../../decisions/019-ordinary-flight-overlay-layout.md), accepted through [PR180](https://github.com/brettbergin/flight-simulator/pull/180) and its locator/tooltip clarification [PR181](https://github.com/brettbergin/flight-simulator/pull/181). Runtime commit `aea449d9430fc361536d48caea435f44467b4777` merged through [PR182](https://github.com/brettbergin/flight-simulator/pull/182) as `d964340d20c76141d511d44f9bf1d8b65d65eb9e` after all eight current-head hosted checks passed. Automated delivery, independent source/package review and original exported-image review are separate evidence gates.

## Resulting presentation

Scene owns fixed responsive side columns, independent of gaze. Expanded cold-engine controls use 216px for all six commands, with actual/request/preview distinctions, denied reasons and mouse-look release guidance. Current 220px and noncurrent 188px locators preserve complete target, range/bearing, source qualification and manual-leg information. Closing the map restores the manual card in the same allocated slot. Only secondary itinerary and binding aliases may shorten; full standard tooltips remain available. Help-off, hidden-HUD and explicitly collapsed-engine choices retain the separate release affordance without forcing visibility.

Existing native header and ground-speed/throttle/brake strips remain unchanged. Copied piston feedback receives bounds and wraps complete existing source strings. The unavailable circuit reference uses a 32px wide notice where permitted; available schematic geometry and all five leg labels remain unchanged. Native physics, aircraft definitions, camera/FOV, requested visibility, route selection, map geography, controls and save schemas are unchanged.

Actual captured-target geometry changes retire capture once before moving the targets. Ordinary full released Raw input is still required before rearm; layout does not manufacture release or submit a starter pulse. Passive layout is checked against complete serialized native/facade/mapper/recording/origin state and an observed native-call ledger.

Tooltip Labels use standard nonconsuming PASS hover. Actual root-window tests require motion/press/release to reach an unhandled-input witness; STOP negative Controls must block it. The final viewport handled flag is deliberately not the oracle: Godot physics picking can mark an event handled after that witness.

Closed/missing-host presentation clears stale readings and geometry synchronously. A development failure exposed hidden route-card Labels measuring at one-pixel width and expanding the footer from 575 to 1204px. The fix gives the same five rows their actual dock width and combined minimum heights before measuring the card. Genuine oversized text remains oversized. New regression tests fail 16 assertions on the old source and pass on the correction; the original 189 Board assertions remain intact.

## Development checks, 2026-10-10

Fresh Windows staging used pinned Godot 4.7.2 and the qualified coupled native build, with isolated process profiles. All six focused groups passed 4,277 assertions and joined native/audio ownership cleanly:

| Group | Assertions |
|---|---:|
| Original briefing | 18 |
| Copied bindings | 116 |
| Frozen geographic reference | 297 |
| Circuit card and actual glyph fit | 2,129 |
| Locator geography, summary and text | 313 |
| Actual Scene lifecycle, layout, Raw and tooltips | 1,404 |

The combined pointer suite passed 120,476 assertions, including 18 active-capture resize/view transitions at three sizes and all three protected modes. Separate suites passed 250 Board and 61 copied-feedback checks. The exact 14-file/eight-group staging roster and package verifier bind the additional observer without dropping the original 39/27 observer. All 14 Node package-verifier tests passed, including every-tree changed/missing resource negatives; Windows junction cases required filesystem access outside the restricted sandbox. These counts describe separate suites and are not a deduplicated total.

The opt-in development GPU observer passed 411 checks across 29 original PNGs and 58 full binary truth files. Every before/after truth pair is byte-identical. The matrix contains 18 current paused tick0 views (two profiles, 960x540/1920x1080/2560x1440, modes 0/3/1), nine minimum-window cold views covering collapsed release/map-closed manual card/unavailable circuit, and two actual joined-worker empty-source views. It performs no Resume or Run. Receipt SHA256: `07cb6ccea3d531c58ce64f4f4b7a1b876cd1c2b75ff2732063ca5ac614009ca4`, under `.local/ordinary-layout-development-visual/run-44bbbe37e00e45ce9f35ff48a48c13bd/captures`.

Independent review checked all 27 captured resource bindings, every original artifact/hash, dimensions and full truth pair, and inspected all 29 original views. Ten originals were reused only after complete PNG byte equality with previously inspected originals; nineteen were opened separately. Review SHA256: `43e414bedcf3c6c8e46931572b26ba27f75f9dc6bde08cfe4851a8ee93ba8a31`. Root separately inspected minimum-window expanded cold controls, feedback, primary instruments and unavailable circuit composition. Six primary faces/numeric readings and native top strips are clear in the observed default views. This is bounded presentation evidence, not flight performance, physical input or aircraft fidelity.

The packaged check harness accepts `-- --facade-checks --ordinary-flight-layout-output=<fresh absolute external directory>` for this separate 29-view diagnostic. Use an isolated process profile and a watchdog; it creates disposable paused flights and joins their workers. The ordinary headless/package checks remain mandatory. The original `--first-flight-visual-output` and `--first-flight-interaction-output` paths retain their existing 39/27 observers.

## Delivery and remaining limits

The fresh automated package run `.local/interactive-preview/run-d222b45003e341bf857e381c648b8c8d` completed with exit0 for runtime commit `aea449d9430fc361536d48caea435f44467b4777`. Its manifest SHA256 is `d3f61421cc3d91814e6f273d84fdeb6097ecb835f5a802bac64eea1f6e14c9d1`; it inventories 483 payload files, 212 authoring sources and the 14 first-flight files in eight source groups. The exported PCK SHA256 is `822694538b4a8d57c007c40f98837f90de6ca01b4e2901c1e1343d708aa3b61c`.

| Actual automated context | Full facade checks | Pointer checks | First-flight subgroup checks |
|---|---:|---:|---:|
| Editor | 43,666 | 120,476 | 4,277 |
| Portable player | 43,666 | 120,476 | 4,277 |
| Player with rebuilt replacement library | 43,666 | 120,476 | 4,277 |

All listed receipts report passed with no failures. First-flight counts are included within each full facade suite; pointer counts are a separate suite. These are repeated context results, not a deduplicated total. The package verifier reports actual source/PCK/native binding, seven in-payload modules, reviewed release CRT pins, notices/model closure and corresponding-source rebuilding/replacement passed. The package-audit receipt SHA256 is `67bbe9911e0ec6c5980af821cc3b1a303ac7f7de9ea764ee30a9d311f5368f24`; replacement-evidence SHA256 is `9e525e1279088cc822646db3a8e8263d083afb671989ac9897e630efd1c5104f`. Independent final package/baseline review approved the actual source and native bindings, complete inventories and corresponding-source replacement; review SHA256: `2381b0915eba069819d4c0789209813f4c84011fa7a549242db773df42f6dc4a`. The replacement clone has 466 files: two rebuilt DLLs and two per-run output files differ from the shipping payload, and seventeen later evidence/notice files were never copied into the earlier clone. It is a qualification context, not a second distribution. The retained native smoke records actual ground movement, airborne flight, touchdown with all three wheel contacts and a bounded vehicle-speed stop; it is automated engineering evidence.

The same frozen exported payload separately completed the original 39-view and 27-view GPU observers on Windows/RTX3090:

| Exported observer | Checks / original views | Receipt SHA256 |
|---|---:|---|
| Original visual | 644 / 39 | `3f6a7c82b2d56cdce5f861404cdf9d9832163c3329a6e09983ffa6f17f46950b` |
| Original interaction | 23,144 / 27 | `eab1abdc429240ca03abfa3fccabd6c20afa8d85657dcfcbb59fd51745bb26ca` |

Both receipts report no failures and native/audio joined. Their current provenance pointers are `.local/resume/first-flight-export-visual-v2-current.json` and `.local/resume/first-flight-export-interaction-v2-current.json`, bound to the manifest above. The 39-view observer uses actual Scene choices/action dispatch, complete released synthetic Raw and manually scheduled live samples; it does not establish physical input delivery. The separate 27-view observer uses complete synthetic Raw through the actual mapper/native boundary and bounded actual takeoff/map-close/restore segments; it proves no landing, continuous-flight performance or hardware input. Independent exported artifact/interaction review approved the bounded evidence; SHA256: `ff660dd7ad56e11653522e36a3cf3df2607f6392caddff39b1b01f8cf9e98e87`. It checked all original hashes and truth pairs, and directly inspected ten visual and twelve interaction PNGs. This is representative pixel review, not inspection of every one of the 66 images. Cold interaction views remain paused with the propeller stopped; no engine-start claim is made for that observer.

The new ordinary-layout observer also completed in all three qualified contexts, each with 411 checks, 29 PNGs, 58 byte-identical paired truth files and clean native/audio joins. The independently audited frozen context inventories were checked before and after each observation; no qualified target changed. Receipt SHA256 values:

| Context | Layout receipt SHA256 |
|---|---|
| Editor | `81fa9479ff5986a094445ecff3e394751ac435d8dcbed8cd9be2aebaa6be5213` |
| Portable | `e57e4935d71c7a47292e270807a9827ecec1d2de9340eac0b33389c22887dbf8` |
| Rebuilt-library player | `a738990e8a195c4adcd8774f192511c91ed4f20226f831f0c53b8a9b824eddb3` |

These captures preserve the same bounded paused/default-view matrix and limitations as the development observer. Independent final artifact and original-image review approved this bounded matrix; SHA256: `35273207351543d9ad243a8159775193d6b6dcdf109cf89e8ce060649ab0c03b`. All 87 qualified-context PNGs are complete byte matches to the previously individually inspected development originals; the exact reuse mapping is retained. All 174 truth files, 87 byte-identical pairs, source/PCK bindings and complete context inventories were checked. This resolves current/default and joined-empty-source presentation only; retained instrument ink remains separate.

## Retained native-strip ink question

ADR019 records a conservative PANEL-cell rectangle intersecting the unchanged retained native strip at 960x540. Actual `Facade.close()` preserves historical Readback but invalidates its render pose; ordinary `Scene.show_state()` hides the physical cockpit. The joined-empty-source matrix cannot settle a physical-ink question. A private diagnostic therefore obtained actual joined CLOSED Readback, published its actual historical readings and first confirmed ordinary geometry suppression. It then restored only the previously captured paused geometry visibility, preserving all transforms/camera/source/native state, without calling `show_state()` again. This is an explicitly synthetic presentation composition, not supported stopped-cockpit behavior or a retained flight.

The separately copied exact qualified editor context passed 116 checks with two 960x540 PANEL originals, eight binary truth files and clean native/audio joins. Both full draw pairs are byte-identical. Receipt SHA256: `257b45fdc23b09e1989c6fec1818e51910c2b71bce61c6da19d7e1280570abe1`, under `.local/retained-panel-ink/editor-6228271c416e4c27aa105981524ef137/captures`. The original and copied 323-file editor contexts, pinned engine, and 483-file portable payload remained exact. No production/PCK/observer change was made.

Root and the independent reviewer each inspected both native-resolution originals. The y84..118 strip crosses blank/header pixels above the upper-right dial; all six primary faces, ticks, numeric readings and captions remain intact. This resolves the specific conservative-cell overlap in the two tested compositions, not whole-panel, all-window/gaze or exported retained-flight readability. Review SHA256: `25adf1fd02e1bdbfe643182cc4902c0f8132ed40c416a84e9f1ad89b30d5d75f`. The earlier external-script portable diagnostic timed out after 180 seconds with zero captures; its failed log is retained, and all 483 payload files were separately reverified unchanged. That attempt is not a portable pass.

The earlier sandboxed package attempt under `.local/interactive-preview/run-65ed840e38744e608371ab57dff733ff` failed saved-review junction creation/cleanup; its original failed receipt remains retained. Its pointer/ground checks and first-flight groups passed, but the whole attempt is not accepted. Earlier failed GPU and tooltip-window trials also remain failed and retain their source/artifact identities.

Some physical auxiliary values (including fuel/throttle) remain under the right dock in PANEL views. The unchanged large CHASE HUD partially occludes first-row unit captions with second-row rings; numeric readings and native strips remain clear. Neither whole physical-panel visibility nor complete large-HUD caption clearance is claimed. A separate bounded HUD correction is being prepared. [Issue179](https://github.com/brettbergin/flight-simulator/issues/179) owns deliberate-gaze/zoom exposed-face feasibility; fixed docks do not solve that case.

Independent exact-head runtime source integration review approved the eighteen-file change; SHA256: `525f093c652445f7da8a943cff37843c2f863d8622224a1af3c488fa599c034d`. Runtime source merged after all eight current-head checks passed; the separate bounded retained-strip ink review is complete. Leaf acceptance requires the checked merge of this evidence; the issue closure records that merge. Human feedback on this iteration is pending. Target C172S source/calibration, sensed instruments, real controls, pilot evaluation, training credit and broad P1/P2/P3 gates remain open.
