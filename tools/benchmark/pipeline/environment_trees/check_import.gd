extends SceneTree

# Isolated original-art evidence only. No game/native/flight resource is loaded.
const EXPORTS := [
	["tall-narrow", 0, "OriginalTallNarrowL0"], ["tall-narrow", 1, "OriginalTallNarrowL1"],
	["broad-tiered", 0, "OriginalBroadTieredL0"], ["broad-tiered", 1, "OriginalBroadTieredL1"],
	["irregular-mature", 0, "OriginalIrregularMatureL0"], ["irregular-mature", 1, "OriginalIrregularMatureL1"]]
const MATERIALS := {
	"Bark": ["EvergreenBark", Color(0.125, 0.0625, 0.03125, 1), 0.875],
	"InnerNeedles": ["EvergreenInner", Color(0.015625, 0.0625, 0.03125, 1), 1.0],
	"OuterNeedles": ["EvergreenOuter", Color(0.03125, 0.125, 0.0625, 1), 0.875]}
const BOUNDS := {"tall-narrow": [[24.0, 26.0], [4.5, 6.0], [4.3, 5.8]], "broad-tiered": [[18.0, 20.0], [8.0, 11.0], [7.5, 10.5]], "irregular-mature": [[21.0, 24.0], [7.0, 10.0], [6.5, 9.5]]}
var world: Node3D
var camera: Camera3D
var environment: Environment
var label: Label
var instances: Array[Node3D] = []
var observed: Array[Dictionary] = []
var source_identity: Dictionary
var journal: FileAccess

func _initialize() -> void:
	call_deferred("_run")

func _write(path: String, data: Dictionary) -> void:
	assert(not FileAccess.file_exists(path), "fresh evidence files only")
	var file := FileAccess.open(path, FileAccess.WRITE)
	assert(file != null)
	file.store_string(JSON.stringify(data, "\t", true, true) + "\n")
	file.close()

func _vec(v: Vector3) -> Array:
	return [v.x, v.y, v.z]

func _color(c: Color) -> Array:
	return [c.r, c.g, c.b, c.a]

func _normal_valid(normal: Vector3) -> bool:
	# Vector3 components are stored f32, but GDScript scalar float is binary64.
	# Do not call Vector3.length(), whose internal f32 reduction can tighten1e-4.
	var nx: float = normal.x
	var ny: float = normal.y
	var nz: float = normal.z
	var length64: float = sqrt((nx * nx + ny * ny) + nz * nz)
	return normal.is_finite() and abs(length64 - 1.0) <= 0.0001

func _normal_math_controls() -> void:
	# Predeclared raw-f32 hand witnesses, independent of any candidate geometry.
	# Valid norm~1.00009999862; Vector3.length() can round it beyond1.0001.
	var valid := Vector3(1.0000998973846435546875, 0.00045000002137385308742523193359375, 0.0)
	var invalid_neighbor := Vector3(1.00010001659393310546875, 0.00045000002137385308742523193359375, 0.0)
	assert(_normal_valid(valid), "binary64 normal acceptance hand witness")
	assert(not _normal_valid(invalid_neighbor), "binary64 normal rejection hand witness")

func _stored_scalar_interval(expected: float) -> Array:
	# Source checker owns abs(source-expected)<=1e-6 in the source domain.
	# The actual material/Color-alpha storage is f32. Mapping both source
	# endpoints through that monotone nearest-f32 primitive preserves every
	# admitted source value; comparing the stored value to1e-6 directly does not.
	var low: float = max(0.0, expected - 0.000001)
	var high: float = min(1.0, expected + 0.000001)
	return [float(PackedFloat32Array([low])[0]), float(PackedFloat32Array([high])[0])]

func _stored_scalar_valid(actual: float, expected: float) -> bool:
	var interval := _stored_scalar_interval(expected)
	return actual >= 0.0 and actual <= 1.0 and actual >= float(interval[0]) and actual <= float(interval[1])

