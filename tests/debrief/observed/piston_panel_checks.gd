extends RefCounted
# Original MIT. Pure processed UI over supplied independently authored records.
# Root supplies decoded small v2 and frozen v1 references, never native objects.
const ObservedPanel=preload("res://ui/debrief/observed/panel.gd")
const Values=preload("res://replay/observed/values.gd")
const CHANNEL_LABELS={"fuel.total":"Fuel (kg)","propeller.angular_speed":"Shaft (RPM)","engine.throttle":"Actual throttle (fraction)","engine.mixture":"Actual mixture (fraction)","engine.running":"Engine running","engine.ignition_left":"Ignition L","engine.ignition_right":" / R","engine.starter":"Starter","fuel.feed":"Feed","engine.starved":"Starved"}
var _checks := 0
var _failures: Array[String]=[]
var _host: Node

func _check(ok: bool, name: String) -> bool:
	_checks+=1
	if not ok: _failures.append(name)
	return ok

func _settle() -> void:
	await _host.get_tree().process_frame
	await _host.get_tree().process_frame
	await _host.get_tree().process_frame

func _result() -> Dictionary:
	return {"passed":_failures.is_empty(),"checks":_checks,"failures":_failures.duplicate(),"scope":"Processed pure copied-record UI at960/1920/2560, captured engine/held-mixture/unavailable/imported facts, selection/copy/rejection, actual container/focus/scroll bounds. No OS keyboard/mouse delivery, original-pixel acceptance, native observation/IO/package/aircraft/pilot/phase claim."}

func _visible_inside(control: Control, viewport: Rect2) -> bool:
	return control.is_visible_in_tree() and viewport.encloses(control.get_global_rect())

func _snapshot(panel: Control) -> Dictionary:
	return {"record":panel._record.duplicate(true),"selection":panel.selection(),"index":panel._index,"engine":panel._engine.text,"instant":panel._instant.text,"controls":panel._controls.text}

func _unavailable(record: Dictionary, id: String, reason: String) -> Dictionary:
	var value: Dictionary=record.duplicate(true)
	value.samples[0].engine_status.readings[id]={"value":null,"unit":record.samples[0].engine_status.readings[id].unit,"valid":false,"error":reason}
	if id=="fuel.total":
		value.samples[0].readings.readings.fuel_total={"value":null,"unit":"kg","valid":false,"error":reason}
	return value

