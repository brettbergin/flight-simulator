extends "res://first_flight_scene_tests/visual_checks.gd"
## Original MIT. Opt-in ADR019 original-image observer, not pixel acceptance.
## Root stages this script/base/source closure, owns watchdog, review and quit.
## Actual PAUSED tick0 views expose ordinary presentation without Resume/Run.

var _layout_closed_witnesses: Array[Dictionary] = []

func _sources() -> Dictionary:
	var result: Dictionary = super._sources()
	for path in ["res://first_flight_scene_tests/visual_checks.gd","res://cockpit/engine_controls.gd",get_script().resource_path]:
		result[path]={"bytes":FileAccess.get_file_as_bytes(path).size(),"sha256":FileAccess.get_sha256(path)}
	return result

func _bound_map_toggle(label: String) -> bool:
	# Pure admission against the actual configured key source, followed by the
	# production action dispatcher. No physical event/device polling or mapper
	# sample is claimed; the sole collector override remains full released Raw.
	var preset: Dictionary = _scene.active_preset.duplicate(true)
	# Both actual profile presets keep their own closed-shape admission. Unknown
	# versions/types fail before reading bindings, constructing Raw or dispatch.
	if not _check(typeof(preset.get("version"))==TYPE_INT and preset.version in [1,2],"supported_map_toggle_preset_version_"+label): return false
	var checked: Dictionary = Scene.Preset.validate_preset_v2(preset) if preset.version==2 else Scene.Preset.validate_preset(preset)
	if not _check(checked.ok,"valid_map_toggle_preset_"+label): return false
	var selected: Dictionary = {}
	for action in preset.actions:
		if action.id!="map_toggle": continue
		for source in action.sources:
			if source.kind=="physical_keys" and not source.keys.is_empty():
				selected=source.duplicate(true)
				break
		break
	if not _check(not selected.is_empty(),"actual_configured_map_toggle_key_source_"+label): return false
	var released: Dictionary = _scene.collect_input_raw()
	var pressed: Dictionary = released.duplicate(true)
	pressed["keys"]=[int(selected.keys[0])]
	if not _check(Scene.Preset.validate_raw(released).ok and Scene.Preset.validate_raw(pressed).ok,"complete_valid_map_toggle_raw_"+label): return false
	if not _check(not Scene.Mapper.action_pressed(preset,released,"map_toggle") and Scene.Mapper.action_pressed(preset,pressed,"map_toggle"),"actual_bound_map_toggle_admission_"+label): return false
	var authority: PackedByteArray = var_to_bytes(_authority())
	var previous: bool = _scene.map_visible
	_scene.dispatch_input_action("map_toggle")
	var unchanged: bool = var_to_bytes(_authority())==authority
	var toggled: bool = _scene.map_visible!=previous and _scene.flight_map.visible==_scene.map_visible
	_map_toggles.append({"label":label,"preset_version":preset.version,"source":selected,"pressed_raw":pressed,"released_raw":released,
		"map_before":previous,"map_after":_scene.map_visible,"full_authority_unchanged":unchanged,
		"bound_action":"map_toggle","delivery":"pure configured binding admission then actual Scene action dispatch; no physical event or mapper sample"})
	_check(unchanged,"bound_map_toggle_preserves_full_authority_"+label)
	return _check(toggled,"bound_map_toggle_changes_actual_visibility_"+label) and unchanged


func _authority() -> Dictionary:
	if _scene.facade!=null: return super._authority()
	# Actual Scene.close_session joins then drops its facade. Never substitute
	# the separately retained CLOSED source as a current Scene readback.
	return {"readback":{},"facade":null,"mapper":_data(_scene.mapper),"origin":null,
		"recording":_scene.observed_recorder.recording(),"held_controls":_scene.held_controls.duplicate(true),
		"held_systems":_scene.held_systems.duplicate(true),"pending_systems":_scene.pending_systems.duplicate(true),
		"submitted_count":_scene.submitted_count,"event_count":_scene.event_count}

func _label_detail(label: Label) -> Dictionary:
	var row: Dictionary = _rect(label)
	if label==null: return row
	row.merge({"text":label.text,"tooltip":label.tooltip_text,"font_size":label.get_theme_font_size("font_size"),
		"line_count":label.get_line_count(),"line_height":label.get_line_height(),"minimum_size":label.get_minimum_size(),
		"autowrap":label.autowrap_mode,"overrun":label.text_overrun_behavior})
	return row

