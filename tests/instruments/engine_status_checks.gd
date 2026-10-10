extends RefCounted
# Original MIT. Full copied synthetic Readback tests; no simulator or scene calls.
const Status = preload("res://cockpit/instruments/engine_status.gd")
const Readings = preload("res://cockpit/instruments/native_readings.gd")
const Frames = preload("res://simulation/canonical_frames.gd")
const Facade = preload("res://simulation/session_facade.gd")
const NativeIdentity = preload("res://build/native_identity.gd")
const REFERENCE_SHA: String = "413eb124254432f8b39d7079b773d14e276415aa54749de3a1d85e527bf70aae"
const PROFILE: Dictionary = {"id":"original-piston-prop-v1","version":"0.1.0-prototype","backend_model":"original-piston-prop"}
const UNITS: Dictionary = {
	"fuel.total":"kg","engine.throttle":"fraction","engine.mixture":"fraction",
	"propeller.angular_speed":"radps","engine.running":"bool",
	"engine.ignition_left":"bool","engine.ignition_right":"bool",
	"engine.starter":"bool","fuel.feed":"bool","engine.starved":"bool"}
const SWITCHES: Array = ["engine.ignition_left","engine.ignition_right","engine.starter","fuel.feed"]
const COLD: Dictionary = {
	"fuel.total":100.0,"engine.throttle":0.0,"engine.mixture":0.0,
	"propeller.angular_speed":0.0,"engine.running":false,
	"engine.ignition_left":false,"engine.ignition_right":false,
	"engine.starter":false,"fuel.feed":true,"engine.starved":false}
var checks: int = 0
var failures: Array[String] = []
var baseline: Dictionary = {}

static func run() -> Dictionary:
	return new()._run()

func _check(ok: bool, label: String) -> void:
	checks+=1
	if not ok:
		failures.append(label)

func _closed(value: Variant, names: Array) -> bool:
	if not value is Dictionary or value.size()!=names.size():
		return false
	for key in value:
		if typeof(key)!=TYPE_STRING or key not in names:
			return false
	return true

func _shape(result: Variant, label: String) -> bool:
	var good: bool = _closed(result,["session_id","tick","state","native_truth","readings","error"])
	_check(good,label+"_six_keys")
	if not good:
		return false
	good=typeof(result.state)==TYPE_STRING and result.state in ["empty","invalid","live","paused","historical"] and typeof(result.native_truth)==TYPE_BOOL and result.native_truth and typeof(result.error)==TYPE_STRING
	_check(good,label+"_typed_state_truth_reason")
	if not _closed(result.readings,UNITS.keys()):
		_check(false,label+"_ten_channels")
		return false
	_check(true,label+"_ten_channels")
	for id in UNITS:
		var channel: Variant = result.readings[id]
		var valid: bool = _closed(channel,["value","unit","valid","error"])
		if valid:
			valid=typeof(channel.unit)==TYPE_STRING and channel.unit==UNITS[id] and typeof(channel.valid)==TYPE_BOOL and typeof(channel.error)==TYPE_STRING
		if valid:
			if channel.valid:
				valid=channel.error.is_empty() and (typeof(channel.value)==TYPE_BOOL if UNITS[id]=="bool" else typeof(channel.value)==TYPE_FLOAT and is_finite(channel.value))
			else:
				valid=channel.value==null and not channel.error.is_empty()
		_check(valid,label+"_"+id+"_closed_typed_unit_availability")
		good=good and valid
	return good

func _invalid(source: Variant, label: String, state: String="invalid") -> void:
	var result: Dictionary = Status.from_readback(source)
	if not _shape(result,label):
		return
	_check(result.state==state and result.session_id==null and result.tick==null and not result.error.is_empty(),label+"_clears_identity")
	for id in UNITS:
		_check(result.readings[id].value==null and not result.readings[id].valid,label+"_"+id+"_clears_value")
	var held: Dictionary = Status.held_systems_from_readback(source)
	_check(_closed(held,["ok","error","value"]) and typeof(held.ok)==TYPE_BOOL and not held.ok and held.value==null and typeof(held.error)==TYPE_STRING and not held.error.is_empty(),label+"_held_rejected")

func _system(source: Dictionary, id: String) -> Dictionary:
	for system in source.aircraft.systems:
		if system.id==id:
			return system
	return {}

func _piston() -> Dictionary:
	var source: Dictionary = baseline.duplicate(true)
	source.model_identity=PROFILE.duplicate(true)
	source.named_start="piston-cold-ground"
	source.native_source_fingerprint=Facade.NATIVE
	source.held_axes.throttle=0.0
	source.held_axes.mixture=0.0
	source.held_axes.left_brake=1.0
	source.held_axes.right_brake=1.0
	# Synthetic cold-control fixture at the authored initial height. This is not
	# a native cold-start observation or a second physics/reference generator.
	source.aircraft.position.ellipsoid_height_m=1.05
	source.atmosphere.position=source.aircraft.position.duplicate(true)
	var point: Array = Frames.anchor(0.8,-2.0,1.05).ecef
	source.aircraft.ecef_position_m={"x":point[0],"y":point[1],"z":point[2]}
	source.canonical=Frames.derive(source.aircraft,Frames.anchor(0.8,-2.0,0.0))
	source.aircraft.systems=[]
	for id in UNITS:
		source.aircraft.systems.append({"id":id,"quantity":UNITS[id],"value":COLD[id],"validity":"valid"})
	return source

