# Rural scenery and runway locator

Date: 2026-10-03. Issue [#106](https://github.com/brettbergin/flight-simulator/issues/106).
This bounded iteration makes the original whole-flight preview easier to
orient in after the [ground stability fix](environment-stability.md).

Original procedural fields, crop rows, roads, a river and pond share the
existing opaque shader-painted surface. Their finite masks and thin detail
use pixel-footprint filtering. Seeded woodland, an orchard, farm buildings,
silos, a water tank, bridge, village and gabled hangars provide recognizable
references. Six named landmarks expose copied presentation coordinates to
the optional locator in the accepted east/up/south frame. The private scene
metadata is not a persisted identifier or a new public content contract.
All code/art is original MIT material; there are no external assets or real
airport geographic/operational data.

Trees use three bounded MultiMesh batches, with 2,760 instances for trunks
and crowns. Their complete bounds clear the central approach corridor.
The single visual plane and decorative ±40 km skirt remain, while native
prepared coverage stays ±20 km. Scenery adds no colliders, elevations or
physical surface types. In particular, drawn water is cosmetic and retains
the prototype plane's contact behavior. Bridges/buildings cannot be struck
in this preview. These are material limits, not validated terrain behavior.

Tab opens the optional north-up locator; +/− changes its horizontal span
between 1 and 32 km. T selects runway 36 or 18 while the map is visible.
It highlights the selected geometric physical pavement end: east/up/south
(0,0,100) for 36 northbound and (0,0,-1700) for 18 southbound. These are not
sourced operational thresholds. It shows planar distance, true bearing
to that end, before/past-end distance and left/right displacement relative
to its inbound axis. Reciprocal selection reverses the axis signs. Zero
range has no bearing. The height is copied native reference-plane CG
clearance, explicitly distinguished from MSL and wheel clearance. The
aircraft arrow projects nose direction, not ground track; a vertical nose
has no heading arrow. No glidepath, landing suitability, aircraft commands
or flight assist is introduced.

Fault/retained/empty states suppress live-looking aircraft/trail and numeric
guidance. Paused state is labeled; repeated native ticks do not add trail
points. Fresh sessions clear the bounded local trail. Landmark input is
validated, bounded and copied rather than retaining mutable caller data.

Bounded development verification passed actual whole-flight and UX checks,
reciprocal/zero/past-end geometry fixtures, paused/fault/empty and menu/input
cases, exact landmark coordinates and copied metadata. Actual native state,
held commands, submission count and sequence remain identical across locator
actions. GPU diagnostics include both runway ends, approach, coverage edges,
camera sweep/return, six landmark observer views, reciprocal selection,
compact layout and failure presentation: 39 viewport images in total.
Camera-only observer checks keep native state/commands unchanged. Static
return RGB comparison is a bounded regression check, not temporal-aliasing
or performance certification.

The PR records exact frozen source/package hashes, fresh editor/export and
rebuilt-JSBSim replacement verification, final exported GPU images,
independent review and all four protected CI checks before merge. Reproduce
with [the pinned Windows runner](../../../tools/interactive-preview/README.md).
The owner handoff uses a new payload/profile and preserves previous games.
No public binary release or new long performance benchmark is implied.

Flat synthetic terrain, regular procedural field patterns, faceted hills,
generic aircraft and derived native-truth instruments remain visible limits.
P1/#18, production airfield/map work (#22/#26), sourced regional terrain,
C172 systems/handling, pilot evaluation and training qualification remain
open. This iteration adds useful visual references without passing those
broader gates.
