# Original prototype KAWO runway paint

Issue #267 adds opaque original pigment to the existing terrain shader. It uses the admitted compiled physical-end vectors, width and winning pavement polygon. It does not establish threshold positions, displaced thresholds, survey accuracy, regulatory marking compliance or operational suitability. Published runway length and bearing remain separate source facts; the visual frame uses the measured horizontal end vector.

The original layout has 0.45m center/edge stripes, a single first-end 20m dash/30m gap phase beginning at90m and clipped90m before the other end, and edge centers1m inside each nominal side. Each physical end has an inward-facing17m-wide block60..72m inward, with original5x7 digits7.5m wide and a2m gap. These dimensions are original prototype art. Row0 faces inward/top. The feasibility guards are horizontal length>180m and width>=19.45m. Every uploaded float must remain finite after actual Float32 narrowing; geometry admission's existing source bounds remain unchanged.

The material uses the existing polygon winner, including priority and identifier tie order. Paint from a losing crossing polygon is never combined into the winner. No vertices, triangle indices, lighting normals, canonical height bytes, collision, sampling, physics, world child counts or origin transactions change. Existing two-sided lighting hemisphere correction remains intact. Derivative-based edge smoothing and thin-stroke fade are presentation only; their actual appearance requires GPU observation.

## Independent controls and two explicit scopes

The unchanged controls-v1.json was independently authored and accepted before implementation. Its raw SHA256 is150f64031548bbbe38930c842315dacb89513dd857184ae79e8cad6467c78a18. Its20 cases cover frames/number boxes, dimensions, and clear paint/gap/crossing expectations. They are synthetic controls, not a complete admitted airport or a shader implementation. CPU checks consume only geometric expectations; they do not duplicate the shader paint classifier. The1e-9m comparison budget applies only to the small rational binary64 frame fixtures, not real geography or GPU pixels. Additional API-invalid controls separately exercise identifier, nonfinite and Float32-overflow refusal.

Use a fully prepared frontend project for the normal-main-scene commands below: it must include the normal frontend scene and descriptor/dependencies, this directory at res://runway_paint_tests/, and the reviewed production KawoWorld source. Supply exactly one proof argument:

```powershell
# Headless geometry only; editor project.
& $godot --headless --audio-driver Dummy --path $project -- --runway-paint-geometry-checks
# The delivered executable uses its normal main scene and actual packed tests.
& $preview --headless --audio-driver Dummy -- --runway-paint-geometry-checks
# Separate material-uniform observations require actual graphics.
& $godot --audio-driver Dummy --path $project --rendering-method forward_plus --rendering-driver vulkan -- --runway-paint-material-checks
& $preview --audio-driver Dummy --rendering-method forward_plus --rendering-driver vulkan -- --runway-paint-material-checks
```

A minimal isolated world-only project does not provide the production frontend main scene or native descriptor. After importing the actual world dependencies and this test directory under the same res:// paths, enter the fixed editor scene explicitly (or set it as that isolated project's main_scene):

```powershell
& $godot --headless --audio-driver Dummy --path $isolatedProject res://runway_paint_tests/runner.tscn -- --runway-paint-geometry-checks
& $godot --audio-driver Dummy --path $isolatedProject --rendering-method forward_plus --rendering-driver vulkan res://runway_paint_tests/runner.tscn -- --runway-paint-material-checks
```

Supply fresh private profiles and retain original logs using the existing supervised preparation. No --script override is used. In the fully prepared frontend, the root Scene loads the fixed Node runner and returns before normal flight/player initialization. Both entry routes create a fresh RefCounted checks instance and call run("geometry") or run("material").

Geometry retains132 frame/number-box/ID association/feasibility assertions, without material getters or pixel claims. Material retains those same132 plus24 actual material-uniform readback assertions; headless material mode explicitly fails. Uniform getters do not establish shader pixel correctness.

The runner prints KAWO_RUNWAY_PAINT_RESULT with unchanged mode, total and per-group counts/failures, material_readback_exercised and explicit false shader_pixel_cases_exercised/native_flight_exercised flags. It quits from the actual failures and exact group counts. Missing/conflicting/extra proof arguments are refused. Scope interpretation remains separate from actual execution evidence.

Required separate observations use the unchanged actual production shader: the frozen clear white/gap/crossing GPU board controls; number orientation/legibility from both ends; approach, cockpit and chase views; crossing winner and reordered/tie fixtures; grazing/moving-camera aliasing; and a common-origin rebase. Source/Scene regressions must retain exactly1536 terrain children, original mesh/grid bytes and unchanged native authority, and verify provisional visual-layout rejection leaves the existing flight intact. Neither CPU scope substitutes for these observations or installed-package delivery checks.

## Private call sites

Shipping call chain: KawoWorld.prepare calls _paint_layout after unchanged full geometry admission, then calls _material with its result. _paint_layout associates runways to polygon slots by identifier and calls _paint_frame; _paint_frame checks actual narrowing via _paint_upload_finite. _material's previous sole shipping caller was prepare; it now takes the fourth paint array. No public or other shipping material callers were found. checks.gd directly calls the private helpers/material for the scopes described above; Root's separate private GPU observation may do the same. These helpers are local implementation seams, not a new public world/data API.

Original shader/glyph/helper/test source is MIT under the repository license. No external font, image, decal or operational marking source is incorporated.

## Normal delivery integration

The existing whole-flight preparation stages this directory at `res://runway_paint_tests/`, includes the frozen JSON explicitly in the PCK, and runs the normal main scene with `-- --runway-paint-geometry-checks` in the actual editor, portable and rebuilt-library executables. Hosted native CI runs the separate headless geometry scope. Its 132 checks remain separate from KAWO86 source/Scene/host results.

The actual admitted KAWO physical runway segments do not cross. Geographic views must not extend their pavement to imitate a crossing; only the frozen synthetic controls establish crossing-winner observations. The public `tests/world/terrain/kawo_gpu_capture.gd` supplies 47 bounded paused views (the original43 plus four ordinary locator selections added under issue269) when copied to `res://kawo_gpu_capture.gd` in an otherwise fully prepared actual frontend project: 32 existing views, eight source-derived end-number views and three normal public-origin offset/return views. It uses fresh output/profile locations, disables persistence/raw hardware input, joins native/audio and requires exact native/source/resource guards. Preserve failures; inspect original images separately. This is no operational approach or pilot/aircraft qualification.

The whole glyph uses four derivative-scaled occupancy samples to avoid artificial seams between adjacent filled cells. This remains an original block font and a bounded smoothing estimate. Actual low-angle/distance quality needs visual inspection. See [retained evidence](../../../docs/evidence/P4/kawo-runway-paint.md).
