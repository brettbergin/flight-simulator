extends RefCounted
# Original MIT. Pointer-operated frontend lifecycle over the qualified model.
# Real production scene/native facade + Viewport GUI; separately supplied Raw.
const Scene=preload("res://simulation/flight_scene.gd")
const Facade=preload("res://simulation/session_facade.gd")
const Mapper=preload("res://input/input_mapper.gd")
const Status=preload("res://cockpit/instruments/engine_status.gd")
const U64=preload("res://simulation/uint64.gd")
const LIMITS_PATH: String="res://pointer_scene_tests/native-limits.json"
const LIMITS_SHA: String="9b667d4b61e47e94af1eed20701119bd72d6de63e6eac28b8597ab44ae6d9feb"
var _host: Node
var _scene: Node
var _checks: int=0
var _failures: Array[String]=[]
var _rows: Array[Dictionary]=[]
var _gestures: Array[Dictionary]=[]
var _lever_values: Array[Dictionary]=[]
var _intended_axes: Dictionary={"throttle":0.0,"mixture":0.0}
var _denied: Array[Dictionary]=[]
var _sequence: String="0"
var _admitted_axes: Dictionary={}
var _admitted_systems: Dictionary={}
var _source: Dictionary={}
var _last_fuel: float=100.0
var _first_running: int=-1
var _first_stopped: int=-1
var _taxi_start: Dictionary={}
var _max_taxi_speed: float=0.0
var _max_crank_shaft: float=0.0

class SyntheticScene extends Scene:
 var synthetic_raw: Dictionary={"keys":[],"mouse_buttons":[],"devices":[]}
 func collect_input_raw(_preset: Dictionary={}) -> Dictionary:
  return synthetic_raw.duplicate(true)

func _check(ok: bool,label: String) -> bool:
 _checks+=1
 if not ok: _failures.append(label)
 _host.check(ok,"pointer_flight_"+label)
 return ok

func _actual(id: String) -> Variant:
 var channel: Dictionary=Status.from_readback(_scene.facade.readback()).readings[id]
 _check(channel.valid,"valid_actual_"+id+"_"+str(_rows.size()))
 return channel.value

func _retained() -> Dictionary:
 var value: Dictionary=_scene.facade.readback()
 return {"session":value.session_id,"tick":value.tick,"aircraft":value.aircraft,
  "atmosphere":value.atmosphere,"axes":value.held_axes,"debt":value.debt_quanta,
  "model":value.model_identity,"source":value.native_source_fingerprint,
  "world":value.world_anchor,"prepared":value.prepared_world_sha256,
  "sequence":_scene.facade.get("_command_sequence"),
  "queued":_scene.facade.get("_pending_commands").duplicate(true),
  "submitted":_scene.submitted_count}

func _button(control: String,pressed: bool,fraction: float=-1.0) -> void:
 var point: Vector2=_scene.engine_controls._rects()[control].get_center()
 if fraction>=0.0:
  var track: Rect2=_scene.engine_controls._track(control)
  point=Vector2(track.position.x+track.size.x*fraction,track.get_center().y)
 var event: InputEventMouseButton=InputEventMouseButton.new()
 event.position=_scene.engine_controls.get_global_transform_with_canvas()*point
 event.global_position=event.position;event.button_index=MOUSE_BUTTON_LEFT
 event.pressed=pressed;event.button_mask=MOUSE_BUTTON_MASK_LEFT if pressed else 0
 _scene._input(event)
 _scene.get_viewport().push_input(event,true)

func _sample_zero(label: String) -> bool:
 var before: Dictionary=_retained()
 _scene.process_input_interval(0)
 return _check(not _scene.paused and _retained()==before,label+"_sample0_no_command_Run_or_publication")

func _press(control: String,fraction: float=-1.0) -> bool:
 var before: Dictionary=_retained()
 var prior: Dictionary=_scene.mapper.pointer_view()
 _scene.synthetic_raw.mouse_buttons=[1]
 _button(control,true,fraction)
 var next: Dictionary=_scene.mapper.pointer_view()
 if not _check(next.capture!=null and next.capture.control==control,"real_GUI_begin_"+control): return false
 _check(_retained()==before and next.requested_axes==prior.requested_axes and next.requested_systems==prior.requested_systems,"GUI_unsampled_does_not_become_requested_or_actual_"+control)
 var request_before: Variant=prior.requested_axes[control] if control in ["throttle","mixture"] else prior.requested_systems[control]
 var emitted: Dictionary=_gestures.back()
 if emitted.value!=request_before:
  _check(_scene.engine_controls.get("_preview")==emitted.value,"distinct_local_unsampled_preview_"+control)
 return true

