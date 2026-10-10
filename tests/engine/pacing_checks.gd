extends RefCounted
# Original MIT. Same-build cold-profile pacing, not engine-performance goldens.
const Facade=preload("res://simulation/session_facade.gd")
const Frames=preload("res://simulation/canonical_frames.gd")
const REFERENCE_PATH: String="res://sim_loop_tests/independent-reference.json"
const REFERENCE_SHA256: String="bd4dd360ae6406f2424d9b46d35f39b5c4142fcdccacab6547701d7813b4c93c"
const CADENCES: Array=["30","60","144","240","jitter"]
const SCALES: Array=["1/4","1/2","1","2","4"]
const SYSTEM_ORDER: Array=["engine.ignition_left","engine.ignition_right","engine.starter","fuel.feed"]
const CATEGORIES: Array[String]=["ownship","cockpit","camera","world","light","spatial_audio","local_particles"]

static func _check(report: Dictionary,condition: bool,label: String) -> void:
	report.checks+=1
	if not condition: report.failures.append(label)

# The only normalization is fresh native session identity, as in the baseline.
static func _normal(value: Variant) -> Variant:
	if value is Dictionary:
		var out: Dictionary={}
		for key in value:
			out[key]="FRESH_SESSION" if key=="session_id" else _normal(value[key])
		return out
	if value is Array:
		var out: Array=[]
		for item in value: out.append(_normal(item))
		return out
	return value

static func _axes(index: int) -> Dictionary:
	return {"kind":"axes","roll":0.0,"pitch":0.0,"yaw":0.0,"throttle":[0.125,0.25,0.375,0.5][index],"mixture":[0.25,0.5,0.75,1.0][index],"left_brake":1.0,"right_brake":1.0,"trim":0.0}

static func _systems(index: int) -> Dictionary:
	return {"engine.ignition_left":[false,true,true,false][index],"engine.ignition_right":[false,false,true,true][index],"engine.starter":false,"fuel.feed":[true,false,true,false][index]}

static func _expected_commands(session: String) -> Array:
	var out: Array=[]
	var previous: Dictionary={"engine.ignition_left":false,"engine.ignition_right":false,"engine.starter":false,"fuel.feed":true}
	for index in 4:
		var payloads: Array=[_axes(index)]
		var systems: Dictionary=_systems(index)
		for id in SYSTEM_ORDER:
			if systems[id]!=previous[id]: payloads.append({"kind":"system","control_id":id,"value":systems[id]})
		for payload in payloads:
			out.append({"type":"ControlCommand","schema_version":1,"tick":str(1+index*30),"session_id":session,"sequence":str(out.size()+1),"source_id":"pilot.controls","authority":"pilot","assistance":{"profile_id":"unassisted","active":[]},"payload":payload})
		previous=systems
	return out

static func _adopt_absent(facade: RefCounted,report: Dictionary,label: String) -> void:
	_check(report,not facade.visual_pose().valid,label+":no pose before adoption")
	var registered: Dictionary=facade.render_origin.call("register_participant","cold-pacing-native-only",null,CATEGORIES)
	_check(report,registered.ok,label+":explicit all-category absence")
	var world: Dictionary=facade.readback().world_anchor
	var anchor: Dictionary=Frames.anchor(world.latitude_rad,world.longitude_rad,world.ellipsoid_height_m)
	var adopted: Dictionary=facade.render_origin.call("rebase",anchor.ecef)
	_check(report,adopted.ok and adopted.origin.valid and facade.visual_pose().valid,label+":same-anchor owned presentation")

static func _finish(report: Dictionary) -> Dictionary:
	report.passed=report.failures.is_empty()
	return report

