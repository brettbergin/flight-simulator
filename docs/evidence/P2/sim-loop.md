# Reusable flight-loop and scene-origin integration

Date: 2026-10-03. Implementation issue [#20](https://github.com/brettbergin/flight-simulator/issues/20), consuming [ADR007](../../decisions/007-sim-loop-facade.md) accepted through #112/PR113. This is original prototype integration evidence and a review candidate. The P1 aggregate owner review, P2 pilot exercise, aircraft-source rights and C172 calibration remain separate gates.

## Result and ownership

The [facade](../../../app/simulation/session_facade.gd) owns one existing synchronous native worker and executive. Its [playable controller](../../../app/simulation/flight_scene.gd) reuses the original cockpit, map, sound and scenery. The original preview remains separately runnable with its historical proof flags. Ordinary interactive flight now routes controls, clock, pause, reset and shutdown through the facade. Scene geometry never writes aircraft state.

Wire identities remain checked canonical decimal uint64 strings. Wall pacing uses checked signed integer arithmetic with 4,000,000 quanta per 120 Hz native tick and exact multipliers for 0.25/0.5/1/2/4 speed. Fractional debt survives ordinary pause and scale changes. The caller settles the preceding interval before changing speed. F5/F6 and the pause-menu button select speed; existing bracket trim controls remain separate. Unsupported overload retains exact representable debt, visibly pauses and requires reset. Unrepresentable accrual retains the prior debt.

Complete pilot intent coalesces locally; only a changed sample at the next due boundary receives the next actual tick and source sequence. Accepted command and lifecycle ledgers validate actual returned records, reject duplicates, reordered, unadmitted or missing due observations, and deliver them once. Acknowledgement is distinguished from native observation. Paused lifecycle draining uses the actual zero-completion step reply; draining does not free the native session's total event-history capacity.

[Wire validation](../../../app/simulation/wire_validation.gd) checks closed v1 shapes, nested finite ranges, bounded IDs/arrays, quaternion/ECEF/time consistency and duplicate contact/system IDs before publishing copied truth. Native JSON numbers decode as Godot floats, while acknowledgement dictionaries can contain integer metadata. Semantic comparisons preserve exact string identities. Only comparisons across native dictionary versus decoded JSON binary64 values have a bounded eight-machine-epsilon codec allowance; this does not relax native trace equivalence, ordering, physics tolerances or local pilot-intent coalescing.

## Canonical presentation and scene transactions

[Canonical geometry](../../../app/simulation/canonical_frames.gd) retains ECEF and fixed-anchor rotations as binary64 scalar arrays. Body-to-current-NED attitudes convert to the same prepared-anchor EUS frame before shortest-arc interpolation. Origin subtraction and fixed-anchor rotation precede float Vector3 construction. Adjacent live presentation has the nominal 8.333 ms delay; pause shows the actual endpoint. Instruments and maps use raw native state independently.

The [origin registry](../../../app/simulation/render_origin.gd) binds to one session and declares all seven categories. Ownship, cockpit, camera, world and light roots are nonoverlapping siblings. Current mono audio and absent particles are explicit absent categories. [Participants](../../../app/simulation/origin_participant.gd) prepare owned transforms from canonical positions; every commit completes before the new origin version is published. The ground shader retains its prepared-anchor vertex coordinates.

The controller attempts adoption at 1800 m; presentation refuses positions beyond 2000 m. A pure preparation rejection pauses visibly until a later successful adoption or reset. Commit failure invalidates presentation, hides all scene geometry, pauses/drains when possible, closes and requires joined confirmation. The same terminal handling applies when already paused. Camera clearance uses the canonical prepared plane transformed into the new origin, including vertical origin moves. Raw maps, native provider/hash and contact authority remain unchanged.

Reset joins the prior worker before fresh allocation, recreates session-bound registry/participant data and returns to origin version 1 after complete initial adoption. An unconfirmed join rejects input and further allocation.

## Verification and independent references

The [focused test directory](../../../tests/integration/sim_loop/README.md) contains an independent Python Fraction/Decimal reference authored before the consumer, actual-native tests and labeled fault adapters. Supplied analytic doubles and expected float32 values use explicit test-only IEEE754 encodings so decimal parser rounding cannot change the reference input. No physics coefficients or tolerances were fitted to consumer results.

The actual driver covers 25 cadence/scale combinations: 30/60/144/240 Hz and irregular rendering at all five speeds, with identical declared tick cuts and four nonzero pilot commands. It compares actual aircraft/weather, held axes and wire records at common native ticks, reaches tick120 with zero debt, and compares pause/resume events within each speed. Fresh session IDs are the only normalized identity. Independently polled live keyboard samples are outside exact-input equivalence.

Additional active checks exercise full-range identity boundaries, copies and invalid arguments, reachable overload/overflow, paused draining, close/reset/join, partial-prefix and malformed/duplicate/missing observation packets. Synthetic reply mutants supplement actual native prefixes; they do not masquerade as aircraft/provider faults.

Separate actual Godot checks exercise registry capacity, ancestry, session/version plans, reentrance and failure behavior, twenty synthetic 2.1 km rebases, scene attachment/reset and horizontal/vertical origin changes. Declared near-cockpit projection and relative spatial-audio transform budgets remain 0.5 pixel and 1 mm; the audio fixture is geometry evidence, not audible continuity.

The combined staged harness explicitly compiles scripts/scenes and executes actual facade, registry, participant, wire and scene checks with active functions in exported release builds. Recursive staging binds source sets/hashes and corresponding source, rejects missing resources and drift, and treats generated import UID metadata separately. CI uses headless offline tests on Windows/Linux. Exact exported payload/module/license closure, short actual-controller viewport review and all four protected checks are required before merge; development checks alone are insufficient.

## Limits and next work

The native executive, 120 Hz, prepared flat world, model/source fingerprints and v1 records are unchanged. This remains the original turbine/direct-thruster engineering prototype with an already-running engine, cosmetic high-wing aircraft and synthetic airfield. No piston/prop, C172 systems/handling, sensor, terrain-streaming, durable save/profile, training-credit or pilot acceptance is established.

This seam supports #21 input remapping/calibration, #22 synthetic airfield integration and #24 instruments. Those tasks retain their own contracts, sources and evidence. Proxy renderer metrics and short viewport checks do not certify full-game performance, OS-present pacing, input latency or hardware flight-control qualification.
