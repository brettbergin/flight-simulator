extends RefCounted
# Original MIT. Explicit GPU observer only; actual paused synthetic starts.
const Cue=preload("res://world/wind/wind_cue.gd")
const PROFILES: Array[String]=["calm","from-north","from-west","from-east"]
var _scene: Node
var _checks: int=0
var _failures: Array[String]=[]
var _views: Array[Dictionary]=[]

func _check(ok: bool, label: String) -> void:
	_checks+=1
	if not ok: _failures.append(label)
	_scene.check(ok,"wind_visual_"+label)

func _truth() -> Dictionary:
	return {"readback":_scene.facade.readback(),"recording":_scene.observed_recorder.recording(),"held":_scene.held_controls.duplicate(true),"submitted":_scene.submitted_count,"events":_scene.event_count,"accepted":_scene.current_wind_profile}

func _measure(name: String, dimensions: Vector2i, fixture: bool=false) -> void:
	var path: String=_scene.output_directory().path_join(name+".png")
	var image: Image=Image.load_from_file(path)
	_check(image!=null and image.get_width()==dimensions.x and image.get_height()==dimensions.y,"dimensions_"+name)
	var state: Dictionary=_scene.facade.readback()
	_views.append({"file":name+".png","width":dimensions.x,"height":dimensions.y,"wind_profile":_scene.current_wind_profile,"native_tick":state.tick,"session_id":state.session_id,"display_fixture":fixture})

func _shot(name: String, dimensions: Vector2i) -> void:
	await _scene.save_view(name)
	_measure(name,dimensions)

func _display_shot(name: String, dimensions: Vector2i) -> void:
	# save_view republishes actual truth; this one intentionally captures a
	# conspicuously labeled invalid view without overwriting it with show_state.
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var image: Image=_scene.get_viewport().get_texture().get_image()
	_check(image.save_png(_scene.output_directory().path_join(name+".png"))==OK,"PNG_saved_"+name)
	_measure(name,dimensions,true)

func _visible_bounds(control: Control, dimensions: Vector2i, name: String) -> void:
	_check(Rect2(Vector2.ZERO,Vector2(dimensions)).encloses(control.get_global_rect()),"bounds_"+name)
	# Viewport containment alone misses children clipped by a scroll viewport.
	var ancestor: Node=control.get_parent()
	while ancestor!=null:
		if ancestor is ScrollContainer:
			_check(ancestor.get_global_rect().encloses(control.get_global_rect()),"scroll_bounds_"+name)
		ancestor=ancestor.get_parent()

func _warning(node: Node) -> Label:
	if node is Label and node.text=="Saved reviews do not retain wind setup or resume a flight": return node
	for child in node.get_children():
		var found: Label=_warning(child)
		if found!=null: return found
	return null

