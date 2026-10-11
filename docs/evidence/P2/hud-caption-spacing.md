# CHASE HUD caption spacing

Status: source and delivery qualification accepted; final evidence acceptance pending for [issue184](https://github.com/brettbergin/flight-simulator/issues/184). This record covers a bounded HUD drawing defect under PRD-015 and UX-009; it does not complete their broader requirements.

## Accepted baseline and defect

[Ordinary-flight layout](ordinary-flight-layout.md) was accepted through runtime [PR182](https://github.com/brettbergin/flight-simulator/pull/182) and evidence [PR183](https://github.com/brettbergin/flight-simulator/pull/183). Its accepted FlightPanel source is 43,976 bytes, SHA256 `308cff4a7401b07b4bda045a242f41e99527cfdc3d38b91e58f39617d0c35045`. The independently reviewed portable baseline receipt is `e57e4935d71c7a47292e270807a9827ecec1d2de9340eac0b33389c22887dbf8`.

The baseline CHASE HUD places the first-row unit/source captions underneath the next instrument row at 1920x1080 and 2560x1440. Original legacy images are respectively `5a76d2b5f8ef45627e2b65a3014de3dee6e328e047d4d76eb583f6eccffbf631` and `3f11e7e22980344d45798982fd15c5d96b0995faa8785657cdacb394481a1079`. These are defect evidence, not passing caption qualification.

## Scope and evidence to retain

The repair reserves measured title and unit bands below each nonphysical HUD dial and its shadow. It preserves all six complete titles/qualifiers, native readings, formatting, physical captions, camera choices and requested visibility. Headless checks must measure actual integer font sizes, shaped glyph extents and production drawing calls, with an actual accepted-source failing example. They include compact/classic transition and height-cap/radius boundaries, unavailable/retained/default/large values and hidden HUD behavior.

The separate Windows observer requests twelve original images per delivery context: both profiles in CHASE with HUD at 960x540, 1920x1080 and 2560x1440; both profiles in cockpit/panel modes at 960x540 with HUD hidden; and both profiles in CHASE at 960x540 with HUD explicitly hidden. It retains complete binary truth before/after each draw, passive-view authority comparisons, glyph metadata, source identities and native/audio joins. Editor, portable and corresponding-source replacement delivery require their own source/PCK/module bindings, preservation checks and independent original-image review.

## Development results

The same focused test (`5237442350c24415e3b74d211ba40b14b6a5f258402b08197f0c39b6f9fdd8fa`) ran 18,943 checks against both source versions. The accepted baseline failed 2,701 assertions, including actual captured first-row unit glyphs crossing the second-row ring/shadow at both larger sizes. The corrected panel (`e3970a311401aebae5ca313e628c7d9bf493ea98bec8d6bccb41c6e26edad218`) passed all checks. Root independently repeated this comparison in fresh projects with the pinned headless engine. Sixteen dimensions and five copied presentation states exercise actual production text calls and shaped font bounds. Digital samples are representative strings, not exhaustive proof of every possible value or radius-dependent subtitle.

The first development Windows Compatibility run passed 245 checks and captured twelve originals with 24 complete binary truth files and clean native/audio joins. Independent review (`b33a6e2702c6f28c1dc2b817d86872778ca03432098b2a2ac1e2d508bda401e7`) passed 2,594 offline checks and inspected all twelve originals; the two largest views also received native, unresampled HUD crop inspection. All complete captions are clear, requested HUD-off remains off, and all four physical-view PNGs match their accepted baseline byte for byte. This uses uncommitted staged source over an identified existing native build; it is not a qualified portable package.

The first complete integrated facade attempt ran 62,612 checks, including the passing 18,943 HUD checks, but failed the existing archive-file junction creation/cleanup checks under restricted Windows permissions. Its raw log, process record and observed receipt are preserved. A fresh authorized development retry passed all 62,612 checks, including 18,943 HUD and 4,277 first-flight checks, without a runtime change. Fresh three-context delivery subsequently passed as recorded below. Package guard tests passed 14/14 after the actual junction negatives received their required permission, and the complete PowerShell staging suite passed using the pinned Python. Its sixteen HUD-result negative cases reject missing, skipped, failed and malformed evidence; all previous first-flight resources remain bound in the fifteen-file/eight-group roster.

Historical failed attempts remain available with their actual scope, including corrected test-only formatter expectations and environment permission/interpreter failures. Physical auxiliary-panel visibility under the locator and [deliberate-gaze design #179](https://github.com/brettbergin/flight-simulator/issues/179) remain separate work; hardware, sensed instruments, C172 calibration, pilot review and phase acceptance remain open.

## Qualified Windows delivery

The fresh package completed successfully at source head `67aa37e861e0f1651a5a8b54198aa9719a580f35`. Its final manifest is SHA256 `5a73ea257398052398402f936d112bc1aa425bd7bc86ca1e39f738e84446ef52`: 485 shipping files and 214 authoring files. The immediately frozen context witness is `321155e52a5bccdc7444c25a16ee0786e2000c96ba3bc68aa4045fd032aa1af8`. Editor contains 327 files; the corresponding-source rebuilt-library target contains 468. That replacement differs in four common files and lacks seventeen final distribution metadata files, so it is not a second 485-file distribution.

Each editor, portable and rebuilt-library facade passed 62,612 checks: HUD 18,943 and first-flight 4,277 included. Each also passed pointer 120,476, original cold-engine 15,957 and ground-material 371 checks. Automated smoke completed takeoff, touchdown and stop with joined native/audio resources. Independent offline package review `b1fce2c084e00625527ec88528efb3aaad30c3493afae5fbd68b05671835d30e` passed 84,480 checks. It bound the actual source, 174-entry packed resources, corresponding sources, modules/models/notices and exact frozen inventories; 460 shipping files were byte-identical to accepted #178, with 23 expected changed files and two additions. This confirms the bounded delivery, not aircraft handling or pilot acceptance.

## Qualified image review

The actual Windows Compatibility observer passed 245 checks per context, each with twelve PNGs, 24 complete binary truth files and clean native/audio joins. All three target inventories and the manifest remained unchanged. Receipt hashes:

| Context | HUD receipt SHA256 |
|---|---|
| Editor | `468ebe5a4968a33cb1c7fcc5f8d0e749dcf4e33cb751cb78527d215a53e7e258` |
| Portable | `cd8e2a39fb855de6f2e1b236b70c50c375732cad5170357eb17e2ce1e9aba2f9` |
| Rebuilt library | `a9f9cef35eca2b8e03171651fe59a8d52f390443fce1f4e1e87cae712c806cd8` |

Independent review `e6af367286d5f6082a4111a98ab9b9eae6fcc34d657386e1c54dccd730766615` passed 9,498 offline checks. All 36 complete qualified PNGs exactly match the twelve previously individually inspected development originals, with explicit per-file/context/hash mappings. The review therefore reuses those identical reviewed pixels, including the native unresampled largest-window HUD crops; it does not claim 36 separately opened originals. All 29 source bindings, packed resources, 72 truth hashes/36 complete binary pairs, glyph metadata, requested visibility, passive-state checks and joins passed. Four physical-view originals remain byte-identical to accepted #178. Unavailable/retained states and intermediate dimensions remain the focused test's scope rather than additional captured windows.

## Preserved failure and remaining limits

The first package attempt failed three existing preset-file replacement assertions after successful initial creation. The valid original and verified replacement temporary bytes were preserved, and its intentional Windows share-lock negative passed. Independent failure review `27ecc50921308d624a171bedfff0c0060c1afc8a48d1f04b831401f40b686bf3` found no deterministic source difference from the passing development run. Eight fresh trials of actual production save/replace and the unchanged fresh complete three-context package passed. The existing helper discarded the underlying Windows exception; its original cause remains unresolved. Do not infer an antivirus, timing or lock diagnosis from the later passes. No test or runtime source was weakened for the retry.

Source [PR185](https://github.com/brettbergin/flight-simulator/pull/185) merged as `6960085db0c581c5a390016c5b0a524f3a1190c2` after all eight hosted checks passed at qualified source head `67aa37e861e0f1651a5a8b54198aa9719a580f35`. The accepted main tree is byte-identical to that qualified source tree; the squash merge changes commit identity rather than qualified file content. Final evidence acceptance is separate. The drawing repair does not advance the C172 configuration, sensors, hardware/pilot, deliberate-gaze, all-window, audio or phase gates. The auxiliary-panel locator limitation and #179 remain open.
