extends RefCounted
# Original MIT. Actual production scene/facade; real viewport GUI events and
# separately supplied complete synthetic Raw. No OS injection or engine goldens.
const Scene=preload("res://simulation/flight_scene.gd")
const Facade=preload("res://simulation/session_facade.gd")
const Mapper=preload("res://input/input_mapper.gd")
const Status=preload("res://cockpit/instruments/engine_status.gd")
const Preset=preload("res://input/input_preset.gd")
var _host: Node
var _checks: int=0
var _failures: Array[String]=[]
class SyntheticScene extends Scene:
 var synthetic_raw: Dictionary={"keys":[],"mouse_buttons":[],"devices":[]}
 var release_fixture: Dictionary={"keys":[],"mouse_buttons":[],"devices":[]}
 var pause_entries: Array[Dictionary]=[]
 var layout_retirements: Array[Dictionary]=[]
 func invalidate_engine_pointer(reason: String) -> void:
  if reason=="Engine controls layout changed":
   # Observe the real host call before it invalidates ownership or remaps hits.
   # No native/input mutation is performed by this test-only observer.
   layout_retirements.append({"reason":reason,"rect":engine_controls.get_rect(),
    "pointer":mapper.pointer_view(),"raw":synthetic_raw.duplicate(true)})
  super.invalidate_engine_pointer(reason)
 func collect_input_raw(_preset: Dictionary={}) -> Dictionary:
  return synthetic_raw.duplicate(true)
 func mapper_intent_snapshot() -> Dictionary:
  if mapper==null: return {}
  # Test-only inspection before normal suspend reseeds from actual held state.
  # Staged pointer metadata is excluded: queueing a terminal is permitted, while
  # all sampled intent/filter/edge/latch/takeover fields must remain untouched.
  return {"preset":mapper.get("_preset").duplicate(true),
   "values":mapper.get("_values").duplicate(true),"start":mapper.get("_start").duplicate(true),
   "pins":mapper.get("_pins").duplicate(true),"edges":mapper.get("_edges").duplicate(true),
   "takeover":mapper.get("_takeover").duplicate(true),"configured":mapper.get("_configured"),
   "live":mapper.get("_live"),"brake_hold":mapper.get("_brake_hold"),"v2":mapper.get("_v2"),
   "held_systems":mapper.get("_held_systems").duplicate(true),
   "system_intents":mapper.get("_system_intents").duplicate(true),
   "system_edges":mapper.get("_system_edges").duplicate(true),
   "host_controls":controls.duplicate(true),"host_brake":brake_hold,
   "host_takeover":takeover_targets.duplicate(),"host_pending_systems":pending_systems.duplicate(true),
   "host_rearm":engine_pointer_rearm.duplicate(),"host_look":engine_pointer_look_active}
 func pause_for_input(reason: String) -> void:
  pause_entries.append({"reason":reason,"mapper":mapper_intent_snapshot(),
   "pointer":mapper.pointer_view() if mapper!=null else {},
   "host_controls":controls.duplicate(true),"host_brake":brake_hold,
   "host_takeover":takeover_targets.duplicate(),"pending_systems":pending_systems.duplicate(true),
   "host_rearm":engine_pointer_rearm.duplicate()})
  super.pause_for_input(reason)

func _check(ok: bool,label: String) -> void:
 _checks+=1
 if not ok: _failures.append(label)
 _host.check(ok,"pointer_scene_"+label)

func _retained(scene: Node) -> Dictionary:
 var state: Dictionary=scene.facade.readback()
 return {"session":state.session_id,"tick":state.tick,"aircraft":state.aircraft,
  "atmosphere":state.atmosphere,"held_axes":state.held_axes,"debt":state.debt_quanta,
  "model":state.model_identity,"source":state.native_source_fingerprint,
  "world":state.world_anchor,"prepared":state.prepared_world_sha256,
  "pilot_sequence":scene.facade.get("_command_sequence"),
  "pending_commands":scene.facade.get("_pending_commands").duplicate(true),
  "submitted":scene.submitted_count}

func _actual_starter(scene: Node) -> bool:
 return Status.from_readback(scene.facade.readback()).readings["engine.starter"].value==true

func _released(scene: Node) -> void:
 scene.synthetic_raw=scene.release_fixture.duplicate(true)

func _resume(scene: Node,label: String) -> bool:
 _released(scene)
 var ok: bool=scene.pause_session(false)
 _check(ok,label+"_explicit_resume")
 if not ok: return false
 scene.menu_open=false;scene.menu.hide()
 Input.mouse_mode=Input.MOUSE_MODE_VISIBLE
 scene.engine_controls.set_expanded(true)
 scene.show_state()
 _check(scene.pointer_ui_eligible(),label+"_qualified_live_pointer_owner")
 return scene.pointer_ui_eligible()

func _point(scene: Node,control: String,fraction: float=-1.0) -> Vector2:
 var panel: Control=scene.engine_controls
 if fraction<0.0: return panel._rects()[control].get_center()
 var track: Rect2=panel._track(control)
 return Vector2(track.position.x+track.size.x*fraction,track.get_center().y)

func _button(scene: Node,control: String,pressed: bool,fraction: float=-1.0) -> void:
 var event: InputEventMouseButton=InputEventMouseButton.new()
 event.position=scene.engine_controls.get_global_transform_with_canvas()*_point(scene,control,fraction)
 event.global_position=event.position
 event.button_index=MOUSE_BUTTON_LEFT;event.pressed=pressed
 event.button_mask=MOUSE_BUTTON_MASK_LEFT if pressed else 0
 # The actual host preflight precedes the GUI path. Scene OS callbacks are
 # disabled below: viewport routes only the real Control event, Raw stays ours.
 scene._input(event)
 scene.get_viewport().push_input(event,true)

