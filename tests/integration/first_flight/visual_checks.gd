extends RefCounted
## Original MIT. Opt-in isolated Windows GPU observer; never pixel acceptance.
## Caller stages the actual integrated source/package, owns watchdog and quit.
const Scene = preload("res://simulation/flight_scene.gd")
const Readings = preload("res://cockpit/instruments/native_readings.gd")
const SIZES: Array[Vector2i] = [Vector2i(960,540),Vector2i(1920,1080),Vector2i(2560,1440)]
const SOURCE_PATHS: Array[String] = [
	"res://simulation/flight_scene.gd","res://simulation/session_facade.gd",
	"res://simulation/render_origin.gd","res://simulation/origin_participant.gd",
	"res://simulation/canonical_frames.gd","res://simulation/wire_validation.gd","res://simulation/uint64.gd",
	"res://input/input_mapper.gd","res://input/input_preset.gd",
	"res://cockpit/instruments/native_readings.gd","res://cockpit/instruments/engine_status.gd",
	"res://ui/first_flight/briefing_panel.gd","res://ui/first_flight/binding_help.gd",
	"res://ui/first_flight/circuit_guide.gd","res://world/synthetic/circuit_geometry.gd","res://world/wind/wind_cue.gd",
	"res://interactive/flight_map.gd","res://interactive/preview.gd","res://ui/freeflight/landmark_board.gd",
	"res://interactive/flight_cockpit.gd","res://interactive/flight_panel.gd",
	"res://build/native_identity.gd","res://content/scenarios/first-flight/briefing.json",
	"res://content/world/synthetic/practice-circuit.json"]

class SyntheticScene extends Scene:
	# Sole production override. Full released Raw, not filtered physical input.
	func collect_input_raw(_preset: Dictionary = {}) -> Dictionary:
		return {"keys":[],"mouse_buttons":[],"devices":[]}

var _scene: Node
var _host: Node
var _window: Window
var _output: String = ""
var _checks: int = 0
var _failures: Array[String] = []
var _views: Array[Dictionary] = []
var _sessions: Array[Dictionary] = []
var _map_toggles: Array[Dictionary] = []
var _map_sequences: Array[Dictionary] = []
var _source_before: Dictionary = {}
var _joined: bool = false
var _audio_joined: bool = false

func _check(ok: bool, label: String) -> bool:
	_checks+=1
	if not ok: _failures.append(label)
	return ok

func _copyable(value: Variant, depth: int = 0) -> bool:
	if depth>32 or value is Object or value is Callable or value is Signal: return false
	if value is Array:
		for item in value:
			if not _copyable(item,depth+1): return false
	if value is Dictionary:
		for key in value:
			if not _copyable(key,depth+1) or not _copyable(value[key],depth+1): return false
	return true

func _data(object: Object) -> Dictionary:
	var result: Dictionary = {}
	if object==null: return result
	for property in object.get_property_list():
		if (int(property.usage)&PROPERTY_USAGE_SCRIPT_VARIABLE)!=0:
			var value: Variant = object.get(property.name)
			if _copyable(value): result[str(property.name)]=value.duplicate(true) if value is Array or value is Dictionary else value
	return result

func _authority() -> Dictionary:
	return {"readback":_scene.facade.readback(),"facade":_data(_scene.facade),
		"mapper":_data(_scene.mapper),"origin":_scene.facade.render_origin.read_origin() if _scene.facade.render_origin!=null else null,
		"recording":_scene.observed_recorder.recording(),"held_controls":_scene.held_controls.duplicate(true),
		"held_systems":_scene.held_systems.duplicate(true),"pending_systems":_scene.pending_systems.duplicate(true),
		"submitted_count":_scene.submitted_count,"event_count":_scene.event_count}

func _truth() -> Dictionary:
	return {"authority":_authority(),"scene":_data(_scene),"map":_data(_scene.flight_map),
		"briefing":_data(_scene.first_flight_panel),"card":_data(_scene.circuit_card),
		"landmark_board":_data(_scene.landmark_board),"engine_controls":_data(_scene.engine_controls),
		"drawn_flight_panel":_data(_scene.panel),"drawn_cockpit_panel":_data(_scene.cockpit_panel),
		"render_pose":_data(_scene.render_pose),"ownship":_scene.airplane.transform,
		"cockpit":_scene.cockpit.root.transform,"world":_scene.world_root.transform,
		"lighting":_scene.light_root.transform,"camera":_scene.camera.transform}

