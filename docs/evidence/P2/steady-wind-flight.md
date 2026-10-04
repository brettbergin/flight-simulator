# Selectable synthetic steady wind

Status: implementation accepted through [PR144](https://github.com/brettbergin/flight-simulator/pull/144), squash-merged as `cb11518ad8056c15930e880bb60c5b0ffc4c27bf` on 2026-10-04. [Issue142](https://github.com/brettbergin/flight-simulator/issues/142) closed after the merge. The reviewed source head was `1cb47d63187c965c89de4425b22593ac1f58ed4a`. P1/P2, C172, hardware and pilot acceptance remain open.

## Scope and use

The paused Wind panel offers four exact fresh-start selections: `calm`, `from-north`, `from-west`, and `from-east`. The three windy selections are 5 m/s in the accepted original airfield NED frame, with dry ISA, seed 42 and zero turbulence. Current conditions come from qualified actual native truth; a menu draft does not change them. Ordinary Restart retains the accepted profile. Explicit ground/airborne starts use the draft and preserve the existing default-Cancel confirmation when replacing an advanced recording.

The compact cue reports FROM and degrees true, the north-up map reports TO, and the cosmetic windsock follows downstream flow. Calm has no horizontal bearing. Invalid/unavailable truth has no invented calm value; retained truth is labelled historical and suppresses the physical windsock. Saved reviews retain neither wind setup nor a recipe to resume physics. Public flight wire, Result/Readback and ADR011/012 formats remain unchanged.

## Contract and independent references

[ADR013](../../decisions/013-steady-wind-starts.md) was accepted through [PR141](https://github.com/brettbergin/flight-simulator/pull/141). Its accepted Git-LF SHA256 is `64548f1c876f77d635bd116710fcd5ca44d27e436b8b6b105d0c66406ea20e8f`. The separate [ratification record](../../../tests/world/wind/ratification-v1.json) binds the reference packet before new backend or consumer observations. The original preparation metadata is preserved.

The independent Python generator uses exact rational arithmetic and high precision rotation references. Its 22 cases and 8 runway interpretations include signed body-frame wind subtraction, nonzero rotations, calm, tiny positive winds and binary64 underflow boundaries. Expected bytes are `7d71cbb4f8d9ad12fe91501d5e020f14bbf02516d363512e69b6fa41320856c3`; generator bytes are `6a66257c468846caab502e1b7681c16ad00a09e5380d95266c082ab0ff5c263c`. [Reference guidance](../../../tests/world/wind/reference/README.md) separates the tight pure arithmetic criteria from the predeclared native nominal wind criterion of 1e-6 m/s per component. No observed backend output becomes a golden.

## Accepted engineering checks

The native producer sets wind only in fresh initialization, observes actual RunIC and trim results, and checks observed total/base wind, zero gust/turbulence and body relative airflow before accepting publication. Original model/XML, prepared world and calm regressions are retained. Failed publication follows the existing last-valid terminal fault contract.

A separate `steady-wind-native-v1` build passed both CTest targets with 85,568 assertions. Actual Godot binding checks passed 504 assertions including both named starts for all profiles, two/three-argument admission and wrong-type/thread rejection. The accepted new native fingerprint is `5fd66c2a861fe0556e077a37f556f3273f584eac26081ffe641a6e0525d1a218`; prior accepted native builds are preserved.

The latest isolated focused run passed 30,606 facade and 126 scene assertions, in addition to the 504 binding assertions, with empty stderr. It checks all eight starts, accepted versus draft separation, reset/restart, invalid selection, default-Cancel, failed replacement cleanup, rejection before replacement admission, and native/map/windsock agreement. A rejected unpaused replacement preserves the old live worker and recording. Failed admitted setup joins its new worker and leaves the old recording closed; its unadopted weather cannot look current.

The final fresh package passed editor, portable Windows player and separately rebuilt/replaced JSBSim DLL checks. Each context passed 504 wind binding, 801 pure cue and 126 wind scene assertions, together with the existing flight/facade checks. Unchanged recorded-review codec, file and scene checks passed 1,560,616, 516,878 and 49 assertions respectively. Editor, portable and replacement traces matched within the existing comparison budgets. These are engineering checks, not real crosswind handling or pilot evaluation.

## Exported visual review and correction

The first export at source `58522eb5a9396da60db4f15ec5e7bb35105cc5e9` passed editor, portable and separately rebuilt-DLL integration, including unchanged archive codec/file/scene checks. Its 39 exported views passed 215 automated assertions, but independent image review rejected two visual defects: Back was clipped by the scroll viewport at 960x540, and the wind label lost contrast over white runway paint. Passing automation did not establish visual acceptance; those artifacts and findings are retained unchanged.

The corrected panel reduces spacing so its controls fit at the minimum size; the native wind cue has a dark backing. The visual observer now checks ScrollContainer ancestor containment as well as viewport bounds. The final exported Windows player passed 230 assertions across 39 captured views at 960x540, 1920x1080 and 2560x1440. Independent review approved the exact source and all 39 images, including the minimum-size Back control and wind label over runway paint.

The actual final player used OpenGL Compatibility, OpenGL 3.3, NVIDIA driver 591.86 and the reference RTX3090. This evidence does not establish the planned Forward+ renderer or its performance gate. The captures cover all four profiles, current/paused/map/windsock views, chooser/default-Cancel, saved-review warning, retained historical truth and a visibly labelled invalid fixture. Display-only captures preserve native state, recording and controls; the scripted replacement scenario uses three actual native ticks per size. Retained historical truth hides the physical windsock.

## Final artifact and review bindings

The accepted local package is the immutable `run-2f58e6213b524d7bb408ee13dd7b4cc9` proof run. Its manifest covers 265 payload entries, four wind groups, seven loaded modules and seven component inventories. Full corresponding-source, license, PE/runtime and separately rebuilt DLL replacement checks passed. Captures and private review receipts are retained outside the payload; no personal pilot profiles or human flight logs were uploaded. CI retains synthetic engineering proof traces separately.

| Artifact | SHA256 |
|---|---|
| Payload manifest | `165a217bca9badd32a27e3cab9bc2ab622308e7235a18bc1cef8f895c2db2990` |
| Player PCK | `ba1095f3d9b185160841e9767049ef4ce53941b2207493c22fb4a7723f3c987f` |
| Player executable | `d34d36f3be1a6c49c56525ae86469b92e4f417ddf0b43cf00dd80c385c4b0562` |
| Capture binding | `aab277bfb6640973326ba3de4a927de48c0e687feccf19229726fb4097e0c667` |
| Visual receipt | `5e11caba1e5eb3bcb25e0a889c03850e01c8e10e409b46ca9b9613c07c3b560b` |
| Independent final review | `9fc7c9fafbfe216c92f659aaff90ec16ca32aeb9c36067d61e7fbc5e56235681` |

The independently reviewed source hashes, package/module inventories and 41 capture files were rehashed before acceptance. Prior failed exports, their receipts and source identities remain unchanged; they are not relabelled as this accepted run.

All four required checks passed on the exact reviewed head before merge: [Foundation CI](https://github.com/brettbergin/flight-simulator/actions/runs/37220135765) for documentation on Ubuntu and Windows, and [Native CI](https://github.com/brettbergin/flight-simulator/actions/runs/37220135818) for native/runtime/package checks on both platforms. The Windows native job completed successfully at 2026-10-04T17:50:37Z. This follow-up records acceptance facts without changing the previously reviewed source or package.

## Remaining limits

This is an original engineering prototype, not a validated C172S model. The preset strength is not an aircraft crosswind limit. Gusts, turbulence, live/real weather, pressure instruments, airport operational sources, durable pilot profiles and training credit are separate backlog requirements. Rendering and the direction-only windsock have no physics or collision authority. Phase gates and pilot evaluation remain open.
