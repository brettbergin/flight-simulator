extends RefCounted
# Original MIT. Actual native/controller checks with explicit synthetic Raw.
# Display-buffer fixtures below are observer-only and are labelled separately.
const Scene=preload("res://simulation/flight_scene.gd")
const Recorder=preload("res://replay/observed/recorder.gd")
const Frames=preload("res://simulation/canonical_frames.gd")
const Checks=preload("res://camera_tests/policy_checks.gd")
const PageChecks=preload("res://camera_tests/panel_checks.gd")
const MAPPER_FIELDS=["_preset","_values","_start","_pins","_edges","_takeover","_configured","_live","_brake_hold","_v2","_held_systems","_system_intents","_system_edges","_pointer_session","_pointer_generation","_pointer_last_token","_pointer_capture","_pointer_begin","_pointer_terminal","_pointer_pending","_pointer_rearm","_pointer_error","_pointer_disabled"]
class ReleasedScene extends Scene:
	var raw: Dictionary={"keys":[],"mouse_buttons":[],"devices":[]}
	var raw_reads: int=0
	var suppress_expected_failure: bool=false
	var expected_failures: Array[String]=[]
	func collect_input_raw(_preset: Dictionary={}) -> Dictionary:
		raw_reads+=1
		return raw.duplicate(true)
	func fail(message: String) -> bool:
		if not suppress_expected_failure: return super.fail(message)
		# Suppress only the expected log, never the actual failed-start cleanup.
		expected_failures.append(message)
		render_pose.clear()
		status=message
		paused=true
		blocked=true
		failures.append(message)
		return false
class RejectBegin extends Recorder:
	func begin(_readback: Variant,_confirmed: bool=false) -> Dictionary:
		return {"ok":false,"error":"Explicit camera-test recording qualification rejection","appended":false,"status":status()}

var _host: Node
var _result: Dictionary
var _refs: Dictionary
var _coverage: Array=[]
var _cold_rejection: bool=false

func _check(ok: bool,label: String) -> void:
	Checks.check(_result,ok,label)
	_host.call("check",ok,"camera_scene_"+label)

static func _copy(value: Variant) -> Variant:
	return value.duplicate(true) if value is Dictionary or value is Array else value

func _authority(scene: Node) -> Dictionary:
	var mapper: Dictionary={}
	for field in MAPPER_FIELDS: mapper[field]=_copy(scene.mapper.get(field))
	return {"native":scene.facade.get("_bridge").call("read_state"),"readback":scene.facade.readback(),"origin":scene.facade.render_origin.read_origin(),"mapper":mapper,"recording":scene.observed_recorder.recording(),"host_controls":scene.controls.duplicate(true),"held_controls":scene.held_controls.duplicate(true),"held_systems":scene.held_systems.duplicate(true),"pending_systems":scene.pending_systems.duplicate(true),"submitted":scene.submitted_count,"events":scene.event_count,"brake_hold":scene.brake_hold,"rearm":scene.engine_pointer_rearm.duplicate(),"terminal":scene.engine_pointer_terminal.duplicate(true),"look_active":scene.engine_pointer_look_active,"raw":scene.raw.duplicate(true)}

func _camera(scene: Node) -> Dictionary:
	return {"settings":scene.camera_view_settings(),"look":scene.look_angles,"distance":scene.camera_distance,"transform":scene.camera.transform,"near":scene.camera.near,"offset":scene.camera_follow_offset,"ready":scene.camera_ready}

func _aids(scene: Node) -> Dictionary:
	var value: Dictionary={"panel":scene.panel_visible,"map":scene.map_visible,"route":scene.route_aids_visible,"circuit":scene.circuit_aid_enabled,"viewport":scene.panel_viewport.render_target_update_mode}
	for name in ["panel","flight_map","engine_controls","wind_card"]:
		var node: Variant=scene.get(name)
		if node is Control: value[name+"_geometry"]={"rect":node.get_global_rect(),"visible":node.visible}
	return value

func _open(scene: Node,label: String) -> bool:
	var opened: bool=scene.open_views()
	_check(opened and scene.views_panel.visible,label+"_open")
	return opened and scene.views_panel.visible

func _apply(scene: Node,preset: String,fov: float=61.5,response: String="immediate") -> bool:
	if not _open(scene,"apply_"+preset): return false
	PageChecks.choose(scene.views_panel,preset)
	PageChecks.edit_fov(scene.views_panel,fov)
	PageChecks.response(scene.views_panel,response)
	PageChecks.press(scene.views_panel,"Apply")
	var wanted: Dictionary={"preset":preset,"fov_deg":fov,"external_response":response}
	var ok: bool=not scene.views_panel.visible and Checks.exact(scene.camera_view_settings(),wanted)
	_check(ok,"atomic_apply_"+preset)
	return ok

func _callbacks(page: Node) -> Array[Callable]:
	var calls: Array[Callable]=[]
	for row in page.get_signal_connection_list("apply_requested"):
		calls.append(row.callable)
	return calls

func _escape(scene: Node) -> void:
	var event: InputEventKey=InputEventKey.new()
	event.pressed=true
	event.physical_keycode=KEY_ESCAPE
	scene._unhandled_key_input(event)

