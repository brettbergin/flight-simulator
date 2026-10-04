# Selectable synthetic steady wind

Status: implementation under review for [issue142](https://github.com/brettbergin/flight-simulator/issues/142). Exported Windows package, GPU review and protected CI qualification are pending. P1/P2, C172, hardware and pilot acceptance remain open.

## Scope and use

The paused Wind panel offers four exact fresh-start selections: `calm`, `from-north`, `from-west`, and `from-east`. The three windy selections are 5 m/s in the accepted original airfield NED frame, with dry ISA, seed 42 and zero turbulence. Current conditions come from qualified actual native truth; a menu draft does not change them. Ordinary Restart retains the accepted profile. Explicit ground/airborne starts use the draft and preserve the existing default-Cancel confirmation when replacing an advanced recording.

The compact cue reports FROM and degrees true, the north-up map reports TO, and the cosmetic windsock follows downstream flow. Calm has no horizontal bearing. Invalid/unavailable truth has no invented calm value; retained truth is labelled historical and suppresses the physical windsock. Saved reviews retain neither wind setup nor a recipe to resume physics. Public flight wire, Result/Readback and ADR011/012 formats remain unchanged.

## Contract and independent references

[ADR013](../../decisions/013-steady-wind-starts.md) was accepted through [PR141](https://github.com/brettbergin/flight-simulator/pull/141). Its accepted Git-LF SHA256 is `64548f1c876f77d635bd116710fcd5ca44d27e436b8b6b105d0c66406ea20e8f`. The separate [ratification record](../../../tests/world/wind/ratification-v1.json) binds the reference packet before new backend or consumer observations. The original preparation metadata is preserved.

The independent Python generator uses exact rational arithmetic and high precision rotation references. Its 22 cases and 8 runway interpretations include signed body-frame wind subtraction, nonzero rotations, calm, tiny positive winds and binary64 underflow boundaries. Expected bytes are `7d71cbb4f8d9ad12fe91501d5e020f14bbf02516d363512e69b6fa41320856c3`; generator bytes are `6a66257c468846caab502e1b7681c16ad00a09e5380d95266c082ab0ff5c263c`. [Reference guidance](../../../tests/world/wind/reference/README.md) separates the tight pure arithmetic criteria from the predeclared native nominal wind criterion of 1e-6 m/s per component. No observed backend output becomes a golden.

## Engineering checks so far

The native producer sets wind only in fresh initialization, observes actual RunIC and trim results, and checks observed total/base wind, zero gust/turbulence and body relative airflow before accepting publication. Original model/XML, prepared world and calm regressions are retained. Failed publication follows the existing last-valid terminal fault contract.

A separate `steady-wind-native-v1` build passed both CTest targets with 85,568 assertions. Actual Godot binding checks passed 504 assertions including both named starts for all profiles, two/three-argument admission and wrong-type/thread rejection. The accepted new native fingerprint is `5fd66c2a861fe0556e077a37f556f3273f584eac26081ffe641a6e0525d1a218`; prior accepted native builds are preserved.

The latest isolated focused run passed 30,606 facade and 126 scene assertions, in addition to the 504 binding assertions, with empty stderr. It checks all eight starts, accepted versus draft separation, reset/restart, invalid selection, default-Cancel, failed replacement cleanup, rejection before replacement admission, and native/map/windsock agreement. A rejected unpaused replacement preserves the old live worker and recording. Failed admitted setup joins its new worker and leaves the old recording closed; its unadopted weather cannot look current.

These focused checks do not establish editor/exported/rebuilt-DLL equivalence, GPU readability, reference-PC performance, real crosswind handling or pilot evaluation. Final package closure and reviewed exported views must be recorded before this implementation issue closes.

## Remaining limits

This is an original engineering prototype, not a validated C172S model. The preset strength is not an aircraft crosswind limit. Gusts, turbulence, live/real weather, pressure instruments, airport operational sources, durable pilot profiles and training credit are separate backlog requirements. Rendering and the direction-only windsock have no physics or collision authority. Phase gates and pilot evaluation remain open.