func _sources() -> Dictionary:
	var paths: Array[String] = SOURCE_PATHS.duplicate()
	paths.append(get_script().resource_path)
	var result: Dictionary = {}
	for path in paths:
		result[path]={"bytes":FileAccess.get_file_as_bytes(path).size(),"sha256":FileAccess.get_sha256(path)}
	return result

func _output_ok(path: String) -> bool:
	if not path.is_absolute_path() or path.begins_with("res://") or path.begins_with("user://"): return false
	var normalized: String = path.replace("\\","/").simplify_path().to_lower().trim_suffix("/")
	for parent in [ProjectSettings.globalize_path("res://"),OS.get_executable_path().get_base_dir()]:
		var forbidden: String = str(parent).replace("\\","/").simplify_path().to_lower().trim_suffix("/")
		if normalized==forbidden or normalized.begins_with(forbidden+"/"): return false
	var directory: DirAccess = DirAccess.open(path)
	if directory==null: return false
	directory.include_hidden=true
	return directory.get_files().is_empty() and directory.get_directories().is_empty()

func _rect(control: Control) -> Dictionary:
	if control==null: return {"present":false}
	var rect: Rect2 = control.get_global_rect()
	return {"present":true,"visible":control.is_visible_in_tree(),"position":[rect.position.x,rect.position.y],"size":[rect.size.x,rect.size.y],
		"inside_viewport":Rect2(Vector2.ZERO,Vector2(_window.size)).encloses(rect),"mouse_filter":control.mouse_filter,"focus_mode":control.focus_mode}

func _label_rows(root: Node) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if root==null: return result
	if root is Label:
		var label: Label = root as Label
		var row: Dictionary = _rect(label)
		row["text"]=label.text
		result.append(row)
	for child in root.get_children(): result.append_array(_label_rows(child))
	return result

func _layout() -> Dictionary:
	var panel: Control = _scene.first_flight_panel
	var card: Control = _scene.circuit_card
	var board: Control = _scene.landmark_board
	var dock: Rect2 = board._card_dock
	var result: Dictionary = {"briefing":_rect(panel),"status":_rect(panel._status),"back":_rect(panel._back),"controls":_rect(panel._controls),
		"tabs":_rect(panel._tabs),"map":_rect(_scene.flight_map),"card":_rect(card),"native_drawn_panel":_rect(_scene.panel),"unused_preview_label":_rect(_scene.label),
		"wind_status":_rect(_scene.wind_label),"circuit_checkbox":_rect(_scene.circuit_checkbox),"card_labels":[],
		"manual_route_card":_rect(board._card),"manual_route_labels":_label_rows(board._card),
		"manual_route_summary_in_map":board._summary_in_map,
		"manual_route_card_dock":{"position":[dock.position.x,dock.position.y],"size":[dock.size.x,dock.size.y]},
		"manual_route_view":board._view.duplicate(true)}
	for label in card._labels:
		var row: Dictionary = _rect(label); row["text"]=label.text; result.card_labels.append(row)
	return result