func _page_matrix(scene: Node,profile: String,start: String) -> void:
	var owned_settings: Dictionary=scene.camera_view_settings()
	var original_settings: Dictionary=owned_settings.duplicate(true)
	owned_settings.preset="unknown"
	owned_settings.fov_deg=1.0
	_check(Checks.exact(scene.camera_view_settings(),original_settings),"actual_settings_getter_owns_copy_"+start)
	for preset in Checks.PRESETS:
		var baseline: Dictionary=_authority(scene)
		var raw_reads: int=scene.raw_reads
		var before: Dictionary=_camera(scene)
		if not _open(scene,preset): continue
		PageChecks.choose(scene.views_panel,preset)
		PageChecks.edit_fov(scene.views_panel,61.5)
		PageChecks.response(scene.views_panel,"immediate")
		_check(Checks.exact(_camera(scene),before) and Checks.exact(_authority(scene),baseline),preset+"_draft_no_preview_or_authority_mutation")
		# Automatic processing is deliberately disabled in this harness. Exercise
		# the actual interval entry explicitly; the Raw counter makes a removed
		# guard visible even when released suspended inputs would be state no-ops.
		for elapsed in [0,8334,250000]:
			scene.process_input_interval(elapsed)
			_check(scene.views_panel.visible and scene.raw_reads==raw_reads and Checks.exact(_camera(scene),before) and Checks.exact(_authority(scene),baseline),preset+"_open_page_interval_"+str(elapsed)+"_does_not_read_raw_or_mutate_authority")
		for request in [["pause_session",[false]],["advance_wall_us",[8334]],["submit_axes",[scene.controls.duplicate(true)]],["set_flight_scale",[0.5]]]:
			var reply: Variant=scene.callv(request[0],request[1])
			_check(typeof(reply)==TYPE_BOOL and not reply and scene.views_panel.visible and scene.raw_reads==raw_reads and Checks.exact(_camera(scene),before) and Checks.exact(_authority(scene),baseline),preset+"_direct_mutator_rejected_without_partial_admission_"+request[0])
		for method in ["open_controls","open_wind","open_audio","open_observed_review","open_instrument_scan","open_landmark_route","open_first_flight"]:
			scene.call(method)
			_check(scene.views_panel.visible and scene.raw_reads==raw_reads and Checks.exact(_camera(scene),before) and Checks.exact(_authority(scene),baseline),preset+"_other_modal_inert_"+method)
		_check(not scene.begin_archive_operation("open",false),preset+"_archive_entry_rejected")
		# The modal guard must also hold for direct action delivery, not only keys.
		for action in ["view_cycle","view_cockpit","view_chase","view_orbit","view_panel","recenter","view_zoom_in","restart","start_ground","start_airborne"]:
			scene.dispatch_input_action(action)
		_check(scene.views_panel.visible and Checks.exact(_camera(scene),before) and Checks.exact(_authority(scene),baseline),preset+"_modal_actions_inert")
		PageChecks.press(scene.views_panel,"Apply")
		var settings: Dictionary={"preset":preset,"fov_deg":61.5,"external_response":"immediate"}
		var adopted: bool=Checks.exact(scene.camera_view_settings(),settings) and not scene.views_panel.visible and scene.paused and scene.menu_open
		_check(adopted and scene.look_angles==Vector2.ZERO,preset+"_applied_still_paused")
		_check(Checks.exact(_authority(scene),baseline),preset+"_complete_native_mapper_recording_unchanged")
		scene.show_state(0.0)
		_check(Checks.exact(_authority(scene),baseline),preset+"_draw_retains_complete_authority")
		if adopted: _coverage.append({"profile":profile,"start":start,"preset":preset})
		var applied: Dictionary=_camera(scene)
		if _open(scene,preset+"_cancel"):
			PageChecks.choose(scene.views_panel,"orbit" if preset!="orbit" else "left_window")
			PageChecks.edit_fov(scene.views_panel,90.0)
			PageChecks.press(scene.views_panel,"Cancel")
			_check(not scene.views_panel.visible and scene.paused and Checks.exact(_camera(scene),applied) and Checks.exact(_authority(scene),baseline),preset+"_cancel_exact")

