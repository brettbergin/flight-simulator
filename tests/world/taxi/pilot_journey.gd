extends RefCounted
# Original MIT. An unexecuted scripted PILOT-input engineering test, not an
# autopilot product feature, hardware observation, airport procedure or lesson.
# There is no pose/state setter, native-step shortcut or Next-as-motion path.
const Existing=preload("res://first_flight_scene_tests/scene_checks.gd")
const Layout=preload("res://world/taxi/taxi_layout.gd")
const Readings=preload("res://cockpit/instruments/native_readings.gd")
const EngineStatus=preload("res://cockpit/instruments/engine_status.gd")
const Facade=preload("res://simulation/session_facade.gd")
const U64=preload("res://simulation/uint64.gd")
const STEP_US: int=100000 # Twelve ordinary 120-Hz ticks; time_scale stays 1.
const MAX_TICKS: int=144000 # Existing 20-minute recording boundary, per journey.
const GROUND_SPEED_LIMIT: float=8.0
const WAYPOINT_RADIUS: float=3.0
const STOP_RADIUS: float=2.0
const STOP_SPEED: float=0.15
const STOP_TICKS: int=120
const RETURN_IDS: Array[String]=["return-south","return-middle","return-north"]
const DEPARTURES: Array[int]=[36,18,36]
var _host: Node
var _checks: int=0
var _failures: Array[String]=[]
var _layout: Dictionary={}
var _session: String=""
var _profile: Dictionary={}
var _fingerprint: String=""
var _start: String=""
var _last_tick: int=0
var _travel: float=0.0
var _last_position: Array=[]
var _checkpoints: Array=[]
var _samples: Array=[]
var _systems: Dictionary={}
var _observer: RefCounted=Existing.new()

func _check(ok: bool,label: String) -> bool:
	_checks+=1
	if not ok:
		_failures.append(label)
		_host.call("check",false,"taxi_journey_"+label)
	return ok

func _axes(throttle: float=0.0,brake: float=1.0) -> Dictionary:
	return {"kind":"axes","roll":0.0,"pitch":0.0,"yaw":0.0,
		"throttle":throttle,"mixture":1.0,"left_brake":brake,"right_brake":brake,"trim":0.0}

func _read(scene: Node) -> Dictionary:
	return scene.facade.readback() if scene.facade!=null else {}

func _position(readback: Dictionary) -> Array:
	return readback.canonical.anchor_eus_position_m

func _speed(readback: Dictionary) -> float:
	var v: Dictionary=readback.aircraft.velocity_body_mps
	return sqrt(v.x*v.x+v.y*v.y+v.z*v.z)

func _distance(a: Array,b: Array) -> float:
	return sqrt(pow(float(a[0])-float(b[0]),2.0)+pow(float(a[2])-float(b[2]),2.0))

func _attitude(readback: Dictionary) -> Dictionary:
	var q: Dictionary=readback.aircraft.orientation_body_to_ned
	var m: Array=readback.canonical.body_to_anchor_eus
	return {"heading":atan2(float(m[0]),-float(m[6])),
		"pitch":asin(clampf(2.0*(q.w*q.y-q.z*q.x),-1.0,1.0)),
		"roll":atan2(2.0*(q.w*q.x+q.y*q.z),1.0-2.0*(q.x*q.x+q.y*q.y))}

func _wow(readback: Dictionary,all_gear: bool=false) -> bool:
	var count: int=0
	for contact in readback.aircraft.contacts:
		if contact.on_ground: count+=1
	return count==3 if all_gear else count>0

func _on_pavement(p: Array) -> bool:
	# Center containment is an engineering path gate, NOT airframe clearance,
	# collision or friction authority. Three pavement + three link rectangles.
	var rectangles: Array=_layout.pavement.duplicate(true)
	rectangles.append_array(_layout.links)
	for rectangle in rectangles:
		if absf(float(p[0])-float(rectangle.center_xz_m[0]))<=float(rectangle.half_extent_xz_m[0]) and absf(float(p[2])-float(rectangle.center_xz_m[1]))<=float(rectangle.half_extent_xz_m[1]): return true
	return false