func _begin(scene: Node,control: String,fraction: float=-1.0) -> Dictionary:
 scene.synthetic_raw.mouse_buttons=[1]
 _button(scene,control,true,fraction)
 var view: Dictionary=scene.mapper.pointer_view()
 _check(view.capture!=null and view.capture.control==control,"real_gui_begin_"+control)
 return {"session_id":view.session_id,"generation":view.generation,
  "token":view.capture.token if view.capture!=null else 1,"control":control,
  "phase":"end","button":1,"value":false if control=="engine.starter" else null}

func _bound_cases(scene: Node) -> void:
 for id in ["both_brakes","view_cycle","pause_menu","look_hold","engine.ignition_left"]:
  _released(scene)
  _check(scene.pause_session(true),"bound_"+id+"_pause_for_Apply")
  var preset: Dictionary=Mapper.default_preset_v2()
  for binding in preset.actions+preset.systems:
   if binding.id==id: binding.sources=[{"kind":"mouse_button","button":1}]
  scene.apply_controls(preset)
  _check(scene.active_preset==preset,"bound_"+id+"_valid_remap_not_mutated")
  if not _resume(scene,"bound_"+id): continue
  var before: Dictionary=_retained(scene)
  var before_mapper: Dictionary=scene.mapper_intent_snapshot()
  scene.pause_entries.clear()
  scene.synthetic_raw.mouse_buttons=[1]
  _button(scene,"engine.starter",true)
  _assert_pre_pause(scene,before_mapper,"bound_"+id)
  _check(scene.facade.readback().paused and scene.input_blocked,"bound_"+id+"_preflight_pause")
  _check(_retained(scene)==before,"bound_"+id+"_no_command_tick_debt_or_native_prefix")
  _check(scene.mapper.pointer_view().capture==null,"bound_"+id+"_no_capture")
  _check(scene.input_problem.contains(id),"bound_"+id+"_specific_conflict")
  _released(scene)
  scene.process_input_interval(0)
 # Restore the ordinary preset explicitly while paused, never auto-remap.
 scene.apply_controls(Mapper.default_preset_v2())


func _assert_pre_pause(scene: Node,before: Dictionary,label: String) -> void:
 _check(not scene.pause_entries.is_empty(),label+"_normal_fault_handler_observed")
 if not scene.pause_entries.is_empty():
  _check(scene.pause_entries[0].mapper==before,label+"_all_mapper_intent_fields_unchanged_before_pause")

func _viewport_button(scene: Node,position_value: Vector2,pressed: bool) -> void:
 var event: InputEventMouseButton=InputEventMouseButton.new()
 event.position=position_value;event.global_position=position_value
 event.button_index=MOUSE_BUTTON_LEFT;event.pressed=pressed
 event.button_mask=MOUSE_BUTTON_MASK_LEFT if pressed else 0
 scene._input(event)
 scene.get_viewport().push_input(event,true)

func _device_release_cases(scene: Node) -> void:
 # Exact closed fixture adapted from existing pointer_engine_checks.gd:
 # reversed unsigned hardware at raw1 maps to throttle0; generation pinned7.
 _released(scene)
 _check(scene.pause_session(true),"device_fixture_pause_for_Apply")
 var preset: Dictionary=Mapper.default_preset_v2()
 preset.devices=[{"slot":"lever","label":"Synthetic lever","match":{"guid":"fixture","name":"fixture","vendor_id":"","product_id":""}}]
 for i in preset.axes.size():
  if preset.axes[i].target=="throttle":
   preset.axes[i]={"target":"throttle","kind":"joy_axis","slot":"lever","index":0,"range":"unsigned","minimum":-1.0,"center":0.0,"maximum":1.0,"invert":true,"deadzone":0.0,"saturation":1.0,"gain":1.0,"slew_per_s":0.0}
 var device: Dictionary={"slot":"lever","generation":7,"axes":[{"index":0,"value":1.0}],"buttons":[]}
 scene.release_fixture={"keys":[],"mouse_buttons":[],"devices":[device.duplicate(true)]}
 _released(scene)
 _check(Preset.validate_preset_v2(preset).ok and Preset.validate_raw(scene.synthetic_raw).ok,"device_fixture_uses_existing_closed_shapes")
 scene.apply_controls(preset)
 _check(scene.active_preset==preset,"device_fixture_explicit_Apply")
 for failure in ["generation","disconnect","missing_axis"]:
  if not _resume(scene,"release_device_"+failure): continue
  _begin(scene,"engine.starter")
  scene.process_input_interval(25000)
  _check(_actual_starter(scene),"release_device_"+failure+"_actual_starter_true")
  var before_native: Dictionary=_retained(scene)
  var before_mapper: Dictionary=scene.mapper_intent_snapshot()
  var before_pointer: Dictionary=scene.mapper.pointer_view()
  scene.pause_entries.clear()
  # No GUI up. Complete Raw genuinely reports up but violates required device
  # admission. Host can stage terminal metadata; it cannot commit the release.
  var invalid: Dictionary=scene.release_fixture.duplicate(true)
  # Independent controls would visibly mutate axes, action/latch and system
  # edges if an accepted prefix slipped through before full device admission.
  invalid.keys=[KEY_B,KEY_PERIOD,KEY_LEFT,KEY_F8]
  match failure:
   "generation": invalid.devices[0].generation=8
   "disconnect": invalid.devices=[]
   "missing_axis": invalid.devices[0].axes=[]
  _check(Preset.validate_raw(invalid).ok,"release_device_"+failure+"_Raw_shape_valid")
  scene.synthetic_raw=invalid
  scene.process_input_interval(25000)
  _assert_pre_pause(scene,before_mapper,"release_device_"+failure)
  if not scene.pause_entries.is_empty():
   var fault: Dictionary=scene.pause_entries[0]
   _check(fault.pointer.capture==before_pointer.capture and fault.pointer.generation==before_pointer.generation and fault.pointer.last_token==before_pointer.last_token,"release_device_"+failure+"_capture_not_consumed_before_pause")
   _check(fault.pointer.rearm_buttons==before_pointer.rearm_buttons,"release_device_"+failure+"_invalid_release_does_not_rearm_before_pause")
  _check(scene.paused and _retained(scene)==before_native and _actual_starter(scene),"release_device_"+failure+"_no_false_publication_command_or_Run")
  _check(1 in scene.engine_pointer_rearm and 1 in scene.mapper.pointer_view().rearm_buttons,"release_device_"+failure+"_fault_keeps_release_latch")
  _check(not scene.pause_session(false) and _retained(scene)==before_native and 1 in scene.engine_pointer_rearm,"release_device_"+failure+"_invalid_Raw_up_cannot_resume_or_rearm")
  scene.synthetic_raw=scene.release_fixture.duplicate(true)
  scene.synthetic_raw.mouse_buttons=[1]
  _check(not scene.pause_session(false) and _retained(scene)==before_native,"release_device_"+failure+"_later_valid_held_still_blocks_resume")
  if _resume(scene,"release_device_"+failure+"_valid_release"):
   scene.process_input_interval(25000)
   _check(not _actual_starter(scene) and scene.engine_pointer_rearm.is_empty(),"release_device_"+failure+"_valid_recovery_false_before_Run")
 _released(scene)
 _check(scene.pause_session(true),"device_fixture_restore_paused")
 scene.release_fixture={"keys":[],"mouse_buttons":[],"devices":[]}
 _released(scene)
 scene.apply_controls(Mapper.default_preset_v2())
 _check(scene.active_preset==Mapper.default_preset_v2(),"device_fixture_restore_default_explicit_Apply")

