# Whole-flight engineering preview

Date: 2026-10-03. Issue [#98](https://github.com/brettbergin/flight-simulator/issues/98).
Build and controls: [Windows runner](../../../tools/interactive-preview/README.md).
The prerequisite model and ownership contract landed in
[ADR-006](../../decisions/006-interactive-prototype.md) before its consumers.

## Result and scope

One JSBSim executive owns flight forces, wheel contacts, steering and braking.
The same original aircraft can start ground-ready, take off, fly, touch down
and stop on the prepared synthetic plane. The Godot player adds human keyboard
controls, chase and generic forward cameras, native contact/force indications,
pause and fresh ground/airborne attempts. The engine is already running.
Human mode has no scripted feedback controller or renderer-owned physics.

This is an original engineering model, not a C172S or a qualified training
device. It does not model startup procedures, a full cockpit, real terrain or
airports, calibrated performance, human handling evaluation, achievements or
the production save/load experience. Earth-relative speed is not IAS; height
is WGS ellipsoid height and clearance is relative to the prepared plane.
P1, renderer acceptance and later aircraft/pilot evidence gates remain open.

## Actual native and Windows evidence

The final native module passed pinned Windows CTest (8/8), 9,807 assertions
(many cover queue capacities), two Node evidence tests, 10,410 strict v1
records and an exact same-build repeat. Rejection evidence covers authority,
malformed contacts/brakes, changed model bytes, coverage, provider identity,
thread ownership and terminal faults. The tested source fingerprint is
`35cf7b603d99b9accb123405f7569a901ed9e28d32110acbc296b376facd6416`.

The explicitly automated pilot-API loop took off at tick 3,755, touched down
at 7,182 and stopped at 8,916 (74.3 seconds), with all three wheels loaded and
speed 0.094998 m/s. Maximum clearance was 32.7513 m. This exercises the combined
loop; it does not prove an unassisted human landing or realistic handling.

The final committed player passed editor and exported Windows loop checks.
Their records matched exactly apart from deliberately fresh session IDs.
Actual loaded paths/hashes for seven native/runtime modules, direct and delay
PE imports, five app-local CRT libraries, model pins, source and notices were
audited. A separately rebuilt corresponding-source JSBSim DLL was substituted
and the whole loop rerun from a Unicode path. Historical editor and portable
121-tick `FlightProofSession` checks also passed with the new bridge.

| Final reference-PC package component | SHA-256 |
|---|---|
| `preview.gd` | `84b7863903470e1939f1aa26c46ba0d2d45c9a7e3295959e518117ee445428e4` |
| Exported PCK | `b8341f0e696e6d0472839260361ed4afa88d1f2ef7b41ddfc01d960eb343a148` |
| Native bridge | `9ef8f97a41596f6bd3b94ec11d5e242833fd0a32568fddda954b1dc0b82b738d` |
| Package manifest | `bffe2119e306eadb57cff79b138826c01499e5c29d48e6f35cb62f1eb11bd408` |
| Prepared world identity | `04bff5a0bcf3509990f6276b2548a28268f57fc96d218a7ca51cab1990ec1ff5` |

## Actual reference-PC graphics diagnostic

The coordinator ran the final package's bounded `-VisualSmoke` on the RTX3090,
Godot 4.7.2/OpenGL 3.3, 1280×720. It exited zero, reported no errors or object
leaks, and recorded joined shutdown. Four actual viewport PNGs were inspected:
fresh ground, fresh airborne, controlled/banked and paused, and fresh ground
reset. The receipt passed 120 controlled native ticks, pause/resume and fresh
joined attempts, and bound the source/world identities above. The HUD and
runway were readable. These four captures use chase view; forward view has
source review but no separate graphics capture in this diagnostic.

## Reproduction and remaining evidence

The Windows runner stages a fresh project and payload, checks pinned tools,
executes editor/exported checks and the replacement loop, and saves exact
receipts. CI runs the native repeat/v1 boundary evidence on both platforms
and the player/package proof on Windows. GPU diagnostics remain local and
separate from headless CI and the deferred performance benchmark.

The worker owns construction, all native operations and destruction; closure
joins it. The player advances fixed 120 Hz ticks in batches of 1–32 and retains
bounded wall-clock debt. A wall stall freezes visibly and requires a fresh
attempt. Missing coverage blocks before mutation; unexpected provider faults
stop publication terminally. These guards are engineering domain limits,
not a certified aircraft envelope or a continuous collision guarantee.
