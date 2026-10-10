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

# Separate TEST-ONLY acceptance observer. The original run()/39-view driver above
# is unchanged. Synthetic Raw is explicit; no OS/hardware event delivery claim.
class MutableRawScene extends Scene:
	var synthetic_raw: Dictionary = {"keys":[],"mouse_buttons":[],"devices":[]}
	func collect_input_raw(_preset: Dictionary = {}) -> Dictionary:
		return synthetic_raw.duplicate(true)

var _interaction_steps: Array[Dictionary] = []
var _interaction_controls: Array[Dictionary] = []
var _interaction_negatives: Array[Dictionary] = []
var _interaction_flight_rows: Array[Dictionary] = []
var _interaction_flight_segments: Array[Dictionary] = []

func _interaction_sources() -> Dictionary:
	var result: Dictionary = _sources()
	for path in ["res://cockpit/engine_controls.gd","res://ui/controls/controls_panel.gd"]:
		result[path]={"bytes":FileAccess.get_file_as_bytes(path).size(),"sha256":FileAccess.get_sha256(path)}
	return result

func _interaction_snapshot() -> Dictionary:
	return {"truth":_truth(),"native_state":_scene.facade.get("_bridge").call("read_state"),
		"raw":_scene.collect_input_raw(),"pilot_axes":_scene.controls.duplicate(true),
		"pilot_systems":_scene.pending_systems.duplicate(true),"mapper_values":_scene.mapper.get("_values").duplicate(true),
		"applied_commands":_scene.facade.get("_commands").duplicate(true),
		"pending_commands":_scene.facade.get("_pending_commands").duplicate(true),
		"command_sequence":_scene.facade.get("_command_sequence"),"submitted_count":_scene.submitted_count}

func _interaction_route_basis() -> Dictionary:
	# Ownship, range/bearing, draw position and tick must change during actual Run.
	# Only the existing authored/manual route and locator choices are invariant.
	return {"extent_m":_scene.flight_map.extent_m,"runway":_scene.flight_map._runway,
		"route":_scene.landmark_board._route.duplicate(true),"leg":_scene.landmark_board._leg,
		"complete":_scene.landmark_board._complete,"session":_scene.landmark_board._session,
		"fixed_points":_scene.flight_map._circuit.get("points_anchor_eus_m",[]).duplicate(true),
		"fixed_labels":_scene.flight_map._circuit.get("leg_labels",[]).duplicate(true)}

func _interaction_keys(action: String) -> Array:
	for binding in _scene.active_preset.actions:
		if binding.id!=action: continue
		for source in binding.sources:
			if source.kind=="physical_keys" and not source.keys.is_empty(): return [int(source.keys[0])]
	return []

func _interaction_axis_keys(target: String, positive: bool = true) -> Array:
	for axis in _scene.active_preset.axes:
		if axis.target==target and axis.kind=="key_pair":
			var keys: Array = axis.positive if positive else axis.negative
			if not keys.is_empty(): return [int(keys[0])]
	return []

func _interaction_decoded_axes_equal(decoded: Variant, requested: Dictionary) -> bool:
	# Independent implementation of accepted session_facade.gd::_same's
	# decoded_wire=true numeric allowance, ONLY for the decoded axes payload.
	# Native held==mapped remains exact. Never round/rewrite intent or evidence.
	if not decoded is Dictionary or decoded.size()!=requested.size(): return false
	for key in decoded:
		if typeof(key)!=TYPE_STRING or not requested.has(key): return false
	for key in requested:
		if key=="kind":
			if typeof(decoded[key])!=TYPE_STRING or decoded[key]!=requested[key]: return false
		else:
			if not typeof(decoded[key]) in [TYPE_FLOAT,TYPE_INT] or not typeof(requested[key]) in [TYPE_FLOAT,TYPE_INT]: return false
			var actual: float = float(decoded[key])
			var expected: float = float(requested[key])
			if not is_finite(actual) or not is_finite(expected): return false
			if absf(actual-expected)>8.0*2.220446049250313e-16*maxf(1.0,maxf(absf(actual),absf(expected))): return false
	return true

func _interaction_codec_checks() -> void:
	var intended: Dictionary = {"kind":"axes","roll":0.0,"pitch":-0.9*0.025,"yaw":0.0,"throttle":0.0,"mixture":1.0,"left_brake":0.0,"right_brake":0.0,"trim":0.0}
	var decoded: Dictionary = intended.duplicate(true); decoded.pitch=-0.0225
	_check(_interaction_decoded_axes_equal(decoded,intended),"interaction_existing_payload_codec_allowance")
	decoded.pitch=float(intended.pitch)+1e-12
	_check(not _interaction_decoded_axes_equal(decoded,intended),"interaction_payload_codec_rejects_outside_bound")
	decoded=intended.duplicate(true); decoded["unknown"]=0.0
	_check(not _interaction_decoded_axes_equal(decoded,intended),"interaction_payload_codec_rejects_extra_key")
	decoded=intended.duplicate(true); decoded.erase("trim")
	_check(not _interaction_decoded_axes_equal(decoded,intended),"interaction_payload_codec_rejects_missing_key")
	decoded=intended.duplicate(true); decoded.kind="system"
	_check(not _interaction_decoded_axes_equal(decoded,intended),"interaction_payload_codec_kind_exact")
	decoded=intended.duplicate(true); decoded.pitch=true
	_check(not _interaction_decoded_axes_equal(decoded,intended),"interaction_payload_codec_rejects_boolean")