func _layout() -> Dictionary:
	var result: Dictionary = super._layout()
	var engine: Control = _scene.engine_controls
	var hit_regions: Dictionary = {}
	for id in engine._rects():
		hit_regions[id]={"rect":engine._rects()[id],"track":engine._track(id) if id in engine.AXES else Rect2(),
			"actual":engine._actual(id),"request":engine._requested(id),"reason":engine._control_reason(id)}
	result.merge({"engine":_rect(engine),"engine_expanded":engine.is_expanded(),"engine_hits":hit_regions,
		"engine_status":_label_detail(engine._status_label),"engine_footer":engine._compact_look_text(),
		"engine_tooltip":engine.tooltip_text,"release":_label_detail(_scene.look_release_label),
		"wind_card":_rect(_scene.wind_card),"wind_label":_label_detail(_scene.wind_label),
		"panel_feedback":_scene.panel._engine_feedback_layout(),"cockpit_feedback":_scene.cockpit_panel._engine_feedback_layout(),
		"panel_requested_visible":_scene.panel._panel_visible,"help_requested_visible":_scene.panel._help_visible,
		"map_rows":_scene.flight_map._presentation_rows(),"map_labels":_label_rows(_scene.flight_map),
		"map_manual_summary":_scene.flight_map.renders_manual_summary(),"map_tooltip":_scene.flight_map.tooltip_text,
		"board_title":_label_detail(_scene.landmark_board._title),"board_metrics":_label_detail(_scene.landmark_board._metrics),
		"board_itinerary":_label_detail(_scene.landmark_board._leg_text),"board_footer":_label_detail(_scene.landmark_board._state)})
	return result

func _truth() -> Dictionary:
	var result: Dictionary = super._truth()
	result["actual_layout_and_labels"]=_layout()
	return result

func _shot(name: String, dimensions: Vector2i, phase: String) -> void:
	_scene.show_state(0.0)
	var before: Dictionary = _truth()
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var image: Image = _window.get_texture().get_image()
	var path: String = _output.path_join(name+".png")
	var saved: bool = false
	if _check(image!=null and image.get_size()==dimensions,"actual_pixel_dimensions_"+name) and _check(not FileAccess.file_exists(path),"fresh_png_"+name):
		saved=_check(image.save_png(path)==OK,"saved_png_"+name)
	var after: Dictionary = _truth()
	_check(var_to_bytes(before)==var_to_bytes(after),"full_truth_and_layout_unchanged_during_capture_"+name)
	var before_file: Dictionary = _truth_file(name+".before.truth",before)
	var after_file: Dictionary = _truth_file(name+".after.truth",after)
	_check(not before_file.is_empty() and before_file.get("sha256")==after_file.get("sha256") and before_file.get("bytes")==after_file.get("bytes"),"saved_truth_pair_exact_"+name)
	var current: Dictionary = _scene.facade.readback() if _scene.facade!=null else {}
	_views.append({"file":name+".png","saved":saved,"bytes":FileAccess.get_file_as_bytes(path).size() if saved else 0,
		"sha256":FileAccess.get_sha256(path) if saved else "","requested_window":[dimensions.x,dimensions.y],
		"actual_window":[_window.size.x,_window.size.y],"phase":phase,"camera_mode":_scene.camera_mode,
		"current_scene_readback":current,"source_state":"actual-paused-tick0" if not current.is_empty() else "actual-worker-joined-missing-host-empty-source",
		"readings":_scene.shared_readings.duplicate(true),"truth_before_file":before_file,"truth_after_file":after_file,
		"layout":_layout(),"route_view":_scene.route_view.duplicate(true),"raw":_scene.collect_input_raw(),
		"bounds_are_not_pixel_acceptance":true})

func _settle_layout() -> void:
	_scene.show_state(0.0)
	await _host.get_tree().process_frame
	await _host.get_tree().process_frame
	_scene.show_state(0.0)
	await _host.get_tree().process_frame

func _ordinary_paused() -> void:
	# TEST-ONLY presentation exposure, exactly as the headless Scene matrix.
	# No native lifecycle/source rewrite, Resume, time interval or Run occurs.
	if _scene.first_flight_open: _back()
	_scene.menu_open=false
	_scene.menu.hide()
	await _settle_layout()