func _release(control: String,fraction: float=-1.0) -> bool:
 _scene.synthetic_raw.mouse_buttons=[]
 _button(control,false,fraction)
 if not _sample_zero("real_GUI_up_"+control): return false
 return _check(_scene.mapper.pointer_view().capture==null,"terminal_consumed_"+control)

func _lever(control: String,fraction: float) -> bool:
 var count: int=_gestures.size()
 if not _press(control,fraction) or not _release(control,fraction): return false
 var terminal: Dictionary=_gestures.back()
 var observed: Variant=_scene.mapper.pointer_view().requested_axes[control]
 _check(_gestures.size()==count+2 and terminal.phase=="end" and terminal.value is float,"lever_exact_real_GUI_begin_end_"+control)
 _check(observed==terminal.value,"sampled_requested_exact_GUI_terminal_"+control)
 # GUI normalized arithmetic uses Vector2 coordinates. Preserve its exact value
 # in evidence; never snap it to a physics oracle or add a tolerance here.
 _lever_values.append({"control":control,"gesture_index":_gestures.size()-1,"intended_schedule_fraction":fraction,"exact_GUI_value":terminal.value})
 _intended_axes[control]=fraction
 return true

func _switch(control: String,desired: bool) -> bool:
 if _scene.mapper.pointer_view().requested_systems[control]==desired: return true
 if not _press(control) or not _release(control): return false
 return _check(_scene.mapper.pointer_view().requested_systems[control]==desired,"desired_switch_sampled_"+control)

func _brake_hold(desired: bool) -> bool:
 if _scene.brake_hold==desired: return true
 _scene.synthetic_raw.keys=[KEY_B]
 if not _sample_zero("physical_brake_hold_press"): return false
 _scene.synthetic_raw.keys=[]
 if not _sample_zero("physical_brake_hold_release"): return false
 return _check(_scene.brake_hold==desired,"ordinary_physical_brake_hold_latch")

func _phase(phase: Dictionary) -> bool:
 _check(int(_scene.facade.readback().tick)==int(phase.at_elapsed_s)*120,"phase_exact_prior_completed_tick_"+phase.phase)
 if phase.phase=="mixture-cutoff":
  var state: Dictionary=_scene.facade.readback()
  var status: Dictionary=Status.from_readback(state)
  if not _check(status.readings["engine.running"].value==true and float(status.readings["propeller.angular_speed"].value)>0.0 and status.readings["engine.starter"].value==false and status.readings["fuel.feed"].value==true and state.held_axes.mixture==1.0,"fail_before_cutoff_if_public_combustion_precondition_missing"): return false
 if phase.phase=="starter-release":
  if not _release("engine.starter"): return false
 # The frozen schedule has no other gesture while momentary starter is held.
 for control in ["throttle","mixture"]:
  var wanted: float=float(phase.axes[control])
  if _intended_axes[control]!=wanted:
   if not _lever(control,wanted): return false
 for control in ["engine.ignition_left","engine.ignition_right","fuel.feed"]:
  if not _switch(control,phase.systems[control]): return false
 if not _brake_hold(float(phase.axes.left_brake)==1.0): return false
 if phase.phase=="deliberate-crank":
  if not _press("engine.starter") or not _sample_zero("starter_requested_true_before_due_boundary"): return false
 return true

func _speed(aircraft: Dictionary) -> float:
 var value: Dictionary=aircraft.velocity_body_mps
 return sqrt(float(value.x)*float(value.x)+float(value.y)*float(value.y)+float(value.z)*float(value.z))

