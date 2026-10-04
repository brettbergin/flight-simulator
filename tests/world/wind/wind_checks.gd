extends RefCounted
# Original MIT. Pure tests; synthetic source fixtures confer no binary authority.
const Cue = preload("res://world/wind/wind_cue.gd")
const Readings = preload("res://cockpit/instruments/native_readings.gd")
const Frames = preload("res://simulation/canonical_frames.gd")
const EXPECTED_SHA: String = "7d71cbb4f8d9ad12fe91501d5e020f14bbf02516d363512e69b6fa41320856c3"
const KEYS: Array = ["state","session_id","tick","wind_toward_ned_mps","speed_mps","from_true_rad","wind_toward_airfield_eus_mps","error"]
var checks: int = 0
var failures: Array[String] = []
var _base: Dictionary = {}

static func run() -> Dictionary:
	return new()._run()

func _check(ok: bool, label: String) -> void:
	checks+=1
	if not ok: failures.append(label)

func _bits(value: float) -> String:
	var bytes: PackedByteArray = PackedByteArray()
	bytes.resize(8)
	bytes.encode_double(0,value)
	return bytes.hex_encode()

func _reference(value: Dictionary) -> float:
	return value.binary64_le.hex_decode().decode_double(0)

func _numbers(values: Array) -> Array:
	var result: Array = []
	for value in values: result.append(_reference(value))
	return result

func _near(actual: Variant, expected: float, absolute: float, label: String) -> void:
	_check(typeof(actual)==TYPE_FLOAT and is_finite(actual) and absf(actual-expected)<=absolute,label)

func _shape(value: Dictionary, label: String) -> void:
	_check(value.size()==KEYS.size(),label+"_closed_size")
	for key in value: _check(typeof(key)==TYPE_STRING and KEYS.has(key),label+"_closed_key")
	_check(typeof(value.state)==TYPE_STRING and value.state in ["live","paused","historical","empty","invalid"],label+"_state_type")
	_check(typeof(value.error)==TYPE_STRING and value.error.length()<=1024,label+"_bounded_reason")

func _invalid(input: Variant, label: String, state: String = "invalid") -> void:
	var result: Dictionary = Cue.from_readback(input)
	_shape(result,label)
	_check(result.state==state and not result.error.is_empty(),label+"_unavailable_reason")
	for key in KEYS:
		if key not in ["state","error"]: _check(result[key]==null,label+"_null_"+key)

func _source(wind: Array = [0.0,0.0,0.0]) -> Dictionary:
	var input: Dictionary = _base.duplicate(true)
	input.debt_quanta=0 # Only known JSON integer counter restored; never tick strings.
	input.native_source_fingerprint=Cue.SUPPORTED_SOURCE
	input.atmosphere.model_id="jsbsim-dry-isa"
	input.atmosphere.seed="42"
	input.atmosphere.wind_toward_ned_mps={"x":wind[0],"y":wind[1],"z":wind[2]}
	return input

func _cue_case(row: Dictionary) -> void:
	var wind: Array = _numbers(row.input_wind_toward_ned_mps)
	var input: Dictionary = _source(wind)
	var original: Dictionary = input.duplicate(true)
	var result: Dictionary = Cue.from_readback(input)
	_shape(result,row.id)
	_check(result.state=="live" and result.session_id==input.session_id and result.tick==input.tick and result.error.is_empty(),row.id+"_qualified")
	_check(input==original,row.id+"_input_unmodified")
	for i in 3:
		_check(typeof(result.wind_toward_ned_mps[i])==TYPE_FLOAT and _bits(result.wind_toward_ned_mps[i])==_bits(wind[i]),row.id+"_native_bits_"+str(i))
		var expected: float = _reference(row.expected_toward_anchor_eus_mps[i])
		if row.kind=="zero-or-tiny": _check(result.wind_toward_airfield_eus_mps[i]==0.0 if expected==0.0 else _bits(result.wind_toward_airfield_eus_mps[i])==_bits(expected),row.id+"_projection_bits_"+str(i))
		else: _near(result.wind_toward_airfield_eus_mps[i],expected,1e-12,row.id+"_projection_"+str(i))
	var speed: float = _reference(row.expected_speed_mps)
	if row.kind=="zero-or-tiny":
		if row.get("speed_comparison")=="within4ulp-positive":
			var actual_bits: int = _bits(result.speed_mps).hex_decode().decode_s64(0)
			var expected_bits: int = row.expected_speed_mps.binary64_le.hex_decode().decode_s64(0)
			_check(result.speed_mps>0.0 and absi(actual_bits-expected_bits)<=4,row.id+"_speed_4ULP_positive")
		else: _check(_bits(result.speed_mps)==_bits(speed) and (row.calm or result.speed_mps>0.0),row.id+"_speed_exact_positive")
	else:
		_near(result.speed_mps,speed,1e-12,row.id+"_speed")
		for i in 3:
			var feet: float = wind[i]/0.3048
			_near(feet,_reference(row.expected_ftps[i]),2e-13,row.id+"_direct_ftps_"+str(i))
			_near(feet*0.3048,wind[i],2e-14,row.id+"_direct_roundtrip_"+str(i))
		_near(result.speed_mps*(3600.0/1852.0),_reference(row.expected_speed_kt),1e-12,row.id+"_knots")
	if row.calm: _check(result.from_true_rad==null,row.id+"_calm_no_direction")
	else: _near(result.from_true_rad,_reference(row.expected_from_true_rad),1e-12,row.id+"_from_bearing")

