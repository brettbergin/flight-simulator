extends RefCounted
# Original MIT. Separate engineering captures; no simulator/schema authority.
const Facade=preload("res://simulation/session_facade.gd")
const SIZES: Array[Vector2i]=[Vector2i(960,540),Vector2i(1920,1080),Vector2i(2560,1440)]
const PRESENTATION: Array[String]=["camera_mode","camera_ready","camera_follow_offset","look_angles","camera_distance","panel_visible","forward_view"]
const SOURCES: Array[String]=["res://instrument_tests/cockpit_visual.gd","res://interactive/flight_cockpit.gd","res://interactive/flight_panel.gd","res://interactive/preview.gd","res://simulation/flight_scene.gd","res://simulation/session_facade.gd","res://simulation/render_origin.gd","res://simulation/origin_participant.gd","res://input/input_mapper.gd","res://cockpit/instruments/native_readings.gd","res://cockpit/instruments/engine_status.gd","res://build/native_identity.gd"]
var _scene: Node
var _output: String=""
var _failures: Array[String]=[]
var _views: Array[Dictionary]=[]
var _sessions: Array[Dictionary]=[]
var _sources_before: Dictionary={}
var _hooks: Array[Dictionary]=[]
var _audio_joined: bool=false
var _gui_before: bool=false
var _window_before: Vector2i

func _check(ok: bool,label: String) -> bool:
	if not ok: _failures.append(label)
	return ok

func _copyable(value: Variant,depth: int=0) -> bool:
	if depth>32 or value is Object or value is Callable or value is Signal: return false
	if value is Array:
		for item in value:
			if not _copyable(item,depth+1): return false
	if value is Dictionary:
		for key in value:
			if not _copyable(key,depth+1) or not _copyable(value[key],depth+1): return false
	return true

func _data(object: Object) -> Dictionary:
	var result: Dictionary={}
	for property in object.get_property_list():
		if (int(property.usage)&PROPERTY_USAGE_SCRIPT_VARIABLE)!=0:
			var value: Variant=object.get(property.name)
			if _copyable(value): result[str(property.name)]=value.duplicate(true) if value is Array or value is Dictionary else value
	return result

func _truth() -> Dictionary:
	var scene_data: Dictionary=_data(_scene)
	for key in PRESENTATION: scene_data.erase(key)
	return {"readback":_scene.facade.readback(),"facade":_data(_scene.facade),"scene":scene_data,
		"mapper":_data(_scene.mapper),"origin":_scene.facade.render_origin.read_origin() if _scene.facade.render_origin!=null else null,
		"recording":_scene.observed_recorder.recording(),"render_pose":_data(_scene.render_pose),
		"map":_data(_scene.flight_map),"world":_scene.world_root.transform,"lighting":_scene.light_root.transform,
		"ownship":_scene.airplane.transform,"cockpit":_scene.cockpit.root.transform}

func _digest(value: Variant) -> String:
	var context: HashingContext=HashingContext.new()
	context.start(HashingContext.HASH_SHA256);context.update(var_to_bytes(value))
	return context.finish().hex_encode()

func _sources() -> Dictionary:
	var result: Dictionary={}
	for path in SOURCES:
		result[path]={"bytes":FileAccess.get_file_as_bytes(path).size(),"sha256":FileAccess.get_sha256(path)}
	return result

func _output_ok(path: String) -> bool:
	if not path.is_absolute_path() or path.begins_with("res://") or path.begins_with("user://"): return false
	var normalized: String=path.replace("\\","/").simplify_path().to_lower().trim_suffix("/")
	for parent in [ProjectSettings.globalize_path("res://"),OS.get_executable_path().get_base_dir()]:
		var forbidden: String=str(parent).replace("\\","/").simplify_path().to_lower().trim_suffix("/")
		if normalized==forbidden or normalized.begins_with(forbidden+"/"): return false
	var directory: DirAccess=DirAccess.open(path)
	if directory==null: return false
	directory.include_hidden=true
	return directory.get_files().is_empty() and directory.get_directories().is_empty()

func _disconnect(signal_value: Signal,callback: Callable) -> void:
	if signal_value.is_connected(callback):
		signal_value.disconnect(callback)
		_hooks.append({"signal":signal_value,"callback":callback})

func _save_presentation() -> Dictionary:
	var fields: Dictionary={}
	for key in PRESENTATION: fields[key]=_scene.get(key)
	return {"fields":fields,"camera":_scene.camera.transform,"fov":_scene.camera.fov,"near":_scene.camera.near,"far":_scene.camera.far,"size":_scene.get_viewport().size}

