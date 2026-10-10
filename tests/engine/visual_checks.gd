extends RefCounted
# Original MIT. Explicit Windows GPU observer, never a flight-performance oracle.
const Facade=preload("res://simulation/session_facade.gd")
const SIZES: Array[Vector2i]=[Vector2i(960,540),Vector2i(1920,1080),Vector2i(2560,1440)]
var _scene: Node
var _output: String=""
var _checks: int=0
var _failures: Array[String]=[]
var _views: Array[Dictionary]=[]
var _bounds_seen: Array[Dictionary]=[]
var _history_path: String=""
var _history_sha: String=""

func _check(ok: bool,label: String) -> void:
	_checks+=1
	if not ok: _failures.append(label)
	_scene.check(ok,"piston_visual_"+label)

func _truth() -> Dictionary:
	return {"readback":_scene.facade.readback().duplicate(true),"recording":_scene.observed_recorder.recording(),
		"held":_scene.held_controls.duplicate(true),"systems":_scene.held_systems.duplicate(true),
		"pending_systems":_scene.pending_systems.duplicate(true),"preset":_scene.active_preset.duplicate(true),
		"submitted":_scene.submitted_count,"events":_scene.event_count,"profile":_scene.selected_profile,
		"start":_scene.named_start,"wind":_scene.current_wind_profile,"adopted":_scene.adopted_session_id}

func _settle() -> void:
	await _scene.get_tree().process_frame
	await _scene.get_tree().process_frame

func _bounds(control: Control,label: String) -> void:
	_check(control!=null and control.is_visible_in_tree(),"visible_"+label)
	if control==null or not control.is_visible_in_tree(): return
	var rect: Rect2=control.get_global_rect()
	_check(_scene.get_viewport().get_visible_rect().encloses(rect),"viewport_bounds_"+label)
	var parent: Node=control.get_parent()
	while parent!=null:
		if parent is ScrollContainer:
			_check(parent.get_global_rect().encloses(rect),"scroll_bounds_"+label)
			for bar in [parent.get_h_scroll_bar(),parent.get_v_scroll_bar()]:
				if bar.is_visible_in_tree(): _check(not bar.get_global_rect().intersects(rect),"scrollbar_clear_"+label)
		parent=parent.get_parent()
	_bounds_seen.append({"label":label,"rect":[rect.position.x,rect.position.y,rect.size.x,rect.size.y]})

func _label(node: Node,text: String) -> Label:
	if node is Label and node.text==text: return node
	for child in node.get_children():
		var result: Label=_label(child,text)
		if result!=null: return result
	return null

func _row_bounds(node: Node,label: String) -> void:
	# Check real leaf controls after scrolling; whole viewport bounds alone miss
	# clipped Learn/binding controls inside the Controls scroll viewport.
	if (node is Button or node is Label or node is LineEdit) and node.is_visible_in_tree():
		_bounds(node,label+"_"+str(node.get_index()))
	for child in node.get_children(): _row_bounds(child,label+"_"+str(node.get_index()))

func _shot(name: String,dimensions: Vector2i,before: Dictionary) -> void:
	var path: String=_output.path_join(name+".png")
	_check(not FileAccess.file_exists(path),"fresh_capture_"+name)
	if FileAccess.file_exists(path): return
	# Same actual show_state/two post-draw frames/viewport capture as save_view,
	# with an external output root so no qualified payload byte is ever written.
	_scene.show_state(0.0)
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var rendered: Image=_scene.get_viewport().get_texture().get_image()
	_check(rendered.save_png(path)==OK,"PNG_saved_"+name)
	var image: Image=Image.load_from_file(path)
	_check(image!=null and image.get_width()==dimensions.x and image.get_height()==dimensions.y,"PNG_dimensions_"+name)
	_check(_truth()==before,"display_preserves_native_controls_recording_"+name)
	_views.append({"file":name+".png","sha256":FileAccess.get_sha256(path),"width":dimensions.x,"height":dimensions.y,
		"native_tick":before.readback.tick,"session_id":before.readback.session_id,"profile":before.profile,
		"native_source_fingerprint":before.readback.native_source_fingerprint,"display_fixture":false})

