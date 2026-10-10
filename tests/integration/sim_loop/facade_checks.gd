extends RefCounted
# Original MIT. Active tests: no assertion depends on export debug settings.
const Facade = preload("res://simulation/session_facade.gd")
const U64 = preload("res://simulation/uint64.gd")
const Frames = preload("res://simulation/canonical_frames.gd")
const CATEGORIES: Array[String] = ["ownship","cockpit","camera","world","light","spatial_audio","local_particles"]
const RESULT_KEYS: Array[String] = ["ok","error","completed","readback","admission","native_rejection","applied_commands","events","observation_complete"]
const READBACK_KEYS: Array[String] = ["host_mode","error","historical","session_id","tick","aircraft","atmosphere","held_axes","native_outcome","native_live","paused","time_scale","debt_quanta","native_fault","named_start","model_identity","native_source_fingerprint","prepared_world_sha256","world_anchor","canonical"]
const DOUBLE_ARITHMETIC_ALLOWANCE: float = 0.000000000002

class ObservedAdapter extends RefCounted:
	# Default six-method wrapper delegates to the actual native extension.
	# Explicit synthetic modes reject close-pause before native submission,
	# return an unjoined close acknowledgement without closing, or mutate owned
	# reply packets. Partial-prefix calls five actual ticks then reports a
	# synthetic coverage boundary. These test faults never introduce a solver.
	var native: RefCounted
	var mode: String
	var requests: Array[int] = []
	var submitted: Array = []
	var controls: Array = []
	var integrated: int = 0
	var close_calls: int = 0
	var joined: bool = false
	var latest: Dictionary = {}
	var captured: Array = []
	func _init(mutant: String = "") -> void:
		mode = mutant
		native = ClassDB.instantiate("FlightInteractiveSession") as RefCounted
	func open_session(model_root: String, named_start: String, wind_profile: Variant="calm") -> Dictionary:
		latest = native.call("open_session",model_root,named_start,wind_profile)
		if mode=="native_fingerprint": latest.native_source_fingerprint=("0" if Facade.NATIVE[0]!="0" else "1")+Facade.NATIVE.substr(1)
		elif mode=="wind_missing": latest.erase("wind_profile")
		elif mode=="wind_echo": latest.wind_profile="calm"
		elif mode=="wind_extra": latest.wind_setup={"profile":wind_profile}
		elif mode=="wind_actual":
			var weather: Dictionary=JSON.parse_string(latest.atmosphere_json)
			weather.wind_toward_ned_mps.x=5.0
			latest.atmosphere_json=JSON.stringify(weather)
		return latest.duplicate(true)
	func read_state() -> Dictionary:
		return native.call("read_state")
	func submit(command: Dictionary) -> Dictionary:
		submitted.append(command.duplicate(true))
		var reply: Dictionary = native.call("submit",command)
		if mode == "rejected_admission":
			reply.queued = false
			reply.rejection = 1
		return reply
	func session_control(control: Dictionary) -> Dictionary:
		controls.append(control.duplicate(true))
		if mode == "close_pause_rejected":
			# Synthetic rejection occurs before calling native: no pause is admitted.
			var rejected: Dictionary = latest.duplicate(true)
			rejected.rejection = 1
			return rejected
		return native.call("session_control",control)
	func step_fixed(count: int) -> Dictionary:
		requests.append(count)
		var reply: Dictionary = native.call("step_fixed",mini(5,count) if mode == "partial_prefix" else count)
		integrated += int(reply.get("completed",0))
		var before: Dictionary = latest.duplicate(true)
		latest = reply.duplicate(true)
		captured.append(reply.duplicate(true))
		if mode == "partial_prefix":
			reply.outcome = "coverage_blocked"
			reply.fault = "SYNTHETIC partial-reply boundary after actual five-tick prefix"
		elif mode == "malformed_aircraft":
			reply.aircraft_json = "{"
		elif mode == "negative_mass":
			var aircraft: Dictionary = JSON.parse_string(reply.aircraft_json)
			aircraft.mass_kg = -1.0
			reply.aircraft_json = JSON.stringify(aircraft)
		elif mode == "negative_density":
			var weather: Dictionary = JSON.parse_string(reply.atmosphere_json)
			weather.density_kgpm3 = -1.0
			reply.atmosphere_json = JSON.stringify(weather)
		elif mode == "extra_position_member":
			var aircraft: Dictionary = JSON.parse_string(reply.aircraft_json)
			aircraft.position.uncontracted = 1
			reply.aircraft_json = JSON.stringify(aircraft)
		elif mode == "wrong_weather_tick":
			var weather: Dictionary = JSON.parse_string(reply.atmosphere_json)
			weather.tick = "0"
			reply.atmosphere_json = JSON.stringify(weather)
		elif mode == "impossible_completed":
			reply.completed = count + 1
		elif mode == "dropped_command" and not reply.applied_commands_json.is_empty():
			reply.applied_commands_json = []
			reply.held_axes = before.held_axes.duplicate(true)
		elif mode == "duplicate_command" and not reply.applied_commands_json.is_empty():
			reply.applied_commands_json.append(reply.applied_commands_json[0])
		elif mode == "unadmitted_command" and not reply.applied_commands_json.is_empty():
			var command: Dictionary = JSON.parse_string(reply.applied_commands_json[0])
			command.payload.roll = 0.5
			reply.applied_commands_json[0] = JSON.stringify(command)
		elif mode == "dropped_event":
			reply.events_json = []
		elif mode == "duplicate_event" and not reply.events_json.is_empty():
			reply.events_json.append(reply.events_json[0])
		return reply
	func close() -> Dictionary:
		close_calls += 1
		if mode == "unjoined":
			return {"ok":true,"joined":false}
		var reply: Dictionary = native.call("close")
		joined = reply.get("ok") == true and reply.get("joined") == true
		return reply