func run(scene: Node) -> void:
	_scene=scene
	var empty_failures: Array[String]=[]
	_scene.failures=empty_failures
	if DisplayServer.get_name()=="headless":
		_check(false,"requires_actual_GPU_window")
		_write_receipt()
		_scene.get_tree().quit(1)
		return
	var sizes: Array[Vector2i]=[Vector2i(960,540),Vector2i(1920,1080),Vector2i(2560,1440)]
	for dimensions in sizes:
		_scene.get_window().size=dimensions
		await _scene.get_tree().process_frame
		await _scene.get_tree().process_frame
		var prefix: String="wind-"+str(dimensions.x)
		for profile in PROFILES:
			_scene.perform_start("ground-ready",profile)
			_check(_scene.facade!=null and _scene.current_wind_profile==profile,"actual_start_"+prefix+"_"+profile)
			_check(_scene.pause_session(true),"actual_pause_"+prefix+"_"+profile)
			_scene.menu_open=false;_scene.menu.hide()
			_scene.map_visible=true;_scene.flight_map.show()
			_scene.set_camera_mode(1)
			_scene.show_state(0.0)
			var baseline: Dictionary=_truth()
			var cue: Dictionary=Cue.from_readback(baseline.readback)
			_check(cue.state=="paused" and baseline.readback.tick=="0","actual_paused_tick0_"+prefix+"_"+profile)
			_check(_scene.flight_map.get("_wind_cue")==cue,"map_copies_native_cue_"+prefix+"_"+profile)
			_check(_scene.windsock_visual.visible,"sock_visible_"+prefix+"_"+profile)
			if cue.speed_mps>0.0:
				var flow: Array=cue.wind_toward_airfield_eus_mps
				var largest: float=maxf(absf(flow[0]),absf(flow[2]))
				var direction:=Vector3(flow[0]/largest,0.0,flow[2]/largest).normalized()
				_check((-_scene.windsock_visual.basis.y).dot(direction)>0.99999,"sock_downstream_"+prefix+"_"+profile)
			await _shot(prefix+"-"+profile+"-paused",dimensions)
			_visible_bounds(_scene.wind_label,dimensions,prefix+"_"+profile+"_native_label")
			var overlay_top: float=dimensions.y-minf(dimensions.y*0.34,455.0)
			_check(_scene.wind_label.get_global_rect().end.y<overlay_top,"label_above_instruments_"+prefix+"_"+profile)
			# The observer moves only the render camera, never the airplane/native
			# point. Camera coordinates are the unchanged prepared-anchor EUS.
			await _scene.save_environment_view(prefix+"-"+profile+"-sock",Vector3(-63,11,94),Vector3(-52,6.1,80))
			_measure(prefix+"-"+profile+"-sock",dimensions)
			_check(_truth()==baseline,"paused_views_preserve_native_recording_"+prefix+"_"+profile)
			_scene.set_camera_mode(1)
			_scene.show_state(0.0)
		var before: Dictionary=_truth()
		_scene.open_wind()
		_scene.select_wind_draft("from-west")
		_scene.show_state(0.0)
		_check(_scene.wind_panel.visible and _scene.current_wind_profile=="from-east" and _scene.wind_draft=="from-west","current_draft_distinct_"+prefix)
		_check(_scene.wind_panel.get("_choice").selected==2 and _scene.wind_panel.get("_current").text.contains("Accepted setup: from-east"),"chooser_labels_match_actual_and_draft_"+prefix)
		await _shot(prefix+"-chooser",dimensions)
		for key in ["_choice","_current","_ground","_airborne","_back"]:
			_visible_bounds(_scene.wind_panel.get(key),dimensions,prefix+"_chooser_"+key)
		_check(_truth()==before,"draft_chooser_no_native_mutation_"+prefix)
		_scene.dismiss_wind()
		_scene.menu_open=false;_scene.menu.hide()
		_check(_scene.pause_session(false) and _scene.advance_wall_us(25000) and _scene.pause_session(true),"three_explicit_native_ticks_"+prefix)
		_scene.show_state(0.0)
		before=_truth()
		_check(before.readback.tick=="3","discard_setup_tick3_"+prefix)
		_scene.open_wind()
		_scene.start_wind_draft("ground-ready")
		_check(not _scene.pending_discard.is_empty() and _scene.get_viewport().gui_get_focus_owner()==_scene.discard_cancel,"default_cancel_"+prefix)
		await _shot(prefix+"-discard",dimensions)
		_visible_bounds(_scene.discard_cancel,dimensions,prefix+"_cancel")
		_visible_bounds(_scene.discard_accept,dimensions,prefix+"_discard")
		var escape:=InputEventKey.new()
		escape.pressed=true;escape.physical_keycode=KEY_ESCAPE
		_scene._unhandled_key_input(escape)
		_check(_scene.pending_discard.is_empty() and _truth()==before,"cancel_preserves_current_native_and_recording_"+prefix)
		_scene.dismiss_wind()
		_scene.open_observed_review()
		await _shot(prefix+"-saved-review-warning",dimensions)
		var warning: Label=_warning(_scene.observed_panel)
		_check(warning!=null and warning.is_visible_in_tree(),"saved_review_limit_visible_"+prefix)
		if warning!=null:_visible_bounds(warning,dimensions,prefix+"_saved_review_limit")
		_check(_truth()==before,"review_warning_no_native_mutation_"+prefix)
		_scene.dismiss_observed_review()
		var closed: Dictionary=_scene.facade.close()
		_check(closed.ok and not closed.readback.native_live,"actual_worker_closed_"+prefix)
		_scene.adopt_result(closed)
		_check(_scene.ensure_review_boundary(),"closed_boundary_confirmed_"+prefix)
		_scene.menu_open=false;_scene.menu.hide()
		await _shot(prefix+"-retained",dimensions)
		before=_truth()
		_check(_scene.flight_map.get("_wind_cue").state=="historical" and not _scene.windsock_visual.visible and _scene.wind_label.text.contains("Retained historical wind"),"retained_label_no_current_sock_"+prefix)
		_scene.update_wind_presentation({})
		_scene.wind_label.text="SYNTHETIC INVALID WIND VIEW FIXTURE\nWind unavailable / actual native worker joined"
		await _display_shot(prefix+"-unavailable",dimensions)
		_check(_scene.flight_map.get("_wind_cue").state in ["invalid","empty"] and not _scene.windsock_visual.visible,"invalid_suppresses_guidance_"+prefix)
		_check(_truth()==before,"display_fixture_preserves_joined_native_recording_"+prefix)
	_check(_views.size()==39,"exact_39_views")
	var joined: bool=_scene.close_session()
	if _scene.sound!=null:joined=bool(await _scene.sound.shutdown()) and joined
	_check(joined,"native_and_audio_joined")
	_write_receipt()
	_scene.get_tree().quit(0 if _failures.is_empty() and _scene.failures.is_empty() else 1)

func _write_receipt() -> void:
	var result: Dictionary={"passed":_failures.is_empty() and _scene.failures.is_empty(),"checks":_checks,"failures":_failures.duplicate(),"host_failures":_scene.failures.duplicate(),"scope":"39 bounded GPU views: four actual paused ground presets and camera-only windsock observers at each of three sizes; current/draft, default Cancel, actual joined retained state, explicitly synthetic invalid display and saved-review setup limitation. Only3 actual ticks per size; no human/device/aircraft/phase qualification.","context":"editor" if OS.has_feature("editor") else "exported","windows":[[960,540],[1920,1080],[2560,1440]],"views":_views.duplicate(true)}
	var file:=FileAccess.open(_scene.output_directory().path_join("wind-visual-receipt.json"),FileAccess.WRITE)
	if file==null:
		_scene.check(false,"wind_visual_receipt_write_failed")
		return
	file.store_string(JSON.stringify(result,"  "));file.close()
	print("WIND_VISUAL_SMOKE ",JSON.stringify(result))