func _interaction_command_feedback(prior: Dictionary, current: Dictionary, requested: Dictionary, commands: Array, count_before: int, count_after: int, sequence_before: String, sequence_after: String, label: String) -> bool:
	# Actual ordinary facade deduplication is part of the input contract. Holding
	# an unchanged intent advances Run without inventing another pilot command.
	if prior.held_axes==requested:
		return _check(commands.is_empty() and count_after==count_before and sequence_after==sequence_before,"interaction_unchanged_axes_deduplicated_no_fabricated_command_"+label)
	var progress: bool = _check(commands.size()==1 and count_after==count_before+1 and int(sequence_after)==int(sequence_before)+1,"interaction_changed_axes_actual_command_progress_"+label)
	if not progress: return false
	var command: Dictionary = commands[0]
	var keys: Array = command.keys(); keys.sort()
	var expected_keys: Array = ["type","schema_version","tick","session_id","sequence","source_id","authority","assistance","payload"]; expected_keys.sort()
	return _check(keys==expected_keys and command.get("type")=="ControlCommand" and command.get("schema_version")==1 and command.get("source_id")=="pilot.controls" and command.get("authority")=="pilot" and command.get("assistance")=={"profile_id":"unassisted","active":[]} and _interaction_decoded_axes_equal(command.get("payload"),requested) and command.get("session_id")==current.session_id and command.get("sequence")==sequence_after and command.get("tick")==str(int(prior.tick)+1),"interaction_changed_axes_exact_provenance_and_bounded_decoded_payload_"+label)

func _interaction_feedback_raw(desired_pitch: float, throttle: float, brakes: bool) -> Dictionary:
	# Existing original preview.gd automated_axes formula, TEST-ONLY desired input.
	# The current guest key-pair bindings/rates/gains still determine actual axes;
	# no preset, scene.controls, mapper internals or native state is overwritten.
	var state: Dictionary = _scene.snapshot
	var q: Dictionary = state.orientation_body_to_ned
	var bank: float = atan2(2*(float(q.w)*float(q.x)+float(q.y)*float(q.z)),1-2*(float(q.x)*float(q.x)+float(q.y)*float(q.y)))
	var pitch: float = asin(clampf(2*(float(q.w)*float(q.y)-float(q.z)*float(q.x)),-1,1))
	var velocity: Dictionary = state.velocity_body_mps
	var rate: Dictionary = state.angular_rate_body_radps
	var alpha: float = atan2(float(velocity.z),float(velocity.x))
	var desired: Dictionary = {"roll":clampf(-2*bank-0.3*float(rate.x),-0.25,0.25),
		"pitch":clampf((alpha-0.02)/0.7+2*(desired_pitch-pitch)-0.5*float(rate.y),-0.4,0.4),"yaw":0.0,"throttle":throttle}
	if brakes: desired={"roll":0.0,"pitch":0.0,"yaw":0.0,"throttle":0.0}
	var keys: Array = _interaction_keys("both_brakes") if brakes else []
	for axis in _scene.active_preset.axes:
		if not desired.has(axis.target) or axis.kind!="key_pair": continue
		var current: float = float(_scene.controls[axis.target])
		var base: float = float(_scene.mapper.get("_start")[axis.target])
		var target: float = clampf(float(desired[axis.target]),maxf(-1.0,base-float(axis.gain)),minf(1.0,base+float(axis.gain))) if axis.return_to_start else float(desired[axis.target])
		# Half the declared25ms key-pair increment is an input quantization band,
		# not a native accuracy tolerance or an aircraft reference threshold.
		var half_increment: float = float(axis.rate)*0.025*0.5
		var source: Array = _interaction_axis_keys(axis.target,true) if current<target-half_increment else (_interaction_axis_keys(axis.target,false) if current>target+half_increment else [])
		for key in source:
			if not keys.has(key): keys.append(key)
	return {"raw":{"keys":keys,"mouse_buttons":[],"devices":[]},"test_desired":desired,"desired_pitch":desired_pitch,"brakes":brakes}

func _interaction_airborne(label: String) -> bool:
	return _check(_scene.snapshot.contacts.size()==3 and not _scene.any_wow() and _scene.ground_valid and _scene.plane_clearance>10.0 and int(_scene.facade.readback().tick)>600,
		"interaction_actual_airborne_all3_false_clearance_above10m_after_settle_"+label)

