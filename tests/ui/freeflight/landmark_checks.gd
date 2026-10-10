extends RefCounted
# Original MIT. Active copied-state/geometry/UI tests, not native flight proof.
const Board = preload("res://ui/freeflight/landmark_board.gd")
const Frames = preload("res://simulation/canonical_frames.gd")
const Readings = preload("res://cockpit/instruments/native_readings.gd")
var _checks := 0
var _failures: Array[String] = []
var _host: Node
var _seed: Dictionary

func _check(value: bool, label: String) -> void:
	_checks+=1
	if not value:
		_failures.append(label)
	if _host.has_method("check"):
		_host.call("check",value,"landmark_"+label)

func _source(x: float=0.0, z: float=0.0) -> Dictionary:
	var value: Dictionary=_seed.duplicate(true)
	value.debt_quanta=0
	value.host_mode="paused"
	value.paused=true
	value.native_outcome="paused"
	var prepared: Dictionary=Frames.anchor(0.8,-2.0,0.0)
	var r: Array=prepared.rotation
	var ecef: Array=[prepared.ecef[0]+r[0]*x+r[6]*z,prepared.ecef[1]+r[1]*x+r[7]*z,prepared.ecef[2]+r[2]*x+r[8]*z]
	# Independent WGS84 inverse for physically consistent synthetic source.
	var e2: float=(1.0/298.257223563)*(2.0-1.0/298.257223563)
	var horizontal: float=sqrt(ecef[0]*ecef[0]+ecef[1]*ecef[1])
	var latitude: float=atan2(ecef[2],horizontal*(1.0-e2))
	var height: float=0.0
	for iteration in 12:
		var radius: float=6378137.0/sqrt(1.0-e2*sin(latitude)*sin(latitude))
		height=horizontal/cos(latitude)-radius
		latitude=atan2(ecef[2],horizontal*(1.0-e2*radius/(radius+height)))
	var p: Dictionary={"latitude_rad":latitude,"longitude_rad":atan2(ecef[1],ecef[0]),"ellipsoid_height_m":height}
	value.aircraft.position=p.duplicate(true)
	value.atmosphere.position=p.duplicate(true)
	value.aircraft.ecef_position_m={"x":ecef[0],"y":ecef[1],"z":ecef[2]}
	value.canonical=Frames.derive(value.aircraft,prepared)
	return value

func _live(value: Dictionary) -> Dictionary:
	var result: Dictionary=value.duplicate(true)
	result.host_mode="live"
	result.paused=false
	result.native_outcome="completed"
	return result