func _on_runway(p: Array) -> bool:
	return absf(float(p[0]))<=20.0 and float(p[2])>=-1700.0 and float(p[2])<=100.0

func _qualified(source: Dictionary,paused: bool) -> bool:
	var view: Dictionary=Readings.from_readback(source)
	return _check(view.state==("paused" if paused else "live") and source.session_id==_session and source.model_identity==_profile and source.named_start==_start and source.native_source_fingerprint==_fingerprint and _fingerprint==Facade.NATIVE and source.prepared_world_sha256==Readings.WORLD and source.native_live and not source.historical and source.native_fault.is_empty() and source.error.is_empty() and source.time_scale==1.0,"current_actual_source_"+_start)

func _command(scene: Node,axes: Dictionary) -> bool:
	if scene.piston_mode():
		var result: Dictionary=scene.facade.set_pilot_intent(axes,_systems)
		scene.adopt_result(result) # SAME production observer/recorder path.
		return _check(result.ok,"piston_pilot_intent_admitted")
	return _check(scene.submit_axes(axes),"legacy_pilot_axes_admitted")

func _advance(scene: Node,axes: Dictionary,ground: bool,runway_only: bool=false) -> bool:
	if not _command(scene,axes) or not _check(scene.advance_wall_us(STEP_US),"ordinary_wall_advance"): return false
	var source: Dictionary=_read(scene)
	if not _qualified(source,false): return false
	if not _check(U64.valid(source.tick) and int(source.tick)==_last_tick+12 and int(source.tick)<=MAX_TICKS,"exact_tick_progress_and_recording_horizon"): return false
	_last_tick=int(source.tick)
	var p: Array=_position(source)
	_travel+=_distance(_last_position,p)
	_last_position=p.duplicate()
	if ground and not _check(_wow(source) and _speed(source)<=GROUND_SPEED_LIMIT and _on_pavement(p),"actual_ground_contact_speed_and_pavement"): return false
	if runway_only and not _check(_on_runway(p),"runway_spatial_containment"): return false
	var status: Dictionary=scene.observed_recorder.status()
	if not _check(status.state=="recording" and status.session_id==_session and status.last_observed_tick==source.tick and status.error.is_empty(),"ordinary_recording_observes_actual_tick"): return false
	if _last_tick%600==0:
		_samples.append({"session_id":_session,"tick":source.tick,"position_eus_m":p.duplicate(),"speed_mps":_speed(source),"any_wow":_wow(source),"all_wow":_wow(source,true),"axes":source.held_axes.duplicate(true)})
	return true

func _checkpoint(scene: Node,label: String) -> void:
	var source: Dictionary=_read(scene)
	_checkpoints.append({"label":label,"readback":source.duplicate(true),"recording_status":scene.observed_recorder.status(),"navigation":scene.taxi_navigation.observe(source),"travel_m":_travel})
	# Observer-only awaited boundary. No controller, time, geometry or pass gate changes.
	_check(bool(await _host.call("observe_checkpoint",scene,label)),"passive_checkpoint_capture_"+label)

func _pause(scene: Node,label: String) -> bool:
	scene.open_menu(label)
	if not _check(scene.paused and scene.menu_open,label+"_ordinary_pause"): return false
	await _checkpoint(scene,label)
	return _qualified(_read(scene),true)

func _resume(scene: Node) -> bool:
	# Existing SyntheticScene supplies explicitly released Raw to the normal
	# Mapper rearm check. This is not observed physical hardware.
	scene.close_menu()
	return _check(not scene.paused and not scene.menu_open,"ordinary_resume_released_raw")