func _restore_presentation(saved: Dictionary) -> void:
	_scene.set_camera_mode(saved.fields.camera_mode)
	for key in PRESENTATION: _scene.set(key,saved.fields[key])
	_scene.camera.fov=saved.fov
	_scene.show_state(0.0)
	for key in PRESENTATION: _scene.set(key,saved.fields[key])
	_scene.camera.transform=saved.camera
	_scene.camera.near=saved.near;_scene.camera.far=saved.far
	DisplayServer.window_set_size(saved.size)
	_scene.get_viewport().size=saved.size

func _setup(size: Vector2i,mode: int,fov: float,look: Vector2) -> void:
	DisplayServer.window_set_size(size)
	_scene.get_viewport().size=size
	_scene.set_camera_mode(mode)
	_scene.camera.fov=fov
	_scene.look_angles=look
	_scene.show_state(0.0)

func _target() -> Dictionary:
	var viewport: SubViewport=_scene.panel_viewport
	var control: Control=_scene.cockpit_panel
	var texture: Texture2D=viewport.get_texture()
	var format: int=int(RenderingServer.call("texture_get_format",texture.get_rid())) if RenderingServer.has_method("texture_get_format") else -1
	return {"size":[viewport.size.x,viewport.size.y],"texture_size":[texture.get_width(),texture.get_height()],"logical_size":[control.size.x,control.size.y],"scale":[control.scale.x,control.scale.y],"anchors":[control.anchor_left,control.anchor_top,control.anchor_right,control.anchor_bottom],"update_mode":viewport.render_target_update_mode,"exposed_format":format,"rgba8_texel_plane_calculated_bytes":texture.get_width()*texture.get_height()*4,"allocation_scope":"Calculated color texels only; driver attachment/allocation unobserved."}

func _shot(name: String,size: Vector2i,before: Dictionary,fixture: String="actual paused tick0",boundary: bool=false) -> bool:
	var path: String=_output.path_join(name+".png")
	if not _check(not FileAccess.file_exists(path),"fresh_png_"+name): return false
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var image: Image=_scene.get_viewport().get_texture().get_image()
	if not _check(image!=null and image.get_width()==size.x and image.get_height()==size.y,"actual_dimensions_"+name): return false
	if not _check(image.save_png(path)==OK,"png_written_"+name): return false
	var after: Dictionary=_truth()
	if not _check(var_to_bytes(before)==var_to_bytes(after),"full_truth_unchanged_"+name): return false
	var target: Dictionary=_target()
	if not _check(target.size==[2048,1024] and target.texture_size==[2048,1024] and target.logical_size==[1024.0,512.0] and target.scale==[2.0,2.0] and target.anchors==[0.0,0.0,0.0,0.0] and target.update_mode==SubViewport.UPDATE_ALWAYS,"actual_candidate_target_"+name): return false
	if not _check(is_equal_approx(_scene.camera.near,0.1),"unchanged_near_clip_"+name): return false
	var readback: Dictionary=before.readback
	_views.append({"file":name+".png","bytes":FileAccess.get_file_as_bytes(path).size(),"sha256":FileAccess.get_sha256(path),"width":size.x,"height":size.y,
		"mode":_scene.camera_mode,"fov":_scene.camera.fov,"look":[_scene.look_angles.x,_scene.look_angles.y],"camera_transform":_scene.camera.transform,"near":_scene.camera.near,
		"eye":_scene.cockpit.eye,"panel_focus":_scene.cockpit.panel_focus,"target":target,"tick":readback.tick,"session_id":readback.session_id,
		"profile":readback.model_identity,"native_source_fingerprint":readback.native_source_fingerprint,"fixture":fixture,"reading_state":_scene.shared_readings.state,
		"boundary_view":boundary,"boundary_note":"Actual supported look clamps can intentionally turn away from all dial faces; pixels establish clipping/context, not readable by visibility." if boundary else "Forward/default or explicit joined fixture; independent glyph, rim, occlusion and horizon review required.",
		"before":before,"after":after,"before_sha256":_digest(before),"after_sha256":_digest(after)})
	return true

