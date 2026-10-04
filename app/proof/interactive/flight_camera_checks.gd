extends RefCounted
# Original MIT bounded diagnostics. Native fixture schedules are identical;
# synthetic observer poses never overwrite aircraft/weather or issue commands.

func _normalise_wire(text: String) -> String:
	var record: Dictionary=JSON.parse_string(text)
	# Replace only the flat session-id token, preserving native numerical bytes.
	return text.replace('"session_id":'+JSON.stringify(record.session_id),'"session_id":"camera-equivalence"')

func _cadence(hz: int) -> Array[int]:
	var values: Array[int]=[]
	for index in range(hz):
		var first: int=index*1000000/hz
		var last: int=(index+1)*1000000/hz
		values.append(last-first)
	return values

func _same_native(a: Dictionary, b: Dictionary) -> bool:
	if _normalise_wire(a.aircraft_json)!=_normalise_wire(b.aircraft_json) or _normalise_wire(a.atmosphere_json)!=_normalise_wire(b.atmosphere_json):
		return false
	for key in ["schema_version","held_axes","outcome","completed","live","historical","paused","time_scale","fault","queued","rejection","ground_query_valid","surface_height_m","plane_clearance_m","applied_commands_json","events_json"]:
		if a.get(key)!=b.get(key):
			return false
	return true

func _profile(host: Node, name: String, cadence: Array[int], baseline: Dictionary, axes: Dictionary, applied: Array[String]) -> Dictionary:
	host.named_start="airborne-prepared"
	var opened: bool=host.restart()
	host.check(opened,"camera_"+name+"_fresh_native_airborne_start")
	if not opened:
		return {}
	host.controls=axes.duplicate(true)
	host.check(host.submit_axes(host.controls),"camera_"+name+"_identical_typed_command_queued")
	var saved_trace: FileAccess=host.trace_file
	var trace_path: String="user://motion-control-"+name+".ndjson"
	host.trace_file=FileAccess.open(trace_path,FileAccess.WRITE)
	host.check(host.trace_file!=null,"camera_"+name+"_isolated_command_trace_open")
	var fixture_trace: FileAccess=host.trace_file
	host.set_camera_mode(1)
	var elapsed: int=0
	var frames: int=0
	var advanced: bool=true
	while elapsed<1000000:
		var delta: int=mini(cadence[frames%cadence.size()],1000000-elapsed)
		advanced=host.advance_wall_us(delta) and advanced
		host.show_state(float(delta)/1000000.0)
		elapsed+=delta
		frames+=1
	if fixture_trace!=null:
		fixture_trace.close()
	host.trace_file=saved_trace
	var records: Array[String]=[]
	for line in FileAccess.get_file_as_string(trace_path).split("\n",false):
		records.append(_normalise_wire(line))
	host.check(records==applied and records.size()==1,"camera_"+name+"_actual_applied_command_identity_and_once_only")
	var observed: Dictionary=host.bridge.call("read_state")
	host.check(advanced and host.snapshot.tick=="120" and host.debt==0 and host.submitted_count==1 and host.command_sequence==1,"camera_"+name+"_fixed_tick_debt_without_input_polling")
	host.check(observed.get("ok",false) and _same_native(baseline,observed),"camera_"+name+"_native_wire_and_worker_data_match_baseline")
	return {"frames":frames,"tick":host.snapshot.tick,"debt":host.debt,"commands":host.submitted_count}

