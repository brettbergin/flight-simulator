# Original evergreen asset study v1

Proposed bounded original-art/export contract under #243, 2026-10-18. Checked
merge, independent fixture/checker review and Root dispatch precede generation
or import execution. This accepts no artwork, tool execution, runtime resource,
geographic placement, performance, botanical accuracy or phase gate. It does not
depend on a terrain provider, geographic pack, native flight or datum interface.

## Scope and existing conventions

Author three original Pacific-Northwest-inspired evergreen silhouettes, each with
two separate explicitly authored LOD exports. They are decorative art: a tall
narrow fir-inspired form, a broad tiered cedar-inspired form and an irregular
mature fir-inspired form. These names describe visual intent, not species
identification, surveyed dimensions, particular KAWO trees or obstacle coverage.
No photographs, traced images, acquired meshes, foliage textures, botanical
datasets or third-party art inputs are authorized by this original-art leaf.

Consume ADR005's original/versioned source convention, architecture asset
pipeline, assets_source/proof's meter/basis convention and the reviewed portable
Blender4.5.14 LTS build62c1db4208e8 to Godot4.7.2 stable pipeline. Root independently
admits actual executable/archive hashes from its existing pins; neither generator
nor verifier downloads software or changes the dependency lock/user preferences.
The historical proof fixture and cockpit asset remain unchanged. Their closed
checkers are not general validators and cannot certify these new trees.

The assets contain opaque geometry/materials only. No alpha cards, animation,
wind shader, skinning, camera/light, collider, navigation, script, flight state,
placement coordinates, scene attachment, runtime LOD selection or origin
participant is included. No current application world or package imports them.

## Exact authored/exported roster

Own `assets_source/environment/original-evergreens-v1/` with exactly these tracked
source/art files: `README.md`, `generate_trees.py`, `original-evergreens.blend`,
`evergreen-source-v1.json` and the six GLBs below under `exports/`. No texture,
external reference or auxiliary executable file belongs to this asset roster.

| Export id | Relative GLB path | Root node | LOD |
| --- | --- | --- | --- |
| tall-narrow | exports/tall-narrow-lod0.glb | OriginalTallNarrowL0 | 0 |
| tall-narrow | exports/tall-narrow-lod1.glb | OriginalTallNarrowL1 | 1 |
| broad-tiered | exports/broad-tiered-lod0.glb | OriginalBroadTieredL0 | 0 |
| broad-tiered | exports/broad-tiered-lod1.glb | OriginalBroadTieredL1 | 1 |
| irregular-mature | exports/irregular-mature-lod0.glb | OriginalIrregularMatureL0 | 0 |
| irregular-mature | exports/irregular-mature-lod1.glb | OriginalIrregularMatureL1 | 1 |

Each GLB has exactly one scene and exactly four nodes: its named root and direct
children `Bark`, `InnerNeedles`, `OuterNeedles`. The three children are mesh nodes,
one mesh/one indexed TRIANGLES primitive each, three meshes/three materials total.
The root has those three children only and no mesh. Object names are unique in
each export; material mapping is Bark→EvergreenBark, InnerNeedles→EvergreenInner,
OuterNeedles→EvergreenOuter. Array ordering is not semantic; exact names, hierarchy
and reference relationships are. There are no disconnected unreferenced nodes,
meshes, accessors, buffer views or materials. All transforms are identity: omitted
glTF defaults or exact translation[0,0,0], rotation[0,0,0,1], scale[1,1,1]; matrices
are forbidden. Author silhouette asymmetry in baked mesh vertices, not import
offset/scale correction. Multiple connected components inside a mesh are allowed.

In the editable blend, source collections have the six exact root names above,
each containing the corresponding hierarchy at the origin. Exports select one
root/collection at a time; other variants do not leak into a GLB. The source can
retain meaningful editable branch/crown construction internally but no external
library links, textures, simulation, drivers, embedded executable text, cameras,
lights or automatic execution dependency. Generation starts from factory scene,
clears defaults and makes only this original content. Save the editable source;
do not ship a destructive intermediate as the only authoring source.

## Units, foot pivot and authored bounds