func _manual_next(scene: Node,label: String) -> bool:
	# Only called AFTER actual measured waypoint reach. This emulates a manual
	# paused-page click; Navigation itself has no automatic arrival advance.
	if not await _pause(scene,label+"_manual_progress"): return false
	if not _check(scene.open_taxi(),label+"_open_for_manual_Next"): return false
	var source: Dictionary=_read(scene)
	var view: Dictionary=scene.taxi_navigation.observe(source)
	var before: PackedByteArray=_observer._snapshot(scene)
	var calls: int=scene.observed_adapters.back().entries.size()
	scene.taxi_panel.next_requested.emit(_session)
	var after: Dictionary=scene.taxi_navigation.observe(_read(scene))
	var expected: int=mini(view.point_index+1,view.point_count-1)
	var valid: bool=_check(after.point_index==expected and after.state==("manual-ended" if view.point_index==view.point_count-1 else "active") and _observer._snapshot(scene)==before and scene.observed_adapters.back().entries.size()==calls,label+"_manual_Next_after_motion_zero_authority_mutations")
	scene.dismiss_taxi()
	return valid and _resume(scene)

func _route(scene: Node,id: String) -> Dictionary:
	if not _check(scene.open_taxi(),"open_page_for_"+id): return {}
	var source: Dictionary=_read(scene)
	var authority: PackedByteArray=var_to_bytes(source)
	# An actual page signal makes the same choice as a user. Manual Next is
	# permitted only after actual measured waypoint reach in _drive below.
	scene.taxi_panel.route_requested.emit(id,_session)
	var view: Variant=scene.taxi_navigation.observe(_read(scene))
	var valid: bool=view is Dictionary and view.qualified and view.available and view.itinerary_id==id and view.point_index==0 and view.tick==source.tick
	_check(valid and var_to_bytes(_read(scene))==authority,"page_choice_does_not_move_aircraft_"+id)
	scene.dismiss_taxi()
	if not valid: return {}
	for itinerary in _layout.itineraries:
		if itinerary.id==id: return itinerary.duplicate(true)
	return {}

func _taxi_axes(source: Dictionary,target: Array,final: bool) -> Dictionary:
	var p: Array=_position(source)
	var attitude: Dictionary=_attitude(source)
	var desired: float=atan2(float(target[0])-float(p[0]),float(p[2])-float(target[2]))
	var error: float=wrapf(desired-attitude.heading,-PI,PI)
	var distance: float=_distance(p,target)
	var speed: float=_speed(source)
	var wanted: float=5.0 if absf(error)<0.20 and distance>15.0 else 1.3
	if final: wanted=minf(wanted,sqrt(maxf(0.0,distance-0.5)))
	var axes: Dictionary=_axes(clampf(0.13+0.16*(wanted-speed),0.0,0.65),clampf((speed-wanted)*0.6,0.0,1.0))
	axes.yaw=clampf(1.7*error-0.4*source.aircraft.angular_rate_body_radps.z,-1.0,1.0)
	if final and distance<=STOP_RADIUS: axes=_axes()
	return axes

func _drive(scene: Node,points: Array,label: String,stop_final: bool=true,runway_only: bool=false,manual_progress: bool=false) -> bool:
	var index: int=0
	var first_stopped_tick: int=-1
	var began: Array=_position(_read(scene)).duplicate()
	while index<points.size() and _last_tick<MAX_TICKS:
		var source: Dictionary=_read(scene)
		var target: Array=points[index]
		var final: bool=index==points.size()-1
		var radius: float=STOP_RADIUS if final and stop_final else WAYPOINT_RADIUS
		var reached: bool=_distance(_position(source),target)<=radius
		if reached and not (final and stop_final):
			await _checkpoint(scene,label+"_waypoint_"+str(index))
			if manual_progress and not await _manual_next(scene,label+"_"+str(index)): return false
			index+=1
			continue
		if final and reached and _speed(source)<=STOP_SPEED and _wow(source,true):
			if first_stopped_tick<0: first_stopped_tick=int(source.tick)
		else: first_stopped_tick=-1
		# No initial-sample credit. Consecutive observed qualifying states must
		# span120 actual native ticks; a lost condition starts a new interval.
		if first_stopped_tick>=0 and int(source.tick)-first_stopped_tick>=STOP_TICKS:
			await _checkpoint(scene,label+"_stopped")
			if manual_progress and not await _manual_next(scene,label+"_final"): return false
			return _check(_distance(began,points.back())<=5.0 or _distance(began,_position(source))>5.0,label+"_real_displacement_when_target_distant")
		if not _advance(scene,_taxi_axes(source,target,final and stop_final),true,runway_only): return false
		if _last_tick%120==0: await _host.get_tree().process_frame
	return _check(index==points.size() and not stop_final,label+"_completed_without_timeout")