func _commands(next_tick: int,axes: Dictionary,systems: Dictionary) -> Array:
 var payloads: Array=[]
 if axes!=_admitted_axes: payloads.append(axes.duplicate(true))
 for id in Facade.SYSTEM_IDS:
  if systems[id]!=_admitted_systems[id]: payloads.append({"kind":"system","control_id":id,"value":systems[id]})
 var expected: Array=[]
 for payload in payloads:
  var increment: Dictionary=U64.increment(_sequence)
  _check(increment.ok,"bounded_sequence_increment")
  _sequence=increment.value
  # Native publications are JSON-decoded: exact integral schema version is float1.0.
  # Match accepted pacing oracle; retain strict full dictionary/array equality.
  expected.append({"type":"ControlCommand","schema_version":1.0,"tick":str(next_tick),
   "session_id":_source.session_id,"sequence":_sequence,"source_id":"pilot.controls",
   "authority":"pilot","assistance":{"profile_id":"unassisted","active":[]},"payload":payload})
 _admitted_axes=axes.duplicate(true);_admitted_systems=systems.duplicate(true)
 return expected

func _step(next_tick: int,targets: Dictionary) -> bool:
 var requested: Dictionary=_scene.mapper.pointer_view()
 var axes: Dictionary=requested.requested_axes.duplicate(true)
 var systems: Dictionary=requested.requested_systems.duplicate(true)
 # Brake override is applied to full outgoing axes, while pointer_view describes
 # mapper lever intent. Existing fixed brake bases remain zero in that view.
 axes.left_brake=1.0 if _scene.brake_hold else 0.0
 axes.right_brake=axes.left_brake
 var expected: Array=_commands(next_tick,axes,systems)
 # Exact three-interval1/120s cadence. First interval rounds upward so each
 # callback completes exactly one tick; debt320,160,0 is not discarded/clamped.
 var elapsed: int=8334 if next_tick%3==1 else 8333
 _scene.process_input_interval(elapsed)
 var state: Dictionary=_scene.facade.readback()
 if not _check(not _scene.paused and state.native_live and state.host_mode=="live" and int(state.tick)==next_tick,"one_actual_native_tick_"+str(next_tick)): return false
 var actual_commands: Array=_scene.facade.get("_commands").duplicate(true)
 _check(actual_commands==expected,"complete_exact_command_identity_order_"+str(next_tick))
 _check(state.held_axes==axes and Status.held_systems_from_readback(state).value==systems,"actual_complete_held_intent_"+str(next_tick))
 _check(state.session_id==_source.session_id and state.native_source_fingerprint==_source.native_source_fingerprint and state.model_identity==Facade.PISTON_PROFILE and state.prepared_world_sha256==_source.prepared_world_sha256,"native_identity_"+str(next_tick))
 _check(next_tick%3!=0 or state.debt_quanta==0,"exact_zero_debt_every3_"+str(next_tick))
 var status: Dictionary=Status.from_readback(state)
 var shaft: float=float(status.readings["propeller.angular_speed"].value)
 var running: bool=status.readings["engine.running"].value
 var fuel: float=float(status.readings["fuel.total"].value)
 _check(is_finite(shaft) and shaft>=float(targets.shaft_radps_domain[0]) and shaft<=float(targets.shaft_radps_domain[1]),"unchanged_shaft_domain_"+str(next_tick))
 _check(is_finite(fuel) and fuel>=0.0 and fuel<=100.0 and fuel<=_last_fuel+float(targets.fuel_abs_tolerance_kg),"public_fuel_nonincrease_"+str(next_tick))
 _last_fuel=fuel
 if running and _first_running<0: _first_running=next_tick
 if next_tick>=120 and next_tick<=240: _max_crank_shaft=maxf(_max_crank_shaft,shaft)
 if next_tick>=960 and next_tick<=6120:
  _check(running,"continuous_actual_combustion_"+str(next_tick))
  var all_wow: bool=not state.aircraft.contacts.is_empty()
  for contact in state.aircraft.contacts: all_wow=all_wow and contact.on_ground
  _check(all_wow,"unchanged_post_settle_all_WOW_"+str(next_tick))
 if next_tick>=960 and next_tick<=3480:
  _check(shaft>=float(targets.warm_shaft_radps[0]) and shaft<=float(targets.warm_shaft_radps[1]),"unchanged_warm_shaft_bounds_"+str(next_tick))
 if next_tick>=961: _check(not status.readings["engine.starter"].value,"actual_starter_up_remains_admitted_"+str(next_tick))
 if next_tick==3480: _taxi_start=state.aircraft.ecef_position_m.duplicate(true)
 if next_tick>=3480 and next_tick<=4680: _max_taxi_speed=maxf(_max_taxi_speed,_speed(state.aircraft))
 if next_tick==4680:
  var end: Dictionary=state.aircraft.ecef_position_m
  var forward: float=(float(end.x)-float(_taxi_start.x))*(-sin(0.8)*cos(-2.0))+(float(end.y)-float(_taxi_start.y))*(-sin(0.8)*sin(-2.0))+(float(end.z)-float(_taxi_start.z))*cos(0.8)
  _check(forward>=float(targets.taxi_forward_distance_min_m) and float(state.aircraft.velocity_body_mps.x)>=float(targets.taxi_end_forward_speed_min_mps) and _max_taxi_speed<=float(targets.taxi_speed_max_mps),"unchanged_taxi_publication_bounds")
 if next_tick>=4681 and _first_stopped<0 and _speed(state.aircraft)<=float(targets.stopped_speed_max_mps): _first_stopped=next_tick
 if next_tick==6120:
  _check(running and shaft>0.0 and systems["engine.starter"]==false and systems["fuel.feed"] and state.held_axes.mixture==1.0,"pre_shutdown_public_live_combustion_not_early_stall")
 if next_tick==6121: _check(not running and shaft>0.0,"mixture_cutoff_same_tick_running_false_and_real_coast")
 if next_tick==9720: _check(shaft<=float(targets.coast_60rpm_radps),"unchanged_81s_coast_bound")
 if next_tick==13320: _check(shaft<=float(targets.coast_1rpm_radps),"unchanged_111s_coast_bound")
 _rows.append({"tick":next_tick,"wall_us":elapsed,"raw":_scene.synthetic_raw.duplicate(true),
  "requested":requested,"expected_commands":expected,"actual_commands":actual_commands,
  "readback":state.duplicate(true)})
 return true

