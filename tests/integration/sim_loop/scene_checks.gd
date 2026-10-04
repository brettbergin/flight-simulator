extends RefCounted
# Original MIT. Actual controller/native fixtures; injected faults are synthetic.
# Run on a settled main-thread Node in an isolated staged project, no --smoke.
const Scene = preload("res://simulation/flight_scene.gd")
const Facade = preload("res://simulation/session_facade.gd")
const Participant = preload("res://simulation/origin_participant.gd")
const Frames = preload("res://simulation/canonical_frames.gd")
class CommitFault extends Participant:
 func commit_origin(_plan: Dictionary) -> Dictionary:
  return {"ok":false,"error":"Declared synthetic scene commit fault"}
class FacadeCallback extends Participant:
 var facade: RefCounted
 var phase: String="prepare"
 var observation: Dictionary={}
 func _ledger() -> Dictionary:
  var result: Dictionary={}
  for key in ["_truth","_pending","_admitted","_commands","_events","_complete","_admission","_rejection","_completed","_command_sequence","_lifecycle_sequence","_pending_commands","_pending_events","_previous","_current","_previous_tick"]:
   var value: Variant=facade.get(key)
   result[key]=value.duplicate(true) if value is Dictionary or value is Array else value
  return result
 func _attempt() -> void:
  var native: RefCounted=facade.get("_bridge")
  var native_before: Dictionary=native.call("read_state").duplicate(true)
  var before: Dictionary=_ledger()
  var axes: Dictionary=before._truth.held_axes.duplicate(true)
  axes.throttle=0.9
  var results: Array=[facade.set_axes(axes),facade.advance_wall_us(25000),facade.set_paused(true),facade.set_time_scale(2.0),facade.close(),facade.reset("ground-ready")]
  var rejected: bool=true
  for result in results:
   rejected=rejected and not result.ok and result.completed==0 and result.applied_commands.is_empty() and result.events.is_empty() and result.admission=="rejected" and result.native_rejection==null and not result.error.is_empty()
  var blocked_read: Dictionary=facade.readback()
  var blocked_visual: Dictionary=facade.visual_pose()
  observation={"native_unchanged_inside_callback":native.call("read_state")==native_before,"ledger_unchanged_inside_callback":_ledger()==before,"all_mutators_rejected":rejected,"readback_rejected":blocked_read.historical and not blocked_read.error.is_empty(),"visual_rejected":not blocked_visual.valid,"native_before_tick":before._truth.tick}
 func prepare_origin(candidate: Dictionary) -> Dictionary:
  var plan: Dictionary=super.prepare_origin(candidate)
  if phase=="prepare": _attempt()
  return plan
 func commit_origin(plan: Dictionary) -> Dictionary:
  if phase=="commit": _attempt()
  return super.commit_origin(plan)

func _ecef_offset(anchor: Array, rotation: Array, eus: Array) -> Array:
 var result: Array=[]
 for axis in 3:
  result.append(float(anchor[axis])+float(rotation[axis])*float(eus[0])+float(rotation[3+axis])*float(eus[1])+float(rotation[6+axis])*float(eus[2]))
 return result
func _hidden(scene: Node3D) -> bool:
 return not scene.airplane.visible and not scene.cockpit.root.visible and not scene.world_root.visible and not scene.light_root.visible
