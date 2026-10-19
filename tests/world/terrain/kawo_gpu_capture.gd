extends SceneTree
# Private actual GPU decoration capture. No aircraft/terrain/physics/provider overrides.
const Scene = preload("res://simulation/flight_scene.gd")
const Codec = preload("res://replay/observed_archive/codec.gd")
const Terrain = preload("res://world/terrain/kawo_world.gd")
const Frames = preload("res://simulation/canonical_frames.gd")
const UInt64 = preload("res://simulation/uint64.gd")
const SIZE = Vector2i(1280,720)
const PAYLOAD = "b2c53308fdc427900d84b541aff51ba66cbb71bc483fcee0ea16d067dbd15cfb"
const SOURCES = ["res://kawo_gpu_capture.gd","res://simulation/flight_scene.gd","res://simulation/session_facade.gd","res://simulation/render_origin.gd","res://simulation/canonical_frames.gd","res://simulation/uint64.gd","res://camera/view_policy.gd","res://world/world_admission.gd","res://world/terrain/resident_grid_reader.gd","res://world/terrain/kawo_world.gd","res://interactive/preview.gd","res://interactive/flight_world.gd","res://interactive/flight_map.gd","res://build/native_identity.gd","res://worlds/kawo-prototype-v1/ground.fgrd","res://worlds/kawo-prototype-v1/compile-receipt.json"]
const DECORATION_SOURCES = ["res://world/decoration/kawo_evergreens.gd","res://environment/original-evergreens-v1/tall-narrow-lod1.glb","res://environment/original-evergreens-v1/broad-tiered-lod1.glb","res://environment/original-evergreens-v1/irregular-mature-lod1.glb"]
const BASE_VIEWS = 40
const EXPECTED_VIEWS = 43

class CaptureScene extends Scene:
	func collect_input_raw(_preset: Dictionary = {}) -> Dictionary:
		return {"keys":[],"mouse_buttons":[],"devices":[]}
	func _players_storage_allowed() -> bool: return false
	func _make_local_players_service() -> RefCounted: return null

var _scene: Node
var _output: String = ""
var _failures: Array = []
var _views: Array = []
var _before: Dictionary = {}
var _source_before: Dictionary = {}
var _diagnostic: Dictionary = {}
var _receipt: Dictionary = {"kind":"actual-kawo-gpu-decoration","passed":false,"native_joined":false,"audio_joined":false,"storage_exercised":false,"physics_advanced":false}

func check(good: bool, name: String) -> bool:
	if not good: _failures.append(name)
	return good

func _initialize() -> void:
	call_deferred("_run")

func _source_rows() -> Dictionary:
	var rows: Dictionary = {}
	for path in SOURCES+DECORATION_SOURCES:
		# Only fixed world-pack files live outside an exported PCK. Source/GLB
		# resources must remain actually readable through their own res:// paths.
		var resolved: String = path
		if not OS.has_feature("editor") and path.begins_with("res://worlds/"):
			resolved = OS.get_executable_path().get_base_dir().path_join(path.trim_prefix("res://"))
		rows[path] = {"resolved_path":resolved,"bytes":FileAccess.get_file_as_bytes(resolved).size(),"sha256":FileAccess.get_sha256(resolved)}
	return rows

func _decoration() -> Dictionary:
	var trees: Node3D = _scene.get("_kawo_decoration_root") as Node3D
	if not is_instance_valid(trees) or trees.is_queued_for_deletion() or not trees.has_method("placement_observation") or not trees.has_method("source_binding"): return {}
	var batches: Array = []
	for node in trees.get_children():
		if not node is MultiMeshInstance3D or node.multimesh == null or node.multimesh.mesh == null: return {}
		var transforms: Array = []
		for i in node.multimesh.instance_count: transforms.append(node.multimesh.get_instance_transform(i))
		batches.append({"id":node.get_instance_id(),"transform":node.transform,"children":node.get_child_count(),"count":node.multimesh.instance_count,"mesh_id":node.multimesh.mesh.get_instance_id(),"surfaces":node.multimesh.mesh.get_surface_count(),"bounds":node.multimesh.custom_aabb,"instances":transforms})
	return {"id":trees.get_instance_id(),"source":trees.source_binding(),"placement":trees.placement_observation(),"transform":trees.transform,"visible":trees.visible,"inside_tree":trees.is_inside_tree(),"sibling":trees != _scene.world_root and trees.get_parent() == _scene.world_root.get_parent(),"parent_id":trees.get_parent().get_instance_id() if trees.get_parent() != null else 0,"batches":batches}

