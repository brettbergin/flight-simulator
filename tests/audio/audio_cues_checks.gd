extends RefCounted
# Original MIT. Saved engineering source below is presentation data, not new
# observed flight or independent aircraft physics. Mutations are authored cases.
const Cues = preload("res://audio/audio_cues.gd")
const Readings = preload("res://cockpit/instruments/native_readings.gd")
const Reference = preload("res://world_tests/synthetic/circuit_checks.gd")
const KEYS: Array=["session_id","tick","profile_id","state","engine_mode","shaft_radps","legacy_throttle","tas_mps","starved","error"]
var checks: int=0
var failures: Array[String]=[]
var baseline: Dictionary={}

static func run() -> Dictionary:
	return new()._run()

func _check(value: bool, label: String) -> void:
	checks+=1
	if not value: failures.append(label)

func _view(source: Variant, label: String) -> Dictionary:
	var view: Dictionary=Cues.from_readback(source)
	var shape: bool=view.size()==KEYS.size()
	for key in KEYS: shape=shape and view.has(key)
	_check(shape and typeof(view.error)==TYPE_STRING and view.error.length()<=1024 and view.state in ["live","paused","historical","unavailable"] and view.engine_mode in ["legacy","running","rotating","stopped","unavailable"],label+"_closed_result")
	return view

func _piston() -> Dictionary:
	var source: Dictionary=baseline.duplicate(true)
	source.model_identity=Readings.PISTON_PROFILE.duplicate(true)
	source.named_start="piston-cold-ground"
	source.aircraft.systems=[
		{"id":"propeller.angular_speed","quantity":"radps","value":120.0,"validity":"valid"},
		{"id":"engine.running","quantity":"bool","value":true,"validity":"valid"},
		{"id":"engine.starved","quantity":"bool","value":false,"validity":"valid"}]
	return source

func _invalid(source: Variant, label: String) -> void:
	var result: Dictionary=_view(source,label)
	var cleared: bool=result.state=="unavailable" and result.engine_mode=="unavailable" and not result.error.is_empty()
	for key in ["session_id","tick","profile_id","shaft_radps","legacy_throttle","tas_mps","starved"]: cleared=cleared and result[key]==null
	_check(cleared,label+"_cleared_all")