func run(host: Node) -> Dictionary:
	_host=host
	var reference: Variant=JSON.parse_string(FileAccess.get_file_as_string("res://instrument_tests/reference.json"))
	if not reference is Dictionary:
		_check(false,"existing_full_readback_fixture_available")
		return _receipt()
	_seed=reference.cases[0].input.duplicate(true)
	var source: Dictionary=_source()
	_check(Readings.from_readback(source).state=="paused","synthetic_source_full_contract_valid")
	var landmarks: Array=[{"label":"East Farm","position_eus_m":Vector3(850,0,-650)},{"label":"North Water Tank","position_eus_m":Vector3(600,0,-2500)},{"label":"West Pond","position_eus_m":Vector3(-1050,0,-900)},{"label":"River Bridge","position_eus_m":Vector3(-2350,0,-2600)},{"label":"South Village","position_eus_m":Vector3(950,0,1250)},{"label":"North Orchard","position_eus_m":Vector3(-650,0,-2800)}]
	var board:=Board.new()
	host.add_child(board)
	board.size=Vector2(960,540)
	_check(board.configure(landmarks).ok,"configure_bounded_original_metadata")
	var input_before: Dictionary=source.duplicate(true)
	_check(board.choose([0,1,5],source).ok,"paused_choose_itinerary")
	_check(source==input_before,"choose_preserves_all_source_records")
	var v: Dictionary=board.observe(source)
	_check(v.size()==16 and v.active and v.route_labels==["East Farm","North Water Tank","North Orchard"] and v.target_label=="East Farm","exact_owned_view_keys_and_order")
	_check(v.keys().all(func(key: Variant): return key is String),"view_actual_string_keys")
	landmarks[0].label="Caller mutation"
	v.route_labels[0]="Caller mutation"
	v.target_anchor_eus_m[0]=999
	v=board.observe(source)
	_check(v.target_label=="East Farm" and v.target_anchor_eus_m[0]==850,"metadata_and_view_copies")
	var at_target: Dictionary=_source(850.0,-650.0)
	var at_view: Dictionary=board.observe(at_target)
	_check(at_view.active and not at_view.complete and at_view.leg_index==0 and at_view.bearing_deg==null and at_view.planar_range_m<=1e-7,"co_location_does_not_auto_arrive_or_advance")
	board.observe(source)
	var selected: Array=[0,1,5]
	board.choose(selected,source)
	selected[0]=2
	_check(board.observe(source).target_label=="East Farm","indices_owned_copy")
	for bad in [[],[0,0],[99],[0.0],[0,1,2,3,4]]:
		_check(not board.choose(bad,source).ok and board.observe(source).route_labels==["East Farm","North Water Tank","North Orchard"],"invalid_selection_"+str(bad))
	_check(not board.choose_return(17,source).ok,"invalid_runway_rejected")
	var live: Dictionary=_live(source)
	for operation in [board.choose([2],live),board.next(live),board.stop(live),board.choose_return(36,live)]:
		_check(not operation.ok,"live_edit_rejected")
	_check(board.observe(live).active and board.observe(live).target_label=="East Farm","selected_route_live_persists")
	_check(board.next(source).ok and board.observe(source).target_label=="North Water Tank","manual_next_first")
	_check(board.next(source).ok and board.observe(source).target_label=="North Orchard","manual_next_second")
	_check(board.next(source).ok and board.observe(source).complete and not board.observe(source).active and board.observe(source).planar_range_m==null,"manual_end_not_arrival_or_score")
	for runway in [36,18]:
		_check(board.choose_return(runway,source).ok,"choose_return_"+str(runway))
		var ret: Dictionary=board.observe(source)
		_check(ret.target_anchor_eus_m==[0.0,0.0,100.0 if runway==36 else -1700.0] and ret.target_label.contains("pavement end"),"exact_return_geometry_"+str(runway))
		_check(absf(ret.bearing_deg-(180.0 if runway==36 else 0.0))<1e-7,"return_anchor_bearing_"+str(runway))
	_check(board.stop(source).ok and not board.observe(source).active,"manual_stop")
	board.choose([0],source)
	var retained: Dictionary=source.duplicate(true)
	retained.host_mode="coverage_blocked"
	retained.historical=true
	retained.native_outcome="coverage_blocked"
	retained.paused=true
	var old: Dictionary=board.observe(retained)
	_check(old.historical and not old.available and old.planar_range_m==null and old.bearing_deg==null and old.target_label==null,"retained_clears_current_guidance")
	_check(not board.next(retained).ok,"retained_edit_rejected")
	var malformed: Dictionary=source.duplicate(true)
	malformed.canonical.anchor_eus_position_m[0]=10.0
	_check(not board.observe(malformed).available and board.observe(malformed).error.contains("differs"),"contradictory_canonical_rejected")
	malformed=source.duplicate(true)
	malformed.aircraft.velocity_body_mps.x=1e308
	_check(not board.observe(malformed).available and board.observe(malformed).planar_range_m==null,"source_arithmetic_overflow_unavailable")
	malformed=source.duplicate(true)
	malformed.debt_quanta=0.0
	_check(not board.observe(malformed).available,"float_debt_full_readback_rejected")
	var fresh: Dictionary=source.duplicate(true)
	fresh.session_id="synthetic-next-session"
	fresh.aircraft.session_id=fresh.session_id
	fresh.atmosphere.session_id=fresh.session_id
	_check(board.observe(fresh).route_labels.is_empty() and not board.observe(fresh).active,"fresh_verified_session_clears_route")
	board.choose([0,1],fresh)
	var baseline: Dictionary=board.observe(fresh)
	for iteration in 20:
		_check(board.observe(fresh)==baseline,"repeated_publication_does_not_advance_leg_"+str(iteration))
	_check(fresh.session_id=="synthetic-next-session" and source==input_before,"view_only_source_invariance")
	board.set_open(true)
	await host.get_tree().process_frame
	await host.get_tree().process_frame
	var choices: Array=board._choices.get_children()
	choices[0].grab_focus()
	for iteration in 5:
		board.observe(fresh)
	_check(board._choices.get_children()==choices and choices[0].has_focus(),"stable_buttons_keyboard_focus_across_publications")
	_check(choices.all(func(child: Node): return child.focus_mode==Control.FOCUS_ALL),"paused_choices_keyboard_accessible")
	var before_draft: Array=board._draft.duplicate()
	choices[2].pressed.emit()
	_check(board._draft.has(2) and board._draft!=before_draft and board._choices.get_children()==choices,"actual_button_correct_index_stable_nodes")
	for viewport_size in [Vector2(960,540),Vector2(1280,720)]:
		board.size=viewport_size
		board._layout()
		await host.get_tree().process_frame
		await host.get_tree().process_frame
		var bounds:=Rect2(Vector2.ZERO,viewport_size)
		_check(bounds.encloses(board._chooser.get_rect()),"chooser_bounds_"+str(viewport_size))
		for child in board._choices.get_children():
			_check(bounds.encloses(child.get_global_rect()),"choice_bounds_"+str(viewport_size)+child.text)
		_check(bounds.encloses(board._begin.get_global_rect()) and bounds.encloses(board._next.get_global_rect()) and bounds.encloses(board._stop.get_global_rect()),"actions_bounds_"+str(viewport_size))
		board.set_open(false)
		await host.get_tree().process_frame
		_check(bounds.encloses(board._card.get_rect()) and board._card.get_child(0).get_child(0).text.contains("SYNTHETIC"),"target_card_bounds_and_scope_"+str(viewport_size))
		board.set_open(true)
	var pre_toggle: Dictionary=board.observe(fresh)
	board.set_aids_visible(false)
	_check(not board._card.visible and not board.observe(fresh).aid_visible and board.observe(fresh).route_labels==pre_toggle.route_labels,"hide_aids_preserves_itinerary")
	board.set_open(true)
	_check(board._chooser.visible,"hidden_aids_paused_chooser_still_available")
	board.set_aids_visible(true)
	_check(board.observe(fresh).aid_visible,"show_aids_restored_without_route_change")
	var invalid: Dictionary=board.configure([{"label":"bad","position_eus_m":Vector3(INF,0,0)}])
	_check(not invalid.ok and board.observe(fresh).route_labels==["East Farm","North Water Tank"],"invalid_configure_atomic_preservation")
	await _compact_card(host,source)
	await _hidden_card_settlement(host,source)
	board.queue_free()
	await host.get_tree().process_frame
	await _geometry(host)
	return _receipt()