func _retirement_cases(scene: Node) -> void:
 for transition in ["collapse","hide"]:
  if not _resume(scene,"retire_"+transition): continue
  _begin(scene,"engine.starter")
  scene.process_input_interval(25000)
  var before: Dictionary=_retained(scene)
  if transition=="collapse": scene.engine_controls.set_expanded(false)
  else: scene.engine_controls.hide()
  _check(scene.mapper.pointer_view().capture==null and 1 in scene.mapper.pointer_view().rearm_buttons and 1 in scene.engine_pointer_rearm,"retire_"+transition+"_capture_gone_real_release_required")
  _check(_retained(scene)==before and _actual_starter(scene) and not scene.paused,"retire_"+transition+"_no_forged_false_publication_or_pause")
  if transition=="collapse": scene.engine_controls.set_expanded(true)
  else: scene.engine_controls.show()
  scene.show_state()
  _button(scene,"engine.starter",true)
  _check(scene.mapper.pointer_view().capture==null,"retire_"+transition+"_held_reentry_cannot_restart")
  scene.synthetic_raw.mouse_buttons=[]
  _button(scene,"engine.starter",false)
  scene.process_input_interval(25000)
  _check(not _actual_starter(scene) and scene.engine_pointer_rearm.is_empty(),"retire_"+transition+"_ordinary_boundary_releases_and_rearms")