func _material_math_controls() -> void:
	# Predeclared source-valid boundary control, independent of candidate output.
	var allowed_source: float = 0.8749990000000001
	assert(abs(allowed_source - 0.875) <= 0.000001)
	var stored: float = PackedFloat32Array([allowed_source])[0]
	# 0.875 is0x3f600000; nearest result is17 binary32 ULPs below it.
	# Test the exact word, avoiding the engine parser's long-decimal rounding.
	assert(PackedFloat32Array([stored]).to_byte_array().hex_encode() == "efff5f3f")
	assert(_stored_scalar_valid(stored, 0.875))
	assert(not _stored_scalar_valid(0.87499892711639404296875, 0.875))
	assert(_stored_scalar_valid(float(PackedFloat32Array([1.0 - pow(2.0, -22.0)])[0]), 1.0))

func _inspect(row: Array) -> Dictionary:
	var path := "res://trees/%s-lod%d.glb" % [row[0], row[1]]
	var preset := ConfigFile.new()
	assert(preset.load(path + ".import") == OK)
	assert(preset.get_value("params", "meshes/generate_lods", true) == false, "actual importer must disable auto LOD")
	assert(preset.get_value("params", "meshes/force_disable_compression", false) == true, "actual importer must retain raw geometry without compression")
	var packed: PackedScene = load(path)
	assert(packed != null)
	var imported_root: Node3D = packed.instantiate()
	# Actual pinned4.7.2 import adds exactly one filename-named identity Node3D.
	# Root independently inspected all six hierarchies before admitting this form.
	assert(imported_root != null and imported_root.get_class() == "Node3D")
	assert(String(imported_root.name) == "%s-lod%d" % [row[0], row[1]])
	assert(imported_root.transform == Transform3D.IDENTITY and imported_root.get_script() == null and imported_root.get_child_count() == 1)
	var instance: Node3D = imported_root.get_child(0)
	assert(instance != null and instance.get_class() == "Node3D" and instance.name == row[2], "unexpected imported authored root")
	world.add_child(imported_root)
	assert(instance.transform == Transform3D.IDENTITY and instance.get_child_count() == 3 and instance.get_script() == null)
	var minimum := Vector3(INF, INF, INF)
	var maximum := Vector3(-INF, -INF, -INF)
	var triangles := 0
	var vertices := 0
	var meshes: Array[Dictionary] = []
	for child in instance.get_children():
		assert(child is MeshInstance3D and MATERIALS.has(String(child.name)))
		var mesh_node := child as MeshInstance3D
		assert(mesh_node.get_child_count() == 0 and mesh_node.transform == Transform3D.IDENTITY)
		assert(mesh_node.get_script() == null and mesh_node.material_override == null)
		assert(mesh_node.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_ON)
		var mesh: ArrayMesh = mesh_node.mesh
		assert(mesh != null and mesh.get_surface_count() == 1)
		assert(mesh.surface_get_primitive_type(0) == Mesh.PRIMITIVE_TRIANGLES)
		var arrays := mesh.surface_get_arrays(0)
		var positions: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		assert(positions.size() > 0 and normals.size() == positions.size() and indices.size() > 0 and indices.size() % 3 == 0)
		for i in range(positions.size()):
			assert(positions[i].is_finite() and _normal_valid(normals[i]))
			minimum = minimum.min(positions[i])
			maximum = maximum.max(positions[i])
		for index in indices:
			assert(index >= 0 and index < positions.size())
		# Preserve exact original imported words for Python's rational area gate.
		# Neither Vector3 f32 cross products nor an approximate f64 cross can
		# decide mathematical nondegeneracy for all admitted mixed exponents.
		var position_bytes := positions.to_byte_array()
		var index_bytes := indices.to_byte_array()
		assert(position_bytes.size() == 12 * positions.size() and index_bytes.size() == 4 * indices.size())
		var material: StandardMaterial3D = mesh.surface_get_material(0)
		var expected: Array = MATERIALS[String(child.name)]
		assert(material != null and material.resource_name == expected[0])
		assert(material.transparency == BaseMaterial3D.TRANSPARENCY_DISABLED and material.cull_mode == BaseMaterial3D.CULL_BACK)
		assert(_stored_scalar_valid(material.metallic, 0.0))
		assert(_stored_scalar_valid(material.roughness, float(expected[2])))
		assert(not material.emission_enabled and material.albedo_texture == null and material.normal_texture == null)
		assert(material.metallic_texture == null and material.roughness_texture == null and material.emission_texture == null)
		var original_linear: Color = expected[1]
		var expected_srgb := original_linear.linear_to_srgb()
		var actual_linear := material.albedo_color.srgb_to_linear()
		var largest_inverse_difference: float = 0.0
		for channel in range(4):
			assert(material.albedo_color[channel] >= 0.0 and material.albedo_color[channel] <= 1.0)
			assert(actual_linear[channel] >= 0.0 and actual_linear[channel] <= 1.0)
			largest_inverse_difference = max(largest_inverse_difference, abs(actual_linear[channel] - original_linear[channel]))
		assert(_stored_scalar_valid(material.albedo_color.a, 1.0))
		triangles += int(indices.size() / 3.0)
		vertices += positions.size()
		meshes.append({"name": String(child.name), "vertices": positions.size(), "indices": indices.size(), "triangles": int(indices.size() / 3.0), "positions_f32_le_hex": position_bytes.hex_encode(), "indices_i32_le_hex": index_bytes.hex_encode(), "triangle_area_gate": "pending exact Python validation of original imported words", "aabb_position": _vec(mesh.get_aabb().position), "aabb_size": _vec(mesh.get_aabb().size), "material": material.resource_name, "albedo_srgb": _color(material.albedo_color), "albedo_linear_readback": _color(actual_linear), "expected_srgb_once": _color(expected_srgb), "source_factor_absolute_tolerance": 0.000001, "stored_scalar_intervals": {"metallic": _stored_scalar_interval(0.0), "roughness": _stored_scalar_interval(float(expected[2])), "alpha": _stored_scalar_interval(1.0)}, "rgb_correspondence_advisory": {"gates_acceptance": false, "largest_inverse_rgba_difference": largest_inverse_difference, "within_source_tolerance_after_inverse": largest_inverse_difference <= 0.000001, "comparison_threshold": 0.000001, "reason": "f32 linear-to-sRGB/inverse rounding is not source-factor admission; Root reviews actual factors"}, "roughness": material.roughness, "metallic": material.metallic, "shadow": mesh_node.cast_shadow})
	# Component promotion precedes each subtraction: Vector3 subtraction would
	# round the dimensions to f32 and incorrectly narrow boundary acceptance.
	var min_x: float = minimum.x
	var min_y: float = minimum.y
	var min_z: float = minimum.z
	var max_x: float = maximum.x
	var max_y: float = maximum.y
	var max_z: float = maximum.z
	var width64: float = max_x - min_x
	var height64: float = max_y - min_y
	var depth64: float = max_z - min_z
	assert(abs(minimum.y) <= 0.00001 and minimum.x < 0 and minimum.z < 0 and maximum.x > 0 and maximum.z > 0)
	assert(abs(minimum.x) <= 8.00001 and abs(minimum.z) <= 8.00001 and maximum.x <= 8.00001 and maximum.z <= 8.00001 and maximum.y <= 26.00001)
	var ranges: Array = BOUNDS[row[0]]
	for i in range(3):
		var measured: float = [height64, width64, depth64][i]
		assert(measured >= float(ranges[i][0]) - 0.00001 and measured <= float(ranges[i][1]) + 0.00001)
	assert(triangles <= (5000 if row[1] == 0 else 900) and vertices <= (15000 if row[1] == 0 else 2700))
	instance.visible = false
	instances.append(instance)
	return {"id": row[0], "lod": row[1], "path": path, "root": String(instance.name), "importer_wrapper": {"name": String(imported_root.name), "class": imported_root.get_class(), "identity_transform": true, "children": 1, "script": false}, "minimum_m": _vec(minimum), "maximum_m": _vec(maximum), "dimensions_binary64_m": [width64, height64, depth64], "height_m": height64, "triangles": triangles, "vertices": vertices, "meshes": meshes, "import_flags": {"meshes/generate_lods": false, "meshes/force_disable_compression": true}}