func _geometry(host: Node) -> void:
	var packet: Variant=JSON.parse_string(FileAccess.get_file_as_string("res://freeflight_tests/reference.json"))
	if not packet is Dictionary:
		_check(false,"independent_geometry_packet_available")
		return
	for c in packet.cases:
		var board:=Board.new()
		host.add_child(board)
		var metadata: Array=[{"label":"Reference target","position_eus_m":Vector3(c.target.x,0,c.target.z)}]
		_check(board.configure(metadata).ok,"reference_configure_"+c.id)
		var source: Dictionary=_source(c.own.x,c.own.z)
		_check(board.choose([0],source).ok,"reference_source_choose_"+c.id)
		var actual: Dictionary=board.observe(source)
		_check(actual.planar_range_m!=null and absf(actual.planar_range_m-c.range_m)<=packet.tolerances_before_observation.range_abs_m,"independent_range_"+c.id)
		var angle_ok: bool=actual.bearing_deg==null if c.bearing_deg==null else actual.bearing_deg!=null and absf(wrapf(actual.bearing_deg-c.bearing_deg,-180.0,180.0))<=packet.tolerances_before_observation.bearing_abs_deg
		_check(angle_ok,"independent_anchor_bearing_"+c.id)
		board.queue_free()
	await host.get_tree().process_frame

func _receipt() -> Dictionary:
	return {"passed":_failures.is_empty(),"checks":_checks,"failures":_failures.duplicate(),"scope":"Synthetic copied Readback / independent anchor geometry / actual paused UI; no native solver, pilot or operational navigation acceptance"}