func _points(route: Dictionary) -> Array:
	var points: Array=[]
	for point in route.points: points.append(point.point_eus_m.duplicate())
	return points

func _hold(scene: Node,seconds: int,label: String) -> bool:
	var target: Array=_position(_read(scene)).duplicate()
	for i in seconds*10:
		if not _advance(scene,_axes(),false): return false
		var observed: Dictionary=_read(scene)
		if not _check(_wow(observed,true) and _speed(observed)<=STOP_SPEED and _distance(target,_position(observed))<=0.25,label+"_every_held_observation"): return false
		if i%10==0: await _host.get_tree().process_frame
	return _check(_wow(_read(scene),true) and _speed(_read(scene))<=STOP_SPEED and _distance(target,_position(_read(scene)))<=0.25,label)

func _start_engine(scene: Node) -> bool:
	if not scene.piston_mode():
		# The authored initial CG has nominal gear clearance. These ordinary
		# recorded ticks are startup settling, not a claim of already-held WOW.
		var initial_position: Array=_position(_read(scene)).duplicate()
		for i in 50: # Existing native proof's five-second settling interval.
			if not _advance(scene,_axes(),false): return false
			var observed: Dictionary=_read(scene)
			if not _check(_on_pavement(_position(observed)) and _distance(initial_position,_position(observed))<=0.25 and observed.held_axes.left_brake==1.0 and observed.held_axes.right_brake==1.0,"ready_startup_settling_brakes_and_planar_bound"): return false
			if i%10==0: await _host.get_tree().process_frame
		if not _check(_wow(_read(scene),true) and _speed(_read(scene))<=STOP_SPEED,"ready_startup_settled_before_strict_hold"): return false
		await _checkpoint(scene,"ready_startup_settled_actual")
		return await _hold(scene,5,"ready_settled_brakes")
	var initial: Dictionary=EngineStatus.from_readback(_read(scene))
	if not _check(initial.readings["engine.running"].valid and initial.readings["engine.running"].value==false,"cold_native_combustion_initially_false"): return false
	_systems={"engine.ignition_left":true,"engine.ignition_right":true,"engine.starter":true,"fuel.feed":true}
	var fired: bool=false
	for i in 120:
		if not _advance(scene,_axes(0.25),false): return false
		var status: Dictionary=EngineStatus.from_readback(_read(scene))
		if status.readings["engine.running"].valid and status.readings["engine.running"].value==true:
			fired=true
			break
		if i%10==0: await _host.get_tree().process_frame
	if not _check(fired,"actual_cold_combustion_within_12_simulated_seconds"): return false
	_systems["engine.starter"]=false
	for i in 20:
		if not _advance(scene,_axes(0.15),false): return false
	var status: Dictionary=EngineStatus.from_readback(_read(scene))
	return _check(status.readings["engine.running"].value==true and status.readings["engine.starter"].value==false and _wow(_read(scene),true) and _speed(_read(scene))<=STOP_SPEED,"starter_released_actual_engine_self_running_brakes_held")