func _interaction_takeoff(prefix: String, route_basis: PackedByteArray) -> bool:
	var segment_before: Dictionary = {}
	var segment_start: int = 0
	var reached: bool = false
	var settled: bool = false
	var row_offset: int = _interaction_flight_rows.size()
	# Five seconds of original held-brake settling, then <=60simulated seconds
	# of actual control input. Failure never lowers the airborne threshold.
	for interval in 2600:
		if interval%100==0:
			segment_start=interval
			segment_before=_truth_file(prefix+"-flight-segment-"+str(segment_start)+".before.truth",_interaction_snapshot())
		var settling: bool = interval<200
		if interval==200:
			settled=_check(_scene.all_wow() and _scene.flight_speed()<0.05,"interaction_actual_original5s_settled_allWOW_"+prefix)
			if not settled: break
		var climbing: bool = not _scene.any_wow() and _scene.plane_clearance>3.0
		var desired_pitch: float = 0.0 if settling else (0.08 if climbing else (0.12 if _scene.flight_speed()>32.0 else 0.0))
		var input: Dictionary = _interaction_feedback_raw(desired_pitch,0.0 if settling else (0.9 if climbing else 1.0),settling)
		if not _check(Scene.Preset.validate_raw(input.raw).ok,"interaction_flight_valid_full_Raw_"+prefix+"-"+str(interval)): break
		_scene.synthetic_raw=input.raw.duplicate(true)
		var prior: Dictionary = _scene.facade.readback()
		var submitted: int = _scene.submitted_count
		var sequence: String = _scene.facade.get("_command_sequence")
		_scene.process_input_interval(25000); _scene.show_state(0.0)
		var current: Dictionary = _scene.facade.readback()
		var actual_commands: Array = _scene.facade.get("_commands").duplicate(true)
		var actual: bool = _check(Readings.from_readback(current).state=="live" and current.session_id==prior.session_id and int(current.tick)==int(prior.tick)+3 and current.debt_quanta==prior.debt_quanta and current.held_axes==_scene.controls,"interaction_flight_real_mapper_Run_feedback_"+prefix+"-"+str(interval))
		var admitted: bool = _interaction_command_feedback(prior,current,_scene.controls,actual_commands,submitted,_scene.submitted_count,sequence,_scene.facade.get("_command_sequence"),prefix+"-flight-"+str(interval))
		var available: bool = _check(_scene.map_visible and _scene.circuit_card._view.get("available")==true and var_to_bytes(_interaction_route_basis())==route_basis,"interaction_flight_map_circuit_route_extent_preserved_"+prefix+"-"+str(interval))
		_interaction_flight_rows.append({"label":prefix,"interval":interval,"elapsed_us":25000,"phase":"original-settle" if settling else ("climb" if climbing else "takeoff"),
			"raw":input.raw,"test_desired":input.test_desired,"desired_pitch":desired_pitch,"session_id":current.session_id,"native_source_fingerprint":current.native_source_fingerprint,"native_tick_before":prior.tick,"native_tick_after":current.tick,
			"debt_quanta":current.debt_quanta,"mapped_axes":_scene.controls.duplicate(true),"native_held_axes":current.held_axes.duplicate(true),
			"submitted_count_before":submitted,"submitted_count_after":_scene.submitted_count,"command_sequence_before":sequence,"command_sequence_after":_scene.facade.get("_command_sequence"),"command_oracle_passed":admitted,
			"applied_commands":actual_commands,"canonical":current.canonical,"velocity_body_mps":current.aircraft.velocity_body_mps,
			"orientation_body_to_ned":current.aircraft.orientation_body_to_ned,"contacts":current.aircraft.contacts,
			"native_ground_query_valid":_scene.ground_valid,"native_plane_clearance_m":_scene.plane_clearance,"map_visible":_scene.map_visible,"circuit_available":_scene.circuit_card._view.get("available",false)})
		reached=settled and current.aircraft.contacts.size()==3 and not _scene.any_wow() and _scene.ground_valid and _scene.plane_clearance>10.0
		if interval%100==99 or reached or not actual or not admitted or not available:
			var segment_after: Dictionary = _truth_file(prefix+"-flight-segment-"+str(segment_start)+".after.truth",_interaction_snapshot())
			_interaction_flight_segments.append({"label":prefix,"interval_first":segment_start,"interval_last":interval,"before":segment_before,"after":segment_after,"rows_offset":row_offset+segment_start,"rows_count":interval-segment_start+1,"actual_airborne":reached})
		if reached or not actual or not admitted or not available: break
	return _check(reached and settled,"interaction_actual_ready_ground_takeoff_not_initial_false_contacts_"+prefix) and _interaction_airborne(prefix)

func _interaction_sample(label: String, keys: Array, elapsed_us: int) -> bool:
	if not _check(elapsed_us in [0,25000],"interaction_bounded_interval_"+label): return false
	var raw: Dictionary = {"keys":keys.duplicate(),"mouse_buttons":[],"devices":[]}
	if not _check(Scene.Preset.validate_raw(raw).ok,"interaction_full_valid_Raw_"+label): return false
	_scene.synthetic_raw=raw.duplicate(true)
	var before: Dictionary = _interaction_snapshot()
	var prior: Dictionary = before.truth.authority.readback
	_scene.process_input_interval(elapsed_us)
	_scene.show_state(0.0)
	var after: Dictionary = _interaction_snapshot()
	var current: Dictionary = after.truth.authority.readback
	var before_file: Dictionary = _truth_file(label+".step-before.truth",before)
	var after_file: Dictionary = _truth_file(label+".step-after.truth",after)
	var live: bool = _check(Readings.from_readback(current).state=="live" and current.session_id==prior.session_id,"interaction_same_actual_live_owner_"+label)
	var ticks: int = 3 if elapsed_us==25000 else 0
	var progress: bool = _check(int(current.tick)==int(prior.tick)+ticks and current.debt_quanta==prior.debt_quanta,"interaction_exact_native_ticks_and_debt_"+label)
	var feedback: bool = true
	_check(before.native_state.get("ok")==true and after.native_state.get("ok")==true,"interaction_actual_native_snapshots_valid_"+label)
	if ticks>0:
		feedback=_check(current.held_axes==_scene.controls,"interaction_mapped_axes_equal_actual_native_feedback_"+label)
		feedback=_interaction_command_feedback(prior,current,_scene.controls,after.applied_commands,before.submitted_count,after.submitted_count,before.command_sequence,after.command_sequence,label) and feedback
	else:
		feedback=_check(current.held_axes==prior.held_axes,"interaction_zero_ticks_do_not_claim_intent_applied_"+label)
	_interaction_steps.append({"label":label,"elapsed_us":elapsed_us,"raw":raw,"before":before_file,"after":after_file,
		"session_id":current.session_id,"tick_before":prior.tick,"tick_after":current.tick,"debt_before":prior.debt_quanta,"debt_after":current.debt_quanta,
		"requested_axes":_scene.controls.duplicate(true),"native_held_axes":current.held_axes.duplicate(true),
		"applied_commands":after.applied_commands,"command_sequence_before":before.command_sequence,"command_sequence_after":after.command_sequence,
		"map_visible":_scene.map_visible,"circuit_available":_scene.circuit_card._view.get("available",false),
		"route_basis":_interaction_route_basis(),"canonical_before":prior.canonical,"canonical_after":current.canonical,
		"delivery":"full synthetic Raw -> actual mapper.sample -> Scene ordinary intent/advance; no direct facade/native mutation"})
	return live and progress and feedback

