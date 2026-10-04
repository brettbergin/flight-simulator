# Stable prototype ground presentation

Date: 2026-10-03. Issue [#104](https://github.com/brettbergin/flight-simulator/issues/104).
The owner reported visually glitchy land/environment after the accepted
[cockpit iteration](cockpit-ux.md). This fixes presentation in the original
whole-flight engineering preview; the model and broader phase gates retain
their existing limits.

The former ground stack put random overlapping grass patches 2 mm above a
base surface, overlapping pavement faces at 4 mm, paint at 7–9 mm and
runway-number labels at 12 mm. Shallow views and the camera's 0.1 m near /
50 km far range made their depth ordering fragile. Patch exclusion checked
only patch centers, so large patches could also extend into airfield bounds.

One opaque, shader-painted PlaneMesh at y0 now owns grass, asphalt and all
paint. Original procedural grass variation replaces the competing patch
faces; runway, taxiway, apron, connectors, white/yellow paint and original
seven-segment number cues are analytic color on the same surface. Local
mesh coordinates keep the colors fixed to the accepted east/up/south anchor.
All three grass detail scales fade toward their mean as the pixel footprint
grows. Rectangular strokes use derivative-based area coverage so subpixel
paint fades instead of alternating between full brightness and nothing.
This is an approximate screen-space filter, not photorealistic terrain.
Four-sample MSAA smooths geometry silhouettes; it does not replace ground
shader filtering.

The same surface extends to ±40 km as a decorative skirt beneath the existing
distant ridges. It closes the uncovered strip between the former ±20 km
visual plane and the ridge feet. Native resident coverage stays ±20 km;
there are no new colliders, heights or contacts. Flying outside prepared
coverage still faults visibly. The exact synthetic runway/taxi/apron and
map bounds, native aircraft, worker, 120 Hz and 14 v1 records are unchanged.
All added code/art is original MIT material; no external textures or
real-airport operational data are included.

Bounded development checks passed the actual whole-flight loop and existing
cockpit/map/menu/input assertions. GPU diagnostics cover both runway ends,
low approach, apron intersections, overhead, fields, the coverage boundary
and diagonal corner, plus a five-step camera-only sweep and return. These
observer views hide the aircraft presentation without moving or commanding
the native aircraft. Native `read_state`, held commands and submission
sequence are compared before/after. The returned paused view compares
rendered RGB bytes with a two-level channel tolerance and a 0.1% changed-byte
limit; this is a static return regression check, not a general temporal
aliasing or performance certification.

The final PR records the frozen source/package hashes, editor/exported/
rebuilt-JSBSim replacement checks, thirty actual exported GPU viewport
images, exact-source independent review and all four protected CI checks.
Reproduce with [the pinned Windows runner](../../../tools/interactive-preview/README.md).
The local handoff uses a fresh payload/profile and preserves earlier games.
No new public binary release or long renderer benchmark is implied.

Remaining limits include a flat synthetic resident surface, sparse original
scenery and faceted decorative hills. Shadow cascades and tiny distant
objects can still produce ordinary aliasing; this pass does not claim every
possible GPU artifact is eliminated. P1/#18, production P2/P4 terrain,
C172 handling/systems, pilot evaluation and training qualification remain
open. Future production scenery work must preserve the sole native ground
authority and use sourced terrain/airport data through the planned contracts.