static func _check(report: Dictionary, condition: bool, label: String) -> void:
	report.checks += 1
	if not condition:
		report.failures.append(label)

static func _same_keys(value: Dictionary, keys: Array) -> bool:
	var actual: Array = value.keys()
	var expected: Array = keys.duplicate()
	actual.sort()
	expected.sort()
	return actual == expected

static func _result_shape(report: Dictionary, result: Dictionary, label: String) -> void:
	_check(report,_same_keys(result,RESULT_KEYS),label+":closed Result keys")
	_check(report,result.get("readback") is Dictionary and _same_keys(result.readback,READBACK_KEYS),label+":closed Readback keys")
	_check(report,result.get("completed") is int and result.completed >= 0 and result.completed <= 32,label+":actual bounded completed")
	_check(report,result.get("applied_commands") is Array and result.get("events") is Array,label+":owned record arrays")

static func _normal(value: Variant) -> Variant:
	if value is Dictionary:
		var out: Dictionary = {}
		for key in value:
			out[key] = "FRESH_SESSION" if key == "session_id" else _normal(value[key])
		return out
	if value is Array:
		var out: Array = []
		for item in value:
			out.append(_normal(item))
		return out
	return value

static func _axes(index: int, held: Dictionary) -> Dictionary:
	var out: Dictionary = held.duplicate(true)
	out.roll = [0.03125,-0.015625,0.0078125,0.0][index]
	out.pitch = [-0.0078125,0.015625,0.0,-0.00390625][index]
	out.yaw = [0.015625,0.0,-0.015625,0.0078125][index]
	out.throttle = [0.25,0.3125,0.1875,0.28125][index]
	out.left_brake = 0.0625
	out.right_brake = 0.0625
	out.trim = 0.0
	return out

static func _adopt_absent(facade: RefCounted, report: Dictionary, label: String) -> void:
	_check(report,not facade.visual_pose().valid,label+":no pose before adoption")
	var registered: Dictionary = facade.render_origin.call("register_participant","native-only-fixture",null,CATEGORIES)
	_check(report,registered.ok,label+":explicit all-category absence")
	var world: Dictionary = facade.readback().world_anchor
	var anchor: Dictionary = Frames.anchor(world.latitude_rad,world.longitude_rad,world.ellipsoid_height_m)
	var adopted: Dictionary = facade.render_origin.call("rebase",anchor.ecef)
	_check(report,adopted.ok and adopted.origin.valid,label+":initial same-anchor version")
	_check(report,facade.visual_pose().valid,label+":pose only after adoption")

static func _uint_cases(reference: Dictionary, report: Dictionary) -> void:
	for row in reference.uint64.values:
		_check(report,U64.valid(row.value),"uint64 valid "+row.value)
		var next: Dictionary = U64.increment(row.value)
		_check(report,next.ok == (not row.increment_rejected) and next.value == row.increment,"uint64 increment "+row.value)
	for value in reference.uint64.invalid:
		_check(report,not U64.valid(value),"uint64 reject "+value)
	for row in reference.uint64.comparisons:
		_check(report,U64.compare(row.left,row.right) == int(row.order),"uint64 lexical compare")
	for row in reference.uint64.differences:
		var difference: Dictionary = U64.small_difference(row.new,row.old)
		_check(report,difference.ok == row.small_difference_allowed,"uint64 bounded difference")
		if difference.ok:
			_check(report,difference.value == int(row.difference),"uint64 exact difference")
	var reversed: Dictionary = reference.uint64.reversed_difference
	_check(report,not U64.small_difference(reversed.new,reversed.old).ok,"uint64 negative difference")

static func _flatten(rows: Array) -> Array:
	var out: Array = []
	for row in rows:
		out.append_array(row)
	return out