func _authority() -> Dictionary:
	return {"native":_scene.facade.get("_bridge").call("read_state"),"readback":_scene.facade.readback(),"recording":_scene.observed_recorder.recording(),"origin":_scene.facade.render_origin.read_origin(),"world_source":_scene.world_root.source_binding(),"world_transform":_scene.world_root.transform,"world_child_count":_scene.world_root.get_child_count(),"decoration":_decoration(),"ownship_transform":_scene.airplane.transform,"cockpit_transform":_scene.cockpit.root.transform,"held_controls":_scene.held_controls.duplicate(true),"held_systems":_scene.held_systems.duplicate(true),"pending_systems":_scene.pending_systems.duplicate(true),"submitted_count":_scene.submitted_count,"event_count":_scene.event_count,"recording_player_context":_scene._recording_player_context.duplicate(true)}

func _digest(value: Variant) -> String:
	var h := HashingContext.new()
	h.start(HashingContext.HASH_SHA256)
	h.update(var_to_bytes(value))
	return h.finish().hex_encode()

func _pose(t: Transform3D) -> Dictionary:
	return {"position":[t.origin.x,t.origin.y,t.origin.z],"basis_columns":[[t.basis.x.x,t.basis.x.y,t.basis.x.z],[t.basis.y.x,t.basis.y.y,t.basis.y.z],[t.basis.z.x,t.basis.z.y,t.basis.z.z]]}

func _camera() -> Dictionary:
	var t: Transform3D = _scene.camera.transform
	var parent: Node3D = _scene.camera.get_parent_node_3d()
	return {"position":[t.origin.x,t.origin.y,t.origin.z],"basis_columns":[[t.basis.x.x,t.basis.x.y,t.basis.x.z],[t.basis.y.x,t.basis.y.y,t.basis.y.z],[t.basis.z.x,t.basis.z.y,t.basis.z.z]],"local_transform":_pose(t),"global_transform":_pose(_scene.camera.global_transform),"parent_id":parent.get_instance_id() if parent != null else 0,"parent_name":str(parent.name) if parent != null else "","parent_global_transform":_pose(parent.global_transform) if parent != null else null,"top_level":_scene.camera.top_level,"mode":_scene.camera_mode,"settings":_scene.camera_view_settings(),"actual_fov_deg":float(_scene.camera.fov),"distance_m":_scene.camera_distance,"look_rad":[_scene.look_angles.x,_scene.look_angles.y],"near_m":_scene.camera.near,"far_m":_scene.camera.far}

func _shot(name: String, mode: String, sequence_index: int = -1) -> bool:
	var path: String = _output.path_join(name+".png")
	if not check(not FileAccess.file_exists(path),"fresh_original_"+name): return false
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var image: Image = root.get_texture().get_image()
	if not check(image != null and image.get_size() == SIZE,"actual_viewport_dimensions_"+name): return false
	if not check(image.save_png(path) == OK,"original_png_written_"+name): return false
	var after: Dictionary = _authority()
	if not check(Codec._exact(after,_before),"complete_paused_native_source_recording_unchanged_"+name): return false
	_views.append({"file":name+".png","bytes":FileAccess.get_file_as_bytes(path).size(),"sha256":FileAccess.get_sha256(path),"width":image.get_width(),"height":image.get_height(),"image_format":image.get_format(),"camera":_camera(),"diagnostic":_diagnostic.duplicate(true),"capture_kind":mode,"sequence_index":sequence_index,"tick":after.readback.tick,"session_id":after.readback.session_id,"prepared_world_sha256":after.readback.prepared_world_sha256,"world_binding":after.world_source,"decoration_binding":after.decoration.source,"decoration_count":after.decoration.placement.count,"decoration_placement_sha256":_digest(after.decoration.placement),"decoration_state_sha256":_digest(after.decoration),"authority_before_sha256":_digest(_before),"authority_after_sha256":_digest(after),"captured_monotonic_usec":Time.get_ticks_usec()})
	return true

func _ordinary_view(mode: int) -> void:
	_diagnostic = {}
	_scene.set_camera_mode(mode)
	_scene.show_state(0.0)