func _air_case(row: Dictionary) -> void:
	var input: Dictionary = _source(_numbers(row.input_wind_toward_ned_mps))
	var q: Array = _numbers(row.input_body_to_ned_wxyz)
	var velocity: Array = _numbers(row.input_ground_body_mps)
	input.aircraft.orientation_body_to_ned={"w":q[0],"x":q[1],"y":q[2],"z":q[3]}
	input.aircraft.velocity_body_mps={"x":velocity[0],"y":velocity[1],"z":velocity[2]}
	input.canonical=Frames.derive(input.aircraft,Frames.anchor(0.8,-2.0,0.0))
	var readings: Dictionary = Readings.from_readback(input)
	_check(readings.state=="live",row.id+"_full_qualified_pair")
	_near(readings.readings.tas.value,_reference(row.expected_tas_mps),2e-12,row.id+"_air_relative_TAS")
	_near(readings.readings.ground_speed.value,_reference(row.expected_ground_speed_mps),2e-12,row.id+"_ground_speed")
	_near(readings.readings.vertical_speed.value,_reference(row.expected_vertical_speed_up_mps),2e-12,row.id+"_up_speed")
	var cue: Dictionary = Cue.from_readback(input)
	_check(cue.state=="live" and cue.wind_toward_ned_mps==_numbers(row.input_wind_toward_ned_mps),row.id+"_cue_independent_of_attitude")

func _negatives() -> void:
	for bad in [null,{},[],"wind",false]: _invalid(bad,"whole_shape_"+str(typeof(bad)))
	var originals: Array = []
	for recipe in ["extra","wind_nan","wind_inf","anchor","turbulence","wet","seed","weather_model","fingerprint","world","model","source_tick","closed_flags","float_debt","source_missing","position","kind_name","seed_name","source_name","unknown_outcome"]:
		var v: Dictionary = _source([0.0,5.0,0.0])
		match recipe:
			"extra": v.unexpected=true
			"wind_nan": v.atmosphere.wind_toward_ned_mps.x=NAN
			"wind_inf": v.atmosphere.wind_toward_ned_mps.y=INF
			"anchor": v.world_anchor.longitude_rad=-1.0
			"turbulence": v.atmosphere.turbulence_ned_mps.x=0.1
			"wet": v.atmosphere.relative_humidity=0.1
			"seed": v.atmosphere.seed="43"
			"weather_model": v.atmosphere.model_id="spatial-future"
			"fingerprint": v.native_source_fingerprint="f".repeat(64)
			"world": v.prepared_world_sha256="f".repeat(64)
			"model": v.model_identity.version="future"
			"source_tick": v.atmosphere.tick="1"
			"closed_flags": v.host_mode="closed"
			"float_debt": v.debt_quanta=0.0
			"source_missing": v.atmosphere=null
			"position": v.atmosphere.position.ellipsoid_height_m=2000.0
			"kind_name": v.held_axes.kind=StringName("axes")
			"seed_name": v.atmosphere.seed=StringName("42")
			"source_name": v.native_source_fingerprint=StringName(Cue.SUPPORTED_SOURCE)
			"unknown_outcome": v.native_outcome="running"
		_invalid(v,"negative_"+recipe)
		originals.append(v)
	_check(originals.size()==20,"twenty_named_structural_negatives")
	var empty: Dictionary = _source()
	for key in Readings.NULLABLE: empty[key]=null
	empty.host_mode="closed";empty.native_live=false;empty.paused=false;empty.historical=true
	_invalid(empty,"empty_closed","empty")

