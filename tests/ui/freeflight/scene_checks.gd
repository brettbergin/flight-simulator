extends RefCounted
# Original MIT. Actual accepted legacy worker with synthetic released input.
# Counting wrapper observes calls; it neither changes replies nor owns a solver.
const Scene = preload("res://simulation/flight_scene.gd")
class SyntheticScene extends Scene:
	var synthetic_raw: Dictionary={"keys":[],"mouse_buttons":[],"devices":[]}
	func collect_input_raw(_preset: Dictionary={}) -> Dictionary:
		return synthetic_raw.duplicate(true)
class CountedBridge extends RefCounted:
	var native: RefCounted
	var submitted: Array=[]
	var lifecycle: Array=[]
	var requested: Array=[]
	var completed := 0
	var closes := 0
	var joined := false
	func _init(existing: RefCounted) -> void:
		native=existing
	func open_session(model_root: String, start: String, wind_profile: Variant="calm", profile_id: Variant="original-interactive-prototype") -> Dictionary:
		return native.call("open_session",model_root,start,wind_profile,profile_id)
	func read_state() -> Dictionary:
		return native.call("read_state")
	func submit(command: Dictionary) -> Dictionary:
		submitted.append(command.duplicate(true))
		return native.call("submit",command)
	func session_control(command: Dictionary) -> Dictionary:
		lifecycle.append(command.duplicate(true))
		return native.call("session_control",command)
	func step_fixed(count: int) -> Dictionary:
		requested.append(count)
		var result: Dictionary=native.call("step_fixed",count)
		completed+=int(result.get("completed",0))
		return result
	func close() -> Dictionary:
		closes+=1
		var result: Dictionary=native.call("close")
		joined=result.get("ok")==true and result.get("joined")==true
		return result
	func writes() -> Dictionary:
		return {"submitted":submitted.duplicate(true),"lifecycle":lifecycle.duplicate(true),"requested":requested.duplicate(true),"completed":completed,"closes":closes}
var checks := 0
var failures: Array[String]=[]
var _host: Node
var _observed: CountedBridge
func _check(ok: bool, label: String) -> void:
	checks+=1
	if not ok:
		failures.append(label)
	_host.call("check",ok,"landmark_scene_"+label)
func _properties(object: Object, names: Array) -> Dictionary:
	var copied: Dictionary={}
	for name in names:
		var value: Variant=object.get(name)
		copied[name]=value.duplicate(true) if value is Dictionary or value is Array else value
	return copied
func _capture(scene: Node) -> Dictionary:
	return {"readback":scene.facade.readback(),"mapper":_properties(scene.mapper,["_preset","_values","_start","_pins","_edges","_takeover","_configured","_live","_brake_hold"]),"map":_properties(scene.flight_map,["_session","_sample_tick","_trail","_position","_direction","_valid","_heading_valid","_paused","_retained","_clearance_valid","_clearance_m","extent_m","_landmarks"]),"origin":scene.facade.render_origin.read_origin(),"camera":scene.camera.transform,"camera_fov":scene.camera.fov,"camera_mode":scene.camera_mode,"submitted":scene.submitted_count,"events":scene.event_count,"bridge_writes":_observed.writes()}
func _unchanged(scene: Node, baseline: Dictionary, label: String) -> void:
	scene.show_state(0.0)
	_check(_capture(scene)==baseline,label+"_complete_native_mapper_origin_camera_map_invariant")
func _retire(scene: Node) -> void:
	if scene.facade!=null:
		_check(scene.close_session(),"final_owned_worker_joined")
	if scene.sound!=null:
		_check(bool(await scene.sound.call("shutdown")),"owned_audio_thread_joined")
	scene.free()