func _interaction_edge(action: String, held: Array, label: String, elapsed_us: int = 0) -> bool:
	var source: Array = _interaction_keys(action)
	if not _check(not source.is_empty(),"interaction_actual_configured_action_"+label): return false
	if not _check(not Scene.Mapper.action_pressed(_scene.active_preset,{"keys":held,"mouse_buttons":[],"devices":[]},action),"interaction_action_released_before_edge_"+label): return false
	if not _interaction_sample(label+"-release",held,elapsed_us): return false
	var pressed: Array = held.duplicate()
	for key in source:
		if not pressed.has(key): pressed.append(key)
	if not _check(Scene.Mapper.action_pressed(_scene.active_preset,{"keys":pressed,"mouse_buttons":[],"devices":[]},action),"interaction_actual_bound_action_pressed_"+label): return false
	var prior_map: bool = _scene.map_visible
	if not _interaction_sample(label+"-press",pressed,elapsed_us): return false
	if action=="map_toggle":
		return _check(_scene.map_visible!=prior_map and _scene.flight_map.visible==_scene.map_visible,"interaction_mapper_edge_actually_toggles_map_"+label)
	return true

func _interaction_engine_rects() -> Dictionary:
	var result: Dictionary = {}
	for id in _scene.engine_controls._rects():
		var rect: Rect2 = _scene.engine_controls._rects()[id]
		var position: Vector2 = _scene.engine_controls.get_global_transform_with_canvas()*rect.position
		result[id]={"local_position":[rect.position.x,rect.position.y],"size":[rect.size.x,rect.size.y],"global_position":[position.x,position.y],
			"inside_viewport":Rect2(Vector2.ZERO,Vector2(_window.size)).encloses(Rect2(position,rect.size))}
	return result

func _interaction_shot(name: String, dimensions: Vector2i, phase: String) -> void:
	_scene.show_state(0.0)
	var before: Dictionary = _interaction_snapshot()
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var image: Image = _window.get_texture().get_image()
	var path: String = _output.path_join(name+".png")
	var saved: bool = false
	if _check(image!=null and image.get_size()==dimensions,"interaction_actual_dimensions_"+name) and _check(not FileAccess.file_exists(path),"interaction_fresh_png_"+name):
		saved=_check(image.save_png(path)==OK,"interaction_saved_png_"+name)
	var after: Dictionary = _interaction_snapshot()
	_check(var_to_bytes(before)==var_to_bytes(after),"interaction_draw_only_full_snapshot_invariance_"+name)
	var before_file: Dictionary = _truth_file(name+".before.truth",before)
	var after_file: Dictionary = _truth_file(name+".after.truth",after)
	_check(not before_file.is_empty() and before_file.get("sha256")==after_file.get("sha256"),"interaction_saved_draw_pair_exact_"+name)
	var controls: Control = _scene.controls_panel
	var engine: Control = _scene.engine_controls
	_views.append({"file":name+".png","saved":saved,"bytes":FileAccess.get_file_as_bytes(path).size() if saved else 0,"sha256":FileAccess.get_sha256(path) if saved else "",
		"phase":phase,"requested_window":[dimensions.x,dimensions.y],"actual_window":[_window.size.x,_window.size.y],"camera_mode":_scene.camera_mode,
		"truth_before_file":before_file,"truth_after_file":after_file,"native":_scene.facade.readback(),"raw":_scene.collect_input_raw(),
		"layout":_layout(),"controls_layout":_rect(controls),"controls_labels":_label_rows(controls),
		"engine_layout":_rect(engine),"engine_expanded":engine.is_expanded(),"engine_control_rectangles":_interaction_engine_rects(),
		"menu_layout":_rect(_scene.menu),"resume_layout":_rect(_scene.resume_button),
		"status":{"scene":_scene.status,"briefing":_scene.first_flight_panel._status.text,"actual":_scene.first_flight_panel._actual.text,
			"controls":controls._status_label.text if controls._status_label!=null else "","engine":_scene.engine_status.duplicate(true),
			"native_draw_info":_scene.panel._info.duplicate(true),"native_draw_held":_scene.panel._held.duplicate(true)},
		"circuit":{"enabled":_scene.circuit_aid_enabled,"card_view":_scene.circuit_card._view.duplicate(true),"map_view":_scene.flight_map._circuit.duplicate(true),"reason":_scene.circuit_card._reason.text},
		"map":{"visible":_scene.map_visible,"extent_m":_scene.flight_map.extent_m,"runway":_scene.flight_map._runway,"position":_scene.flight_map._position,"route":_scene.flight_map._route.duplicate(true)},
		"route_basis":_interaction_route_basis(),"bounds_are_not_pixel_acceptance":true})