func _ordinary_layout_cases(scene: Node) -> void:
 # Source-supported ordinary layout transitions only; no OS key/mouse claim.
 # The actual window owns the viewport dimensions. All native Run calls below
 # go through the existing full-Raw production host; layout itself gets none.
 var window: Window=scene.get_tree().root
 var original_size: Vector2i=window.size
 var original_mode: int=scene.camera_mode
 var original_gaze: Vector2=scene.look_angles
 for window_size in [Vector2i(960,540),Vector2i(1920,1080),Vector2i(2560,1440)]:
  for mode in [0,3,1]:
   for transition in ["resize","view"]:
    var label: String="ordinary_layout_%dx%d_mode%d_%s"%[window_size.x,window_size.y,mode,transition]
    window.size=window_size
    await scene.get_tree().process_frame
    scene.set_camera_mode(mode)
    if not _resume(scene,label): continue
    scene.show_state()
    await scene.get_tree().process_frame
    _check(Vector2i(scene.get_viewport().get_visible_rect().size)==window_size,label+"_actual_requested_viewport")
    var column: float=clampf(float(window_size.x)/6.0,250.0,360.0)
    var panel: Control=scene.engine_controls
    _check(panel.size==Vector2(column,216) and panel.is_expanded() and panel.visible,label+"_expanded216_source_width")
    var native_before: Dictionary=_retained(scene)
    var raw_before: PackedByteArray=var_to_bytes(scene.synthetic_raw)
    var initial_pointer: Dictionary=scene.mapper.pointer_view()
    var initial_intent: Dictionary=scene.mapper_intent_snapshot()
    for repeat in 3: scene.layout_live_flight_aids()
    _check(_retained(scene)==native_before and scene.mapper.pointer_view()==initial_pointer and scene.mapper_intent_snapshot()==initial_intent and var_to_bytes(scene.synthetic_raw)==raw_before,label+"_idle_layout_no_native_Raw_intent_or_generation_change")
    # Deliberate gaze is a presentation fixture, not admitted simultaneous look
    # input during a pointer drag. Fixed docks must be independent of the gaze.
    var fixed_rect: Rect2=panel.get_rect()
    var prior_gaze: Vector2=scene.look_angles
    for gaze in [Vector2(0.4,-0.2),Vector2(-1.1,0.15),Vector2.ZERO]:
     scene.look_angles=gaze
     scene.layout_live_flight_aids()
     _check(panel.get_rect()==fixed_rect and scene.mapper.pointer_view()==initial_pointer and _retained(scene)==native_before and scene.mapper_intent_snapshot()==initial_intent,label+"_gaze_does_not_remap_or_sample_"+str(gaze))
    scene.look_angles=prior_gaze
    # Unconsumed starter begin proves a passive layout cannot manufacture even
    # one true native starter tick, command, pilot sequence or hidden submission.
    _begin(scene,"engine.starter")
    var captured: Dictionary=scene.mapper.pointer_view()
    var captured_intent: Dictionary=scene.mapper_intent_snapshot()
    var before_rect: Rect2=panel.get_rect()
    var before_log: int=scene.layout_retirements.size()
    _check(captured.capture!=null and not _actual_starter(scene) and _retained(scene)==native_before,label+"_unsampled_capture_has_no_native_pulse")
    for repeat in 3: scene.layout_live_flight_aids()
    scene.look_angles=Vector2(0.3,0.1);scene.layout_live_flight_aids()
    _check(scene.mapper.pointer_view()==captured and panel.get_rect()==before_rect and scene.mapper_intent_snapshot()==captured_intent and _retained(scene)==native_before and scene.layout_retirements.size()==before_log,label+"_active_capture_repeated_and_gaze_layout_inert")
    if transition=="resize":
     window.size=Vector2i(1920,1080) if window_size.x!=1920 else Vector2i(960,540)
     await scene.get_tree().process_frame
    else:
     # These views deliberately change the actual hit mapping. COCKPIT/CHASE
     # same-left-column transitions are tested separately below as idempotent.
     scene.set_camera_mode(0 if mode==3 else 3)
    scene.show_state()
    await scene.get_tree().process_frame
    var retired: Dictionary=scene.mapper.pointer_view()
    _check(panel.get_rect()!=before_rect,label+"_actual_hit_mapping_changed")
    _check(retired.capture==null and retired.generation==captured.generation+1 and scene.layout_retirements.size()==before_log+1,label+"_capture_retired_exactly_once")
    if scene.layout_retirements.size()==before_log+1:
     var observed: Dictionary=scene.layout_retirements[-1]
     _check(observed.rect==before_rect and observed.pointer==captured and observed.raw.mouse_buttons==[1],label+"_retirement_observed_before_geometry_and_real_release")
    _check(1 in retired.rearm_buttons and 1 in scene.engine_pointer_rearm and panel._capture.is_empty(),label+"_retirement_requires_actual_left_release")
    _check(_retained(scene)==native_before and not _actual_starter(scene) and not scene.paused and scene.synthetic_raw.mouse_buttons==[1],label+"_passive_transition_no_starter_pulse_or_submission_Run")
    for repeat in 3: scene.layout_live_flight_aids()
    _check(scene.mapper.pointer_view()==retired and scene.layout_retirements.size()==before_log+1 and _retained(scene)==native_before,label+"_post_retirement_identical_layout_inert")
    # A GUI up by itself is not full Raw release and cannot clear either latch.
    _button(scene,"engine.starter",false)
    scene.process_input_interval(0)
    _button(scene,"engine.starter",true)
    _check(scene.mapper.pointer_view().capture==null and 1 in scene.mapper.pointer_view().rearm_buttons and 1 in scene.engine_pointer_rearm and _retained(scene)==native_before and not _actual_starter(scene),label+"_GUI_up_and_held_reentry_cannot_rearm_or_pulse")
    # Only ordinary successful complete Raw-up observation rearms. No elapsed
    # time or GUI release is needed to invent a solver boundary here.
    _released(scene)
    scene.process_input_interval(0)
    _check(scene.mapper.pointer_view().rearm_buttons.is_empty() and scene.engine_pointer_rearm.is_empty() and scene.pointer_ui_eligible() and _retained(scene)==native_before,label+"_real_Raw_up_rearms_without_native_advance")
    scene.show_state()
    var fresh_before: Dictionary=scene.mapper.pointer_view()
    _begin(scene,"engine.starter")
    var fresh: Dictionary=scene.mapper.pointer_view()
    _check(fresh.capture!=null and fresh.generation==fresh_before.generation and fresh.capture.token==fresh_before.last_token+1,label+"_fresh_real_press_after_release")
    scene.process_input_interval(25000)
    _check(_actual_starter(scene) and scene.facade.readback().tick!=native_before.tick,label+"_ordinary_due_Run_applies_fresh_starter")
    var commands: Array=scene.facade.get("_commands").duplicate(true)
    _check(commands.size()==1 and commands[0].payload=={"kind":"system","control_id":"engine.starter","value":true},label+"_one_ordinary_true_command_only")
    _released(scene);_button(scene,"engine.starter",false)
    scene.process_input_interval(25000)
    commands=scene.facade.get("_commands").duplicate(true)
    _check(not _actual_starter(scene) and commands.size()==1 and commands[0].payload=={"kind":"system","control_id":"engine.starter","value":false},label+"_ordinary_release_one_false_command")
 # View name alone does not justify retirement if the hit mapping stays exact.
 window.size=Vector2i(960,540)
 await scene.get_tree().process_frame
 scene.set_camera_mode(0)
 if _resume(scene,"ordinary_layout_same_column"):
  scene.show_state()
  _begin(scene,"engine.starter")
  var same_column_pointer: Dictionary=scene.mapper.pointer_view()
  var same_column_rect: Rect2=scene.engine_controls.get_rect()
  var same_column_native: Dictionary=_retained(scene)
  var same_column_logs: int=scene.layout_retirements.size()
  scene.set_camera_mode(1);scene.show_state()
  _check(scene.engine_controls.get_rect()==same_column_rect and scene.mapper.pointer_view()==same_column_pointer and scene.layout_retirements.size()==same_column_logs and _retained(scene)==same_column_native,"ordinary_layout_same_hit_mapping_view_keeps_capture_no_generation")
  _released(scene);scene.process_input_interval(25000)
  _check(not _actual_starter(scene),"ordinary_layout_same_mapping_Raw_up_before_sample_no_true_pulse")
 window.size=original_size
 await scene.get_tree().process_frame
 scene.set_camera_mode(original_mode);scene.look_angles=original_gaze
 scene.show_state()
 _check(window.size==original_size,"ordinary_layout_original_viewport_restored")