func _live_sequence(label: String,profile: String,start: String,boundaries: bool=false) -> bool:
	if not _check(_scene.restart(true,"calm",profile,start),"legitimate_fresh_"+label): return false
	_scene.menu_open=false;_scene.menu.hide();_scene.map_visible=false;_scene.flight_map.hide()
	_scene.scan_open=false;_scene.scan_panel.clear_focus();_scene.scan_panel.hide()
	_scene.show_state(0.0)
	var before: Dictionary=_truth()
	if not _check(before.readback.native_live and before.readback.paused and before.readback.tick=="0" and not before.readback.historical,"native_paused_tick0_"+label): return false
	var saved: Dictionary=_save_presentation()
	var completed: bool=true
	for size in SIZES:
		for mode in [0,3]:
			_setup(size,mode,72.0 if mode==0 else 58.0,Vector2.ZERO)
			if not await _shot(label+"-"+str(size.x)+("-cockpit" if mode==0 else "-dashboard"),size,before): completed=false;break
		if not completed: break
	if completed and boundaries:
		# Forward zoom evidence is separate from turn-away look-limit evidence.
		for size in [SIZES[0],SIZES[2]]:
			for mode in [0,3]:
				for fov in [35.0,90.0]:
					_setup(size,mode,fov,Vector2.ZERO)
					if not await _shot(label+"-"+str(size.x)+"-mode"+str(mode)+"-zoom"+str(int(fov)),size,before): completed=false;break
				if not completed: break
			if not completed: break
	if completed and boundaries:
		for size in [SIZES[0],SIZES[2]]:
			for mode in [0,3]:
				for high in [false,true]:
					# Exactly the production look handler's admitted endpoints, without
					# dispatching an input event or altering any pilot action.
					var look: Vector2=Vector2(clampf(10.0 if high else -10.0,-PI,PI),clampf(10.0 if high else -10.0,-1.2,1.2))
					_setup(size,mode,90.0 if high else 35.0,look)
					if not await _shot(label+"-"+str(size.x)+"-mode"+str(mode)+("-wide-high" if high else "-narrow-low"),size,before,"actual paused tick0",true): completed=false;break
				if not completed: break
			if not completed: break
	_restore_presentation(saved)
	var after: Dictionary=_truth()
	_check(var_to_bytes(before)==var_to_bytes(after),"full_session_truth_restored_"+label)
	_check(_save_presentation()==saved,"exact_view_restored_"+label)
	_sessions.append({"name":label,"before":before,"after":after,"before_sha256":_digest(before),"after_sha256":_digest(after),"presentation_restored":_save_presentation()==saved})
	return completed and _failures.is_empty()

func _closed_sequence() -> bool:
	# Cache actual live camera poses first. After joining, no show_state() call
	# can replace the explicit invalid fixture or fabricate a native pose.
	var poses: Array[Dictionary]=[]
	for recipe in [{"size":SIZES[0],"mode":0},{"size":SIZES[2],"mode":3}]:
		_setup(recipe.size,recipe.mode,72.0 if recipe.mode==0 else 58.0,Vector2.ZERO)
		poses.append({"size":recipe.size,"mode":recipe.mode,"camera":_scene.camera.transform,"fov":_scene.camera.fov})
	var preclose: Dictionary=_truth()
	var result: Dictionary=_scene.facade.close()
	if not _check(result.ok and not result.readback.native_live and result.readback.historical,"actual_join_before_fixtures"): return false
	_scene.adopt_result(result)
	var native_closed: Dictionary=_scene.facade.readback()
	for invalid in [false,true]:
		for pose in poses:
			DisplayServer.window_set_size(pose.size);_scene.get_viewport().size=pose.size
			_scene.set_camera_mode(pose.mode);_scene.camera.fov=pose.fov;_scene.camera.transform=pose.camera
			var publication: Dictionary=native_closed.duplicate(true)
			if invalid: publication.tick=0.0
			var label: String="invalid" if invalid else "retained"
			_scene.publish_readings(publication,{"status":"SYNTHETIC INVALID DISPLAY ONLY AFTER JOIN" if invalid else "CONFIRMED CLOSED / RETAINED NATIVE TRUTH","paused":false,"view_name":"UNAVAILABLE" if invalid else "RETAINED","historical":not invalid})
			if not _check(_scene.shared_readings.state==("invalid" if invalid else "historical"),"explicit_display_state_"+label): return false
			var before: Dictionary=_truth()
			if not await _shot("cold-"+label+"-"+str(pose.size.x),pose.size,before,"explicit invalid copied display after join" if invalid else "actual retained closed native truth"): return false
			if not _check(_scene.facade.readback()==native_closed,"joined_truth_unchanged_"+label): return false
	_sessions.append({"name":"closed-display-fixtures","before_close":preclose,"joined_readback":native_closed,"after":_truth(),"scope":"Only the copied display tick is malformed after confirmed join; native readback remains exact. Cached real paused camera poses; no fabricated aircraft state."})
	return true