func _setup_visible() -> Dictionary:
	var viewport := get_root()
	assert(viewport.size == Vector2i(1280, 720))
	viewport.msaa_3d = Viewport.MSAA_DISABLED
	viewport.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
	viewport.use_taa = false
	viewport.scaling_3d_scale = 1.0
	viewport.mesh_lod_threshold = 0.0
	Engine.max_fps = 60
	camera = Camera3D.new()
	camera.keep_aspect = Camera3D.KEEP_HEIGHT
	camera.projection = Camera3D.PROJECTION_PERSPECTIVE
	camera.fov = 60.0
	camera.near = 0.1
	camera.far = 1000.0
	world.add_child(camera)
	camera.make_current()
	var attributes := CameraAttributesPractical.new()
	attributes.auto_exposure_enabled = false
	attributes.exposure_multiplier = 1.0
	camera.attributes = attributes
	environment = Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.5, 0.625, 0.75).linear_to_srgb()
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color.WHITE
	environment.ambient_light_energy = 0.5
	environment.ambient_light_sky_contribution = 0.0
	environment.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	environment.tonemap_exposure = 1.0
	environment.fog_enabled = false
	environment.volumetric_fog_enabled = false
	environment.ssao_enabled = false
	environment.ssr_enabled = false
	environment.ssil_enabled = false
	environment.adjustment_enabled = false
	var env_node := WorldEnvironment.new()
	env_node.environment = environment
	world.add_child(env_node)
	var light := DirectionalLight3D.new()
	light.light_color = Color.WHITE
	light.light_energy = 1.0
	light.rotation_degrees = Vector3(-35, -40, 0)
	light.shadow_enabled = true
	world.add_child(light)
	var projection := camera.get_camera_projection()
	var actual_fov := rad_to_deg(2.0 * atan(1.0 / projection.y.y))
	assert(abs(actual_fov - 60.0) <= 0.0001)
	assert(camera.keep_aspect == Camera3D.KEEP_HEIGHT and abs(camera.near - 0.1) <= 0.000001 and camera.far == 1000)
	assert(viewport.mesh_lod_threshold == 0 and viewport.scaling_3d_scale == 1)
	return {"viewport": [viewport.size.x, viewport.size.y], "fov_vertical_degrees": actual_fov, "projection_y_scale": projection.y.y, "keep_aspect": camera.keep_aspect, "near_m": camera.near, "far_m": camera.far, "ambient_energy": environment.ambient_light_energy, "ambient_srgb": _color(environment.ambient_light_color), "background_linear_intent": [0.5, 0.625, 0.75], "background_stored": _color(environment.background_color), "background_policy": "linear intent converted once to property sRGB; predeclared pixel control", "tonemap": environment.tonemap_mode, "exposure": environment.tonemap_exposure, "light_euler_degrees": _vec(light.rotation_degrees), "light_energy": light.light_energy, "light_white": _color(light.light_color), "shadows": light.shadow_enabled, "automatic_viewport_lod_threshold": viewport.mesh_lod_threshold, "msaa": viewport.msaa_3d, "screen_space_aa": viewport.screen_space_aa, "taa": viewport.use_taa, "scale": viewport.scaling_3d_scale, "fog": environment.fog_enabled, "autoexposure": attributes.auto_exposure_enabled, "renderer": RenderingServer.get_current_rendering_method(), "driver": RenderingServer.get_current_rendering_driver_name()}