func run(host: Node) -> void:
	var model_root: String=ProjectSettings.globalize_path("res://models") if OS.has_feature("editor") else OS.get_executable_path().get_base_dir().path_join("models")
	var reference: RefCounted=ClassDB.instantiate("FlightInteractiveSession")
	var opened: Dictionary=reference.call("open_session",model_root,"airborne-prepared")
	host.check(opened.get("ok",false),"camera_baseline_actual_native_open")
	if not opened.get("ok",false):
		reference.call("close")
		return
	var axes: Dictionary=opened.held_axes.duplicate(true)
	axes.kind="axes"
	axes.roll=clampf(float(axes.roll)+0.07,-1,1)
	axes.pitch=clampf(float(axes.pitch)+0.01,-1,1)
	axes.throttle=clampf(float(axes.throttle)+0.03,0,1)
	axes.trim=0.015
	var initial: Dictionary=JSON.parse_string(opened.aircraft_json)
	var command: Dictionary={"type":"ControlCommand","schema_version":1,"tick":"1","session_id":initial.session_id,"sequence":"1","source_id":"pilot.controls","authority":"pilot","assistance":{"profile_id":"unassisted","active":[]},"payload":axes}
	var admitted: Dictionary=reference.call("submit",command)
	host.check(admitted.get("ok",false) and admitted.get("queued",false),"camera_baseline_identical_typed_command_queued")
	var applied: Array[String]=[]
	var completed: bool=true
	for count in [32,32,32,24]:
		var reply: Dictionary=reference.call("step_fixed",count)
		for line in reply.get("applied_commands_json",[]):
			applied.append(_normalise_wire(line))
		for line in reply.get("events_json",[]):
			applied.append(_normalise_wire(line))
		completed=reply.get("ok",false) and reply.get("completed",0)==count and reply.get("outcome","")=="completed" and completed
	var applied_matches: bool=applied.size()==1
	if applied_matches:
		var actual: Dictionary=JSON.parse_string(applied[0])
		for key in ["type","schema_version","tick","sequence","source_id","authority","assistance"]:
			applied_matches=applied_matches and actual.get(key)==command.get(key)
		applied_matches=applied_matches and actual.payload.kind=="axes" and actual.session_id=="camera-equivalence"
		for key in ["roll","pitch","yaw","throttle","mixture","left_brake","right_brake","trim"]:
			applied_matches=applied_matches and absf(float(actual.payload[key])-float(axes[key]))<1e-12
	host.check(applied_matches,"camera_baseline_actual_command_applied_once")
	var baseline: Dictionary=reference.call("read_state")
	host.check(completed and JSON.parse_string(baseline.aircraft_json).tick=="120","camera_baseline_actual_120_ticks")
	var closed: Dictionary=reference.call("close")
	host.check(closed.get("ok",false) and closed.get("joined",false),"camera_baseline_worker_joined")
	var profiles: Dictionary={}
	for hz in [30,60,144,240]:
		profiles[str(hz)]=_profile(host,str(hz)+"Hz",_cadence(hz),baseline,axes,applied)
	profiles["irregular"]=_profile(host,"irregular",[1000,5000,17000,33000,50000,0],baseline,axes,applied)
	host.evidence["camera_native_schedules"]=profiles
	if host.snapshot.is_empty() or host.bridge==null:
		return
	# Clearly synthetic private rendering endpoints around an actual copied pose.
	var before: Dictionary=host.bridge.call("read_state").duplicate(true)
	var intent: Dictionary=host.controls.duplicate(true)
	var raw_snapshot: Dictionary=host.snapshot.duplicate(true)
	var count_before: int=host.submitted_count
	var sequence_before: int=host.command_sequence
	var native_position: Vector3=host.visual_position()
	var native_basis: Basis=host.visual_basis(host.body_quaternion())
	var tick: int=int(host.snapshot.tick)
	host.set_camera_mode(1)
	host.render_pose.reset(host.snapshot.session_id,tick-1,native_position,native_basis)
	host.render_pose.push(host.snapshot.session_id,tick,native_position+Vector3(10,0,0),native_basis)
	host.debt=0
	host.show_state(0.0)
	var first_relative: Vector3=host.camera.position-host.airplane.position
	var first_camera_basis: Basis=host.camera.basis
	host.debt=500000
	host.show_state(1.0/60.0)
	host.check(host.airplane.position.distance_to(native_position+Vector3(5,0,0))<0.0001,"camera_synthetic_half_tick_changes_render_only")
	host.check((host.camera.position-host.airplane.position).distance_to(first_relative)<0.0001 and host.camera.basis.is_equal_approx(first_camera_basis),"camera_chase_translation_keeps_relative_offset_and_gaze")
	for index in range(10):
		host.show_state(1.0/144.0)
	host.check(host.flight_map.get("_position").distance_to(Vector2(native_position.x,native_position.z))<0.0001,"camera_map_retains_raw_native_position_not_interpolated_pose")
	host.check(host.panel.get("_snapshot")==raw_snapshot and host.cockpit_panel.get("_snapshot")==raw_snapshot,"camera_instruments_keep_actual_native_snapshot")
	host.check(host.bridge.call("read_state")==before and host.snapshot==raw_snapshot and host.controls==intent and host.submitted_count==count_before and host.command_sequence==sequence_before,"camera_observer_calls_preserve_native_state_intent_and_command_count")
	host.check(host.pause_session(true),"camera_pause_native_accepted")
	host.show_state(0.0)
	host.check(host.airplane.transform.is_equal_approx(Transform3D(native_basis,native_position)),"camera_pause_collapses_to_actual_native_pose")
	var old_session: String=host.snapshot.session_id
	host.named_start="ground-ready"
	host.check(host.restart(),"camera_fresh_ground_reset")
	host.show_state(0.0)
	var fresh := Transform3D(host.visual_basis(host.body_quaternion()),host.visual_position())
	host.check(host.snapshot.session_id!=old_session and host.snapshot.tick=="0" and host.debt==0 and host.airplane.transform.is_equal_approx(fresh),"camera_reset_cannot_blend_old_airborne_history")
	var saved_outcome: String=host.native_outcome
	host.blocked=true
	host.native_outcome="discarded"
	host.render_pose.clear()
	host.show_state(0.0)
	host.check(not host.render_pose.has_pose() and host.airplane.transform.is_equal_approx(fresh),"camera_synthetic_terminal_display_has_no_stale_pose_blend")
	host.blocked=false
	host.native_outcome=saved_outcome
	host.reset_render_pose()
	host.show_state(0.0)
	host.evidence["camera_check_scope"]="Actual same-build native 120Hz endpoint/held/weather equivalence for identical pre-admitted typed-command presentation schedules; synthetic render-only chase/pause/reset/fault fixtures. No live-keyboard cadence equivalence or physics smoothing claim."