func _same_mode_and_stale(scene: Node) -> void:
	_check(_apply(scene,"left_window"),"same_mode_initial")
	scene.show_state(0.0)
	scene.panel_visible=false
	scene.panel.set_panel_visible(false)
	scene.map_visible=false
	scene.flight_map.hide()
	scene.camera_distance=17.0
	scene.look_angles=Vector2(0.25,-0.125)
	scene.show_state(0.0)
	var authority: Dictionary=_authority(scene)
	var aids: Dictionary=_aids(scene)
	var camera: Dictionary=_camera(scene)
	if _open(scene,"escape"):
		PageChecks.choose(scene.views_panel,"right_window")
		_escape(scene)
		_check(not scene.views_panel.visible and scene.paused and Checks.exact(_camera(scene),camera) and Checks.exact(_authority(scene),authority),"L03_escape_cancels_without_resume")
	if _open(scene,"Back"):
		PageChecks.choose(scene.views_panel,"right_window")
		scene.close_menu()
		_check(not scene.views_panel.visible and scene.paused and scene.menu_open and Checks.exact(_camera(scene),camera) and Checks.exact(_authority(scene),authority),"L04_Back_cancels_without_resume")
	# Exercise the real read-only event branch separately from close_menu().
	for kind in ["mapped_P","unbound_gamepad_B"]:
		if not _open(scene,kind): continue
		PageChecks.choose(scene.views_panel,"orbit")
		var event_reads: int=scene.raw_reads
		if kind=="mapped_P":
			var key: InputEventKey=InputEventKey.new()
			key.pressed=true
			key.physical_keycode=KEY_P
			scene._unhandled_key_input(key)
		else:
			var joy: InputEventJoypadButton=InputEventJoypadButton.new()
			joy.pressed=true
			joy.button_index=JOY_BUTTON_B
			joy.device=0
			# Pinned actual project defaults have Escape only for ui_cancel.
			# B has no configured pause-menu alias here; do not fabricate a binding.
			_check(not joy.is_action_pressed("ui_cancel"),"gamepad_B_has_no_builtin_UI_Back_mapping")
			var draft: Dictionary=scene.views_panel.draft()
			scene._unhandled_input(joy)
			_check(scene.views_panel.visible and scene.raw_reads==event_reads and Checks.exact(scene.views_panel.draft(),draft) and Checks.exact(_camera(scene),camera) and Checks.exact(_authority(scene),authority),"unbound_gamepad_B_inert_without_Raw_sampling_or_resume")
			PageChecks.press(scene.views_panel,"Cancel")
		_check(not scene.views_panel.visible and scene.paused and scene.menu_open and scene.raw_reads==event_reads and Checks.exact(_camera(scene),camera) and Checks.exact(_authority(scene),authority),kind+"_ends_at_Cancel_without_Raw_sampling_or_resume")
	if _open(scene,"defaults_cancel"):
		PageChecks.press(scene.views_panel,"RestoreDefaults")
		_check(Checks.exact(_camera(scene),camera),"L06_defaults_draft_only")
		PageChecks.press(scene.views_panel,"Cancel")
		_check(Checks.exact(_camera(scene),camera),"L06_defaults_cancel_preserves_all_camera")
	_check(_apply(scene,"right_window",58.0),"L05_same_mode_apply")
	scene.show_state(0.0)
	_check(scene.camera_distance==17.0 and Checks.exact(_aids(scene),aids) and Checks.exact(_authority(scene),authority),"L05_same_mode_manual_aids_and_generation_preserved")
	var applied: Dictionary=_camera(scene)
	_check(_apply(scene,"right_window",58.0),"L10_identical_apply_again")
	scene.show_state(0.0)
	_check(Checks.exact(_camera(scene),applied) and Checks.exact(_authority(scene),authority),"L10_identical_apply_idempotent")
	if _open(scene,"defaults_apply"):
		PageChecks.press(scene.views_panel,"RestoreDefaults")
		PageChecks.press(scene.views_panel,"Apply")
		_check(Checks.exact(scene.camera_view_settings(),Checks.decode(_refs.defaults.settings)) and scene.camera_distance==17.0 and Checks.exact(_authority(scene),authority),"L07_defaults_apply_preserves_distance_and_authority")
	_check(_apply(scene,"panel",61.5,"immediate"),"L08_traditional_panel_choice")
	_check(scene.camera_mode==3 and scene.forward_view and not scene.panel_visible and scene.panel_viewport.render_target_update_mode==SubViewport.UPDATE_ALWAYS and scene.camera_distance==17.0 and Checks.exact(_authority(scene),authority),"L08_changed_mode_retains_inherited_visibility_rules")
	# Actual saved closures prove a retired opening cannot affect a newer opening
	# under the SAME session, even though a session-only guard would admit it.
	if _open(scene,"same_session_stale"):
		var old: Array[Callable]=_callbacks(scene.views_panel)
		var source: String=scene.adopted_session_id
		scene.dismiss_views()
		if _open(scene,"same_session_new_opening"):
			var draft: Dictionary=scene.views_panel.draft()
			var settings: Dictionary=scene.camera_view_settings()
			_check(not old.is_empty(),"old_real_scene_callback_captured")
			for call in old: call.call({"preset":"orbit","fov_deg":90.0,"external_response":"smooth"},source)
			_check(scene.views_panel.visible and Checks.exact(scene.views_panel.draft(),draft) and Checks.exact(scene.camera_view_settings(),settings) and Checks.exact(_authority(scene),authority),"retired_same_session_callback_inert")
			# Force an invalid typed payload through the ACTUAL host callback too.
			for call in _callbacks(scene.views_panel): call.call({"preset":"orbit","fov_deg":72,"external_response":"smooth"},source)
			_check(scene.views_panel.visible and Checks.exact(scene.camera_view_settings(),settings) and Checks.exact(_authority(scene),authority),"L09_host_rejects_int_fov_atomically")
			scene.dismiss_views()

func _action_cases(scene: Node) -> void:
	for row in _refs.mapped_action_cases:
		if row.id=="A18": continue # actual release exercised separately below
		_check(_apply(scene,row.initial_preset),row.id+"_initial_selection")
		scene.look_angles=Vector2(0.25,-0.125)
		scene.camera_distance=17.0
		var before: Dictionary=_authority(scene)
		if row.id in ["A13","A14"]:
			scene.camera.fov=35.0 if row.id=="A13" else 90.0
			scene.dispatch_input_action("view_zoom_in" if row.id=="A13" else "view_zoom_out")
		elif row.id in ["A15","A16"]:
			scene.camera_distance=6.0 if row.id=="A15" else 40.0
			scene.dispatch_input_action("view_zoom_in" if row.id=="A15" else "view_zoom_out")
		elif row.id=="A17":
			scene.camera.fov=72.0
			scene.dispatch_input_action("view_zoom_in")
			if _open(scene,"A17_actual_fov"):
				_check(Checks.exact(scene.views_panel.draft().fov_deg,Checks.number(row.expected_draft_fov)),"A17_actual_wheel_fov_copied")
				scene.dismiss_views()
		else:
			var action: String="recenter" if row.id=="A12" else row.operation.trim_prefix("accepted ")
			scene.dispatch_input_action(action)
		if row.has("expected_preset"):
			_check(scene.camera_view_settings().preset==row.expected_preset and scene.look_angles==Vector2.ZERO,row.id+"_selected_base_and_recenter")
		if row.has("expected_fov"):
			_check(Checks.exact(scene.camera_view_settings().fov_deg,Checks.number(row.expected_fov)),row.id+"_fov_exact")
		if row.has("expected_distance_m"):
			_check(Checks.exact(scene.camera_distance,Checks.number(row.expected_distance_m)),row.id+"_distance_bound")
		else:
			_check(scene.camera_distance==17.0,row.id+"_distance_preserved")
		_check(scene.camera_view_settings().external_response=="immediate" and Checks.exact(_authority(scene),before),row.id+"_response_and_complete_authority")