func _positive() -> void:
	var source: Dictionary = _piston()
	var before: Dictionary = source.duplicate(true)
	var result: Dictionary = Status.from_readback(source)
	if _shape(result,"cold"):
		_check(result.state=="live" and result.error.is_empty() and result.session_id==source.session_id and result.tick=="0","cold_owned_publication_identity")
		for id in COLD:
			_check(result.readings[id].valid and result.readings[id].value==COLD[id],"cold_"+id+"_actual_copied_value")
	_check(source==before,"cold_input_not_mutated")
	var held: Dictionary = Status.held_systems_from_readback(source)
	_check(_closed(held,["ok","error","value"]) and held.ok and held.error.is_empty() and _closed(held.value,SWITCHES),"held_exact_four_switches")
	if held.ok:
		for id in SWITCHES:
			_check(typeof(held.value[id])==TYPE_BOOL and held.value[id]==COLD[id],"held_"+id+"_actual_bool")
		var original_held: Dictionary = held.value.duplicate(true)
		held.value["fuel.feed"]=false
		_check(Status.held_systems_from_readback(source).value==original_held,"held_output_owned")
	result.readings["fuel.total"].value=-99.0
	_check(Status.from_readback(source).readings["fuel.total"].value==100.0,"status_output_owned")
	_system(source,"fuel.total").value=75.0
	_check(result.readings["fuel.total"].value==-99.0,"status_input_later_mutation_does_not_alias_output")
	# Running, shaft and switches are independent native observations.
	source=_piston()
	_system(source,"engine.running").value=true
	_system(source,"propeller.angular_speed").value=120.0
	source.held_axes.throttle=0.25
	_system(source,"engine.throttle").value=0.25
	source.held_axes.mixture=0.75
	_system(source,"engine.mixture").value=0.75
	result=Status.from_readback(source)
	_check(result.state=="live" and result.readings["engine.running"].value==true and result.readings["propeller.angular_speed"].value==120.0,"running_and_shaft_are_copied_not_throttle_inferred")
	source=_piston()
	source.host_mode="paused";source.paused=true;source.native_outcome="paused"
	_system(source,"engine.starter").value=true
	result=Status.from_readback(source)
	_check(result.state=="paused" and result.readings["engine.starter"].value==true and Status.held_systems_from_readback(source).value["engine.starter"]==true,"paused_starter_true_is_not_pending_rearm_false")
	for mode in ["closed","stalled","coverage_blocked","discarded"]:
		source=_piston();source.host_mode=mode;source.historical=true;source.native_live=false;source.paused=false;source.canonical=null
		result=Status.from_readback(source)
		_check(_shape(result,"retained_"+mode) and result.state=="historical" and result.readings["fuel.total"].value==100.0,"retained_"+mode+"_does_not_relabel_current")
	# Source equality belongs to the facade/package gate. The pure leaf accepts
	# other structurally valid historical digests; never call this binary proof.
	source.native_source_fingerprint=("0" if Facade.NATIVE[0]!="0" else "1")+Facade.NATIVE.substr(1)
	_check(Status.from_readback(source).state=="historical","historical_digest_syntax_only_not_current_binary_authority")
	_check(Facade.NATIVE==NativeIdentity.SOURCE_FINGERPRINT and Facade._native_identity_valid(),"facade_generated_identity_alias_and_shape_only")

func _unavailable_channels() -> void:
	for id in UNITS:
		for mutation in ["missing","unavailable","wrong_unit"]:
			var source: Dictionary = _piston()
			var selected: Dictionary = _system(source,id)
			if mutation=="missing":
				source.aircraft.systems.erase(selected)
			elif mutation=="unavailable":
				selected.validity="unavailable"
			else:
				selected.quantity="pa";selected.value=0.0
			var result: Dictionary = Status.from_readback(source)
			var label: String = id+"_"+mutation
			if not _shape(result,label):
				continue
			_check(result.state=="live" and result.error.is_empty() and not result.readings[id].valid and result.readings[id].value==null,label+"_one_unavailable")
			for other in UNITS:
				if other!=id:
					_check(result.readings[other].valid and result.readings[other].value==COLD[other],label+"_preserves_"+other)
			var held: Dictionary = Status.held_systems_from_readback(source)
			_check(held.ok==(id not in SWITCHES),label+"_held_requires_only_all_four_valid_switches")

