extends RefCounted
# Original MIT. Actual native executive and production lifecycle; only complete
# Raw, adapter construction and one explicitly named admission-fault case are
# supplied by this fixture; production lifecycle methods are never overridden.
const Scene=preload("res://simulation/flight_scene.gd")
const Facade=preload("res://simulation/session_facade.gd")
const Mapper=preload("res://input/input_mapper.gd")
const Preset=preload("res://input/input_preset.gd")
const CHOICES: Array=[
 {"id":"cold-familiarization","start":"piston-cold-ground","profile":{"id":"original-piston-prop-v1","version":"0.1.0-prototype","backend_model":"original-piston-prop"}},
 {"id":"ready-flight","start":"ground-ready","profile":{"id":"original-interactive-prototype","version":"0.1.0-prototype","backend_model":"original-interactive"}},
 {"id":"airborne-orientation","start":"airborne-prepared","profile":{"id":"original-interactive-prototype","version":"0.1.0-prototype","backend_model":"original-interactive"}}]

class ObservedAdapter extends RefCounted:
 var native: RefCounted
 var entries: Array[Dictionary]=[]
 var inject_open_failure: bool=false
 func _init() -> void:
  native=ClassDB.instantiate("FlightInteractiveSession") as RefCounted
 func _forward(method: String,args: Array) -> Dictionary:
  var reply: Dictionary=native.callv(method,args)
  entries.append({"method":method,"arguments":args.duplicate(true),"reply":reply.duplicate(true)})
  return reply
 func open_session(root: String,start: String,wind: String,profile: String) -> Dictionary:
  var reply: Dictionary=_forward("open_session",[root,start,wind,profile])
  if inject_open_failure:
   # Explicit admission fault AFTER the actual native worker opened. Production
   # Facade must reject and join it; the native lifecycle is never overridden.
   reply=reply.duplicate(true)
   reply.ok=false
  return reply
 func submit(command: Dictionary) -> Dictionary:
  return _forward("submit",[command])
 func session_control(command: Dictionary) -> Dictionary:
  return _forward("session_control",[command])
 func step_fixed(count: int) -> Dictionary:
  return _forward("step_fixed",[count])
 func read_state() -> Dictionary:
  # Read-only observation is excluded from the mutation ledger.
  return native.call("read_state")
 func close() -> Dictionary:
  return _forward("close",[])

class CountedFacade extends Facade:
 var pause_attempts: Array[bool]=[]
 var advances: Array[int]=[]
 var intent_attempts: Array[Dictionary]=[]
 func _init(factory: Callable) -> void:
  super(factory)
 func set_paused(value: bool) -> Dictionary:
  # Count before forwarding, including idempotent or rejected false attempts.
  pause_attempts.append(value)
  return super.set_paused(value)
 func advance_wall_us(elapsed: int) -> Dictionary:
  advances.append(elapsed)
  return super.advance_wall_us(elapsed)
 func set_axes(axes: Dictionary) -> Dictionary:
  intent_attempts.append({"api":"set_axes","axes":axes.duplicate(true)})
  return super.set_axes(axes)
 func set_pilot_intent(axes: Dictionary,systems: Dictionary) -> Dictionary:
  intent_attempts.append({"api":"set_pilot_intent","axes":axes.duplicate(true),"systems":systems.duplicate(true)})
  return super.set_pilot_intent(axes,systems)

class SyntheticScene extends Scene:
 var synthetic_raw: Dictionary={"keys":[],"mouse_buttons":[],"devices":[]}
 var observed_facades: Array[RefCounted]=[]
 var observed_adapters: Array[RefCounted]=[]
 var inject_next_open_failure: bool=false
 var expect_injected_open_failure: bool=false
 var expected_failures: Array[String]=[]
 func collect_input_raw(_preset: Dictionary={}) -> Dictionary:
  return synthetic_raw.duplicate(true)
 func make_observed_adapter() -> RefCounted:
  var adapter: RefCounted=ObservedAdapter.new()
  adapter.inject_open_failure=inject_next_open_failure
  inject_next_open_failure=false
  observed_adapters.append(adapter)
  return adapter
 func _make_facade() -> RefCounted:
  var next: RefCounted=CountedFacade.new(Callable(self,"make_observed_adapter"))
  observed_facades.append(next)
  return next
 func fail(message: String) -> bool:
  if not expect_injected_open_failure or message!="Native initialization or pinned identity validation failed":
   return super.fail(message)
  # Exact production fail() state, suppressing ONLY this named expected log.
  expect_injected_open_failure=false
  expected_failures.append(message)
  render_pose.clear()
  status=message+" | R starts a fresh attempt"
  paused=true
  blocked=true
  failures.append(message)
  return false

class UnhandledWitness extends Node:
 var events: Array[InputEvent]=[]
 func _unhandled_input(event: InputEvent) -> void:
  events.append(event)

var _host: Node
var _checks: int=0
var _failures: Array[String]=[]
var _adoptions: Array[Dictionary]=[]
var _include_piston: bool=true

func _check(ok: bool,label: String) -> void:
 _checks+=1
 if not ok: _failures.append(label)
 _host.call("check",ok,"first_flight_scene_"+label)

func _copy(value: Variant) -> Variant:
 return value.duplicate(true) if value is Array or value is Dictionary else value

func _snapshot(scene: Node) -> PackedByteArray:
 # Full binary Variant equality preserves integer/float distinctions and all
 # native binary64 values. No JSON normalization or physics tolerance involved.
 var mapper: Dictionary={}
 for key in ["_preset","_values","_start","_pins","_edges","_takeover","_configured","_live","_brake_hold","_v2","_held_systems","_system_intents","_system_edges","_pointer_session","_pointer_generation","_pointer_last_token","_pointer_capture","_pointer_begin","_pointer_terminal","_pointer_pending","_pointer_rearm","_pointer_error","_pointer_disabled"]:
  mapper[key]=_copy(scene.mapper.get(key))
 var facade: Dictionary={}
 for key in ["_command_sequence","_lifecycle_sequence","_pending","_admitted","_pending_systems","_admitted_systems","_previous","_current","_previous_tick","_commands","_events","_pending_commands","_pending_events","_delivered_command","_delivered_event","_complete","_admission","_rejection","_completed","_origin_blocked","_blocked_origin_version"]:
  facade[key]=_copy(scene.facade.get(key))
 var state: Dictionary={"readback":scene.facade.readback(),"native":scene.facade.get("_bridge").call("read_state"),"mapper":mapper,"facade":facade,
  "recording":scene.observed_recorder.recording(),"recorder_status":scene.observed_status.duplicate(true),"origin":scene.facade.render_origin.read_origin()}
 for key in ["controls","held_controls","last_submitted","held_systems","pending_systems","brake_hold","takeover_targets","engine_pointer_rearm","engine_pointer_terminal","engine_pointer_look_active","submitted_count","event_count","adopted_session_id","current_wind_profile","selected_profile","active_preset","profile_presets"]:
  state[key]=_copy(scene.get(key))
 return var_to_bytes(state)

func _ledger(scene: Node) -> PackedByteArray:
 var result: Array=[]
 for facade in scene.observed_facades:
  result.append({"pause_attempts":facade.pause_attempts.duplicate(),"advances":facade.advances.duplicate(),"intent_attempts":facade.intent_attempts.duplicate(true)})
 for adapter in scene.observed_adapters: result.append(adapter.entries.duplicate(true))
 return var_to_bytes(result)

func _settle(scene: Node) -> void:
 # Normal host paused-zero accounting may run; settle before the strict UI span.
 _check(scene.pause_session(true),"settled_pause")
 _check(scene.advance_wall_us(0),"settled_ordinary_zero_accounting")
 scene.show_state(0.0)

func _source(scene: Node,profile: String,start_override: String="") -> bool:
 scene.synthetic_raw={"keys":[],"mouse_buttons":[],"devices":[]}
 var start: String=start_override if not start_override.is_empty() else ("piston-cold-ground" if profile=="original-piston-prop-v1" else "ground-ready")
 var ok: bool=scene.restart(true,"calm",profile,start)
 _check(ok,"source_"+profile)
 if not ok: return false
 scene.open_menu("Fixture paused")
 _settle(scene)
 scene.open_first_flight()
 _check(scene.first_flight_open and scene.first_flight_panel.visible,"source_briefing_open")
 return scene.first_flight_open

