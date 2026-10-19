# Original evergreen studies

Original decorative art for #252 under the [checked brief](../../../docs/contracts/world/original-evergreens-v1.md).
The fourth art candidate passed the independent source-bundle checks, editable
Blender source/export comparison, and isolated Godot import/capture checks. Its
visual acceptance is limited to a faceted prototype source artifact. It is not
placed in the current game and establishes no forest performance, geographic
vegetation, obstacle, or aviation fidelity claim. The path-redacted evidence and
remaining limits belong in [the art evidence](../../../docs/evidence/P4/original-evergreens.md).

The fixed original designs are tall-narrow 25×5×5m, broad-tiered 19×9.5×9m, and
irregular-mature 22.5×8.5×8m. These are authored dimensions, not botanical
measurements, KAWO trees, or surveyed obstacles. Each tree combines a tapered
trunk, bark branches, a narrow dark internal support, and 64 overlapping radial
foliage clumps. Unequal heights, golden-angle placement, varied branch lengths,
droop, and diagonal detail break up the outline. Both LODs retain all 64 clumps,
their end tips, and central cardinal vertices. LOD0 refines the cross sections;
LOD1 preserves their longitudinal taper. The tall crown tapers steadily, the
broad crown carries wider lower masses, and the mature crown has an unequal
upper bulge. No full circumferential canopy plates are used.

Actual checked counts per tree are **3936 triangles / 11808 stored GLB vertices
for LOD0** and **864 triangles / 2592 stored vertices for LOD1**. Both are within
the unchanged brief budgets. Structural checks establish decoded geometry and
source-receipt integrity; they do not by themselves establish appearance.

Reproduction uses the reviewed Blender 4.5.14 LTS build `62c1db4208e8`:

```text
<admitted-blender> --background --factory-startup --python assets_source/environment/original-evergreens-v1/generate_trees.py -- --output <fresh-absolute-checkout-.local-directory>
```

The generator accepts only `--output`. It reads its own reviewed source, checked
contract, and fixed MIT notice. Existing, reparse, and escaping output directories
refuse; failures preserve their files. It writes `original-evergreens.blend`, six
exact GLBs under `exports/`, and `evergreen-source-v1.json`. Receipt sizes and
hashes come from actual output bytes, while tool version/build fields come from
Blender readback. The retained tool acquisition evidence is separate from this
original-art inventory. Candidate geometry is authored before export; it is not
fitted, rescaled, or recentered afterward to pass a check.

The editable blend has six named collections/empty roots, one per design/LOD,
with three static mesh children per root and three shared material meanings.
Blender object IDs are root-prefixed, such as `OriginalTallNarrowL0_Bark`, because
object names are globally unique. Each GLB exports only its own root and semantic
children `Bark`, `InnerNeedles`, and `OuterNeedles`. Object transforms are identity;
vertices carry the dimensions. No external libraries, executable text, cameras,
lights, images, textures, animation, wind, or colliders remain in the source.

The explicit GLB2 exporter serializes each actual Blender mesh's stored Float32
positions. Blender meters, +X right, +Y forward, +Z up map to glTF meters, +X right,
−Z forward, +Y up as `(x,z,-y)`. Flat triangle normals are computed from those
positions. Each primitive has separate POSITION/NORMAL/index views, opaque
materials, and no optional extensions or external URI. No importer decimation is
used. Shared cardinal extrema, top point, and foot are authored before export;
the independent checker still verifies actual decoded bounds and paired LODs.

The isolated proof used pinned Godot 4.7.2 Compatibility/OpenGL3 with automatic
LOD generation and viewport LOD disabled. It retained 36 original fixed views
and six 301-frame approaches, sampled over five seconds of camera time at 60Hz.
All approaches were reviewed through twelve derived overview sheets, with
selected original frames opened directly. The sheets crop from recorded geometry
and camera metadata and resize for inspection; they are not playback, a
performance measurement, or proof that flicker/aliasing is absent. Far-range
foliage aliasing and the subpixel trunk remain prototype limitations. Original
frames and controls remain authoritative; capture completion alone is not visual
acceptance.

The adopted source leaf contains only the reviewed editable blend, six exports,
source receipt, generator, and source documentation. Failed attempts remain
retained separately. This artifact does not qualify runtime placement, terrain
interaction, collisions, installed packaging, or obstacle clearance; parent
airport and phase gates remain open.

Original geometry, code, and editable source are MIT under
[OriginalEvergreens-MIT.txt](../../../third_party/licenses/notices/OriginalEvergreens-MIT.txt).
Blender, Godot, and their dependencies retain their separate licenses. Provenance
and inventory rules are in [the leaf rights evidence](../../../third_party/licenses/evidence/original-evergreens-v1.md).