func _truth_file(name: String, value: Dictionary) -> Dictionary:
	var path: String = _output.path_join(name)
	if not _check(not FileAccess.file_exists(path),"fresh_truth_"+name): return {}
	var file: FileAccess = FileAccess.open(path,FileAccess.WRITE)
	if not _check(file!=null,"open_truth_"+name): return {}
	var bytes: PackedByteArray = var_to_bytes(value)
	file.store_buffer(bytes); file.close()
	return {"file":name,"bytes":bytes.size(),"sha256":FileAccess.get_sha256(path)}

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
	_check(var_to_bytes(before)==var_to_bytes(after),"full_truth_unchanged_during_capture_"+name)
	var before_file: Dictionary = _truth_file(name+".before.truth",before)
	var after_file: Dictionary = _truth_file(name+".after.truth",after)
	_check(not before_file.is_empty() and before_file.get("sha256")==after_file.get("sha256") and before_file.get("bytes")==after_file.get("bytes"),"saved_truth_pair_exact_"+name)
	var native: Dictionary = _scene.facade.readback()
	var card: Control = _scene.circuit_card
	var map: Control = _scene.flight_map
	var panel: Control = _scene.first_flight_panel
	_views.append({"file":name+".png","saved":saved,"bytes":FileAccess.get_file_as_bytes(path).size() if saved else 0,"sha256":FileAccess.get_sha256(path) if saved else "",
		"requested_window":[dimensions.x,dimensions.y],"actual_window":[_window.size.x,_window.size.y],"phase":phase,
		"camera_mode":_scene.camera_mode,"native":native,"readings":_scene.shared_readings.duplicate(true),
		"truth_before_file":before_file,"truth_after_file":after_file,"layout":_layout(),
		"status":{"scene":_scene.status,"custom_draw_info":_scene.panel._info.duplicate(true),"custom_draw_readings":_scene.panel._readings.duplicate(true),
			"custom_draw_held_controls":_scene.panel._held.duplicate(true),"preview_label_present":_scene.label!=null,
			"preview_label_text":_scene.label.text if _scene.label!=null else null,"briefing":panel._status.text,"actual":panel._actual.text,"wind":_scene.wind_label.text},
		"briefing":{"visible":panel.visible,"tab":panel._tabs.current_tab,"manual_step":panel._step_index,"manual_text":panel._step_text.text,"binding_text":panel._binding_text.text},
		"circuit":{"enabled":_scene.circuit_aid_enabled,"card_view":card._view.duplicate(true),"map_view":map._circuit.duplicate(true),"reason":card._reason.text},
		"map":{"visible":_scene.map_visible,"extent_m":map.extent_m,"runway":map._runway,"ownship_center":[map._position.x,map._position.y],"route":map._route.duplicate(true)},
		"existing_route":_scene.route_view.duplicate(true),"raw":_scene.collect_input_raw(),"bounds_are_not_pixel_acceptance":true})

func _tab(index: int, bottom: bool = false) -> void:
	var panel: Control = _scene.first_flight_panel
	panel._tabs.current_tab=index
	await _host.get_tree().process_frame
	var scroll: ScrollContainer = panel._tabs.get_child(index)
	scroll.scroll_vertical=int(scroll.get_v_scroll_bar().max_value) if bottom else 0
	await _host.get_tree().process_frame

func _ready_choice() -> bool:
	_scene.open_first_flight()
	if not _check(_scene.first_flight_open and _scene.first_flight_panel.visible,"ordinary_briefing_open"): return false
	_scene.first_flight_panel._choice_buttons[1].pressed.emit()
	if not _scene.pending_discard.is_empty():
		_check(_scene.get_viewport().gui_get_focus_owner()==_scene.discard_cancel,"ordinary_discard_default_cancel")
		_scene.discard_accept.pressed.emit()
	var native: Dictionary = _scene.facade.readback()
	var ok: bool = _check(Readings.from_readback(native).state=="paused" and native.tick=="0" and native.named_start=="ground-ready" and native.model_identity==Scene.Facade.LEGACY_PROFILE and _scene.current_wind_profile=="calm" and _scene.first_flight_open,"actual_ready_adoption_stays_paused_tick0")
	_sessions.append({"session_id":native.get("session_id"),"readback":native.duplicate(true),"discard_pending":_scene.pending_discard.duplicate(true)})
	return ok

func _back() -> void:
	_scene.first_flight_panel._back.pressed.emit()
	_check(not _scene.first_flight_open and _scene.menu_open and _scene.facade.readback().paused,"ordinary_back_stays_paused")

func _resume() -> bool:
	_scene.resume_button.pressed.emit()
	return _check(not _scene.menu_open and not _scene.first_flight_open and Readings.from_readback(_scene.facade.readback()).state=="live","ordinary_explicit_resume")

func _set_aid(enabled: bool) -> bool:
	_scene.open_first_flight()
	if not _check(_scene.first_flight_open and _scene.facade.readback().paused,"ordinary_pause_before_aid_edit"): return false
	_scene.circuit_checkbox.button_pressed=enabled
	_check(_scene.circuit_aid_enabled==enabled,"ordinary_checkbox_adopted")
	_back()
	return _resume()