func _assert_new(scene: Node,choice: Dictionary,old_session: String,label: String) -> void:
 var rb: Dictionary=scene.facade.readback()
 _check(rb.session_id!=old_session and rb.session_id==scene.adopted_session_id,label+"_new_session")
 _check(rb.model_identity==choice.profile and rb.named_start==choice.start and scene.current_wind_profile=="calm",label+"_exact_full_choice_identity")
 _check(rb.tick=="0" and rb.paused and rb.native_live and not rb.historical and rb.host_mode=="paused" and rb.debt_quanta==0,label+"_paused_live_tick_zero")
 _check(scene.first_flight_open and scene.first_flight_panel.visible and scene.menu_open and scene.pending_discard.is_empty(),label+"_briefing_continuation_no_hidden_resume")
 _check(scene.first_flight_source_session()==rb.session_id,label+"_callback_identity_refreshed")
 var counted: RefCounted=scene.observed_facades.back()
 var adapter: RefCounted=scene.observed_adapters.back()
 _check(counted==scene.facade and not counted.pause_attempts.has(false),label+"_no_false_pause_attempt_from_construction")
 _check(counted.intent_attempts.is_empty(),label+"_no_pending_or_noop_pilot_intent_attempt")
 var completed: int=0
 var commands: int=0
 var false_controls: int=0
 var opens: int=0
 for entry in adapter.entries:
  if entry.method=="open_session":
   opens+=1
   _check(entry.arguments.slice(1)==[choice.start,"calm",choice.profile.id] and entry.reply.get("completed")==0,label+"_native_open_identity")
  if entry.method=="step_fixed": completed+=int(entry.reply.get("completed",-1000))
  if entry.method=="submit": commands+=1
  if entry.method=="session_control":
   var payload: Dictionary=entry.arguments[0].payload
   if payload.get("kind")=="pause" and payload.get("paused")==false: false_controls+=1
 _check(opens==1 and completed==0 and commands==0 and false_controls==0,label+"_no_completed_Run_or_pilot_command")
 _adoptions.append({"label":label,"model_identity":rb.model_identity.duplicate(true),"start":rb.named_start,"tick":rb.tick,"pause_attempts":counted.pause_attempts.duplicate(),"native_calls":adapter.entries.size(),"completed":completed})

func _immediate_matrix(scene: Node) -> void:
 var sources: Array=[{"profile":"original-interactive-prototype","start":"ground-ready"}]
 if _include_piston: sources.append({"profile":"original-piston-prop-v1","start":"piston-cold-ground"})
 else: sources.append({"profile":"original-interactive-prototype","start":"airborne-prepared"})
 for old in sources:
  for choice in CHOICES:
   if not _include_piston and choice.id=="cold-familiarization": continue
   if not _source(scene,old.profile,old.start): continue
   var prior: String=scene.adopted_session_id
   var old_adapter: RefCounted=scene.observed_adapters.back()
   scene.on_first_flight_choice(choice.id,prior,scene.first_flight_panel)
   _assert_new(scene,choice,prior,"immediate_"+old.profile+"_"+old.start+"_"+choice.id)
   _check(not old_adapter.entries.is_empty() and old_adapter.entries.back().method=="close" and old_adapter.entries.back().reply.get("joined")==true,"immediate_old_worker_joined")

func _paused_invariance(scene: Node) -> void:
 for profile in ["original-interactive-prototype","original-piston-prop-v1"]:
  if not _include_piston and profile=="original-piston-prop-v1": continue
  if not _source(scene,profile): continue
  scene.dismiss_first_flight()
  var before: PackedByteArray=_snapshot(scene)
  var ledger: PackedByteArray=_ledger(scene)
  scene.open_first_flight()
  _check(_snapshot(scene)==before and _ledger(scene)==ledger,"already_paused_open_exact_"+profile)
  scene.first_flight_panel.call("_change_step",-3)
  _check(scene.first_flight_panel.get("_step_index")==0,"manual_step_initial_zero_"+profile)
  for index in 4:
   scene.first_flight_panel.call("_change_step",1)
   _check(scene.first_flight_panel.get("_step_index")==mini(index+1,3),"manual_step_positive_control_"+profile+"_"+str(index))
   _check(_snapshot(scene)==before and _ledger(scene)==ledger,"manual_step_exact_"+profile+"_"+str(index))
  scene.first_flight_panel.call("_change_step",-3)
  _check(_snapshot(scene)==before and _ledger(scene)==ledger,"manual_step_back_exact_"+profile)
  var source: String=scene.first_flight_source_session()
  var context: PackedByteArray=var_to_bytes({"extent":scene.flight_map.extent_m,"runway":scene.flight_map.get("_runway"),"route":scene.flight_map.get("_route")})
  scene.on_circuit_enabled(true,source,scene.first_flight_panel)
  scene.publish_circuit_reference()
  _check(_snapshot(scene)==before and _ledger(scene)==ledger,"aid_on_exact_"+profile)
  _check(var_to_bytes({"extent":scene.flight_map.extent_m,"runway":scene.flight_map.get("_runway"),"route":scene.flight_map.get("_route")})==context,"aid_preserves_map_route_extent_runway_"+profile)
  scene.on_circuit_enabled(false,source,scene.first_flight_panel)
  _check(_snapshot(scene)==before and _ledger(scene)==ledger,"aid_off_exact_"+profile)
  scene.on_first_flight_back(source,scene.first_flight_panel)
  _check(not scene.first_flight_open and scene.menu_open and scene.facade.readback().paused,"Back_returns_to_paused_Resume_"+profile)
  _check(_snapshot(scene)==before and _ledger(scene)==ledger,"Back_exact_"+profile)

func _reject_requests(scene: Node) -> void:
 if not _source(scene,"original-interactive-prototype"): return
 var source: String=scene.first_flight_source_session()
 var stale: Control=Control.new()
 for kind in ["widget","session","unknown","file","initializing","pending"]:
  var before: PackedByteArray=_snapshot(scene)
  var ledger: PackedByteArray=_ledger(scene)
  var aid: bool=scene.circuit_aid_enabled
  match kind:
   "widget": scene.on_first_flight_choice("cold-familiarization",source,stale)
   "session": scene.on_first_flight_choice("cold-familiarization",source+"-stale",scene.first_flight_panel)
   "unknown": scene.on_first_flight_choice("invented-running-piston",source,scene.first_flight_panel)
   "file":
    scene.archive_operation={"kind":"test-only-open-guard"}
    scene.on_first_flight_choice("cold-familiarization",source,scene.first_flight_panel)
    scene.on_first_flight_back(source,scene.first_flight_panel)
    scene.on_first_flight_controls(source,scene.first_flight_panel)
    scene.on_circuit_enabled(true,source,scene.first_flight_panel)
    scene.archive_operation.clear()
   "initializing":
    scene.initializing_recording=true
    scene.on_first_flight_choice("cold-familiarization",source,scene.first_flight_panel)
    scene.on_first_flight_back(source,scene.first_flight_panel)
    scene.on_first_flight_controls(source,scene.first_flight_panel)
    scene.on_circuit_enabled(true,source,scene.first_flight_panel)
    scene.initializing_recording=false
   "pending":
    scene.pending_discard={"action":"restart","session_id":source,"first_flight":true}
    scene.on_first_flight_choice("cold-familiarization",source,scene.first_flight_panel)
    scene.on_first_flight_back(source,scene.first_flight_panel)
    scene.on_first_flight_controls(source,scene.first_flight_panel)
    scene.on_circuit_enabled(true,source,scene.first_flight_panel)
    scene.pending_discard.clear()
  _check(_snapshot(scene)==before and _ledger(scene)==ledger and scene.circuit_aid_enabled==aid and scene.first_flight_open,"reject_"+kind+"_without_effect")
 var stale_before: PackedByteArray=_snapshot(scene)
 var stale_ledger: PackedByteArray=_ledger(scene)
 scene.on_first_flight_back(source,stale)
 scene.on_first_flight_controls(source,stale)
 scene.on_circuit_enabled(true,source,stale)
 _check(scene.first_flight_open and not scene.controls_panel.visible and _snapshot(scene)==stale_before and _ledger(scene)==stale_ledger,"stale_widget_cannot_close_or_open_Controls")
 stale.free()
 scene.dismiss_first_flight()
 var retired: PackedByteArray=_snapshot(scene)
 var retired_ledger: PackedByteArray=_ledger(scene)
 scene.on_first_flight_choice("cold-familiarization",source,scene.first_flight_panel)
 scene.on_circuit_enabled(true,source,scene.first_flight_panel)
 _check(_snapshot(scene)==retired and _ledger(scene)==retired_ledger and not scene.first_flight_open,"hidden_widget_request_rejected")