func _interaction_button(root: Node, text: String) -> Button:
	if root is Button and root.text==text: return root as Button
	for child in root.get_children():
		var found: Button = _interaction_button(child,text)
		if found!=null: return found
	return null

func _interaction_ready(dimensions: Vector2i) -> void:
	var prefix: String = "interaction-"+str(dimensions.x)
	_scene.synthetic_raw={"keys":[],"mouse_buttons":[],"devices":[]}
	if not _ready_choice(): return
	# Reject an unknown request through the real guarded consumer before flight.
	var paused_prefix: PackedByteArray = var_to_bytes(_authority())
	_scene.on_first_flight_choice("unknown-observer-choice",_scene.first_flight_source_session(),_scene.first_flight_panel)
	var negative: bool = _check(var_to_bytes(_authority())==paused_prefix and _scene.first_flight_open,"interaction_unknown_choice_has_no_effect_"+prefix)
	_interaction_negatives.append({"label":prefix+"-unknown-choice","unchanged_full_authority":negative})
	_back()
	_scene.open_landmark_route(); _scene.choose_landmark_route([0,1])
	if not _check(not _scene.route_open and _scene.route_view.get("active")==true,"interaction_real_existing_route_"+prefix): return
	if not _set_aid(true): return
	if not _scene.map_visible and not _interaction_edge("map_toggle",[],prefix+"-map-open"): return
	if _scene.flight_map._runway!=36:
		if not _interaction_edge("runway_toggle",[],prefix+"-runway36"): return
	# Binding-driven zoom, no fit/recenter/direct extent or route assignment.
	for index in 6:
		if not _interaction_edge("map_zoom_in",[],prefix+"-zoom-"+str(index)): return
	if _scene.brake_hold:
		if not _interaction_edge("brake_hold",[],prefix+"-release-brake-latch"): return
	if not _interaction_sample(prefix+"-baseline",[],25000): return
	_scene.set_camera_mode(0); _scene.show_state(0.0)
	if not _check(_scene.map_visible and _scene.flight_map.extent_m==1000.0 and _scene.flight_map._runway==36 and _scene.circuit_card._view.get("available")==true,"interaction_live_available_map_circuit_"+prefix): return
	_check(_scene.flight_map._circuit.points_anchor_eus_m.size()==6 and _scene.flight_map._circuit.leg_labels.size()==5,"interaction_actual_fixed_geometry_not_empty_"+prefix)
	var start: Dictionary = _scene.facade.readback()
	if not _check(start.held_axes.left_brake==0.0 and start.held_axes.right_brake==0.0,"interaction_native_brakes_actually_released_"+prefix): return
	var basis: PackedByteArray = var_to_bytes(_interaction_route_basis())
	await _interaction_shot(prefix+"-ready-before-controls",dimensions,"Actual resumed ready-ground source, map/circuit available, native brakes released through configured mapper action")
	var held: Array = []
	for target in ["throttle","pitch","roll","yaw"]:
		var source: Array = _interaction_axis_keys(target)
		if not _check(not source.is_empty(),"interaction_configured_positive_axis_"+prefix+"-"+target): return
		for key in source:
			if not held.has(key): held.append(key)
	if not _interaction_takeoff(prefix,basis): return
	# Brief deliberate nonzero control exercise after actual ground-to-air flight.
	for index in 2:
		if not _interaction_sample(prefix+"-active-"+str(index),held,25000): return
	var actual: Dictionary = _scene.facade.readback()
	for target in ["throttle","pitch","roll","yaw"]:
		_check(absf(float(actual.held_axes[target]))>0.0 and actual.held_axes[target]==_scene.controls[target],"interaction_nonzero_mapped_native_axis_"+prefix+"-"+target)
	_check(var_to_bytes(actual.canonical)!=var_to_bytes(start.canonical),"interaction_actual_native_motion_observed_"+prefix)
	_check(var_to_bytes(_interaction_route_basis())==basis,"interaction_active_controls_preserve_manual_route_and_extent_"+prefix)
	if not _interaction_airborne(prefix+"-after-controls"): return
	await _interaction_shot(prefix+"-ready-after-controls",dimensions,"Actual settled ready-ground takeoff, all3contacts false and native clearance above10m; ordinary nonzero throttle/pitch/roll/yaw feedback with available map/circuit. Test feedback, not human handling")
	# Hold ordinary axes continuously; map action edges travel through actual Raw
	# and mapper. Add actual both-brakes action and verify native admitted feedback.
	held.append_array(_interaction_keys("both_brakes"))
	if not _interaction_edge("map_toggle",held,prefix+"-active-map-close",25000): return
	_check(not _scene.map_visible and not _scene.flight_map.visible,"interaction_active_map_closed_"+prefix)
	_check(_scene.facade.readback().held_axes.left_brake==1.0 and _scene.facade.readback().held_axes.right_brake==1.0,"interaction_both_brakes_native_admitted_"+prefix)
	_check(var_to_bytes(_interaction_route_basis())==basis,"interaction_closed_manual_route_and_extent_"+prefix)
	if not _interaction_airborne(prefix+"-map-closed"): return
	await _interaction_shot(prefix+"-ready-map-closed",dimensions,"Actual mapper map-close edge with nonzero ordinary axes continuing and both native brakes admitted; existing manual route card restored")
	if not _interaction_edge("map_toggle",held,prefix+"-active-map-restore",25000): return
	_check(_scene.map_visible and _scene.flight_map.visible and _scene.circuit_card._view.get("available")==true,"interaction_active_map_restored_"+prefix)
	_check(var_to_bytes(_interaction_route_basis())==basis,"interaction_restored_manual_route_and_extent_"+prefix)
	if not _interaction_airborne(prefix+"-map-restored"): return
	await _interaction_shot(prefix+"-ready-map-restored",dimensions,"Actual mapper restore edge with axes/brakes continuing; available circuit and unchanged manual route/extent")
	_interaction_controls.append({"size":[dimensions.x,dimensions.y],"initial":start,"after_axes":actual,"after_map_restore":_scene.facade.readback(),
		"held_raw_keys":held.duplicate(),"map_route_basis":_interaction_route_basis(),"actual_ready_ground_takeoff":true,"physical_input_delivery":false})

