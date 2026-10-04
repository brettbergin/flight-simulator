extends RefCounted
# Original MIT. Independent source-only expectations; synthetic copied records.
const Recorder = preload("res://replay/observed/recorder.gd")
const Review = preload("res://replay/observed/review.gd")
const TickMath = preload("res://replay/observed/tick_math.gd")
const Frames = preload("res://simulation/canonical_frames.gd")
const Readings = preload("res://cockpit/instruments/native_readings.gd")
const RESULT_KEYS: Array = ["ok","error","appended","status"]
const STATUS_KEYS: Array = ["contract_version","state","session_id","first_tick","last_observed_tick","last_sample_tick","sample_count","seal_reason","error","skipped_target_count","late_sample_count","uncaptured_tail_targets"]
const RECORD_KEYS: Array = ["contract_version","state","metadata","last_observed_tick","samples","seal_reason","error","skipped_target_count","late_sample_count","uncaptured_tail_targets"]
var _checks: int = 0
var _failures: Array[String] = []
var _host: Node
var _seed: Dictionary

func _check(value: bool, label: String) -> void:
	_checks+=1
	if not value:
		_failures.append(label)
	if _host!=null and _host.has_method("check"):
		_host.call("check",value,"observed_"+label)

func _keys(value: Variant, names: Array) -> bool:
	if not value is Dictionary or value.size()!=names.size():
		return false
	for key in value:
		if not key is String or not names.has(key):
			return false
	return true

func _source(tick: String="0", x: float=0.0, z: float=0.0) -> Dictionary:
	var value: Dictionary=_seed.duplicate(true)
	# ONLY known fixture counter path is restored from Godot JSON float parsing.
	value.debt_quanta=0
	value.host_mode="paused"
	value.paused=true
	value.native_outcome="paused"
	value.tick=tick
	value.aircraft.tick=tick
	value.atmosphere.tick=tick
	# Legacy Wire elapsed_s validation requires this fixture conversion; never
	# feeds the schedule oracle, target/count/cursor expectations or tick identity.
	value.aircraft.elapsed_s=float(tick)/120.0
	var prepared: Dictionary=Frames.anchor(0.8,-2.0,0.0)
	var r: Array=prepared.rotation
	var ecef: Array=[prepared.ecef[0]+r[0]*x+r[6]*z,prepared.ecef[1]+r[1]*x+r[7]*z,prepared.ecef[2]+r[2]*x+r[8]*z]
	var f: float=1.0/298.257223563
	var e2: float=f*(2.0-f)
	var horizontal: float=sqrt(ecef[0]*ecef[0]+ecef[1]*ecef[1])
	var latitude: float=atan2(ecef[2],horizontal*(1.0-e2))
	var height: float=0.0
	for iteration in 12:
		var radius: float=6378137.0/sqrt(1.0-e2*sin(latitude)*sin(latitude))
		height=horizontal/cos(latitude)-radius
		latitude=atan2(ecef[2],horizontal*(1.0-e2*radius/(radius+height)))
	var position: Dictionary={"latitude_rad":latitude,"longitude_rad":atan2(ecef[1],ecef[0]),"ellipsoid_height_m":height}
	value.aircraft.position=position.duplicate(true)
	value.atmosphere.position=position.duplicate(true)
	value.aircraft.ecef_position_m={"x":ecef[0],"y":ecef[1],"z":ecef[2]}
	value.canonical=Frames.derive(value.aircraft,prepared)
	# Supplied exact scalar canonical is within the declared requalification guard;
	# preserve its exact 3-4-5 geometry rather than fitting placement roundoff.
	value.canonical.anchor_eus_position_m=[x,0.0,z]
	return value

func _historical(value: Dictionary, closed: bool=false) -> Dictionary:
	var result: Dictionary=value.duplicate(true)
	result.host_mode="closed" if closed else "stalled"
	result.historical=true
	result.native_live=not closed
	result.paused=not closed
	if closed:
		result.debt_quanta=0
	result.canonical=null
	return result

func _empty_closed() -> Dictionary:
	var value: Dictionary=_source()
	for key in ["session_id","tick","aircraft","atmosphere","held_axes","native_outcome","named_start","model_identity","native_source_fingerprint","prepared_world_sha256","world_anchor","canonical"]:
		value[key]=null
	value.host_mode="closed"
	value.historical=true
	value.native_live=false
	value.paused=false
	return value