Blender uses meters, +X right, +Y forward, +Z up; export uses existing glTF Y-up
mapping to meters, +X right, -Z forward, +Y up. Foot/root pivot is(0,0,0), at the
center of the trunk base. No parent scales, negative scales, postimport axis flips
or automatic ground projection are permitted. Minimum exported vertexY is0 within
1e-5m numerical export tolerance; no vertexY is below−1e-5m. The trunk crosses
X=Z=0, includes its foot atY0 and reaches the canopy. AABB minimumX/Z<0 and maximum
X/Z>0. All positions are finite; |X|,|Z|<=8m and0<=Y<=26m, apart from that foot
numerical tolerance. These are original design dimensions, not measured trees.

| Silhouette | AABB height m | AABB widthX m | AABB depthZ m |
| --- | --- | --- | --- |
| tall-narrow | 24..26 | 4.5..6.0 | 4.3..5.8 |
| broad-tiered | 18..20 | 8.0..11.0 | 7.5..10.5 |
| irregular-mature | 21..24 | 7.0..10.0 | 6.5..9.5 |

Ranges are inclusive, allowing only1e-5m boundary export tolerance. Each paired
LOD1 preserves every min/max AABB component of its LOD0 within0.02m and uses the
same foot, orientation and material meanings. This is an export correspondence
limit, not a runtime LOD switching-distance/crossfade contract. No procedural
postexport fitting, rescaling or recentering repairs an out-of-bounds candidate.

LOD0 has at most5000 nondegenerate triangles and15000 stored vertices total;
LOD1 has at most900 triangles and2700 stored vertices total. Every mesh is nonempty;
each primitive has at least one triangle. Each tree has exactly three material
surfaces, hence at most three ordinary uninstanced material draw submissions per
LOD, before renderer/pass overhead. Six GLBs are <=2MiB each and <=12MiB together;
source .blend <=32MiB. These are authored resource ceilings, not measured frame
time/RSS or a forest instancing benchmark. LOD1 is independently authored or
reviewedly simplified before export, never generated by an uncontrolled Godot
importer decimator. Imported automatic mesh LOD generation is disabled in the
isolated proof so the two authored levels remain explicit.

## Exact opaque materials and GLB subset

Use exactly these shared named PBR meanings in every export. Values are linear
glTF factors, not Godot sRGB inspector values. They are dyadic original choices
so that export checks have no decimal-fit dispute. No scientific color/material
or measured foliage-reflectance claim is made.

| Material | baseColorFactor RGBA | metallicFactor | roughnessFactor |
| --- | --- | --- | --- |
| EvergreenBark | [0.125,0.0625,0.03125,1] | 0 | 0.875 |
| EvergreenInner | [0.015625,0.0625,0.03125,1] | 0 | 1 |
| EvergreenOuter | [0.03125,0.125,0.0625,1] | 0 | 0.875 |

All are alphaMode OPAQUE (omitted default allowed), doubleSided false (omitted
default allowed), no alpha cutoff, emission, texture, normal map or extensions.
The isolated actual import verifies the existing linear-glTF to Godot material
color conversion exactly once. GLB checker compares factors within1e-6 absolute;
it does not silently substitute a prettier factor from a candidate output.

Use GLB2, one JSON chunk followed by one BIN chunk; no other chunks. JSON UTF-8
<=1MiB, no duplicate keys/nonfinite constants/BOM, normal four-byte JSON-space
padding only; BIN padding0..3 zero bytes is allowed. Complete header/chunk lengths
must agree with actual bytes. No extra trailing bytes. One embedded buffer with
no URI; declared byteLength differs from BIN chunk length only by that padding.

The accepted JSON subset is closed to top-level asset, scene, scenes, nodes,
meshes, materials, accessors, bufferViews, buffers. asset requires version"2.0"
and permits only a bounded exporter generator String<=256bytes and optional
copyright String<=256bytes in addition. The default scene index is valid and
selects the sole scene; scene requires nodes and optionally its bounded name.
Nodes permit name, children, mesh and the identity transform members above only.
Meshes permit name and primitives; each primitive permits attributes, indices,
material and mode4 (omitted TRIANGLES default allowed). Attributes are exactly
POSITION and NORMAL. No extra attributes, morph targets or sparse accessors.

There are exactly nine accessors: one position/normal/index triplet per primitive,
not reused between meshes. POSITION/NORMAL are nonnormalized FLOAT VEC3, same
positive count; indices are unsigned SHORT or unsigned INT SCALAR, count positive
and divisible by3, all values within vertex count. POSITION min/max are required
and independently checked against decoded vertices; NORMAL/index min/max may be
present and must agree if present. Accessors permit bufferView, byteOffset,
componentType, normalized(false only), count, type, min and max only. Vertices and
normals are finite; decoded normal length is within1e-4 of1. Degenerate triangles
and out-of-range indices reject; face winding must be outward/consistently authored,
with no mirrored transform to compensate. Different leaf clusters can intersect
as intentional opaque foliage, but duplicate coincident faces and zero-thickness
coplanar leaf sheets are forbidden visual/export defects.