func _assert_modal_motion_blocked(scene: Node,label: String) -> void:
 var before: Vector2=scene.look_angles
 var motion: InputEventMouseMotion=InputEventMouseMotion.new()
 motion.relative=Vector2(8,-5)
 Input.mouse_mode=Input.MOUSE_MODE_CAPTURED
 scene._unhandled_input(motion)
 _check(scene.look_angles==before and not scene.engine_pointer_look_active,label+"_modal_blocks_look_motion")
 Input.mouse_mode=Input.MOUSE_MODE_VISIBLE

func _modal_cases(scene: Node) -> void:
 for kind in ["menu","route","review"]:
  if not _resume(scene,"modal_"+kind): continue
  _begin(scene,"engine.starter")
  scene.process_input_interval(25000)
  var before: Dictionary=_retained(scene)
  match kind:
   "menu": scene.open_menu("Pointer modal fixture")
   "route": scene.open_landmark_route()
   "review": scene.open_observed_review()
  scene.show_state()
  _check(scene.menu_open and scene.paused and not scene.pointer_ui_eligible() and not scene.engine_controls.visible,"modal_"+kind+"_actual_modal_owner_hides_strip")
  if kind=="review": _check(scene.review_open,"modal_review_actual_open")
  _check(_retained(scene)==before and scene.mapper.pointer_view().capture==null and _actual_starter(scene),"modal_"+kind+"_retirement_preserves_native_actual_true")
  _assert_modal_motion_blocked(scene,"modal_"+kind)
  _button(scene,"engine.starter",true)
  scene.process_input_interval(0)
  _check(scene.mapper.pointer_view().capture==null and _retained(scene)==before,"modal_"+kind+"_GUI_and_diagnostics_no_live_capture_or_Run")
  if kind=="review":
   var prior_recent: PackedStringArray=FileDialog.get_recent_list()
   _check(scene.begin_archive_operation("open",false),"modal_archive_actual_open_without_dialog_or_file_IO")
   var archive_before: Dictionary=_retained(scene)
   _button(scene,"engine.starter",true)
   scene.process_input_interval(25000)
   _check(not scene.archive_operation.is_empty() and _retained(scene)==archive_before and scene.mapper.pointer_view().capture==null,"modal_archive_no_input_prefix_or_Run")
   _assert_modal_motion_blocked(scene,"modal_archive")
   scene.cancel_archive_operation()
   _check(scene.archive_operation.is_empty() and FileDialog.get_recent_list()==prior_recent,"modal_archive_cancel_restores_prior_chooser_state")
   scene.dismiss_observed_review()
  elif kind=="route": scene.dismiss_landmark_route()
 # Wind and scan intentionally require an already paused boundary. A denied
 # live request must not retire a legitimate capture or change the session.
 for kind in ["wind","scan"]:
  if not _resume(scene,"modal_"+kind): continue
  _begin(scene,"engine.starter")
  scene.process_input_interval(25000)
  var before: Dictionary=_retained(scene)
  var capture: Dictionary=scene.mapper.pointer_view()
  if kind=="wind": scene.open_wind()
  else: scene.open_instrument_scan()
  _check(scene.mapper.pointer_view()==capture and _retained(scene)==before and not scene.paused,"modal_"+kind+"_denied_live_request_keeps_capture")
  _check(scene.pause_session(true),"modal_"+kind+"_explicit_pause")
  if kind=="wind": scene.open_wind()
  else: scene.open_instrument_scan()
  scene.show_state()
  _check((scene.wind_panel.visible if kind=="wind" else scene.scan_open) and not scene.pointer_ui_eligible() and not scene.engine_controls.visible,"modal_"+kind+"_actual_paused_owner")
  _check(_retained(scene)==before and _actual_starter(scene),"modal_"+kind+"_paused_starter_actual_preserved")
  _assert_modal_motion_blocked(scene,"modal_"+kind)
  if kind=="wind": scene.dismiss_wind()
  else: scene.dismiss_instrument_scan()

func _outside_and_lifecycle_cases(scene: Node) -> void:
 _released(scene)
 _check(scene.pause_session(true),"outside_bind_pause")
 var preset: Dictionary=Mapper.default_preset_v2()
 for action in preset.actions:
  if action.id=="view_cycle": action.sources=[{"kind":"mouse_button","button":1}]
 scene.apply_controls(preset)
 if _resume(scene,"outside_bound"):
  var camera: int=scene.camera_mode
  scene.synthetic_raw.mouse_buttons=[1]
  _viewport_button(scene,Vector2(3,3),true)
  scene.process_input_interval(0)
  _check(not scene.paused and scene.camera_mode==(camera+1)%4 and scene.mapper.pointer_view().capture==null,"outside_engine_hit_region_keeps_physical_view_action")
  scene.process_input_interval(0)
  _check(scene.camera_mode==(camera+1)%4,"outside_held_physical_view_action_no_repeat")
  _released(scene);_viewport_button(scene,Vector2(3,3),false);scene.process_input_interval(0)
  scene.synthetic_raw.mouse_buttons=[2];scene.process_input_interval(0)
  camera=scene.camera_mode
  scene.synthetic_raw.mouse_buttons=[1,2]
  _button(scene,"engine.starter",true)
  scene.process_input_interval(0)
  _check(not scene.paused and scene.engine_pointer_look_active and scene.camera_mode==(camera+1)%4 and scene.mapper.pointer_view().capture==null,"look_noninteractive_region_keeps_physical_view_action")
  _released(scene);_button(scene,"engine.starter",false);scene.process_input_interval(0)
 _released(scene)
 _check(scene.pause_session(true),"outside_restore_pause")
 scene.apply_controls(Mapper.default_preset_v2())
 if _resume(scene,"invalid_selection"):
  _begin(scene,"engine.starter")
  var before: Dictionary=_retained(scene)
  var pointer: Dictionary=scene.mapper.pointer_view()
  _check(not scene.restart(true,"calm","not-an-approved-profile","piston-cold-ground"),"invalid_profile_selection_rejected")
  _check(_retained(scene)==before and scene.mapper.pointer_view()==pointer and not scene.paused,"invalid_profile_selection_keeps_current_capture_and_native")
  scene.synthetic_raw.mouse_buttons=[];scene.process_input_interval(0)
 if _resume(scene,"same_interval_restart"):
  _begin(scene,"engine.starter")
  var old_facade: RefCounted=scene.facade
  var old_session: String=scene.adopted_session_id
  # Pointer true is sampled locally, but the ordinary restart action replaces
  # its session before submission. Raw remains held across the new mapper.
  scene.synthetic_raw.keys=[KEY_R]
  scene.process_input_interval(25000)
  _check(scene.facade!=old_facade and scene.adopted_session_id!=old_session,"same_interval_restart_actual_facade_and_session_changed")
  _check(scene.facade.readback().tick=="0" and scene.paused and not _actual_starter(scene) and scene.submitted_count==0,"same_interval_restart_no_old_intent_or_Run_in_new_session")
  _check(scene.mapper.pointer_view().capture==null and 1 in scene.engine_pointer_rearm,"same_interval_restart_retires_old_capture_keeps_held_rearm")
  _check(not scene.pause_session(false) and scene.facade.readback().tick=="0","same_interval_restart_held_pointer_cannot_implicitly_resume")