func run(host: Node, piston_record: Dictionary, legacy_record: Dictionary) -> Dictionary:
	_host=host;_checks=0;_failures.clear()
	if not _check(host!=null and host.is_inside_tree(),"processed_host_required"): return _result()
	if not _check(Values.valid_recording(piston_record) and piston_record.get("contract_version")==2 and piston_record.get("samples",[]).size()>=3,"required_admitted_nonempty_three_sample_v2_fixture"): return _result()
	if not _check(Values.valid_recording(legacy_record) and legacy_record.get("contract_version")==1 and not legacy_record.get("samples",[]).is_empty(),"required_admitted_nonempty_v1_fixture"): return _result()
	var piston_before: PackedByteArray=var_to_bytes(piston_record)
	var legacy_before: PackedByteArray=var_to_bytes(legacy_record)
	var viewport:=SubViewport.new()
	viewport.size=Vector2i(960,540)
	host.add_child(viewport)
	var panel: Control=ObservedPanel.new()
	viewport.add_child(panel)
	panel.set_open(true)
	await _settle()
	_check(viewport.gui_get_focus_owner()==panel._back,"new_review_focus_is_persistent_Back")
	_check(ObservedPanel.CHANNELS==["tas","ground_speed","ellipsoid_height","vertical_speed","fuel_total"] and panel._graph_choice.item_count==5,"existing_five_flight_graphs_unchanged")
	_check(panel.set_recording(piston_record),"small_v2_record_admitted")
	_check(panel.select_sample(0),"first_sample_selected")
	_check(panel._engine.visible and panel._engine.text.contains("RECORDED ENGINE FACTS / ORIGINAL PISTON PROTOTYPE") and panel._engine.text.contains("tick "+piston_record.samples[0].tick),"stored_piston_tick_profile_qualified")
	for id in CHANNEL_LABELS:
		_check(panel._engine.text.contains(CHANNEL_LABELS[id]),"captured_channel_label_"+id)
	_check(panel._engine.text.contains("Shaft (RPM) 0.00") and panel._engine.text.contains("Engine running OFF") and panel._engine.text.contains("Starter OFF"),"small_reference_stopped_facts_no_false_unavailable")
	_check(panel.select_sample(1),"middle_sample_selected")
	_check(panel._engine.text.contains("Starter ON") and panel._engine.text.contains("Engine running OFF") and panel._engine.text.contains("Actual mixture (fraction) 0.70") and panel._controls.text.contains("Mixture 70.00%"),"small_reference_held_and_engine_mixture_starter_facts")
	_check(not panel._controls.tooltip_text.contains("fixed at 1") and panel._controls.tooltip_text.contains("not the complete pilot command history"),"piston_held_axes_not_queued_or_fixed_legacy_mixture")
	var tools: Node=panel._cursor.get_parent()
	tools.get_child(0).pressed.emit()
	_check(panel.selection().sample.tick==piston_record.samples[0].tick,"actual_First_button_selects_recorded_sample")
	tools.get_child(3).pressed.emit()
	_check(panel.selection().sample.tick==piston_record.samples[1].tick,"actual_Next_button_selects_recorded_sample")
	tools.get_child(1).pressed.emit()
	_check(panel.selection().sample.tick==piston_record.samples[0].tick,"actual_Previous_button_selects_recorded_sample")
	panel._cursor.value=1
	_check(panel.selection().sample.tick==piston_record.samples[1].tick,"actual_slider_selects_middle_sample")
	tools.get_child(4).pressed.emit()
	_check(panel.selection().sample.tick==piston_record.samples[-1].tick and panel._engine.text.contains("Engine running ON") and panel._engine.text.contains("Starter OFF"),"actual_Latest_button_selects_running_reference_fact")
	_check(not panel._engine.text.contains("CRANKING") and not panel._engine.text.contains("COASTING"),"no_inferred_phase_or_exact_transition_label")
	var owned: Dictionary=panel.selection()
	owned.sample.engine_status.readings["engine.mixture"].value=0.123
	_check(panel.selection().sample==piston_record.samples[-1],"engine_selection_owned_deep_copy")
	var supplied: Dictionary=piston_record.duplicate(true)
	_check(panel.set_recording(supplied),"copied_supplied_record_admitted")
	supplied.samples[0].engine_status.readings["engine.mixture"].value=0.456
	_check(panel._record==piston_record,"caller_mutation_does_not_change_owned_record")
	var held: Dictionary=_snapshot(panel)
	var invalid: Dictionary=piston_record.duplicate(true)
	invalid.samples[0].engine_status.readings["unexpected"]={}
	_check(not panel.set_recording(invalid) and _snapshot(panel)==held,"invalid_replacement_preserves_history_cursor_and_facts")
	_check(not panel.select_sample(-1) and _snapshot(panel)==held,"invalid_cursor_preserves_selection_and_facts")
	for id in CHANNEL_LABELS:
		var reason: String="Captured source unavailable for "+id
		var missing: Dictionary=_unavailable(piston_record,id,reason)
		_check(panel.set_recording(missing) and panel.select_sample(0),"valid_per_channel_unavailable_admitted_"+id)
		_check(panel._engine.text.contains("unavailable: "+reason) and panel._details_text.text.contains(reason),"full_unavailable_reason_visible_and_copyable_"+id)
	var huge: Dictionary=piston_record.duplicate(true)
	huge.samples[0].engine_status.readings["propeller.angular_speed"].value=1.7976931348623157e308
	_check(panel.set_recording(huge) and panel.select_sample(0),"finite_extreme_shaft_fixture_admitted")
	_check(panel._engine.text.contains("display conversion overflow") and panel._engine.text.contains("rad/s") and panel.selection().sample.engine_status.readings["propeller.angular_speed"].value==1.7976931348623157e308,"RPM_display_overflow_does_not_zero_or_invalidate_recorded_radps")
	var shaft_fact: String=panel._engine_fact(panel.selection().sample,"propeller.angular_speed")
	var captured_parts: PackedStringArray=shaft_fact.split("captured ")
	var captured_value: String=captured_parts[1].trim_suffix(" rad/s") if captured_parts.size()==2 else ""
	_check(not captured_value.is_empty() and captured_value.is_valid_float() and is_finite(float(captured_value)) and float(captured_value)>1e308,"RPM_overflow_displays_nonempty_finite_captured_shaft_value")
	var long_reason: String="Captured missing shaft: "+"diagnostic ".repeat(85)
	var long_missing: Dictionary=_unavailable(piston_record,"propeller.angular_speed",long_reason)
	_check(panel.set_recording(long_missing) and panel.select_sample(0),"bounded_long_source_reason_admitted")
	var context: String="Synthetic recovery path C:/review-ui-fixture/"+"long-folder/".repeat(30)+"record.fsreview.json"
	panel.set_file_context(true,context,true)
	_check(panel._summary.text.begins_with("OPENED FILE / HISTORICAL") and panel._engine.text.begins_with("OPENED FILE / HISTORICAL") and panel._summary.tooltip_text.contains("authorship is unverified"),"imported_flight_and_engine_are_historical_not_authenticated")
	_check(panel._details_text.text.contains(context) and panel._details_text.text.contains(long_reason) and panel._details_text.text.contains(piston_record.metadata.native_source_fingerprint),"full_recovery_reason_and_recorded_source_copyable")
	for button in [panel._save_file,panel._open_file,panel._current_file,panel._details_button,panel._back]:
		_check(button.disabled,"existing_busy_disable_"+button.text)
	panel.set_file_context(true,context,false)
	for dimensions in [Vector2i(960,540),Vector2i(1920,1080),Vector2i(2560,1440)]:
		viewport.size=dimensions
		await _settle()
		var bounds:=Rect2(Vector2.ZERO,Vector2(dimensions))
		for control in [panel._title,panel._back,panel._save_file,panel._open_file,panel._current_file,panel._details_button,panel._scroll]:
			_check(_visible_inside(control,bounds),"persistent_header_and_scroll_inside_"+str(dimensions)+"_"+control.name)
		_check(panel._body.size.y>=130 and panel._scroll.size.y>130 and panel._scroll.horizontal_scroll_mode==ScrollContainer.SCROLL_MODE_DISABLED,"graph_minimum_and_vertical_only_scroll_"+str(dimensions))
		_check(panel._engine.get_line_count()*panel._engine.get_line_height()<=panel._engine.size.y and panel._engine.get_combined_minimum_size().y<=panel._engine.size.y,"complete_wrapped_engine_line_height_"+str(dimensions))
		var scrollbar: VScrollBar=panel._scroll.get_v_scroll_bar()
		if scrollbar.is_visible_in_tree():
			scrollbar.grab_focus()
			_check(viewport.gui_get_focus_owner()==scrollbar,"builtin_scrollbar_keyboard_focus_"+str(dimensions))
		else:
			_check(panel._scroll.get_child(0).get_combined_minimum_size().y<=panel._scroll.size.y,"all_content_fits_when_no_scrollbar_"+str(dimensions))
			panel._cursor.grab_focus()
			_check(viewport.gui_get_focus_owner()==panel._cursor,"ordinary_cursor_keyboard_focus_without_scrolling_"+str(dimensions))
		panel._scroll.scroll_vertical=int(panel._scroll.get_v_scroll_bar().max_value)
		await _settle()
		_check(panel._scroll.get_global_rect().encloses(panel._controls.get_global_rect()),"held_controls_reachable_at_bottom_"+str(dimensions))
		_check(_visible_inside(panel._back,bounds),"Back_remains_visible_after_scroll_"+str(dimensions))
		_check(panel.set_recording(legacy_record),"legacy_admitted_"+str(dimensions))
		panel.set_file_context(false)
		panel._scroll.scroll_vertical=0
		await _settle()
		_check(not panel._engine.visible and panel._engine.text.is_empty() and panel._controls.tooltip_text.contains("Mixture is fixed at 1"),"legacy_no_invented_engine_view_"+str(dimensions))
		for control in [panel._summary,panel._instant,panel._controls,panel._graph_choice,panel._cursor]:
			_check(_visible_inside(control,bounds),"legacy_existing_visible_control_"+str(dimensions)+"_"+control.name)
		var legacy_owned: PackedByteArray=var_to_bytes(panel._record)
		panel._graph_choice.item_selected.emit(3)
		_check(panel._channel=="vertical_speed" and var_to_bytes(panel._record)==legacy_owned,"existing_graph_selection_pure_"+str(dimensions))
		_check(panel.set_recording(long_missing) and panel.select_sample(0),"restore_piston_for_next_layout_"+str(dimensions))
		panel.set_file_context(true,context,false)
	var signal_counts: Dictionary={"dismissed":0,"save":0,"open":0,"current":0}
	panel.dismissed.connect(func():signal_counts.dismissed+=1)
	panel.save_requested.connect(func():signal_counts.save+=1)
	panel.open_requested.connect(func():signal_counts.open+=1)
	panel.current_requested.connect(func():signal_counts.current+=1)
	var before_signals: PackedByteArray=var_to_bytes(panel._record)
	for button in [panel._back,panel._save_file,panel._open_file,panel._current_file]: button.pressed.emit()
	_check(signal_counts=={"dismissed":1,"save":1,"open":1,"current":1} and var_to_bytes(panel._record)==before_signals,"existing_buttons_emit_only_expected_requests_preserving_record")
	var empty: Dictionary=piston_record.duplicate(true)
	empty.metadata=null;empty.samples=[];empty.last_observed_tick=null
	empty.skipped_target_count=0;empty.late_sample_count=0;empty.uncaptured_tail_targets=0
	empty.state="empty";empty.seal_reason=null;empty.error=""
	_check(panel.set_recording(empty) and panel._engine.text.is_empty() and not panel._engine.visible and panel._controls.text.is_empty(),"canonical_empty_clears_stale_engine_controls")
	_check(var_to_bytes(piston_record)==piston_before and var_to_bytes(legacy_record)==legacy_before,"all_supplied_fixture_bytes_unchanged")
	panel.set_open(false)
	_check(not panel.visible and panel.mouse_filter==Control.MOUSE_FILTER_IGNORE,"existing_dismissed_panel_routing")
	viewport.free()
	return _result()