func run(host: Node) -> Dictionary:
 var scene: Node3D=Scene.new()
 host.add_child(scene)
 scene.set_process(false)
 scene.menu.hide()
 scene.menu_open=false
 host.check(scene.facade!=null and scene.facade.readback().host_mode=="paused","scene_actual_start_owned_worker_paused")
 var truth: Dictionary=scene.facade.readback()
 if truth.aircraft==null:
  host.check(false,"scene_actual_initial_publication_available")
  if scene.sound!=null: await scene.sound.call("shutdown")
  scene.free()
  return {"scope":"actual-scene-integration","initialized":false}
 host.check(scene.pause_session(false) and scene.submit_axes(scene.controls) and scene.advance_wall_us(25000) and scene.snapshot.tick=="3", "scene_actual_controller_advances_three_authoritative_ticks")
 host.check(scene.pause_session(true) and scene.facade.readback().debt_quanta==0, "scene_actual_controller_pause_drains_at_completed_boundary")
 # Minimum-window layout and real lifecycle pacing through UI handlers.
 var window: Window=scene.get_window()
 var prior_window_size: Vector2i=window.size
 window.size=Vector2i(960,540)
 await host.get_tree().process_frame
 scene.open_menu("Scene input/layout fixture")
 scene.show_state(0.0)
 await host.get_tree().process_frame
 scene.layout_flight_menu()
 var viewport_bounds: Rect2=scene.get_viewport().get_visible_rect()
 var menu_bounds: Rect2=scene.menu.get_global_rect()
 host.check(viewport_bounds.size==Vector2(960,540) and viewport_bounds.encloses(menu_bounds),"scene_actual_minimum_960x540_menu_inside_viewport")
 var buttons_inside: bool=true
 for button in scene.menu.find_children("*","Button",true,false):
  buttons_inside=buttons_inside and viewport_bounds.encloses(button.get_global_rect()) and menu_bounds.encloses(button.get_global_rect())
 host.check(buttons_inside and scene.speed_button.visible and scene.speed_button.get_global_rect().size.y>0,"scene_actual_minimum_menu_buttons_including_speed_are_visible")
 scene.menu_open=false
 scene.menu.hide()
 host.check(scene.pause_session(false) and scene.advance_wall_us(2000) and scene.pause_session(true),"scene_actual_fractional_debt_fixture_paused")
 var speed_before: Dictionary=scene.facade.readback()
 var intent_before: Dictionary=scene.controls.duplicate(true)
 var submitted_before: int=scene.submitted_count
 var pending_events_before: int=scene.event_count
 var faster:=InputEventKey.new()
 faster.pressed=true
 faster.physical_keycode=KEY_F6
 scene._unhandled_key_input(faster)
 var faster_state: Dictionary=scene.facade.readback()
 host.check(faster_state.time_scale==2.0 and faster_state.tick==speed_before.tick and faster_state.debt_quanta==960000 and faster_state.aircraft==speed_before.aircraft and faster_state.held_axes==speed_before.held_axes and scene.controls==intent_before and scene.submitted_count==submitted_before,"scene_actual_F6_paused_scale_preserves_native_trim_intent_tick_fractional_debt")
 var slower:=InputEventKey.new()
 slower.pressed=true
 slower.physical_keycode=KEY_F5
 scene._unhandled_key_input(slower)
 var slower_state: Dictionary=scene.facade.readback()
 host.check(slower_state.time_scale==1.0 and slower_state.tick==speed_before.tick and slower_state.debt_quanta==speed_before.debt_quanta and slower_state.aircraft==speed_before.aircraft and scene.controls==intent_before and scene.event_count==pending_events_before,"scene_actual_F5_paused_cycle_preserves_truth_and_does_not_invent_events")
 var resumed: bool=scene.pause_session(false)
 var speed_delivery: Dictionary=scene.facade.advance_wall_us(8334)
 scene.adopt_result(speed_delivery)
 host.check(resumed and speed_delivery.ok and speed_delivery.completed==1,"scene_actual_speed_cycle_delivers_lifecycle_on_next_native_tick")
 var payloads: Array=[]
 for observed in speed_delivery.events:
  payloads.append(observed.payload)
 host.check(payloads==[{"kind":"time-scale","scale":2.0},{"kind":"time-scale","scale":1.0},{"kind":"pause","paused":false}],"scene_actual_UI_speed_acknowledgements_match_ordered_native_operational_events")
 var speed_after: Dictionary=scene.facade.readback()
 host.check(speed_after.tick=="4" and speed_after.debt_quanta==960320 and speed_after.time_scale==1.0 and speed_after.held_axes.trim==speed_before.held_axes.trim and scene.event_count==pending_events_before+3,"scene_actual_scale_scale_resume_events_observed_with_exact_debt_and_unchanged_trim")
 host.check(scene.pause_session(true),"scene_actual_speed_fixture_pauses_at_new_completed_tick")
 window.size=prior_window_size
 await host.get_tree().process_frame
 scene.set_camera_mode(2)
 scene.show_state(0.0)
 var registry: RefCounted=scene.facade.render_origin
 var origin: Dictionary=registry.read_origin()
 host.check(origin.valid and origin.active_ids==["camera","cockpit","lighting","ownship","world"] and origin.absent_categories==["local_particles","spatial_audio"],"scene_actual_all_origin_categories_declared")
 var roots: Array=[scene.airplane,scene.cockpit.root,scene.camera,scene.world_root,scene.light_root]
 var siblings: bool=true
 for item in roots:
  siblings=siblings and item.get_parent()==scene
  for other in roots:
   if item!=other: siblings=siblings and not item.is_ancestor_of(other)
 host.check(siblings,"scene_actual_nonoverlapping_sibling_roots")
 host.check(scene.sound.player is AudioStreamPlayer and not scene.sound.player is AudioStreamPlayer3D,"scene_actual_audio_explicitly_nonspatial")
 var body_before: Transform3D=scene.airplane.transform
 var camera_offset: Vector3=scene.camera.position-scene.airplane.position
 var map_before: Vector2=scene.flight_map.get("_position")
 var commands_before: int=scene.submitted_count
 var native_before: Dictionary=scene.facade.readback()
 var candidate: Array=_ecef_offset(scene.prepared.ecef,scene.prepared.rotation,[750.0,250.0,-100.0])
 var rebase: Dictionary=registry.rebase(candidate)
 scene.show_state(0.0)
 host.check(rebase.ok and scene.facade.readback()==native_before and scene.submitted_count==commands_before,"scene_actual_horizontal_vertical_origin_preserves_native_and_commands")
 var shift:=Vector3(750.0,250.0,-100.0)
 host.check((scene.airplane.position-(body_before.origin-shift)).length()<0.0001 and scene.airplane.basis.is_equal_approx(body_before.basis),"scene_actual_body_uses_canonical_origin_projection")
 host.check((scene.camera.position-scene.airplane.position-camera_offset).length()<0.0001,"scene_actual_camera_body_share_translation_phase")
 host.check(scene.flight_map.get("_position")==map_before,"scene_actual_map_retains_raw_prepared_anchor_position")
 var floor: Array=Frames.project(scene.prepared.ecef,candidate,scene.prepared.rotation)
 host.check(absf(float(floor[1])+250.0)<0.000001 and scene.camera.position.y>=float(floor[1])+0.35-0.0001,"scene_actual_orbit_clearance_uses_shifted_canonical_plane")
 host.check(scene.world_root.position.distance_to(-shift)<0.0001 and scene.light_root.position.distance_to(-shift)<0.0001,"scene_actual_world_light_adopt_same_origin")
 var old_session: String=truth.session_id
 host.check(scene.restart(true),"scene_actual_reset_joins_then_initializes")
 scene.set_process(false)
 scene.show_state(0.0)
 var fresh: Dictionary=scene.facade.readback()
 host.check(fresh.session_id!=old_session and fresh.tick=="0" and scene.facade.render_origin!=registry and scene.facade.render_origin.read_origin().committed.version=="1","scene_actual_reset_fresh_session_registry_version")
 host.check(scene.world_root.position==Vector3.ZERO and scene.light_root.position==Vector3.ZERO,"scene_actual_reset_clears_prior_origin_translations")
 var fresh_native: Dictionary=fresh.duplicate(true)
 var fresh_body: Transform3D=scene.airplane.transform
 host.check(not registry.rebase(scene.prepared.ecef).ok and scene.facade.readback()==fresh_native and scene.airplane.transform==fresh_body,"scene_actual_old_registry_plan_cannot_rebind_new_session")
 # Native-writing facade callbacks are prohibited in both transaction stages.
 # Direct read_state calls inside the fixture are observers, not solver writes.
 for callback_phase in ["prepare","commit"]:
  if callback_phase=="commit":
   host.check(scene.restart(true),"scene_callback_reset_between_transaction_stages")
   scene.set_process(false)
   scene.show_state(0.0)
  host.check(scene.pause_session(false),"scene_callback_"+callback_phase+"_starts_explicitly_live")
  var callback_truth: Dictionary=scene.facade.readback()
  host.check(callback_truth.host_mode=="live" and not callback_truth.paused,"scene_callback_"+callback_phase+"_would_integrate_without_entry_guard")
  var body_at_entry: Transform3D=scene.airplane.transform
  var world_at_entry: Transform3D=scene.world_root.transform
  scene.world_root.set_script(null)
  scene.world_root.set_script(FacadeCallback)
  scene.world_root.set("facade",scene.facade)
  scene.world_root.set("phase",callback_phase)
  scene.world_root.call("configure",callback_truth.session_id,scene.prepared.ecef,scene.prepared.rotation,[0.0,0.0,0.0],Basis.IDENTITY)
  var callback_result: Dictionary=scene.facade.render_origin.rebase(_ecef_offset(scene.prepared.ecef,scene.prepared.rotation,[10.0,3.0,5.0]))
  var observed: Dictionary=scene.world_root.get("observation")
  host.check(not callback_result.ok and observed.get("native_unchanged_inside_callback",false) and observed.get("ledger_unchanged_inside_callback",false) and observed.get("all_mutators_rejected",false) and observed.get("readback_rejected",false) and observed.get("visual_rejected",false),"scene_actual_"+callback_phase+"_facade_reentry_rejects_native_writes_and_ledger_changes")
  if callback_phase=="prepare":
   host.check(scene.facade.render_origin.read_origin().valid and scene.airplane.transform==body_at_entry and scene.world_root.transform==world_at_entry and scene.facade.readback()==callback_truth,"scene_actual_prepare_callback_failure_preserves_coherent_scene_native_truth")
   # Recovery belongs after the transaction and legitimately accepts a pause.
   scene.facade.call("_origin_pause","Declared synthetic callback prepare rejection")
   host.check(scene.facade.readback().host_mode=="paused" and scene.facade.readback().tick==callback_truth.tick and scene.facade.readback().native_live,"scene_actual_prepare_callback_recovery_pauses_only_after_transaction")
  else:
   var stopped: Dictionary=scene.facade.advance_wall_us(0)
   scene.adopt_result(stopped)
   scene.show_state(0.0)
   host.check(not stopped.ok and stopped.readback.host_mode=="discarded" and not stopped.readback.native_live and stopped.readback.tick==callback_truth.tick and _hidden(scene),"scene_actual_commit_callback_terminal_recovery_joins_after_transaction_without_step")
 host.check(scene.restart(true),"scene_actual_reset_after_callback_faults")
 scene.set_process(false)
 host.check(scene.pause_session(true),"scene_actual_pause_before_synthetic_origin_commit_fault")
 scene.show_state(0.0)
 var fault_truth: Dictionary=scene.facade.readback()
 scene.world_root.set_script(null)
 scene.world_root.set_script(CommitFault)
 scene.world_root.call("configure",fault_truth.session_id,scene.prepared.ecef,scene.prepared.rotation,[0.0,0.0,0.0],Basis.IDENTITY)
 var failed: Dictionary=scene.facade.render_origin.rebase(_ecef_offset(scene.prepared.ecef,scene.prepared.rotation,[10.0,3.0,5.0]))
 var terminal: Dictionary=scene.facade.advance_wall_us(0)
 scene.adopt_result(terminal)
 scene.show_state(0.0)
 host.check(not failed.ok and not terminal.ok and terminal.readback.host_mode=="discarded" and not terminal.readback.native_live and terminal.readback.tick==fault_truth.tick,"scene_actual_paused_commit_fault_stops_and_joins_without_tick")
 host.check(_hidden(scene) and not scene.facade.visual_pose().valid,"scene_actual_partial_commit_failure_hides_all_geometry")
 host.check(scene.restart(true),"scene_actual_reset_reconstructs_faulted_adapters")
 scene.set_process(false)
 scene.show_state(0.0)
 var retained: Dictionary=scene.snapshot.duplicate(true)
 var closed: Dictionary=scene.facade.close()
 scene.adopt_result(closed)
 scene.show_state(0.0)
 host.check(closed.ok and _hidden(scene) and scene.snapshot==retained,"scene_actual_closed_retained_publication_hides_geometry")
 # Reproduce failed fresh start while the view still retains its old snapshot.
 scene.facade=Facade.new()
 scene.bridge=scene.facade
 var rejected: Dictionary=scene.facade.start("res://synthetic-missing-model","ground-ready")
 scene.adopt_result(rejected)
 scene.show_state(0.0)
 host.check(not rejected.ok and rejected.readback.canonical==null and _hidden(scene) and scene.snapshot==retained,"scene_actual_failed_start_does_not_render_stale_snapshot")
 scene.snapshot={}
 scene.show_state(0.0)
 host.check(_hidden(scene),"scene_actual_empty_start_hides_all_geometry")
 host.check(scene.close_session(),"scene_actual_fixture_close_join")
 if scene.sound!=null:
  host.check(bool(await scene.sound.call("shutdown")),"scene_actual_fixture_audio_retired")
 scene.free()
 return {"scope":"Actual staged controller/native scene; synthetic commit/start faults, no pilot or GPU qualification","initial_tick":truth.tick,"fresh_tick":fresh.tick,"origin_shift_eus_m":[750.0,250.0,-100.0],"native_records_unchanged_by_rebase":true}