func _field_guard(scene: Node,field: String,value: Variant,label: String) -> void:
	var previous: Variant=_copy(scene.get(field))
	scene.set(field,value)
	var before: Dictionary=_authority(scene)
	var camera: Dictionary=_camera(scene)
	_check(not scene.open_views() and not scene.views_panel.visible and Checks.exact(_authority(scene),before) and Checks.exact(_camera(scene),camera),label+"_reject_before_side_effects")
	scene.set(field,previous)

func _entry_guards(scene: Node) -> void:
	_field_guard(scene,"adopted_session_id","foreign-camera-session","G01_identity")
	_field_guard(scene,"paused",false,"G02_scene_not_paused")
	_field_guard(scene,"menu_open",false,"G05_menu_closed")
	_field_guard(scene,"initializing_recording",true,"G06_initializing")
	_field_guard(scene,"quitting",true,"G07_quitting")
	_field_guard(scene,"engine_pointer_look_active",true,"G09_look_owner")
	_field_guard(scene,"engine_pointer_terminal",{"declared":"pending"},"G10_queued_terminal")
	for pair in [["archive_operation",{"kind":"open"}],["pending_discard",{"kind":"test-conflict"}],["review_open",true],["audio_open",true],["scan_open",true],["route_open",true],["first_flight_open",true]]:
		_field_guard(scene,pair[0],pair[1],"modal_"+pair[0])
	for field in ["controls_panel","wind_panel"]:
		var control: Control=scene.get(field)
		control.show()
		var before: Dictionary=_authority(scene)
		_check(not scene.open_views() and not scene.views_panel.visible and Checks.exact(_authority(scene),before),"modal_"+field)
		control.hide()
	var old_current: Variant=scene.facade.get("_current")
	scene.facade.set("_current",null)
	var invalid_before: Dictionary=_authority(scene)
	_check(not scene.open_views() and Checks.exact(_authority(scene),invalid_before),"G04_invalid_presentation_rejects")
	scene.facade.set("_current",old_current)
	var old_mode: int=Input.mouse_mode
	Input.mouse_mode=Input.MOUSE_MODE_CAPTURED
	var captured: Dictionary=_authority(scene)
	_check(not scene.open_views() and Checks.exact(_authority(scene),captured) and Input.mouse_mode==Input.MOUSE_MODE_CAPTURED,"G08_hidden_pointer_no_retirement")
	Input.mouse_mode=old_mode
	_check(scene.pause_session(false),"G03_actual_live_setup")
	var live: Dictionary=_authority(scene)
	_check(not scene.open_views() and Checks.exact(_authority(scene),live) and not scene.paused,"G03_live_direct_open_never_pauses")
	_check(scene.pause_session(true),"G03_actual_pause_after_guard")
	scene.open_menu()

static func _vector(values: Array) -> Vector3:
	return Vector3(values[0],values[1],values[2])

static func _near(vector: Vector3,values: Array,tolerance: float) -> bool:
	return absf(float(vector.x)-float(values[0]))<=tolerance and absf(float(vector.y)-float(values[1]))<=tolerance and absf(float(vector.z)-float(values[2]))<=tolerance

static func _basis(rows: Array) -> Basis:
	return Basis(Vector3(rows[0][0],rows[1][0],rows[2][0]),Vector3(rows[0][1],rows[1][1],rows[2][1]),Vector3(rows[0][2],rows[1][2],rows[2][2]))

func _presentation(scene: Node,position: Array,rows: Array) -> void:
	var origin: Dictionary=scene.facade.render_origin.read_origin().committed
	var ecef: Array=[]
	for axis in range(3):
		ecef.append(float(origin.origin_ecef_m[axis])+float(origin.ecef_to_eus[axis])*float(position[0])+float(origin.ecef_to_eus[3+axis])*float(position[1])+float(origin.ecef_to_eus[6+axis])*float(position[2]))
	# Frames.transform includes body-to-visual axis mapping C. Supply S*C^T
	# so the actual presented model basis is the frozen S, not body-axis S.
	var rotation: Array=[]
	for row in rows: rotation.append_array([-float(row[2]),float(row[0]),-float(row[1])])
	var pose: Dictionary=scene.facade.get("_current").duplicate(true)
	pose.ecef_position_m=ecef
	pose.body_to_anchor_eus=rotation
	scene.facade.set("_previous",pose.duplicate(true))
	scene.facade.set("_current",pose.duplicate(true))