func _flight_axes(source: Dictionary,heading: float,desired_pitch: float,throttle: float,brake: bool=false) -> Dictionary:
	# Pitch-hold algebra has source provenance in tests/interactive/native.cpp.
	# Here every command is admitted as PILOT through the real Facade, rather
	# than reusing that older proof's scenario authority or straight-line PASS.
	var attitude: Dictionary=_attitude(source)
	var a: Dictionary=source.aircraft
	var alpha: float=atan2(a.velocity_body_mps.z,a.velocity_body_mps.x)
	var heading_error: float=wrapf(heading-attitude.heading,-PI,PI)
	var bank: float=clampf(heading_error*0.8,-0.15,0.15)
	var axes: Dictionary=_axes(throttle,1.0 if brake else 0.0)
	axes.roll=clampf(2.0*(bank-attitude.roll)-0.3*a.angular_rate_body_radps.x,-0.25,0.25)
	axes.pitch=clampf((alpha-0.02)/0.7+2.0*(desired_pitch-attitude.pitch)-0.5*a.angular_rate_body_radps.y,-0.4,0.4)
	axes.yaw=clampf(0.5*heading_error,-0.25,0.25)
	return axes

func _flight(scene: Node,runway: int) -> bool:
	var heading: float=0.0 if runway==36 else PI
	var direction: float=-1.0 if runway==36 else 1.0
	var origin: Array=_position(_read(scene)).duplicate()
	var phase: int=0
	var phase_ticks: int=0
	var airborne_ticks: int=0
	var airborne_distance: float=0.0
	var prior_airborne: Array=[]
	var takeoff: Dictionary={}
	var touchdown: Dictionary={}
	var maximum_height: float=float(origin[1])
	var first_stopped_tick: int=-1
	for i in 1800: # Hard maximum 180 simulated seconds, never a PASS on expiry.
		var source: Dictionary=_read(scene)
		var p: Array=_position(source)
		var height: float=float(p[1])
		var alpha: float=atan2(source.aircraft.velocity_body_mps.z,source.aircraft.velocity_body_mps.x)
		maximum_height=maxf(maximum_height,height)
		if not _wow(source):
			# Credit only elapsed intervals between qualifying observations.
			if not prior_airborne.is_empty():
				airborne_ticks+=12
				airborne_distance+=_distance(prior_airborne,p)
			prior_airborne=p.duplicate()
		else: prior_airborne=[]
		if phase==0 and not _wow(source) and height>3.0:
			takeoff=source.duplicate(true)
			await _checkpoint(scene,"actual_takeoff_"+str(runway))
			phase=1; phase_ticks=0
		elif phase==1 and height>=12.0:
			await _checkpoint(scene,"actual_required_height_"+str(runway))
			phase=2; phase_ticks=0
		# The flight gate is three seconds AIRBORNE, not an additional three
		# seconds after reaching twelve metres. No spatial gate is relaxed.
		if phase==2 and airborne_ticks>=360 and airborne_distance>=100.0:
			await _checkpoint(scene,"actual_descent_after_flight_gates_"+str(runway))
			phase=3; phase_ticks=0
		if phase==3 and _wow(source):
			touchdown=source.duplicate(true)
			await _checkpoint(scene,"actual_touchdown_"+str(runway))
			phase=4; phase_ticks=0
		if phase==4 and _wow(source,true) and _speed(source)<=STOP_SPEED and _on_runway(p):
			if first_stopped_tick<0: first_stopped_tick=int(source.tick)
		else: first_stopped_tick=-1
		# Touchdown/rollout time is not stopped dwell; every observed loss resets.
		if first_stopped_tick>=0 and int(source.tick)-first_stopped_tick>=STOP_TICKS:
			return _check(not takeoff.is_empty() and not touchdown.is_empty() and airborne_ticks>=360 and airborne_distance>=100.0 and maximum_height>=12.0 and _on_runway(_position(touchdown)) and _on_runway(p),"actual_runway_takeoff_flight_touchdown_braked_stop_"+str(runway))
		# Reject a missed runway before its endpoint; never extend pavement or
		# turn an off-field touchdown into successful airport completion.
		if not _check((float(p[2])-float(origin[2]))*direction<1600.0 and absf(float(p[0]))<=15.0,"flight_stays_inside_declared_runway_corridor"): return false
		# Original test-only pilot recipe: begin rotation earlier and request
		# more positive pitch, using unchanged admitted axes/physical dynamics.
		# These choices are not performance data or guaranteed runway success.
		var desired: float=0.18 if _speed(source)>28.0 else 0.0
		var throttle: float=1.0
		if phase==1: desired=0.14; throttle=1.0
		elif phase==2: desired=0.03; throttle=0.6
		elif phase==3: desired=alpha-(0.045 if height>4.0 else 0.018); throttle=0.3 if height>4.0 else 0.0
		elif phase==4: desired=0.0; throttle=0.0
		if not _advance(scene,_flight_axes(source,heading,desired,throttle,phase==4),false,true): return false
		phase_ticks+=12
		if i%10==0: await _host.get_tree().process_frame
	return _check(false,"flight_phase_timeout_"+str(runway))

