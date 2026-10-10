extends RefCounted
## Original MIT. Synthetic assignment fixtures and actual full supplied Readback.
const FirstFlightPanel = preload("res://ui/first_flight/briefing_panel.gd")
const Help = preload("res://ui/first_flight/binding_help.gd")
const Mapper = preload("res://input/input_mapper.gd")
const Preset = preload("res://input/input_preset.gd")
const Readings = preload("res://cockpit/instruments/native_readings.gd")
var _host: Node
var _checks: int = 0
var _failures: Array[String] = []
var _events: Array = []
func _check(ok: bool, label: String) -> void:
	_checks+=1
	if not ok: _failures.append(label)
	if _host.has_method("check"): _host.call("check",ok,"first_flight_ui_"+label)
func _row(rows: Array,id: String) -> Dictionary:
	for row in rows:
		if row.id==id: return row
	return {}
func _preset(version: int) -> Dictionary:
	var preset: Dictionary = Mapper.default_preset_v2() if version==2 else Mapper.default_preset()
	preset.devices=[{"slot":"training-stick","label":"Synthetic configured reference only","match":{"guid":"","name":"","vendor_id":"","product_id":""}}]
	for i in preset.axes.size():
		var target: String = preset.axes[i].target
		preset.axes[i]={"target":target,"kind":"fixed","value":1.0 if target=="mixture" else 0.0}
	preset.actions=[]
	for i in Help.ACTIONS.size():
		var id: String = Help.ACTIONS[i]
		var source: Dictionary = {"kind":"physical_keys","keys":[KEY_A+i]}
		if id=="look_hold": source={"kind":"mouse_button","button":8}
		elif id=="map_toggle": source={"kind":"joy_button","slot":"training-stick","index":2}
		preset.actions.append({"id":id,"sources":[source]})
	if version==2:
		for i in preset.systems.size(): preset.systems[i].sources=[{"kind":"joy_button","slot":"training-stick","index":4+i}]
	return preset