static func _close_scalar(actual: float, expected: float) -> bool:
	return is_finite(actual) and absf(actual-expected) <= DOUBLE_ARITHMETIC_ALLOWANCE

static func _geometry_cases(reference: Dictionary, report: Dictionary) -> void:
	var geometry: Dictionary = reference.geometry
	# Load the intended binary64 inputs without Godot's decimal JSON parser
	# rounding them before the canonical cancellation test. This is test data,
	# not a new runtime/wire encoding.
	var supplied: Dictionary = {}
	for name in geometry.supplied_binary64_le:
		var values: Array = []
		for encoded in geometry.supplied_binary64_le[name]:
			values.append(String(encoded).hex_decode().decode_double(0))
		supplied[name] = values
	var rotation: Array = supplied.ecef_to_anchor_eus
	var prepared: Dictionary = Frames.anchor(PI/6.0,PI/3.0,0.0)
	for i in 9:
		_check(report,_close_scalar(prepared.rotation[i],rotation[i]),"analytic nonzero-latitude basis")
	for origin in ["origin_a_ecef_m","origin_b_ecef_m"]:
		for point in ["ownship_ecef_m","camera_ecef_m"]:
			var expected: Dictionary = geometry.exact_supplied_value_expectations[origin+":"+point]
			var projected: Array = Frames.project(supplied[point],supplied[origin],rotation)
			_check(report,projected.size() == 3,"binary64 projection shape")
			for i in 3:
				_check(report,_close_scalar(projected[i],String(expected.decimal_reference_m[i]).to_float()),"exact rational projection before float conversion")
			var visual: Transform3D = Frames.transform(projected,[0.0,1.0,0.0,0.0,0.0,-1.0,-1.0,0.0,0.0])
			for i in 3:
				_check(report,float(visual.origin[i]) == String(expected.final_float32_le[i]).hex_decode().decode_float(0),"correct final float32 conversion")
			_check(report,visual.basis == Basis.IDENTITY,"native FRD to artist right/up/aft identity")
	var relative_at_a: Array = []
	for origin in ["origin_a_ecef_m","origin_b_ecef_m"]:
		var own: Array = Frames.project(supplied.ownship_ecef_m,supplied[origin],rotation)
		var cam: Array = Frames.project(supplied.camera_ecef_m,supplied[origin],rotation)
		var relative: Array = []
		for i in 3:
			relative.append(cam[i]-own[i])
			_check(report,_close_scalar(relative[i],String(geometry.invariant_camera_minus_ownship_m[i]).to_float()),"origin-independent near-camera relative geometry")
		if relative_at_a.is_empty():
			relative_at_a = relative
		else:
			for i in 3:
				_check(report,_close_scalar(relative[i],relative_at_a[i]),"two-origin camera invariance")
	var change: Dictionary = geometry.frame_change
	var endpoints: Array = []
	for index in 2:
		var latitude: float = deg_to_rad(float(change.current_latitudes_deg[index]))
		var snapshot: Dictionary = {"position":{"latitude_rad":latitude,"longitude_rad":PI/3.0},"ecef_position_m":{"x":1000000.0,"y":-2000000.0,"z":3000000.0},"orientation_body_to_ned":{"w":1.0,"x":0.0,"y":0.0,"z":0.0}}
		var canonical: Dictionary = Frames.derive(snapshot,prepared)
		_check(report,not canonical.is_empty(),"frame conversion analytic input")
		var expected: Array = _flatten(change.endpoint_common_bases[index])
		for i in 9:
			_check(report,_close_scalar(canonical.body_to_anchor_eus[i],String(expected[i]).to_float()),"current NED converted into fixed prepared basis")
		endpoints.append(canonical.body_to_anchor_eus)
	var midpoint: Array = Frames.interpolate_rotation(endpoints[0],endpoints[1],0.5)
	var expected_mid: Array = _flatten(change.shortest_arc_midpoint_common_basis)
	for i in 9:
		_check(report,_close_scalar(midpoint[i],String(expected_mid[i]).to_float()),"analytic common-frame shortest-arc midpoint")
	_check(report,not _close_scalar(midpoint[3],endpoints[0][3]),"equal raw NED quaternion blend is distinguishably wrong")
	_check(report,Frames.project([1e308,0.0,0.0],[-1e308,0.0,0.0],[1.0,0.0,0.0,0.0,1.0,0.0,0.0,0.0,1.0]).is_empty(),"finite inputs with overflowing subtraction reject")