func capture(host: Node) -> void:
	# Short explicit native motion fixture. Render callbacks do not advance physics.
	var saved_start: String=host.named_start
	var saved_mode: int=host.camera_mode
	var metrics: Dictionary={}
	for mode in [1,2]:
		host.named_start="airborne-prepared"
		host.check(host.restart(),"motion_gpu_"+str(mode)+"_actual_airborne_start")
		host.set_camera_mode(mode)
		host.look_angles=Vector2(0.35,0.15) if mode==2 else Vector2.ZERO
		var first_tick: int=int(host.snapshot.tick)
		var stable: bool=true
		var frames: Array=[]
		for frame in range(8):
			var elapsed: int=[5000,11000,17000,23000][frame%4]
			host.check(host.advance_wall_us(elapsed),"motion_gpu_"+str(mode)+"_completed_frame_"+str(frame))
			host.show_state(float(elapsed)/1000000.0)
			var before: Dictionary=host.bridge.call("read_state").duplicate(true)
			var held: Dictionary=host.controls.duplicate(true)
			var count: int=host.submitted_count
			var label: String="view-motion-"+("chase" if mode==1 else "orbit")+"-%02d" % frame
			await host.save_view(label)
			stable=stable and host.bridge.call("read_state")==before and host.controls==held and host.submitted_count==count
			frames.append({"frame":frame,"native_tick":host.snapshot.tick,"fractional_debt":host.debt,"render_position_m":[host.airplane.position.x,host.airplane.position.y,host.airplane.position.z],"camera_offset_m":[host.camera_follow_offset.x,host.camera_follow_offset.y,host.camera_follow_offset.z]})
		host.check(stable,"motion_gpu_"+str(mode)+"_draw_callbacks_preserve_actual_native_state_and_commands")
		metrics[str(mode)]={"actual_native_ticks":int(host.snapshot.tick)-first_tick,"frames":frames}
	host.evidence["motion_gpu"]=metrics
	host.evidence["motion_gpu_scope"]="16 short actual native flight/render views under explicit irregular wall cadence, fixed admitted controls; not a human handling evaluation or frame-polled input equivalence."
	host.named_start=saved_start
	host.check(host.restart(),"motion_gpu_restores_fresh_named_start")
	host.set_camera_mode(saved_mode)
	host.show_state()

