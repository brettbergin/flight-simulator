extends RefCounted
# Original MIT. Authored complete Readback inputs, not native flight observations.
const Recorder = preload("res://replay/observed/recorder.gd")
const Review = preload("res://replay/observed/review.gd")
const Values = preload("res://replay/observed/values.gd")
const Readings = preload("res://cockpit/instruments/native_readings.gd")
const Frames = preload("res://simulation/canonical_frames.gd")
const REFERENCE_SHA: String = "413eb124254432f8b39d7079b773d14e276415aa54749de3a1d85e527bf70aae"
const UNITS: Dictionary = {
	"fuel.total":"kg","engine.throttle":"fraction","engine.mixture":"fraction",
	"propeller.angular_speed":"radps","engine.running":"bool",
	"engine.ignition_left":"bool","engine.ignition_right":"bool",
	"engine.starter":"bool","fuel.feed":"bool","engine.starved":"bool"}
const COLD: Dictionary = {
	"fuel.total":100.0,"engine.throttle":0.0,"engine.mixture":0.0,
	"propeller.angular_speed":0.0,"engine.running":false,
	"engine.ignition_left":false,"engine.ignition_right":false,
	"engine.starter":false,"fuel.feed":true,"engine.starved":false}
var _checks: int = 0
var _failures: Array[String] = []
var _host: Node
var _seed: Dictionary = {}

func _check(ok: bool, label: String) -> void:
	_checks+=1
	if not ok:
		_failures.append(label)
	if _host!=null and _host.has_method("check"):
		_host.call("check",ok,"piston_observed_"+label)

func _system(source: Dictionary, id: String) -> Dictionary:
	for row in source.aircraft.systems:
		if row.id==id:
			return row
	return {}

func _legacy() -> Dictionary:
	var source: Dictionary = _seed.duplicate(true)
	source.host_mode="paused"
	source.paused=true
	source.native_outcome="paused"
	return source

func _source(tick: String = "0") -> Dictionary:
	var source: Dictionary = _legacy()
	source.model_identity=Readings.PISTON_PROFILE.duplicate(true)
	source.named_start="piston-cold-ground"
	source.held_axes.throttle=0.0
	source.held_axes.mixture=0.0
	source.held_axes.left_brake=1.0
	source.held_axes.right_brake=1.0
	# Same original synthetic geometry as EngineStatus tests, never native proof.
	source.aircraft.position.ellipsoid_height_m=1.05
	source.atmosphere.position=source.aircraft.position.duplicate(true)
	var point: Array = Frames.anchor(0.8,-2.0,1.05).ecef
	source.aircraft.ecef_position_m={"x":point[0],"y":point[1],"z":point[2]}
	source.canonical=Frames.derive(source.aircraft,Frames.anchor(0.8,-2.0,0.0))
	source.tick=tick
	source.aircraft.tick=tick
	source.atmosphere.tick=tick
	# Presentation fixture conversion only; expected sampling targets stay Strings.
	source.aircraft.elapsed_s=float(tick)/120.0
	source.aircraft.systems=[]
	for id in UNITS:
		source.aircraft.systems.append({"id":id,"quantity":UNITS[id],"value":COLD[id],"validity":"valid"})
	return source

func _session(source: Dictionary, id: String) -> Dictionary:
	source.session_id=id
	source.aircraft.session_id=id
	source.atmosphere.session_id=id
	return source

func _closed(source: Dictionary, mode: String = "closed") -> Dictionary:
	var result: Dictionary = source.duplicate(true)
	result.host_mode=mode
	result.historical=true
	result.native_live=false
	result.paused=false
	result.debt_quanta=0
	result.canonical=null
	return result

func _empty_closed() -> Dictionary:
	var result: Dictionary = _closed(_source())
	result.time_scale=1.0
	for key in Readings.NULLABLE:
		result[key]=null
	return result

func _bits(value: float) -> PackedByteArray:
	var result := PackedByteArray()
	result.resize(8)
	result.encode_double(0,value)
	return result