func _resume() -> bool:
 _scene.synthetic_raw={"keys":[],"mouse_buttons":[],"devices":[]}
 if not _check(_scene.pause_session(false),"explicit_resume"): return false
 _scene.menu_open=false;_scene.menu.hide();Input.mouse_mode=Input.MOUSE_MODE_VISIBLE
 _scene.engine_controls.set_expanded(true);_scene.show_state()
 return _check(_scene.pointer_ui_eligible(),"live_identity_qualified_visible_pointer")

func _negative_cases() -> void:
 _scene.synthetic_raw={"keys":[],"mouse_buttons":[],"devices":[]}
 if not _check(_scene.restart(true,"calm",Facade.PISTON_PROFILE.id,"piston-cold-ground"),"negative_fresh_session"): return
 if not _resume(): return
 var before: Dictionary=_retained()
 if _press("engine.starter"):
  _scene.synthetic_raw={"keys":[],"mouse_buttons":[1,1],"devices":[]}
  _scene.process_input_interval(8334)
  var after: Dictionary=_retained()
  _check(_scene.paused and before==after,"malformed_complete_Raw_denied_no_command_submission_or_Run")
  _denied.append({"case":"malformed_Raw","before":before,"after":after,"paused":_scene.paused,"problem":_scene.input_problem})
 _scene.synthetic_raw={"keys":[],"mouse_buttons":[],"devices":[]}
 var bound: Dictionary=Mapper.default_preset_v2()
 for action in bound.actions:
  if action.id=="both_brakes": action.sources=[{"kind":"mouse_button","button":1}]
 _scene.apply_controls(bound)
 if not _resume(): return
 before=_retained()
 _scene.synthetic_raw.mouse_buttons=[1]
 _button("engine.starter",true)
 var after: Dictionary=_retained()
 _check(_scene.paused and before==after and _scene.input_problem.contains("both_brakes"),"bound_GUI_primary_denied_before_physical_action_or_Run")
 _denied.append({"case":"bound_primary","before":before,"after":after,"paused":_scene.paused,"problem":_scene.input_problem})