func _result(value: Variant, label: String) -> void:
	_check(_keys(value,RESULT_KEYS),label+"_exact_result")
	if not value is Dictionary:
		return
	_check(typeof(value.ok)==TYPE_BOOL and typeof(value.appended)==TYPE_BOOL and value.error is String and value.error.length()<=1024,label+"_typed_result")
	_check(_keys(value.status,STATUS_KEYS) and not value.status.has("samples") and not value.status.has("metadata"),label+"_bounded_status_without_history")

func run(host: Node=null) -> Dictionary:
	_host=host
	var packet: Variant=JSON.parse_string(FileAccess.get_file_as_string("res://observed_tests/expected-v1.json"))
	var inputs: Variant=JSON.parse_string(FileAccess.get_file_as_string("res://instrument_tests/reference.json"))
	if not packet is Dictionary or not inputs is Dictionary:
		_check(false,"frozen_packet_and_accepted_source_available")
		return _receipt()
	_seed=inputs.cases[0].input.duplicate(true)
	_check(packet.total_case_count==42 and packet.arithmetic_case_count==24 and packet.sampling_case_count==18,"frozen_case_counts")
	_check(Readings.from_readback(_source()).state=="paused","complete_synthetic_source_qualified")
	_arithmetic(packet)
	for value in packet.sampling_cases:
		_schedule(value,packet)
	_qualification()
	_copies_and_review()
	_review_type_mutants()
	_thread_rejections()
	return _receipt()

func _arithmetic(packet: Dictionary) -> void:
	for value in packet.arithmetic_cases:
		var c: Dictionary=value
		var expected: Dictionary=c.expected
		var b: Variant=c.b
		# Only independent add-small integer operand; identities remain Strings.
		if c.operation=="add_small" and typeof(b)==TYPE_FLOAT:
			b=int(b)
		var actual: Dictionary=TickMath.subtract(c.a,b) if c.operation=="subtract" else TickMath.add_small(c.a,b)
		_check(_keys(actual,["ok","error","value"]),c.id+"_closed_math_result")
		_check(actual.ok==expected.ok and actual.value==expected.decimal,c.id+"_exact_math_value")
		_check(actual.value==null or actual.value is String,c.id+"_decimal_not_float")
		if c.operation=="subtract":
			var bounded: Dictionary=TickMath.bounded_difference(c.a,b)
			_check(bounded.ok==(expected.bounded_int!=null),c.id+"_bound_admission")
			_check(bounded.value==null if expected.bounded_int==null else typeof(bounded.value)==TYPE_INT and bounded.value==int(expected.bounded_int),c.id+"_bounded_exact_integer")
	for bad in [0.0,1,true,null,{},[],"+1","1.0","-1","","00"]:
		_check(not TickMath.subtract(bad,"0").ok and not TickMath.add_small(bad,1).ok,"math_malformed_tick_"+str(bad))
	_check(not TickMath.add_small("0",1.0).ok and not TickMath.add_small("0",144001).ok,"small_operand_no_coercion_or_unbounded_loop")
	_check(not TickMath.subtract(StringName("60"),"0").ok and not TickMath.add_small(StringName("0"),60).ok and not TickMath.bounded_difference("60",StringName("0")).ok,"math_tick_stringname_not_string")