func _negative_zero() -> float:
	# Decode original bytes at runtime; a folded -0.0 literal is not evidence.
	return PackedByteArray([0,0,0,0,0,0,0,128]).decode_double(0)

func run(host: Node = null) -> Dictionary:
	_host=host
	_checks=0
	_failures=[]
	var path: String = "res://instrument_tests/reference.json"
	_check(FileAccess.get_sha256(path)==REFERENCE_SHA,"frozen_complete_source_reference")
	var packet: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not packet is Dictionary or not packet.get("cases") is Array:
		_check(false,"complete_reference_available")
		return _receipt()
	for row in packet.cases:
		if row.id=="identity-zero":
			_seed=row.input.duplicate(true)
	if _seed.is_empty():
		_check(false,"identity_zero_source_present")
		return _receipt()
	# Only the existing declared zero-debt counter is restored after JSON parsing.
	if typeof(_seed.debt_quanta) not in [TYPE_INT,TYPE_FLOAT] or _seed.debt_quanta!=0.0:
		_check(false,"source_zero_debt_restoration")
		return _receipt()
	_seed.debt_quanta=0
	_check(Readings.from_readback(_source()).state=="paused","complete_authored_piston_source_qualifies")
	var probe := Recorder.new()
	if not probe.begin(_source()).ok:
		_check(false,"v2_begin_prerequisite")
		return _receipt()
	_positive_and_copies()
	_partial_channels()
	_same_tick()
	_endpoints_and_replacement()
	_record_mutants()
	return _receipt()

func _positive_and_copies() -> void:
	var recorder := Recorder.new()
	_check(recorder.status().contract_version==1 and recorder.recording()==Values.empty_recording(),"fresh_empty_v1_unchanged")
	var source: Dictionary = _source()
	source.held_axes.mixture=0
	var before: PackedByteArray = var_to_bytes(source)
	var begun: Dictionary = recorder.begin(source)
	_check(Values.keys(begun,["ok","error","appended","status"]) and begun.ok and begun.appended and begun.status.contract_version==2,"begin_exact_result_and_revision2")
	_check(var_to_bytes(source)==before,"begin_input_not_mutated")
	var record: Dictionary = recorder.recording()
	_check(Values.valid_recording(record) and record.contract_version==2 and record.samples.size()==1 and typeof(record.samples[0].held_axes.mixture)==TYPE_INT,"owned_v2_sample_preserves_axis_integer")
	for key in record.samples[0]:
		_check(typeof(key)==TYPE_STRING,"generated_sample_key_is_String_"+str(key))
	if not Values.valid_recording(record): return
	var engine: Dictionary = record.samples[0].engine_status
	_check(Values.keys(engine,["session_id","tick","state","native_truth","readings","error"]) and engine.session_id==record.metadata.session_id and engine.tick=="0" and engine.state=="paused" and engine.native_truth,"engine_identity_and_state")
	for id in COLD:
		_check(engine.readings[id].value==COLD[id] and engine.readings[id].unit==UNITS[id] and engine.readings[id].valid,"cold_copied_"+id)
	var next: Dictionary = _source("60")
	next.held_axes.throttle=0.25
	next.held_axes.mixture=0.75
	_system(next,"engine.throttle").value=0.25
	_system(next,"engine.mixture").value=0.75
	_system(next,"propeller.angular_speed").value=120.0
	_system(next,"engine.running").value=true
	var observed: Dictionary = recorder.observe(next)
	record=recorder.recording()
	_check(observed.ok and observed.appended and record.samples.size()==2 and record.samples[1].target_tick=="60" and not record.samples[1].gap_before and Values.valid_recording(record),"second_actual_sample_and_valid_record")
	_check(record.samples[1].engine_status.readings["engine.mixture"].value==0.75 and record.samples[1].engine_status.readings["propeller.angular_speed"].value==120.0 and record.samples[1].engine_status.readings["engine.running"].value==true,"chosen_running_values_not_inferred")
	_system(next,"fuel.total").value=1.0
	record.samples[1].engine_status.readings["engine.mixture"].value=0.1
	_check(recorder.recording().samples[1].engine_status.readings["fuel.total"].value==100.0 and recorder.recording().samples[1].engine_status.readings["engine.mixture"].value==0.75,"input_and_record_output_do_not_alias")
	var review := Review.new()
	var retained: Dictionary = recorder.recording()
	var admitted: bool=review.set_recording(retained)
	_check(admitted and review.selection().historical and review.selection().sample.tick=="60","review_latest_actual_sample_historical")
	if not admitted: return
	var selected: Dictionary = review.select(0)
	selected.sample.engine_status.readings["fuel.feed"].value=false
	retained.samples[0].engine_status.readings["fuel.feed"].value=false
	_check(review.selection().sample.engine_status.readings["fuel.feed"].value==true,"review_input_and_output_owned_engine_copies")
	var selection_before: Dictionary = review.selection()
	_check(not review.select(99).available and review.selection()==selection_before,"invalid_selection_retains_prior_sample")
	var legacy := Recorder.new()
	_check(legacy.begin(_legacy()).ok and legacy.status().contract_version==1 and legacy.recording().samples[0].size()==9 and not legacy.recording().samples[0].has("engine_status"),"legacy_exact_nine_key_sample_retained")
	var mixed: Dictionary = legacy.recording()
	mixed.samples[0].engine_status=engine
	_check(not Values.valid_recording(mixed),"legacy_rejects_extra_engine_view")
	_check(Values.valid_recording(Values.empty_recording(2)) and review.set_recording(Values.empty_recording(2)) and not review.selection().available,"canonical_empty2_has_no_selection")