func _pose(height: float, distance_m: float, azimuth_degrees: float) -> Dictionary:
	var angle := deg_to_rad(azimuth_degrees)
	var target := Vector3(0, height / 2.0, 0)
	camera.position = Vector3(distance_m * sin(angle), target.y, distance_m * cos(angle))
	camera.look_at(target, Vector3.UP)
	return {"range_m": distance_m, "azimuth_degrees": azimuth_degrees, "eye_m": _vec(camera.position), "target_m": _vec(target), "up": [0, 1, 0]}

func _capture(filename: String) -> void:
	await RenderingServer.frame_post_draw
	var image := get_root().get_texture().get_image()
	assert(image.get_width() == 1280 and image.get_height() == 720)
	assert(image.save_png("res://evidence/" + filename) == OK)

func _visible_lod_readback() -> Array:
	assert(RenderingServer.has_method("mesh_get_surface"), "pinned renderer surface readback unavailable")
	var result: Array[Dictionary] = []
	for instance in instances:
		for child in instance.get_children():
			var mesh: ArrayMesh = (child as MeshInstance3D).mesh
			var surface: Dictionary = RenderingServer.mesh_get_surface(mesh.get_rid(), 0)
			assert(not surface.is_empty() and typeof(surface.get("format")) == TYPE_INT and typeof(surface.get("primitive")) == TYPE_INT)
			assert(surface["primitive"] == Mesh.PRIMITIVE_TRIANGLES)
			assert(typeof(surface.get("vertex_count")) == TYPE_INT and int(surface["vertex_count"]) > 0)
			assert(typeof(surface.get("index_count")) == TYPE_INT and int(surface["index_count"]) > 0)
			assert(typeof(surface.get("vertex_data")) == TYPE_PACKED_BYTE_ARRAY and not surface["vertex_data"].is_empty())
			assert(typeof(surface.get("index_data")) == TYPE_PACKED_BYTE_ARRAY and not surface["index_data"].is_empty())
			if surface.has("lods"):
				assert(typeof(surface["lods"]) == TYPE_ARRAY and surface["lods"].is_empty(), "unexpected actual importer LOD data")
			result.append({"root": String(instance.name), "mesh": String(child.name), "vertex_count": surface["vertex_count"], "index_count": surface["index_count"], "format": surface["format"], "lod_count": 0, "actual_visible_renderer_readback": true})
	return result