func _display_observers(scene: Node) -> void:
	# These are synthetic presentation endpoints around the actual paused
	# session. They are NOT altered native aircraft publications or live trials.
	var buffers: Dictionary={}
	for field in ["_previous","_current","_previous_tick"]: buffers[field]=_copy(scene.facade.get(field))
	var baseline: Dictionary=_authority(scene)
	var original_paused: bool=scene.paused
	var original_camera: Dictionary=_camera(scene)
	var identity: Array=Checks.decode(_refs.basis_rows.identity)
	for row in _refs.direction_cases:
		_check(_apply(scene,row.preset),row.id+"_actual_presentation_selection")
		var rows: Array=Checks.decode(_refs.basis_rows[row.basis])
		_presentation(scene,[0.0,0.0,0.0],rows)
		scene.look_angles=Vector2(Checks.number(row.yaw),Checks.number(row.pitch))
		scene.show_state(0.0)
		var expected: Array=Checks.decode(row.expected_scene)
		var up: Array=Checks.decode(row.expected_scene_up)
		var direction: Vector3=-scene.camera.basis.z
		_check(_near(direction,expected,Checks.DIRECTION_ERROR),row.id+"_frozen_direction_components")
		var eye: Vector3=scene.airplane.position+_basis(rows)*scene.cockpit.eye
		_check((scene.camera.position-eye).length()<=Checks.POSITION_ERROR,row.id+"_same_presented_eye")
		_check((scene.camera.position+direction*60.0-(eye+_vector(expected)*60.0)).length()<=Checks.RAY_ERROR,row.id+"_sixty_meter_ray")
		var right: Vector3=_vector(expected).cross(_vector(up)).normalized()
		_check((scene.camera.basis.x-right).length()<=Checks.DIRECTION_ERROR,row.id+"_aircraft_up_not_stabilized")
		_check((scene.airplane.basis.x-_basis(rows).x).length()<=Checks.DIRECTION_ERROR and (scene.airplane.basis.y-_basis(rows).y).length()<=Checks.DIRECTION_ERROR,row.id+"_frozen_aircraft_rotation_applied")
		if row.preset in ["cockpit","panel"]:
			# Same pinned engine, exact old expression/order; ideal numbers above
			# cannot excuse changing this traditional computation.
			var base: Vector3=(scene.cockpit.panel_focus-scene.cockpit.eye).normalized() if row.preset=="panel" else Vector3(0,-0.268,-1).normalized()
			var gaze: Basis=Basis(Vector3.UP,-scene.look_angles.x)*Basis(Vector3.RIGHT,scene.look_angles.y)
			var target: Vector3=scene.camera.position+scene.airplane.basis*(gaze*base)*60
			scene.camera.look_at(target,scene.airplane.basis.y)
			var legacy: Transform3D=scene.camera.transform
			scene.show_state(0.0)
			_check(Checks.exact(scene.camera.transform,legacy),row.id+"_traditional_expression_exact_engine_regression")
	_check(_apply(scene,"chase",72.0,"smooth"),"filter_select_smooth")
	_presentation(scene,[0.0,0.0,0.0],identity)
	scene.look_angles=Vector2(PI/2.0,0.0)
	scene.camera_distance=13.0
	scene.paused=false # presentation fixture only; actual facade remains paused
	for row in _refs.filter_scalar_cases:
		_check(scene.has_method("_camera_smooth_alpha"),row.id+"_used_scalar_seam_exists")
		if scene.has_method("_camera_smooth_alpha"):
			var alpha_result: Variant=scene.call("_camera_smooth_alpha",Checks.number(row.seconds))
			_check(typeof(alpha_result)==TYPE_FLOAT and absf(alpha_result-Checks.number(row.expected_alpha))<=Checks.ALPHA_ERROR,row.id+"_frozen_scalar_alpha")
		scene.camera_ready=true
		scene.camera_follow_offset=Vector3.ZERO
		scene.show_state(Checks.number(row.seconds))
		var alpha: float=Checks.number(row.expected_alpha)
		_check(_near(scene.camera_follow_offset,[13.0*alpha,3.5*alpha,0.0],Checks.POSITION_ERROR),row.id+"_analytic_response_through_actual_position")
	# Each response receives its own previous offset; no consumer result is
	# fed back into the frozen reference expectations.
	for response_name in ["smooth","immediate"]:
		scene.paused=true
		_check(_apply(scene,"chase",72.0,response_name),"moving_response_"+response_name)
		scene.paused=false
		var previous: Vector3=_vector(Checks.decode(_refs.filter_moving_sequence[0].previous_smooth_offset_m))
		for row in _refs.filter_moving_sequence:
			_presentation(scene,Checks.decode(row.presented_ownship_m),identity)
			scene.look_angles=Vector2(PI/2.0 if row.id=="M01" else PI,0.0)
			scene.camera_ready=true
			scene.camera_follow_offset=previous
			scene.show_state(Checks.number(row.seconds))
			var offset: Array=Checks.decode(row["expected_"+response_name+"_offset_m"])
			var camera: Array=Checks.decode(row["expected_"+response_name+"_camera_m"])
			_check(_near(scene.camera_follow_offset,offset,Checks.POSITION_ERROR),row.id+"_"+response_name+"_analytic_offset")
			_check(_near(scene.camera.position,camera,Checks.POSITION_ERROR),row.id+"_"+response_name+"_same_presented_translation")
			_check((scene.camera.position-(_vector(Checks.decode(row.latest_raw_endpoint_m))+_vector(offset))).length()>1.0,row.id+"_"+response_name+"_raw_template_not_used")
			previous=scene.camera_follow_offset
	# Branches B01..B07 in the real draw, still synthetic display-only inputs.
	_presentation(scene,[0.0,0.0,0.0],identity)
	scene.look_angles=Vector2.ZERO
	scene.camera_ready=false
	scene.camera_follow_offset=Vector3(29,29,29)
	scene.view_settings.external_response="smooth"
	scene.show_state(0.125)
	var desired: Vector3=(scene.airplane.position+scene.airplane.basis*Vector3(0,3.5,13))-scene.airplane.position
	_check(scene.camera_follow_offset==desired,"B01_first_draw_reseeds")
	scene.paused=true
	scene.camera_ready=true
	scene.camera_follow_offset=Vector3(29,29,29)
	scene.show_state(0.125)
	_check(scene.camera_follow_offset==desired,"B02_paused_snap")
	scene.paused=false
	scene.camera_follow_offset=Vector3(1,2,3)
	scene.show_state(0.0)
	_check(scene.camera_follow_offset==Vector3(1,2,3),"B04_zero_time_preserves_previous")
	scene.view_settings.external_response="immediate"
	scene.show_state(0.0)
	_check(scene.camera_follow_offset==desired,"B05_zero_time_immediate_desired")
	scene.paused=true
	_check(_apply(scene,"left_window",72.0,"smooth"),"B03_interior_choice")
	scene.show_state(0.0)
	_check(scene.camera_follow_offset==(scene.airplane.position+scene.airplane.basis*scene.cockpit.eye)-scene.airplane.position,"B03_interior_exact_eye")
	_check(_apply(scene,"chase",72.0,"immediate"),"B06_mode_response_choice")
	scene.show_state(0.0)
	desired=(scene.airplane.position+scene.airplane.basis*Vector3(0,3.5,13))-scene.airplane.position
	_check(scene.camera_follow_offset==desired,"B06_next_draw_no_stale_offset")
	_check(_apply(scene,"orbit",72.0,"immediate"),"B07_orbit_choice")
	scene.look_angles=Vector2(0.0,-1.2)
	scene.show_state(0.0)
	var origin: Dictionary=scene.facade.render_origin.read_origin().committed
	var floor_point: Array=Frames.project(scene.prepared.ecef,origin.origin_ecef_m,origin.ecef_to_eus)
	_check(scene.camera.position.y>=float(floor_point[1])+0.35-Checks.POSITION_ERROR,"B07_origin_aware_floor")
	# Restore the EXACT presentation buffer, not a derived or rounded substitute.
	for field in buffers: scene.facade.set(field,buffers[field])
	scene.paused=original_paused
	_check(Checks.exact(_authority(scene),baseline),"synthetic_display_fixtures_preserve_complete_authority")
	_check(_apply(scene,original_camera.settings.preset,original_camera.settings.fov_deg,original_camera.settings.external_response),"restore_pre_observer_presentation")
	scene.look_angles=original_camera.look
	scene.camera_distance=original_camera.distance
	scene.camera_follow_offset=original_camera.offset
	scene.camera_ready=original_camera.ready
	scene.show_state(0.0)