static func _native_profiles(model_root: String, reference: Dictionary, report: Dictionary) -> void:
	var per_scale: Dictionary = {}
	var common_physics: Variant = null
	for profile in reference.wall_profiles:
		var label: String = "actual "+profile.profile+"Hz scale"+profile.scale
		var facade: RefCounted = Facade.new()
		var opened: Dictionary = facade.start(model_root,"ground-ready")
		_result_shape(report,opened,label+":start")
		_check(report,opened.ok,label+":actual native open")
		if not opened.ok:
			facade.close()
			continue
		_adopt_absent(facade,report,label)
		var parts: PackedStringArray = String(profile.scale).split("/")
		var scale: float = float(parts[0])/(float(parts[1]) if parts.size() == 2 else 1.0)
		var scaled: Dictionary = facade.set_time_scale(scale)
		_check(report,scaled.ok,label+":scale accepted")
		var commands: Array = []
		var events: Array = scaled.events.duplicate(true)
		var cuts: Array = []
		var expected_axes: Dictionary = _axes(0,opened.readback.held_axes)
		var intent: Dictionary = facade.set_axes(expected_axes)
		_check(report,intent.ok and intent.admission == "intent_stored",label+":local intent distinguished")
		# A caller mutation must not alter the intent actually stored by the facade.
		expected_axes.roll = 0.9
		var completed_profile: bool = true
		for row in profile.rows:
			var result: Dictionary = facade.advance_wall_us(int(row.elapsed_us))
			_result_shape(report,result,label+":advance")
			_check(report,result.ok,label+":valid reference wall interval")
			_check(report,result.completed == int(row.completed_this_call),label+":exact completed per call")
			_check(report,result.readback.tick == str(int(row.completed_total)) and result.readback.debt_quanta == int(row.debt_quanta),label+":exact Fraction oracle tick/debt")
			commands.append_array(result.applied_commands)
			events.append_array(result.events)
			if not result.ok or result.completed != int(row.completed_this_call) or result.readback.tick != str(int(row.completed_total)) or result.readback.debt_quanta != int(row.debt_quanta):
				completed_profile = false
				break
			if row.declared_native_cut:
				cuts.append({"tick":result.readback.tick,"aircraft":_normal(result.readback.aircraft),"atmosphere":_normal(result.readback.atmosphere),"held_axes":result.readback.held_axes.duplicate(true)})
				var native_tick: int = int(row.completed_total)
				if native_tick < 120:
					var paused: Dictionary = facade.set_paused(true)
					_check(report,paused.ok and paused.completed == 0,label+":actual pause/drain at equal native cut")
					events.append_array(paused.events)
					var noop: Dictionary = facade.set_paused(true)
					_check(report,noop.ok and noop.admission == "none" and noop.events.is_empty(),label+":redundant lifecycle suppressed")
					var excluded: Dictionary = facade.advance_wall_us(10000000)
					_check(report,excluded.ok and excluded.completed == 0 and excluded.readback.tick == str(native_tick) and excluded.readback.debt_quanta == 0,label+":paused wall excluded")
					var resumed: Dictionary = facade.set_paused(false)
					_check(report,resumed.ok and resumed.events.is_empty(),label+":resume ACK is not invented event")
					_check(report,facade.set_axes(_axes(int(native_tick/30.0),opened.readback.held_axes)).ok,label+":changed intent at next declared cut")
				var pose: Dictionary = facade.visual_pose()
				_check(report,pose.valid,label+":owned visual pose")
		var copied: Dictionary = facade.readback()
		copied.aircraft.mass_kg = -123.0
		_check(report,facade.readback().aircraft.mass_kg > 0,label+":readback mutation cannot alter authority")
		_check(report,commands.size() == 4,label+":four exactly-once actual commands")
		for i in commands.size():
			_check(report,commands[i].tick == str(1+i*30) and commands[i].sequence == str(i+1) and commands[i].payload == _axes(i,opened.readback.held_axes),label+":actual typed command schedule")
		var final_truth: Dictionary = facade.readback()
		var closed: Dictionary = facade.close()
		_check(report,closed.ok and not closed.readback.native_live and closed.readback.historical,label+":confirmed joined close")
		events.append_array(closed.events)
		_check(report,not facade.visual_pose().valid,label+":closed visual invalid")
		var normalized: Dictionary = {"cuts":cuts,"commands":_normal(commands),"events":_normal(events)}
		if per_scale.has(profile.scale):
			_check(report,normalized == per_scale[profile.scale],label+":same-scale exact native state/command/lifecycle equivalence")
		else:
			per_scale[profile.scale] = normalized.duplicate(true)
		var physics: Dictionary = {"cuts":cuts,"commands":_normal(commands)}
		if common_physics == null:
			common_physics = physics.duplicate(true)
		else:
			_check(report,physics == common_physics,label+":all-scale unchanged native dt/state/commands")
		report.native_profiles.append({"cadence":profile.profile,"scale":profile.scale,"completed_profile":completed_profile,"final_tick":final_truth.tick,"final_debt_quanta":final_truth.debt_quanta,"cuts":cuts,"applied_commands":commands,"events":events,"scope":"ACTUAL same-build native fixture; only fresh session identifiers normalized for comparison"})