There are exactly nine bufferViews, one per accessor, no shared/interleaved view.
Each permits buffer0, byteOffset, byteLength and optional target matching vertex
ARRAY_BUFFER34962 or index ELEMENT_ARRAY_BUFFER34963; no byteStride. Prove all
offset/length/accessor spans, alignment and counts before reads; views do not
overlap, and unused alignment padding is zero. Buffer objects permit byteLength
only. Materials permit name, pbrMetallicRoughness, alphaMode and doubleSided only;
PBR objects permit baseColorFactor, metallicFactor, roughnessFactor only. Do not
repair unsupported exporter output; report a contract mismatch before adoption.
No extras, extensionsUsed/Required, extensions at any level, external URIs,
images/textures/samplers, skin, animation, camera, light, scripts, collision or
navigation payload is admitted. This subset applies to these six original GLBs,
not a general glTF validator or permission to rewrite the frozen proof checker.

## Source receipt, rights and future tool seams

Generator CLI is exactly `generate_trees.py --output <fresh-directory>`, launched
by Root through the admitted Blender `--background --factory-startup --python`
workflow. Output must resolve strictly below the checkout's .local and must not
exist already; the generator creates that directory and its exports subdirectory,
then writes only the blend, six GLBs and evergreen-source-v1.json. It reads no
art/input/download path. Its only project reads are its own source, this checked
contract and the fixed MIT notice below. Deterministic authored parameters/seeds
are explicit source literals; independent checks assess semantics rather than
promise byte-identical .blend saves. Failures preserve their output for inspection.
No copying into tracked asset paths, application settings or package adoption is
performed by the generator. No preferences or startup files are saved.

Receipt is strict UTF-8 JSON<=65536bytes, depth<=8, <=1024values, no duplicate/extra
keys, exactly `{kind,version,license,scope,contract_sha256,generator,blender,blend,exports,notice}`.
kind is OriginalEvergreenSource/v1; version integer1; license MIT; scope is
"Original decorative evergreen art; no botanical, geographic or obstacle claim".
contract_sha256 is actual raw LF checked contract hash. generator is exactly
`{path,sha256}` for the repository-relative generator path above; blender is
exactly `{version:"4.5.14 LTS",build_hash:"62c1db4208e8"}` from actual tool readback.
blend is exactly `{path:"original-evergreens.blend",bytes,sha256}`. exports is six
ordered rows in the roster table order, each exactly `{id,lod,path,bytes,sha256}`;
lod is integer0/1, paths are exact leaf-relative paths. notice is exactly
`{path:"third_party/licenses/notices/OriginalEvergreens-MIT.txt",sha256}`. Hashes
are actual64lowerhex raw file hashes and sizes actual nonnegative integers within
the stated ceilings; no guessed asset hash, expected output-derived acceptance,
self-hash of the receipt or geometry/count qualification occurs in this receipt.
The independent checker recomputes all output values. Root's execution evidence
separately binds actual tool executable hashes/version logs and invocation/source
files; a receipt's tool strings alone do not establish that execution.

New leaf-owned rights files are
`third_party/licenses/notices/OriginalEvergreens-MIT.txt` (full project MIT grant,
2026 Flight Simulator contributors, UTF-8 LF) and
`third_party/licenses/evidence/original-evergreens-v1.md` with an adjacent
`original-evergreens-v1.inventory.json` listing actual paths/bytes/hashes of the
source, six exports, receipt, generator, independent tools and notice. Inventory
excludes itself; Root records its actual hash externally. Original geometry/code
and editable source are MIT; Blender/Godot/tooling retain their separate licenses.
Root owns central register.json, package/CI inclusion and any .gitattributes
changes; no future third-party-input permission follows from this original record.

