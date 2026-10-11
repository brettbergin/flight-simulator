extends RefCounted
## Original MIT. Synthetic assignment fixtures and actual full supplied Readback.
const FirstFlightPanel = preload("res://ui/first_flight/briefing_panel.gd")
const Help = preload("res://ui/first_flight/binding_help.gd")
const Mapper = preload("res://input/input_mapper.gd")
const Preset = preload("res://input/input_preset.gd")
const Readings = preload("res://cockpit/instruments/native_readings.gd")
const EngineStatus = preload("res://cockpit/instruments/engine_status.gd")
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
func _inside_scroll(control: Control, scroll: ScrollContainer) -> bool:
	return control.is_visible_in_tree() and scroll.get_global_rect().encloses(control.get_global_rect())
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
	# The real Scene owns this child; use the same visible caption/height in this leaf fixture.
	var circuit: CheckBox = CheckBox.new()
	circuit.text="Show optional synthetic circuit reference (not evaluated)"
	circuit.add_theme_font_size_override("font_size",16); circuit.custom_minimum_size.y=36
	panel.circuit_slot.add_child(circuit)
	var input_preset: Dictionary = _preset(1)
	panel.set_state(readback,input_preset,"calm")
	var copied_session: String = readback.session_id
	input_preset.actions.clear()
	var mutable_readback: Dictionary = readback.duplicate(true); panel.set_state(mutable_readback,_preset(1),"calm")
	mutable_readback.model_identity.id="changed"
	_check(panel._readback.model_identity==readback.model_identity and panel._help.available,"panel_owned_inputs")
	_check(panel._qualified.state=="paused" and panel._source_session()==copied_session and "Model: "+str(readback.model_identity.id) in panel._actual.text and "wind NED" in panel._actual.text and "Wind preset: calm" in panel._actual.text and "True airspeed:" in panel._actual.text and "Native-held controls:" in panel._actual.text,"actual_adopted_readback")
	_check(panel._tabs.get_child_count()==4 and panel._tabs.get_child(3).name=="Details","details_appended_existing_tab_order")
	_check(panel._tabs.get_child(0).name=="Start & state" and panel._tabs.get_child(1).name=="Control help" and panel._tabs.get_child(2).name=="Software steps","existing_tab_indices")
	_check(panel._choice_buttons.size()==3 and panel._cards.size()==3,"three_bounded_starting_points")
	_check("Recorded flight and engine review available" in panel._card_facts[0].text and "Idealized starter supply" in panel._card_facts[0].text,"cold_current_review_and_starter_caveat")
	_check("Startup is skipped" in panel._card_facts[1].text and "Legacy observed review available" in panel._card_facts[1].text,"ready_skipped_startup_and_review_caveat")
	_check("Start, taxi and takeoff are skipped" in panel._card_facts[2].text and "initialized state" in panel._card_facts[2].text,"airborne_skipped_work_and_state_caveat")
	for choice in FirstFlightPanel._fixture_check().value.choices:
		for fact in choice.required_truth: _check(fact in panel._choice_details.text,"full_fixture_fact_in_details_"+fact)
	_check("Source state:" in panel._details_source.text and copied_session in panel._details_source.text and "tick "+str(readback.tick) in panel._details_source.text,"complete_source_details")
	_check(not copied_session in panel._status.text and not "tick " in panel._status.text and "Paused" in panel._summary.text,"compact_state_discloses_technical_source")
	_check("Start:" in panel._summary.text and "Adopted wind: calm" in panel._summary.text and "TAS" in panel._summary.text,"actual_summary_labels")
	if readback.model_identity!=Readings.PISTON_PROFILE:
		_check("Engine status unavailable" in panel._summary.text,"legacy_engine_not_inferred_from_start")
	elif readback.named_start=="piston-cold-ground":
		# Inspect the actual supplied native channel; never infer stopped/running from this named start.
		var engine: Dictionary = EngineStatus.from_readback(readback)
		var running: Dictionary = engine.readings["engine.running"]
		var expected_engine: String = ("Engine running" if running.value else "Engine off") if running.valid else "Engine status unavailable"
		_check(expected_engine in panel._summary.text,"actual_piston_cold_summary_channel")
		_check("Native engine.running: "+(str(running.value) if running.valid else "unavailable") in panel._actual.text and "Circuit reference unavailable for this start" in panel._actual.text,"actual_cold_engine_and_legitimate_circuit_limit")
	panel._tabs.current_tab=3; panel.set_state(readback,_preset(1),"calm")
	_check(panel._tabs.current_tab==3 and _events.is_empty(),"details_selection_retained_no_requests")
	panel._tabs.current_tab=0
	panel._change_step(1); panel.set_state(readback,_preset(1),"calm")
	_check(panel._step_index==1 and _events.is_empty(),"manual_step_retained_no_events")
	panel._change_step(999); _check(panel._step_index==3,"manual_upper_bound")
	panel._change_step(-999); _check(panel._step_index==0,"manual_lower_bound")
	panel._request_choice("READY-FLIGHT"); _check(_events.is_empty(),"unknown_request_no_event")
	for i in FirstFlightPanel.CHOICE_IDS.size():
		panel._choice_buttons[i].pressed.emit()
		_check(_events.back()==["choice",FirstFlightPanel.CHOICE_IDS[i],copied_session],"actual_button_exact_choice_"+str(i))
	_events.clear()
	panel._request_choice("ready-flight"); panel._request_controls(); panel._request_back()
	_check(_events==[["choice","ready-flight",copied_session],["controls",copied_session],["back",copied_session]],"only_bounded_signals")
	panel.hide(); panel._request_choice("ready-flight"); panel._request_controls(); panel._request_back()
	_check(_events.size()==3 and not panel.visible,"hidden_widget_no_events")
	panel.set_state(readback,_preset(1),"calm"); _check(not panel.visible,"set_state_does_not_show")
	panel.show(); panel.set_state({},_preset(1),"calm")
	_check(panel._source_session().is_empty() and "unavailable" in panel._actual.text.to_lower(),"invalid_visible_no_session")
	_check("State unavailable" in panel._status.text and "Malformed exact Readback shape" in panel._summary.text,"malformed_empty_dictionary_is_invalid")
	# Synthetic copied presentation states only; these do not claim native lifecycle transitions.
	var empty: Dictionary = readback.duplicate(true)
	for key in Readings.NULLABLE: empty[key]=null
	empty.host_mode="closed"; empty.historical=true; empty.native_live=false; empty.paused=false; empty.debt_quanta=0; empty.time_scale=1.0
	panel.set_state(empty,_preset(1),"calm")
	_check(panel._qualified.state=="empty" and panel._source_session().is_empty() and "No current flight" in panel._status.text and "unavailable" in panel._summary.text.to_lower(),"qualified_empty_honest_summary")
	var retained: Dictionary = readback.duplicate(true)
	retained.host_mode="closed"; retained.historical=true; retained.native_live=false; retained.paused=false; retained.debt_quanta=0
	panel.set_state(retained,_preset(1),"calm")
	_check(panel._qualified.state=="historical" and panel._source_session().is_empty() and "Historical / view-only" in panel._status.text and "not a current flight" in panel._summary.text,"historical_not_current_summary")
	_check(not panel._choice_buttons[0].disabled,"historical_preserves_fresh_choice_admission")
	var live: Dictionary = readback.duplicate(true); live.host_mode="live"; live.paused=false
	panel.set_state(live,_preset(1),"calm")
	_check(panel._qualified.state=="live" and "Running" in panel._status.text and panel._source_session()==copied_session,"live_source_visible")
	for button in panel._choice_buttons: _check(button.disabled,"live_choice_disabled")
	var malformed: Dictionary = readback.duplicate(true); malformed.session_id=42
	panel.set_state(malformed,_preset(1),"calm")
	_check(panel._qualified.state=="invalid" and panel._source_session().is_empty() and "State unavailable" in panel._status.text,"invalid_visible_source_error")
	for button in panel._choice_buttons: _check(button.disabled,"invalid_choice_disabled")
	panel.set_state(readback,{},"calm")
	_check("Binding help unavailable" in panel._binding_text.text and not panel._help.available,"invalid_bindings_no_defaults_visible")
	panel.set_state(readback,_preset(1),"calm")
	var fixture_bytes: PackedByteArray = FileAccess.get_file_as_bytes(FirstFlightPanel.FIXTURE_PATH)
	_check(FirstFlightPanel.validate_fixture_bytes(fixture_bytes).ok,"exact_fixture_still_admitted")
	var altered: PackedByteArray = fixture_bytes.duplicate(); altered.append(32)
	_check(not FirstFlightPanel.validate_fixture_bytes(altered).ok,"changed_fixture_still_rejected")
	# Explicit local content-error fixture; no file mutation and no native state fabrication.
	panel._fixture={}; panel._fixture_error="Briefing unavailable: synthetic missing fixture"; panel._refresh()
	_check("Starting points unavailable" in panel._status.text and "synthetic missing fixture" in panel._details_source.text,"fixture_error_visible_details")
	for button in panel._choice_buttons: _check(button.disabled,"fixture_error_disables_choices")
	_check("facts unavailable" in panel._card_facts[0].text and not "Recorded flight and engine review available" in panel._card_facts[0].text,"fixture_error_no_old_accepted_facts")
	panel.set_state(readback,_preset(1),"calm")
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
		_check(panel._shell.size.x<=1120 and panel._shell.size.y<=720,"bounded_surface_"+str(size_value))
		_check(panel._shell.position.is_equal_approx((panel.size-panel._shell.size)*0.5),"centered_surface_"+str(size_value))
		_check(panel._shell.position.x>=16 and panel._shell.position.y>=16,"viewport_clearance_"+str(size_value))
		panel._tabs.current_tab=0
		await host.get_tree().process_frame; await host.get_tree().process_frame
		var start_scroll: ScrollContainer = panel._tabs.get_child(0)
		_check(_inside_scroll(panel._summary,start_scroll) and _inside_scroll(circuit,start_scroll) and _inside_scroll(panel._circuit_hint,start_scroll),"start_context_and_circuit_visible_"+str(size_value))
		for i in panel._cards.size():
			_check(_inside_scroll(panel._cards[i],start_scroll) and _inside_scroll(panel._choice_buttons[i],start_scroll),"complete_card_cta_visible_"+str(size_value)+"_"+str(i))
			_check(panel._card_titles[i].get_theme_font_size("font_size")==20 and panel._card_facts[i].get_theme_font_size("font_size")==13,"legible_card_fonts_"+str(size_value)+"_"+str(i))
			_check(panel._choice_buttons[i].size.y>=36 and not panel._choice_buttons[i].disabled,"available_cta_hit_"+str(size_value)+"_"+str(i))
			for caption in panel._cards[i].get_child(0).get_child(0).get_children():
				if caption is Label:
					_check(panel._cards[i].get_global_rect().encloses(caption.get_global_rect()) and caption.size.y>=caption.get_combined_minimum_size().y,"full_card_label_layout_"+str(size_value)+"_"+str(i)+"_"+caption.text)
			if i>0: _check(panel._cards[i-1].get_global_rect().end.x<=panel._cards[i].get_global_rect().position.x,"separate_cards_"+str(size_value)+"_"+str(i))
			panel._choice_buttons[i].grab_focus(); _check(panel._choice_buttons[i].has_focus(),"choice_focus_"+str(size_value)+"_"+str(i))
		panel._tabs.current_tab=3
		await host.get_tree().process_frame; await host.get_tree().process_frame
		_check(panel._actual.is_visible_in_tree() and panel._details_source.is_visible_in_tree(),"details_accessible_"+str(size_value))
		_check(panel._shell.get_global_rect().encloses(panel._limits.get_global_rect()),"persistent_limits_"+str(size_value))
		panel._tabs.current_tab=0
		panel.focus_back(); _check(panel._back.has_focus(),"back_focus_"+str(size_value))
	_check(not panel.has_signal("resume_requested") and panel._back.tooltip_text.contains("still paused") and not panel._controls.tooltip_text.is_empty(),"no_resume_synchronous_tooltips")
	_check(_events.size()==3,"presentation_changes_no_additional_requests")
	_check(var_to_bytes(readback)==original,"full_supplied_readback_unchanged")
	panel.queue_free(); window.size=old_size; await host.get_tree().process_frame
	return {"passed":_failures.is_empty(),"checks":_checks,"failures":_failures,"limits":"Headless synthetic assignments and copied presentation; no native/lifecycle, GPU, hardware or pilot acceptance"}