func _strips(dimensions: Vector2i,label: String) -> void:
	# Independently check occupied strips/map regions; PNG review still decides
	# glyph clipping, contrast and whether the cockpit/dashboard is readable.
	var viewport:=Rect2(Vector2.ZERO,Vector2(dimensions))
	var controls:=Rect2(10,51,dimensions.x-20,34)
	var engine:=Rect2(10,90,dimensions.x-20,54)
	var instruments:=Rect2(12,dimensions.y-minf(dimensions.y*0.34,455.0),dimensions.x-24,minf(dimensions.y*0.34,455.0))
	_check(viewport.encloses(controls) and viewport.encloses(engine),"strip_bounds_"+label)
	_check(not controls.intersects(engine) and not engine.intersects(instruments),"strips_do_not_overlap_controls_or_instruments_"+label)
	_check(_scene.panel.get("_info").get("engine_status")==_scene.engine_status,"overlay_copies_actual_engine_status_"+label)
	_check(_scene.cockpit_panel.get("_info").get("engine_status")==_scene.engine_status,"dashboard_copies_actual_engine_status_"+label)
	_check(_scene.panel.call("_engine_phase")=="STOPPED","actual_cold_stopped_label_"+label)
	if _scene.flight_map.visible:
		_bounds(_scene.flight_map,label+"_map")
		_check(_scene.flight_map.get_global_rect().position.y>=engine.end.y,"map_below_engine_strip_"+label)

func _prepare_history() -> void:
	var bytes: PackedByteArray=FileAccess.get_file_as_bytes("res://engine_tests/reference/minimal.fsreview.json")
	_check(not bytes.is_empty(),"staged_legacy_history_present")
	_history_path=_output.path_join("piston-visual-history-"+str(OS.get_process_id())+"-"+str(Time.get_ticks_usec())+".fsreview.json")
	_check(not FileAccess.file_exists(_history_path),"fresh_owned_history_copy")
	if FileAccess.file_exists(_history_path): _history_path="";return
	var stream:=FileAccess.open(_history_path,FileAccess.WRITE)
	_check(stream!=null,"owned_history_copy_open")
	if stream==null: _history_path="";return
	stream.store_buffer(bytes);stream.close()
	_history_sha=FileAccess.get_sha256(_history_path)
	_check(FileAccess.get_file_as_bytes(_history_path)==bytes,"owned_history_copy_exact")

func _reject_output(message: String) -> void:
	# An unsafe/freshness failure must never write a receipt into that directory.
	_check(false,"external_output_admission")
	push_error(message)
	var joined: bool=_scene.close_session()
	if _scene.sound!=null: joined=bool(await _scene.sound.shutdown()) and joined
	print("PISTON_VISUAL_OUTPUT_REJECTED ",JSON.stringify({"error":message,"native_and_audio_joined":joined,"failures":_failures}))
	_scene.get_tree().quit(1)