func _advanced_discard(scene: Node) -> void:
 for choice in CHOICES:
  if not _include_piston and choice.id=="cold-familiarization": continue
  if not _source(scene,"original-interactive-prototype"): continue
  scene.dismiss_first_flight()
  var adapter: RefCounted=scene.observed_adapters.back()
  # Deliberate positive control: the same observer must detect actual Run.
  scene.close_menu()
  _check(scene.facade.readback().host_mode=="live" and scene.observed_facades.back().pause_attempts.has(false),"explicit_Resume_observed_"+choice.id)
  _check(scene.advance_wall_us(25000),"deliberate_actual_advance_"+choice.id)
  var completed: int=0
  for entry in adapter.entries:
   if entry.method=="step_fixed": completed+=int(entry.reply.get("completed",0))
  _check(completed>0 and scene.facade.readback().tick!="0","positive_Run_oracle_"+choice.id)
  _settle(scene)
  scene.open_first_flight()
  _check(scene.recorded_flight_advanced(),"actual_advanced_recording_"+choice.id)
  var prior: String=scene.adopted_session_id
  var before: PackedByteArray=_snapshot(scene)
  var ledger: PackedByteArray=_ledger(scene)
  scene.on_first_flight_choice(choice.id,prior,scene.first_flight_panel)
  _check(scene.pending_discard.get("first_flight")==true and scene.pending_discard.get("session_id")==prior and scene.discard_layer.visible,"advanced_choice_requests_scoped_discard_"+choice.id)
  _check(scene.get_viewport().gui_get_focus_owner()==scene.discard_cancel,"default_Cancel_focus_"+choice.id)
  _check(_snapshot(scene)==before and _ledger(scene)==ledger,"discard_request_preserves_full_prefix_"+choice.id)
  scene.cancel_discard()
  _check(scene.pending_discard.is_empty() and not scene.discard_layer.visible and scene.first_flight_open,"Cancel_clears_continuation_"+choice.id)
  _check(_snapshot(scene)==before and _ledger(scene)==ledger,"Cancel_preserves_full_prefix_"+choice.id)
  scene.on_first_flight_choice(choice.id,prior,scene.first_flight_panel)
  scene.pending_discard.session_id=prior+"-stale"
  scene.confirm_discard()
  _check(scene.pending_discard.is_empty() and _snapshot(scene)==before and _ledger(scene)==ledger,"stale_discard_rejected_and_cleared_"+choice.id)
  scene.on_first_flight_choice(choice.id,prior,scene.first_flight_panel)
  scene.confirm_discard()
  _assert_new(scene,choice,prior,"confirmed_"+choice.id)
  var fresh: PackedByteArray=_snapshot(scene)
  var fresh_ledger: PackedByteArray=_ledger(scene)
  scene.on_first_flight_choice("ready-flight",prior,scene.first_flight_panel)
  _check(_snapshot(scene)==fresh and _ledger(scene)==fresh_ledger,"old_session_callback_inert_after_adoption_"+choice.id)

func _geographic_bytes(scene: Node) -> PackedByteArray:
 var state: Dictionary={}
 for key in ["_session","_sample_tick","_trail","_position","_direction","_valid","_heading_valid","_paused","_retained","_clearance_valid","_clearance_m","extent_m","_runway","_route","_wind_cue","_circuit"]:
  state[key]=_copy(scene.flight_map.get(key))
 return var_to_bytes(state)

func _actual_origin_rebase(scene: Node) -> void:
 if not _source(scene,"original-interactive-prototype"): return
 # A real existing landmark itinerary coexists with the independent diagram.
 scene.dismiss_first_flight()
 scene.open_landmark_route()
 scene.choose_landmark_route([0,1])
 scene.flight_map.extent_m=1000.0
 scene.flight_map.select_runway(36)
 scene.open_first_flight()
 scene.on_circuit_enabled(true,scene.first_flight_source_session(),scene.first_flight_panel)
 scene.show_state(0.0)
 var guide: Dictionary=scene.flight_map.get("_circuit").duplicate(true)
 var expected_points: Array=[[0.0,0.0,100.0],[0.0,0.0,-2700.0],[-1400.0,0.0,-2700.0],[-1400.0,0.0,1300.0],[0.0,0.0,1300.0],[0.0,0.0,100.0]]
 _check(guide.get("available")==true and scene.flight_map.get("_valid") and not scene.flight_map.get("_route").is_empty(),"rebase_real_available_guide_and_existing_route")
 if guide.get("available")!=true: return
 _check(guide.points_anchor_eus_m==expected_points and guide.leg_labels==["Departure","Crosswind","Downwind","Base","Final"],"rebase_independent_ADR018_diagram_before")
 var rb: Dictionary=scene.facade.readback()
 for component in 3:
  _check(var_to_bytes([guide.ownship_anchor_eus_m[component]])==var_to_bytes([rb.canonical.anchor_eus_position_m[component]]),"rebase_all_three_direct_canonical_scalars_before_"+str(component))
 _check(scene.flight_map.get("_position")==Vector2(rb.canonical.anchor_eus_position_m[0],rb.canonical.anchor_eus_position_m[2]),"rebase_map_center_uses_original_geographic_anchor")
 var native_before: Dictionary=bytes_to_var(_snapshot(scene))
 # Only the explicitly changed render-origin record is excluded. Every native,
 # queue, mapper, recording, preset and canonical/source byte remains required.
 native_before.erase("origin")
 var native_bytes: PackedByteArray=var_to_bytes(native_before)
 var ledger: PackedByteArray=_ledger(scene)
 var geographic: PackedByteArray=_geographic_bytes(scene)
 var card_view: PackedByteArray=var_to_bytes(scene.circuit_card.get("_view"))
 var origin_before: Dictionary=scene.facade.render_origin.read_origin()
 var pose_before: Transform3D=scene.airplane.transform
 var chart: Rect2=Rect2(12,56,400,300)
 var projected: Array[Vector2]=[]
 for point in expected_points: projected.append(scene.flight_map._point(Vector2(point[0],point[2]),chart))
 # Accepted freeflight rebase pattern: explicit horizontal AND vertical shift
 # in the fixed anchor basis, never a native reposition or physics command.
 scene.update_canonical_scene_sources()
 var request: Array=rb.canonical.ecef_position_m.duplicate()
 var rotation: Array=scene.prepared.rotation
 for component in 3:
  request[component]+=rotation[component]*600.0+rotation[3+component]*125.0+rotation[6+component]*800.0
 var rebased: Dictionary=scene.facade.render_origin.rebase(request)
 _check(rebased.ok,"actual_horizontal_vertical_rebase_accepted")
 if not rebased.ok: return
 scene.show_state(0.0)
 var origin_after: Dictionary=scene.facade.render_origin.read_origin()
 _check(origin_after.valid and origin_after.committed.origin_ecef_m==request and origin_after.committed.version!=origin_before.committed.version and scene.airplane.transform!=pose_before,"actual_rebase_changes_only_origin_and_render_pose")
 var native_after: Dictionary=bytes_to_var(_snapshot(scene))
 native_after.erase("origin")
 _check(var_to_bytes(native_after)==native_bytes and _ledger(scene)==ledger,"actual_rebase_full_native_mapper_queues_recording_source_invariant")
 var after: Dictionary=scene.flight_map.get("_circuit")
 _check(after.get("available")==true and var_to_bytes(after)==var_to_bytes(guide),"actual_rebase_retains_complete_available_anchor_guide")
 _check(_geographic_bytes(scene)==geographic,"actual_rebase_preserves_map_ownship_points_extent_runway_route")
 _check(var_to_bytes(scene.circuit_card.get("_view"))==card_view,"actual_rebase_preserves_copied_fixed_card_view")
 for index in expected_points.size():
  _check(scene.flight_map._point(Vector2(expected_points[index][0],expected_points[index][2]),chart)==projected[index],"actual_rebase_preserves_geographic_projection_"+str(index))

