extends RefCounted
# Original MIT. Paused editor API tests with synthetic copied controls only.
const Controls=preload("res://ui/controls/controls_panel.gd")
const Mapper=preload("res://input/input_mapper.gd")
const Preset=preload("res://input/input_preset.gd")
const Fixtures=preload("res://input_tests/piston_checks.gd")
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
 var file_path:String="user://synthetic-v1-migration.json"
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
 return {"passed":_failures.is_empty(),"checks":_checks,"failures":_failures.duplicate(),"scope":"synthetic paused editor API; no native/hardware/GPU"}