func run(host: Node) -> Dictionary:
	_host=host
	var scene: Node=SyntheticScene.new()
	host.add_child(scene)
	scene.set_process(false)
	_check(scene.facade!=null and scene.mapper!=null and scene.landmark_board!=null,"actual_default_worker_mapper_board")
	if scene.facade==null or scene.mapper==null or scene.landmark_board==null or scene.facade.readback().aircraft==null:
		await _retire(scene)
		return _receipt()
	_observed=CountedBridge.new(scene.facade._bridge)
	scene.facade._bridge=_observed
	scene.show_state(0.0)
	_check(scene.facade.readback().host_mode=="paused","actual_initial_native_paused")
	_check(scene.flight_map._valid and scene.flight_map._paused and not scene.flight_map._retained and not scene.flight_map._runway_metrics().is_empty(),"actual_paused_map_current_not_stopped_with_runway_geometry")
	_check(scene.landmark_board._landmarks==scene.flight_map._landmarks and scene.landmark_board._landmarks.size()==6,"exact_rendered_six_landmark_metadata")
	var baseline: Dictionary=_capture(scene)
	scene.open_landmark_route()
	_check(scene.route_open and scene.landmark_board._chooser.visible and not scene.menu.visible,"paused_open_chooser")
	_unchanged(scene,baseline,"paused_open")
	scene.choose_landmark_route([0,1,5])
	_check(not scene.route_open and scene.menu.visible and scene.route_view.target_label=="East Farm","choose_returns_paused_menu_with_first_leg")
	_unchanged(scene,baseline,"paused_choose")
	_check(scene.flight_map._valid and scene.flight_map._paused and not scene.flight_map._retained and not scene.flight_map._route.is_empty() and scene.flight_map._route.label=="East Farm" and scene.flight_map._route.target==Vector2(850,-650) and not scene.flight_map._runway_metrics().is_empty(),"actual_paused_route_map_target_and_runway_guidance_visible")
	for index in 2:
		scene.open_landmark_route()
		scene.next_landmark_leg()
		_check(scene.route_view.leg_index==index+1,"paused_manual_next_"+str(index))
		_unchanged(scene,baseline,"manual_next_"+str(index))
	scene.set_route_aids_visible(false)
	_check(scene.flight_map._route.is_empty() and not scene.landmark_board._card.visible,"hide_both_optional_aids")
	_unchanged(scene,baseline,"hide_aids")
	scene.set_route_aids_visible(true)
	_check(not scene.flight_map._route.is_empty(),"restore_current_map_target")
	_unchanged(scene,baseline,"show_aids")
	for runway in [36,18]:
		scene.open_landmark_route()
		scene.return_to_runway(runway)
		_check(scene.route_view.target_anchor_eus_m==[0.0,0.0,100.0 if runway==36 else -1700.0],"return_pavement_end_"+str(runway))
		_check(scene.flight_map._runway==runway,"selected_map_runway_matches_return_"+str(runway))
		_unchanged(scene,baseline,"return_"+str(runway))
	scene.open_landmark_route()
	scene.stop_landmark_route()
	_check(not scene.route_view.active and scene.flight_map._route.is_empty() and scene.flight_map._runway==18,"stop_current_itinerary_only")
	_unchanged(scene,baseline,"stop")
	scene.open_landmark_route()
	var key:=InputEventKey.new()
	key.physical_keycode=KEY_W
	key.pressed=true
	scene._unhandled_key_input(key)
	_unchanged(scene,baseline,"modal_throttle_key_no_intent")
	key.physical_keycode=KEY_ESCAPE
	scene._unhandled_key_input(key)
	_check(not scene.route_open and scene.menu.visible and scene.paused,"escape_returns_to_menu_without_resume")
	_unchanged(scene,baseline,"escape")
	scene.open_landmark_route()
	scene.choose_landmark_route([0,1])
	var raw_before: Dictionary=scene.facade.readback()
	var before_view: Dictionary=scene.route_view.duplicate(true)
	var before_calls: Dictionary=_observed.writes()
	scene.update_canonical_scene_sources()
	var origin_point: Array=raw_before.canonical.ecef_position_m.duplicate()
	var rotation: Array=scene.prepared.rotation
	for component in 3:
		origin_point[component]+=rotation[component]*600.0+rotation[3+component]*125.0+rotation[6+component]*800.0
	var rebased: Dictionary=scene.facade.render_origin.rebase(origin_point)
	_check(rebased.ok,"actual_horizontal_vertical_origin_rebase")
	scene.show_state(0.0)
	_check(scene.facade.readback()==raw_before and _observed.writes()==before_calls and scene.route_view==before_view,"rebase_preserves_raw_native_and_anchor_guidance")
	_check(scene.flight_map._position==baseline.map._position,"rebase_map_uses_raw_original_anchor")
	_check(scene.pause_session(false),"explicit_resume_before_live_open")
	scene.menu_open=false
	scene.menu.hide()
	scene.show_state(0.0)
	var live: Dictionary=scene.facade.readback()
	var live_calls: Dictionary=_observed.writes()
	scene.open_landmark_route()
	var after_open: Dictionary=scene.facade.readback()
	_check(scene.route_open and after_open.host_mode=="paused" and after_open.tick==live.tick and after_open.aircraft==live.aircraft and after_open.atmosphere==live.atmosphere and after_open.held_axes==live.held_axes,"live_open_only_existing_pause_no_solver_tick")
	_check(_observed.lifecycle.size()==live_calls.lifecycle.size()+1 and _observed.submitted.size()==live_calls.submitted.size() and _observed.completed==live_calls.completed,"live_open_exact_pause_no_axes_or_integration")
	scene.synthetic_raw.keys=[KEY_W]
	scene.process_input_interval(25000)
	_check(scene.facade.readback().tick==live.tick and not scene.pause_session(false),"modal_held_throttle_cannot_leak_or_resume")
	scene.synthetic_raw.keys=[]
	scene.dismiss_landmark_route()
	_check(scene.pause_session(false),"explicit_released_input_resume")
	scene.menu_open=false
	scene.menu.hide()
	scene.process_input_interval(25000)
	scene.show_state(0.0)
	_check(scene.facade.readback().tick=="3" and _observed.completed==3,"only_explicit_interval_runs_three_actual_ticks")
	_check(scene.route_view.target_label=="East Farm" and scene.route_view.leg_index==0,"route_remains_manual_during_actual_flight")
	_check(scene.pause_session(true),"pause_before_fresh_attempt")
	var old_session: String=scene.facade.readback().session_id
	var old_worker: CountedBridge=_observed
	_check(scene.restart(true),"actual_fresh_attempt")
	_check(old_worker.joined,"old_actual_worker_joined_on_reset")
	_observed=CountedBridge.new(scene.facade._bridge)
	scene.facade._bridge=_observed
	scene.show_state(0.0)
	_check(scene.facade.readback().session_id!=old_session and scene.facade.readback().tick=="0" and scene.route_view.route_labels.is_empty() and not scene.route_view.active,"fresh_native_session_clears_route")
	scene.open_landmark_route()
	scene.choose_landmark_route([0])
	# Explicit map-only replay of a retained paused source. No facade/native
	# reply is changed: the actual worker remains paused and is checked below.
	var paused_truth: Dictionary=scene.facade.readback()
	var paused_calls: Dictionary=_observed.writes()
	var terminal_paused: Dictionary=paused_truth.duplicate(true)
	terminal_paused.host_mode="stalled"
	terminal_paused.historical=true
	terminal_paused.error="SYNTHETIC retained paused presentation fixture"
	var terminal_info: Dictionary={"outcome":terminal_paused.native_outcome,"historical":true,"paused":true,"blocked":false,"stalled":false,"ground_valid":true,"clearance_m":scene.plane_clearance}
	scene.publish_landmark_route(terminal_paused,terminal_info)
	var raw: Array=paused_truth.canonical.anchor_eus_position_m
	scene.flight_map.set_state(terminal_paused.aircraft,Vector3(raw[0],raw[1],raw[2]),scene.airplane.basis,terminal_info)
	_check(terminal_paused.native_outcome=="paused" and scene.route_view.historical and scene.flight_map._valid and scene.flight_map._paused and scene.flight_map._retained,"retained_paused_outcome_is_history_not_current_paused_guidance")
	_check(scene.flight_map._route.is_empty() and scene.flight_map._runway_metrics().is_empty() and not scene.flight_map._clearance_valid and scene.route_view.planar_range_m==null and scene.route_view.bearing_deg==null,"historical_flag_alone_suppresses_map_route_runway_and_height_guidance")
	_check(scene.facade.readback()==paused_truth and _observed.writes()==paused_calls,"synthetic_terminal_presentation_preserves_actual_paused_worker")
	scene.show_state(0.0)
	_check(scene.flight_map._valid and scene.flight_map._paused and not scene.flight_map._retained and not scene.flight_map._route.is_empty() and not scene.flight_map._runway_metrics().is_empty(),"actual_current_paused_publication_restores_guidance_after_history_fixture")
	var closed: Dictionary=scene.facade.close()
	_check(closed.ok and _observed.joined,"actual_close_before_historical_fixture")
	scene.publish_landmark_route(closed.readback,{"blocked":true,"stalled":false})
	_check(scene.route_view.historical and not scene.route_view.available and scene.route_view.planar_range_m==null and scene.route_view.bearing_deg==null and scene.flight_map._route.is_empty(),"retained_actual_closed_guidance_null_and_labelled")
	var invalid: Dictionary=closed.readback.duplicate(true)
	invalid.tick=0.0
	scene.publish_landmark_route(invalid)
	_check(not scene.route_view.available and scene.route_view.planar_range_m==null and scene.route_view.bearing_deg==null and scene.flight_map._route.is_empty(),"invalid_guidance_no_stale_numbers")
	await _retire(scene)
	return _receipt()
func _receipt() -> Dictionary:
	return {"passed":failures.is_empty(),"checks":checks,"failures":failures.duplicate(),"scope":"Actual accepted legacy scene/worker with synthetic Raw; paused route UI native invariance, three explicit fixed ticks and lifecycle. No coupled piston trial, GPU, hardware, pilot or phase acceptance."}