func _origin_observer(scene: Node) -> void:
	_check(_apply(scene,"chase",72.0,"immediate"),"B08_origin_chase")
	scene.show_state(0.0)
	var before: Dictionary=_authority(scene)
	var origin: Dictionary=scene.facade.render_origin.read_origin().committed
	var original: Array=origin.origin_ecef_m.duplicate()
	var shift: Array=[16.0,0.0,-8.0]
	var candidate: Array=[]
	for axis in range(3): candidate.append(float(original[axis])+float(origin.ecef_to_eus[axis])*shift[0]+float(origin.ecef_to_eus[3+axis])*shift[1]+float(origin.ecef_to_eus[6+axis])*shift[2])
	var body: Vector3=scene.airplane.position
	var camera: Vector3=scene.camera.position
	var gaze: Basis=scene.camera.basis
	var map_position: Vector2=scene.flight_map.get("_position")
	scene.update_canonical_scene_sources()
	var rebased: Dictionary=scene.facade.render_origin.rebase(candidate)
	_check(rebased.ok,"B08_actual_origin_transaction")
	scene.show_state(0.0)
	_check((scene.airplane.position-(body-_vector(shift))).length()<=Checks.POSITION_ERROR and (scene.camera.position-(camera-_vector(shift))).length()<=Checks.POSITION_ERROR and (scene.camera.basis.z-gaze.z).length()<=Checks.DIRECTION_ERROR,"B08_camera_and_body_common_translation")
	_check(scene.flight_map.get("_position")==map_position,"B08_raw_map_unchanged")
	var after: Dictionary=_authority(scene)
	before.erase("origin")
	after.erase("origin")
	_check(Checks.exact(before,after),"B08_native_mapper_recording_unchanged_origin_version_legitimately_changes")
	scene.update_canonical_scene_sources()
	_check(scene.facade.render_origin.rebase(original).ok,"B08_restore_origin_transaction")
	scene.show_state(0.0)

func _restart_cases(scene: Node) -> void:
	_check(_apply(scene,"left_window",61.5,"immediate"),"restart_custom_view")
	scene.look_angles=Vector2(0.25,-0.125)
	scene.camera_distance=17.0
	scene.show_state(0.0)
	var settings: Dictionary=scene.camera_view_settings()
	var authority: Dictionary=_authority(scene)
	_check(not scene.restart(true,"invalid-wind") and Checks.exact(scene.camera_view_settings(),settings) and Checks.exact(_authority(scene),authority),"rejected_restart_preserves_settings_and_authority")
	# A real advanced recording must use the existing default-Cancel prompt.
	_check(not scene.restart(false) and not scene.pending_discard.is_empty(),"L13_discard_prompt")
	var after_prompt: Dictionary=_authority(scene)
	scene.cancel_discard()
	_check(Checks.exact(scene.camera_view_settings(),settings) and Checks.exact(_authority(scene),after_prompt),"L13_discard_cancel_preserves_settings_after_existing_retirement")
	var old_callbacks: Array[Callable]=[]
	var old_session: String=scene.adopted_session_id
	if _open(scene,"L11_old_session_callback"):
		old_callbacks=_callbacks(scene.views_panel)
	# Actual successful adoption is the only allowed default/reset boundary.
	_check(scene.restart(true),"L15_actual_fresh_adoption")
	scene.open_menu()
	scene.show_state(0.0)
	_check(scene.adopted_session_id!=old_session and Checks.exact(scene.camera_view_settings(),Checks.decode(_refs.defaults.settings)) and scene.camera_distance==13.0 and scene.look_angles==Vector2.ZERO,"L15_success_defaults")
	var post_restart: Dictionary=_authority(scene)
	var camera: Dictionary=_camera(scene)
	for call in old_callbacks: call.call(settings,old_session)
	_check(Checks.exact(_camera(scene),camera) and Checks.exact(_authority(scene),post_restart),"L11_old_session_callback_cannot_mutate_new_flight")
	_check(_apply(scene,"right_window",58.0,"immediate"),"L14_failed_adoption_view_setup")
	settings=scene.camera_view_settings()
	var retained: RefCounted=scene.observed_recorder
	var injected: RefCounted=RejectBegin.new()
	# This deliberately injected qualification failure occurs AFTER real open.
	# Existing recording is copied to the replacement recorder for lifecycle truth.
	for field in ["_record","_last","_last_grid"]: injected.set(field,_copy(retained.get(field)))
	scene.observed_recorder=injected
	scene.suppress_expected_failure=true
	_check(not scene.restart(true),"L14_actual_worker_open_then_injected_qualification_rejection")
	_check(not scene.expected_failures.is_empty() and (scene.facade==null or not scene.facade.readback().native_live),"L14_failed_new_worker_joined")
	_check(Checks.exact(scene.camera_view_settings(),settings),"L14_failed_adoption_preserves_retained_settings")
	# Restore the actual post-close recording prefix rather than inventing a live
	# prior state; old mutable observer state is not a successful replacement.
	for field in ["_record","_last","_last_grid"]: retained.set(field,_copy(injected.get(field)))
	scene.observed_recorder=retained
	scene.suppress_expected_failure=false
	_check(scene.restart(true),"L14_recover_actual_new_session")
	scene.open_menu()
	scene.show_state(0.0)
	_check(Checks.exact(scene.camera_view_settings(),Checks.decode(_refs.defaults.settings)),"L14_recovery_success_defaults")