func _choose_profile(profile: String) -> bool:
	_scene.open_first_flight()
	if not _check(_scene.first_flight_open,"layout_actual_choice_owner_"+profile): return false
	_scene.first_flight_panel._choice_buttons[0 if profile==Scene.Facade.PISTON_PROFILE.id else 1].pressed.emit()
	if not _scene.pending_discard.is_empty(): _scene.discard_accept.pressed.emit()
	var current: Dictionary = _scene.facade.readback() if _scene.facade!=null else {}
	var expected: Dictionary = Scene.Facade.PISTON_PROFILE if profile==Scene.Facade.PISTON_PROFILE.id else Scene.Facade.LEGACY_PROFILE
	if not _check(Readings.from_readback(current).state=="paused" and current.get("tick")=="0" and current.get("model_identity")==expected and _scene.first_flight_open,"layout_actual_paused_tick0_profile_"+profile): return false
	_scene.circuit_checkbox.button_pressed=false
	_check(not _scene.circuit_aid_enabled,"layout_aid_off_actual_choice_"+profile)
	_back()
	_scene.open_landmark_route()
	var board: Control = _scene.landmark_board
	if not _check(_scene.route_open and board._choice_buttons.size()>=4,"layout_actual_four_landmark_chooser_"+profile): return false
	for index in 4: board._choice_buttons[index].pressed.emit()
	board._begin.pressed.emit()
	if not _check(not _scene.route_open and _scene.route_view.get("active")==true and _scene.route_view.get("leg_count")==4,"layout_actual_four_landmarks_selected_"+profile): return false
	if not _scene.map_visible and not _bound_map_toggle("layout-open-"+profile): return false
	_scene.engine_controls.set_expanded(true)
	_scene.panel.set_help_visible(false)
	await _ordinary_paused()
	_sessions.append({"session_id":current.session_id,"readback":current.duplicate(true),"route_labels":_scene.route_view.route_labels.duplicate(),
		"delivery":"actual choice/discard/Back and four actual Board buttons/Begin; TEST-ONLY ordinary presentation exposure over actual PAUSED tick0, no Resume/Run"})
	return true

func _at_size(dimensions: Vector2i) -> bool:
	DisplayServer.window_set_size(dimensions); _window.size=dimensions
	await _host.get_tree().process_frame
	await _host.get_tree().process_frame
	return _check(_window.size==dimensions,"layout_actual_window_"+str(dimensions))

func _current_views(profile: String, dimensions: Vector2i) -> void:
	if not (await _at_size(dimensions)): return
	var authority: PackedByteArray = var_to_bytes(_authority())
	for mode in [0,3,1]:
		_scene.set_camera_mode(mode)
		# Existing requested HUD is on, including CHASE six-pack. This observer
		# does not force a fallback HUD for intentional physical-camera clipping.
		_scene.panel_visible=mode not in [0,3]
		_scene.panel.set_panel_visible(_scene.panel_visible)
		await _settle_layout()
		var name: String = "layout-"+profile+"-"+str(dimensions.x)+"-mode"+str(mode)+"-current-aid-off"
		_check(_scene.facade.readback().tick=="0" and _scene.facade.readback().paused and not _scene.circuit_aid_enabled and _scene.map_visible,"layout_current_actual_source_"+name)
		if profile==Scene.Facade.PISTON_PROFILE.id:
			_check(_scene.engine_controls.is_expanded() and _scene.engine_controls.size.y==216,"layout_current_expanded_engine_"+name)
		await _shot(name,dimensions,"ACTUAL PAUSED tick0 current qualification; aid OFF, four actual manual landmarks, map OPEN, default physical views and requested CHASE HUD ON; not flying")
	_check(var_to_bytes(_authority())==authority,"layout_camera_draws_preserve_full_authority_"+profile+str(dimensions))

func _extra_piston_views() -> void:
	if not (await _at_size(Vector2i(960,540))): return
	for state in ["collapsed-release","map-closed-manual","circuit-unavailable"]:
		if state=="collapsed-release": _scene.engine_controls.set_expanded(false)
		elif state=="map-closed-manual":
			_scene.engine_controls.set_expanded(true)
			if _scene.map_visible and not _bound_map_toggle("layout-extra-close"): return
		else:
			if not _scene.map_visible and not _bound_map_toggle("layout-extra-restore"): return
			_scene.open_first_flight()
			_scene.circuit_checkbox.button_pressed=true
			await _ordinary_paused()
		for mode in [0,3,1]:
			_scene.set_camera_mode(mode)
			_scene.help_visible=false; _scene.panel.set_help_visible(false)
			_scene.panel_visible=state!="collapsed-release" and mode not in [0,3]; _scene.panel.set_panel_visible(_scene.panel_visible)
			await _settle_layout()
			var authority: PackedByteArray = var_to_bytes(_authority())
			if state=="collapsed-release": _check(_scene.look_release_label.is_visible_in_tree(),"layout_release_Help_off_HUD_hidden_"+str(mode))
			elif state=="map-closed-manual": _check(not _scene.map_visible and _scene.landmark_board._card.is_visible_in_tree(),"layout_actual_closed_map_manual_card_"+str(mode))
			else: _check(_scene.circuit_aid_enabled and _scene.circuit_card.visible and not _scene.circuit_card._view.available and _scene.flight_map._circuit.is_empty(),"layout_actual_piston_circuit_unavailable_"+str(mode))
			await _shot("layout-piston-960-mode"+str(mode)+"-"+state,Vector2i(960,540),"ACTUAL PAUSED cold tick0; "+state+"; no engine automation, Resume or Run")
			_check(var_to_bytes(_authority())==authority,"layout_extra_draw_preserves_authority_"+state+str(mode))

