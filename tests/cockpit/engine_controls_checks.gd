extends RefCounted
## Original MIT. Synthetic copy-only GUI fixture; no native, facade or hardware claim.
const EnginePanel=preload("res://cockpit/engine_controls.gd")
var _events: Array[Dictionary]=[]
var _invalidations: Array[String]=[]
var _denied: Array[Dictionary]=[]
var _host: Node
var _checks: int=0
var _failures: Array[String]=[]
func _check(ok: bool,label: String) -> void:
	_checks+=1
	if not ok: _failures.append(label)
	if _host.has_method("check"): _host.call("check",ok,"engine_panel_"+label)
func _event(value: Dictionary) -> void: _events.append(value.duplicate(true))
func _invalidated(reason: String) -> void: _invalidations.append(reason)
func _deny(control: String,reason: String) -> void: _denied.append({"control":control,"reason":reason})
func _view() -> Dictionary:
	return {"session_id":"fixture-panel-session","generation":4,"last_token":0,"capture":null,"requested_axes":{"throttle":0.4,"mixture":0.6},"requested_systems":{"engine.ignition_left":false,"engine.ignition_right":false,"fuel.feed":true,"engine.starter":false},"rearm_buttons":[],"error":""}
func _engine() -> Dictionary:
	var readings: Dictionary={}
	for entry in [["engine.throttle",0.1],["engine.mixture",0.2],["engine.ignition_left",false],["engine.ignition_right",false],["fuel.feed",true],["engine.starter",false]]:
		readings[entry[0]]={"valid":true,"value":entry[1],"unit":"bool" if entry[1] is bool else "fraction","error":""}
	return {"session_id":"fixture-panel-session","tick":"7","state":"live","native_truth":true,"readings":readings,"error":""}
func _preset() -> Dictionary:
	return {"axes":[{"target":"throttle","kind":"key_pair","negative":[KEY_S],"positive":[KEY_W]},{"target":"mixture","kind":"joy_axis","slot":"synthetic-fixture","index":2}],"actions":[{"id":"look_hold","sources":[{"kind":"mouse_button","button":2}]}],"systems":[{"id":"engine.starter","sources":[{"kind":"physical_keys","keys":[KEY_U]}]}]}
func _button(panel: Control,position_value: Vector2,pressed: bool,button: int=MOUSE_BUTTON_LEFT) -> void:
	var event: InputEventMouseButton=InputEventMouseButton.new()
	event.position=panel.position+position_value;event.global_position=event.position
	event.button_index=button;event.pressed=pressed;event.button_mask=MOUSE_BUTTON_MASK_LEFT if pressed and button==MOUSE_BUTTON_LEFT else 0
	panel.get_viewport().push_input(event,true)
func _motion(panel: Control,position_value: Vector2) -> void:
	var event: InputEventMouseMotion=InputEventMouseMotion.new()
	event.position=panel.position+position_value;event.global_position=event.position;event.button_mask=MOUSE_BUTTON_MASK_LEFT
	panel.get_viewport().push_input(event,true)
func _consumed(panel: Control,view: Dictionary,engine: Dictionary,preset: Dictionary) -> void:
	view.last_token+=1;view.capture=null
	panel.set_state(view,engine,preset,true,"","Release right mouse look to expose pointer")