func _truth_bytes(scene: Node) -> PackedByteArray:
 return var_to_bytes({"readback":scene.facade.readback(),"native":scene.facade.get("_bridge").call("read_state"),"recording":scene.observed_recorder.recording(),"origin":scene.facade.render_origin.read_origin(),"pending_commands":scene.facade.get("_pending_commands"),"pending_events":scene.facade.get("_pending_events"),"pilot_sequence":scene.facade.get("_command_sequence")})

func _key(scene: Node,code: int) -> void:
 var event: InputEventKey=InputEventKey.new()
 event.pressed=true;event.physical_keycode=code
 scene._unhandled_key_input(event)

func _modal_input(scene: Node) -> void:
 var profile: String="original-piston-prop-v1" if _include_piston else "original-interactive-prototype"
 if not _source(scene,profile): return
 if _include_piston:
  scene.dismiss_first_flight()
  scene.close_menu()
  scene.synthetic_raw.mouse_buttons=[MOUSE_BUTTON_RIGHT]
  scene.process_input_interval(0)
  _check(scene.engine_pointer_look_active,"live_look_logical_owner_positive_control")
  var before_pause: Dictionary=scene.facade.readback()
  scene.open_first_flight()
  _check(scene.facade.readback().paused and scene.facade.readback().tick==before_pause.tick and not scene.engine_pointer_look_active and Input.mouse_mode==Input.MOUSE_MODE_VISIBLE,"live_open_ordinary_pause_retires_look_without_Run")
  scene.synthetic_raw={"keys":[],"mouse_buttons":[],"devices":[]}
  scene.process_input_interval(0)
  scene.show_state(0.0)
 var before: PackedByteArray=_snapshot(scene)
 var ledger: PackedByteArray=_ledger(scene)
 var angles: Vector2=scene.look_angles
 scene.synthetic_raw={"keys":[KEY_W],"mouse_buttons":[1,2],"devices":[]}
 _key(scene,KEY_W)
 var motion: InputEventMouseMotion=InputEventMouseMotion.new()
 motion.relative=Vector2(40,20)
 scene._unhandled_input(motion)
 _check(_snapshot(scene)==before and _ledger(scene)==ledger and scene.look_angles==angles,"modal_complete_held_Raw_flight_key_and_look_motion_inert")
 scene.synthetic_raw={"keys":[KEY_P],"mouse_buttons":[],"devices":[]}
 _key(scene,KEY_P)
 _check(not scene.first_flight_open and scene.menu_open and scene.facade.readback().paused and _snapshot(scene)==before and _ledger(scene)==ledger,"modal_pause_key_returns_paused_not_Resume")
 scene.synthetic_raw={"keys":[],"mouse_buttons":[],"devices":[]}
 scene.open_first_flight()
 var truth: PackedByteArray=_truth_bytes(scene)
 var control_ledger: PackedByteArray=_ledger(scene)
 scene.synthetic_raw.keys=[KEY_F7]
 _key(scene,KEY_F7)
 _check(scene.controls_panel.visible and not scene.first_flight_open and scene.facade.readback().paused and not scene.pointer_ui_eligible(),"default_F7_Controls_owns_paused_modal")
 _check(_truth_bytes(scene)==truth and _ledger(scene)==control_ledger,"default_F7_Controls_preserves_full_native_queues_recording_origin")
 scene.synthetic_raw.keys=[]
 scene.dismiss_controls()
 # Explicit remap and complete closed synthetic Raw; no physical-device claim.
 var preset: Dictionary=scene.active_preset.duplicate(true)
 preset.devices=[{"slot":"briefing-pad","label":"Synthetic pause fixture","match":{"guid":"fixture","name":"fixture","vendor_id":"","product_id":""}}]
 for action in preset.actions:
  if action.id=="pause_menu": action.sources=[{"kind":"joy_button","slot":"briefing-pad","index":0}]
  if action.id=="controls_panel": action.sources=[{"kind":"physical_keys","keys":[KEY_L]},{"kind":"joy_button","slot":"briefing-pad","index":1}]
 scene.synthetic_raw={"keys":[],"mouse_buttons":[],"devices":[{"slot":"briefing-pad","generation":3,"axes":[],"buttons":[{"index":0,"pressed":false},{"index":1,"pressed":false}]}]}
 scene.apply_controls(preset)
 _check(scene.active_preset==preset,"joy_pause_explicit_valid_preset_applied")
 scene.open_first_flight()
 var remap_before: PackedByteArray=_snapshot(scene)
 var remap_ledger: PackedByteArray=_ledger(scene)
 scene.synthetic_raw.keys=[KEY_F7]
 _key(scene,KEY_F7)
 _check(scene.first_flight_open and not scene.controls_panel.visible and _snapshot(scene)==remap_before and _ledger(scene)==remap_ledger,"old_default_Controls_key_inert_after_explicit_remap")
 scene.synthetic_raw.keys=[KEY_L]
 var remap_truth: PackedByteArray=_truth_bytes(scene)
 _key(scene,KEY_L)
 _check(scene.controls_panel.visible and not scene.first_flight_open and scene.facade.readback().paused,"remapped_physical_key_opens_Controls")
 _check(_truth_bytes(scene)==remap_truth and _ledger(scene)==remap_ledger,"remapped_physical_Controls_preserves_truth_and_ledger")
 scene.synthetic_raw.keys=[]
 scene.dismiss_controls()
 scene.open_first_flight()
 var joy_control_truth: PackedByteArray=_truth_bytes(scene)
 var joy_control_ledger: PackedByteArray=_ledger(scene)
 scene.synthetic_raw.devices[0].buttons[1].pressed=true
 var controls_joy: InputEventJoypadButton=InputEventJoypadButton.new()
 controls_joy.pressed=true;controls_joy.button_index=1
 scene._unhandled_input(controls_joy)
 _check(scene.controls_panel.visible and not scene.first_flight_open and scene.facade.readback().paused,"remapped_joy_button_opens_Controls")
 _check(_truth_bytes(scene)==joy_control_truth and _ledger(scene)==joy_control_ledger,"remapped_joy_Controls_preserves_truth_and_ledger")
 scene.synthetic_raw.devices[0].buttons[1].pressed=false
 scene.dismiss_controls()
 scene.open_first_flight()
 var joy_before: PackedByteArray=_snapshot(scene)
 var joy_ledger: PackedByteArray=_ledger(scene)
 scene.synthetic_raw.devices[0].buttons[0].pressed=true
 var joy: InputEventJoypadButton=InputEventJoypadButton.new()
 joy.pressed=true;joy.button_index=0
 scene._unhandled_input(joy)
 _check(not scene.first_flight_open and scene.menu_open and scene.facade.readback().paused and _snapshot(scene)==joy_before and _ledger(scene)==joy_ledger,"remapped_joy_pause_returns_paused_without_sampling_or_Run")
 scene.synthetic_raw.devices[0].buttons[0].pressed=false
 scene.open_first_flight()
 _key(scene,KEY_ESCAPE)
 _check(not scene.first_flight_open and scene.facade.readback().paused,"Escape_returns_paused")
 scene.synthetic_raw={"keys":[],"mouse_buttons":[],"devices":[]}
 scene.apply_controls(Mapper.default_preset_v2() if _include_piston else Mapper.default_preset())
 _check(scene.active_preset.devices.is_empty(),"synthetic_joy_fixture_explicitly_restored")