func _oblique(offset: Vector3) -> bool:
	# Explicit diagnostic camera-only override in fixed anchor EUS. No ownship,
	# mesh, origin, native state, terrain height or view-policy change is made.
	_ordinary_view(1)
	var position: Vector3 = _scene.airplane.position + offset
	var floor: Dictionary = _scene.world_root.camera_height(float(position.x),float(position.z))
	if not check(floor.ok,"diagnostic_camera_has_canonical_floor"): return false
	position.y = maxf(position.y,floor.height_m+0.35)
	_scene.camera.position = position
	_scene.camera.look_at(_scene.airplane.position+Vector3(0.0,-1.0,0.0),Vector3.UP)
	return true

func _canopy(camera_xz: Vector2,target_xz: Vector2) -> bool:
	# Predeclared fixed anchor-EUS X/Z positions; terrain-relative camera/target
	# heights use the actual admitted surface, never an image-derived placement.
	_ordinary_view(1)
	var offset: Vector3 = _scene.world_root.position
	var camera_floor: Dictionary = _scene.world_root.camera_height(float(camera_xz.x+offset.x),float(camera_xz.y+offset.z))
	var target_floor: Dictionary = _scene.world_root.camera_height(float(target_xz.x+offset.x),float(target_xz.y+offset.z))
	if not check(camera_floor.ok and target_floor.ok,"canopy_fixed_points_have_canonical_floor"): return false
	_scene.camera.position = Vector3(camera_xz.x+offset.x,camera_floor.height_m+140.0,camera_xz.y+offset.z)
	_scene.camera.look_at(Vector3(target_xz.x+offset.x,target_floor.height_m+12.0,target_xz.y+offset.z),Vector3.UP)
	return true

func _trunk(target_height: float = 8.0) -> bool:
	# Index0 is fixed by the admitted deterministic placement order, selected
	# before any capture output; no tree/image search or ownship move occurs.
	_ordinary_view(1)
	var first: Dictionary = _before.decoration.placement.placements[0]
	var pose: Transform3D = _before.decoration.transform
	var foot: Vector3 = pose*Vector3(float(first.east_m),float(first.up_m),float(first.south_m))
	var position: Vector3 = foot+Vector3(18.0,3.0,18.0)
	var floor: Dictionary = _scene.world_root.camera_height(float(position.x),float(position.z))
	if not check(floor.ok,"first_canonical_tree_close_camera_has_floor"): return false
	position.y = maxf(position.y,floor.height_m+1.0)
	_scene.camera.position = position
	_scene.camera.look_at(foot+Vector3(0.0,target_height,0.0),Vector3.UP)
	_receipt["trunk_control" if target_height == 8.0 else "trunk_foot_control"] = {"placement_index":0,"placement":first.duplicate(true),"camera_offset_eus_m":[18.0,3.0,18.0],"target_offset_eus_m":[0.0,target_height,0.0],"camera_floor_clearance_m":1.0}
	return true

func _paint_frames() -> Array:
	# Existing admitted geometry only. No source-end or image-derived selection.
	var geometry: Dictionary = _scene.world_root.get("_geometry")
	var frames: Array = []
	for runway in geometry.runways:
		var positions: Array = []
		var names: Array = []
		for end in runway.ends:
			var position: Array = []
			for tag in end.eus_m:
				var number: Dictionary = Terrain._tag(tag)
				if not check(number.ok,"admitted_end_tag_for_camera"): return []
				position.append(number.value)
			positions.append(position)
			names.append(end.designator)
		var width: Dictionary = Terrain._tag(runway.width_m)
		if not check(width.ok,"admitted_width_tag_for_camera"): return []
		var frame: Dictionary = Terrain._paint_frame(positions[0],positions[1],width.value,names,runway.id)
		if not check(not frame.is_empty(),"admitted_paint_frame_for_camera"): return []
		frame["designators"] = names
		frame["physical_ends_eus_m"] = positions
		frames.append(frame)
	return frames