func _invalid_publications() -> void:
	for mutation in ["extra_outer","missing_outer","wrong_flag","float_debt","negative_debt","bad_scale","live_historical","paused_historical","live_not_native","closed_current","partial_pair","pair_tick","pair_position","wrong_profile","wrong_version","wrong_backend","legacy_profile","wrong_start","bad_fingerprint","fingerprint_type","world_digest","wrong_anchor","canonical_point","duplicate_system","wrong_bool","nan_shaft","infinite_fuel","negative_fuel","negative_shaft","throttle_mismatch","mixture_mismatch","invalid_aircraft","invalid_weather_source"]:
		var source: Dictionary = _piston()
		match mutation:
			"extra_outer": source.extra=true
			"missing_outer": source.erase("native_fault")
			"wrong_flag": source.native_live=1
			"float_debt": source.debt_quanta=0.0
			"negative_debt": source.debt_quanta=-1
			"bad_scale": source.time_scale=3.0
			"live_historical": source.historical=true
			"paused_historical": source.host_mode="paused";source.paused=true;source.historical=true
			"live_not_native": source.native_live=false
			"closed_current": source.host_mode="closed";source.native_live=false
			"partial_pair": source.atmosphere=null
			"pair_tick": source.atmosphere.tick="1"
			"pair_position": source.atmosphere.position.ellipsoid_height_m=2.0
			"wrong_profile": source.model_identity.id="unknown-profile"
			"wrong_version": source.model_identity.version="0.2.0-prototype"
			"wrong_backend": source.model_identity.backend_model="original-interactive"
			"legacy_profile": source.model_identity={"id":"original-interactive-prototype","version":"0.1.0-prototype","backend_model":"original-interactive"};source.named_start="ground-ready";source.held_axes.mixture=1.0
			"wrong_start": source.named_start="airborne-prepared"
			"bad_fingerprint": source.native_source_fingerprint="g".repeat(64)
			"fingerprint_type": source.native_source_fingerprint=StringName(Facade.NATIVE)
			"world_digest": source.prepared_world_sha256="0".repeat(64)
			"wrong_anchor": source.world_anchor.latitude_rad=0.7
			"canonical_point": source.canonical.ecef_position_m[0]+=1.0
			"duplicate_system": source.aircraft.systems.append(source.aircraft.systems[0].duplicate(true))
			"wrong_bool": _system(source,"engine.starter").value=1.0
			"nan_shaft": _system(source,"propeller.angular_speed").value=NAN
			"infinite_fuel": _system(source,"fuel.total").value=INF
			"negative_fuel": _system(source,"fuel.total").value=-1.0
			"negative_shaft": _system(source,"propeller.angular_speed").value=-0.25
			"throttle_mismatch": _system(source,"engine.throttle").value=0.5
			"mixture_mismatch": _system(source,"engine.mixture").value=0.5
			"invalid_aircraft": source.aircraft.validity="invalid"
			"invalid_weather_source": source.atmosphere.model_id="Bad Source"
		_invalid(source,"invalid_"+mutation)
	for source in [null,{},[],true,"Readback"]:
		_invalid(source,"wrong_whole_type_"+str(typeof(source)))
	var empty: Dictionary = baseline.duplicate(true)
	empty.host_mode="closed";empty.historical=true;empty.native_live=false;empty.paused=false;empty.debt_quanta=0;empty.time_scale=1.0
	for key in ["session_id","tick","aircraft","atmosphere","held_axes","native_outcome","named_start","model_identity","native_source_fingerprint","prepared_world_sha256","world_anchor","canonical"]:
		empty[key]=null
	_invalid(empty,"never_started_empty","empty")

func _run() -> Dictionary:
	var path: String = "res://instrument_tests/reference.json"
	_check(FileAccess.get_sha256(path)==REFERENCE_SHA,"unchanged_frozen_35_reference_hash")
	var packet: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not packet is Dictionary or not packet.get("cases") is Array or not packet.get("non_json_cases") is Array:
		_check(false,"full_reference_packet_available")
		return _report()
	_check(packet.cases.size()==30 and packet.non_json_cases.size()==5,"unchanged_frozen_30_json_5_direct_case_count")
	for row in packet.cases:
		if row.id=="identity-zero":
			baseline=row.input.duplicate(true)
	if baseline.is_empty():
		_check(false,"identity_zero_full_readback_fixture_present")
		return _report()
	# JSON restores only the declared integer debt field; other malformed-type
	# fixtures deliberately keep their wrong type and must not be normalized.
	var debt: Variant = baseline.get("debt_quanta")
	if typeof(debt) not in [TYPE_FLOAT,TYPE_INT] or not is_finite(float(debt)) or float(debt)!=0.0:
		_check(false,"fixture_declared_zero_debt")
		return _report()
	baseline.debt_quanta=0
	_check(Readings.from_readback(baseline).state=="live","retained_legacy_fixture_admission")
	_positive()
	_unavailable_channels()
	_invalid_publications()
	return _report()

func _report() -> Dictionary:
	return {"passed":failures.is_empty(),"checks":checks,"failures":failures.duplicate(),"scope":"Pure synthetic full copied ADR010 EngineStatus/Readback tests; source digest syntax only. No native engine, electrical indication, device, GPU, pilot or phase qualification."}