func _pointer_button(scene: Node,pressed: bool) -> void:
	var event: InputEventMouseButton=InputEventMouseButton.new()
	var rect: Rect2=scene.engine_controls.call("_rects")["engine.starter"]
	event.position=scene.engine_controls.get_global_transform_with_canvas()*rect.get_center()
	event.global_position=event.position
	event.button_index=MOUSE_BUTTON_LEFT
	event.button_mask=MOUSE_BUTTON_MASK_LEFT if pressed else 0
	event.pressed=pressed
	# Actual viewport GUI dispatch and host preflight; physical Raw is explicitly
	# synthetic, complete and independently supplied, never rewritten by Views.
	scene._input(event)
	scene.get_viewport().push_input(event,true)

func _release_and_focus(scene: Node,piston: bool) -> void:
	_check(_apply(scene,"left_window",61.5,"immediate"),"release_selected_side")
	scene.raw={"keys":[],"mouse_buttons":[],"devices":[]}
	_check(scene.pause_session(false),"release_actual_resume")
	scene.menu_open=false
	scene.menu.hide()
	Input.mouse_mode=Input.MOUSE_MODE_VISIBLE
	if piston:
		scene.engine_controls.set_expanded(true)
		scene.show_state(0.0)
		_check(scene.pointer_ui_eligible(),"real_pointer_gui_eligible")
		scene.raw.mouse_buttons=[1]
		_pointer_button(scene,true)
		_check(scene.mapper.pointer_view().capture!=null and not scene.mapper.get("_pointer_pending").is_empty(),"real_gui_begin_capture_and_queue")
		var active: Dictionary=_authority(scene)
		_check(not scene.open_views() and Checks.exact(_authority(scene),active),"active_real_pointer_cannot_open_views")
		scene.process_input_interval(8334)
		_check(scene.facade.readback().tick!="0" and scene.held_systems.get("engine.starter")==true,"actual_native_starter_held_before_pause")
		# No GUI up is sent: ordinary pause/capture retirement must retain rearm.
		_check(scene.pause_session(true),"real_pointer_ordinary_pause")
		scene.open_menu()
		scene.show_state(0.0)
		_check(1 in scene.engine_pointer_rearm and 1 in scene.mapper.pointer_view().rearm_buttons and scene.mapper.pointer_view().capture==null,"ordinary_pause_real_release_required")
		var paused: Dictionary=_authority(scene)
		_check(_apply(scene,"right_window",58.0,"immediate"),"L16_guarded_held_page_apply")
		_check(Checks.exact(_authority(scene),paused) and 1 in scene.engine_pointer_rearm,"L16_page_does_not_clear_guard_or_fabricate_native_release")
		_check(not scene.pause_session(false) and Checks.exact(_authority(scene),paused),"L16_held_button_resume_still_rejected")
		# Complete Raw reports a real release through normal validated input.
		scene.raw.mouse_buttons=[]
		scene.process_input_interval(0)
		_check(scene.pause_session(false) and scene.engine_pointer_rearm.is_empty(),"L16_validated_actual_up_allows_explicit_resume")
		scene.menu_open=false
		scene.menu.hide()
		_check(scene.advance_wall_us(8334) and not scene.held_systems.get("engine.starter",true),"L16_false_replacement_before_first_resumed_tick")
	# A18 and ordinary free-look sensitivity/clamps use production event routing.
	scene.raw.mouse_buttons=[MOUSE_BUTTON_RIGHT]
	scene.process_input_interval(0)
	_check(scene.engine_pointer_look_active and Input.mouse_mode==Input.MOUSE_MODE_CAPTURED,"real_look_hold_admitted")
	var native: Dictionary=scene.facade.get("_bridge").call("read_state")
	var preset: String=scene.camera_view_settings().preset
	scene.look_angles=Vector2.ZERO
	var motion: InputEventMouseMotion=InputEventMouseMotion.new()
	motion.relative=Vector2(50.0,-25.0)
	scene._unhandled_input(motion)
	_check(scene.look_angles==Vector2(-0.2,0.1),"original_mouse_sensitivity_signs")
	motion.relative=Vector2(-100000,-100000)
	scene._unhandled_input(motion)
	_check(scene.look_angles==Vector2(PI,1.2),"original_mouse_clamps")
	var angles: Vector2=scene.look_angles
	scene.raw.mouse_buttons=[]
	scene.process_input_interval(0)
	_check(not scene.engine_pointer_look_active and Input.mouse_mode==Input.MOUSE_MODE_VISIBLE and scene.look_angles==angles and scene.camera_view_settings().preset==preset and scene.facade.get("_bridge").call("read_state")==native,"A18_real_up_exposes_pointer_without_recenter_or_native_change")
	# Actual focus loss is an external ordinary pause, not a Views mutation.
	scene.on_focus_lost()
	_check(scene.paused and scene.facade.readback().paused,"external_focus_loss_actual_pause")
	scene.open_menu()
	var post_focus: Dictionary=_authority(scene)
	_check(_apply(scene,"forward_horizon",72.0,"smooth"),"after_focus_page_apply")
	_check(Checks.exact(_authority(scene),post_focus),"page_invariant_after_external_focus_boundary")