func _map_reference() -> Dictionary:
	var map: Control = _scene.flight_map
	var board: Control = _scene.landmark_board
	return {"extent_m":map.extent_m,"runway":map._runway,"ownship_center":map._position,
		"map_route":map._route.duplicate(true),"scene_route":_scene.route_view.duplicate(true),
		"board_route":board._route.duplicate(true),"board_leg":board._leg,"board_complete":board._complete,
		"board_session":board._session,"board_view":board._view.duplicate(true)}

func _bound_map_toggle(label: String) -> bool:
	# Pure admission against the actual configured key source, followed by the
	# production action dispatcher. No physical event/device polling or mapper
	# sample is claimed; the sole collector override remains full released Raw.
	var preset: Dictionary = _scene.active_preset.duplicate(true)
	if not _check(Scene.Preset.validate_preset(preset).ok,"valid_map_toggle_preset_"+label): return false
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
	_map_toggles.append({"label":label,"source":selected,"pressed_raw":pressed,"released_raw":released,
		"map_before":previous,"map_after":_scene.map_visible,"full_authority_unchanged":unchanged,
		"bound_action":"map_toggle","delivery":"pure configured binding admission then actual Scene action dispatch; no physical event or mapper sample"})
	_check(unchanged,"bound_map_toggle_preserves_full_authority_"+label)
	return _check(toggled,"bound_map_toggle_changes_actual_visibility_"+label) and unchanged

func _views_at_size(dimensions: Vector2i) -> void:
	DisplayServer.window_set_size(dimensions); _window.size=dimensions
	await _host.get_tree().process_frame; await _host.get_tree().process_frame
	if not _check(_window.size==dimensions,"observed_window_"+str(dimensions)): return
	if not _ready_choice(): return
	var prefix: String = "first-flight-"+str(dimensions.x)
	var authority: PackedByteArray = var_to_bytes(_authority())
	await _tab(0); await _shot(prefix+"-briefing-state",dimensions,"actual paused ready-flight")
	await _tab(0,true); await _shot(prefix+"-briefing-choices",dimensions,"exact supported choice descriptions and paused aid chooser")
	await _tab(1); await _shot(prefix+"-controls-actions",dimensions,"validated current action assignments")
	await _tab(1,true); await _shot(prefix+"-controls-axes-systems",dimensions,"validated axes and honest legacy system unavailability")
	await _tab(2)
	for i in 4:
		if _scene.first_flight_panel._step_index>0: _scene.first_flight_panel._previous.pressed.emit()
	_check(_scene.first_flight_panel._step_index==0,"bounded_manual_step_reset_"+prefix)
	_scene.first_flight_panel._next.pressed.emit()
	await _shot(prefix+"-manual-step",dimensions,"manual software step, never aircraft progress")
	_check(var_to_bytes(_authority())==authority,"all_paused_briefing_pages_preserve_authority_"+prefix)
	_back()
	# Reuse the actual existing optional route chooser, never forge set_route.
	_scene.open_landmark_route(); _scene.choose_landmark_route([0,1])
	_check(not _scene.route_open and _scene.route_view.get("active")==true,"existing_original_route_selected_"+prefix)
	if not _scene.map_visible and not _bound_map_toggle(prefix+"-initial-open"): return
	if _scene.flight_map._runway!=36: _scene.dispatch_input_action("runway_toggle")
	for i in 6: _scene.dispatch_input_action("map_zoom_in")
	_check(_scene.map_visible and _scene.flight_map.extent_m==1000.0 and _scene.flight_map._runway==36,"ordinary_locator_minimum_extent_"+prefix)
	if not _set_aid(true): return
	# One controlled ordinary host interval, using the full released Raw fixture.
	_scene.process_input_interval(8334); _scene.show_state(0.0)
	_check(_scene.facade.readback().tick=="1","one_explicit_native_tick_"+prefix)
	authority=var_to_bytes(_authority())
	for mode in [0,3,1]:
		_scene.set_camera_mode(mode); _scene.show_state(0.0)
		_check(_scene.circuit_card._view.available and _scene.circuit_card.visible and not _scene.flight_map._circuit.is_empty(),"actual_available_circuit_"+prefix+"_"+str(mode))
		await _shot(prefix+"-live-circuit-mode"+str(mode),dimensions,"actual live native tick1, manual host schedule; existing route and clipped1000m locator")
		var sequence: String = prefix+"-mode"+str(mode)
		var before: Dictionary = _map_reference()
		var authority_before: PackedByteArray = var_to_bytes(_authority())
		if not _bound_map_toggle(sequence+"-close"): return
		_scene.show_state(0.0)
		var closed: Dictionary = _map_reference()
		var closed_authority_same: bool = var_to_bytes(_authority())==authority_before
		_check(closed_authority_same,"closed_map_full_authority_unchanged_"+sequence)
		var closed_reference_same: bool = var_to_bytes(before)==var_to_bytes(closed)
		_check(closed_reference_same,"closed_map_extent_runway_full_route_unchanged_"+sequence)
		_check(not _scene.map_visible and not _scene.flight_map.is_visible_in_tree() and not _scene.landmark_board._summary_in_map and _scene.landmark_board._card.is_visible_in_tree(),"closed_map_actual_manual_route_card_visible_"+sequence)
		await _shot(prefix+"-live-map-closed-mode"+str(mode),dimensions,"actual configured map toggle dispatch; closed locator exposes original manual route card")
		if not _bound_map_toggle(sequence+"-restore"): return
		_scene.show_state(0.0)
		var restored: Dictionary = _map_reference()
		var restored_authority_same: bool = var_to_bytes(_authority())==authority_before
		var restored_reference_same: bool = var_to_bytes(before)==var_to_bytes(restored)
		_check(restored_authority_same,"restored_map_full_authority_unchanged_"+sequence)
		_check(restored_reference_same,"restored_map_extent_runway_full_route_unchanged_"+sequence)
		_check(_scene.map_visible and _scene.flight_map.is_visible_in_tree() and _scene.landmark_board._summary_in_map and not _scene.landmark_board._card.is_visible_in_tree(),"restored_map_actual_summary_suppresses_duplicate_card_"+sequence)
		_map_sequences.append({"name":sequence,"before":before,"closed":closed,"restored":restored,
			"closed_full_authority_unchanged":closed_authority_same,"restored_full_authority_unchanged":restored_authority_same,
			"closed_reference_exact":closed_reference_same,"restored_reference_exact":restored_reference_same,"restored_layout":_layout()})
	_check(var_to_bytes(_authority())==authority,"camera_views_preserve_authority_"+prefix)
	if not _set_aid(false): return
	_scene.show_state(0.0)
	_check(not _scene.circuit_card.visible and _scene.flight_map._circuit.is_empty(),"aid_off_clears_both_"+prefix)
	await _shot(prefix+"-live-aid-off",dimensions,"actual aid disabled through paused chooser")
	if not _set_aid(true): return
	_scene.dispatch_input_action("runway_toggle"); _scene.show_state(0.0)
	_check(_scene.flight_map._runway==18 and _scene.flight_map.extent_m==1000.0 and _scene.circuit_card.visible and not _scene.circuit_card._view.available and _scene.flight_map._circuit.is_empty(),"runway18_unavailable_no_stale_map_"+prefix)
	await _shot(prefix+"-live-runway18-unavailable",dimensions,"actual unsupported selected runway, no guidance substitution")