static func _native_lifecycle(model_root: String, report: Dictionary) -> void:
	var observed: Array = []
	var make_adapter: Callable = func() -> RefCounted:
		var value: RefCounted = ObservedAdapter.new()
		observed.append(value)
		return value
	var facade: RefCounted = Facade.new(make_adapter)
	var opened: Dictionary = facade.start(model_root,"ground-ready")
	_check(report,opened.ok,"actual observed lifecycle open")
	if not opened.ok:
		facade.close()
		return
	var adapter: RefCounted = observed[0]
	_adopt_absent(facade,report,"actual observed lifecycle")
	var before: Dictionary = adapter.read_state()
	var rb: Dictionary = facade.readback()
	var anchor: Dictionary = Frames.anchor(rb.world_anchor.latitude_rad,rb.world_anchor.longitude_rad,rb.world_anchor.ellipsoid_height_m)
	var shifted: Array = anchor.ecef.duplicate()
	shifted[0] += 128.0
	_check(report,facade.render_origin.call("rebase",shifted).ok,"actual worker origin transaction accepted")
	_check(report,adapter.read_state() == before,"origin transaction leaves actual native read_state/held/publication unchanged")
	_check(report,adapter.requests.is_empty() and adapter.submitted.is_empty(),"origin has no native step or input calls")
	var original: Dictionary = facade.readback()
	for invalid_kind in ["mixture", "nan_brake", "extra", "kind", "throttle"]:
		var invalid: Dictionary = opened.readback.held_axes.duplicate(true)
		if invalid_kind == "mixture":
			invalid.mixture = 0.5
		elif invalid_kind == "nan_brake":
			invalid.left_brake = NAN
		elif invalid_kind == "extra":
			invalid.undocumented = 1
		elif invalid_kind == "kind":
			invalid.kind = "system"
		else:
			invalid.throttle = 1.001
		_check(report,not facade.set_axes(invalid).ok,"invalid caller axes reject "+invalid_kind)
		_check(report,facade.readback() == original and adapter.submitted.is_empty(),"invalid axes preserve publication/admission")
	_check(report,not facade.advance_wall_us(-1).ok and facade.readback() == original,"negative elapsed before mutation")
	_check(report,not facade.set_time_scale(0.4).ok and facade.readback() == original,"unsupported scale before mutation")
	var alien_thread: Thread = Thread.new()
	var status: Error = alien_thread.start(func() -> Dictionary: return {"mutation":facade.set_axes(_axes(0,opened.readback.held_axes)),"read":facade.readback(),"visual":facade.visual_pose()})
	_check(report,status == OK,"wrong-thread fixture starts")
	if status == OK:
		var rejected: Dictionary = alien_thread.wait_to_finish()
		_result_shape(report,rejected.mutation,"wrong-thread independent rejection")
		_check(report,not rejected.mutation.ok and facade.readback() == original and adapter.submitted.is_empty(),"wrong-thread intent cannot mutate or call native")
		_check(report,_same_keys(rejected.read,READBACK_KEYS) and not rejected.visual.valid,"wrong-thread readback exact shape and invalid visual")
		for key in ["session_id","tick","aircraft","atmosphere","held_axes","native_outcome","named_start","model_identity","native_source_fingerprint","prepared_world_sha256","world_anchor","canonical"]:
			_check(report,rejected.read[key] == null and rejected.mutation.readback[key] == null,"wrong-thread returns independent nullable state "+key)
		_check(report,rejected.read.historical and not rejected.read.native_live and not rejected.read.error.is_empty(),"wrong-thread read does not imply authority or native liveness")
	var accrued: Dictionary = facade.advance_wall_us(4000)
	_check(report,accrued.ok and accrued.completed == 0 and accrued.readback.debt_quanta == 1920000,"fractional initial debt")
	var paused: Dictionary = facade.set_paused(true)
	_check(report,paused.ok and paused.events.size() == 1 and adapter.integrated == 0,"paused step1 drains actual event with zero integration")
	var scaled: Dictionary = facade.set_time_scale(2.0)
	_check(report,scaled.ok and scaled.readback.debt_quanta == 1920000,"scale during pause preserves exact debt")
	var excluded: Dictionary = facade.advance_wall_us(10000000)
	_check(report,excluded.ok and excluded.completed == 0 and excluded.readback.debt_quanta == 1920000,"excluded long paused interval")
	var resumed: Dictionary = facade.set_paused(false)
	_check(report,resumed.ok and resumed.events.is_empty() and resumed.observation_complete,"resume may leave real lifecycle event pending")
	var stepped: Dictionary = facade.advance_wall_us(3000)
	_check(report,stepped.ok and stepped.completed == 1 and stepped.readback.debt_quanta == 800000 and stepped.events.size() == 2,"next actual step observes deferred scale and resume once")
	_check(report,facade.set_time_scale(0.25).ok,"settled scale quarter")
	var quarter: Dictionary = facade.advance_wall_us(10000)
	_check(report,quarter.ok and quarter.completed == 0 and quarter.readback.debt_quanta == 2000000,"quarter scale Fraction debt")
	_check(report,facade.set_time_scale(4.0).ok,"settled scale four")
	var accelerated: Dictionary = facade.advance_wall_us(12500)
	_check(report,accelerated.ok and accelerated.completed == 6 and accelerated.readback.tick == "7" and accelerated.readback.debt_quanta == 2000000,"all transitions exact7.5ticks")
	var old_session: String = facade.readback().session_id
	var reset: Dictionary = facade.reset("ground-ready")
	_check(report,reset.ok and adapter.joined and observed.size() == 2,"reset joins previous actual worker before allocating fresh")
	_check(report,reset.readback.session_id != old_session and reset.readback.tick == "0" and reset.readback.debt_quanta == 0,"fresh reset identity/tick/debt")
	_check(report,not facade.visual_pose().valid,"reset requires new origin declarations")
	_check(report,facade.close().ok and observed[1].joined,"new actual worker joined")
	_check(report,facade.close().ok,"idempotent close")
	report.lifecycle = {"scope":"ACTUAL six-method wrapper delegates to one native worker at a time","actual_opened":observed.size(),"previous_joined":adapter.joined,"integrated_before_reset":adapter.integrated}