func _schedule(c: Dictionary, packet: Dictionary) -> void:
	var recorder:=Recorder.new()
	var first: Dictionary=_source(c.first_tick)
	var initial: Dictionary=recorder.begin(first)
	_result(initial,c.id+"_begin")
	_check(initial.ok and initial.appended,c.id+"_first_actual_sample")
	if c.has("observed_grid"):
		for tick in range(int(c.observed_grid.first),int(c.observed_grid.last)+1,int(c.observed_grid.step)):
			var observed: Dictionary=recorder.observe(_source(str(tick)))
			_check(observed.ok and observed.appended,c.id+"_grid_"+str(tick))
	else:
		for value in c.observations:
			var item: Dictionary=value
			var observed: Dictionary
			if item.kind=="manual":
				observed=recorder.seal("manual")
			elif item.kind=="closed_empty":
				observed=recorder.observe(_empty_closed())
			else:
				var source: Dictionary=_source(item.tick,float(item.position_xz_m[0]),float(item.position_xz_m[1]))
				if item.kind=="historical":
					source=_historical(source)
				elif item.kind=="foreign":
					source.session_id="synthetic-foreign"
					source.aircraft.session_id=source.session_id
					source.atmosphere.session_id=source.session_id
				elif item.kind=="malformed":
					source.debt_quanta=0.0
				observed=recorder.observe(source)
			_result(observed,c.id+"_observe")
	var actual: Dictionary=recorder.recording()
	var status: Dictionary=recorder.status()
	var expected: Dictionary=c.expected
	_check(_keys(actual,RECORD_KEYS) and _keys(status,STATUS_KEYS),c.id+"_exact_record_and_status")
	for key in ["state","last_observed_tick","seal_reason","skipped_target_count","late_sample_count","uncaptured_tail_targets"]:
		_check(actual[key]==expected[key] and status[key]==expected[key],c.id+"_"+key)
	_check(actual.metadata.first_tick==expected.first_tick and status.first_tick==expected.first_tick,c.id+"_actual_first_tick")
	_check(actual.samples.size()==int(expected.sample_count) and status.sample_count==int(expected.sample_count) and status.last_sample_tick==expected.last_sample_tick,c.id+"_counts_and_distinct_endpoints")
	_check(first.tick==c.first_tick and first.debt_quanta==0,c.id+"_begin_input_unmutated")
	var expected_samples: Array=expected.get("samples",[])
	var chord: float=0.0
	for index in actual.samples.size():
		var sample: Dictionary=actual.samples[index]
		var oracle: Dictionary
		if expected.has("exact_samples_grid"):
			oracle={"tick":str(index*60),"target_tick":str(index*60),"late_by_ticks":0,"skipped_targets_before":0,"gap_before":false,"position_xz_m":[0.0,0.0]}
		else:
			oracle=expected_samples[index]
		_check(_keys(sample,["tick","target_tick","late_by_ticks","skipped_targets_before","gap_before","elapsed_s","anchor_eus_position_m","readings","held_axes"]),c.id+"_sample_closed_"+str(index))
		_check(typeof(sample.late_by_ticks)==TYPE_INT and typeof(sample.skipped_targets_before)==TYPE_INT and typeof(sample.gap_before)==TYPE_BOOL and typeof(sample.elapsed_s)==TYPE_FLOAT,c.id+"_sample_scalar_types_"+str(index))
		for key in ["tick","target_tick","late_by_ticks","skipped_targets_before","gap_before"]:
			_check(sample[key]==oracle[key],c.id+"_sample_"+str(index)+"_"+key)
		_check(sample.anchor_eus_position_m==[float(oracle.position_xz_m[0]),0.0,float(oracle.position_xz_m[1])],c.id+"_stored_canonical_scalars_"+str(index))
		_check(sample.readings.tick==sample.tick and sample.readings.session_id==actual.metadata.session_id,c.id+"_source_reading_identity_"+str(index))
		if index>0 and not sample.gap_before:
			var previous: Dictionary=actual.samples[index-1]
			var dx: float=sample.anchor_eus_position_m[0]-previous.anchor_eus_position_m[0]
			var dz: float=sample.anchor_eus_position_m[2]-previous.anchor_eus_position_m[2]
			chord+=sqrt(dx*dx+dz*dz)
	_check(absf(chord-float(expected.sampled_planar_track_m_decimal))<=float(packet.tolerances_before_observation.chord_abs_m_decimal),c.id+"_captured_chords_break_only_on_true_gaps")
	var baseline: Dictionary=recorder.recording()
	if baseline.state=="sealed":
		recorder.seal("manual")
		recorder.observe(_source())
		_check(recorder.recording()==baseline,c.id+"_sealed_no_later_update")