func _legacy_cold_rejection(scene: Node) -> void:
 if not _source(scene,"original-interactive-prototype"): return
 var before: PackedByteArray=_snapshot(scene)
 var ledger: PackedByteArray=_ledger(scene)
 scene.on_first_flight_choice("cold-familiarization",scene.first_flight_source_session(),scene.first_flight_panel)
 _check(_snapshot(scene)==before and _ledger(scene)==ledger and scene.pending_discard.is_empty(),"upstream_cold_rejected_before_close_or_factory")

func _presentation_bytes(scene: Node) -> PackedByteArray:
 var board: Control=scene.landmark_board
 return var_to_bytes({"map":scene.flight_map.get_global_rect(),"compact":scene.flight_map.compact_aid_layout,
  "engine":scene.engine_controls.get_global_rect(),"engine_expanded":scene.engine_controls.is_expanded(),
  "wind":scene.wind_card.get_global_rect(),"wind_label":scene.wind_label.get_global_rect(),"wind_visible":scene.wind_card.visible,
  # Hidden Containers defer minimum-size settlement. Their committed dock,
  # visibility and typography remain checked; actual visible bounds are checked
  # below after opening the card and processing its real layout frames.
  "route_card":board._card.get_global_rect() if board._card.is_visible_in_tree() else Rect2(),"route_visible":board._card.visible,"summary":board._summary_in_map,"dock":board._card_dock,
  "title_font":board._title.get_theme_font_size("font_size"),"metrics_font":board._metrics.get_theme_font_size("font_size"),"state_wrap":board._state.autowrap_mode,"state_minimum":board._state.custom_minimum_size})

func _layout_frames(scene: Node) -> void:
 # Real container/theme/viewport processing; native automatic input is disabled.
 scene.show_state(0.0)
 await _host.get_tree().process_frame
 await _host.get_tree().process_frame
 scene.show_state(0.0)

func _paused_native_live_aid_view(scene: Node) -> void:
 # Only expose the live presentation over ACTUAL PAUSED truth. No Resume,
 # worker call, lifecycle override or claim of an observed flying aircraft.
 scene.dismiss_first_flight()
 scene.menu_open=false
 scene.menu.hide()
 await _layout_frames(scene)

func _set_layout_aid(scene: Node,enabled: bool) -> void:
 scene.open_first_flight()
 _check(scene.first_flight_open,"layout_choice_has_actual_paused_modal_owner")
 scene.on_circuit_enabled(enabled,scene.first_flight_source_session(),scene.first_flight_panel)
 await _paused_native_live_aid_view(scene)

func _projected_bezel(scene: Node,index: int) -> Rect2:
 var ring: MeshInstance3D=scene.cockpit.root.find_child("OriginalDialBezel"+str(index),true,false) as MeshInstance3D
 if ring==null: return Rect2()
 # Observe the actual accepted mesh bounds through the actual camera. No new
 # camera/projection geometry or expected layout is copied from the consumer.
 var box: AABB=ring.mesh.get_aabb()
 var bounds: Rect2=Rect2()
 for corner in 8:
  var local: Vector3=box.position+Vector3(box.size.x if (corner&1)!=0 else 0.0,box.size.y if (corner&2)!=0 else 0.0,box.size.z if (corner&4)!=0 else 0.0)
  var world: Vector3=ring.global_transform*local
  if scene.camera.is_position_behind(world): return Rect2()
  var point: Vector2=scene.camera.unproject_position(world)
  bounds=Rect2(point,Vector2.ZERO) if corner==0 else bounds.expand(point)
 return bounds