func _closed_view(profile: String) -> void:
	if not (await _at_size(Vector2i(960,540))): return
	_scene.set_camera_mode(3)
	_scene.panel_visible=false; _scene.panel.set_panel_visible(false)
	if not _scene.map_visible and not _bound_map_toggle("layout-before-close-"+profile): return
	var retained_facade: RefCounted = _scene.facade
	var last_source: Dictionary = retained_facade.readback()
	var joined: bool = _scene.close_session()
	var closed: Dictionary = retained_facade.readback()
	if not _check(joined and _scene.facade==null and closed.get("host_mode")=="closed" and closed.get("native_live")==false,"layout_actual_worker_joined_"+profile): return
	_layout_closed_witnesses.append({"profile":profile,"last_current_readback":last_source,"joined":joined,
		"actual_closed_readback":closed,"actual_closed_facade_data":_data(retained_facade),
		"source_qualification":"Actual Scene.close_session joined worker and dropped Scene.facade; following UI is empty-source unavailable, not retained current Readback"})
	await _settle_layout()
	await _shot("layout-"+profile+"-960-mode3-joined-closed-empty-source",Vector2i(960,540),"ACTUAL worker joined; Scene facade NULL; empty-source unavailable UI; saved closed Readback is separate, never current truth")

func _expected_roster() -> Array[String]:
	var result: Array[String] = []
	for profile in [Scene.Facade.LEGACY_PROFILE.id,Scene.Facade.PISTON_PROFILE.id]:
		for dimensions in SIZES:
			for mode in [0,3,1]: result.append("layout-"+profile+"-"+str(dimensions.x)+"-mode"+str(mode)+"-current-aid-off.png")
		if profile==Scene.Facade.PISTON_PROFILE.id:
			for state in ["collapsed-release","map-closed-manual","circuit-unavailable"]:
				for mode in [0,3,1]: result.append("layout-piston-960-mode"+str(mode)+"-"+state+".png")
		result.append("layout-"+profile+"-960-mode3-joined-closed-empty-source.png")
	return result

