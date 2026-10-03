# ADR-003: Double geodesy with a local float render origin

Date: 2026-10-03. Status: accepted for planning; rebase and datum fixtures required in P1/P2.

## Context

Long navigation flights, runway placement, and instrument altitudes require defined geodetic frames and datums. Ordinary engine vectors lose precision far from the origin. A cockpit and nearby runway need high local precision, while global position must survive rendering changes and saving.

## Decision

Use C++ doubles for WGS84 geodetic/ECEF state and explicit SI/frame types. Use NED for local physics, forward/right/down for aircraft body, and a normalized `q_body_to_ned` quaternion. Convert to Godot local east/up/south coordinates through a tested basis transform. Maintain separate ellipsoid, MSL, pressure, indicated, and AGL altitudes.

Use official standard-precision Godot builds. Anchor the render frame in double ECEF; rebase beyond 2 km from ownship's anchor. Compute all visible transforms from canonical positions, with one origin version applied to camera, terrain, cockpit placement, lighting, audio, and particles. Rebase has no effect on physics or recorded state.

Godot documents precision loss with large ordinary coordinates and requires rebuilding editor/export templates and compatible extensions for double-precision engine builds. Our design trades a controlled render rebase for avoiding a custom engine distribution in the first regional product. [Large world coordinates](https://docs.godotengine.org/en/4.7/tutorials/physics/large_world_coordinates.html).

Record vertical datum/geoid conversions in world packages. Terrain and airport elevations cannot be treated as ellipsoid height without conversion. JSBSim boundary units and contact frame semantics receive independent mapping tests; its contact API explicitly documents feet for AGL and ECEF contact vectors. [FGInertial contract](https://jsbsim-team.github.io/jsbsim/classJSBSim_1_1FGInertial.html).

## Alternatives

A custom double-precision Godot engine simplifies some large-coordinate workflows but adds engine/export/binding maintenance and does not eliminate all shader issues. Entire globe coordinates in ordinary Godot vectors are too imprecise for cockpit/contact work. Flat regional coordinates without a global geodesy layer would complicate navigation expansion and datum-correct maps.

## Consequences and gates

All public vectors carry a frame/unit meaning; unit conversion is centralized. Tests cover north/east/up/right-turn signs, quaternion composition/round trips, date-line/pole geodesy, reference airport elevations, repeated rebases, and replay paths through origin changes. P1's representative scene must show no visible cockpit/terrain/audio discontinuity. If a verified rebase design cannot meet visual/performance correctness after corrective iterations, prototype a custom double build and revise this ADR with actual measurements.