func _layout_matrix(scene: Node) -> void:
 var window: Window=scene.get_window()
 var old_size: Vector2i=window.size
 var old_expanded: bool=scene.engine_controls.is_expanded()
 var profiles: Array[String]=["original-interactive-prototype"]
 if _include_piston: profiles.append("original-piston-prop-v1")
 for profile in profiles:
  if not _source(scene,profile): continue
  var cold: bool=profile=="original-piston-prop-v1"
  if cold: scene.engine_controls.set_expanded(true)
  if not cold:
   scene.dismiss_first_flight()
   scene.open_landmark_route()
   scene.choose_landmark_route([0,1])
  scene.map_visible=true
  scene.flight_map.show()
  for dimensions in [Vector2i(960,540),Vector2i(1920,1080),Vector2i(2560,1440)]:
   window.size=dimensions
   await _layout_frames(scene)
   _check(window.size==dimensions,"layout_observed_window_"+profile+str(dimensions))
   for mode in [0,3,1]:
    scene.set_camera_mode(mode)
    scene.map_visible=true
    scene.flight_map.show()
    await _set_layout_aid(scene,false)
    var label: String=profile+"_"+str(dimensions)+"_view_"+str(mode)
    var off: PackedByteArray=_presentation_bytes(scene)
    var native: PackedByteArray=_snapshot(scene)
    var ledger: PackedByteArray=_ledger(scene)
    var route: PackedByteArray=var_to_bytes(scene.flight_map.get("_route"))
    await _set_layout_aid(scene,true)
    var card: Control=scene.circuit_card
    var card_rect: Rect2=card.get_global_rect()
    var map_rect: Rect2=scene.flight_map.get_global_rect()
    var viewport: Rect2=Rect2(Vector2.ZERO,Vector2(dimensions))
    _check(card.is_visible_in_tree() and viewport.encloses(card_rect),"layout_enabled_card_inside_"+label)
    _check(card._view.available==(not cold),"layout_actual_start_availability_"+label)
    # Accepted live top bar occupies y0..85. Cold cockpit/chase additionally
    # draws its native engine feedback through y144; PANEL draws it at bottom.
    var top: float=85.0
    var native_bar: Rect2=Rect2(0,0,dimensions.x,top)
    _check(not card_rect.intersects(native_bar),"layout_card_preserves_native_top_bar_"+label)
    if mode==1:
     # Existing accepted outside-view flight HUD owns the lower 34%, capped455.
     var hud_height: float=minf(dimensions.y*0.34,455.0)
     var hud: Rect2=Rect2(0,dimensions.y-hud_height,dimensions.x,hud_height)
     _check(not card_rect.intersects(hud),"layout_card_preserves_actual_chase_HUD_band_"+label)
     if not cold: _check(not map_rect.intersects(hud),"layout_map_preserves_actual_chase_HUD_band_"+label)
    else:
     for index in 6:
      var bezel: Rect2=_projected_bezel(scene,index)
      _check(bezel.size.x>0.0 and bezel.size.y>0.0,"layout_observed_actual_bezel_"+label+"_"+str(index))
      _check(not card_rect.intersects(bezel),"layout_card_preserves_primary_dial_"+label+"_"+str(index))
      _check(not map_rect.intersects(bezel),"layout_map_preserves_primary_dial_"+label+"_"+str(index))
    if cold:
     _check(card._view.points_anchor_eus_m.is_empty() and card._view.leg_labels.is_empty() and card._reason.visible and not card._reason.text.is_empty(),"layout_cold_notice_no_false_diagram_"+label)
     _check(card_rect.encloses(card._title.get_global_rect()) and card_rect.encloses(card._reason.get_global_rect()),"layout_cold_complete_notice_regions_"+label)
     _check(not card._title.get_global_rect().intersects(card._reason.get_global_rect()),"layout_cold_title_reason_separate_"+label)
     for text_label in [card._title,card._reason]:
      var line_count: int=text_label.get_line_count()
      var text_height: float=line_count*text_label.get_line_height()+maxi(0,line_count-1)*text_label.get_theme_constant("line_spacing")
      _check(line_count>0 and text_height<=text_label.size.y,"layout_cold_complete_wrapped_text_"+label+str(text_label==card._title))
     for legend in card._labels: _check(not legend.visible,"layout_cold_no_visible_leg_"+label)
     for child in card.get_children():
      if child is Label and child.visible: _check(card_rect.encloses(child.get_global_rect()),"layout_cold_visible_text_inside_notice_"+label)
     _check(not scene.engine_controls.visible or not card_rect.intersects(scene.engine_controls.get_global_rect()),"layout_cold_notice_preserves_engine_controls_"+label)
     _check(not scene.wind_card.visible or not card_rect.intersects(scene.wind_card.get_global_rect()),"layout_cold_notice_preserves_wind_"+label)
    else:
     _check(viewport.encloses(map_rect) and map_rect.size.x>=220.0 and map_rect.size.y>=220.0,"layout_enabled_map_actually_drawable_inside_"+label)
     _check(not card_rect.intersects(map_rect),"layout_available_map_card_distinct_"+label)
     _check(scene.landmark_board._summary_in_map and not scene.landmark_board._card.visible and not scene.flight_map.get("_route").is_empty(),"layout_actual_manual_route_summarized_in_visible_map_"+label)
     scene.dispatch_input_action("map_toggle")
     await _layout_frames(scene)
     _check(not scene.flight_map.visible and not scene.landmark_board._summary_in_map and scene.landmark_board._card.visible,"layout_closed_map_restores_actual_route_card_"+label)
     # A visible flag alone can hide a one-pixel footer. Observe all five actual
     # container labels after the real layout frames, including font line height.
     var board: Control=scene.landmark_board
     var route_rect: Rect2=board._card.get_global_rect()
     var route_labels: Array[Label]=[board._card.get_child(0).get_child(0) as Label,board._title,board._metrics,board._leg_text,board._state]
     for index in route_labels.size():
      var text_label: Label=route_labels[index]
      _check(text_label.is_visible_in_tree() and not text_label.text.is_empty(),"layout_closed_map_actual_route_label_visible_"+label+"_"+str(index))
      var line_count: int=text_label.get_line_count()
      var full_height: float=line_count*text_label.get_line_height()+maxi(0,line_count-1)*text_label.get_theme_constant("line_spacing")
      _check(line_count>0 and full_height<=text_label.size.y,"layout_closed_map_actual_route_label_font_height_"+label+"_"+str(index))
      _check(route_rect.encloses(text_label.get_global_rect()),"layout_closed_map_actual_route_label_inside_card_"+label+"_"+str(index))
     _check(board._state.size.y>=board._state.get_line_height() and board._state.get_global_rect().end.y<=route_rect.end.y,"layout_closed_map_real_footer_has_drawable_height_"+label)
     _check(var_to_bytes(scene.flight_map.get("_route"))==route and scene.landmark_board._view.active,"layout_map_close_preserves_current_manual_route_"+label)
     scene.dispatch_input_action("map_toggle")
     await _layout_frames(scene)
    var engine_rect: Rect2=scene.engine_controls.get_global_rect()
    if cold:
     _check(viewport.encloses(engine_rect) and engine_rect.size==Vector2(clampf(dimensions.x/6.0,250,360),216),"layout_compact_engine_inside_"+label)
     _check(not engine_rect.intersects(map_rect),"layout_engine_locator_distinct_"+label)
    var release: Label=scene.look_release_label
    _check(release.is_visible_in_tree()==(not cold),"layout_legacy_persistent_release_expanded_engine_equivalent_"+label)
    if release.is_visible_in_tree():
     _check(viewport.encloses(release.get_global_rect()) and release.mouse_filter==Control.MOUSE_FILTER_PASS,"layout_release_inside_noninteractive_"+label)
     _check(release.text.begins_with("Look: ") and release.text.ends_with("release to use") and not release.tooltip_text.is_empty(),"layout_release_complete_action_and_full_binding_"+label)
     _check(release.get_theme_font("font").get_string_size(release.text,HORIZONTAL_ALIGNMENT_LEFT,-1,10).x<=release.size.x,"layout_release_actual_composed_font_fits_"+label)
    var stable: PackedByteArray=_presentation_bytes(scene)
    for repeat in 3: scene.layout_live_flight_aids()
    _check(_presentation_bytes(scene)==stable,"layout_identical_publication_idempotent_"+label)
    var gaze: Vector2=scene.look_angles
    scene.look_angles=Vector2(1.1,0.15)
    scene.show_state(0.0)
    _check(_presentation_bytes(scene)==stable,"layout_gaze_does_not_move_targets_"+label)
    scene.look_angles=gaze
    scene.show_state(0.0)
    _check(_snapshot(scene)==native and _ledger(scene)==ledger,"layout_view_only_full_native_mapper_recording_origin_invariant_"+label)
    await _set_layout_aid(scene,false)
    if _presentation_bytes(scene)!=off:
     print("LAYOUT_RESTORE_DIAGNOSTIC "+label+" "+JSON.stringify({"before":bytes_to_var(off),"after":bytes_to_var(_presentation_bytes(scene))}))
    _check(_presentation_bytes(scene)==off,"layout_aid_off_restores_original_map_wind_route_presentation_"+label)
    _check(scene.landmark_board._state.custom_minimum_size.y>=scene.landmark_board._state.get_line_height(),"layout_aid_off_keeps_readable_docked_route_footer_"+label)
    _check(_snapshot(scene)==native and _ledger(scene)==ledger and var_to_bytes(scene.flight_map.get("_route"))==route,"layout_aid_off_full_truth_route_invariant_"+label)
 window.size=old_size
 scene.engine_controls.set_expanded(old_expanded)
 await _layout_frames(scene)

func _persistent_release_matrix(scene: Node) -> void:
 var window: Window=scene.get_window()
 var witness: Node=UnhandledWitness.new()
 scene.add_child(witness)
 var old_size: Vector2i=window.size
 var old_mode: int=scene.camera_mode
 var profiles: Array[String]=["original-interactive-prototype"]
 if _include_piston: profiles.append("original-piston-prop-v1")
 for profile in profiles:
  if not _source(scene,profile): continue
  await _paused_native_live_aid_view(scene)
  scene.engine_controls.set_expanded(false)
  scene.circuit_aid_enabled=false
  scene.map_visible=true;scene.flight_map.show()
  scene.panel.set_help_visible(false)
  var native: PackedByteArray=_snapshot(scene)
  var ledger: PackedByteArray=_ledger(scene)
  for dimensions in [Vector2i(960,540),Vector2i(1920,1080),Vector2i(2560,1440)]:
   window.size=dimensions
   for mode in [0,3,1]:
    scene.set_camera_mode(mode)
    scene.panel.set_panel_visible(false)
    await _layout_frames(scene)
    var label: String=profile+str(dimensions)+str(mode)
    var release: Label=scene.look_release_label
    _check(release.is_visible_in_tree() and release.get_global_rect().end.y<=dimensions.y,"release_Help_off_HUD_hidden_collapsed_engine_"+label)
    _check(not scene.panel._help_visible and not scene.panel._panel_visible,"release_respects_optional_Help_and_HUD_"+label)
    _check(not release.get_global_rect().intersects(scene.flight_map.get_global_rect()),"release_clear_of_visible_locator_"+label)
    var hover: InputEventMouseMotion=InputEventMouseMotion.new()
    hover.position=release.get_global_rect().get_center()
    var event_count: int=witness.events.size()
    scene.get_viewport().push_input(hover,true)
    _check(scene.get_viewport().gui_get_hovered_control()==release and witness.events.size()==event_count+1 and witness.events.back()==hover,"release_standard_hover_reaches_unhandled_witness_"+label)
    _check(release.get_signal_connection_list("gui_input").is_empty() and release.focus_mode==Control.FOCUS_NONE,"release_has_no_GUI_handler_or_focus_"+label)
    var click: InputEventMouseButton=InputEventMouseButton.new()
    click.button_index=MOUSE_BUTTON_LEFT;click.pressed=true;click.position=hover.position
    event_count=witness.events.size()
    scene.get_viewport().push_input(click,true)
    _check(witness.events.size()==event_count+1 and witness.events.back()==click and release.get_tooltip(Vector2.ZERO)==release.tooltip_text,"release_full_tooltip_click_reaches_unhandled_witness_"+label)
    var released: InputEventMouseButton=InputEventMouseButton.new()
    released.button_index=MOUSE_BUTTON_LEFT;released.pressed=false;released.position=hover.position
    event_count=witness.events.size()
    scene.get_viewport().push_input(released,true)
    _check(witness.events.size()==event_count+1 and witness.events.back()==released,"release_button_up_reaches_unhandled_witness_"+label)
    if profile=="original-interactive-prototype" and dimensions==Vector2i(960,540) and mode==0:
     var stop: Control=Control.new()
     stop.mouse_filter=Control.MOUSE_FILTER_STOP
     stop.position=release.position;stop.size=release.size
     release.get_parent().add_child(stop)
     await _host.get_tree().process_frame
     var blocked_event: InputEventMouseMotion=InputEventMouseMotion.new()
     blocked_event.position=hover.position
     event_count=witness.events.size()
     scene.get_viewport().push_input(blocked_event,true)
     _check(scene.get_viewport().gui_get_hovered_control()==stop and witness.events.size()==event_count,"release_STOP_negative_blocks_unhandled_witness")
     stop.free()
     await _host.get_tree().process_frame
    scene.dispatch_input_action("map_toggle")
    await _layout_frames(scene)
    _check(release.is_visible_in_tree() and not scene.map_visible,"release_persists_when_map_closed_"+label)
    if mode in [0,3]:
     var expected_bottom: float=scene.engine_controls.get_global_rect().end.y if profile=="original-piston-prop-v1" else 92.0
     _check(release.position.y==expected_bottom,"release_absent_widgets_do_not_reserve_slots_"+label)
    scene.dispatch_input_action("map_toggle")
    await _layout_frames(scene)
  _check(_snapshot(scene)==native and _ledger(scene)==ledger,"release_layout_full_native_mapper_recording_origin_invariant_"+profile)
  var preset: Dictionary=scene.active_preset.duplicate(true)
  # Remove optional action as a display-boundary fixture only; no mapper apply.
  for index in range(scene.active_preset.actions.size()-1,-1,-1):
   if scene.active_preset.actions[index].id=="look_hold": scene.active_preset.actions.remove_at(index)
  scene.layout_live_flight_aids()
  _check(scene.look_release_label.text.contains("Binding unavailable") and scene.look_release_label.tooltip_text.contains("Binding unavailable"),"release_unbound_category_truthful_"+profile)
  scene.active_preset=preset
  scene.layout_live_flight_aids()
  _release_remap_boundaries(scene)
  scene.open_first_flight()
  _check(not scene.look_release_label.visible,"release_explicit_modal_owns_guidance_"+profile)
 window.size=old_size
 scene.set_camera_mode(old_mode)
 await _layout_frames(scene)
 witness.free()