func run_layout(host: Node, output_root: String) -> Dictionary:
	_host=host; _window=host.get_tree().root; _output=output_root
	_checks=0; _failures=[]; _views=[]; _sessions=[]; _map_toggles=[]; _map_sequences=[]
	_layout_closed_witnesses=[]; _joined=false; _audio_joined=false
	if not _check(_output_ok(output_root),"layout_fresh_absolute_empty_external_output"): return {"passed":false,"checks":_checks,"failures":_failures}
	if not _check(OS.get_name()=="Windows" and DisplayServer.get_name()!="headless" and RenderingServer.get_current_rendering_method()=="gl_compatibility","layout_actual_Windows_Compatibility_GPU"): return {"passed":false,"checks":_checks,"failures":_failures}
	var adapter: String = RenderingServer.get_video_adapter_name().to_lower()
	if not _check(not adapter.is_empty(),"layout_actual_adapter_present"): return {"passed":false,"checks":_checks,"failures":_failures}
	for fallback in ["llvmpipe","softpipe","software","warp","microsoft basic render"]:
		if not _check(not adapter.contains(fallback),"layout_no_software_"+fallback): return {"passed":false,"checks":_checks,"failures":_failures}
	if host is Scene and not _check(host.facade==null,"layout_caller_has_no_owner_flight"): return {"passed":false,"checks":_checks,"failures":_failures}
	_source_before=_sources()
	for path in _source_before: _check(_source_before[path].bytes>0 and str(_source_before[path].sha256).length()==64,"layout_actual_source_present_"+path)
	if not _failures.is_empty(): return {"passed":false,"checks":_checks,"failures":_failures}
	var previous_size: Vector2i = _window.size
	var previous_gui: bool = _window.gui_disable_input
	var previous_mouse: int = Input.mouse_mode
	_window.gui_disable_input=true
	_joined=true; _audio_joined=true
	for profile in [Scene.Facade.LEGACY_PROFILE.id,Scene.Facade.PISTON_PROFILE.id]:
		# A separate child per profile allows genuine joined-close captures without
		# forging a closed source into the subsequent First-flight admission seam.
		_scene=SyntheticScene.new(); host.add_child(_scene)
		_scene.set_process(false); _scene.set_physics_process(false); _scene.set_process_input(false)
		_scene.set_process_unhandled_input(false); _scene.set_process_unhandled_key_input(false); _scene.set_process_shortcut_input(false)
		if _scene.sound!=null: _scene.sound.set_process(false)
		var focus_callback: Callable = Callable(_scene,"on_focus_lost")
		if _window.focus_exited.is_connected(focus_callback): _window.focus_exited.disconnect(focus_callback)
		var device_callback: Callable = Callable(_scene,"on_joy_connection_changed")
		if Input.joy_connection_changed.is_connected(device_callback): Input.joy_connection_changed.disconnect(device_callback)
		if _check(_scene.facade!=null and _scene.mapper!=null and _scene.landmark_board!=null and _scene.engine_controls!=null,"layout_actual_integrated_owners_present_"+profile) and (await _choose_profile(profile)):
			for dimensions in SIZES:
				await _current_views(profile,dimensions)
				if not _failures.is_empty(): break
			if _failures.is_empty() and profile==Scene.Facade.PISTON_PROFILE.id: await _extra_piston_views()
			if _failures.is_empty(): await _closed_view(profile)
		var joined: bool = _scene.close_session()
		_joined=joined and _joined
		_check(joined,"layout_finish_actual_native_join_"+profile)
		var audio_joined: bool = true
		if _scene.sound!=null: audio_joined=bool(await _scene.sound.shutdown())
		_audio_joined=audio_joined and _audio_joined
		_check(audio_joined,"layout_finish_actual_audio_join_"+profile)
		_check(_scene.failures.is_empty(),"layout_production_scene_clean_"+profile)
		_scene.free(); _scene=null
		if not _failures.is_empty(): break
	var actual_roster: Array[String] = []
	for view in _views: actual_roster.append(view.file)
	_check(actual_roster==_expected_roster() and _views.size()==29,"layout_exact_twenty_nine_original_views")
	var source_after: Dictionary = _sources()
	_check(source_after==_source_before,"layout_all_staged_source_bytes_unchanged")
	DisplayServer.window_set_size(previous_size); _window.size=previous_size
	_window.gui_disable_input=previous_gui; Input.mouse_mode=previous_mouse
	var receipt: Dictionary = {"schema":"OrdinaryFlightLayoutVisual/v1","passed":_failures.is_empty(),"checks":_checks,"failures":_failures.duplicate(),
		"expected_roster":_expected_roster(),"views":_views.duplicate(true),"sessions":_sessions.duplicate(true),"map_toggles":_map_toggles.duplicate(true),
		"closed_witnesses":_layout_closed_witnesses.duplicate(true),"sources_before":_source_before,"sources_after":source_after,
		"native_joined":_joined,"audio_joined":_audio_joined,"display_backend":DisplayServer.get_name(),"renderer":RenderingServer.get_current_rendering_method(),
		"adapter":RenderingServer.get_video_adapter_name(),"engine":Engine.get_version_info(),"editor":OS.has_feature("editor"),
		"scope":"29 original Windows GPU images with58 paired full Variant truth/layout files. Current images expose ordinary presentation over ACTUAL PAUSED tick0, using actual choices and four existing Board landmark buttons; no Resume, Run, continuous flight or forged current source. Closed images follow actual worker join with Scene.facade null and empty-source UI; separate actual closed witness is never current truth. Released synthetic Raw, manual rendering schedule, focus/device callbacks isolated. Alias/font/rect metadata are not pixel acceptance; Root and independent reviewers inspect original images. No owner data, physical input, aircraft/C172, pilot/hardware/performance/training-credit or phase acceptance. Existing39/27 observers unchanged."}
	var path: String = _output.path_join("layout-receipt.json")
	if _check(not FileAccess.file_exists(path),"layout_fresh_receipt"):
		var file: FileAccess = FileAccess.open(path,FileAccess.WRITE)
		if _check(file!=null,"layout_receipt_open"):
			receipt.passed=_failures.is_empty(); receipt.checks=_checks; receipt.failures=_failures.duplicate()
			file.store_string(JSON.stringify(receipt,"  ",false,true)); file.close()
	receipt.passed=_failures.is_empty(); receipt.checks=_checks; receipt.failures=_failures.duplicate()
	return receipt