func _closed_callbacks(scene: Node) -> void:
	if not _open(scene,"L12_before_close"): return
	var calls: Array[Callable]=_callbacks(scene.views_panel)
	var source: String=scene.adopted_session_id
	var facade: RefCounted=scene.facade
	_check(scene.close_session(),"L12_external_actual_close_join")
	var before: Dictionary={"readback":facade.readback(),"recording":scene.observed_recorder.recording(),"camera":_camera(scene),"pointer":scene.mapper.pointer_view()}
	for call in calls: call.call({"preset":"orbit","fov_deg":90.0,"external_response":"smooth"},source)
	var after: Dictionary={"readback":facade.readback(),"recording":scene.observed_recorder.recording(),"camera":_camera(scene),"pointer":scene.mapper.pointer_view()}
	_check(not scene.views_panel.visible and not facade.readback().native_live and Checks.exact(before,after),"L12_retired_callback_cannot_mutate_closed_history")

func _receipt() -> Dictionary:
	_result.coverage=_coverage
	_result.cold_rejection=_cold_rejection
	return Checks.finish(_result)

func _retire(scene: Node) -> void:
	if scene.facade!=null: _check(scene.close_session(),"final_actual_worker_join")
	if scene.sound!=null: _check(bool(await scene.sound.call("shutdown")),"final_actual_audio_join")
	scene.free()

func run(host: Node,include_piston: bool=true,include_apron: bool=false) -> Dictionary:
	_host=host
	_result=Checks.receipt("Actual production Scene/native paused page matrix plus labelled synthetic display/failure fixtures; no pilot/GPU qualification")
	_refs=Checks.references(_result)
	if _refs.is_empty(): return _receipt()
	var scene: Node=ReleasedScene.new()
	host.add_child(scene)
	scene.set_process(false)
	scene.set_process_input(false)
	scene.set_process_unhandled_input(false)
	scene.set_process_unhandled_key_input(false)
	_check(scene.facade!=null and scene.facade.readback().aircraft!=null,"initial_actual_session")
	if scene.facade==null or scene.facade.readback().aircraft==null:
		await _retire(scene)
		return _receipt()
	var starts: Array=[["original-interactive-prototype","ground-ready"],["original-interactive-prototype","airborne-prepared"]]
	if include_piston: starts.append(["original-piston-prop-v1","piston-cold-ground"])
	# IncludeApron comes from independently qualified first-party build bindings.
	if include_apron:
		starts.append(["original-interactive-prototype","apron-ready"])
		if include_piston: starts.append(["original-piston-prop-v1","piston-cold-apron"])
	for pair in starts:
		var opened: bool=scene.restart(true,"calm",pair[0],pair[1])
		_check(opened,"fresh_"+pair[0]+"_"+pair[1])
		if not opened: continue
		_check(scene.pause_session(true),"verified_pause_"+pair[1])
		scene.open_menu()
		scene.show_state(0.0)
		var truth: Dictionary=scene.facade.readback()
		_check(truth.native_live and truth.paused and truth.host_mode=="paused" and truth.model_identity.id==pair[0] and truth.named_start==pair[1] and scene.facade.visual_pose().valid,"qualified_supported_start_"+pair[1])
		_check(Checks.exact(scene.camera_view_settings(),Checks.decode(_refs.defaults.settings)) and scene.camera_distance==13.0 and scene.look_angles==Vector2.ZERO,"successful_adoption_defaults_"+pair[1])
		_page_matrix(scene,pair[0],pair[1])
		_same_mode_and_stale(scene)
		_action_cases(scene)
		_entry_guards(scene)
		# A page never resumes. The ordinary explicit boundary still advances.
		var tick: String=scene.facade.readback().tick
		_check(scene.pause_session(false) and scene.advance_wall_us(25000) and scene.pause_session(true),"explicit_resume_three_ticks_"+pair[1])
		_check(scene.facade.readback().tick==str(int(tick)+3),"actual_three_ticks_"+pair[1])
		scene.open_menu()
	_check(_coverage.size()==starts.size()*7,"actual_supported_coverage_not_metadata")
	_display_observers(scene)
	_origin_observer(scene)
	_release_and_focus(scene,include_piston)
	_restart_cases(scene)
	if not include_piston:
		var before: Dictionary=_authority(scene)
		_cold_rejection=not scene.restart(true,"calm","original-piston-prop-v1","piston-cold-ground")
		_check(_cold_rejection and Checks.exact(_authority(scene),before),"upstream_cold_source_unqualified_refusal")
	_closed_callbacks(scene)
	await _retire(scene)
	return _receipt()