func _route_tooltip_dispatch(scene: Node) -> void:
 # Use the real integrated root Window. Isolated synthetic child Windows have
 # separate DisplayServer hover routing; queued local events cannot prove it.
 var window: Window=scene.get_window()
 var old_size: Vector2i=window.size
 var old_mode: int=scene.camera_mode
 var witness: Node=UnhandledWitness.new()
 scene.add_child(witness)
 var profiles: Array[String]=["original-interactive-prototype"]
 if _include_piston: profiles.append("original-piston-prop-v1")
 window.size=Vector2i(960,540)
 for profile in profiles:
  if not _source(scene,profile): continue
  scene.dismiss_first_flight()
  scene.open_landmark_route()
  scene.choose_landmark_route([0,1])
  scene.circuit_aid_enabled=false
  scene.map_visible=true;scene.flight_map.show()
  scene.set_camera_mode(0)
  await _paused_native_live_aid_view(scene)
  _check(scene.route_view.available and scene.route_view.leg_count==2,"tooltip_actual_paused_manual_route_"+profile)
  for context in ["locator","manual_card"]:
   if context=="manual_card":
    scene.dispatch_input_action("map_toggle")
    await _layout_frames(scene)
   var target: Label=scene.flight_map._labels.status if context=="locator" else scene.landmark_board._leg_text
   var tag: String=context+"_"+profile
   _check(target.is_visible_in_tree() and target.mouse_filter==Control.MOUSE_FILTER_PASS and target.focus_mode==Control.FOCUS_NONE and target.get_signal_connection_list("gui_input").is_empty(),"tooltip_actual_production_label_no_handler_focus_"+tag)
   _check(target.tooltip_text.contains(scene.route_view.route_labels[1]),"tooltip_complete_secondary_itinerary_"+tag)
   var native: PackedByteArray=_snapshot(scene)
   var ledger: PackedByteArray=_ledger(scene)
   var copied: PackedByteArray=var_to_bytes([scene.route_view,scene.flight_map._route,scene.flight_map._manual_summary,scene.landmark_board._view,scene.collect_input_raw()])
   for kind in ["motion","press","release"]:
    var event: InputEvent
    if kind=="motion":
     var motion: InputEventMouseMotion=InputEventMouseMotion.new()
     motion.position=target.get_global_rect().get_center()
     event=motion
    else:
     var button: InputEventMouseButton=InputEventMouseButton.new()
     button.position=target.get_global_rect().get_center()
     button.button_index=MOUSE_BUTTON_LEFT;button.pressed=kind=="press"
     event=button
    var before: int=witness.events.size()
    window.push_input(event,true)
    _check(window.gui_get_hovered_control()==target and target.get_tooltip(Vector2.ZERO)==target.tooltip_text,"tooltip_actual_root_hover_and_full_hint_"+tag+kind)
    _check(witness.events.size()==before+1 and witness.events.back()==event,"tooltip_actual_event_reaches_nonconsuming_witness_"+tag+kind)
    _check(_snapshot(scene)==native and _ledger(scene)==ledger and var_to_bytes([scene.route_view,scene.flight_map._route,scene.flight_map._manual_summary,scene.landmark_board._view,scene.collect_input_raw()])==copied,"tooltip_full_native_Raw_mapper_recording_origin_route_invariant_"+tag+kind)
   var stop: Control=Control.new()
   stop.mouse_filter=Control.MOUSE_FILTER_STOP
   stop.position=target.get_global_rect().position;stop.size=target.size
   stop.z_index=100
   scene.look_release_label.get_parent().add_child(stop)
   await _host.get_tree().process_frame
   for kind in ["motion","press","release"]:
    var event: InputEvent
    if kind=="motion":
     var motion: InputEventMouseMotion=InputEventMouseMotion.new()
     motion.position=stop.get_global_rect().get_center();event=motion
    else:
     var button: InputEventMouseButton=InputEventMouseButton.new()
     button.position=stop.get_global_rect().get_center()
     button.button_index=MOUSE_BUTTON_LEFT;button.pressed=kind=="press";event=button
    var before: int=witness.events.size()
    window.push_input(event,true)
    _check(window.gui_get_hovered_control()==stop and witness.events.size()==before,"tooltip_root_STOP_negative_blocks_"+tag+kind)
   stop.free()
   await _host.get_tree().process_frame
   _check(_snapshot(scene)==native and _ledger(scene)==ledger and var_to_bytes([scene.route_view,scene.flight_map._route,scene.flight_map._manual_summary,scene.landmark_board._view,scene.collect_input_raw()])==copied,"tooltip_root_negative_full_authority_invariant_"+tag)
 witness.free()
 window.size=old_size
 scene.set_camera_mode(old_mode)
 await _layout_frames(scene)