func _lifecycle_copies() -> void:
	var input: Dictionary = _source([0.0,-5.0,0.0])
	for mode in ["paused","closed","stalled","coverage_blocked","discarded"]:
		var v: Dictionary = input.duplicate(true)
		v.host_mode=mode;v.paused=mode=="paused";v.native_live=mode=="paused";v.historical=mode!="paused"
		v.native_outcome="paused" if mode=="paused" else "discarded"
		if v.historical: v.canonical=null
		var result: Dictionary = Cue.from_readback(v)
		_check(result.state==("paused" if mode=="paused" else "historical") and result.error.is_empty(),mode+"_truthful_state")
		_check(result.speed_mps==5.0 and result.wind_toward_ned_mps==[0.0,-5.0,0.0],mode+"_retained_actual_wind")
	var residual: Dictionary = Cue.from_readback(_source([0.0,0.0,1e-12]))
	_check(residual.state=="live" and _bits(residual.wind_toward_ned_mps[2])==_bits(1e-12),"actual_vertical_residual_copied_not_clamped")
	_check(_bits(residual.wind_toward_airfield_eus_mps[1])==_bits(-1e-12),"actual_vertical_residual_EUS_up_sign")
	_check(residual.speed_mps==0.0 and residual.from_true_rad==null,"horizontal_calm_does_not_erase_actual_vertical_component")
	var first: Dictionary = Cue.from_readback(input)
	var untouched: Dictionary = first.duplicate(true)
	input.atmosphere.wind_toward_ned_mps.y=3.0
	_check(first==untouched,"input_mutation_cannot_change_prior_cue")
	first.wind_toward_ned_mps[0]=23.0;first.wind_toward_airfield_eus_mps[0]=29.0
	_check(Cue.from_readback(input).wind_toward_ned_mps==[0.0,3.0,0.0],"output_mutation_cannot_change_source_or_next_cue")
	for tick in ["9007199254740993","18446744073709551615"]:
		var v: Dictionary = _source()
		v.tick=tick;v.aircraft.tick=tick;v.atmosphere.tick=tick
		# Existing Wire elapsed check alone uses approximate legacy absolute seconds.
		# Tick identity is never parsed as signed integer nor normalized in the cue.
		v.aircraft.elapsed_s=float(tick)/120.0
		_check(Cue.from_readback(v).tick==tick,"full_uint64_identity_"+tick)

func _run() -> Dictionary:
	var path: String = "res://wind_tests/reference/expected-v1.json"
	_check(FileAccess.get_sha256(path)==EXPECTED_SHA,"frozen_reference_bytes")
	var packet: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
	var old: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://instrument_tests/reference.json"))
	_base=old.cases[0].input.duplicate(true)
	for row in packet.cases:
		if row.kind=="air-relative": _air_case(row)
		else: _cue_case(row)
	for row in packet.runway_expectations:
		var wind: Array = []
		for candidate in packet.cases:
			if candidate.kind=="profile" and candidate.profile==row.profile: wind=_numbers(candidate.input_wind_toward_ned_mps)
		var cue: Dictionary = Cue.from_readback(_source(wind))
		var north_flow: float = -cue.wind_toward_airfield_eus_mps[2]
		var east_flow: float = cue.wind_toward_airfield_eus_mps[0]
		var headwind: float = -north_flow if row.runway==36.0 else north_flow
		var from_right: float = -east_flow if row.runway==36.0 else east_flow
		_near(headwind,_reference(row.expected_headwind_mps),1e-12,row.id+"_headwind")
		_near(from_right,_reference(row.expected_wind_from_right_mps),1e-12,row.id+"_reciprocal_source_side")
	_negatives()
	_lifecycle_copies()
	return {"passed":failures.is_empty(),"checks":checks,"failures":failures.duplicate(),"scope":"Pure source-qualified synthetic Readback arithmetic/type/copy/lifecycle fixtures; no native or scene execution or binary authority claim","reference_cases":22,"runway_expectations":8,"reference_sha256":EXPECTED_SHA}