func _number_view(frame: Dictionary,end_index: int,top: bool) -> bool:
	_ordinary_view(1)
	_scene.camera.fov = 60.0
	var sign_value: float = 1.0 if end_index == 0 else -1.0
	var forward: Array = [sign_value*frame.forward[0],sign_value*frame.forward[1]]
	var target: Array = [frame.number_bottoms[end_index][0]+6.0*forward[0],frame.number_bottoms[end_index][1]+6.0*forward[1]]
	var camera_xz: Array = target.duplicate()
	if not top:
		camera_xz = [frame.ends[end_index][0]-200.0*forward[0],frame.ends[end_index][1]-200.0*forward[1]]
	var offset: Vector3 = _scene.world_root.position
	var camera_floor: Dictionary = _scene.world_root.camera_height(float(camera_xz[0]+offset.x),float(camera_xz[1]+offset.z))
	var target_floor: Dictionary = _scene.world_root.camera_height(float(target[0]+offset.x),float(target[1]+offset.z))
	if not check(camera_floor.ok and target_floor.ok,"number_view_canonical_surface"): return false
	var position: Vector3 = Vector3(camera_xz[0]+offset.x,camera_floor.height_m+(100.0 if top else 30.0),camera_xz[1]+offset.z)
	var aim: Vector3 = Vector3(target[0]+offset.x,target_floor.height_m,target[1]+offset.z)
	var up: Vector3 = Vector3(forward[0],0.0,forward[1]) if top else Vector3.UP
	# Set the complete prescribed pose, independent of prior camera basis/scale.
	# These are render-world coordinates; do not inherit an earlier look_at pose.
	_scene.camera.global_transform = Transform3D(Basis.looking_at(aim-position,up),position)
	_diagnostic = {"purpose":"original prototype number inspection; not operational approach guidance","runway_id":frame.id,"designator":frame.designators[end_index],"physical_end_eus_m":frame.physical_ends_eus_m[end_index].duplicate(),"inward_xz":forward,"number_bottom_xz":frame.number_bottoms[end_index].duplicate(),"canonical_target_xz":target,"canonical_camera_xz":camera_xz,"camera_surface_height_m":camera_floor.height_m,"target_surface_height_m":target_floor.height_m,"height_above_camera_surface_m":100.0 if top else 30.0,"up":[up.x,up.y,up.z],"fov_deg":60.0}
	return true

func _render_roots() -> Dictionary:
	return {"world":_scene.world_root.transform,"ownship":_scene.airplane.transform,"cockpit":_scene.cockpit.root.transform,"camera":_scene.camera.transform,"lighting":_scene.light_root.transform,"decoration":_scene.get("_kawo_decoration_root").transform}

func _render_content() -> Dictionary:
	# Actual resource identities and original array bytes, never regenerated
	# reference terrain. Keep only digests, not1536 copied mesh arrays in memory.
	var meshes: Array = []
	var materials: Dictionary = {}
	for child in _scene.world_root.get_children():
		if not child is MeshInstance3D or child.mesh == null or child.mesh.get_surface_count() != 1: return {}
		var material: ShaderMaterial = child.mesh.surface_get_material(0) as ShaderMaterial
		if material == null or material.shader == null: return {}
		meshes.append({"node":child.get_instance_id(),"transform":child.transform,"visible":child.visible,"mesh":child.mesh.get_instance_id(),"primitive":child.mesh.surface_get_primitive_type(0),"aabb":child.mesh.get_aabb(),"custom_aabb":child.custom_aabb,"arrays_sha256":_digest(child.mesh.surface_get_arrays(0)),"material":material.get_instance_id()})
		var key: String = str(material.get_instance_id())
		if not materials.has(key):
			var uniforms: Dictionary = {}
			for name in ["ring0","ring1","second_wins","ground_color","color0","color1","paint_ends0","paint_ends1","paint_axes0","paint_axes1","paint_size0","paint_size1","paint_numbers0","paint_numbers1","paint_digits0","paint_digits1"]:
				uniforms[name] = material.get_shader_parameter(name)
			materials[key] = {"shader":material.shader.get_instance_id(),"shader_source_sha256":material.shader.code.sha256_text(),"uniforms":uniforms}
	return {"world":_scene.world_root.get_instance_id(),"visible":_scene.world_root.visible,"children":_scene.world_root.get_child_count(),"meshes":meshes,"materials":materials}