func _qualification() -> void:
	var mutants: Array=[]
	for kind in ["unknown_key","seed","pair_tick","clock","model","fingerprint","float_debt","held_kind","nonfinite","canonical_position","canonical_rotation","missing_canonical"]:
		var source: Dictionary=_source("60")
		match kind:
			"unknown_key": source.extra=true
			"seed": source.atmosphere.seed="43"
			"pair_tick": source.atmosphere.tick="61"
			"clock": source.aircraft.clock.tick_rate_hz=60
			"model": source.model_identity.id="different-model"
			"fingerprint": source.native_source_fingerprint="NOT_A_FINGERPRINT"
			"float_debt": source.debt_quanta=0.0
			"held_kind": source.held_axes.kind=StringName("axes")
			"nonfinite": source.aircraft.velocity_body_mps.x=INF
			"canonical_position": source.canonical.anchor_eus_position_m[0]+=1.0
			"canonical_rotation": source.canonical.body_to_anchor_eus=Frames.quaternion_matrix([0.0,0.0,0.0,1.0])
			"missing_canonical": source.canonical=null
		mutants.append({"kind":kind,"source":source})
	for value in mutants:
		var recorder:=Recorder.new()
		var rejected: Dictionary=recorder.begin(value.source)
		_result(rejected,"empty_"+value.kind)
		_check(not rejected.ok and recorder.status().state=="empty" and recorder.status().error.is_empty(),"empty_bad_"+value.kind)
		recorder.begin(_source())
		recorder.observe(_source("30"))
		rejected=recorder.observe(value.source)
		var reason: String="identity_changed" if value.kind in ["seed","model"] else "invalid_observation"
		_check(not rejected.ok and recorder.status().seal_reason==reason and recorder.status().last_observed_tick=="30" and recorder.status().sample_count==1,"retained_bad_"+value.kind)
	var recorder:=Recorder.new()
	var value: Dictionary=_source()
	recorder.begin(value)
	value.held_axes.throttle=0.5
	_check(not recorder.observe(value).ok and recorder.status().seal_reason=="invalid_observation","same_tick_changed_held_axes_rejected")
	recorder=Recorder.new()
	value=_source()
	recorder.begin(value)
	value.paused=false
	value.host_mode="live"
	value.native_outcome="completed"
	value.time_scale=4.0
	value.debt_quanta=480000
	_check(recorder.observe(value).ok and recorder.status().sample_count==1,"same_tick_pause_scale_debt_labels_not_physics")
	_check(recorder.observe(_historical(value,true)).ok and recorder.status().seal_reason=="closed","same_tick_terminal_null_canonical_not_conflict")
	recorder=Recorder.new()
	recorder.begin(_source("61"))
	value=_source("60")
	_check(not recorder.observe(value).ok and recorder.status().last_observed_tick=="61","backward_preserves_qualified_endpoint")
	recorder=Recorder.new()
	recorder.begin(_source())
	value=_source("60")
	value.native_source_fingerprint="e".repeat(64)
	_check(not recorder.observe(value).ok and recorder.status().seal_reason=="identity_changed" and recorder.status().last_observed_tick=="0","changed_valid_identity_preserves_prefix")
	recorder=Recorder.new()
	value=_source()
	value.aircraft.systems=[]
	_check(recorder.begin(value).ok and recorder.recording().samples[0].readings.readings.fuel_total.value==null and not recorder.recording().samples[0].readings.readings.fuel_total.valid,"missing_fuel_is_channel_gap_not_zero_or_whole_invalid")
	recorder=Recorder.new()
	value=_source()
	var half: float=sqrt(0.5)
	value.aircraft.orientation_body_to_ned={"w":half,"x":0.0,"y":half,"z":0.0}
	value.canonical=Frames.derive(value.aircraft,Frames.anchor(0.8,-2.0,0.0))
	_check(recorder.begin(value).ok and recorder.recording().samples[0].readings.readings.heading_true.value==null and recorder.recording().samples[0].readings.readings.pitch.valid,"singular_heading_preserved_unavailable")

func _copies_and_review() -> void:
	var recorder:=Recorder.new()
	var source: Dictionary=_source()
	var result: Dictionary=recorder.begin(source)
	source.held_axes.throttle=0.9
	source.canonical.anchor_eus_position_m[0]=999.0
	result.status.first_tick="999"
	var record: Dictionary=recorder.recording()
	_check(record.metadata.first_tick=="0" and record.samples[0].held_axes.throttle!=0.9 and record.samples[0].anchor_eus_position_m[0]==0.0,"begin_input_result_deep_copies")
	record.samples[0].readings.readings.tas.value=999.0
	record.metadata.world_anchor.latitude_rad=0.0
	_check(recorder.recording().samples[0].readings.readings.tas.value!=999.0 and recorder.recording().metadata.world_anchor.latitude_rad==0.8,"recording_deep_copy")
	_check(not recorder.begin(_source(),true).ok and recorder.status().first_tick=="0","same_session_replacement_not_authorized")
	var other: Dictionary=_source()
	other.session_id="synthetic-new-session"
	other.aircraft.session_id=other.session_id
	other.atmosphere.session_id=other.session_id
	_check(not recorder.begin(other).ok,"different_session_needs_explicit_replacement")
	_check(recorder.begin(other,true).ok and recorder.status().session_id==other.session_id,"explicit_qualified_replacement")
	recorder.observe(_source_for_session("60",other.session_id))
	var review:=Review.new()
	var baseline: Dictionary=recorder.recording()
	_check(review.set_recording(baseline) and review.selection().sample_index==1 and review.selection().historical,"review_defaults_actual_latest_historical")
	var selected: Dictionary=review.select(0)
	_check(selected.available and selected.sample.tick=="0" and selected.historical,"review_actual_sample_not_interpolation")
	selected.sample.held_axes.throttle=0.99
	baseline.samples[0].held_axes.throttle=0.99
	_check(review.selection().sample.held_axes.throttle!=0.99,"review_selection_and_input_copied")
	var previous: Dictionary=review.selection()
	_check(not review.select(99).available and review.selection()==previous,"invalid_index_does_not_replace_valid_selection")
	var invalid: Dictionary=recorder.recording()
	invalid.samples[1].skipped_targets_before=1
	_check(not review.set_recording(invalid) and not review.selection().available,"inconsistent_sample_gap_counts_reject_and_clear")
	_check(review.set_recording(recorder.recording()),"review_restore_valid_after_rejection")
	var empty:=Recorder.new()
	_check(review.set_recording(empty.recording()) and not review.selection().available,"empty_recording_explicit_unavailable")
	var empty_result: Dictionary=empty.observe(_empty_closed())
	_check(empty_result.ok and empty.status().state=="empty" and empty.status().error.is_empty(),"empty_closed_noop")