func run(host: Node) -> Dictionary:
 _host=host
 var original_mouse_mode: int=Input.mouse_mode
 if not _check(FileAccess.get_sha256(LIMITS_PATH)==LIMITS_SHA,"unchanged_frozen_native_limits_pin"):
  return {"passed":false,"checks":_checks,"failures":_failures,"scope":"Missing or changed staged pretrial; no scenario executed"}
 var limits: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(LIMITS_PATH))
 _scene=SyntheticScene.new();host.add_child(_scene)
 _scene.set_process(false);_scene.set_physics_process(false);_scene.set_process_input(false)
 _scene.set_process_unhandled_input(false);_scene.set_process_unhandled_key_input(false);_scene.set_process_shortcut_input(false)
 if _scene.sound!=null: _scene.sound.set_process(false)
 var initialized: bool=_check(_scene.facade!=null and _scene.facade.readback().aircraft!=null,"actual_initialization")
 if initialized: initialized=_check(_scene.restart(true,"calm",Facade.PISTON_PROFILE.id,"piston-cold-ground"),"actual_cold_adoption")
 if initialized:
  _source=_scene.facade.readback().duplicate(true)
  initialized=_check(_source.tick=="0" and _source.paused and _source.model_identity==Facade.PISTON_PROFILE and _source.prepared_world_sha256==limits.world_sha256,"unadvanced_qualified_cold_tick0")
 if initialized:
  _admitted_axes=_source.held_axes.duplicate(true)
  _admitted_systems=Status.held_systems_from_readback(_source).value.duplicate(true)
  _scene.engine_controls.gesture_requested.connect(func(value: Dictionary):_gestures.append(value.duplicate(true)))
  await host.get_tree().process_frame
  if _resume():
   var phase_index: int=0
   for next_tick in range(1,13321):
    if phase_index<limits.schedule.size() and int(limits.schedule[phase_index].at_elapsed_s)*120==next_tick-1:
     if not _phase(limits.schedule[phase_index]): break
     phase_index+=1
    if not _step(next_tick,limits.targets): break
   _check(_rows.size()==13320 and phase_index==limits.schedule.size(),"complete_111s_all10_original_phases")
   _check(_first_running>=0 and _first_running<=int(limits.targets.first_running_deadline_s)*120,"unchanged_first_running_deadline")
   _check(_max_crank_shaft>=float(limits.targets.cranking_min_radps),"unchanged_natural_cranking_bound")
   _check(_first_stopped>=0 and _first_stopped<=int(limits.targets.stopped_deadline_s)*120,"unchanged_held_brake_stop_deadline")
   # A separate, explicit post-shutdown cleanup exercises feed OFF and both
   # ignition switches through GUI. It is not an alternate physics shutdown.
   if _rows.size()==13320 and _switch("fuel.feed",false) and _switch("engine.ignition_left",false) and _switch("engine.ignition_right",false):
    _step(13321,limits.targets)
    _check(_actual("fuel.feed")==false and _actual("engine.ignition_left")==false and _actual("engine.ignition_right")==false,"actual_GUI_post_shutdown_feed_and_ignition_off")
   _negative_cases()
 var native_joined: bool=_scene.close_session()
 _check(native_joined,"actual_native_worker_joined")
 var audio_joined: bool=true
 if _scene.sound!=null: audio_joined=bool(await _scene.sound.shutdown())
 _check(audio_joined,"actual_audio_worker_joined")
 var scene_failures: Array=_scene.failures.duplicate(true)
 _check(scene_failures.is_empty(),"production_scene_has_no_internal_check_failures")
 _scene.free();Input.mouse_mode=original_mouse_mode
 return {"schema":"PointerEngineFlight/v1","passed":_failures.is_empty(),"checks":_checks,
  "failures":_failures.duplicate(),"scene_failures":scene_failures,"initialized":initialized,"limits_sha256":LIMITS_SHA,
  "initial_readback":_source,"first_running_tick":_first_running,"first_stopped_tick":_first_stopped,
  "gestures":_gestures,"lever_values":_lever_values,"denied":_denied,"rows":_rows,"native_joined":native_joined,"audio_joined":audio_joined,
  "scope":"Actual original-piston GUI and separate complete synthetic Raw; unchanged published lifecycle bounds and full command/publication trace. GUI normalized coordinates retained exactly. No native private fuel-flow/pumping oracle, aircraft calibration, pilot/hardware, listening, GPU readability or phase acceptance."}
