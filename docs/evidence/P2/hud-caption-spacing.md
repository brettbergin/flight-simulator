# CHASE HUD caption spacing

Status: implementation and qualification in progress for [issue184](https://github.com/brettbergin/flight-simulator/issues/184). This record covers a bounded HUD drawing defect under PRD-015 and UX-009; it does not complete their broader requirements.

## Accepted baseline and defect

[Ordinary-flight layout](ordinary-flight-layout.md) was accepted through runtime [PR182](https://github.com/brettbergin/flight-simulator/pull/182) and evidence [PR183](https://github.com/brettbergin/flight-simulator/pull/183). Its accepted FlightPanel source is 43,976 bytes, SHA256 `308cff4a7401b07b4bda045a242f41e99527cfdc3d38b91e58f39617d0c35045`. The independently reviewed portable baseline receipt is `e57e4935d71c7a47292e270807a9827ecec1d2de9340eac0b33389c22887dbf8`.

The baseline CHASE HUD places the first-row unit/source captions underneath the next instrument row at 1920x1080 and 2560x1440. Original legacy images are respectively `5a76d2b5f8ef45627e2b65a3014de3dee6e328e047d4d76eb583f6eccffbf631` and `3f11e7e22980344d45798982fd15c5d96b0995faa8785657cdacb394481a1079`. These are defect evidence, not passing caption qualification.

## Scope and evidence to retain

The repair reserves measured title and unit bands below each nonphysical HUD dial and its shadow. It preserves all six complete titles/qualifiers, native readings, formatting, physical captions, camera choices and requested visibility. Headless checks must measure actual integer font sizes, shaped glyph extents and production drawing calls, with an actual accepted-source failing example. They include compact/classic transition and height-cap/radius boundaries, unavailable/retained/default/large values and hidden HUD behavior.

The separate Windows observer requests twelve original images per delivery context: both profiles in CHASE with HUD at 960x540, 1920x1080 and 2560x1440; both profiles in cockpit/panel modes at 960x540 with HUD hidden; and both profiles in CHASE at 960x540 with HUD explicitly hidden. It retains complete binary truth before/after each draw, passive-view authority comparisons, glyph metadata, source identities and native/audio joins. Editor, portable and corresponding-source replacement delivery require their own source/PCK/module bindings, preservation checks and independent original-image review.

## Development results

The same focused test (`5237442350c24415e3b74d211ba40b14b6a5f258402b08197f0c39b6f9fdd8fa`) ran 18,943 checks against both source versions. The accepted baseline failed 2,701 assertions, including actual captured first-row unit glyphs crossing the second-row ring/shadow at both larger sizes. The corrected panel (`e3970a311401aebae5ca313e628c7d9bf493ea98bec8d6bccb41c6e26edad218`) passed all checks. Root independently repeated this comparison in fresh projects with the pinned headless engine. Sixteen dimensions and five copied presentation states exercise actual production text calls and shaped font bounds. Digital samples are representative strings, not exhaustive proof of every possible value or radius-dependent subtitle.

The first development Windows Compatibility run passed 245 checks and captured twelve originals with 24 complete binary truth files and clean native/audio joins. Independent review (`b33a6e2702c6f28c1dc2b817d86872778ca03432098b2a2ac1e2d508bda401e7`) passed 2,594 offline checks and inspected all twelve originals; the two largest views also received native, unresampled HUD crop inspection. All complete captions are clear, requested HUD-off remains off, and all four physical-view PNGs match their accepted baseline byte for byte. This uses uncommitted staged source over an identified existing native build; it is not a qualified portable package.

The first complete integrated facade attempt ran 62,612 checks, including the passing 18,943 HUD checks, but failed the existing archive-file junction creation/cleanup checks under restricted Windows permissions. Its raw log, process record and observed receipt are preserved. A fresh authorized retry is pending; no runtime source change is inferred from that environment failure. Current CI and fresh three-context delivery also remain pending. Package guard tests passed 14/14 after the actual junction negatives received their required permission, and the complete PowerShell staging suite passed using the pinned Python. Its sixteen HUD-result negative cases reject missing, skipped, failed and malformed evidence; all previous first-flight resources remain bound in the fifteen-file/eight-group roster.

Historical failed attempts remain available with their actual scope, including corrected test-only formatter expectations and environment permission/interpreter failures. Physical auxiliary-panel visibility under the locator and [deliberate-gaze design #179](https://github.com/brettbergin/flight-simulator/issues/179) remain separate work; hardware, sensed instruments, C172 calibration, pilot review and phase acceptance remain open.