func _partial_channels() -> void:
	for id in UNITS:
		var source: Dictionary = _source()
		source.aircraft.systems.erase(_system(source,id))
		var recorder := Recorder.new()
		var result: Dictionary = recorder.begin(source)
		_check(result.ok,"missing_system_does_not_discard_sample_"+id)
		if not result.ok:
			continue
		var record: Dictionary = recorder.recording()
		var channel: Dictionary = record.samples[0].engine_status.readings[id]
		_check(Values.valid_recording(record) and channel.value==null and not channel.valid and not channel.error.is_empty(),"missing_channel_stays_unavailable_"+id)
		if id=="fuel.total":
			var flight: Dictionary = record.samples[0].readings.readings.fuel_total
			_check(not flight.valid and flight.value==null,"missing_fuel_both_views_unavailable")
			flight.error="Flight channel unavailable"
			channel.error="Engine channel unavailable"
			_check(Values.valid_recording(record),"unavailable_fuel_error_wording_may_differ")
	var source: Dictionary = _source()
	_system(source,"propeller.angular_speed").quantity="pa"
	var recorder := Recorder.new()
	_check(recorder.begin(source).ok and recorder.recording().samples[0].engine_status.readings["propeller.angular_speed"].value==null,"wrong_unit_is_unavailable_not_zero")

func _same_tick() -> void:
	var recorder := Recorder.new()
	var source: Dictionary = _source()
	recorder.begin(source)
	source.host_mode="live"
	source.paused=false
	source.native_outcome="completed"
	source.time_scale=4.0
	source.debt_quanta=480000
	_check(recorder.observe(source).ok and recorder.status().sample_count==1,"same_tick_display_labels_not_engine_conflict")
	_check(recorder.observe(_closed(source)).ok and recorder.status().seal_reason=="closed" and recorder.status().sample_count==1,"same_tick_historical_engine_labels_do_not_append")
	for id in ["engine.starter","engine.running","propeller.angular_speed","fuel.total"]:
		recorder=Recorder.new()
		source=_source()
		recorder.begin(source)
		_system(source,id).value=true if UNITS[id]=="bool" else 1.0
		var result: Dictionary = recorder.observe(source)
		_check(not result.ok and recorder.status().seal_reason=="invalid_observation" and recorder.status().sample_count==1 and recorder.status().last_observed_tick=="0","same_tick_changed_engine_seals_prefix_"+id)
	recorder=Recorder.new()
	source=_source()
	recorder.begin(source)
	var negative_zero: float=_negative_zero()
	_check(_bits(negative_zero).hex_encode()=="0000000000000080" and _bits(0.0).hex_encode()=="0000000000000000","same_tick_actual_distinct_signed_zero_witness")
	_system(source,"propeller.angular_speed").value=negative_zero
	_check(not recorder.observe(source).ok,"same_tick_engine_signed_zero_change_detected")