static func _fault_cases(model_root: String, report: Dictionary) -> void:
	for mode in ["partial_prefix","malformed_aircraft","negative_mass","negative_density","extra_position_member","wrong_weather_tick","impossible_completed","rejected_admission","dropped_command","duplicate_command","unadmitted_command","dropped_event","duplicate_event"]:
		var observed: Array = []
		var factory: Callable = func() -> RefCounted:
			var value: RefCounted = ObservedAdapter.new(mode)
			observed.append(value)
			return value
		var facade: RefCounted = Facade.new(factory)
		var opened: Dictionary = facade.start(model_root,"ground-ready")
		_check(report,opened.ok,"fault template actual open "+mode)
		if not opened.ok:
			facade.close()
			continue
		var adapter: RefCounted = observed[0]
		var before: Dictionary = opened.readback.aircraft.duplicate(true)
		var event_case: bool = mode in ["dropped_event","duplicate_event"]
		if mode in ["rejected_admission","dropped_command","duplicate_command","unadmitted_command"]:
			var intent: Dictionary = opened.readback.held_axes.duplicate(true)
			intent.roll = 0.025
			_check(report,facade.set_axes(intent).ok,"mutant command intent local only")
		var result: Dictionary = facade.set_paused(true) if event_case else facade.advance_wall_us(100000)
		_result_shape(report,result,"synthetic reply "+mode)
		_check(report,not result.ok,"synthetic reply rejected "+mode)
		_check(report,result.readback.historical and not facade.visual_pose().valid,"fault never presents live geometry "+mode)
		if mode == "partial_prefix":
			_check(report,result.completed == 5 and result.readback.tick == "5" and result.readback.debt_quanta == 28000000,"verified actual prefix alone debited")
			_check(report,result.readback.host_mode == "coverage_blocked" and adapter.requests == [11],"failed first segment prevents final adjacent step")
		else:
			_check(report,result.completed == 0 and result.readback.aircraft == before,"unverified completion retains last verified publication "+mode)
			_check(report,result.readback.host_mode == "discarded","malformed reply terminal host discard "+mode)
		_check(report,adapter.joined,"fault closes and joins actual worker "+mode)
		facade.close()
		report.synthetic_faults.append({"mode":mode,"scope":"SYNTHETIC packet mutation around actual native prefix; not an actual world fault","actual_requested_counts":adapter.requests,"actual_integrated":adapter.integrated,"verified_completed":result.completed,"retained_tick":result.readback.tick,"actual_joined":adapter.joined})