func run(scene: Node,output_directory: String="") -> void:
	_scene=scene
	if output_directory.is_empty():
		var args: PackedStringArray=OS.get_cmdline_user_args()
		if args.size()!=3 or args[0]!="--piston-visual-smoke" or args[1]!="--piston-visual-output":
			await _reject_output("Expected --piston-visual-smoke --piston-visual-output <fresh absolute external directory>")
			return
		output_directory=args[2]
	if not output_directory.is_absolute_path() or output_directory.begins_with("res://") or output_directory.begins_with("user://"):
		await _reject_output("Visual output must be an absolute external filesystem directory")
		return
	var payload_root: String=OS.get_executable_path().get_base_dir().replace("\\","/").simplify_path().to_lower()
	var output_root: String=output_directory.replace("\\","/").simplify_path().to_lower().trim_suffix("/")
	if output_root==payload_root or output_root.begins_with(payload_root+"/"):
		await _reject_output("Visual output must remain outside the exported payload")
		return
	var directory:=DirAccess.open(output_directory)
	if directory==null:
		await _reject_output("Fresh externally prepared visual output directory required")
		return
	directory.include_hidden=true
	if not directory.get_files().is_empty() or not directory.get_directories().is_empty():
		await _reject_output("Visual output directory must be empty; preserve previous evidence")
		return
	_output=output_directory
	_check(not OS.has_feature("editor"),"actual_export_required")
	_check(not _scene.is_processing(),"scene_automatic_advancement_disabled")
	if OS.has_feature("editor") or _scene.is_processing():
		await _finish();return
	_check(OS.get_name()=="Windows" and DisplayServer.get_name()!="headless","requires_actual_Windows_GPU_window")
	if OS.get_name()!="Windows" or DisplayServer.get_name()=="headless":
		await _finish();return
	var adapter: String=RenderingServer.get_video_adapter_name()
	_check(not adapter.is_empty(),"reported_GPU_adapter")
	for fallback in ["llvmpipe","softpipe","software","warp","microsoft basic render"]:
		_check(not adapter.to_lower().contains(fallback),"no_known_software_adapter_"+fallback)
	_prepare_history()
	for dimensions in SIZES:
		_scene.get_window().size=dimensions
		await _settle()
		var prefix: String="piston-"+str(dimensions.x)
		var fresh: bool=_scene.restart(true,"calm",Facade.PISTON_PROFILE.id,"piston-cold-ground")
		_check(fresh,"actual_fresh_cold_"+prefix)
		if not fresh:
			await _finish()
			return
		_check(_scene.pause_session(true),"actual_pause_"+prefix)
		_scene.menu_open=false;_scene.menu.hide()
		_scene.map_visible=true;_scene.flight_map.show()
		_scene.show_state(0.0)
		var before: Dictionary=_truth()
		_check(before.readback.tick=="0" and before.readback.native_live and before.readback.paused and not before.readback.historical,"actual_live_paused_tick0_"+prefix)
		_check(before.profile==Facade.PISTON_PROFILE.id and before.wind=="calm" and before.recording.state=="empty" and before.recording.samples.is_empty(),"cold_profile_no_recording_"+prefix)
		for camera in [{"id":1,"name":"exterior-overlay"},{"id":2,"name":"exterior-clear"},{"id":0,"name":"cockpit"},{"id":3,"name":"dashboard"}]:
			_scene.set_camera_mode(camera.id)
			_scene.map_visible=camera.id==1;_scene.flight_map.visible=_scene.map_visible
			if camera.id==2:
				_scene.panel_visible=false;_scene.panel.set_panel_visible(false)
			_scene.show_state(0.0)
			_strips(dimensions,prefix+"_"+camera.name)
			await _shot(prefix+"-"+camera.name,dimensions,before)
		_scene.set_camera_mode(1)
		_scene.open_menu("Cold-engine prototype / paused")
		await _shot(prefix+"-aircraft-menu",dimensions,before)
		_bounds(_scene.profile_button,prefix+"_aircraft_button")
		_bounds(_scene.resume_button,prefix+"_resume_button")
		_check(_scene.profile_button.text.contains("cold piston prototype"),"actual_selected_profile_label_"+prefix)
		# At tick0 there is no legacy recording to discard; pressing Aircraft
		# commits a fresh profile immediately. Observe its real label, do not click
		# it or fabricate a confirmation panel over this unchanged cold session.
		_scene.open_controls()
		await _settle()
		_check(_scene.controls_panel.get("_v2") and _scene.controls_panel.get_draft()==_scene.active_preset,"actual_version2_controls_draft_"+prefix)
		var list: Control=_scene.controls_panel.get("_list")
		var scroll: ScrollContainer=list.get_parent() as ScrollContainer
		_check(scroll!=null,"actual_controls_scroll_container_"+prefix)
		if scroll!=null:
			scroll.scroll_horizontal=0;scroll.scroll_vertical=0
			await _settle()
		await _shot(prefix+"-controls-top",dimensions,before)
		_bounds(_scene.controls_panel.get("_apply_button"),prefix+"_apply")
		_bounds(_scene.controls_panel.get("_name"),prefix+"_preset_name")
		var mixture: Label=_label(list,"MIXTURE")
		_check(mixture!=null and scroll!=null,"mixture_row_present_"+prefix)
		if mixture!=null and scroll!=null:
			var section: Control=mixture.get_parent().get_parent()
			scroll.ensure_control_visible(section)
			await _settle()
			_row_bounds(section,prefix+"_mixture")
		await _shot(prefix+"-controls-mixture",dimensions,before)
		var system_rows: Array[Control]=[]
		for id in ["engine.ignition_left","engine.ignition_right","engine.starter","fuel.feed"]:
			var label: Label=_label(list,id)
			_check(label!=null,"engine_binding_present_"+prefix+"_"+id)
			if label!=null: system_rows.append(label.get_parent())
		if scroll!=null and system_rows.size()==4:
			for index in system_rows.size():
				scroll.ensure_control_visible(system_rows[index])
				await _settle()
				_row_bounds(system_rows[index],prefix+"_system_"+str(index))
				if index==0: await _shot(prefix+"-controls-engine-top",dimensions,before)
				if index==3: await _shot(prefix+"-controls-engine-bottom",dimensions,before)
		_scene.dismiss_controls()
		_scene.open_observed_review()
		_check(_scene.review_open and _scene.observed_panel.get("_file_message").text.contains("Cold-engine flight recording is unavailable"),"actual_current_review_unavailable_"+prefix)
		await _shot(prefix+"-review-unavailable",dimensions,before)
		_bounds(_scene.observed_panel.get("_file_message"),prefix+"_recording_limit")
		_check(not _scene.begin_archive_operation("save",false),"actual_cold_save_rejected_"+prefix)
		_check(not _history_path.is_empty() and _scene.begin_archive_operation("open",false),"actual_historical_open_gate_"+prefix)
		if not _history_path.is_empty() and not _scene.archive_operation.is_empty():
			var opened: Dictionary=_scene.finish_archive_operation(_history_path)
			_check(opened.ok and _scene.archive_imported,"actual_opened_staged_legacy_history_"+prefix)
		_check(_scene.observed_panel.get("_file_message").text.contains("Opened historical file"),"historical_warning_not_current_flight_"+prefix)
		await _shot(prefix+"-review-historical",dimensions,before)
		for key in ["_file_message","_back","_open_file","_save_file"]: _bounds(_scene.observed_panel.get(key),prefix+"_historical"+key)
		_scene.dismiss_observed_review()
		_check(_truth()==before,"all_UI_views_preserve_cold_truth_"+prefix)
		var closed: Dictionary=_scene.facade.close()
		_check(closed.ok and not closed.readback.native_live,"actual_worker_joined_"+prefix)
		_scene.adopt_result(closed)
	_check(_views.size()==33,"exact_33_GPU_views")
	await _finish()