Future isolated verification tools are owned at
`tools/benchmark/pipeline/environment_trees/{README.md,check_trees.py,test_trees.py,verify_trees.py,check_import.gd}`.
The Python tools use standard library only; bpy exists only inside admitted
Blender authoring. `check_trees.py --source-dir <candidate-directory>` reads the
exact candidate receipt/blend/export roster and fixed project source/notice pins,
then validates all six GLBs and source hashes, failing nonzero on mismatch.
It reads no arbitrary URI/imported script from a GLB. Candidate directory is an
ordinary existing .local generation directory or the fixed tracked source leaf.
`verify_trees.py --godot <admitted-editor> --source-dir <candidate-directory>
--output <fresh-.local-directory>` first invokes those same independent checks,
then copies exactly the six GLBs and its reviewed check_import.gd into a fresh
isolated .local Godot project. It never opens the current game project or changes
native/Scene/world configuration. Output/source roots must be disjoint, no
symlink/reparse/escaping output, no existing output reuse. Root admits actual tool
paths before execution; these are offline authoring commands, not product APIs.

## Predeclared checks and visual acceptance

Before candidate output, independent checker fixtures must establish valid minimal
subset acceptance and rejection for truncated/header/chunk/count/accessor/offset/
alignment failures, external URI, extra node/material/attribute/extension, wrong
units/pivot/transform, NaN/Inf/zero normal, out-of-range/degenerate index triangles,
wrong material/alpha, bad source hash and exceeded byte/vertex/triangle bounds.
Keep these expectations independent of the production authoring generator.
Do not use a generator roundtrip as expected GLB evidence or edit old pipeline
fixture tests/inventories to make new trees appear qualified.

Retain isolated actual import/version/runtime logs, source pins and receipt only
after successful complete verification. Check actual imported root/hierarchy,
identity transforms, composed meter bounds, mesh triangles/normals/material
bindings, opaque/shadow behavior and one-time color conversion. Reject importer
diagnostics, missing nodes, extra imported resources or unexpected auto-LOD;
document a pinned importer's synthetic scene wrapper separately rather than
confusing it with a new authored node. Headless import establishes resources only.

Visible standalone captures use the admitted Godot Compatibility renderer, fixed
1280x720 viewport,60degree actual vertical perspective FOV, near0.1m/far1000m,
no AA/upscaler/custom shader/temporal effect, no fog/autoexposure/SSAO/SSR, linear
tonemapping/exposure1. Background linear RGB[0.5,0.625,0.75]; white ambient color
energy0.5; one white DirectionalLight3D energy1, Euler degrees[-35,-40,0], shadows
enabled. The sole ground is a128x128m plane atY−0.001 with opaque linear
RGB[0.25,0.25,0.25], roughness1, metallic0. These are original review lighting
choices, not weather or photometry claims. No KAWO backdrop or operational placement.
For each of six exports,
capture front-quarter and rear-quarter azimuths45/225degrees at camera horizontal
ranges50,150,400m, camera/target at half the measured tree height:36 original
images total. Target=(0,height/2,0), eye=(range*sin(azimuth),height/2,
range*cos(azimuth)), up=+Y. Record exact camera/lighting/import/resource identities before
capture. Root reviews paired LODs at the same camera positions; no image is
presented as current-game or flight-quality acceptance. An unambiguous isolated
artifact/LOD label is permitted outside the object silhouette.

Visual pass requires visibly distinct profiles, irregular asymmetric branch/crown
clusters, nonidentical tier spacing/width and a continuous plausible trunk; no
stacked identical cones, geometric pole/spike artifacts, obvious duplicate coplanar
faces, alpha-card popping, floating base or severe LOD silhouette collapse. Tall
narrow remains slender, broad tiered has wider drooping/layered masses and mature
irregular has an uneven crown. LOD0 carries branch-cluster depth at50m, while both
levels remain readable as the intended profile at150/400m. A bounded fixed-camera
near/far approach observation per variant/LOD (six observations, fixed45degree
azimuth and a5second linear50→400m camera-range change) records absence
of visible z-fighting or alpha/coplanar-surface-driven flicker; still images alone cannot establish temporal
stability. Root owns original image/observation review and records limitations;
ordinary subpixel edge aliasing at long range must be reported separately rather
than hidden by an unrecorded rendering setting or called botanical error.
these aesthetic criteria are not botanical measurements or frame-rate guarantees.

After acceptance, this leaf may preserve reviewed source/GLBs and their isolated
evidence only. Geographic distribution, batching/instancing, runtime LOD distances,
world rendering, native collision/obstacles, source accuracy, installed package and
forest performance require later separate admission/verification. Parent airport,
aircraft, pilot and phase issues remain open.