func _transaction_authority_same(original: Dictionary,current: Dictionary) -> bool:
	# Enumerated unchanged authority. Only the committed origin/version and
	# normal participant root transforms may change during a successful rebase.
	for key in ["native","readback","recording","world_source","world_child_count","held_controls","held_systems","pending_systems","submitted_count","event_count","recording_player_context"]:
		if not check(Codec._exact(original[key],current[key]),"rebase_preserves_"+key): return false
	for key in ["id","source","placement","visible","inside_tree","sibling","parent_id","batches"]:
		if not check(Codec._exact(original.decoration[key],current.decoration[key]),"rebase_preserves_decoration_"+key): return false
	return true

func _rebase_shot(name: String,phase: Dictionary,content: Dictionary) -> bool:
	# Separate phase baseline. The original40 _shot/_before assertions remain
	# unchanged and are never reassigned to exempt a transaction from a guard.
	var path: String = _output.path_join(name+".png")
	if not check(not FileAccess.file_exists(path),"fresh_original_"+name): return false
	var camera: Dictionary = _camera()
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var image: Image = root.get_texture().get_image()
	if not check(image != null and image.get_size() == SIZE,"actual_viewport_dimensions_"+name): return false
	if not check(image.save_png(path) == OK,"original_png_written_"+name): return false
	var after: Dictionary = _authority()
	if not check(Codec._exact(after,phase),"complete_origin_phase_authority_unchanged_"+name): return false
	if not check(Codec._exact(_source_rows(),_source_before),"source_product_bytes_unchanged_"+name): return false
	if not check(Codec._exact(_camera(),camera) and Codec._exact(_render_content(),content),"camera_material_mesh_unchanged_"+name): return false
	_views.append({"file":name+".png","bytes":FileAccess.get_file_as_bytes(path).size(),"sha256":FileAccess.get_sha256(path),"width":image.get_width(),"height":image.get_height(),"image_format":image.get_format(),"camera":camera,"diagnostic":_diagnostic.duplicate(true),"capture_kind":"diagnostic same canonical number-top across public normal-origin transaction; no native advance","tick":after.readback.tick,"session_id":after.readback.session_id,"prepared_world_sha256":after.readback.prepared_world_sha256,"world_binding":after.world_source,"origin":after.origin,"render_content_sha256":_digest(content),"authority_before_sha256":_digest(phase),"authority_after_sha256":_digest(after),"captured_monotonic_usec":Time.get_ticks_usec()})
	return true

func _rebase_addendum(frame: Dictionary) -> bool:
	if not _number_view(frame,0,true): return false
	var original: Dictionary = _authority()
	var content: Dictionary = _render_content()
	if not check(not content.is_empty() and content.children == 1536,"rebase_original_actual_mesh_material_content"): return false
	var roots: Dictionary = _render_roots()
	if not check(original.origin.valid and original.origin.committed != null,"rebase_original_registry_valid"): return false
	var committed: Dictionary = original.origin.committed
	var original_ecef: Array = committed.origin_ecef_m.duplicate()
	var rotation: Array = committed.ecef_to_eus
	var shifted: Array = []
	# Fixed EUS(100,0,64)m through the existing anchor rotation transpose.
	for axis in 3:
		var east: float = rotation[axis]*100.0
		var south: float = rotation[6+axis]*64.0
		shifted.append(original_ecef[axis]+(east+south))
	_receipt.render_origin_addendum = {"fixed_origin_delta_eus_m":[100.0,0.0,64.0],"original_origin":original.origin.duplicate(true),"requested_shifted_ecef_m":shifted.duplicate(),"canonical_number_frame":frame.duplicate(true),"content_sha256":_digest(content),"phases":[],"scope":"Public registry route, exact immutable authority/resources and same canonical number camera; independent original-image review, not pixel equality or GPU coordinate-accuracy proof"}
	if not await _rebase_shot("number-origin-before",original,content): return false
	for phase_index in 2:
		var request: Array = shifted if phase_index == 0 else original_ecef
		var prior_origin: Dictionary = _scene.facade.render_origin.read_origin()
		var expected_version: Dictionary = UInt64.increment(prior_origin.committed.version)
		var reply: Dictionary = _scene.facade.render_origin.rebase(request)
		if not check(expected_version.ok and reply.ok and reply.error.is_empty() and reply.origin.valid and reply.origin.error.is_empty() and reply.origin.committed.origin_ecef_m == request and reply.origin.committed.version == expected_version.value and reply.origin.committed.ecef_to_eus == rotation and reply.origin.committed.session_id == committed.session_id,"normal_public_origin_commit_"+str(phase_index)): return false
		if not check(reply.origin.active_ids == original.origin.active_ids and reply.origin.absent_categories == original.origin.absent_categories,"same_origin_participant_roster_"+str(phase_index)): return false
		if not _transaction_authority_same(original,_authority()): return false
		if not check(Codec._exact(_source_rows(),_source_before),"origin_transaction_preserves_all_source_product_bytes_"+str(phase_index)): return false
		if not _number_view(frame,0,true): return false
		var phase: Dictionary = _authority()
		if not _transaction_authority_same(original,phase): return false
		if not check(Codec._exact(_render_content(),content),"origin_preserves_exact_mesh_arrays_and_material_uniforms_"+str(phase_index)): return false
		var current_roots: Dictionary = _render_roots()
		# Retain actual parent/local/global camera diagnostics even if a following
		# exact invariant fails. A recorded phase is not a passed phase by itself.
		_receipt.render_origin_addendum.phases.append({"index":phase_index,"origin":phase.origin.duplicate(true),"render_roots_sha256":_digest(current_roots),"content_sha256":_digest(content),"authority_sha256":_digest(phase),"camera":_camera(),"guards_passed":false})
		for key in roots:
			if not check(Codec._exact(current_roots[key].basis,roots[key].basis),"origin_preserves_participant_basis_"+key): return false
		var offset: Array = Frames.project(phase.world_source.anchor_ecef_m,request,rotation)
		if not check(offset.size() == 3 and _scene.world_root.position == Vector3(offset[0],offset[1],offset[2]),"actual_common_terrain_translation_"+str(phase_index)): return false
		if phase_index == 1 and not check(Codec._exact(current_roots,roots),"same_origin_reproduces_exact_original_cpu_transforms"): return false
		_receipt.render_origin_addendum.phases[-1].guards_passed = true
		if not await _rebase_shot("number-origin-shifted" if phase_index == 0 else "number-origin-returned",phase,content): return false
	return true