static func run(model_root: String) -> Dictionary:
	var report: Dictionary={"passed":false,"checks":0,"failures":[],"native_profiles":[],"scope":"Actual cold-profile120Hz same-build pacing over unchanged25 Fraction wall profiles; starter always false, no engine-performance/pilot/phase qualification"}
	var hash_ok: bool=FileAccess.get_sha256(REFERENCE_PATH)==REFERENCE_SHA256
	_check(report,hash_ok,"unchanged independent Fraction reference bytes")
	if not hash_ok: return _finish(report)
	var reference: Variant=JSON.parse_string(FileAccess.get_file_as_string(REFERENCE_PATH))
	_check(report,reference is Dictionary,"independent reference loads")
	if not reference is Dictionary: return _finish(report)
	var roster_ok: bool=reference.schema_version==1 and reference.wall_profiles is Array and reference.wall_profiles.size()==25
	_check(report,roster_ok,"closed25 reference profiles")
	if not roster_ok: return _finish(report)
	var covered: Dictionary={}
	for profile in reference.wall_profiles:
		var key: String=profile.profile+":"+profile.scale
		roster_ok=roster_ok and CADENCES.has(profile.profile) and SCALES.has(profile.scale) and not covered.has(key)
		covered[key]=true
	_check(report,roster_ok and covered.size()==25,"exact5cadence by5scale oracle roster")
	if not roster_ok: return _finish(report)
	_check(report,ClassDB.class_exists("FlightInteractiveSession"),"actual native bridge required")
	if not ClassDB.class_exists("FlightInteractiveSession"): return _finish(report)
	var per_scale: Dictionary={}
	var common_physics: Variant=null
	var completed_profiles: int=0
	for profile in reference.wall_profiles:
		var label: String="cold "+profile.profile+"Hz scale"+profile.scale
		var facade: RefCounted=Facade.new()
		var opened: Dictionary=facade.start(model_root,"piston-cold-ground","calm","original-piston-prop-v1")
		_check(report,opened.ok and opened.completed==0 and opened.readback.tick=="0",label+":actual explicit cold zero-tick open")
		if not opened.ok:
			facade.close()
			continue
		_adopt_absent(facade,report,label)
		var parts: PackedStringArray=String(profile.scale).split("/")
		var scale: float=float(parts[0])/(float(parts[1]) if parts.size()==2 else 1.0)
		var scaled: Dictionary=facade.set_time_scale(scale)
		_check(report,scaled.ok and scaled.completed==0 and scaled.readback.tick=="0",label+":scale acknowledgement invents no tick")
		var commands: Array=[]
		var events: Array=scaled.events.duplicate(true)
		var cuts: Array=[]
		var intent: Dictionary=facade.set_pilot_intent(_axes(0),_systems(0))
		_check(report,intent.ok and intent.admission=="intent_stored",label+":complete local axes/four-bool intent at0")
		var completed_profile: bool=true
		for row in profile.rows:
			var result: Dictionary=facade.advance_wall_us(int(row.elapsed_us))
			var agrees: bool=result.ok and result.completed==int(row.completed_this_call) and result.readback.tick==str(int(row.completed_total)) and result.readback.debt_quanta==int(row.debt_quanta)
			_check(report,result.ok,label+":oracle wall interval admitted")
			_check(report,result.completed==int(row.completed_this_call),label+":exact completed-this-call")
			_check(report,result.readback.tick==str(int(row.completed_total)) and result.readback.debt_quanta==int(row.debt_quanta),label+":exact Fraction tick/debt")
			commands.append_array(result.applied_commands)
			events.append_array(result.events)
			if not agrees:
				completed_profile=false
				break
			if row.declared_native_cut:
				var native_tick: int=int(row.completed_total)
				_check(report,[30,60,90,120].has(native_tick) and result.readback.debt_quanta==0,label+":declared exact cut")
				cuts.append({"tick":result.readback.tick,"aircraft":_normal(result.readback.aircraft),"atmosphere":_normal(result.readback.atmosphere),"held_axes":result.readback.held_axes.duplicate(true)})
				for system in result.readback.aircraft.systems:
					if system.id=="engine.starter": _check(report,typeof(system.value)==TYPE_BOOL and system.value==false,label+":starter remains actual false")
				if native_tick<120:
					var paused: Dictionary=facade.set_paused(true)
					_check(report,paused.ok and paused.completed==0 and paused.readback.tick==str(native_tick),label+":actual pause/drain has no completed tick")
					events.append_array(paused.events)
					var paused_truth: Dictionary=paused.readback.duplicate(true)
					var noop: Dictionary=facade.set_paused(true)
					_check(report,noop.ok and noop.completed==0 and noop.admission=="none" and noop.events.is_empty() and noop.readback==paused_truth,label+":paused lifecycle no-op")
					var excluded: Dictionary=facade.advance_wall_us(10000000)
					_check(report,excluded.ok and excluded.completed==0 and excluded.applied_commands.is_empty() and excluded.events.is_empty() and excluded.readback==paused_truth,label+":paused wall excluded including exact debt/state")
					var resumed: Dictionary=facade.set_paused(false)
					_check(report,resumed.ok and resumed.completed==0 and resumed.events.is_empty() and resumed.readback.tick==str(native_tick) and resumed.readback.debt_quanta==0 and resumed.readback.aircraft==paused_truth.aircraft and resumed.readback.atmosphere==paused_truth.atmosphere,label+":resume acknowledgement invents no tick/event/state")
					_check(report,facade.set_pilot_intent(_axes(int(native_tick/30.0)),_systems(int(native_tick/30.0))).ok,label+":complete local intent at next native cut")
				_check(report,facade.visual_pose().valid,label+":owned pose at cut")
		var ticks: Array=[]
		for cut in cuts: ticks.append(cut.tick)
		_check(report,ticks==["30","60","90","120"],label+":four exact cuts once each")
		var expected: Array=_expected_commands(opened.readback.session_id)
		_check(report,expected.size()==10 and commands==expected,label+":ten exact actual commands at1/31/61/91 with fixed order and shared sequence")
		var final_truth: Dictionary=facade.readback()
		_check(report,final_truth.tick=="120" and final_truth.debt_quanta==0,label+":exact final native tick/debt")
		var closed: Dictionary=facade.close()
		_check(report,closed.ok and not closed.readback.native_live and closed.readback.historical and not facade.visual_pose().valid,label+":joined close invalidates presentation")
		events.append_array(closed.events)
		var normalized: Dictionary={"cuts":cuts,"commands":_normal(commands),"events":_normal(events)}
		if per_scale.has(profile.scale):
			_check(report,normalized==per_scale[profile.scale],label+":same-scale exact native/command/lifecycle equality")
		else: per_scale[profile.scale]=normalized.duplicate(true)
		var physics: Dictionary={"cuts":cuts,"commands":_normal(commands)}
		if common_physics==null: common_physics=physics.duplicate(true)
		else: _check(report,physics==common_physics,label+":all-scale exact native120Hz snapshots and commands")
		if completed_profile: completed_profiles+=1
		report.native_profiles.append({"cadence":profile.profile,"scale":profile.scale,"completed_profile":completed_profile,"final_tick":final_truth.tick,"final_debt_quanta":final_truth.debt_quanta,"cuts":cuts,"applied_commands":commands,"events":events})
	_check(report,completed_profiles==25 and report.native_profiles.size()==25 and per_scale.size()==5,"complete closed25 actual cold pacing profiles, none skipped")
	return _finish(report)