func run(scene: Node) -> void:
	_scene=scene
	_window_before=_scene.get_viewport().size
	_gui_before=_scene.get_viewport().gui_disable_input
	_scene.get_viewport().gui_disable_input=true
	_scene.set_process(false);_scene.set_physics_process(false);_scene.set_process_input(false)
	_scene.set_process_unhandled_input(false);_scene.set_process_unhandled_key_input(false);_scene.set_process_shortcut_input(false)
	_scene.process_mode=Node.PROCESS_MODE_DISABLED
	_disconnect(_scene.get_viewport().focus_exited,Callable(_scene,"on_focus_lost"))
	_disconnect(Input.joy_connection_changed,Callable(_scene,"on_joy_connection_changed"))
	var args: PackedStringArray=OS.get_cmdline_user_args()
	var at: int=args.find("--cockpit-visual-output")
	if at>=0 and at+1<args.size() and args.count("--cockpit-visual-output")==1 and _output_ok(args[at+1]): _output=args[at+1]
	if not _check(not _output.is_empty(),"fresh_absolute_external_output"): await _finish();return
	if not _check(OS.get_name()=="Windows" and DisplayServer.get_name()!="headless" and RenderingServer.get_current_rendering_method()=="gl_compatibility","actual_Windows_Compatibility_GPU"): await _finish();return
	var adapter: String=RenderingServer.get_video_adapter_name().to_lower()
	if not _check(not adapter.is_empty(),"adapter_present"): await _finish();return
	for fallback in ["llvmpipe","softpipe","software","warp","microsoft basic render"]:
		if not _check(not adapter.contains(fallback),"no_software_"+fallback): await _finish();return
	if not _check(_scene.facade!=null and _scene.mapper!=null,"ordinary_owners_present"): await _finish();return
	if _scene.sound!=null: _audio_joined=bool(await _scene.sound.call("shutdown"))
	if not _check(_audio_joined,"audio_retired_before_observation"): await _finish();return
	_sources_before=_sources()
	for path in _sources_before:
		if not _check(_sources_before[path].bytes>0 and str(_sources_before[path].sha256).length()==64,"source_present_"+path): await _finish();return
	if not await _live_sequence("legacy-ground",Facade.LEGACY_PROFILE.id,"ground-ready",true): await _finish();return
	if not await _live_sequence("legacy-airborne",Facade.LEGACY_PROFILE.id,"airborne-prepared"): await _finish();return
	if not await _live_sequence("cold",Facade.PISTON_PROFILE.id,"piston-cold-ground"): await _finish();return
	await _closed_sequence()
	await _finish()

func _finish() -> void:
	var joined: bool=_scene.close_session()
	if _scene.sound!=null: _audio_joined=bool(await _scene.sound.call("shutdown"))
	_check(joined and _audio_joined,"native_and_audio_joined")
	if not _sources_before.is_empty(): _check(_sources_before==_sources(),"source_bytes_unchanged")
	DisplayServer.window_set_size(_window_before);_scene.get_viewport().size=_window_before
	_scene.get_viewport().gui_disable_input=_gui_before
	for hook in _hooks:
		var signal_value: Signal=hook["signal"]
		var callback: Callable=hook["callback"]
		if not signal_value.is_connected(callback): signal_value.connect(callback)
	var result: Dictionary={"passed":_failures.is_empty() and _views.size()==38,"failures":_failures,"views":_views,"sessions":_sessions,"source_before":_sources_before,"source_after":_sources(),"native_joined":joined,"audio_joined":_audio_joined,
		"engine":Engine.get_version_info(),"adapter":RenderingServer.get_video_adapter_name(),"renderer":RenderingServer.get_current_rendering_method(),"editor":OS.has_feature("editor"),
		"scope":"Thirty-eight actual GPU views with legitimate native paused tick0 starts; no Run or pilot submission. Forward zoom and look-limit views are separate. Explicit malformed display only after join. Separate engineering output, no closed Facade/Piston schema, sensed/C172/pilot/performance/phase qualification. Independent glyph/occlusion/horizon review and external module/model/payload hash witnesses required."}
	if not _output.is_empty():
		var receipt: String=_output.path_join("cockpit-visual-receipt.json")
		if not FileAccess.file_exists(receipt):
			var stream: FileAccess=FileAccess.open(receipt,FileAccess.WRITE)
			if stream!=null: stream.store_string(JSON.stringify(result,"  ",false,true));stream.close()
			else: result.passed=false;push_error("Cockpit visual receipt write failed")
		else: result.passed=false;push_error("Fresh cockpit visual receipt required")
	print("COCKPIT_VISUAL_COMPLETE ",JSON.stringify({"passed":result.passed,"views":_views.size(),"native_joined":joined,"audio_joined":_audio_joined}))
	_scene.get_tree().quit(0 if result.passed else 1)