func _interaction_cold(dimensions: Vector2i) -> void:
	var prefix: String = "interaction-"+str(dimensions.x)
	_scene.synthetic_raw={"keys":[],"mouse_buttons":[],"devices":[]}
	_scene.open_first_flight()
	if not _check(_scene.first_flight_open and _scene.facade.readback().paused,"interaction_cold_ordinary_pause_"+prefix): return
	_scene.first_flight_panel._choice_buttons[0].pressed.emit()
	if not _scene.pending_discard.is_empty():
		_check(_scene.get_viewport().gui_get_focus_owner()==_scene.discard_cancel,"interaction_cold_discard_default_cancel_"+prefix)
		_scene.discard_accept.pressed.emit()
	var initial: Dictionary = _scene.facade.readback()
	if not _check(Readings.from_readback(initial).state=="paused" and initial.tick=="0" and initial.named_start=="piston-cold-ground" and initial.model_identity==Scene.Facade.PISTON_PROFILE and _scene.first_flight_open,"interaction_cold_full_admission_paused_tick0_"+prefix): return
	_check(not _scene.circuit_aid_enabled,"interaction_cold_fresh_aid_off_"+prefix)
	_scene.circuit_checkbox.button_pressed=true
	await _tab(0)
	_scene.set_camera_mode(0)
	await _interaction_shot(prefix+"-cold-briefing-state",dimensions,"Ordinary cold choice adopted paused tick0; actual cold state and unavailable optional circuit choice, no engine automation")
	var native_before: PackedByteArray = var_to_bytes(_scene.facade.readback())
	_scene.first_flight_panel._controls.pressed.emit()
	_check(_scene.controls_panel.visible and not _scene.first_flight_open and _scene.facade.readback().paused and _scene.facade.readback().tick=="0","interaction_cold_actual_Controls_paused0_"+prefix)
	_check(var_to_bytes(_scene.facade.readback())==native_before,"interaction_cold_Controls_native_truth_preserved_"+prefix)
	await _interaction_shot(prefix+"-cold-controls",dimensions,"Actual briefing Controls callback opens ordinary paused v2 Controls; configured bindings and observed availability are not fabricated")
	var cancel: Button = _interaction_button(_scene.controls_panel,"Cancel")
	if not _check(cancel!=null and cancel.is_visible_in_tree(),"interaction_actual_Controls_Cancel_present_"+prefix): return
	cancel.pressed.emit()
	_check(not _scene.controls_panel.visible and _scene.menu_open and _scene.facade.readback().tick=="0" and _scene.facade.readback().paused,"interaction_actual_Controls_Cancel_returns_paused0_"+prefix)
	# Exercise actual First flight Back after the Controls round-trip as well.
	_scene.open_first_flight(); _back()
	_check(var_to_bytes(_scene.facade.readback())==native_before,"interaction_cold_Back_native_truth_preserved_"+prefix)
	await _interaction_shot(prefix+"-cold-back-menu",dimensions,"Actual Controls Cancel and First flight Back return to visible ordinary paused menu; explicit Resume remains reachable at tick0")
	if not _resume(): return
	# Resume does not schedule show_state while this isolated host is manually
	# driven. Let the ordinary presentation/layout expose the real header first.
	var header_native: PackedByteArray = var_to_bytes(_scene.facade.readback())
	_scene.show_state(0.0)
	await _host.get_tree().process_frame; await _host.get_tree().process_frame
	_scene.show_state(0.0)
	var header_local: Rect2 = Rect2(Vector2.ZERO,Vector2(_scene.engine_controls.size.x,30.0))
	var header_global: Rect2 = Rect2(_scene.engine_controls.global_position,header_local.size)
	var header_layout: Dictionary = _rect(_scene.engine_controls)
	if not _check(_scene.engine_controls.is_visible_in_tree() and _scene.engine_controls.size.x>0.0 and _scene.engine_controls.size.y>=30.0 and Rect2(Vector2.ZERO,Vector2(dimensions)).encloses(header_global),"interaction_actual_engine_header_visible_laid_out_"+prefix): return
	if not _check(var_to_bytes(_scene.facade.readback())==header_native,"interaction_engine_header_layout_native_truth_preserved_"+prefix): return
	# Invoke the real header callback, not a forced visibility or expanded flag.
	var header_pressed: bool = not _scene.engine_controls.is_expanded()
	if not _scene.engine_controls.is_expanded():
		var press: InputEventMouseButton = InputEventMouseButton.new()
		press.button_index=MOUSE_BUTTON_LEFT; press.pressed=true; press.position=Vector2(minf(16.0,header_local.size.x*0.5),15.0)
		_scene.engine_controls._gui_input(press)
		var release: InputEventMouseButton = InputEventMouseButton.new()
		release.button_index=MOUSE_BUTTON_LEFT; release.pressed=false; release.position=press.position
		_scene.engine_controls._gui_input(release)
	_scene.show_state(0.0)
	await _host.get_tree().process_frame; await _host.get_tree().process_frame
	_scene.show_state(0.0)
	if not _check(_scene.engine_controls.is_expanded() and _scene.engine_controls.is_visible_in_tree(),"interaction_actual_engine_header_expands_"+prefix): return
	if not _check(var_to_bytes(_scene.facade.readback())==header_native,"interaction_engine_header_callback_native_truth_preserved_"+prefix): return
	if not _scene.map_visible and not _interaction_edge("map_toggle",[],prefix+"-cold-map-open"): return
	_scene.show_state(0.0)
	var cold: Dictionary = _scene.facade.readback()
	var engine: Dictionary = Scene.EngineStatus.from_readback(cold)
	_check(cold.tick=="0" and Readings.from_readback(cold).state=="live" and engine.readings["engine.running"].valid and engine.readings["engine.running"].value==false and engine.readings["engine.starter"].value==false,"interaction_cold_explicit_Resume_no_hidden_Run_or_start_"+prefix)
	_check(_scene.circuit_aid_enabled and _scene.circuit_card.visible and not _scene.circuit_card._view.available and _scene.flight_map._circuit.is_empty(),"interaction_cold_explicit_unavailable_no_stale_geometry_"+prefix)
	await _interaction_shot(prefix+"-cold-live-map-open",dimensions,"Ordinary explicit Resume cold tick0, engine stopped/starterOFF, actual expanded engine UI and compact unavailable notice; existing map overlap scope retained")
	if not _interaction_edge("map_toggle",[],prefix+"-cold-map-close"): return
	_check(_scene.facade.readback().tick=="0" and not _scene.map_visible,"interaction_cold_bound_map_close_no_Run_"+prefix)
	await _interaction_shot(prefix+"-cold-live-map-closed",dimensions,"Actual mapper-bound map close; ordinary resumed cold engine UI and complete unavailable notice, no hidden menu or Run")
	_sessions.append({"session_id":initial.session_id,"readback":initial,"cold_final":_scene.facade.readback(),"engine_header_delivery":"actual GUI callback when collapsed, synthetic event; not OS pointer delivery","engine_header_pressed":header_pressed,"engine_header_before":header_layout,"engine_header_after":_rect(_scene.engine_controls),"engine_header_native_truth_preserved":var_to_bytes(_scene.facade.readback())==header_native})