func _legacy_modal_cases(scene: Node) -> void:
 _released(scene)
 _check(scene.restart(true,"calm",Facade.LEGACY_PROFILE.id,"ground-ready"),"legacy_explicit_profile_adoption")
 scene.menu_open=false;scene.menu.hide();scene.show_state()
 _check(not scene.engine_controls.visible and not scene.pointer_ui_eligible(),"legacy_profile_has_no_interactive_engine_strip")
 var preset: Dictionary=Mapper.default_preset()
 for action in preset.actions:
  if action.id=="view_cycle": action.sources=[{"kind":"mouse_button","button":1}]
 scene.apply_controls(preset)
 _released(scene)
 var resumed: bool=scene.pause_session(false)
 _check(resumed,"legacy_explicit_resume")
 if not resumed: return
 scene.menu_open=false;scene.menu.hide();scene.show_state()
 var camera: int=scene.camera_mode
 scene.synthetic_raw.mouse_buttons=[1]
 _button(scene,"engine.starter",true)
 scene.process_input_interval(0)
 _check(not scene.paused and scene.camera_mode==(camera+1)%4 and scene.mapper.pointer_view().capture==null,"legacy_hidden_region_keeps_physical_view_action")
 _released(scene);_button(scene,"engine.starter",false)
 scene.process_input_interval(25000)
 _check(scene.recorded_flight_advanced(),"legacy_actual_observed_record_advanced")
 var before: Dictionary=_retained(scene)
 scene.request_discard("restart","ground-ready","calm",Facade.LEGACY_PROFILE.id)
 scene.show_state()
 _check(not scene.pending_discard.is_empty() and scene.discard_layer.visible and scene.paused and not scene.pointer_ui_eligible(),"legacy_discard_actual_confirmation_owner")
 _check(_retained(scene)==before,"legacy_discard_no_session_replacement_or_Run_before_confirmation")
 _assert_modal_motion_blocked(scene,"legacy_discard")
 scene.cancel_discard()
 _check(scene.pending_discard.is_empty() and _retained(scene)==before and scene.paused,"legacy_discard_cancel_preserves_current_flight")