func _finish() -> void:
	var joined: bool=_scene.close_session()
	if _scene.sound!=null: joined=bool(await _scene.sound.shutdown()) and joined
	_check(joined,"all_native_and_audio_joined")
	if not _history_path.is_empty():
		_check(FileAccess.get_sha256(_history_path)==_history_sha,"owned_history_unchanged_before_removal")
		if FileAccess.get_sha256(_history_path)==_history_sha: _check(DirAccess.remove_absolute(_history_path)==OK,"owned_history_removed")
	var path: String=_output.path_join("piston-visual-receipt.json")
	_check(not FileAccess.file_exists(path),"fresh_receipt")
	var result: Dictionary={"schema":"PistonVisualChecks/v1","passed":_failures.is_empty() and _scene.failures.is_empty(),"checks":_checks,"failures":_failures.duplicate(),"host_failures":_scene.failures.duplicate(),
		"scope":"33 actual Windows GPU views, fresh calm paused cold tick0 only, real Aircraft menu/version2 scroll controls/unavailable current review and staged historical file. No native advancement, calibration, pilot, hardware or phase acceptance. PNG legibility requires independent visual review.",
		"context":"editor" if OS.has_feature("editor") else "exported","display_server":DisplayServer.get_name(),"video_adapter":RenderingServer.get_video_adapter_name(),
		"windows":[[960,540],[1920,1080],[2560,1440]],"views":_views.duplicate(true),"bounds":_bounds_seen.duplicate(true),"staged_historical_fixture_sha256":_history_sha,"native_and_audio_joined":joined}
	if not FileAccess.file_exists(path):
		var file:=FileAccess.open(path,FileAccess.WRITE)
		if file!=null: file.store_string(JSON.stringify(result,"  "));file.close()
		else: _scene.check(false,"piston_visual_receipt_write_failed")
	print("PISTON_VISUAL_SMOKE ",JSON.stringify(result))
	_scene.get_tree().quit(0 if result.passed and _scene.failures.is_empty() else 1)
