# Original evergreen structural checks

This #252 slice implements per-GLB and six-export/source-receipt checks for the
checked [original-evergreens-v1 brief](../../../../docs/contracts/world/original-evergreens-v1.md),
raw LF SHA256 `eb3aea53ba869b80117eaed952ac1f65ec2e1e3df1fe731524715fd7e3ae40d6`.
The structural checker generates no art, imports no third-party Python package,
and opens no GLB URI. The fourth art candidate passed source-bundle and editable
Blender source/export checks, followed by an isolated Godot import/capture proof.
It received bounded visual acceptance as faceted prototype source art. Those
separate observations do not change what a structural checker exit status proves.

`check_trees.py --source-dir <absolute-candidate-directory>` accepts the exact
tracked source leaf or an ordinary existing generation directory below this
checkout's `.local`. It requires the closed roster, source receipt, blend byte
identity, fixed LF contract/generator/notice identities and six GLBs. Exit0 means
source receipt/hash integrity, GLB structure and paired-LOD bounds pass; actual
Blender execution/content, artwork and import remain separate gates. No public
filename/identity/root/pin override exists. `_check_glb` remains a private routine
whose caller supplies one of the six fixed identities, never candidate limits.
The MIT notice has a fixed full-text hash. The generator is hashed as actual
reviewed project source; it does not embed its own hash or create a hash cycle.

The routine checks exact closed GLB framing/JSON subset, sole root/hierarchy,
named materials, identity transforms, all nine separate accessors/views, spans,
alignment/zero padding, counts, exact decoded extrema, Float32 finiteness, normal
length, class bounds and stored geometry budgets. Material RGBA/PBR factors use
the brief's absolute1e-6 tolerance within the [0,1] domain, including alpha. Under
OPAQUE, alpha1−2^-22 admits and1−2^-19 rejects. It does not force accepted exporter
defaults, permitted uint32 indices or consistent array reorderings into the
baseline's incidental choices.

Geometry checks use exact rational arithmetic on the decoded Float32 values for
nondegeneracy, winding versus vertex-normal direction and coincident triangles.
Exact shared geometric edges identify connected triangle components. A component
entirely in one plane rejects as a zero-thickness sheet. When a component has
exactly two oppositely directed owners for every edge, its signed volume must be
positive to support outward orientation. This does not invent a blanket closed
manifold requirement: other topology is reported for later export/visual review.
Self-intersection, nonidentically triangulated overlapping surfaces, realistic
branch clusters, continuous trunk/solid axis coverage and natural silhouettes are
not established by these structural checks. Bark bounds must span the origin at
the foot and reach the canopy bounds; those bounds alone are not a solid-model
or continuity proof. The three-box hand witness must pass structure while failing
any claim of accepted tree artwork.

`test_trees.py --reference <Root-frozen-expected-v1.json>` uses standard library
only and requires the exact already reviewed independent byte-reference SHA256
`1d867f93e07dc4247894dcf135427e80e1080440c51a6f8258ca38aa09afae25`.
The unchanged reviewed producer, hand oracles and frozen byte artifact are retained
under `reference/`. CI verifies their source/artifact pins, reproduces the literal
artifact with `reference/producer.py --check reference/expected-v1.json`, then runs
`test_trees.py --reference reference/expected-v1.json` from this tool directory.
Those boxes establish independent numerical expectations; they are never candidate
tree art or expected geometry derived from the Blender generator.
Run it through Root's verified explicit Python with `-I -B -S` after source review
and integration of the complete source/notice packet beside the checked contract.
It never runs the reference producer or an authoring generator. The uint16 and
uint32 box witnesses must retain the hand's72vertices/36triangles,25×5×5m bounds
and5.5/250/110.25m³ component volumes. Mutations exercise framing, duplicate JSON,
keys, transforms, references, bounds, normal/index/triangle faults and tolerances.
Every strict prefix rejects. Explicit defaults, negative zero, reorderings and
subtolerance factors are acceptance controls.

