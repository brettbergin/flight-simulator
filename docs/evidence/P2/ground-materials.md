# Original filtered ground materials

Date: 2026-10-10. Issue [#160](https://github.com/brettbergin/flight-simulator/issues/160). Windows Compatibility renderer; original synthetic scenery.

The single opaque ground plane now has restrained dry grass, soil grain,
grass tufts, asphalt weathering and aggregate variation. Five new deterministic
noise terms fade toward their neutral mean before becoming subpixel. The
anisotropic grass term uses a conservative doubled pixel footprint. This is
a modest color improvement over the existing flat procedural scenery.

The plane, local anchor sampling, runway/taxi/apron/paint masks, roads, water,
geometry and native contact surfaces are unchanged. There are no new textures,
colliders, elevations, animation, transparent layers or displaced vertices.
Original MIT provenance and the accepted mask hashes are recorded in
[ground-presentation.json](../../../content/aircraft/prototype/ground-presentation.json).
Cosmetic soil and water retain the same flat prototype contact behavior.

The focused actual-builder suite has 371 checks for the single plane/material,
unchanged local vertices and protected masks, finite fade bounds and bounded
noise terms. A separate ground-only runner records actual resource bytes and
the parsed shader constant. It leaves the existing Facade/Piston receipt
shapes unchanged. Packaging binds the exact dedicated test folder and original
provenance in authoring, staged and corresponding source, then checks editor,
portable and rebuilt-library resources independently.

## GPU observations

Two same-source before/after trials produced 31 views each, including near
grass, both runway ends, apron, approach, airborne fields and a camera sweep.
The 960×540 and 1920×1080 captures show modest material variation with intact
paint, horizon and scenery boundaries. Full native/mapper/origin state and
source inventories remained unchanged; workers and audio joined on exit.

The initial eight-frame warmup produced an inconclusive candidate p95 tail:
6.395 to 9.898 ms. Every raw row and this failed investigation threshold are
retained. A prospectively reviewed five-second warmup was then used for one
new pair with the same views, shader, 180 measured frames and criteria:

| Post-draw callback proxy | Baseline | Candidate |
|---|---:|---:|
| Median | 6.0595 ms | 6.0610 ms |
| p95 | 6.347 ms | 6.096 ms |

Neither warmed increase exceeded the frozen investigation threshold of the
larger of 20% or 2 ms. Draw-call/primitive/object counts were unchanged.
These are callback observations under VSync and the owner's concurrently
running game; they establish neither isolated GPU throughput nor a cause for
the initial startup tail. Independently verified images matched the first
pair exactly. Review SHA256:
`3f20d91e3fbc1d324b714e81825afd708405418ff5d9ff6a7a78af72bcce15ec`.

A supplementary pair saved every one of 90 consecutive rendered camera-motion
frames, followed by grass/runway views before, during and after a presentation
translation of (4096,0,-8192) m. Before/restored images matched exactly; shifted
images remained within the prospective 0.5/255 mean RGB and 1% changed-pixel
limits. Independent review observed no gross seams or popping in the sampled
sequence. All authoritative state remained unchanged and presentation restored
exactly. This checks translated rendering, not a native origin transaction.
Per-frame screenshot writes perturb cadence; the route crosses paving early,
so it cannot certify all grass views or continuous gameplay shimmer. Review
SHA256: `74d6417494006b5d65414cafaa5458504ea8c143b6586b7e028a7c895642f8f4`.

## Delivery status

Fresh Windows editor, portable and rebuilt-library qualification passed on
runtime commit `c2032c90c5d32357955dd4630d6f9ba329ac6c0b`. Each context passed
371 focused ground checks, 41,833 existing Facade checks and 15,909 existing
cold-engine checks. The existing 75 pacing profiles and three 9,805-row
native traces passed their original comparisons. No aircraft model, reference
or native library was changed for this presentation iteration.

The final package inventory contains 456 files and 189 authoring sources.
Independent inspection verified exact ground resource bytes in both actual
portable and rebuilt-library PCK directories, their member checksums, native
module/CRT closure and complete corresponding-source archive. The parsed
shader SHA256 is
`2ca148130b19dbc989b92858e7427bbae407ae348b126bac6d44226e0eb34370`.
The complete package manifest SHA256 is
`25ab9f568529088964ebaa917ddbfde174bf7915d50af89f4a4887e6656732b2`;
independent delivery review SHA256 is
`46cebab3b149a2b1c1b1dd0cb86b4bb87aa4c06abd0074168767e63093128c05`.

A fresh exact copy of the qualified portable export also completed the existing
33-view Windows GPU observer at 960×540, 1920×1080 and 2560×1440. Its paused
native cold sessions stayed at tick zero, workers/audio joined, and complete
original/copied payload and authoring source inventories remained unchanged.
Independent inspection opened all 33 captures, verified their hashes and found
no blocking cosmetic regression; runway paint remained continuous and legible.
The 570 observer assertions passed. Pixel review SHA256:
`ea122271c124f351fcbc14487eecb8d3edfc75f800db7e2d85483b3ffcbe1bdd`.

Final protected hosted CI and the PR review remain required before merge.
No terrain, airport, C172S, hardware/pilot or phase qualification is inferred
from these bounded presentation checks.
