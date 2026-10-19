extends SceneTree
# Private actual GPU decoration capture. No aircraft/terrain/physics/provider overrides.
const Scene = preload("res://simulation/flight_scene.gd")
const Codec = preload("res://replay/observed_archive/codec.gd")
const SIZE = Vector2i(1280,720)
const PAYLOAD = "b2c53308fdc427900d84b541aff51ba66cbb71bc483fcee0ea16d067dbd15cfb"
const SOURCES = ["res://kawo_gpu_capture.gd","res://simulation/flight_scene.gd","res://simulation/session_facade.gd","res://simulation/render_origin.gd","res://simulation/canonical_frames.gd","res://camera/view_policy.gd","res://world/world_admission.gd","res://world/terrain/resident_grid_reader.gd","res://world/terrain/kawo_world.gd","res://interactive/preview.gd","res://interactive/flight_world.gd","res://interactive/flight_map.gd","res://build/native_identity.gd","res://worlds/kawo-prototype-v1/ground.fgrd","res://worlds/kawo-prototype-v1/compile-receipt.json"]
const DECORATION_SOURCES = ["res://world/decoration/kawo_evergreens.gd","res://environment/original-evergreens-v1/tall-narrow-lod1.glb","res://environment/original-evergreens-v1/broad-tiered-lod1.glb","res://environment/original-evergreens-v1/irregular-mature-lod1.glb"]
const EXPECTED_VIEWS = 32

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

func _camera() -> Dictionary:
	var t: Transform3D = _scene.camera.transform
	return {"position":[t.origin.x,t.origin.y,t.origin.z],"basis_columns":[[t.basis.x.x,t.basis.x.y,t.basis.x.z],[t.basis.y.x,t.basis.y.y,t.basis.y.z],[t.basis.z.x,t.basis.z.y,t.basis.z.z]],"mode":_scene.camera_mode,"settings":_scene.camera_view_settings(),"distance_m":_scene.camera_distance,"look_rad":[_scene.look_angles.x,_scene.look_angles.y],"near_m":_scene.camera.near,"far_m":_scene.camera.far}

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
	_views.append({"file":name+".png","bytes":FileAccess.get_file_as_bytes(path).size(),"sha256":FileAccess.get_sha256(path),"width":image.get_width(),"height":image.get_height(),"image_format":image.get_format(),"camera":_camera(),"capture_kind":mode,"sequence_index":sequence_index,"tick":after.readback.tick,"session_id":after.readback.session_id,"prepared_world_sha256":after.readback.prepared_world_sha256,"world_binding":after.world_source,"decoration_binding":after.decoration.source,"decoration_count":after.decoration.placement.count,"decoration_placement_sha256":_digest(after.decoration.placement),"decoration_state_sha256":_digest(after.decoration),"authority_before_sha256":_digest(_before),"authority_after_sha256":_digest(after),"captured_monotonic_usec":Time.get_ticks_usec()})
	return true

func _ordinary_view(mode: int) -> void:
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
	_ordinary_view(1)
	# Twenty-four ordinary paused-view zoom action steps, captured separately.
	# One action per capture after frame0; no imposed frame timing/FPS claim.
	for i in 24:
		if i > 0: _scene.dispatch_input_action("view_zoom_out")
		_scene.show_state(0.0)
		if not check(_scene.camera_distance == 13.0+float(i),"ordinary_zoom_distance_"+str(i)):
			await _finish(); return
		if not await _shot("motion-%02d" % i,"ordinary dispatch_input_action(view_zoom_out), paused camera only; no hardware-input claim",i):
			await _finish(); return
	check(_views.size() == EXPECTED_VIEWS,"eight_original_stills_and24_motion_originals")
	check(Codec._exact(_source_rows(),_source_before),"source_product_bytes_unchanged")
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