Two independently reviewed source-authored padding controls cover unused bytes.
Inserting four zero bytes after the first288position
bytes moves all following view offsets by4 and declared BIN length1944→1948;
all hand vectors remain unchanged. The zero gap admits and a nonzero gap rejects.
Separately, appending four zeros with declared buffer length1945 gives one unused
declared zero plus three GLB BIN padding bytes; it admits, while nonzero padding
rejects. These controls do not pretend the original witnesses contained gaps.

Full-bundle tests create a separate temporary synthetic
project with the fixed checked contract/MIT notice, explicitly fake generator and
noneditable blend-header/hash witness. Six independently specified box GLBs use
tall25×5×5m, broad19×9.5×9m and mature22×8×8m dimensions; both LODs stay36triangles.
These are checksum/roster/pair fixtures, not a successful Blender source bundle.
The tests check exact scope/pins/strings, missing/extra/reordered entries, altered
source/receipt hashes and malformed receipt data. A broad LOD1 +X extremum4.75m
moves by exact dyadic0.015625m for acceptance and0.03125m for refusal, updating
actual words, accessor bounds and file hash together. Both remain inside the
class range; only the prescribed paired-bound ceiling differs. No expected
geometry or tolerance is derived from the art generator or candidate output.

The checker returns structural/source-integrity success only; it does not grant
artwork, import, or runtime acceptance. The adopted candidate's actual checked
counts are 3936 triangles / 11808 stored GLB vertices per LOD0 tree and 864 / 2592
per LOD1 tree. The [original authoring source](../../../../assets_source/environment/original-evergreens-v1/README.md)
describes its shared 64-branch roster and explicit LODs. The retained blend,
exports, and source receipt have actual identities; inventories must contain
those adopted bytes rather than template or guessed values. Inventory excludes
itself, with its final hash recorded externally to avoid a hash cycle.

The separately reviewed isolated verifier is invoked as:

```text
<admitted-python> -I -B -S tools/benchmark/pipeline/environment_trees/verify_trees.py --godot <admitted-console-launcher> --source-dir <absolute-candidate-directory> --output <fresh-absolute-checkout-.local-directory>
```

`verify_trees.py` consumes `check_trees.py --source-dir` through its exit status,
then copies the six GLBs and reviewed `check_import.gd` into a fresh isolated
project. It validates ordinary, disjoint paths and preserves failed outputs.
Headless resource checks and visible Compatibility/OpenGL3 captures are separate
stages; neither opens the current game or its native flight module. The visible
stage uses pinned Godot 4.7.2, fixed 1280×720 output, 60-degree vertical FOV,
lighting/ground/background controls, and a predeclared background-pixel check.
Importer automatic LOD generation is disabled, raw mesh compression is disabled,
and actual sidecar/readback checks accompany viewport LOD threshold zero.
Headless dummy-renderer observations are not proof of visible surface LOD data.

The completed proof retained **36 fixed stills and six approaches with 301 frames
each**, representing 300 intervals over five seconds of camera time at 60Hz.
Image files, raw controls, imported mesh observations, identities, and logs are
retained as isolated proof artifacts. Saving those frames is not a real-time
performance measurement. Actual imported Float32 positions and indices also
undergo exact rational nondegeneracy checks. Source material-factor admission
remains authoritative; imported scalar observables account for Float32 storage,
while color correspondence is recorded for review without inventing a tighter
source-factor tolerance.

All approaches were reviewed through twelve derived overview sheets, with
selected original frames opened directly. The overviews project recorded source
bounds/camera metadata into crops and resize them for inspection. They are
derived review aids, not authoritative originals, playback, or proof that flicker
is absent. Far-range foliage aliasing and a subpixel trunk remain prototype
limits. The accepted artifact is faceted source art; no tree is placed in a
world, used as a collider, or qualified for installed runtime use by this slice.
See [the art evidence](../../../../docs/evidence/P4/original-evergreens.md) for the
path-redacted execution/review summary. Parent airport, runtime performance, and
phase gates remain separate and open.