func _endpoints_and_replacement() -> void:
	var recorder := Recorder.new()
	recorder.begin(_source())
	recorder.observe(_source("61"))
	recorder.observe(_source("181"))
	var record: Dictionary = recorder.recording()
	_check(record.samples.size()==3 and record.samples[1].target_tick=="60" and record.samples[2].target_tick=="180" and record.samples[2].gap_before and record.skipped_target_count==1 and record.late_sample_count==2 and Values.valid_recording(record),"existing_grid_late_gap_semantics_apply_to_v2")
	for mode in ["closed","stalled"]:
		recorder=Recorder.new()
		recorder.begin(_source())
		recorder.observe(_source("60"))
		var ended: Dictionary = recorder.observe(_closed(_source("180"),mode))
		record=recorder.recording()
		_check(ended.ok and not ended.appended and record.samples.size()==2 and record.last_observed_tick=="180" and record.uncaptured_tail_targets==2 and record.seal_reason==("closed" if mode=="closed" else "terminal") and Values.valid_recording(record),"terminal_endpoint_has_no_invented_sample_"+mode)
	recorder=Recorder.new()
	recorder.begin(_source())
	recorder.observe(_source("30"))
	_check(recorder.observe(_empty_closed()).ok and recorder.status().last_observed_tick=="30" and recorder.status().seal_reason=="closed","empty_closed_retains_prior_endpoint")
	var baseline: PackedByteArray = var_to_bytes(recorder.recording())
	var malformed: Dictionary = _session(_source(),"new-piston-session")
	_system(malformed,"engine.starter").value=1.0
	_check(not recorder.begin(malformed,true).ok and var_to_bytes(recorder.recording())==baseline,"failed_qualified_replacement_preserves_revision_and_history")
	var legacy: Dictionary = _session(_legacy(),"new-legacy-session")
	_check(not recorder.begin(legacy).ok and var_to_bytes(recorder.recording())==baseline,"unconfirmed_profile_change_preserves_history")
	_check(recorder.begin(legacy,true).ok and recorder.status().contract_version==1,"confirmed_legacy_replacement_after_v2")
	var piston: Dictionary = _session(_source(),"new-piston-session")
	_check(recorder.begin(piston,true).ok and recorder.status().contract_version==2,"confirmed_piston_replacement_after_v1")
	baseline=var_to_bytes(recorder.recording())
	_check(not recorder.begin(piston,true).ok and var_to_bytes(recorder.recording())==baseline,"same_session_replacement_stays_rejected")
	var changed: Dictionary = _source("60")
	changed.model_identity.id="other-piston"
	_check(not recorder.observe(changed).ok and recorder.status().seal_reason=="identity_changed" and recorder.status().last_observed_tick=="0","piston_start_identity_change_keeps_prefix")