func _record_before_capture(data: Dictionary) -> void:
	journal.store_string(JSON.stringify(data, "", true, true) + "\n")
	journal.flush()

func _run() -> void:
	_normal_math_controls()
	_material_math_controls()
	assert(PackedFloat32Array([1.0]).to_byte_array().hex_encode() == "0000803f", "raw imported-word proof requires little-endian Float32")
	assert(PackedInt32Array([1]).to_byte_array().hex_encode() == "01000000", "raw index proof requires little-endian Int32")
	var arguments := OS.get_cmdline_user_args()
	assert(arguments.size() == 1 and arguments[0] in ["resources", "visible"])
	var parsed = JSON.parse_string(FileAccess.get_file_as_string("res://source-identities.json"))
	assert(parsed is Dictionary)
	source_identity = parsed
	world = Node3D.new()
	get_root().add_child(world)
	for row in EXPORTS:
		observed.append(_inspect(row))
	for i in [0, 2, 4]:
		for component in range(3):
			assert(abs(float(observed[i]["minimum_m"][component]) - float(observed[i + 1]["minimum_m"][component])) <= 0.02)
			assert(abs(float(observed[i]["maximum_m"][component]) - float(observed[i + 1]["maximum_m"][component])) <= 0.02)
	if arguments[0] == "resources":
		_write("res://evidence/resources.json", {"passed": true, "mode": "resources", "engine": Engine.get_version_info(), "sources": source_identity, "resources": observed, "scope": "headless imported ArrayMesh/source/sidecar resources only; no actual GPU surface-LOD, pixel or art acceptance"})
		quit(0)
		return
	assert(DisplayServer.get_name() != "headless")
	var settings := _setup_visible()
	assert(settings["renderer"] == "gl_compatibility")
	await RenderingServer.frame_post_draw
	settings["actual_surface_readback"] = _visible_lod_readback()
	_write("res://evidence/visible-settings.json", {"engine": Engine.get_version_info(), "sources": source_identity, "settings": settings, "scope": "properties recorded before capture; visual review still required"})
	camera.position = Vector3(0, 10, 50)
	camera.look_at(Vector3(0, 10, 0))
	await _capture("background-control.png")
	var control_image := get_root().get_texture().get_image()
	var pixel := control_image.get_pixel(8, 8)
	var expected_pixel := Color(0.5, 0.625, 0.75).linear_to_srgb()
	assert(abs(pixel.r - expected_pixel.r) <= 2.0 / 255.0 and abs(pixel.g - expected_pixel.g) <= 2.0 / 255.0 and abs(pixel.b - expected_pixel.b) <= 2.0 / 255.0, "background pixel control failed; do not fit against tree output")
	settings["background_control"] = {"pixel_xy": [8, 8], "observed_rgba": _color(pixel), "expected_display_srgb": _color(expected_pixel), "tolerance": 2.0 / 255.0, "image": "background-control.png"}
	_write("res://evidence/background-control.json", settings["background_control"])
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(128, 128)
	ground.mesh = plane
	ground.position.y = -0.001
	var ground_material := StandardMaterial3D.new()
	ground_material.albedo_color = Color(0.25, 0.25, 0.25).linear_to_srgb()
	ground_material.roughness = 1
	ground_material.metallic = 0
	ground.material_override = ground_material
	world.add_child(ground)
	settings["ground"] = {"size_m": [128, 128], "y_m": ground.position.y, "linear_intent": [0.25, 0.25, 0.25], "stored_albedo": _color(ground_material.albedo_color), "roughness": ground_material.roughness, "metallic": ground_material.metallic}
	var overlay := CanvasLayer.new()
	label = Label.new()
	label.position = Vector2(8, 8)
	overlay.add_child(label)
	get_root().add_child(overlay)
	assert(not FileAccess.file_exists("res://evidence/capture-plan.jsonl"))
	journal = FileAccess.open("res://evidence/capture-plan.jsonl", FileAccess.WRITE)
	assert(journal != null)
	var stills: Array[Dictionary] = []
	var approaches: Array[Dictionary] = []
	for i in range(EXPORTS.size()):
		instances[i].visible = true
		var row: Array = EXPORTS[i]
		var height: float = observed[i]["height_m"]
		label.text = "ISOLATED ART STUDY - NOT CURRENT GAME | %s LOD%d" % [row[0], row[1]]
		for azimuth in [45.0, 225.0]:
			for distance_m in [50.0, 150.0, 400.0]:
				var view := _pose(height, distance_m, azimuth)
				var filename := "%s-lod%d-a%d-r%d.png" % [row[0], row[1], int(azimuth), int(distance_m)]
				view.merge({"id": row[0], "lod": row[1], "image": filename})
				stills.append(view)
				_record_before_capture(view)
				await _capture(filename)
		var frames: Array[Dictionary] = []
		var approach_begin_us := Time.get_ticks_usec()
		for frame in range(301):
			var time_s := float(frame) / 60.0
			var view := _pose(height, 50.0 + 350.0 * time_s / 5.0, 45.0)
			var filename := "%s-lod%d-approach-%04d.png" % [row[0], row[1], frame]
			view.merge({"frame": frame, "time_s": time_s, "image": filename})
			frames.append(view)
			_record_before_capture(view)
			await _capture(filename)
		approaches.append({"id": row[0], "lod": row[1], "duration_s": 5.0, "sample_hz": 60, "inclusive_endpoint_samples": 301, "time_basis": "fixed60Hz capture timeline; PNG saving may extend wall time", "wall_capture_elapsed_s": float(Time.get_ticks_usec() - approach_begin_us) / 1000000.0, "frames": frames, "review": "Root temporal review required; ordinary aliasing distinguished from flicker"})
		instances[i].visible = false
	journal.close()
	_write("res://evidence/visible.json", {"passed": true, "mode": "visible", "meaning_of_passed": "capture/control completion only; no automatic visual acceptance", "engine": Engine.get_version_info(), "sources": source_identity, "settings": settings, "resources": observed, "stills": stills, "approaches": approaches, "scope": "isolated original decorative art; not current game or flight acceptance"})
	quit(0)