func _release_remap_boundaries(scene: Node) -> void:
 var saved: Dictionary=scene.active_preset.duplicate(true)
 var look_index: int=-1
 for index in saved.actions.size():
  if saved.actions[index].id=="look_hold": look_index=index
 _check(look_index>=0,"release_remap_existing_action_precondition")
 if look_index<0: return
 for kind in ["physical4","joy4"]:
  var preset: Dictionary=saved.duplicate(true)
  var sources: Array=[]
  if kind=="joy4": preset.devices=[]
  for index in 4:
   if kind=="physical4":
    sources.append({"kind":"physical_keys","keys":[int(KEY_F13)+index*4,int(KEY_F13)+index*4+1,int(KEY_F13)+index*4+2,int(KEY_F13)+index*4+3]})
   else:
    var slot: String=("layout-slot-"+str(index)).rpad(32,"X")
    preset.devices.append({"slot":slot,"label":"Configured fixture only","match":{"guid":"fixture","name":"fixture","vendor_id":"","product_id":""}})
    sources.append({"kind":"joy_button","slot":slot,"index":index})
  preset.actions[look_index].sources=sources
  var checked: Dictionary=Preset.validate_preset_v2(preset) if preset.version==2 else Preset.validate_preset(preset)
  _check(checked.ok,"release_remap_maximum_fixture_validated_"+kind)
  if not checked.ok: continue
  # Display-boundary fixture only; never apply/suspend/sample this preset.
  scene.active_preset=checked.value.duplicate(true)
  scene.layout_live_flight_aids()
  var release: Label=scene.look_release_label
  _check(release.text.begins_with("Look: ") and release.text.ends_with("release to use"),"release_remap_action_never_shortens_"+kind)
  _check(release.get_theme_font("font").get_string_size(release.text,HORIZONTAL_ALIGNMENT_LEFT,-1,10).x<=release.size.x,"release_remap_actual_compacted_font_fits_"+kind)
  for source in sources:
   _check(release.tooltip_text.contains(source.slot if kind=="joy4" else OS.get_keycode_string(source.keys[3])),"release_remap_full_alias_synchronous_"+kind)
  if kind=="joy4": _check(release.tooltip_text.contains("CONFIGURED") and release.tooltip_text.contains("availability unverified"),"release_remap_does_not_claim_connected_device")
 scene.active_preset=saved
 scene.layout_live_flight_aids()

func _missing_facade_presentation(scene: Node) -> void:
 # Explicit missing-host presentation fixture; the real worker is retained and
 # restored without closing/advancing it, then joined by ordinary cleanup.
 var profiles: Array[String]=["original-interactive-prototype"]
 if _include_piston: profiles.append("original-piston-prop-v1")
 for profile in profiles:
  if not _source(scene,profile): continue
  await _paused_native_live_aid_view(scene)
  scene.circuit_aid_enabled=true
  scene.show_state(0.0)
  var actual: RefCounted=scene.facade
  var native: PackedByteArray=_snapshot(scene)
  var ledger: PackedByteArray=_ledger(scene)
  scene.facade=null
  scene.show_state(0.0)
  _check(scene.shared_readings.state in ["empty","invalid"] and scene.panel._readings.valid==false and scene.cockpit_panel._readings.valid==false,"missing_host_clears_native_reading_presentation_"+profile)
  _check(scene.flight_map._wind_cue.state in ["empty","invalid"] and not scene.windsock_visual.visible,"missing_host_clears_prior_wind_and_sock_"+profile)
  _check(not scene.flight_map._valid and scene.flight_map._route.is_empty() and not scene.landmark_board._view.available,"missing_host_has_no_current_geographic_guidance_"+profile)
  _check(scene.look_release_label.is_visible_in_tree() and not scene.engine_controls.visible,"missing_host_preserves_release_without_engine_"+profile)
  if profile=="original-piston-prop-v1": _check(scene.engine_status.state in ["empty","invalid"],"missing_host_clears_engine_feedback_source")
  scene.facade=actual
  scene.show_state(0.0)
  _check(_snapshot(scene)==native and _ledger(scene)==ledger,"missing_host_display_fixture_no_native_mapper_recording_origin_mutation_"+profile)

func _closed_failure(scene: Node) -> void:
 if not _source(scene,"original-interactive-prototype"): return
 var prior: String=scene.adopted_session_id
 var old_adapter: RefCounted=scene.observed_adapters.back()
 scene.dismiss_first_flight()
 scene.open_landmark_route()
 scene.choose_landmark_route([0,1])
 scene.map_visible=true
 scene.flight_map.show()
 scene.open_first_flight()
 scene.on_circuit_enabled(true,scene.first_flight_source_session(),scene.first_flight_panel)
 scene.show_state(0.0)
 _check(scene.landmark_board._summary_in_map and not scene.landmark_board._card.visible and not scene.flight_map.get("_route").is_empty(),"post_close_failure_real_route_summary_precondition")
 scene.inject_next_open_failure=true
 scene.expect_injected_open_failure=true
 scene.on_first_flight_choice("ready-flight",prior,scene.first_flight_panel)
 var rb: Dictionary=scene.facade.readback()
 _check(scene.expected_failures==["Native initialization or pinned identity validation failed"],"named_expected_post_open_fault_observed")
 _check(old_adapter.entries.back().method=="close" and old_adapter.entries.back().reply.get("joined")==true,"post_close_failure_old_worker_joined")
 var failed_adapter: RefCounted=scene.observed_adapters.back()
 _check(failed_adapter.entries.front().method=="open_session" and failed_adapter.entries.front().reply.get("ok")==true and failed_adapter.entries.back().method=="close" and failed_adapter.entries.back().reply.get("joined")==true,"injected_new_worker_really_opened_then_joined")
 _check(rb.host_mode=="closed" and not rb.native_live and rb.historical and scene.review_joined and not scene.initializing_recording and scene.first_flight_source_session()=="","post_close_failure_reports_joined_closed_truth")
 _check(scene.flight_map.get("_circuit").is_empty() and not scene.circuit_card._view.available,"post_close_failure_no_stale_circuit")
 _check(scene.flight_map.get("_route").is_empty() and not scene.landmark_board._view.available,"post_close_failure_retires_current_geographic_guidance")
 var closed: PackedByteArray=var_to_bytes(rb)
 var ledger: PackedByteArray=_ledger(scene)
 scene.on_first_flight_choice("ready-flight",prior,scene.first_flight_panel)
 scene.on_circuit_enabled(true,prior,scene.first_flight_panel)
 _check(var_to_bytes(scene.facade.readback())==closed and _ledger(scene)==ledger,"old_nonempty_session_rejected_after_closed_failure")
 # Joined empty-source presentation is a deliberate supported recovery path.
 scene.open_first_flight()
 scene.on_first_flight_choice("ready-flight","",scene.first_flight_panel)
 _assert_new(scene,CHOICES[1],prior,"joined_failure_explicit_recovery")

func run(host: Node,include_piston: bool=true) -> Dictionary:
 _host=host
 _include_piston=include_piston
 var previous_mode: int=Input.mouse_mode
 var scene: Node=SyntheticScene.new()
 host.add_child(scene)
 scene.set_process(false);scene.set_process_input(false)
 scene.set_process_unhandled_input(false);scene.set_process_unhandled_key_input(false)
 if scene.sound!=null: scene.sound.set_process(false)
 var initialized: bool=scene.facade!=null and scene.facade.readback().aircraft!=null and scene.first_flight_panel!=null
 _check(initialized,"actual_native_and_briefing_initialized")
 if initialized:
  _immediate_matrix(scene)
  _paused_invariance(scene)
  _reject_requests(scene)
  _advanced_discard(scene)
  _actual_origin_rebase(scene)
  await _layout_matrix(scene)
  await _persistent_release_matrix(scene)
  await _route_tooltip_dispatch(scene)
  await _missing_facade_presentation(scene)
  _modal_input(scene)
  if not _include_piston: _legacy_cold_rejection(scene)
  _closed_failure(scene)
 _check(scene.close_session(),"actual_worker_joined")
 if scene.sound!=null: _check(bool(await scene.sound.shutdown()),"actual_audio_retired")
 scene.free()
 Input.mouse_mode=previous_mode
 return {"passed":_failures.is_empty(),"checks":_checks,"failures":_failures.duplicate(),"adoptions":_adoptions.duplicate(true),"include_piston":_include_piston,
  "route_scope":"coupled: all six same/cross-profile choices and three advanced confirmations" if _include_piston else "upstream: four legacy start mappings, two advanced confirmations and explicit cold admission rejection; cold runtime is not qualified",
  "scope":"Actual native lifecycle and complete synthetic Raw; no hardware/pilot, physics tolerance, procedure, GPU or phase acceptance"}