func _run() -> Dictionary:
	baseline=Reference.reference_readback()
	_check(not baseline.is_empty() and Readings._validate(baseline)=="","verified_original_capture_fixture")
	if baseline.is_empty(): return {"passed":false,"checks":checks,"failures":failures}
	var before: Dictionary=baseline.duplicate(true)
	var legacy: Dictionary=_view(baseline,"legacy_paused")
	_check(legacy.state=="paused" and legacy.engine_mode=="legacy" and legacy.profile_id==Readings.LEGACY_PROFILE.id and legacy.session_id==baseline.session_id and legacy.tick==baseline.tick and typeof(legacy.legacy_throttle)==TYPE_FLOAT and legacy.legacy_throttle==float(baseline.held_axes.throttle) and legacy.shaft_radps==null and legacy.starved==null and legacy.error=="","legacy_same_source_held_axes_and_paused_caption")
	_check(baseline==before,"source_unchanged")
	legacy.legacy_throttle=0.9
	_check(Cues.from_readback(baseline).legacy_throttle==float(before.held_axes.throttle),"result_owned")
	baseline.held_axes.throttle=0.7
	_check(legacy.legacy_throttle==0.9,"later_source_change_not_alias")
	baseline=before
	var source: Dictionary=_piston()
	for row in [[true,120.0,"running"],[false,120.0,"rotating"],[false,0.0,"stopped"],[true,0.0,"unavailable"]]:
		source.aircraft.systems[0].value=row[1]; source.aircraft.systems[1].value=row[0]
		var view: Dictionary=_view(source,"engine_"+row[2])
		_check(view.engine_mode==row[2] and view.state=="paused" and view.legacy_throttle==null and (view.shaft_radps==null if row[2]=="unavailable" else view.shaft_radps==row[1]),"engine_truth_"+row[2])
		_check(view.error.is_empty()==(row[2]!="unavailable"),"engine_reason_"+row[2])
	for mode in ["live","paused","closed","stalled","coverage_blocked","discarded"]:
		source=_piston();source.host_mode=mode
		source.historical=mode not in ["live","paused"]
		source.paused=mode=="paused"; source.native_live=mode in ["live","paused"]
		var view: Dictionary=_view(source,mode)
		_check(view.state==("historical" if source.historical else mode) and view.engine_mode=="running" and view.shaft_radps==120.0 and view.session_id==source.session_id and view.tick==source.tick,mode+"_facts_not_relabelled")
	# Identity quaternion, finite WGS84 publication, original authored wind cases.
	for row in [[0.0,0.0,5.0],[3.0,4.0,0.0]]:
		source=_piston();source.aircraft.orientation_body_to_ned={"w":1.0,"x":0.0,"y":0.0,"z":0.0}
		source.aircraft.velocity_body_mps={"x":row[0],"y":row[1],"z":0.0}
		source.atmosphere.wind_toward_ned_mps={"x":3.0,"y":4.0,"z":0.0}
		source.atmosphere.turbulence_ned_mps={"x":0.0,"y":0.0,"z":0.0}
		var view: Dictionary=_view(source,"wind_relative_"+str(row[2]))
		var old_norm: float=sqrt(row[0]*row[0]+row[1]*row[1])
		_check(view.tas_mps==row[2] and old_norm!=row[2] and view.error=="","independent_TAS_old_ground_norm_fails_"+str(row[2]))
	for id in ["propeller.angular_speed","engine.running","engine.starved"]:
		for mutation in ["missing","unavailable","wrong_unit"]:
			source=_piston()
			var index: int=0 if id=="propeller.angular_speed" else 1 if id=="engine.running" else 2
			if mutation=="missing": source.aircraft.systems.remove_at(index)
			elif mutation=="unavailable": source.aircraft.systems[index].validity="unavailable"
			else: source.aircraft.systems[index].quantity="pa";source.aircraft.systems[index].value=0.0
			var view: Dictionary=_view(source,id+"_"+mutation)
			_check(view.state=="paused" and view.tas_mps!=null and not view.error.is_empty() and ((view.starved==null and view.engine_mode=="running" and view.shaft_radps==120.0) if id=="engine.starved" else (view.engine_mode=="unavailable" and view.shaft_radps==null and view.starved==false)),"independent_partial_"+id+"_"+mutation)
	source=_piston();source.aircraft.velocity_body_mps.x=1e200
	var overflow: Dictionary=_view(source,"TAS_overflow")
	_check(Readings._validate(source)=="" and overflow.state=="paused" and overflow.tas_mps==null and overflow.engine_mode=="running" and overflow.shaft_radps==120.0 and overflow.error.begins_with("Airflow unavailable:"),"derived_overflow_only_mutes_airflow")
	source.aircraft.systems=[]
	var ordered: Dictionary=_view(source,"error_order")
	_check(ordered.error.find("Engine unavailable:")==0 and ordered.error.find("Airflow unavailable:")>ordered.error.find("Engine unavailable:") and ordered.error.find("Starvation observation unavailable:")>ordered.error.find("Airflow unavailable:"),"deterministic_component_error_order")
	for mutation in ["extra","missing","wrong_flag","source_session","weather_tick","world","profile","invalid_weather","nan_velocity","wrong_bool","nan_shaft","throttle_mismatch","fingerprint","duplicate_system"]:
		source=_piston()
		match mutation:
			"extra": source.extra=true
			"missing": source.erase("canonical")
			"wrong_flag": source.paused=1
			"source_session": source.session_id="unpaired"
			"weather_tick": source.atmosphere.tick="1"
			"world": source.prepared_world_sha256="0".repeat(64)
			"profile": source.model_identity.version="9.0.0"
			"invalid_weather": source.atmosphere.model_id="Bad source"
			"nan_velocity": source.aircraft.velocity_body_mps.x=NAN
			"wrong_bool": source.aircraft.systems[1].value=1.0
			"nan_shaft": source.aircraft.systems[0].value=NAN
			"fingerprint": source.native_source_fingerprint="g".repeat(64)
			"duplicate_system": source.aircraft.systems.append(source.aircraft.systems[0].duplicate(true))
			"throttle_mismatch": source.aircraft.systems.append({"id":"engine.throttle","quantity":"fraction","value":0.5,"validity":"valid"})
		_invalid(source,mutation)
	var empty: Dictionary=baseline.duplicate(true)
	for key in Readings.NULLABLE: empty[key]=null
	empty.host_mode="closed";empty.historical=true;empty.native_live=false;empty.paused=false
	empty.time_scale=1.0;empty.debt_quanta=0
	_check(Readings._validate(empty)=="","valid_empty_publication_fixture")
	_invalid(empty,"valid_empty_source")
	source=_piston();source.aircraft.systems[2].value=true
	var starved: Dictionary=_view(source,"actual_starved")
	_check(starved.starved==true and starved.engine_mode=="running" and starved.shaft_radps==120.0 and starved.error=="","starved_observation_independent_of_engine_cue")
	for wrong in [null,{},[],true,"readback"]: _invalid(wrong,"wrong_source_"+str(wrong))
	return {"passed":failures.is_empty(),"checks":checks,"failures":failures.duplicate()}