func _compact_card(host:Node,source:Dictionary)->void:
	var viewport:=SubViewport.new()
	viewport.size=Vector2i(960,540)
	host.add_child(viewport)
	var board:=Board.new()
	viewport.add_child(board)
	board.size=Vector2(960,540)
	var names:Array=[]
	for i in 4: names.append({"label":"W".repeat(31)+str(i),"position_eus_m":Vector3(100+i,0,-100)})
	_check(board.configure(names).ok and board.choose([0,1,2,3],source).ok,"compact_long_route_admitted")
	var before:Dictionary=board._view.duplicate(true)
	for width in [250.0,320.0,360.0]:
		board.set_card_dock(Rect2(14,124,width,188))
		await host.get_tree().process_frame
		await host.get_tree().process_frame
		_check(board._view.duplicate(true)==before and source==_source(),"compact_dock_no_route_or_source_change_"+str(width))
		_check(board._title.text==names[0].label and board._title.text_overrun_behavior==TextServer.OVERRUN_NO_TRIMMING,"compact_complete_target_"+str(width))
		_check(board._leg_text.tooltip_text.contains(names[3].label) and board._state.text.contains("Itinerary shortened; full list in tooltip"),"compact_secondary_full_tooltip_and_explanation_"+str(width))
		_check(board._state.text.begins_with("PAUSED / select Next from the route board") and board._state.text_overrun_behavior==TextServer.OVERRUN_NO_TRIMMING,"compact_complete_paused_footer_"+str(width))
		var bounds:Rect2=board._card.get_rect()
		_check(bounds.size.y<=188.0 and bounds.size.x==width,"compact_card188_bounds_"+str(width)+" actual="+str(bounds))
		for label in [board._card_header,board._title,board._metrics,board._leg_text,board._state]:
			_check(bounds.encloses(Rect2(label.global_position-board.global_position,label.size)),"compact_child_in_bounds_"+str(width)+label.text.left(12))
		_check(board._title.get_line_count()<=2 and board._state.get_line_count()<=3,"compact_full_text_rows_"+str(width))
	var press:=InputEventMouseButton.new()
	press.button_index=MOUSE_BUTTON_LEFT;press.pressed=true;press.position=board._leg_text.get_global_rect().get_center()
	viewport.push_input(press,true)
	_check(not viewport.is_input_handled() and board._view.duplicate(true)==before and board._leg_text.get_signal_connection_list("gui_input").is_empty(),"compact_local_viewport_press_flag_route_and_no_handler_only")
	_check(board._leg_text.mouse_filter==Control.MOUSE_FILTER_PASS and board._card.mouse_filter==Control.MOUSE_FILTER_IGNORE and board._leg_text.get_tooltip(Vector2.ZERO)==board._leg_text.text,"compact_hover_capable_complete_standard_tooltip")
	board.set_summary_in_map(true)
	_check(not board._card.visible and board._view.duplicate(true)==before,"compact_summary_suppression_only")
	board.set_summary_in_map(false)
	_check(board._card.visible and board._view.duplicate(true)==before,"compact_summary_restore_only")
	var retained:Dictionary=source.duplicate(true)
	retained.host_mode="coverage_blocked";retained.historical=true;retained.native_outcome="coverage_blocked";retained.paused=true
	board.observe(retained)
	_check(board._title.text=="Current guidance unavailable" and board._metrics.text=="Range / bearing unavailable" and board._state.text.begins_with("RETAINED / NO CURRENT GUIDANCE"),"compact_honest_noncurrent_summary")
	board.observe(source)
	for i in 4: board.next(source)
	_check(board._title.text=="Manual itinerary ended" and not board._view.duplicate(true).active and board._view.duplicate(true).complete and board._metrics.text=="Range / bearing unavailable","compact_honest_completed_summary")
	var tall_name:String=("W\n").repeat(15)+"W"
	_check(board.configure([{"label":tall_name,"position_eus_m":Vector3(100,0,-100)}]).ok and board.choose([0],source).ok,"compact_valid_multiline_name_negative_admitted")
	board.set_card_dock(Rect2(14,124,250,188))
	await host.get_tree().process_frame
	await host.get_tree().process_frame
	_check(board._card.size.y>188 and board._title.text==tall_name and board._title.text_overrun_behavior==TextServer.OVERRUN_NO_TRIMMING,"compact_unfit_title_remains_visible_failure_not_truncated")
	board.configure(names);board.choose([0,1,2,3],source)
	board.set_card_dock(Rect2())
	_check(board._title.get_theme_font_size("font_size")==20 and board._state.text=="PAUSED / select Next from the route board","compact_reset_default_no_explanation_leak")
	viewport.queue_free()
	await host.get_tree().process_frame