func _journey(scene: Node,runway: int,return_id: String) -> bool:
	if not _resume(scene) or not await _start_engine(scene): return false
	await _checkpoint(scene,"engine_ready_actual")
	if not await _pause(scene,"choose_outbound"): return false
	var route: Dictionary=_route(scene,"outbound-"+str(runway))
	if route.is_empty() or not _resume(scene): return false
	if not await _drive(scene,_points(route),"outbound_"+str(runway),true,false,true): return false
	# The actual stop precedes deliberate crossing. It is not ATC clearance.
	if not await _hold(scene,2,"actual_hold_reference_two_seconds"): return false
	await _checkpoint(scene,"actual_stop_before_runway_crossing")
	var z: float=30.0 if runway==36 else -1630.0
	if not await _drive(scene,[[0.0,0.0,z],[0.0,0.0,z+(-20.0 if runway==36 else 20.0)]],"line_up_"+str(runway),false): return false
	if not await _flight(scene,runway): return false
	# Backtaxi is an explicit scripted engineering action on this empty original
	# field, not an airport procedure or an operational clearance claim.
	var selected: Dictionary={}
	for candidate in _layout.itineraries:
		if candidate.id==return_id: selected=candidate
	if not _check(not selected.is_empty(),"closed_return_id"): return false
	var entry: Array=selected.points[0].point_eus_m
	if not await _drive(scene,[[0.0,0.0,float(entry[2])]],"backtaxi_to_"+return_id,true,true): return false
	if not await _pause(scene,"choose_"+return_id): return false
	var back: Dictionary=_route(scene,return_id)
	if back.is_empty() or not _resume(scene): return false
	if not await _drive(scene,_points(back),return_id,true,false,true): return false
	await _checkpoint(scene,"actual_PARK1_stopped")
	var final: Dictionary=_read(scene)
	return _check(_distance(_position(final),[108.0,0.0,18.0])<=STOP_RADIUS and _speed(final)<=STOP_SPEED and _wow(final,true) and _travel>250.0 and scene.taxi_navigation.observe(final).state=="manual-ended","actual_same_session_return_not_Next_as_movement_"+return_id)

