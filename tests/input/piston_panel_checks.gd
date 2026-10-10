extends RefCounted
# Original MIT. Paused editor API tests with synthetic copied controls only.
const Controls=preload("res://ui/controls/controls_panel.gd")
const Mapper=preload("res://input/input_mapper.gd")
const Preset=preload("res://input/input_preset.gd")
const Fixtures=preload("res://input_tests/piston_checks.gd")
const FlightPanel=preload("res://interactive/flight_panel.gd")
var _checks:int=0
var _failures:Array[String]=[]
var _applied:Array=[]
var _dismissals:int=0
func check(value:bool,label:String)->void:
 _checks+=1
 if not value:_failures.append(label)
func run(host:Node)->Dictionary:
 var viewport:=SubViewport.new();viewport.size=Vector2i(960,540);host.add_child(viewport)
 var panel=Controls.new();viewport.add_child(panel)
 panel.applied.connect(func(value:Dictionary):_applied.append(value.duplicate(true)))
 panel.dismissed.connect(func():_dismissals+=1)
 var preset:Dictionary=Mapper.default_preset_v2();var held:Dictionary=Fixtures.systems()
 panel.open_v2(preset,Fixtures.raw(),Fixtures.axes(),Fixtures.axes(),Preset.PISTON_PROFILE,held)
 await host.get_tree().process_frame
 await host.get_tree().process_frame
 check(panel._v2 and panel._valid and not panel._apply_button.disabled,"v2_editor_valid_and_apply_enabled")
 check(panel.size==Vector2(960,540),"minimum_viewport_editor_bounds")
 check(panel._engine_status_label.visible and panel._hint_label.text.contains("idealized"),"visible_native_controls_and_supply_scope")
 preset.systems[0].sources[0].keys[0]=KEY_Z;held["fuel.feed"]=false
 check(panel.get_draft().systems[0].sources[0].keys[0]==KEY_F8 and panel._held_systems["fuel.feed"],"open_owns_preset_and_feedback")
 var copy:Dictionary=panel.get_draft();copy.profile.id="wrong"
 check(panel.get_draft().profile==Preset.PISTON_PROFILE,"draft_read_is_owned")
 panel._apply()
 check(_applied.size()==1 and Preset.validate_preset_v2(_applied[0]).ok,"explicit_apply_emits_valid_v2_only")
 var before:Dictionary=panel.get_draft()
 panel.open_v2(Mapper.default_preset_v2(),Fixtures.raw(),Fixtures.axes(),Fixtures.axes(),{},Fixtures.systems())
 check(panel.get_draft()==before,"bad_verified_profile_preserves_draft")
 panel.update_diagnostics(Fixtures.raw(),Fixtures.axes(),Fixtures.axes(),{"profile":Preset.PISTON_PROFILE,"held_systems":Fixtures.systems(),"pending_systems":{"engine.ignition_left":true,"engine.ignition_right":false,"engine.starter":true,"fuel.feed":true},"takeover":["mixture"],"brake_hold":true})
 check(panel._engine_status_label.text.contains("NATIVE HELD") and panel._engine_status_label.text.contains("PENDING (not admission)") and panel._status_label.text.contains("mixture"),"held_pending_takeover_distinct")
 panel.update_diagnostics(Fixtures.raw(),Fixtures.axes(),Fixtures.axes(),{"profile":Preset.PISTON_PROFILE,"held_systems":{},"pending_systems":Fixtures.systems()})
 check(panel._engine_status_label.text.contains("unavailable"),"bad_system_feedback_not_guessed_off")
 # Actual selected-file path enters a deliberately invalid draft, never applies.
 var file_path:String="user://synthetic-v1-migration-"+str(OS.get_process_id())+"-"+str(Time.get_ticks_usec())+".json"
 var file=FileAccess.open(file_path,FileAccess.WRITE);file.store_buffer(Preset.encode(Mapper.default_preset()).value);file.close()
 panel._save_dialog=false;panel._file_selected(file_path)
 check(panel.get_draft().version==2 and not panel._valid and panel._apply_button.disabled,"v1_import_is_disabled_migration_draft")
 check(panel._message.text.contains("UNBOUND") and panel._message.text.contains("full rich"),"migration_warning_visible")
 panel._apply();check(_applied.size()==1,"migration_cannot_apply_unbound_controls")
 for item in [["engine.ignition_left",KEY_F8],["engine.ignition_right",KEY_F9],["engine.starter",KEY_F12],["fuel.feed",KEY_F10]]:
  panel._learn({"mode":"system","id":item[0]})
  panel.update_diagnostics(Fixtures.raw(),Fixtures.axes(),Fixtures.axes())
  var event:=InputEventKey.new();event.physical_keycode=item[1];event.pressed=true;panel._input(event)
 check(panel._valid and not panel._apply_button.disabled,"all_four_engine_bindings_explicitly_learned")
 panel._change_kind("mixture",0)
 check(panel._axis("mixture").kind=="key_pair" and panel._axis("mixture").negative==[KEY_COMMA] and panel._axis("mixture").positive==[KEY_PERIOD],"mixture_digital_binding_editable")
 panel._apply();check(_applied.size()==2 and Preset.validate_preset_v2(_applied[1]).ok,"migration_explicit_final_apply")
 panel._learn({"mode":"system","id":"engine.starter"});panel.update_diagnostics(Fixtures.raw(),Fixtures.axes(),Fixtures.axes())
 var wheel:=InputEventMouseButton.new();wheel.button_index=MOUSE_BUTTON_WHEEL_UP;wheel.pressed=true
 before=panel.get_draft();panel._input(wheel)
 check(panel.get_draft()==before and not panel._capture.is_empty() and panel._message.text.contains("wheel"),"wheel_not_accepted_as_engine_capture")
 panel._cancel();check(_dismissals==1 and panel._capture.is_empty() and panel.get_draft()==before,"cancel_capture_no_apply")
 panel.open(Mapper.default_preset(),Fixtures.raw(),Fixtures.axes(1.0),Fixtures.axes(1.0))
 check(not panel._v2 and not panel._engine_status_label.visible and Preset.validate_preset(panel.get_draft()).ok,"legacy_editor_mode_restored")
 viewport.queue_free()
 await host.get_tree().process_frame
 await _feedback(host)
 return {"passed":_failures.is_empty(),"checks":_checks,"failures":_failures.duplicate(),"scope":"synthetic paused editor API; no native/hardware/GPU"}