func _source_for_session(tick: String, session: String) -> Dictionary:
	var value: Dictionary=_source(tick)
	value.session_id=session
	value.aircraft.session_id=session
	value.atmosphere.session_id=session
	return value

func _review_type_mutants() -> void:
	var recorder:=Recorder.new()
	recorder.begin(_source())
	recorder.observe(_source("60"))
	var baseline: Dictionary=recorder.recording()
	var review:=Review.new()
	for kind in ["unknown_key","float_counter","held_kind","model_stringname","hash_stringname","seed_stringname","start_stringname","clock_stringname","reading_state_stringname","unit_stringname","session_stringname","nonfinite_channel","missing_channel","object_value"]:
		var invalid: Dictionary=baseline.duplicate(true)
		match kind:
			"unknown_key": invalid.extra=true
			"float_counter": invalid.skipped_target_count=0.0
			"held_kind": invalid.samples[0].held_axes.kind=StringName("axes")
			"model_stringname": invalid.metadata.model_identity.id=StringName(invalid.metadata.model_identity.id)
			"hash_stringname": invalid.metadata.prepared_world_sha256=StringName(invalid.metadata.prepared_world_sha256)
			"seed_stringname": invalid.metadata.seed=StringName("42")
			"start_stringname": invalid.metadata.named_start=StringName(invalid.metadata.named_start)
			"clock_stringname": invalid.metadata.clock.purpose=StringName("runtime")
			"reading_state_stringname": invalid.samples[0].readings.state=StringName("paused")
			"unit_stringname": invalid.samples[0].readings.readings.tas.unit=StringName("m/s")
			"session_stringname": invalid.samples[0].readings.session_id=StringName(invalid.metadata.session_id)
			"nonfinite_channel": invalid.samples[0].readings.readings.tas.value=INF
			"missing_channel": invalid.samples[0].readings.readings.erase("fuel_total")
			"object_value": invalid.samples[0].held_axes.roll=RefCounted.new()
		_check(review.set_recording(baseline),"review_type_fixture_restored_"+kind)
		_check(not review.set_recording(invalid) and not review.selection().available,"review_strict_closed_types_"+kind)

func _thread_rejections() -> void:
	var recorder:=Recorder.new()
	recorder.begin(_source())
	var review:=Review.new()
	review.set_recording(recorder.recording())
	var before: Dictionary=recorder.recording()
	var selection_before: Dictionary=review.selection()
	var thread:=Thread.new()
	var error: Error=thread.start(func() -> Dictionary:
		return {"mutation":recorder.seal("manual"),"status":recorder.status(),"recording":recorder.recording(),"set":review.set_recording({}),"select":review.select(0),"selection":review.selection()})
	_check(error==OK,"actual_foreign_thread_started")
	if error!=OK:
		return
	var alien: Variant=thread.wait_to_finish()
	var message: String="Observed flight review belongs to its main-thread owner"
	_check(alien.mutation=={"ok":false,"error":message,"appended":false,"status":null} and alien.status==null and alien.recording==null,"foreign_recorder_exact_null_no_owner_read")
	var unavailable: Dictionary={"available":false,"error":message,"sample_index":null,"sample":null,"historical":true}
	_check(not alien.set and alien.select==unavailable and alien.selection==unavailable,"foreign_review_exact_unavailable_no_owner_read")
	_check(recorder.recording()==before and review.selection()==selection_before,"foreign_calls_preserve_owner_record_selection")

func _receipt() -> Dictionary:
	return {"passed":_failures.is_empty(),"checks":_checks,"failures":_failures.duplicate(),"reference_cases":42,"reference_sha256":"a4c3184c46f2eb76c85ff4ba43fc8aac49e772a447576eeec5663fff1ac78844","scope":"Pure actual recorder/review over frozen integer/rational references and synthetic full Readbacks. No native dynamics, scene lifecycle, persistence, pilot or phase acceptance."}