func run(host: Node) -> Dictionary:
	_host=host
	var admitted: Dictionary=Layout.load()
	if not _check(admitted.ok,"frozen_packaged_layout"): return _result([])
	_layout=admitted.value
	var rows: Array=[]
	for pair in [[Facade.LEGACY_PROFILE.id,"apron-ready"],[Facade.PISTON_PROFILE.id,"piston-cold-apron"]]:
		for index in RETURN_IDS.size():
			_host.call("begin_journey",pair[0],pair[1],RETURN_IDS[index],DEPARTURES[index])
			var scene: Node=Existing.SyntheticScene.new()
			host.add_child(scene)
			scene.set_process(false); scene.set_process_input(false)
			scene.set_process_unhandled_input(false); scene.set_process_unhandled_key_input(false)
			var opened: bool=scene.restart(true,"calm",pair[0],pair[1])
			var failures_before: int=_failures.size()
			_check(opened,"actual_apron_restart_"+pair[1])
			_checkpoints=[]; _samples=[]; _travel=0.0; _last_tick=0; _systems={}
			var success: bool=false
			var facade: RefCounted=scene.facade
			var adapter: RefCounted=facade.get("_bridge") if facade!=null else null
			if opened:
				var source: Dictionary=_read(scene)
				_session=source.session_id; _fingerprint=source.native_source_fingerprint; _start=pair[1]
				_profile=(Facade.PISTON_PROFILE if pair[0]==Facade.PISTON_PROFILE.id else Facade.LEGACY_PROFILE).duplicate(true)
				_last_position=_position(source).duplicate()
				if _qualified(source,true) and _check(source.tick=="0" and _distance(_last_position,[108.0,1.05,18.0])<0.001,"actual_fixed_apron_native_start"):
					await _checkpoint(scene,"actual_initial_paused")
					success=await _journey(scene,DEPARTURES[index],RETURN_IDS[index])
			var final: Dictionary=facade.readback() if facade!=null else {}
			var recording: Variant=scene.observed_recorder.recording()
			var joined: bool=scene.close_session()
			_check(joined and (facade==null or not facade.readback().native_live),"actual_native_close_join")
			var audio_joined: bool=true
			if scene.sound!=null:
				audio_joined=bool(await scene.sound.shutdown())
				_check(audio_joined,"actual_audio_shutdown_join")
			# Raw forwarding ledger is actual producer output, not an expected
			# golden. Root must retain it with the separate fullprecision receipt.
			var calls: Array=adapter.entries.duplicate(true) if adapter!=null else []
			var pilot_count: int=0
			for entry in calls:
				if entry.method=="submit":
					pilot_count+=1
					var command: Dictionary=entry.arguments[0]
					_check(command.source_id=="pilot.controls" and command.authority=="pilot" and command.assistance=={"profile_id":"unassisted","active":[]} and command.session_id==_session,"actual_recorded_commands_are_unassisted_pilot")
			_check(not opened or pilot_count>0,"nonvacuous_actual_pilot_command_ledger")
			var lifecycle: Array=[]
			for observed in scene.observed_adapters: lifecycle.append(observed.entries.duplicate(true))
			rows.append({"profile":pair[0],"start":pair[1],"runway":DEPARTURES[index],"return_itinerary":RETURN_IDS[index],"passed":success and joined and _failures.size()==failures_before,"session_id":_session if opened else null,"source_fingerprint":_fingerprint if opened else null,"initial_and_waypoint_readbacks":_checkpoints.duplicate(true),"five_second_samples":_samples.duplicate(true),"final_readback":final,"recording":recording,"native_calls":calls,"scene_lifecycle_calls":lifecycle,"actual_joined":joined,"travel_m":_travel})
			if not joined or not audio_joined:
				# Keep the owning node attached for Root's failure coordinator. Do
				# not free/replace an executive whose shutdown is unconfirmed.
				Input.mouse_mode=Input.MOUSE_MODE_VISIBLE
				return _result(rows)
			scene.free()
	Input.mouse_mode=Input.MOUSE_MODE_VISIBLE
	_check(rows.size()==6,"all_six_supported_journeys_attempted")
	for row in rows: _check(row.passed,"journey_complete_"+row.start+"_"+row.return_itinerary)
	return _result(rows)

func _result(rows: Array) -> Dictionary:
	return {"schema":"TaxiPilotJourneyChecks/v1","passed":_failures.is_empty() and rows.size()==6,"checks":_checks,"failures":_failures.duplicate(),"journeys":rows,"scope":"Real native state through scripted normalized PILOT intents and released synthetic Raw. Two apron starts, both runway stop references and runway flight/touchdown, each return link to PARK1; actual source/session, unchanged geometry, recording and joins. No teleport, Next-as-movement, hardware/pilot/procedure/fidelity or shipping acceptance. Unexecuted source until a separately authorized Root run."}