func _feedback(host:Node)->void:
 var panel=FlightPanel.new()
 host.add_child(panel)
 panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
 panel.size=Vector2(960,540)
 var channels:Dictionary={}
 for item in [["propeller.angular_speed",100.0,"rad/s"],["engine.mixture",1.0,"ratio"],["fuel.total",20.0,"kg"],["engine.running",true,"bool"],["engine.starter",false,"bool"],["engine.ignition_left",true,"bool"],["engine.ignition_right",true,"bool"],["fuel.feed",true,"bool"],["engine.starved",false,"bool"]]:
  channels[item[0]]={"value":item[1],"unit":item[2],"valid":true,"error":""}
 var info:Dictionary={"engine_status":{"native_truth":true,"state":"paused","readings":channels},"view_name":"CHASE"}
 var original:Dictionary=info.duplicate(true)
 panel.set_state({}, {}, {}, info)
 var owned:Dictionary=panel._info.duplicate(true)
 info.engine_status.readings["fuel.feed"].value=false
 check(panel._info==owned,"feedback_caller_mutation_cannot_change_copied_truth")
 info.engine_status.readings["fuel.feed"].value=true
 check(panel._engine_feedback_layout().bounds==Rect2(10,90,940,54),"feedback_original_fallback")
 var bounds:=Rect2(272,150,416,86)
 check(panel.set_engine_feedback_bounds(bounds),"feedback_copied_bounds_admitted")
 bounds.position.x=1
 check(panel._engine_feedback_bounds==Rect2(272,150,416,86),"feedback_bounds_value_owned")
 check(panel.set_engine_feedback_bounds(Rect2(272,150,416,86)) and panel._info==owned,"feedback_idempotent_no_state_change")
 var saved:Rect2=panel._engine_feedback_bounds
 for bad in [Rect2(-1,0,100,54),Rect2(0,0,-1,54),Rect2(0,0,100,0),Rect2(950,0,20,54),Rect2(0,530,100,54),Rect2(NAN,0,100,54),Rect2(0,0,INF,54)]:
  check(not panel.set_engine_feedback_bounds(bad) and panel._engine_feedback_bounds==saved and panel._info==owned,"feedback_invalid_preserves_"+str(bad))
 for retained in [false,true]:
  info.retained=retained;panel.set_state({}, {}, {}, info)
  var layout:Dictionary=panel._engine_feedback_layout()
  check(layout.fits and layout.pixels==12,"feedback_chase_complete_fit_"+str(retained))
  for row in 2:
   check(" ".join(layout.rows[row])==layout.texts[row] and not layout.texts[row].contains("…"),"feedback_complete_row_"+str(retained)+str(row))
  check(layout.texts[0].begins_with("RETAINED" if retained else "ENGINE") and layout.texts[1].ends_with("IDEALIZED STARTER SUPPLY"),"feedback_scope_and_supply_preserved_"+str(retained))
 for phase in [[false,false,0.0,"STOPPED"],[false,true,1.0,"CRANKING"],[false,false,1.0,"COASTING"],[true,false,1.0,"RUNNING"]]:
  info.engine_status.readings["engine.running"].value=phase[0];info.engine_status.readings["engine.starter"].value=phase[1];info.engine_status.readings["propeller.angular_speed"].value=phase[2]
  panel.set_state({}, {}, {}, info)
  check(panel._engine_phase()==phase[3] and panel._engine_feedback_layout().texts[0].contains(phase[3]),"feedback_phase_"+phase[3])
 for value in [-9.999e307,1e100,999999.0,-999999.0]:
  info.engine_status.readings["fuel.total"].value=value
  panel.set_state({}, {}, {}, info)
  var layout:Dictionary=panel._engine_feedback_layout()
  check(layout.fits and layout.texts[0].contains("FUEL "+panel._native_number(value,1)+" kg") and " ".join(layout.rows[0])==layout.texts[0],"feedback_unchanged_large_formatter_"+str(value))
 info.engine_status.readings["fuel.total"].valid=false
 panel.set_state({}, {}, {}, info)
 check(panel._engine_feedback_layout().texts[0].contains("FUEL — kg"),"feedback_invalid_channel_not_guessed")
 check(panel.set_engine_feedback_bounds(Rect2(0,0,30,20)) and not panel._engine_feedback_layout().fits,"feedback_unfit_not_truncated_or_passed")
 panel.size=Vector2(1920,1080)
 check(panel.set_engine_feedback_bounds(Rect2(10,1020,1566,54)) and panel._engine_feedback_layout().pixels==14 and panel._engine_feedback_layout().fits,"feedback_viewport_font_not_rectangle_width")
 panel.size=Vector2(960,540)
 check(not panel._engine_feedback_layout().fits,"feedback_stale_resize_not_hidden")
 for viewport_size in [Vector2(960,540),Vector2(1920,1080),Vector2(2560,1440)]:
  panel.size=viewport_size
  var column:float=clampf(viewport_size.x/6.0,250.0,360.0)
  for rect in [Rect2(column+28,194,viewport_size.x-column-42,54),Rect2(10,viewport_size.y-60,viewport_size.x-column-34,54),Rect2(column+22,182,viewport_size.x-2*column-44,86)]:
   check(panel.set_engine_feedback_bounds(rect) and panel._engine_feedback_layout().fits and panel._engine_feedback_layout().pixels==(12 if viewport_size.x<1100 else 14),"feedback_three_modes_and_viewport_fonts_"+str(viewport_size)+str(rect))
 panel.size=Vector2(960,540)
 check(panel.set_engine_feedback_bounds(Rect2()) and panel._engine_feedback_layout().bounds==Rect2(10,123,940,54),"feedback_zero_restores_retained_fallback")
 check(original.engine_status.readings["fuel.total"].value==20.0 and panel._held.is_empty() and panel._snapshot.is_empty(),"feedback_never_mutates_source_or_controls")
 panel.queue_free()
 await host.get_tree().process_frame