func run(host: Node) -> Dictionary:
 _host=host
 var original_mouse_mode: int=Input.mouse_mode
 var scene: Node=SyntheticScene.new()
 host.add_child(scene)
 scene.set_process(false);scene.set_process_input(false)
 scene.set_process_unhandled_input(false);scene.set_process_unhandled_key_input(false)
 if scene.sound!=null: scene.sound.set_process(false)
 var initialized: bool=scene.facade!=null and scene.facade.readback().aircraft!=null
 _check(initialized,"actual_legacy_initialization")
 if initialized:
  _check(scene.restart(true,"calm","original-piston-prop-v1","piston-cold-ground"),"explicit_actual_cold_adoption")
  initialized=scene.facade!=null and scene.facade.readback().model_identity==Facade.PISTON_PROFILE and scene.engine_controls!=null
 _check(initialized,"actual_cold_identity_and_widget")
 if initialized:
  _check(scene.facade.readback().tick=="0" and scene.facade.readback().paused,"cold_starts_paused_tick_zero")
  _check(scene.mapper.pointer_view().session_id==scene.facade.readback().session_id,"bind_uses_new_facade_not_old_adopted_id")
  await host.get_tree().process_frame
  _bound_cases(scene)
  if _resume(scene,"unbound"):
   # Genuine GUI terminal must retain its final value rather than Raw-up cancel.
   _begin(scene,"mixture",0.75)
   # Observe the panel's actual normalized terminal value, independently of
   # native truth. Exact request-to-native equality uses that GUI event value.
   var terminals: Array[Dictionary]=[]
   var observe_terminal: Callable=func(g: Dictionary):
    if g.phase=="end": terminals.append(g.duplicate(true))
   scene.engine_controls.gesture_requested.connect(observe_terminal)
   scene.synthetic_raw.mouse_buttons=[]
   _button(scene,"mixture",false,0.75)
   scene.engine_controls.gesture_requested.disconnect(observe_terminal)
   _check(terminals.size()==1 and terminals[0].value is float,"real_GUI_terminal_value_observed")
   var terminal_value: float=float(terminals[0].value) if terminals.size()==1 else -1.0
   scene.process_input_interval(25000)
   _check(scene.mapper.pointer_view().capture==null,"genuine_end_consumed")
   _check(scene.mapper.pointer_view().requested_axes.mixture==terminal_value,"genuine_end_final_value_not_canceled")
   _check(scene.facade.readback().held_axes.mixture==terminal_value,"ordinary_full_intent_reaches_native")
   # Missing GUI up is independently observed Raw, not a fabricated GUI event.
   _begin(scene,"engine.starter")
   scene.process_input_interval(25000)
   _check(_actual_starter(scene),"pointer_starter_actual_true_after_due_tick")
   var start_commands: Array=scene.facade.get("_commands").duplicate(true)
   _check(start_commands.size()==1 and start_commands[0].payload=={"kind":"system","control_id":"engine.starter","value":true},"starter_no_duplicate_axes_or_other_system_commands")
   for command in start_commands:
    _check(command.session_id==scene.adopted_session_id and command.source_id=="pilot.controls" and command.authority=="pilot" and command.assistance=={"profile_id":"unassisted","active":[]},"ordinary_native_command_identity_and_no_assist")
   scene.synthetic_raw.mouse_buttons=[]
   scene.process_input_interval(25000)
   _check(not _actual_starter(scene) and scene.mapper.pointer_view().capture==null,"missing_GUI_up_releases_before_Run")
   var release_commands: Array=scene.facade.get("_commands").duplicate(true)
   _check(release_commands.size()==1 and release_commands[0].payload=={"kind":"system","control_id":"engine.starter","value":false},"release_exactly_one_ordinary_starter_false")
   _check(scene.mapper.pointer_view().rearm_buttons.is_empty(),"valid_Raw_up_rearms")
   var after_release: Dictionary=_retained(scene)
   _button(scene,"engine.starter",false)
   _check(_retained(scene)==after_release and not scene.paused,"late_GUI_up_is_inert")
   # Missing GUI terminal before first sample cannot create a true starter tick.
   _begin(scene,"engine.starter")
   scene.synthetic_raw.mouse_buttons=[]
   scene.process_input_interval(25000)
   _check(not _actual_starter(scene),"down_and_Raw_up_before_boundary_no_true_pulse")
   # Look release must expose pointer without a presentation reset.
   var camera: int=scene.camera_mode
   var angles: Vector2=Vector2(0.2,-0.1)
   scene.look_angles=angles
   # Backend capture by itself never grants application look ownership.
   Input.mouse_mode=Input.MOUSE_MODE_CAPTURED
   if DisplayServer.get_name()!="headless":
    _check(Input.mouse_mode==Input.MOUSE_MODE_CAPTURED,"unadmitted_motion_actual_backend_capture")
   var motion: InputEventMouseMotion=InputEventMouseMotion.new()
   motion.relative=Vector2(5,-4)
   scene._unhandled_input(motion)
   _check(not scene.engine_pointer_look_active and scene.look_angles==angles,"backend_capture_alone_cannot_rotate_look")
   Input.mouse_mode=Input.MOUSE_MODE_VISIBLE
   scene.synthetic_raw.mouse_buttons=[2]
   scene.process_input_interval(0)
   _check(scene.engine_pointer_look_active and not scene.pointer_ui_eligible(),"ordinary_look_owns_input_and_disables_strip")
   # Headless DisplayServer has no mouse and ignores CAPTURED requests. This
   # checks application ownership there; actual Windows runs MUST also prove
   # backend capture, and the receipt separately reports whether it was seen.
   if DisplayServer.get_name()=="headless":
    _check(not DisplayServer.has_feature(DisplayServer.FEATURE_MOUSE) and Input.mouse_mode==Input.MOUSE_MODE_VISIBLE,"headless_no_physical_mouse_capture_observed")
   else:
    _check(Input.mouse_mode==Input.MOUSE_MODE_CAPTURED,"ordinary_look_actual_backend_captured")
   scene._unhandled_input(motion)
   if DisplayServer.get_name()=="headless":
    _check(scene.look_angles==angles,"headless_no_physical_captured_motion_observed")
   else:
    _check(scene.look_angles==Vector2(angles.x-0.02,angles.y+0.016),"admitted_look_actual_motion_rotates_angles")
   angles=scene.look_angles
   var before_look_click: Dictionary=_retained(scene)
   scene.synthetic_raw.mouse_buttons=[1,2]
   _button(scene,"engine.starter",true)
   _check(scene.mapper.pointer_view().capture==null and not scene.paused,"look_owner_GUI_press_cannot_acquire_engine_capture")
   _check(_retained(scene)==before_look_click,"look_owner_GUI_press_no_command_or_tick")
   scene.synthetic_raw.mouse_buttons=[2]
   _button(scene,"engine.starter",false)
   scene.synthetic_raw.mouse_buttons=[]
   scene.process_input_interval(0)
   _check(not scene.engine_pointer_look_active and Input.mouse_mode==Input.MOUSE_MODE_VISIBLE and scene.camera_mode==camera and scene.look_angles==angles,"look_release_exposes_without_camera_reset")
   scene.show_state()
   _begin(scene,"throttle",0.25)
   var before_look: Dictionary=_retained(scene)
   var before_look_mapper: Dictionary=scene.mapper_intent_snapshot()
   scene.pause_entries.clear()
   scene.synthetic_raw.mouse_buttons=[1,2]
   scene.process_input_interval(25000)
   _assert_pre_pause(scene,before_look_mapper,"look_conflict")
   _check(scene.paused and not scene.engine_pointer_look_active and _retained(scene)==before_look and Input.mouse_mode==Input.MOUSE_MODE_VISIBLE,"look_during_capture_pauses_before_intent_Run_or_recapture")
  if _resume(scene,"pause_starter"):
   var old_terminal: Dictionary=_begin(scene,"engine.starter")
   scene.process_input_interval(25000)
   _check(_actual_starter(scene),"starter_true_before_pause")
   _check(scene.pause_session(true),"explicit_pause_with_pointer_held")
   _check(_actual_starter(scene) and scene.pending_systems["engine.starter"]==false,"paused_actual_true_local_false_truth")
   var paused_before: Dictionary=_retained(scene)
   _check(not scene.pause_session(false) and _retained(scene)==paused_before,"held_pointer_blocks_resume_no_native_change")
   scene.apply_controls(scene.active_preset.duplicate(true))
   _check(scene.mapper.pointer_view().capture==null and scene.mapper.pointer_view().session_id==scene.facade.readback().session_id,"same_session_Apply_rebinds_without_capture")
   _check(1 in scene.mapper.pointer_view().rearm_buttons and not scene.pause_session(false),"same_session_Apply_cannot_rearm_still_held_pointer")
   _released(scene)
   if _resume(scene,"recover"):
    scene.process_input_interval(25000)
    _check(not _actual_starter(scene),"resume_release_completed_before_first_Run")
    _begin(scene,"engine.starter")
    var newer: Dictionary=scene.mapper.pointer_view()
    var retired_widget: Control=Control.new()
    scene.on_engine_retired("Old widget callback",retired_widget)
    _check(scene.mapper.pointer_view()==newer,"old_widget_cannot_retire_current_capture")
    retired_widget.free()
    scene.on_engine_gesture(old_terminal,scene.engine_controls)
    _check(scene.mapper.pointer_view()==newer and not scene.paused,"obsolete_terminal_cannot_retire_new_capture")
    scene.process_input_interval(25000)
    var before_focus: Dictionary=_retained(scene)
    scene.on_focus_lost()
    _check(scene.paused and _retained(scene)==before_focus and scene.mapper.pointer_view().capture==null,"focus_retires_without_command_or_tick")
    _check(_actual_starter(scene),"focus_does_not_forge_false_native_publication")
    _released(scene)
    if _resume(scene,"reset"):
     var reset_terminal: Dictionary=_begin(scene,"engine.starter")
     var prior_session: String=scene.facade.readback().session_id
     # Raw stays physically held across creation of a genuinely new mapper.
     _check(scene.restart(true),"explicit_reset_joins_old_session")
     var fresh: Dictionary=scene.mapper.pointer_view()
     _check(fresh.session_id!=prior_session and fresh.capture==null and scene.facade.readback().tick=="0" and scene.paused,"reset_new_bound_identity_paused_tick_zero")
     var reset_before: Dictionary=_retained(scene)
     _check(not scene.pause_session(false) and _retained(scene)==reset_before,"fresh_mapper_cannot_lose_held_pointer_rearm")
     scene.on_engine_gesture(reset_terminal,scene.engine_controls)
     _check(scene.mapper.pointer_view()==fresh and _retained(scene)==reset_before,"old_session_terminal_inert_after_reset")
     # A superficially released button inside malformed complete Raw cannot
     # clear the host latch or silently resume the new worker.
     scene.synthetic_raw={"keys":[],"mouse_buttons":[],"devices":[{"slot":"malformed-release"}]}
     _check(not scene.pause_session(false) and _retained(scene)==reset_before,"malformed_release_cannot_rearm_fresh_session")
     scene.synthetic_raw={"keys":[],"mouse_buttons":[1],"devices":[]}
     _check(not scene.pause_session(false) and _retained(scene)==reset_before,"held_recheck_after_malformed_release_still_blocked")
     if _resume(scene,"restart_observed_valid_release"):
      _begin(scene,"engine.starter")
      var new_capture: Dictionary=scene.mapper.pointer_view()
      scene.on_engine_gesture(reset_terminal,scene.engine_controls)
      _check(scene.mapper.pointer_view()==new_capture and not scene.paused,"old_reset_terminal_cannot_retire_new_session_capture")
      _released(scene)
      scene.process_input_interval(25000)
      _check(not _actual_starter(scene),"new_capture_Raw_up_before_boundary_has_no_true_pulse")
  if _resume(scene,"controls_modal"):
   _begin(scene,"engine.starter")
   scene.process_input_interval(25000)
   var before_modal: Dictionary=_retained(scene)
   scene.open_controls()
   _check(scene.controls_panel.visible and scene.paused and not scene.pointer_ui_eligible(),"Controls_owns_modal_no_live_pointer")
   _check(_retained(scene)==before_modal and scene.mapper.pointer_view().capture==null,"Controls_retires_capture_without_native_advance")
   _check(_actual_starter(scene),"Controls_keeps_actual_paused_starter_truth")
   _check(1 in scene.mapper.pointer_view().rearm_buttons,"Controls_requires_actual_button_release")
   scene.dismiss_controls()
  # A malformed complete Raw cannot be interpreted as release recovery.
  if _resume(scene,"malformed"):
   _begin(scene,"engine.starter")
   var before_bad: Dictionary=_retained(scene)
   var before_bad_mapper: Dictionary=scene.mapper_intent_snapshot()
   scene.pause_entries.clear()
   scene.synthetic_raw={"keys":[],"mouse_buttons":[1,1],"devices":[]}
   scene.process_input_interval(25000)
   _assert_pre_pause(scene,before_bad_mapper,"malformed_Raw")
   _check(scene.paused and _retained(scene)==before_bad,"malformed_Raw_no_release_intent_or_Run")
   _check(scene.mapper.pointer_view().capture==null,"normal_fault_pause_retires_capture")
  _device_release_cases(scene)
  _retirement_cases(scene)
  await _ordinary_layout_cases(scene)
  _modal_cases(scene)
  _outside_and_lifecycle_cases(scene)
  _legacy_modal_cases(scene)
 var joined: bool=scene.close_session()
 _check(joined,"actual_worker_joined")
 if scene.sound!=null: _check(bool(await scene.sound.shutdown()),"actual_audio_retired")
 scene.free()
 Input.mouse_mode=original_mouse_mode
 return {"passed":_failures.is_empty(),"checks":_checks,"failures":_failures.duplicate(),
  "physical_capture_observed":DisplayServer.get_name()!="headless",
  "display_backend":DisplayServer.get_name(),
  "scope":"Actual qualified cold native/production host, viewport GUI and separate synthetic Raw; strict backend capture assertion on nonheadless runs; headless proves logical ownership only; no OS hardware, pilot or new physics-performance qualification"}