static func _reachable_guards(model_root: String, report: Dictionary) -> void:
	for row in [{"scale":1.0,"elapsed":250000,"stall":false,"tick":"30","debt":0},{"scale":0.25,"elapsed":250001,"stall":true,"tick":"0","debt":30000120},{"scale":4.0,"elapsed":62500,"stall":false,"tick":"30","debt":0},{"scale":4.0,"elapsed":62501,"stall":true,"tick":"0","debt":120001920},{"scale":4.0,"seed_us":1,"elapsed":62500,"stall":true,"tick":"0","debt":120000120},{"scale":4.0,"elapsed":9223372036854775807,"stall":true,"tick":"0","debt":0},{"scale":4.0,"seed_us":4000,"seed_scale":1.0,"elapsed":9223372036854775807,"stall":true,"tick":"0","debt":1920000,"error_kind":"Unrepresentable"},{"scale":4.0,"elapsed":4803839602528529,"stall":true,"tick":"0","debt":9223372036854775680,"error_kind":"Wall overload"}]:
		var values: Array = []
		var factory: Callable = func() -> RefCounted:
			var adapter: RefCounted = ObservedAdapter.new()
			values.append(adapter)
			return adapter
		var facade: RefCounted = Facade.new(factory)
		var opened: Dictionary = facade.start(model_root,"ground-ready")
		_check(report,opened.ok,"actual guard open")
		if not opened.ok:
			facade.close()
			continue
		if row.has("seed_us"):
			_check(report,facade.set_time_scale(row.get("seed_scale",0.25)).ok,"reachable fractional guard initial scale")
			var seeded: Dictionary = facade.advance_wall_us(row.seed_us)
			_check(report,seeded.ok and seeded.completed == 0 and seeded.readback.tick == "0" and seeded.readback.debt_quanta == (1920000 if row.has("seed_scale") else 120),"actual reachable fractional debt before guard")
		_check(report,facade.set_time_scale(row.scale).ok,"guard scale")
		_check(report,facade.set_axes(_axes(0,opened.readback.held_axes)).ok,"guard pending input")
		var result: Dictionary = facade.advance_wall_us(row.elapsed)
		_check(report,result.ok == (not row.stall) and result.readback.tick == row.tick and result.readback.debt_quanta == row.debt,"exact actual reachable guard")
		if row.has("error_kind"):
			_check(report,String(result.error).begins_with(row.error_kind),"overflow distinguished from representable overload")
		if row.stall:
			_check(report,result.readback.host_mode == "stalled" and values[0].submitted.is_empty() and values[0].integrated == 0,"overload before pilot admission/integration")
			_check(report,not facade.set_paused(false).ok and not facade.advance_wall_us(1).ok,"stalled cannot catch up/resume")
		_check(report,facade.close().ok and values[0].joined,"guard worker joined")

static func _close_pause_rejection(model_root: String, report: Dictionary) -> void:
	var observed: Array = []
	var factory: Callable = func() -> RefCounted:
		var adapter: RefCounted = ObservedAdapter.new()
		observed.append(adapter)
		return adapter
	var facade: RefCounted = Facade.new(factory)
	var opened: Dictionary = facade.start(model_root,"ground-ready")
	_check(report,opened.ok,"synthetic close-pause rejection template actual open")
	if not opened.ok:
		facade.close()
		return
	_adopt_absent(facade,report,"synthetic close-pause rejection")
	var seeded: Dictionary = facade.advance_wall_us(4000)
	_check(report,seeded.ok and seeded.completed == 0 and seeded.readback.tick == "0" and seeded.readback.debt_quanta == 1920000,"close rejection starts with reachable nonzero debt")
	var adapter: RefCounted = observed[0]
	adapter.mode = "close_pause_rejected"
	var closed: Dictionary = facade.close()
	_result_shape(report,closed,"synthetic rejected close-pause acknowledgement")
	_check(report,closed.ok and closed.completed == 0 and adapter.joined and adapter.integrated == 0 and adapter.requests.is_empty(),"rejected close-pause still joins actual worker without integration")
	_check(report,closed.readback.host_mode == "closed" and closed.readback.historical and not closed.readback.native_live and closed.readback.debt_quanta == 0,"confirmed close epilogue clears debt and retains historical truth")
	_check(report,not facade.visual_pose().valid and facade.render_origin == null,"close rejection clears presentation and old registry")
	_check(report,adapter.controls.size() == 1 and adapter.controls[0].payload == {"kind":"pause","paused":true},"synthetic wrapper rejected the attempted pause before native submission")
	_check(report,facade.close().ok,"closed rejected-pause fixture remains idempotent")
	report.synthetic_faults.append({"mode":"close_pause_rejected","scope":"SYNTHETIC close-pause acknowledgement rejection before native submission; actual worker joins, not a native rejection claim","actual_requested_counts":adapter.requests,"actual_integrated":adapter.integrated,"verified_completed":closed.completed,"retained_tick":closed.readback.tick,"actual_joined":adapter.joined})

static func _unjoined_reset(model_root: String, report: Dictionary) -> void:
	var observed: Array = []
	var factory: Callable = func() -> RefCounted:
		var adapter: RefCounted = ObservedAdapter.new("unjoined")
		observed.append(adapter)
		return adapter
	var facade: RefCounted = Facade.new(factory)
	var opened: Dictionary = facade.start(model_root,"ground-ready")
	_check(report,opened.ok,"unjoined acknowledgement template actual open")
	if not opened.ok:
		facade.close()
		return
	var failed: Dictionary = facade.reset("ground-ready")
	_check(report,not failed.ok and observed.size() == 1,"unconfirmed join cannot allocate another actual worker")
	_check(report,failed.readback.host_mode == "discarded" and not facade.set_axes(_axes(0,opened.readback.held_axes)).ok,"failed reset terminally rejects new input")
	# This is a synthetic acknowledgement around an actual worker; restore its
	# honest close reply and explicitly join it, never leave a fixture worker live.
	observed[0].mode = ""
	_check(report,facade.close().ok and observed[0].joined,"synthetic unjoined fixture explicitly cleans up")