func _run() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() < 1 or args.size() > 2: quit(1); return
	_output = args[0]
	var fallback: bool = args.size() == 2 and args[1] == "--compatibility-fallback"
	if args.size() == 2 and not fallback: quit(1); return
	if not _output.is_absolute_path() or _output.begins_with("res://") or _output.begins_with("user://") or DirAccess.dir_exists_absolute(_output) or FileAccess.file_exists(_output): quit(1); return
	if DirAccess.make_dir_recursive_absolute(_output) != OK: quit(1); return
	_receipt.engine = Engine.get_version_info()
	_receipt.display_server = DisplayServer.get_name()
	_receipt.renderer = RenderingServer.get_current_rendering_method()
	_receipt.driver = RenderingServer.call("get_current_rendering_driver_name") if RenderingServer.has_method("get_current_rendering_driver_name") else "unavailable"
	_receipt.adapter = RenderingServer.get_video_adapter_name()
	_receipt.argv = OS.get_cmdline_args()
	_receipt.compatibility_fallback_requested = fallback
	_receipt.exported_world_mapping = not OS.has_feature("editor")
	if not check(DisplayServer.get_name() != "headless","actual_graphical_display"):
		await _finish(); return
	if not check(_receipt.renderer == ("gl_compatibility" if fallback else "forward_plus"),"explicit_requested_renderer_observed"):
		await _finish(); return
	if not fallback and not check(_receipt.driver == "vulkan","actual_vulkan_driver"):
		await _finish(); return
	var adapter: String = str(_receipt.adapter).to_lower()
	if not check(not adapter.is_empty(),"actual_gpu_adapter_named"):
		await _finish(); return
	for word in ["llvmpipe","softpipe","software","warp","microsoft basic render"]:
		if not check(not adapter.contains(word),"no_software_adapter_"+word): await _finish(); return
	DisplayServer.window_set_size(SIZE)
	root.size = SIZE
	_scene = CaptureScene.new()
	root.add_child(_scene)
	_scene.set_process(false)
	_scene.set_physics_process(false)
	_scene.set_process_input(false)
	_scene.set_process_unhandled_input(false)
	_scene.set_process_unhandled_key_input(false)
	if not check(_scene.facade != null,"actual_initial_native_flight"):
		await _finish(); return
	_scene.dismiss_first_flight()
	if not check(_scene.restart(true,"calm","original-interactive-prototype","ground-ready","kawo-prototype-v1"),"actual_kawo_adoption"):
		await _finish(); return
	_scene.dismiss_first_flight()
	if not check(_scene.pause_session(true) and _scene.advance_wall_us(0),"verified_actual_pause_tick0"):
		await _finish(); return
	if _scene.sound != null:
		_scene.sound.set_process(false)
		if not check(bool(await _scene.sound.shutdown()),"audio_joined_before_observation"):
			await _finish(); return
	# Hide the pause menu as presentation only. close_menu() resumes native flight
	# and is deliberately not used. The actual native session stays paused.
	_scene.menu_open = false
	_scene.menu.hide()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_ordinary_view(0)
	_before = _authority()
	_source_before = _source_rows()
	var native: Dictionary = _before.readback
	if not check(native.host_mode == "paused" and native.tick == "0" and native.prepared_world_sha256 == PAYLOAD and _before.world_source.payload_sha256 == PAYLOAD and _before.world_source.session_id == native.session_id,"actual_paused_native_renderer_binding"):
		await _finish(); return
	var decoration: Dictionary = _before.decoration
	if not check(not decoration.is_empty() and decoration.visible and decoration.inside_tree and decoration.sibling and Codec._exact(decoration.source,_before.world_source) and decoration.placement.count == 192 and decoration.placement.batch_count == 9 and decoration.placement.placements.size() == 192 and decoration.batches.size() == 9 and _before.world_child_count == 1536,"actual_visible_same_binding_192_tree_nine_batch_sibling"):
		await _finish(); return
	for batch in decoration.batches:
		if not check(batch.count == 64 and batch.children == 0 and batch.transform == Transform3D.IDENTITY and batch.surfaces == 1,"actual_three_balanced_64_instance_material_batches_per_design"):
			await _finish(); return
	_receipt.decoration_source = decoration.source.duplicate(true)
	_receipt.decoration_placement = decoration.placement.duplicate(true)
	_receipt.decoration_initial_state_sha256 = _digest(decoration)
	for row in _source_before.values():
		if not check(row.bytes > 0 and row.sha256.length() == 64,"all_fixed_source_product_inputs_present"):
			await _finish(); return
	_receipt.actual_source = native.duplicate(true)
	if not await _shot("cockpit","ordinary accepted cockpit preset"): await _finish(); return
	_ordinary_view(1)
	if not await _shot("chase","ordinary accepted chase preset"): await _finish(); return
	if not _oblique(Vector3(40.0,20.0,-35.0)) or not await _shot("runway-grass-edge","diagnostic camera-only offset EUS(+40,+20,-35)m from unchanged ownship; floor clamped"):
		await _finish(); return
	if not _oblique(Vector3(-55.0,55.0,45.0)) or not await _shot("runway-overview","diagnostic camera-only offset EUS(-55,+55,+45)m from unchanged ownship; floor clamped"):
		await _finish(); return
	if not _canopy(Vector2(-1120.0,1000.0),Vector2(-720.0,360.0)) or not await _shot("canopy-west","diagnostic camera-only fixed anchor EUS XZ(-1120,1000), surface+140m; target XZ(-720,360), surface+12m"):
		await _finish(); return
	if not _canopy(Vector2(1200.0,1200.0),Vector2(688.0,576.0)) or not await _shot("canopy-east","diagnostic camera-only fixed anchor EUS XZ(1200,1200), surface+140m; target XZ(688,576), surface+12m"):
		await _finish(); return
	if not _trunk() or not await _shot("trunk-first","diagnostic camera-only first deterministic placement; foot+(18,3,18)m camera clamped to floor+1m; target foot+(0,8,0)m"):
		await _finish(); return
	if not _trunk(1.0) or not await _shot("trunk-foot","diagnostic camera-only same first placement/camera and floor clamp; target foot+(0,1,0)m for contact inspection above normal HUD"):
		await _finish(); return
	# These8 predetermined views are added before the unchanged ordinary zoom
	# sequence. Source vectors, never captured pixels, determine every camera.
	var ordinary_fov: float = _scene.camera.fov
	var ordinary_settings: Dictionary = _scene.camera_view_settings().duplicate(true)
	var paint_frames: Array = _paint_frames()
	if not check(paint_frames.size() == 2,"two_admitted_runway_camera_frames"):
		await _finish(); return
	_receipt.runway_paint_frames = paint_frames.duplicate(true)
	# The retained first attempt refused the impossible actual-segment crossing
	# view. Do not extend endpoints/pavement or reinterpret it as a real crossing.
	_receipt.runway_paint_applicability = {"actual_source_physical_centerline_segments_cross":false,"actual_crossing_views":0,"basis":"Admitted fixed source frames; retained first attempt refused intersection outside11-29 physical segment","retained_first_failure_receipt_sha256":"09f2253b58bd54efe5a10cecf5e3ea4dc03ee601f1b4e90d8ec6bcc07273358c","crossing_winner_evidence":"Separate frozen synthetic board controls only; not an actual-source KAWO crossing or source-fidelity acceptance"}
	for frame in paint_frames:
		for end_index in 2:
			for top in [true,false]:
				var label: String = "number-"+frame.designators[end_index]+("-top" if top else "-inbound")
				if not _number_view(frame,end_index,top) or not await _shot(label,"diagnostic camera-only original prototype physical-end number view; not operational approach guidance"):
					await _finish(); return
	_scene.camera.fov = ordinary_fov
	_ordinary_view(1)
	if not check(Codec._exact(_scene.camera_view_settings(),ordinary_settings),"ordinary_view_policy_restored_before_existing_zoom_sequence"):
		await _finish(); return
	# Twenty-four ordinary paused-view zoom action steps, captured separately.
	# One action per capture after frame0; no imposed frame timing/FPS claim.
	for i in 24:
		if i > 0: _scene.dispatch_input_action("view_zoom_out")
		_scene.show_state(0.0)
		if not check(_scene.camera_distance == 13.0+float(i),"ordinary_zoom_distance_"+str(i)):
			await _finish(); return
		if not await _shot("motion-%02d" % i,"ordinary dispatch_input_action(view_zoom_out), paused camera only; no hardware-input claim",i):
			await _finish(); return
	check(_views.size() == BASE_VIEWS,"eight_original_stills_eight_number_diagnostics_and24_motion_originals")
	check(Codec._exact(_source_rows(),_source_before),"source_product_bytes_unchanged")
	if not _failures.is_empty() or not await _rebase_addendum(paint_frames[0]):
		await _finish(); return
	check(_views.size() == EXPECTED_VIEWS,"original40_plus_three_public_origin_number_views")
	check(Codec._exact(_source_rows(),_source_before),"source_product_bytes_unchanged_after_origin_addendum")
	await _finish()