func _record_mutants() -> void:
	var recorder := Recorder.new()
	recorder.begin(_source())
	var base: Dictionary = recorder.recording()
	_check(Values.valid_recording(base),"generated_base_qualified_before_mutants")
	if not Values.valid_recording(base): return
	var negative_zero: float=_negative_zero()
	_check(_bits(negative_zero).hex_encode()=="0000000000000080","mutant_actual_negative_zero_witness")
	for kind in ["float_revision","legacy_as_v2","piston_as_v1","missing_view","string_name_sample_key","extra_view_key","missing_channel","extra_channel","numeric_bool","bool_numeric","int_numeric","nonfinite_numeric","valid_null","valid_error","invalid_empty_error","invalid_false_value","long_channel_error","wrong_unit_type","wrong_session","wrong_tick","wrong_state","false_truth","view_error","negative_fuel","negative_shaft","fraction_range","axes_contradiction","fuel_validity","fuel_bits"]:
		var bad: Dictionary = base.duplicate(true)
		var sample: Dictionary = bad.samples[0]
		var engine: Dictionary = sample.engine_status
		match kind:
			"float_revision": bad.contract_version=2.0
			"legacy_as_v2": bad.metadata.model_identity=Readings.LEGACY_PROFILE.duplicate(true);bad.metadata.named_start="ground-ready"
			"piston_as_v1": bad.contract_version=1
			"missing_view": sample.erase("engine_status")
			"string_name_sample_key": sample.erase("engine_status");sample[StringName("engine_status")]=engine
			"extra_view_key": engine.extra=true
			"missing_channel": engine.readings.erase("engine.running")
			"extra_channel": engine.readings.extra=engine.readings["engine.running"].duplicate(true)
			"numeric_bool": engine.readings["engine.running"].value=0.0
			"bool_numeric": engine.readings["propeller.angular_speed"].value=false
			"int_numeric": engine.readings["propeller.angular_speed"].value=0
			"nonfinite_numeric": engine.readings["propeller.angular_speed"].value=NAN
			"valid_null": engine.readings["engine.running"].value=null
			"valid_error": engine.readings["engine.running"].error="Unexpected error"
			"invalid_empty_error": engine.readings["engine.running"]={"value":null,"unit":"bool","valid":false,"error":""}
			"invalid_false_value": engine.readings["engine.running"]={"value":false,"unit":"bool","valid":false,"error":"Unavailable"}
			"long_channel_error": engine.readings["engine.running"]={"value":null,"unit":"bool","valid":false,"error":"x".repeat(1025)}
			"wrong_unit_type": engine.readings["engine.running"].unit=StringName("bool")
			"wrong_session": engine.session_id="other-session"
			"wrong_tick": engine.tick="60"
			"wrong_state": engine.state="historical"
			"false_truth": engine.native_truth=false
			"view_error": engine.error="Global invalidity"
			"negative_fuel": engine.readings["fuel.total"].value=-1.0;sample.readings.readings.fuel_total.value=-1.0
			"negative_shaft": engine.readings["propeller.angular_speed"].value=-1.0
			"fraction_range": engine.readings["engine.mixture"].value=2.0
			"axes_contradiction": engine.readings["engine.throttle"].value=0.5
			"fuel_validity": engine.readings["fuel.total"]={"value":null,"unit":"kg","valid":false,"error":"Unavailable"}
			"fuel_bits": engine.readings["fuel.total"].value=negative_zero;sample.readings.readings.fuel_total.value=0.0
		var review := Review.new()
		_check(review.set_recording(base),"valid_review_before_mutant_"+kind)
		_check(not Values.valid_recording(bad) and not review.set_recording(bad) and not review.selection().available,"closed_v2_mutant_rejected_"+kind)
	var source: Dictionary = _source()
	source.held_axes.throttle=negative_zero
	_system(source,"engine.throttle").value=negative_zero
	recorder=Recorder.new()
	_check(recorder.begin(source).ok and _bits(recorder.recording().samples[0].held_axes.throttle)==_bits(negative_zero) and _bits(recorder.recording().samples[0].engine_status.readings["engine.throttle"].value)==_bits(negative_zero),"admitted_signed_zero_axes_and_engine_bits_preserved")

func _receipt() -> Dictionary:
	return {"passed":_failures.is_empty(),"checks":_checks,"failures":_failures.duplicate(),"scope":"Pure v2 recorder/review over original synthetic complete Readbacks; unchanged v1 oracle remains separate. No native flight, codec/file IO, UI, pilot or phase acceptance."}