func _card_allocation(board: Control) -> Dictionary:
	var labels: Array=[]
	for label in [board._card_header,board._title,board._metrics,board._leg_text,board._state]:
		labels.append({"rect":label.get_rect(),"minimum":label.get_combined_minimum_size(),"text":label.text,"lines":label.get_line_count()})
	return {"card":board._card.get_rect(),"box":board._card_box.get_rect(),"labels":labels}

func _hidden_card_settlement(host: Node,source: Dictionary) -> void:
	# A fresh hidden card must shape at its actual dock width even before the
	# Container ever receives a visible sort. Keep every hidden row in evidence.
	var board:=Board.new()
	host.add_child(board)
	board.size=Vector2(960,540)
	var landmarks: Array=[{"label":"East Farm","position_eus_m":Vector3(850,0,-650)},{"label":"North Water Tank","position_eus_m":Vector3(600,0,-2500)},{"label":"North Orchard","position_eus_m":Vector3(-650,0,-2800)},{"label":"West Pond","position_eus_m":Vector3(-1050,0,-900)}]
	var source_before: PackedByteArray=var_to_bytes(source)
	_check(board.configure(landmarks).ok and board.choose([0,1,2,3],source).ok,"hidden_settlement_actual_route_seed")
	board.set_summary_in_map(true)
	for width in [250.0,320.0,360.0]:
		board.set_card_dock(Rect2(14,124,width,188))
		for kind in ["empty","retained"]:
			var supplied: Dictionary={} if kind=="empty" else source.duplicate(true)
			if kind=="retained":
				supplied.host_mode="coverage_blocked";supplied.historical=true;supplied.native_outcome="coverage_blocked";supplied.paused=true
			board.observe(supplied)
			board.set_summary_in_map(true)
			var view_before: PackedByteArray=var_to_bytes(board._view)
			var supplied_before: PackedByteArray=var_to_bytes(supplied)
			var allocation: PackedByteArray=var_to_bytes(_card_allocation(board))
			for iteration in 4:
				board.observe(supplied)
				board.set_summary_in_map(false)
				board.set_card_dock(Rect2(14,124,width,188))
				board.set_summary_in_map(true)
				await host.get_tree().process_frame
				await host.get_tree().process_frame
				_check(var_to_bytes(_card_allocation(board))==allocation,"hidden_all_rows_exact_across_publication_and_draw_"+kind+str(width)+"_"+str(iteration))
			_check(not board._card.visible and board._card.size==Vector2(width,188),"hidden_card188_not_minimum_overflow_"+kind+str(width))
			_check(board._card_box.size.x==width-24 and board._state.size.x==width-24 and board._state.size.y<=42 and board._state.get_line_count()<=3,"hidden_footer_actual_width_and_full_rows_"+kind+str(width))
			_check(var_to_bytes(board._view)==view_before and var_to_bytes(supplied)==supplied_before and var_to_bytes(source)==source_before,"hidden_settlement_all_source_and_route_copies_"+kind+str(width))
		board.set_summary_in_map(false)
		await host.get_tree().process_frame
		await host.get_tree().process_frame
		_check(board._card.visible and board._card.size==Vector2(width,188),"hidden_restore_visible_same188_"+str(width))
		var bounds: Rect2=Rect2(Vector2.ZERO,board._card.size)
		for label in [board._card_header,board._title,board._metrics,board._leg_text,board._state]:
			_check(bounds.encloses(Rect2(label.global_position-board._card.global_position,label.size)),"hidden_restore_actual_row_bounds_"+str(width)+label.text.left(12))
		board.set_summary_in_map(true)
	board.queue_free()
	await host.get_tree().process_frame