func run_interaction(host: Node, output_root: String) -> Dictionary:
	_host=host; _window=host.get_tree().root; _output=output_root
	_checks=0; _failures=[]; _views=[]; _sessions=[]; _map_toggles=[]; _map_sequences=[]; _joined=false; _audio_joined=false
	_interaction_steps=[]; _interaction_controls=[]; _interaction_negatives=[]; _interaction_flight_rows=[]; _interaction_flight_segments=[]
	_interaction_codec_checks()
	if not _check(_output_ok(output_root),"interaction_fresh_external_output"): return {"passed":false,"failures":_failures}
	if not _check(OS.get_name()=="Windows" and DisplayServer.get_name()!="headless" and RenderingServer.get_current_rendering_method()=="gl_compatibility","interaction_actual_Windows_Compatibility_GPU"): return {"passed":false,"failures":_failures}
	var adapter: String = RenderingServer.get_video_adapter_name().to_lower()
	if not _check(not adapter.is_empty(),"interaction_actual_adapter_present"): return {"passed":false,"failures":_failures}
	for fallback in ["llvmpipe","softpipe","software","warp","microsoft basic render"]:
		if not _check(not adapter.contains(fallback),"interaction_no_software_"+fallback): return {"passed":false,"failures":_failures}
	if host is Scene and not _check(host.facade==null,"interaction_caller_has_no_owner_flight"): return {"passed":false,"failures":_failures}
	_source_before=_interaction_sources()
	for path in _source_before: _check(_source_before[path].bytes>0 and str(_source_before[path].sha256).length()==64,"interaction_actual_source_present_"+path)
	if not _failures.is_empty(): return {"passed":false,"failures":_failures}
	var previous_size: Vector2i = _window.size
	var previous_gui: bool = _window.gui_disable_input
	var previous_mouse: int = Input.mouse_mode
	_window.gui_disable_input=true
	_scene=MutableRawScene.new(); host.add_child(_scene)
	_scene.set_process(false); _scene.set_physics_process(false); _scene.set_process_input(false)
	_scene.set_process_unhandled_input(false); _scene.set_process_unhandled_key_input(false); _scene.set_process_shortcut_input(false)
	if _scene.sound!=null: _scene.sound.set_process(false)
	var focus_callback: Callable = Callable(_scene,"on_focus_lost")
	if _window.focus_exited.is_connected(focus_callback): _window.focus_exited.disconnect(focus_callback)
	var device_callback: Callable = Callable(_scene,"on_joy_connection_changed")
	if Input.joy_connection_changed.is_connected(device_callback): Input.joy_connection_changed.disconnect(device_callback)
	var roster: Array[String] = []
	for dimensions in SIZES:
		for suffix in ["ready-before-controls","ready-after-controls","ready-map-closed","ready-map-restored","cold-briefing-state","cold-controls","cold-back-menu","cold-live-map-open","cold-live-map-closed"]:
			roster.append("interaction-"+str(dimensions.x)+"-"+suffix+".png")
	if _check(_scene.facade!=null and _scene.mapper!=null and _scene.first_flight_panel!=null and _scene.circuit_card!=null and _scene.engine_controls!=null,"interaction_actual_integrated_owners_present"):
		for dimensions in SIZES:
			DisplayServer.window_set_size(dimensions); _window.size=dimensions
			await host.get_tree().process_frame; await host.get_tree().process_frame
			if not _check(_window.size==dimensions,"interaction_actual_window_"+str(dimensions)): break
			await _interaction_ready(dimensions)
			if not _failures.is_empty(): break
			await _interaction_cold(dimensions)
			if not _failures.is_empty(): break
	var actual_roster: Array[String] = []
	for view in _views: actual_roster.append(view.file)
	_check(actual_roster==roster and _views.size()==27,"interaction_exact_twenty_seven_original_views")
	_check(_interaction_controls.size()==3 and _interaction_negatives.size()==3,"interaction_all_three_control_and_negative_witnesses")
	_joined=_scene.close_session(); _check(_joined,"interaction_actual_native_join")
	_audio_joined=true
	if _scene.sound!=null: _audio_joined=bool(await _scene.sound.shutdown())
	_check(_audio_joined,"interaction_actual_audio_join")
	_check(_scene.failures.is_empty(),"interaction_actual_scene_clean")
	var closed: Dictionary = _scene.facade.readback() if _scene.facade!=null else {}
	_scene.free()
	var source_after: Dictionary = _interaction_sources()
	_check(source_after==_source_before,"interaction_all_source_bytes_unchanged")
	DisplayServer.window_set_size(previous_size); _window.size=previous_size
	_window.gui_disable_input=previous_gui; Input.mouse_mode=previous_mouse
	var receipt: Dictionary = {"schema":"FirstFlightInteraction/v1","passed":_failures.is_empty(),"checks":_checks,"failures":_failures.duplicate(),
		"expected_roster":roster,"views":_views.duplicate(true),"steps":_interaction_steps.duplicate(true),"flight_intervals":_interaction_flight_rows.duplicate(true),"flight_segments":_interaction_flight_segments.duplicate(true),"controls":_interaction_controls.duplicate(true),"negative_cases":_interaction_negatives.duplicate(true),
		"sessions":_sessions.duplicate(true),"sources_before":_source_before,"sources_after":source_after,"native_joined":_joined,"audio_joined":_audio_joined,"closed_readback":closed,
		"display_backend":DisplayServer.get_name(),"renderer":RenderingServer.get_current_rendering_method(),"adapter":RenderingServer.get_video_adapter_name(),"engine":Engine.get_version_info(),"editor":OS.has_feature("editor"),
		"scope":"Separate27-view bounded actual-native observer. Mutable complete synthetic Raw travels through actual mapper and ordinary scene submission/Run. Existing original wholeflight TEST-ONLY desired-input feedback is quantized through unchanged configured key-pair bindings, never direct axes/native mutation. Each size must settle allWOW then actually takeoff to all3contacts false and native plane clearance above10m, with available map/circuit; map closes/restores while nonzero axes/brakes continue. Full transition/segment snapshots intentionally change; only paired sampled draw snapshots are invariant. Commands are actual facade-decoded native replies, not retained original step JSON; only their numeric payload uses the accepted8EPS codec allowance, with nativeheld==mapped and provenance exact. Cold uses ordinary choice/discard/Controls/Back/Resume and native tick0 with stopped engine, no hidden menu/automatic start. Host scheduling is explicit; no landing/physical input, continuous-flight/performance, owner data, pilot/hardware, C172S/procedure/training-credit or phase acceptance. Original39-view run is separate and unchanged."}
	var receipt_path: String = _output.path_join("interaction-receipt.json")
	if _check(not FileAccess.file_exists(receipt_path),"interaction_fresh_receipt"):
		var file: FileAccess = FileAccess.open(receipt_path,FileAccess.WRITE)
		if _check(file!=null,"interaction_receipt_open"):
			receipt.passed=_failures.is_empty(); receipt.checks=_checks; receipt.failures=_failures.duplicate()
			file.store_string(JSON.stringify(receipt,"  ",false,true)); file.close()
	receipt.passed=_failures.is_empty(); receipt.checks=_checks; receipt.failures=_failures.duplicate()
	return receipt