static func _wind_cases(model_root: String, report: Dictionary) -> void:
	for profile in ["calm","from-north","from-west","from-east"]:
		for start_name in ["ground-ready","airborne-prepared"]:
			var facade:=Facade.new()
			var opened: Dictionary=facade.start(model_root,start_name,profile)
			_check(report,opened.ok,"wind_admitted_"+profile+"_"+start_name)
			if opened.ok:
				_result_shape(report,opened,"unchanged_wind_result_shape")
				var nominal: Array=Facade._nominal_wind(profile)
				for index in 3:
					_check(report,absf(opened.readback.atmosphere.wind_toward_ned_mps[["x","y","z"][index]]-nominal[index])<=1e-6,"wind_actual_nominal_component")
				_adopt_absent(facade,report,"wind accepted origin")
				_check(report,facade.set_paused(true).ok,"wind paused")
				var baseline: Dictionary=facade.readback()
				for bad in [null,0,{},Vector3.ZERO,&"calm","CALM","from-south",""]:
					var rejected: Dictionary=facade.start(model_root,start_name,bad)
					_check(report,not rejected.ok and facade.readback()==baseline,"invalid_wind_preserves_actual_current")
				var reset: Dictionary=facade.reset(start_name)
				_check(report,reset.ok and facade.get("_wind_profile")==profile,"wind_reset_preserves_accepted_profile")
			_check(report,facade.close().ok,"wind_owned_worker_joined")
	for mode in ["wind_missing","wind_echo","wind_extra","wind_actual"]:
		var adapters: Array=[]
		var factory: Callable=func() -> RefCounted:
			var adapter:=ObservedAdapter.new(mode)
			adapters.append(adapter)
			return adapter
		var facade:=Facade.new(factory)
		for bad in [null,0,&"from-west","from-south"]:
			_check(report,not facade.start(model_root,"ground-ready",bad).ok and adapters.is_empty(),"invalid_wind_preallocation")
		var rejected: Dictionary=facade.start(model_root,"ground-ready","from-west")
		_check(report,not rejected.ok and adapters.size()==1 and adapters[0].joined and not facade.readback().native_live,"wind_bad_open_joined_"+mode)
		_check(report,facade.close().ok,"wind_bad_open_host_closed")

static func _native_identity_cases(model_root: String, report: Dictionary) -> void:
	var adapters: Array=[]
	var factory: Callable=func() -> RefCounted:
		var adapter:=ObservedAdapter.new("native_fingerprint")
		adapters.append(adapter)
		return adapter
	var facade:=Facade.new(factory)
	var opened: Dictionary=facade.start(model_root,"ground-ready","calm")
	_check(report,not opened.ok and adapters.size()==1,"wrong_native_identity_rejected")
	if not adapters.is_empty():
		_check(report,adapters[0].joined and adapters[0].close_calls==1,"wrong_native_identity_worker_joined")
		_check(report,adapters[0].requests.is_empty() and adapters[0].integrated==0,"wrong_native_identity_zero_ticks")
	var truth: Dictionary=facade.readback()
	_check(report,not truth.native_live and truth.historical and truth.tick==null and truth.native_source_fingerprint==null,"wrong_native_identity_no_publication")
	_check(report,facade.close().ok,"wrong_native_identity_host_closed")

static func run(model_root: String) -> Dictionary:
	var report: Dictionary = {"checks":0,"failures":[],"native_profiles":[],"synthetic_faults":[],"scope":"Original same-build ADR007 facade/coordinate fixtures; no pilot, aircraft calibration or product performance qualification"}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://sim_loop_tests/independent-reference.json"))
	_check(report,parsed is Dictionary,"independent analytical reference loads")
	if not parsed is Dictionary:
		return report
	_uint_cases(parsed,report)
	_geometry_cases(parsed,report)
	_check(report,ClassDB.class_exists("FlightInteractiveSession"),"actual accepted native extension present")
	if not ClassDB.class_exists("FlightInteractiveSession"):
		return report
	_native_profiles(model_root,parsed,report)
	_native_lifecycle(model_root,report)
	_native_identity_cases(model_root,report)
	_reachable_guards(model_root,report)
	_unjoined_reset(model_root,report)
	_wind_cases(model_root,report)
	_fault_cases(model_root,report)
	_close_pause_rejection(model_root,report)
	return report
