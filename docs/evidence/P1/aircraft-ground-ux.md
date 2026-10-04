# Aircraft glazing and rollout controls

Issue [#108](https://github.com/brettbergin/flight-simulator/issues/108), following accepted [#106 / PR107](https://github.com/brettbergin/flight-simulator/pull/107). This is a bounded correction to the original combined-model preview, not aircraft calibration or phase acceptance.

## Result and cause

The former opaque windshield and side-window quadrilaterals cut through a solid white elliptical cabin. Their corners alternated between inside and outside the loft; a small depth offset could not eliminate the visible white patches. Glazing now replaces triangles of the same continuous shell. White frame regions separate windshield and side/rear windows. No window overlay plane or hidden white cabin occupies the glazing area. Independent review also found the original loft and wing triangles used counterclockwise exterior winding. Godot uses [clockwise front faces](https://docs.godotengine.org/en/4.7/classes/class_arraymesh.html), so exterior body/wing faces were culled. Both now use clockwise exterior winding with outward normals. All geometry is original MIT presentation; proportions, collision/contact authority and native model are unchanged.

X explicitly sets pilot throttle intent to zero. The normal next-tick pilot command applies that value; engine spool-down remains native. Continuing to hold W/PageUp or a throttle-increase trigger after X raises throttle again through the normal input reader; release that input to retain idle. Space applies both brakes while held, B toggles brake hold, Q/E apply individual brakes. The persistent strip displays copied horizontal ground speed and actual held throttle/left/right brake fractions independently of the full instrument overlay. Pending input is not displayed as already applied. Paused and retained states are labeled; unavailable motion/control values show dashes. The map fits below this strip, including its fault banner and the 960x540 layout.

## Bounded brake diagnosis

The [13 raw result rows](brake-diagnosis.ndjson), [original probe](../../../tools/interactive-preview/brake-diagnosis.cpp) and [reproduction instructions](../../../tools/interactive-preview/brake-diagnosis.md) retain synthetic engineering evidence. This is not a recording of the owner's flight. Main-wheel brake fractions map through the accepted native command boundary and JSBSim LEFT/RIGHT groups; no disconnected brake binding was found.

Ground trials settle the ground-ready model for 600 visible ticks, accelerate through actual commands, then apply declared throttle/brake fractions at 120Hz. Stop means actual speed below 0.1m/s with all three contacts on ground. Distances sum horizontal prepared-plane travel at every completed tick. Released-brake trials end at 60s while still moving.

| Nominal initial speed | Full brakes, idle: stop | Half brakes, idle: stop | Released brakes, idle: travel after60s / remaining speed |
|---|---|---|---|
|10m/s|13.21m /2.53s|23.62m /4.52s|563.83m /8.51m/s|
|20m/s|51.87m /5.04s|92.09m /8.97s|1047.09m /15.02m/s|
|30m/s|118.77m /7.67s|208.41m /13.55s|1475.73m /20.14m/s|

All ten ground trials retained three on-ground contacts. At 20m/s, full throttle plus full brakes stopped in 110.15m/10.78s. Idle intent does not instantaneously remove modeled engine thrust.

Three scripted flight-transition trials share first touchdown at 51.99777m/s. Released brakes still move after120s/3631.86m; half/full brake trials stop in667.80m/24.66s and400.15m/14.45s. There are three subsequent non-all-contact ticks in each trial. The script touches down north2142.49m, beyond the rendered runway's north1700m end: it tests solver transition on the prepared plane, not a runway landing, circuit or pilot procedure. Residual lift and load transfer affect main-wheel normal load and therefore braking force.

These cases establish bounded current solver response. They do not establish the owner's input history, a real C172 stopping distance, or correct handling in every condition. No friction, gear, mass, aerodynamic, engine, native interface, schema or assistance changes are justified by this diagnosis.

## Verification and integration gate

Actual development headless whole-flight/UX checks pass, including menu-suppressed X, nonzero native-throttle fixture, pending-only idle intent, next-tick application, preservation of all other axes, copied strip values, and disjoint shell triangles with finite unit normals, clockwise front faces aligned with outward shell normals, and geometric outward-facing main/tail wing checks. The diagnostic observer compares actual native read_state and command counters before/after camera views.

Actual reference-PC GPU inspection covers the existing 39 scenery/cockpit/map views and four unobstructed nose/left/right/aft shell views. A first visual review exposed fault-map overlap; layout now occurs before the missing-state early return. The corrected views preserve native truth and do not demonstrate flight handling quality.

The PR must retain fresh frozen-source editor/export/rebuilt-JSBSim proof, final exported GPU receipt/images, source/package hashes and independent review before merge. These immutable integration results belong to its final PR evidence comment; development screenshots alone are insufficient. All four protected checks must pass. A separate verified owner payload preserves older games/profiles. No public release is implied.

Consumed native fingerprint: 35cf7b603d99b9accb123405f7569a901ed9e28d32110acbc296b376facd6416. Prepared-world hash: 04bff5a0bcf3509990f6276b2548a28268f57fc96d218a7ca51cab1990ec1ff5. Original probe source SHA256: 54d8c4a8b39c55f116982b1a75b12a70479d138719f81ebefcb6d6bba74d51dc; the reproduction note records its verified complete hash. This evidence contains no pilot profiles or user flight logs.

P1 renderer [#18](https://github.com/brettbergin/flight-simulator/issues/18) and owner phase review stay open. Production flight loop #20, cockpit #21/#26, input #23, sourced aircraft #31 and pilot/training gates retain their independent scope. The renderer qualification remains on hold while this user-facing defect is corrected.