func _finish() -> void:
	if _scene != null:
		var native_joined: bool = _scene.close_session()
		var audio_joined: bool = true
		if _scene.sound != null: audio_joined = bool(await _scene.sound.shutdown())
		_receipt.native_joined = native_joined
		_receipt.audio_joined = audio_joined
		check(native_joined and audio_joined,"final_actual_native_and_audio_joined")
		if native_joined and audio_joined:
			root.remove_child(_scene)
			_scene.free()
			_scene = null
		else:
			_receipt.retained_unjoined = true
	_receipt.passed = _failures.is_empty() and _views.size() == EXPECTED_VIEWS and _receipt.native_joined and _receipt.audio_joined
	_receipt.failures = _failures
	_receipt.views = _views
	_receipt.source_before = _source_before
	_receipt.scope = "Actual original ViewportImage PNGs of paused KAWO; camera-only diagnostics explicitly labelled. No native advancing, storage, GPU frame-rate, alias/flicker absence, geographic accuracy or pilot acceptance claim. Independent original-image review required."
	if not _output.is_empty():
		var path: String = _output.path_join("capture.json")
		if FileAccess.file_exists(path): check(false,"fresh_capture_receipt_required")
		else:
			var file: FileAccess = FileAccess.open(path,FileAccess.WRITE)
			if file == null: check(false,"capture_receipt_write_failed")
			else: file.store_string(JSON.stringify(_receipt,"  ")); file.close()
	_receipt.passed = _receipt.passed and _failures.is_empty()
	print("KAWO_GPU_CAPTURE_RESULT="+JSON.stringify({"passed":_receipt.passed,"views":_views.size(),"failures":_failures,"native_joined":_receipt.native_joined,"audio_joined":_receipt.audio_joined}))
	if _receipt.get("retained_unjoined",false): return
	await process_frame
	quit(0 if _receipt.passed and _failures.is_empty() else 1)