func _choice(id: String,session: String) -> void: _events.append(["choice",id,session])
func _controls(session: String) -> void: _events.append(["controls",session])
func _back(session: String) -> void: _events.append(["back",session])
func run(host: Node, readback: Dictionary = {}) -> Dictionary:
	_host=host; _checks=0; _failures=[]; _events=[]
	for version in [1,2]:
		var preset: Dictionary = _preset(version)
		var before: PackedByteArray = var_to_bytes(preset)
		var view: Dictionary = Help.view(preset)
		_check(view.available,"valid_remapped_v"+str(version))
		_check(view.actions.size()==14 and view.axes.size()==6 and view.systems.size()==4,"exact_rosters_v"+str(version))
		for i in Help.ACTIONS.size():
			var id: String = Help.ACTIONS[i]
			var expected: String = OS.get_keycode_string(KEY_A+i)
			if id=="look_hold": expected="Mouse 8"
			elif id=="map_toggle": expected="CONFIGURED training-stick button 2"
			_check(_row(view.actions,id).text==expected,"remap_"+str(version)+"_"+id)
		_check("unverified here" in view.availability and "paused Controls" in view.availability,"unverified_v"+str(version))
		for i in Help.SYSTEMS.size():
			var row: Dictionary = _row(view.systems,Help.SYSTEMS[i])
			_check(row.available==(version==2),"actual_system_version_"+row.id)
			if version==2: _check("CONFIGURED training-stick button "+str(4+i) in row.text and ("momentary" if row.id=="engine.starter" else "toggle") in row.text,"system_remap_"+row.id)
		_check(var_to_bytes(preset)==before,"helper_input_immutable_v"+str(version))
		view.actions.clear(); _check(Help.view(preset).actions.size()==14,"helper_output_owned_v"+str(version))
		preset.actions.pop_back()
		_check(Help.view(preset).available and not _row(Help.view(preset).actions,"idle").available,"missing_optional_action_v"+str(version))
		preset.axes.pop_back(); _check(not Help.view(preset).available,"missing_required_axis_v"+str(version))
	var v1: Dictionary = _preset(1)
	for target in ["roll","throttle","trim"]:
		for i in v1.axes.size():
			if v1.axes[i].target==target:
				v1.axes[i]={"target":target,"kind":"joy_axis","slot":"training-stick","index":3,"range":"unsigned" if target=="throttle" else "centered","minimum":-1.0,"center":0.0,"maximum":1.0,"invert":target!="trim","deadzone":0.0,"saturation":1.0,"gain":1.0,"slew_per_s":0.0}
	var axes: Array = Help.view(v1).axes
	for target in ["roll","throttle","trim"]:
		_check("CONFIGURED training-stick axis 3" in _row(axes,target).text and ("Not reversed" if target=="trim" else "Reversed") in _row(axes,target).text,"axis_assignment_"+target)
	_check("unsigned" in _row(axes,"throttle").text and "Fixed 1" in _row(axes,"mixture").text,"unsigned_and_legacy_fixed")
	for version in [1,2]:
		var pair: Dictionary = _preset(version)
		var target: String = "pitch" if version==1 else "mixture"
		for i in pair.axes.size():
			if pair.axes[i].target==target: pair.axes[i]={"target":target,"kind":"key_pair","negative":[KEY_U],"positive":[KEY_O],"rate":0.25,"gain":1.0,"return_to_start":false}
		_check(Help.view(pair).available and "Negative: U" in _row(Help.view(pair).axes,target).text and "Positive: O" in _row(Help.view(pair).axes,target).text,"key_pair_"+target)
	for invalid in [null,{}, {"version":3},{"version":true}]:
		var invalid_view: Dictionary = Help.view(invalid)
		_check(not invalid_view.available and not invalid_view.error.is_empty() and not _row(invalid_view.actions,"pause_menu").available,"invalid_no_defaults")
	var bad_v2: Dictionary = _preset(2); bad_v2.systems.pop_back()
	_check(not Help.view(bad_v2).available,"missing_v2_system_rejected")
	bad_v2=_preset(2); bad_v2.systems[0].sources=bad_v2.actions[0].sources.duplicate(true)
	_check(not Help.view(bad_v2).available,"v2_conflict_rejected")
	var aliases: Dictionary = _preset(2)
	aliases.actions[0].sources=[{"kind":"physical_keys","keys":[KEY_F13,KEY_F14]},{"kind":"joy_button","slot":"training-stick","index":8}]
	aliases.systems[0].sources=[{"kind":"physical_keys","keys":[KEY_F15]}]
	aliases.systems[1].sources=[{"kind":"mouse_button","button":1}]
	var alias_view: Dictionary = Help.view(aliases)
	_check(alias_view.available and _row(alias_view.actions,"pause_menu").text=="F13/F14 OR CONFIGURED training-stick button 8","key_aliases_and_alternative_sources")
	_check("F15" in _row(alias_view.systems,"engine.ignition_left").text and "Mouse 1" in _row(alias_view.systems,"engine.ignition_right").text,"actual_v2_key_mouse_systems")
	aliases.profile.backend_model="fabricated"
	_check(not Help.view(aliases).available,"fabricated_v2_profile_rejected")
	aliases=_preset(2); aliases.actions[0].sources=[{"kind":"physical_keys","keys":[KEY_ESCAPE]}]
	_check(not Help.view(aliases).available,"reserved_escape_not_remapped")
	_check(Readings.from_readback(readback).state=="paused","supplied_full_actual_paused_baseline_required")
	if Readings.from_readback(readback).state!="paused":
		return {"passed":false,"checks":_checks,"failures":_failures,"error":"Full qualified paused Readback required; panel checks not executed"}
	var original: PackedByteArray = var_to_bytes(readback)
	var panel: Control = FirstFlightPanel.new(); host.add_child(panel)
	panel.choice_requested.connect(_choice); panel.controls_requested.connect(_controls); panel.back_requested.connect(_back)
	var window: Window = host.get_tree().root
	var old_size: Vector2i = window.size
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var input_preset: Dictionary = _preset(1)
	panel.set_state(readback,input_preset,"calm")
	var copied_session: String = readback.session_id
	input_preset.actions.clear()
	var mutable_readback: Dictionary = readback.duplicate(true); panel.set_state(mutable_readback,_preset(1),"calm")
	mutable_readback.model_identity.id="changed"
	_check(panel._readback.model_identity==readback.model_identity and panel._help.available,"panel_owned_inputs")
	_check(panel._source_session()==copied_session and "wind NED" in panel._actual.text and "unavailable" not in panel._actual.text,"actual_adopted_readback")
	panel._change_step(1); panel.set_state(readback,_preset(1),"calm")
	_check(panel._step_index==1 and _events.is_empty(),"manual_step_retained_no_events")
	panel._change_step(999); _check(panel._step_index==3,"manual_upper_bound")
	panel._change_step(-999); _check(panel._step_index==0,"manual_lower_bound")
	panel._request_choice("READY-FLIGHT"); _check(_events.is_empty(),"unknown_request_no_event")
	panel._request_choice("ready-flight"); panel._request_controls(); panel._request_back()
	_check(_events==[["choice","ready-flight",copied_session],["controls",copied_session],["back",copied_session]],"only_bounded_signals")
	panel.hide(); panel._request_choice("ready-flight"); panel._request_controls(); panel._request_back()
	_check(_events.size()==3 and not panel.visible,"hidden_widget_no_events")
	panel.set_state(readback,_preset(1),"calm"); _check(not panel.visible,"set_state_does_not_show")
	panel.show(); panel.set_state({},_preset(1),"calm")
	_check(panel._source_session().is_empty() and "unavailable" in panel._actual.text.to_lower(),"invalid_visible_no_session")
	for size_value in [Vector2i(960,540),Vector2i(1920,1080),Vector2i(2560,1440)]:
		window.size=size_value; panel.set_state(readback,_preset(1),"calm")
		await host.get_tree().process_frame; await host.get_tree().process_frame
		_check(window.size==size_value,"observed_window_"+str(size_value))
		for control in [panel._back,panel._controls,panel._status,panel._tabs]:
			_check(panel.get_global_rect().encloses(control.get_global_rect()),"reachable_"+str(size_value)+"_"+control.get_class())
		_check(panel._tabs.get_tab_bar().focus_mode==Control.FOCUS_ALL,"tab_focus_"+str(size_value))
		_check(panel._tabs.size.y>=150,"scroll_region_"+str(size_value))
		for tab in panel._tabs.get_children():
			_check(tab is ScrollContainer and tab.follow_focus,"scroll_focus_"+str(size_value))
		panel.focus_back(); _check(panel._back.has_focus(),"back_focus_"+str(size_value))
	_check(not panel.has_signal("resume_requested") and panel._back.tooltip_text.contains("still paused") and not panel._controls.tooltip_text.is_empty(),"no_resume_synchronous_tooltips")
	_check(var_to_bytes(readback)==original,"full_supplied_readback_unchanged")
	panel.queue_free(); window.size=old_size; await host.get_tree().process_frame
	return {"passed":_failures.is_empty(),"checks":_checks,"failures":_failures,"limits":"Headless synthetic assignments and copied presentation; no native/lifecycle, GPU, hardware or pilot acceptance"}