func run(host: Node) -> Dictionary:
	_host=host
	var panel: Control=EnginePanel.new()
	panel.position=Vector2(10,180);panel.size=Vector2(940,140)
	host.add_child(panel)
	panel.gesture_requested.connect(_event);panel.capture_invalidated.connect(_invalidated);panel.denied_press.connect(_deny)
	await host.get_tree().process_frame
	var view: Dictionary=_view();var engine: Dictionary=_engine();var preset: Dictionary=_preset()
	panel.set_state(view,engine,preset,true,"","Release right mouse look")
	var source_bytes: PackedByteArray=var_to_bytes([view,engine,preset])
	view.requested_axes.throttle=0.9;engine.readings["engine.throttle"].value=0.8;preset.axes[0].negative=[KEY_Z]
	_check(panel._requested("throttle")==0.4 and panel._actual("throttle")==0.1 and "S" in panel._binding_hint("throttle"),"deep_owned_copies")
	view=_view();engine=_engine();preset=_preset();panel.set_state(view,engine,preset,true)
	var rects: Dictionary=panel._rects()
	for control in rects:
		var rect: Rect2=rects[control]
		_check(rect.position.x>=0 and rect.end.x<=940 and rect.end.y<=140 and rect.size.x>=100,"940_bounds_"+control)
		_check(panel.hit_control(rect.get_center())==control,"six_actual_hit_regions_"+control)
	_check(panel.expanded_height()==140 and panel.is_expanded(),"expanded_height")
	# A real viewport-routed thumb press starts from sampled mapper request, not actual.
	var track: Rect2=panel._track("throttle")
	var thumb: Vector2=Vector2(track.position.x+0.4*track.size.x,track.get_center().y)
	_button(panel,thumb,true)
	_check(_events.size()==1 and _events[0].phase=="begin" and _events[0].value==0.4 and _events[0].token==1,"real_gui_thumb_seeds_request")
	_check(_events[0].keys().size()==7 and _events[0].session_id==view.session_id and _events[0].generation==4 and _events[0].button==1,"exact_gesture_metadata")
	_check(panel._actual("throttle")==0.1 and panel._requested("throttle")==0.4,"unsampled_no_feedback_mutation")
	_motion(panel,Vector2(1100,80))
	_check(_events.size()==2 and _events[-1].phase=="move" and _events[-1].value==1.0,"lever_continues_outside_clamped")
	_button(panel,Vector2(1100,80),false)
	_check(_events.size()==3 and _events[-1].phase=="end" and _events[-1].value==1.0,"outside_up_final_axis")
	_button(panel,thumb,false)
	_check(_events.size()==3,"duplicate_gui_up_inert")
	view.last_token=1;view.requested_axes.throttle=1.0;panel.set_state(view,engine,preset,true)
	_check(panel._capture.is_empty() and panel._preview==null,"terminal_consumption_clears_preview")
	_events.clear()
	var mixture: Rect2=panel._track("mixture")
	_button(panel,Vector2(mixture.position.x+mixture.size.x*0.8,mixture.get_center().y),true)
	_check(_events.size()==1 and absf(float(_events[0].value)-0.8)<0.000001,"track_jump_explicit")
	_button(panel,mixture.get_center(),false);view.last_token=2;panel.set_state(view,engine,preset,true)
	_events.clear()
	var toggle: Vector2=rects["engine.ignition_left"].get_center()
	_button(panel,toggle,true);_button(panel,toggle,true)
	_check(_events.size()==1 and _events[0].value==true,"desired_bool_chosen_once")
	_motion(panel,toggle+Vector2(5,0))
	_check(_events.size()==1,"switch_has_no_moves")
	_button(panel,toggle,false)
	_check(_events.size()==2 and _events[1].value==null,"switch_terminal_null")
	_check(panel._actual("engine.ignition_left")==false and panel._requested("engine.ignition_left")==false,"queued_toggle_not_actual_or_sampled")
	view.last_token=3;view.requested_systems["engine.ignition_left"]=true;panel.set_state(view,engine,preset,true)
	_events.clear()
	var starter: Vector2=rects["engine.starter"].get_center()
	_button(panel,starter,true)
	_motion(panel,starter-Vector2(180,0));_motion(panel,starter)
	_check(_events.size()==2 and _events[0].value==true and _events[1].phase=="end" and _events[1].value==false,"starter_leave_and_no_reentry")
	_check(panel._preview==false and panel._terminal and panel._actual("engine.starter")==false and panel._requested("engine.starter")==false,"starter_leave_preview_matches_queued_release_without_repainting_truth")
	_button(panel,starter,true)
	_check(_events.size()==2,"held_reentry_no_new_capture")
	view.last_token=4;view.capture=null;view.rearm_buttons=[1];panel.set_state(view,engine,preset,true)
	_button(panel,starter,true)
	_check(_events.size()==2,"mapper_rearm_blocks_fresh_hold")
	_button(panel,starter,false);view.rearm_buttons=[];panel.set_state(view,engine,preset,true)
	_button(panel,starter,true)
	_check(_events.size()==3 and _events[-1].token==5 and _events[-1].value==true,"observed_release_then_fresh_starter")
	# Paused native starter true stays true while local preview/capture retires.
	engine.state="paused";engine.readings["engine.starter"].value=true;view.generation=5
	panel.set_state(view,engine,preset,false,"Paused · release starter before resume")
	_check(panel._capture.is_empty() and panel._actual("engine.starter")==true and panel.hit_control(starter)=="","paused_actual_truth_and_no_capture")
	var before_count: int=_events.size();_button(panel,starter,false)
	_check(_events.size()==before_count,"retired_up_no_new_gesture")
	engine=_engine();view=_view();panel.set_state(view,engine,preset,true)
	# Visual bound/fixed disabling retains host preflight hit region.
	preset.actions.append({"id":"both_brakes","sources":[{"kind":"mouse_button","button":1}]})
	panel.set_state(view,engine,preset,true)
	_check(panel.hit_control(starter)=="engine.starter" and "both_brakes" in panel._control_reason("engine.starter"),"bound_region_stays_preflight_eligible")
	_check(panel._binding_caption(panel._button_binding(preset))=="Both Brakes","bound_display_names_action_without_internal_path")
	_events.clear();_denied.clear();_button(panel,starter,true);_button(panel,starter,false)
	_check(_events.is_empty() and _denied.size()==1 and "remap" in _denied[0].reason,"bound_gui_denied_signal_only")
	preset=_preset();preset.axes[0]={"target":"throttle","kind":"fixed","value":0.35};panel.set_state(view,engine,preset,true)
	_check(panel.hit_control(thumb)=="throttle" and "35%" in panel._control_reason("throttle"),"fixed_explicit_disabled_value")
	_events.clear();_button(panel,thumb,true);_button(panel,thumb,false)
	_check(_events.is_empty(),"fixed_never_emits")
	preset=_preset();panel.set_state(view,engine,preset,true)
	_events.clear();_button(panel,starter,true,MOUSE_BUTTON_RIGHT);_button(panel,starter,false,MOUSE_BUTTON_RIGHT);_button(panel,starter,true,MOUSE_BUTTON_WHEEL_UP)
	_check(_events.is_empty(),"nonprimary_and_wheel_not_engine_gestures")
	_button(panel,thumb,true)
	panel.set_expanded(false)
	_check(not panel.is_expanded() and panel.expanded_height()==30 and panel._capture.is_empty() and panel.hit_control(thumb)=="" and not _invalidations.is_empty(),"collapse_retires_and_removes_regions")
	panel.set_expanded(true);view.generation=6;panel.set_state(view,engine,preset,true)
	_events.clear();_button(panel,starter,true);panel.hide()
	_check(panel._capture.is_empty() and _invalidations[-1]=="Engine controls hidden","visibility_capture_loss")
	panel.show();view.generation=7;panel.set_state(view,engine,preset,true)
	var invalid_count: int=_invalidations.size();panel.invalidate_local("Host transition")
	_check(_invalidations.size()==invalid_count and panel._capture.is_empty(),"host_local_clear_no_recursion")
	engine.state="historical";panel.set_state(view,engine,preset,true)
	_check(panel.hit_control(starter)=="","retained_even_erroneous_host_eligible_disabled")
	engine.state="live";engine.session_id="different-session";panel.set_state(view,engine,preset,true)
	_check(panel.hit_control(starter)=="","identity_mismatch_disabled")
	_check(var_to_bytes([_view(),_engine(),_preset()])==source_bytes,"initial_fixture_unchanged_by_panel")
	# Preserve all original wide-mode checks above; add real builder-derived compact
	# rectangles, fallback-font measurement and viewport-routed narrow gestures.
	panel.set_expanded(true);panel.show()
	view=_view();engine=_engine();preset=_preset()
	view.generation=8;panel.set_state(view,engine,preset,true,"","Look: Mouse 2 · release to expose pointer; P pauses · F7 Controls")
	for narrow_width in [260.0,270.0]:
		panel.size=Vector2(narrow_width,300.0)
		await host.get_tree().process_frame
		var narrow: Dictionary=panel._rects()
		_check(panel.expanded_height()==300.0 and panel.custom_minimum_size.y==300.0,"compact_height_"+str(narrow_width))
		_check(panel._font.get_string_size(panel._header_text(),HORIZONTAL_ALIGNMENT_LEFT,-1,10).x<=narrow_width-24.0,"compact_header_font_fit_"+str(narrow_width))
		_check(panel._font.get_string_size(panel._legend_text(),HORIZONTAL_ALIGNMENT_LEFT,-1,10).x<=narrow_width-24.0,"compact_legend_font_fit_"+str(narrow_width))
		_check(panel._font.get_string_size("Hover for bindings / release guidance",HORIZONTAL_ALIGNMENT_LEFT,-1,10).x<=narrow_width-24.0,"compact_guidance_font_fit_"+str(narrow_width))
		for control in narrow:
			var narrow_rect: Rect2=narrow[control]
			_check(narrow_rect.position.x>=12 and narrow_rect.end.x<=narrow_width-12 and narrow_rect.end.y<=272 and narrow_rect.size.x>=114 and narrow_rect.size.y==54,"compact_bounds_"+str(narrow_width)+"_"+control)
			_check(panel.hit_control(narrow_rect.get_center())==control,"compact_hit_"+str(narrow_width)+"_"+control)
			_check(panel._font.get_string_size(panel.LABELS[control],HORIZONTAL_ALIGNMENT_LEFT,-1,11).x<=narrow_rect.size.x,"compact_caption_font_fit_"+str(narrow_width)+"_"+control)
			for other in narrow:
				if other!=control: _check(not narrow_rect.intersects(narrow[other]),"compact_disjoint_"+str(narrow_width)+"_"+control+"_"+other)
			if control in panel.AXES:
				var geometry_track: Rect2=panel._track(control)
				_check(narrow_rect.encloses(geometry_track) and geometry_track.size.x>=94,"compact_track_"+str(narrow_width)+"_"+control)
				_check(panel._font.get_string_size("A 100%  R 100%",HORIZONTAL_ALIGNMENT_LEFT,-1,11).x<=narrow_rect.size.x,"compact_axis_values_font_fit_"+str(narrow_width)+"_"+control)
			else:
				_check(panel._font.get_string_size("A OFF",HORIZONTAL_ALIGNMENT_LEFT,-1,12).x<=narrow_rect.size.x-12,"compact_switch_values_font_fit_"+str(narrow_width)+"_"+control)
		_check(panel.hit_control(Vector2(16,35)).is_empty() and panel.hit_control(Vector2(16,130)).is_empty() and panel.hit_control(Vector2(16,289)).is_empty(),"compact_noncontrol_chrome_"+str(narrow_width))
		_events.clear()
		var narrow_track: Rect2=panel._track("throttle")
		var narrow_thumb: Vector2=Vector2(narrow_track.position.x+0.4*narrow_track.size.x,narrow_track.get_center().y)
		_button(panel,narrow_thumb,true)
		_check(_events.size()==1 and _events[0].value==0.4 and _events[0].phase=="begin","compact_gui_thumb_request_"+str(narrow_width))
		_motion(panel,Vector2(narrow_track.end.x+30,narrow_track.get_center().y));_button(panel,Vector2(narrow_track.end.x+30,narrow_track.get_center().y),false)
		_check(_events.size()==3 and _events[-1].phase=="end" and _events[-1].value==1.0 and panel._actual("throttle")==0.1 and panel._requested("throttle")==0.4,"compact_gui_final_axis_truth_"+str(narrow_width))
		view.generation+=1;view.last_token=0;panel.set_state(view,engine,preset,true,"","Look: Mouse 2 · release to expose pointer; P pauses · F7 Controls")
		_events.clear()
		var compact_starter: Vector2=narrow["engine.starter"].get_center()
		_button(panel,compact_starter,true);_motion(panel,Vector2(narrow_width+30,compact_starter.y));_motion(panel,compact_starter)
		_check(_events.size()==2 and _events[0].value==true and _events[1].phase=="end" and _events[1].value==false,"compact_gui_starter_leave_"+str(narrow_width))
		_button(panel,compact_starter,false)
		view.generation+=1;panel.set_state(view,engine,preset,true,"","Look: Mouse 2 · release to expose pointer; P pauses · F7 Controls")
		_motion(panel,narrow["mixture"].get_center())
		_check("Axis synthetic-fixture:2" in panel.tooltip_text and "release arms .03 pickup" in panel.tooltip_text and "Mouse 2" in panel.tooltip_text and "F7 Controls" in panel.tooltip_text,"compact_tooltip_updates_before_any_draw_"+str(narrow_width))
		await host.get_tree().process_frame
		_check("Axis synthetic-fixture:2" in panel.tooltip_text and "release arms .03 pickup" in panel.tooltip_text and "Mouse 2" in panel.tooltip_text and "F7 Controls" in panel.tooltip_text,"compact_full_remap_tooltip_"+str(narrow_width))
		var narrow_invalidations: int=_invalidations.size()
		_button(panel,Vector2(20,15),true);_button(panel,Vector2(20,15),false)
		_check(not panel.is_expanded() and panel.expanded_height()==30 and _invalidations.size()==narrow_invalidations+1 and panel.hit_control(compact_starter).is_empty(),"compact_gui_collapse_"+str(narrow_width))
		_button(panel,Vector2(20,15),true);_button(panel,Vector2(20,15),false)
		_check(panel.is_expanded() and panel.expanded_height()==300,"compact_gui_expand_"+str(narrow_width))
		view.generation+=1;panel.set_state(view,engine,preset,true)
	panel.size=Vector2(940,140);await host.get_tree().process_frame
	_check(panel.expanded_height()==140 and panel._rects()==rects,"responsive_return_preserves_wide_geometry")
	# Medium outside-view strip: full text captions fit measured fallback font,
	# and a second legend line keeps header/status separate without new semantics.
	view=_view();engine=_engine();preset=_preset();view.generation=20
	panel.set_state(view,engine,preset,true)
	for medium_width in [600.0,620.0,899.0]:
		panel.size=Vector2(medium_width,156.0)
		await host.get_tree().process_frame
		var medium_rects: Dictionary=panel._rects()
		_check(panel._medium() and not panel._compact() and panel.expanded_height()==156 and panel.custom_minimum_size.y==156,"medium_height_"+str(medium_width))
		_check(panel._font.get_string_size(panel._header_text(),HORIZONTAL_ALIGNMENT_LEFT,-1,12).x<=medium_width-24,"medium_header_font_fit_"+str(medium_width))
		_check(panel._font.get_string_size(panel._legend_text(),HORIZONTAL_ALIGNMENT_LEFT,-1,11).x<=medium_width-24,"medium_legend_font_fit_"+str(medium_width))
		for control in medium_rects:
			var medium_rect: Rect2=medium_rects[control]
			_check(medium_rect.position.x>=12 and medium_rect.end.x<=medium_width-12 and medium_rect.position.y==62 and medium_rect.end.y==116 and medium_rect.size.x>=65,"medium_bounds_"+str(medium_width)+"_"+control)
			_check(panel.hit_control(medium_rect.get_center())==control,"medium_hit_"+str(medium_width)+"_"+control)
			var caption_pixels: int=panel._label_pixels(control,medium_rect.size.x)
			_check(caption_pixels in [9,10,11] and panel._font.get_string_size(panel.LABELS[control],HORIZONTAL_ALIGNMENT_LEFT,-1,caption_pixels).x<=medium_rect.size.x,"medium_full_caption_font_fit_"+str(medium_width)+"_"+control)
			for candidate_pixels in [11,10,9]:
				if candidate_pixels>caption_pixels: _check(panel._font.get_string_size(panel.LABELS[control],HORIZONTAL_ALIGNMENT_LEFT,-1,candidate_pixels).x>medium_rect.size.x,"medium_largest_fitting_font_"+str(medium_width)+"_"+control+"_"+str(candidate_pixels))
			for other in medium_rects:
				if other!=control: _check(not medium_rect.intersects(medium_rects[other]),"medium_disjoint_"+str(medium_width)+"_"+control+"_"+other)
			if control in panel.AXES:
				_check(medium_rect.encloses(panel._track(control)),"medium_track_"+str(medium_width)+"_"+control)
				_check(panel._font.get_string_size("A 100%  R 100%",HORIZONTAL_ALIGNMENT_LEFT,-1,11).x<=medium_rect.size.x,"medium_axis_values_font_fit_"+str(medium_width)+"_"+control)
			else:
				_check(panel._font.get_string_size("A OFF",HORIZONTAL_ALIGNMENT_LEFT,-1,12).x<=medium_rect.size.x-12 and panel._font.get_string_size("R OFF",HORIZONTAL_ALIGNMENT_LEFT,-1,12).x<=medium_rect.size.x-12,"medium_switch_values_font_fit_"+str(medium_width)+"_"+control)
		_check(panel.hit_control(Vector2(16,36)).is_empty() and panel.hit_control(Vector2(16,130)).is_empty() and panel.hit_control(Vector2(16,149)).is_empty(),"medium_noncontrol_chrome_"+str(medium_width))
		_events.clear()
		var medium_starter: Vector2=medium_rects["engine.starter"].get_center()
		_button(panel,medium_starter,true);_button(panel,medium_starter,false)
		_check(_events.size()==2 and _events[0].control=="engine.starter" and _events[0].value==true and _events[1].value==false and panel._actual("engine.starter")==false,"medium_real_gui_starter_truth_"+str(medium_width))
		_check(panel._preview==false and panel._terminal and panel._requested("engine.starter")==false,"medium_unsampled_up_preview_is_OFF_"+str(medium_width))
		view.generation+=1;panel.set_state(view,engine,preset,true)
		var medium_invalidations: int=_invalidations.size()
		_button(panel,Vector2(20,15),true);_button(panel,Vector2(20,15),false)
		_check(not panel.is_expanded() and panel.expanded_height()==30 and _invalidations.size()==medium_invalidations+1,"medium_gui_collapse_"+str(medium_width))
		_button(panel,Vector2(20,15),true);_button(panel,Vector2(20,15),false)
		_check(panel.is_expanded() and panel.expanded_height()==156,"medium_gui_expand_"+str(medium_width))
		view.generation+=1;panel.set_state(view,engine,preset,true)
	panel.size=Vector2(940,140);await host.get_tree().process_frame
	_check(not panel._medium() and panel.expanded_height()==140 and panel._rects()==rects,"medium_return_preserves_wide_geometry")
	# Captured mouse look cannot hover. Its current host-supplied binding and
	# release instruction must fit visibly below the compact switch rows.
	for hint_width in [260.0,270.0]:
		panel.size=Vector2(hint_width,300);await host.get_tree().process_frame
		var default_hint: String="Look: Mouse 2 · release to expose pointer; P pauses · F7 Controls"
		panel.set_state(view,engine,preset,false,"Release mouse look to use engine controls",default_hint)
		await host.get_tree().process_frame
		_check(panel._compact_look_text()=="Look: Mouse 2 · release to use","compact_visible_default_look_"+str(hint_width))
		_check(panel._font.get_string_size(panel._compact_look_text(),HORIZONTAL_ALIGNMENT_LEFT,-1,9).x<=hint_width-24,"compact_visible_default_look_font_fit_"+str(hint_width))
		_check(panel._font.get_ascent(9)<=12 and 284+panel._font.get_descent(9)<=297-panel._font.get_ascent(9) and 297+panel._font.get_descent(9)<=300,"compact_two_footer_lines_bounds_"+str(hint_width))
		_check(panel._fit_text(panel._reason,hint_width-24,9).begins_with("Release mouse look") and default_hint in panel.tooltip_text and "P pauses" in panel.tooltip_text and "F7 Controls" in panel.tooltip_text,"compact_captured_status_and_full_tooltip_"+str(hint_width))
		var key_hint: String="Look: Q / Button custom-hotas-slot-with-many-controls-and-panels:14 · release to expose pointer; P pauses · F7 Controls"
		panel.set_state(view,engine,preset,false,"Release mouse look to use engine controls",key_hint)
		await host.get_tree().process_frame
		var fitted_look: String=panel._compact_look_text()
		_check(fitted_look.begins_with("Look: Q / Button") and fitted_look.ends_with(" · release to use") and "…" in fitted_look and not "Mouse 2" in fitted_look,"compact_visible_remapped_look_ellipsis_"+str(hint_width))
		_check(panel._font.get_string_size(fitted_look,HORIZONTAL_ALIGNMENT_LEFT,-1,9).x<=hint_width-24 and key_hint in panel.tooltip_text,"compact_full_remapped_hint_retained_"+str(hint_width))
		var short_key_hint: String="Look: Q / Button slot:14 · release to expose pointer; P pauses · F7 Controls"
		panel.set_state(view,engine,preset,false,"Release mouse look to use engine controls",short_key_hint);await host.get_tree().process_frame
		_check(panel._compact_look_text()=="Look: Q / Button slot:14 · release to use" and panel._font.get_string_size(panel._compact_look_text(),HORIZONTAL_ALIGNMENT_LEFT,-1,9).x<=hint_width-24 and short_key_hint in panel.tooltip_text,"compact_short_remapped_hint_unabridged_"+str(hint_width))
		for disabled_reason in ["Paused / retained / unavailable · resume explicitly","Release left button before a fresh press","Input invalid · preset/actions/look_hold source unavailable"]:
			panel.set_state(view,engine,preset,false,disabled_reason,key_hint);await host.get_tree().process_frame
			var fitted_reason: String=panel._fit_text(panel._reason,hint_width-24,9)
			_check(panel._reason==disabled_reason and panel._font.get_string_size(fitted_reason,HORIZONTAL_ALIGNMENT_LEFT,-1,9).x<=hint_width-24 and disabled_reason in panel.tooltip_text,"compact_honest_disabled_reason_"+str(hint_width)+"_"+disabled_reason)
		panel.set_state(view,engine,preset,false,"Look binding unavailable","");await host.get_tree().process_frame
		_check("unavailable" in panel._compact_look_text() and not "Mouse 2" in panel._compact_look_text(),"compact_missing_hint_not_invented_"+str(hint_width))
	panel.queue_free();await host.get_tree().process_frame
	return {"passed":_failures.is_empty(),"checks":_checks,"failures":_failures,"scope":"Real viewport-routed GUI events against synthetic copied view/status; no native, mapper Raw, physical hardware, exported pixels or phase qualification."}