func run(host: Node, output_root: String) -> Dictionary:
	_host=host; _window=host.get_tree().root; _output=output_root
	_checks=0; _failures=[]; _views=[]; _sessions=[]; _map_toggles=[]; _map_sequences=[]; _joined=false; _audio_joined=false
	if not _check(_output_ok(output_root),"fresh_absolute_external_output"): return {"passed":false,"failures":_failures}
	if not _check(OS.get_name()=="Windows" and DisplayServer.get_name()!="headless" and RenderingServer.get_current_rendering_method()=="gl_compatibility","actual_Windows_Compatibility_GPU"): return {"passed":false,"failures":_failures}
	var adapter: String = RenderingServer.get_video_adapter_name().to_lower()
	if not _check(not adapter.is_empty(),"adapter_present"): return {"passed":false,"failures":_failures}
	for fallback in ["llvmpipe","softpipe","software","warp","microsoft basic render"]:
		if not _check(not adapter.contains(fallback),"no_software_"+fallback): return {"passed":false,"failures":_failures}
	if host is Scene and not _check(host.facade==null,"caller_has_no_existing_owner_flight"): return {"passed":false,"failures":_failures}
	_source_before=_sources()
	for path in _source_before: _check(_source_before[path].bytes>0 and str(_source_before[path].sha256).length()==64,"actual_source_present_"+path)
	if not _failures.is_empty(): return {"passed":false,"failures":_failures}
	var previous_size: Vector2i = _window.size
	var previous_gui: bool = _window.gui_disable_input
	var previous_mouse: int = Input.mouse_mode
	_window.gui_disable_input=true
	_scene=SyntheticScene.new(); host.add_child(_scene)
	_scene.set_process(false); _scene.set_physics_process(false); _scene.set_process_input(false)
	_scene.set_process_unhandled_input(false); _scene.set_process_unhandled_key_input(false); _scene.set_process_shortcut_input(false)
	if _scene.sound!=null: _scene.sound.set_process(false)
	# Isolate resize/focus/device events for this view-only child. Full production
	# callbacks remain unchanged and belong to separate host interaction checks.
	var focus_callback: Callable = Callable(_scene,"on_focus_lost")
	if _window.focus_exited.is_connected(focus_callback): _window.focus_exited.disconnect(focus_callback)
	var device_callback: Callable = Callable(_scene,"on_joy_connection_changed")
	if Input.joy_connection_changed.is_connected(device_callback): Input.joy_connection_changed.disconnect(device_callback)
	if _check(_scene.facade!=null and _scene.mapper!=null and _scene.first_flight_panel!=null and _scene.circuit_card!=null and _scene.landmark_board!=null,"actual_integrated_owners_present"):
		for dimensions in SIZES: await _views_at_size(dimensions)
	_check(_views.size()==39,"exact_thirty_nine_original_views")
	_check(_map_sequences.size()==9,"exact_nine_map_close_restore_sequences")
	_joined=_scene.close_session(); _check(_joined,"ordinary_native_join")
	_audio_joined=true
	if _scene.sound!=null: _audio_joined=bool(await _scene.sound.shutdown())
	_check(_audio_joined,"audio_joined"); _check(_scene.failures.is_empty(),"production_scene_checks_clean")
	var closed_readback: Dictionary = _scene.facade.readback() if _scene.facade!=null else {}
	_scene.free()
	var source_after: Dictionary = _sources()
	_check(_source_before==source_after,"all_staged_source_bytes_unchanged")
	DisplayServer.window_set_size(previous_size); _window.size=previous_size
	_window.gui_disable_input=previous_gui; Input.mouse_mode=previous_mouse
	var receipt: Dictionary = {"schema":"FirstFlightVisual/v1","passed":_failures.is_empty(),"checks":_checks,"failures":_failures.duplicate(),
		"views":_views.duplicate(true),"sessions":_sessions.duplicate(true),"map_toggles":_map_toggles.duplicate(true),
		"map_close_restore_sequences":_map_sequences.duplicate(true),"sources_before":_source_before,"sources_after":source_after,
		"native_joined":_joined,"audio_joined":_audio_joined,"closed_readback":closed_readback,"display_backend":DisplayServer.get_name(),
		"renderer":RenderingServer.get_current_rendering_method(),"adapter":RenderingServer.get_video_adapter_name(),"engine":Engine.get_version_info(),"editor":OS.has_feature("editor"),
		"scope":"Thirty-nine actual GPU originals with 78 full saved Variant truth files. Nine live map close/restore sequences use pure current configured key-binding admission and actual Scene action dispatch, not physical input event delivery or mapper sampling. Full released synthetic Raw collector; actual scene choices/pause/menu Resume and one ordinary tick per size. Live images use a manually scheduled host, not continuous flight. Existing route is original optional geometry. Two sampled draws do not cover all OS frames. Bounds do not establish pixel readability. No owner data, hardware, pilot, performance, aircraft, training-credit or phase acceptance."}
	var receipt_path: String = _output.path_join("receipt.json")
	if _check(not FileAccess.file_exists(receipt_path),"fresh_receipt"):
		var file: FileAccess = FileAccess.open(receipt_path,FileAccess.WRITE)
		if _check(file!=null,"receipt_open"):
			receipt.passed=_failures.is_empty(); receipt.checks=_checks; receipt.failures=_failures.duplicate()
			file.store_string(JSON.stringify(receipt,"  ",false,true)); file.close()
	receipt.passed=_failures.is_empty(); receipt.checks=_checks; receipt.failures=_failures.duplicate()
	return receipt
