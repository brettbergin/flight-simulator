extends RefCounted
# Original analytic cases were frozen before consumers existed. All device inputs
# here are labeled synthetic readings; no physical device or native qualification.
const Mapper = preload("res://input/input_mapper.gd")
const Preset = preload("res://input/input_preset.gd")
const EPSILON = 1e-12 # Selected before first mapper comparison; arithmetic only.
var checks := 0
var failures: Array[String] = []
var references: Dictionary = {}
var covered: Dictionary = {}
var file_evidence: Dictionary = {}
# Diagnostic branch only: opt-in low-volume checkpoints, no payload/path output.
var _trace_enabled: bool = false
var _trace_started_usec: int = 0
var _trace_sequence: int = 0

func _trace(stage: String) -> void:
	if not _trace_enabled: return
	_trace_sequence += 1
	print("INPUT_PREFLIGHT_TRACE " + JSON.stringify({"schema":"InputPreflightPhase/v1","sequence":_trace_sequence,"stage":stage,"elapsed_usec":Time.get_ticks_usec()-_trace_started_usec,"checks":checks,"failures":failures.size()}))

func _trace_save(stage: String, target: String, value: Dictionary) -> Dictionary:
	_trace(stage+"_before")
	var result: Dictionary = Preset.save(target,value)
	_trace(stage+"_after")
	return result

static func run() -> Dictionary:
	return new()._run()

func _check(condition: bool, label: String) -> void:
	checks += 1
	if not condition: failures.append(label)

func _near(value: Variant, expected: float, label: String) -> void:
	_check((value is float or value is int) and is_finite(float(value)) and abs(float(value) - expected) <= EPSILON, label)

func _q(value: Variant) -> float:
	if value is Dictionary: return _q(value.rational)
	var pieces := str(value).split("/")
	return float(pieces[0]) / float(pieces[1]) if pieces.size() == 2 else float(pieces[0])

func _row(id: String) -> Dictionary:
	covered[id] = true
	return references[id]

func _axes() -> Dictionary:
	return {"kind":"axes","roll":0.0,"pitch":0.0,"yaw":0.0,"throttle":0.0,"mixture":1.0,"left_brake":0.0,"right_brake":0.0,"trim":0.0}

func _raw(keys: Array = [], values: Dictionary = {}, generation: int = 9) -> Dictionary:
	var devices: Array = []
	if not values.is_empty():
		var axes: Array = []
		for index in values: axes.append({"index":int(index),"value":float(values[index])})
		devices.append({"slot":"stick","generation":generation,"axes":axes,"buttons":[]})
	return {"keys":keys.duplicate(),"mouse_buttons":[],"devices":devices}

func _preset() -> Dictionary:
	return Mapper.default_preset().duplicate(true)

func _replace(preset: Dictionary, target: String, row: Dictionary) -> void:
	for i in preset.axes.size():
		if preset.axes[i].target == target:
			preset.axes[i] = row.duplicate(true)
			return
	_check(false, "test_target_exists_" + target)

func _joy(preset: Dictionary, target: String, index: int, input: Dictionary) -> void:
	if preset.devices.is_empty():
		preset.devices = [{"slot":"stick","label":"Synthetic observed controls","match":{"guid":"","name":"","vendor_id":"","product_id":""}}]
	_replace(preset, target, {"target":target,"kind":"joy_axis","slot":"stick","index":index,"range":"unsigned" if target in ["throttle","left_brake","right_brake"] else "centered","minimum":_q(input.get("minimum","-1")),"center":_q(input.get("center","0")),"maximum":_q(input.get("maximum","1")),"invert":input.get("invert",false),"deadzone":_q(input.get("deadzone","0")),"saturation":_q(input.get("saturation","1")),"gain":_q(input.get("gain","1")),"slew_per_s":_q(input.get("slew_per_s","0"))})

func _mapper(preset: Dictionary, held: Dictionary, start: Dictionary, raw: Dictionary, resume: bool = true) -> RefCounted:
	var mapper = Mapper.new()
	_check(mapper.configure(preset, held, start, raw).ok, "configure_valid")
	if resume: _check(mapper.resume_confirmed(raw).ok, "resume_valid")
	return mapper

func _shape(result: Dictionary, label: String) -> void:
	var keys := result.keys()
	keys.sort()
	_check(keys == ["actions","axes","brake_hold","error","ok","takeover"], label + "_six_keys")
	_check(result.ok is bool and result.error is String and result.actions is Array and result.takeover is Array and result.brake_hold is bool, label + "_types")
	if result.ok:
		_check(result.axes is Dictionary and result.axes.size() == 9 and result.axes.get("kind") == "axes", label + "_complete_axes")
	else:
		_check(result.axes == null and result.actions.is_empty() and result.takeover.is_empty() and not result.error.is_empty(), label + "_failed_closed")

func _key(name: String) -> int:
	return {"W":KEY_W,"S":KEY_S,"PageUp":KEY_PAGEUP,"PageDown":KEY_PAGEDOWN,"A":KEY_A,"D":KEY_D,"Left":KEY_LEFT,"Right":KEY_RIGHT,"Up":KEY_UP,"Down":KEY_DOWN,"[":KEY_BRACKETLEFT,"]":KEY_BRACKETRIGHT}[name]

func _mapping() -> void:
	for id in ["centered_asymmetric_left","centered_asymmetric_right","centered_inverted_right","centered_noise_deadzone","centered_deadzone_half","centered_saturated_gain","unsigned_asymmetric_quarter","unsigned_inverted_quarter","analog_wall_slew_bound","centered_negative_endpoint"]:
		var row := _row(id)
		var input: Dictionary = row.input
		var target := "left_brake" if id.begins_with("unsigned") else "roll"
		var preset := _preset()
		_joy(preset,target,JOY_AXIS_LEFT_X,input)
		var initial := _raw([], {JOY_AXIS_LEFT_X:_q(input.get("center","0")) if target == "roll" else _q(input.get("maximum","1") if input.get("invert",false) else input.get("minimum","-1"))})
		var mapper = _mapper(preset,_axes(),_axes(),initial)
		var raw_value := _q(input.get("raw",input.get("normalized",input.get("target","0"))))
		var result: Dictionary = mapper.sample(_raw([], {JOY_AXIS_LEFT_X:raw_value}),int(input.get("elapsed_us",0)))
		_shape(result,id)
		_check(result.ok,id + "_accepted")
		if result.ok: _near(result.axes[target],_q(row.expected.mapped),id + "_rational_value")
	var pedals := _row("separate_unsigned_pedals")
	var preset := _preset()
	_joy(preset,"left_brake",JOY_AXIS_LEFT_X,pedals.input)
	_joy(preset,"right_brake",JOY_AXIS_LEFT_Y,pedals.input)
	var mapper = _mapper(preset,_axes(),_axes(),_raw([], {JOY_AXIS_LEFT_X:-0.7,JOY_AXIS_LEFT_Y:-0.7}))
	var result: Dictionary = mapper.sample(_raw([], {JOY_AXIS_LEFT_X:-0.3,JOY_AXIS_LEFT_Y:0.5}),0)
	_check(result.ok,"separate_unsigned_pedals_accepted")
	if result.ok:
		_near(result.axes.left_brake,_q(pedals.expected.left_brake),"separate_left_quarter")
		_near(result.axes.right_brake,_q(pedals.expected.right_brake),"separate_right_three_quarters")

func _digital() -> void:
	for id in ["throttle_aliases_count_once","opposite_aliases_cancel","legacy_roll_start_bias","legacy_yaw_return_start","legacy_pitch_target_clamp","throttle_negative_rate","trim_positive_rate","unsigned_release_holds"]:
		var row := _row(id)
		var input: Dictionary = row.input
		var held := _axes()
		var start := _axes()
		var keys: Array = []
		if input.has("positive_pressed"):
			for name in input.positive_pressed: keys.append(_key(name))
		if input.has("negative_pressed"):
			for name in input.negative_pressed: keys.append(_key(name))
		for target in ["roll","pitch","yaw","throttle","trim"]:
			if input.has("held_" + target): held[target] = _q(input["held_" + target])
			if input.has("start_" + target): start[target] = _q(input["start_" + target])
		if id in ["throttle_aliases_count_once","opposite_aliases_cancel","throttle_negative_rate"]: held.throttle = _q(input.held)
		if id == "trim_positive_rate": held.trim = _q(input.held)
		if id == "legacy_roll_start_bias": keys = [KEY_RIGHT]
		if id == "legacy_pitch_target_clamp": keys = [KEY_DOWN]
		if id == "throttle_negative_rate": keys = [KEY_S]
		if id == "trim_positive_rate": keys = [KEY_BRACKETRIGHT]
		var mapper = _mapper(_preset(),held,start,_raw())
		var result: Dictionary = mapper.sample(_raw(keys),int(input.elapsed_us))
		_check(result.ok,id + "_accepted")
		if result.ok:
			for target in row.expected:
				if target != "target": _near(result.axes[target],_q(row.expected[target]),id + "_" + target)
	# Explicit elapsed schedules test timed sampling, not arbitrary device polling equivalence.
	for hz in [30,60,144]:
		var mapper = _mapper(_preset(),_axes(),_axes(),_raw())
		var previous := 0
		var result: Dictionary = {}
		for i in range(1,hz+1):
			var cut := int(i * 1000000 / hz)
			result = mapper.sample(_raw([KEY_W,KEY_RIGHT]),cut-previous)
			previous = cut
		_check(result.get("ok",false),"timed_schedule_accepted_" + str(hz))
		if result.get("ok",false):
			_near(result.axes.throttle,0.25,"timed_throttle_total_" + str(hz))
			_near(result.axes.roll,0.35,"timed_roll_target_" + str(hz))

func _latch() -> void:
	for ground in [true,false]:
		var row := _row("first_ground_hold_seed" if ground else "first_airborne_hold_false")
		var held := _axes()
		held.left_brake = 0.8 if ground else 0.0
		held.right_brake = held.left_brake
		var mapper = _mapper(_preset(),held,held,_raw())
		var result: Dictionary = mapper.sample(_raw(),0)
		_check(result.brake_hold == row.expected.brake_hold,row.id)
	var row := _row("later_apply_preserves_false")
	var mapper = _mapper(_preset(),_axes(),_axes(),_raw())
	var held := _axes()
	held.left_brake = 1.0
	held.right_brake = 1.0
	_check(mapper.configure(_preset(),held,held,_raw()).ok,"later_apply_accepted")
	_check(mapper.sample(_raw(),0).brake_hold == row.expected.brake_hold,"later_apply_preserves_false")
	row = _row("B_edge_one_toggle")
	var start := _axes()
	start.left_brake = 0.8
	start.right_brake = 0.8
	mapper = _mapper(_preset(),start,start,_raw())
	for i in row.input.B_samples.size():
		var result: Dictionary = mapper.sample(_raw([KEY_B] if row.input.B_samples[i] else []),0)
		_check(result.brake_hold == row.expected.brake_hold_after_each[i],"B_edge_" + str(i))
	row = _row("held_overrides_return_primary")
	var preset := _preset()
	_joy(preset,"left_brake",JOY_AXIS_LEFT_X,{"minimum":-0.7,"maximum":0.9})
	_joy(preset,"right_brake",JOY_AXIS_LEFT_Y,{"minimum":-0.7,"maximum":0.9})
	mapper = _mapper(preset,_axes(),_axes(),_raw([], {JOY_AXIS_LEFT_X:-0.7,JOY_AXIS_LEFT_Y:-0.7}))
	for i in [0,1]:
		var result: Dictionary = mapper.sample(_raw([KEY_Q] if i == 0 else [],{JOY_AXIS_LEFT_X:-0.3,JOY_AXIS_LEFT_Y:0.5}),0)
		_near(result.axes.left_brake,_q(row.expected.brakes_after_each[i][0]),"left_override_" + str(i))
		_near(result.axes.right_brake,_q(row.expected.brakes_after_each[i][1]),"right_override_" + str(i))
	row = _row("suspend_preserves_hold")
	mapper = _mapper(_preset(),start,start,_raw())
	held = _axes()
	held.left_brake = 0.2
	held.right_brake = 0.4
	_check(mapper.suspend("synthetic focus",held).ok,"suspend_hold_accepted")
	_check(mapper.sample(_raw(),0).brake_hold,"suspended_latch_visible")
	_check(mapper.resume_confirmed(_raw()).ok,"resume_hold_accepted")
	var result: Dictionary = mapper.sample(_raw(),0)
	_check(result.brake_hold == row.expected.brake_hold,"hold_resume_latch")
	_near(result.axes.left_brake,1,"hold_resume_left")
	_near(result.axes.right_brake,1,"hold_resume_right")

func _lifecycle() -> void:
	_row("suspended_diagnostics_only")
	var held := _axes()
	held.throttle = 0.4
	var mapper = _mapper(_preset(),held,_axes(),_raw(),false)
	var result: Dictionary = mapper.sample(_raw([KEY_W,KEY_B,KEY_V]),0)
	_shape(result,"suspended")
	_check(result.ok and result.axes == held and result.actions.is_empty() and not result.brake_hold,"suspended_no_filter_or_edges")
	_row("suspended_elapsed_rejects")
	result = mapper.sample(_raw([KEY_W]),1)
	_shape(result,"suspended_nonzero")
	_check(not result.ok,"suspended_nonzero_rejected")
	_row("resume_pressed_flight_key_blocks")
	_check(not mapper.resume_confirmed(_raw([KEY_W])).ok,"resume_W_blocks")
	_check(mapper.sample(_raw(),0).axes == held,"resume_reject_keeps_held")
	var preset := _preset()
	_joy(preset,"throttle",JOY_AXIS_LEFT_X,{"minimum":0,"maximum":1})
	held = _axes()
	held.throttle = 0.6
	mapper = _mapper(preset,held,_axes(),_raw([], {JOY_AXIS_LEFT_X:0.1}),false)
	_row("resume_unmatched_absolute_allowed")
	_check(mapper.resume_confirmed(_raw([], {JOY_AXIS_LEFT_X:0.1})).ok,"unmatched_resume_allowed")
	result = mapper.sample(_raw([], {JOY_AXIS_LEFT_X:0.1}),0)
	_near(result.axes.throttle,0.6,"unmatched_holds")
	_check(result.takeover == ["throttle"],"unmatched_named_target")
	_row("takeover_matches_then_follows")
	for value in [0.58,0.7]:
		result = mapper.sample(_raw([], {JOY_AXIS_LEFT_X:value}),0)
		_near(result.axes.throttle,value,"takeover_follow_" + str(value))
		_check(result.takeover.is_empty(),"takeover_cleared")
	_row("idle_rearms_takeover")
	mapper = _mapper(preset,held,_axes(),_raw([],{JOY_AXIS_LEFT_X:0.6}))
	mapper.sample(_raw([],{JOY_AXIS_LEFT_X:0.6}),0)
	result = mapper.sample(_raw([KEY_X],{JOY_AXIS_LEFT_X:0.6}),0)
	_near(result.axes.throttle,0,"idle_zero")
	result = mapper.sample(_raw([],{JOY_AXIS_LEFT_X:0.6}),0)
	_near(result.axes.throttle,0,"unmoved_idle_keeps_zero")
	_check(result.takeover == ["throttle"],"idle_rearmed")
	for id in ["active_source_removed","slot_reused_generation_changed"]:
		_row(id)
		mapper = _mapper(preset,held,_axes(),_raw([],{JOY_AXIS_LEFT_X:0.1}))
		result = mapper.sample(_raw() if id == "active_source_removed" else _raw([],{JOY_AXIS_LEFT_X:0.1},10),0)
		_shape(result,id)
		_check(not result.ok,id)
	_row("bound_axis_unobserved")
	var missing := _raw([],{JOY_AXIS_LEFT_Y:0.0})
	mapper = Mapper.new()
	_check(not mapper.configure(preset,held,_axes(),missing).ok,"unobserved_axis_rejects_configure")
	_row("resume_centered_not_neutral")
	preset = _preset()
	_joy(preset,"roll",JOY_AXIS_LEFT_X,{})
	mapper = _mapper(preset,_axes(),_axes(),_raw([],{JOY_AXIS_LEFT_X:0.0}),false)
	_check(not mapper.resume_confirmed(_raw([],{JOY_AXIS_LEFT_X:0.06})).ok,"nonneutral_resume_rejected")
	_row("resume_primes_ui_edges_no_wheel_leak")
	mapper = _mapper(_preset(),_axes(),_axes(),_raw(),false)
	var paused_raw := _raw([KEY_P])
	paused_raw.mouse_buttons = [MOUSE_BUTTON_WHEEL_UP]
	_check(mapper.sample(paused_raw,0).actions.is_empty(),"paused_wheel_no_actions")
	_check(mapper.resume_confirmed(paused_raw).ok,"resume_UI_wheel_not_blocked")
	result = mapper.sample(_raw([KEY_P]),0)
	_check(result.actions.is_empty(),"held_resume_UI_not_fired_again")

func _invalid_and_copies() -> void:
	_row("invalid_calibration_atomic")
	var preset := _preset()
	var mapper = _mapper(preset,_axes(),_axes(),_raw())
	var bad := preset.duplicate(true)
	_joy(bad,"roll",JOY_AXIS_LEFT_X,{"minimum":0,"center":0.04,"maximum":1})
	_check(not mapper.configure(bad,_axes(),_axes(),_raw([],{JOY_AXIS_LEFT_X:0.04})).ok,"bad_span_rejected")
	_near(mapper.sample(_raw([KEY_W]),200000).axes.throttle,0.05,"bad_config_keeps_prior_filter")
	_row("runtime_mixture_rejected")
	bad = preset.duplicate(true)
	_joy(bad,"mixture",JOY_AXIS_LEFT_X,{})
	_check(not Preset.validate_preset(bad).ok,"codec_runtime_mixture_rejects")
	_check(not mapper.configure(bad,_axes(),_axes(),_raw([],{JOY_AXIS_LEFT_X:0.0})).ok,"mapper_runtime_mixture_rejects")
	var held := _axes()
	mapper = _mapper(preset,held,_axes(),_raw())
	held.throttle = 1.0
	for axis in preset.axes:
		if axis.target == "throttle": axis.rate = 4.0
	var raw := _raw([KEY_W])
	var result: Dictionary = mapper.sample(raw,200000)
	_near(result.axes.throttle,0.05,"caller_preset_held_are_copied")
	result.axes.throttle = 1.0
	raw.keys.clear()
	result = mapper.sample(_raw(),0)
	_near(result.axes.throttle,0.05,"returned_axes_are_copied")
	for elapsed in [-1,250001,9223372036854775807]:
		result = mapper.sample(_raw([KEY_W]),elapsed)
		_shape(result,"invalid_elapsed_" + str(elapsed))
		_check(not result.ok,"invalid_elapsed_rejected_" + str(elapsed))
	_near(mapper.sample(_raw(),0).axes.throttle,0.05,"invalid_elapsed_preserves_filter")
	for malformed in [{"keys":[KEY_W,KEY_W],"mouse_buttons":[],"devices":[]},{"keys":[],"mouse_buttons":[],"devices":[{"slot":"stick","generation":9,"axes":[{"index":JOY_AXIS_LEFT_X,"value":NAN}],"buttons":[]}]},{"keys":[],"mouse_buttons":[],"devices":[],"aircraft":{}}]:
		result = mapper.sample(malformed,0)
		_shape(result,"invalid_raw")
		_check(not result.ok,"invalid_raw_rejected")
		_near(mapper.sample(_raw(),0).axes.throttle,0.05,"invalid_raw_preserves_filter")

func _edges_and_failures() -> void:
	var mapper = _mapper(_preset(),_axes(),_axes(),_raw())
	for i in [0,1]:
		var wheel := _raw()
		wheel.mouse_buttons = [MOUSE_BUTTON_WHEEL_UP]
		_check(mapper.sample(wheel,0).actions == ["view_zoom_in"],"consecutive_wheel_pulse_" + str(i))
	var preset := _preset()
	for action in preset.actions:
		if action.id == "view_zoom_in": action.sources.append({"kind":"physical_keys","keys":[KEY_K]})
	mapper = _mapper(preset,_axes(),_axes(),_raw())
	for i in [0,1]:
		var combined := _raw([KEY_K])
		combined.mouse_buttons = [MOUSE_BUTTON_WHEEL_UP]
		_check(mapper.sample(combined,0).actions == ["view_zoom_in"],"wheel_and_key_alias_coalesce_" + str(i))
	_check(mapper.sample(_raw([KEY_K]),0).actions.is_empty(),"persistent_key_not_repeated_after_wheel")
	mapper.sample(_raw(),0)
	_check(mapper.sample(_raw([KEY_K]),0).actions == ["view_zoom_in"],"persistent_key_rearms_after_release")
	var unconfigured = Mapper.new()
	var result: Dictionary = unconfigured.sample(_raw(),0)
	_shape(result,"unconfigured")
	_check(not result.ok and not result.brake_hold,"unconfigured_failure_has_false_latch")
	var held := _axes()
	held.throttle = 0.4
	mapper = _mapper(_preset(),held,_axes(),_raw())
	mapper.sample(_raw([KEY_W]),200000)
	var invalid_held := held.duplicate(true)
	invalid_held.throttle = NAN
	_check(not mapper.suspend("synthetic invalid held",invalid_held).ok,"invalid_suspend_rejects")
	result = mapper.sample(_raw([KEY_W]),0)
	_near(result.axes.throttle,0.45,"invalid_suspend_preserves_last_valid_filter")
	_check(result.actions.is_empty() and not mapper.sample(_raw(),1).ok,"invalid_suspend_still_nonflight")
	preset = _preset()
	_joy(preset,"roll",JOY_AXIS_LEFT_X,{})
	var observed := _raw([],{JOY_AXIS_LEFT_X:0.0})
	mapper = _mapper(preset,_axes(),_axes(),observed)
	observed.devices[0].generation = 10
	_check(mapper.sample(_raw([],{JOY_AXIS_LEFT_X:0.0}),0).ok,"configure_raw_generation_copied")
	var duplicate := _raw([],{JOY_AXIS_LEFT_X:0.0})
	duplicate.devices[0].axes.append({"index":JOY_AXIS_LEFT_X,"value":0.0})
	result = mapper.sample(duplicate,0)
	_shape(result,"duplicate_observation")
	_check(not result.ok,"duplicate_axis_observation_rejected")
	# Bound joy buttons also require actual sparse observations, not fabricated false.
	preset = _preset()
	preset.devices = [{"slot":"stick","label":"Synthetic button","match":{"guid":"","name":"","vendor_id":"","product_id":""}}]
	for action in preset.actions:
		if action.id == "view_cycle": action.sources = [{"kind":"joy_button","slot":"stick","index":JOY_BUTTON_A}]
	var button_raw := {"keys":[],"mouse_buttons":[],"devices":[{"slot":"stick","generation":9,"axes":[],"buttons":[{"index":JOY_BUTTON_A,"pressed":false}]}]}
	mapper = _mapper(preset,_axes(),_axes(),button_raw)
	button_raw.devices[0].buttons = []
	_check(not mapper.sample(button_raw,0).ok,"observed_button_removal_rejects")
	button_raw.devices[0].buttons = [{"index":JOY_BUTTON_A,"pressed":true}]
	_check(mapper.sample(button_raw,0).actions == ["view_cycle"],"observed_button_rising_action")
	_check(mapper.sample(button_raw,0).actions.is_empty(),"observed_button_no_repeat")

func _save_failure_diagnostics() -> void:
	# Original closed transport examples, independent of any helper/process output.
	var safe: Dictionary = {"stage":"install","chain":[{"type":"System.IO.IOException","hresult":-2147024864.0}]}
	var marker: String = "PRESET_SAVE_FAILURE "
	var formatted: String = Preset._save_failure_diagnostic([marker+JSON.stringify(safe)])
	_check(formatted.begins_with(marker) and JSON.parse_string(formatted.trim_prefix(marker))==safe,"save_diagnostic_safe_fields_reconstructed")
	var failures: Array = [
		["missing",[]],
		["wrong_outer_type",[17]],
		["repeated_output",[marker+JSON.stringify(safe),marker+JSON.stringify(safe)]],
		["no_marker",[JSON.stringify(safe)]],
		["malformed",[marker+"{broken"]],
		["oversized",[marker+"x".repeat(4096)]],
		["extra_path",[marker+JSON.stringify({"stage":"install","chain":safe.chain,"path":"C:/private/profile"})]],
		["unknown_stage",[marker+JSON.stringify({"stage":"C:/private/target","chain":safe.chain})]],
		["null_chain",[marker+JSON.stringify({"stage":"install","chain":null})]],
		["empty_chain",[marker+JSON.stringify({"stage":"install","chain":[]})]],
		["too_many",[marker+JSON.stringify({"stage":"install","chain":safe.chain+safe.chain+safe.chain+safe.chain+safe.chain+safe.chain+safe.chain+safe.chain+safe.chain})]]]
	var boundary_chain: Array = []
	for i in range(8): boundary_chain.append({"type":"A".repeat(128),"hresult":0.0})
	var maximum: Dictionary = {"stage":"install","chain":boundary_chain}
	var maximum_result: String = Preset._save_failure_diagnostic([marker+JSON.stringify(maximum)])
	_check(maximum_result.begins_with(marker) and JSON.parse_string(maximum_result.trim_prefix(marker))==maximum,"save_diagnostic_exact_chain_type_bounds")
	failures.append(["nonfinite_hresult",[marker+'{"stage":"install","chain":[{"type":"System.IO.IOException","hresult":1e999}]}']])
	failures.append(["malformed_then_valid",[marker+'{"path":"private"}'+"\n"+marker+JSON.stringify(safe)]])
	for mutation in ["message","path_type","unicode_type","empty_type","long_type","string_hresult","bool_hresult","fraction_hresult","overflow_hresult","underflow_hresult","missing_hresult","entry_not_object"]:
		var bad: Dictionary = safe.duplicate(true)
		match mutation:
			"message": bad.chain[0].message="Private error message"
			"path_type": bad.chain[0].type="C:/private/target.tmp-123"
			"unicode_type": bad.chain[0].type="System.IO."+String.chr(233)
			"empty_type": bad.chain[0].type=""
			"long_type": bad.chain[0].type="A".repeat(129)
			"string_hresult": bad.chain[0].hresult="-2147024864"
			"bool_hresult": bad.chain[0].hresult=true
			"fraction_hresult": bad.chain[0].hresult=1.5
			"overflow_hresult": bad.chain[0].hresult=2147483648
			"underflow_hresult": bad.chain[0].hresult=-2147483649
			"missing_hresult": bad.chain[0].erase("hresult")
			"entry_not_object": bad.chain[0]="private"
		failures.append([mutation,[marker+JSON.stringify(bad)]])
	for row in failures:
		_check(Preset._save_failure_diagnostic(row[1])=="unavailable","save_diagnostic_rejects_"+row[0])
	for stage in ["canonical_source","canonical_target","drive","ancestor_guards","target_attributes","install"]:
		for hresult in [-2147483648,2147483647]:
			var boundary: Dictionary = {"stage":stage,"chain":[{"type":"A_1.+`","hresult":float(hresult)}]}
			var result: String = Preset._save_failure_diagnostic([marker+JSON.stringify(boundary)])
			_check(result.begins_with(marker) and JSON.parse_string(result.trim_prefix(marker))==boundary,"save_diagnostic_closed_stage_signed32_"+stage+"_"+str(hresult))

func _codec() -> void:
	_save_failure_diagnostics()
	var preset := _preset()
	var encoded: Dictionary = Preset.encode(preset)
	_check(encoded.ok and encoded.value is PackedByteArray,"codec_encode_valid")
	if not encoded.ok: return
	var decoded: Dictionary = Preset.decode(encoded.value)
	_check(decoded.ok and decoded.value == preset,"codec_actual_roundtrip")
	var valid_text: String = encoded.value.get_string_from_utf8()
	# Both duplicate mutants are otherwise complete valid presets. Ignoring the
	# duplicate key would accept them, so rejection exercises the scanner itself.
	var duplicate := ('{"type":"InputPreset",' + valid_text.substr(1)).to_utf8_buffer()
	var escaped_duplicate := ('{"ty\\u0070e":"InputPreset",' + valid_text.substr(1)).to_utf8_buffer()
	var malformed: Array = [encoded.value.slice(0,encoded.value.size()-2),PackedByteArray([0xff]),PackedByteArray([0xc0,0xaf]),(" ".repeat(65537)).to_utf8_buffer(),duplicate,escaped_duplicate,('['.repeat(9)+'0'+']'.repeat(9)).to_utf8_buffer()]
	for i in malformed.size(): _check(not Preset.decode(malformed[i]).ok,"codec_malformed_" + str(i))
	for duplicate_bytes in [duplicate,escaped_duplicate]:
		_check(Preset.decode(duplicate_bytes).error.contains("Duplicate"),"complete_duplicate_rejected_by_scanner")

	for mutation in ["unknown_version","extra_field","duplicate_axis","axis_nan","unbounded_index","runtime_serial","mixture_zero"]:
		var bad := preset.duplicate(true)
		match mutation:
			"unknown_version": bad.version = 2
			"extra_field": bad.filename = "arbitrary"
			"duplicate_axis": bad.axes[1] = bad.axes[0].duplicate(true)
			"axis_nan": bad.axes[0].gain = NAN
			"unbounded_index": _joy(bad,"roll",JOY_AXIS_MAX,{})
			"runtime_serial": bad.devices = [{"slot":"stick","label":"forbidden","match":{"guid":"","name":"","vendor_id":"","product_id":""},"serial":"private"}]
			"mixture_zero": _replace(bad,"mixture",{"target":"mixture","kind":"fixed","value":0.0})
		_check(not Preset.encode(bad).ok,"codec_encode_rejects_" + mutation)
	# Actual disposable selected paths: successful replacement and impossible-directory
	# replacement prove caller data preservation, without adding a production fault API.
	var directory := ProjectSettings.globalize_path("user://input-check-" + str(Time.get_ticks_usec()))
	_check(DirAccess.make_dir_recursive_absolute(directory) == OK,"codec_private_test_directory")
	var target := directory.path_join("selected.json")
	if OS.get_name() != "Windows":
		var original := FileAccess.open(target,FileAccess.WRITE)
		_check(original != null,"codec_unsupported_original_created")
		if original != null:
			original.store_string("UNSUPPORTED_ORIGINAL_KEEP")
			original.close()
		var unsupported: Dictionary = _trace_save("codec_unsupported_save",target,preset)
		_check(not unsupported.ok and not unsupported.error.is_empty(),"codec_unsupported_platform_explicit_rejection")
		_check(FileAccess.get_file_as_string(target)=="UNSUPPORTED_ORIGINAL_KEEP","codec_unsupported_platform_preserves_original")
		var retained := false
		for filename in DirAccess.get_files_at(directory):
			if filename.begins_with("selected.json.tmp-"): retained = true
		_check(retained,"codec_unsupported_platform_retains_temporary")
		file_evidence = {"scope":"explicit disposable selected path","platform":OS.get_name(),"atomic_save_qualified":false,"unsupported_rejected":not unsupported.ok,"original_preserved":FileAccess.get_file_as_string(target)=="UNSUPPORTED_ORIGINAL_KEEP","retained_test_directory":directory}
		return
	var saved: Dictionary = _trace_save("codec_selected_save",target,preset)
	_check(saved.ok,"codec_selected_save")
	var before := FileAccess.get_file_as_bytes(target)
	var next := preset.duplicate(true)
	next.name = "Original explicit replacement test"
	var replaced: Dictionary = _trace_save("codec_selected_replace",target,next)
	_check(replaced.ok,"codec_selected_replace_verifies_contents")
	var after := FileAccess.get_file_as_bytes(target)
	_check(after != before and Preset.decode(after).ok,"codec_replacement_verified_bytes")
	_check(Preset.decode(after).value.name == next.name,"codec_replacement_expected_contents")
	var blocked := directory.path_join("existing-directory")
	_check(DirAccess.make_dir_absolute(blocked) == OK,"codec_failure_target_directory")
	var marker := FileAccess.open(blocked.path_join("preserved-marker.txt"),FileAccess.WRITE)
	_check(marker != null,"codec_marker_open")
	if marker != null:
		marker.store_string("ORIGINAL_KEEP")
		marker.flush()
		marker.close()
	_check(not _trace_save("codec_directory_refusal",blocked,next).ok,"codec_replace_failure_reported")
	_check(DirAccess.dir_exists_absolute(blocked) and FileAccess.get_file_as_string(blocked.path_join("preserved-marker.txt")) == "ORIGINAL_KEEP","codec_replace_failure_preserves_target")
	_check(not _trace_save("codec_invalid_save",target,{"version":2}).ok,"codec_invalid_save_rejected")
	_check(FileAccess.get_file_as_bytes(target) == after,"codec_invalid_save_preserves_bytes")
	# Interrupted/corrupt import is exercised against real decode; applying that result
	# is deliberately never attempted and existing mapper state must remain unchanged.
	var mapper = _mapper(preset,_axes(),_axes(),_raw())
	var corrupt := after.slice(0,after.size()/2)
	_check(not Preset.decode(corrupt).ok,"codec_truncated_import_rejects")
	_near(mapper.sample(_raw([KEY_W]),200000).axes.throttle,0.05,"failed_import_existing_mapper_unmodified")
	var locked_result := _locked_replacement(target,next)
	file_evidence = {"scope":"unique explicitly selected disposable paths; no pilot settings","save_error":saved.error,"replacement_error":replaced.error,"save_replace_verified":replaced.ok and after != before and Preset.decode(after).ok,"replacement_failure_kind":"existing_directory_and_external_Windows_share_lock" if OS.get_name()=="Windows" else "existing_directory","locked_replacement":locked_result,"retained_test_directory":directory,"atomicity_limit":"Successful replacement and failures alone do not prove atomicity. Review the actual Windows replacement implementation separately; no power-loss durability or unsupported filesystem/hardware claim."}

func _locked_replacement(target: String, prior_preset: Dictionary) -> Dictionary:
	if OS.get_name() != "Windows": return {"tested":false,"reason":"Windows sharing fixture unavailable"}
	var ready := target + ".lock-ready"
	var release := target + ".lock-release"
	var done := target + ".lock-done"
	# Test-only child holds a real Windows share lock; paths derive only from this
	# run's generated disposable directory, and PS literal quoting remains exact.
	var target_ps := target.replace("'","''")
	var ready_ps := ready.replace("'","''")
	var release_ps := release.replace("'","''")
	var done_ps := done.replace("'","''")
	var script := "$ErrorActionPreference='Stop'; $parentProcess=[Diagnostics.Process]::GetProcessById(%d); $null=$parentProcess.Handle; $released=$false; $release='%s'; $heldFile=[IO.File]::Open('%s',[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read); try { if($parentProcess.HasExited){throw 'Fixture parent exited before READY'}; [IO.File]::WriteAllText('%s','LOCKED'); while(-not $released){ if($parentProcess.HasExited){throw 'Fixture parent exited before release'}; if([IO.File]::Exists($release)){if([IO.File]::ReadAllText($release) -cne 'RELEASE'){throw 'Invalid fixture release'}; $released=$true}else{[Threading.Thread]::Sleep(20)} } } finally { $heldFile.Dispose(); $parentProcess.Dispose(); $completion=if($released){'CLOSED'}else{'ABORTED'}; [IO.File]::WriteAllText('%s',$completion) }; [Environment]::Exit(0)" % [OS.get_process_id(),release_ps,target_ps,ready_ps,done_ps]
	# No wall-clock lease can release a held lock during a synchronous save.
	# The captured parent handle anchors liveness; only exact RELEASE permits CLOSED.
	# Parent death/invalid release closes the owned handle but cannot pass retirement.
	# Existing readiness/retirement deadlines and outer supervisor bound remain.
	# End only this owned fixture process after finally closes the handle and marker.
	# Environment.Exit is outside try/finally so cleanup always precedes exit:
	# https://learn.microsoft.com/en-us/dotnet/api/system.environment.exit
	var encoded := Marshalls.raw_to_base64(script.to_utf16_buffer())
	var executable := OS.get_environment("SystemRoot").path_join("System32/WindowsPowerShell/v1.0/powershell.exe")
	_trace("lock_create_before")
	var pid := OS.create_process(executable,PackedStringArray(["-NoProfile","-NonInteractive","-WindowStyle","Hidden","-EncodedCommand",encoded]),false)
	_trace("lock_create_after")
	_check(pid>0,"codec_external_lock_child_created")
	if pid<=0: return {"tested":false,"error":"Cannot create fixture child"}
	_trace("lock_ready_wait_before")
	var deadline := Time.get_ticks_msec()+5000
	while not FileAccess.file_exists(ready) and OS.is_process_running(pid) and Time.get_ticks_msec()<deadline:
		OS.delay_msec(20)
	_trace("lock_ready_wait_after")
	var locked := FileAccess.file_exists(ready) and OS.is_process_running(pid)
	_check(locked,"codec_external_share_lock_observed")
	var old_bytes := FileAccess.get_file_as_bytes(target)
	var temporary_before := DirAccess.get_files_at(target.get_base_dir())
	var rejected := false
	var preserved := false
	var retained := false
	var save_error: String = ""
	var held_through_save: bool = false
	if locked:
		var replacement := prior_preset.duplicate(true)
		replacement.name = "Must not replace externally locked original"
		var result: Dictionary = _trace_save("codec_locked_save",target,replacement)
		held_through_save = OS.is_process_running(pid) and not FileAccess.file_exists(done) and not FileAccess.file_exists(release)
		save_error = result.error
		rejected = not result.ok and not result.error.is_empty()
		preserved = FileAccess.get_file_as_bytes(target) == old_bytes
		var encoded_replacement: Dictionary = Preset.encode(replacement)
		for filename in DirAccess.get_files_at(target.get_base_dir()):
			if filename.begins_with(target.get_file()+".tmp-") and not filename in temporary_before:
				retained = retained or FileAccess.get_file_as_bytes(target.get_base_dir().path_join(filename)) == encoded_replacement.value
		_check(held_through_save,"codec_lock_remained_held_during_save")
		_check(rejected,"codec_share_locked_replace_reports_failure")
		_check(save_error.begins_with("Preset not saved:") and save_error.contains("original target preserved, temporary retained"),"codec_share_locked_error_clear_preservation")
		_check(save_error.length()<=4352,"codec_share_locked_error_bounded")
		_check(save_error.contains("helper_exit=2; helper_output=PRESET_SAVE_FAILURE "),"codec_share_locked_error_actual_helper_exit")
		var diagnostic_text: String = save_error.get_slice("helper_output=PRESET_SAVE_FAILURE ",1)
		var diagnostic: Variant = JSON.parse_string(diagnostic_text)
		var closed_diagnostic: bool = diagnostic is Dictionary and diagnostic.size()==2 and diagnostic.has("stage") and diagnostic.has("chain")
		_check(closed_diagnostic and diagnostic.get("stage")=="install","codec_share_locked_error_actual_install_stage")
		var chain_valid: bool = closed_diagnostic and diagnostic.get("chain") is Array and diagnostic.chain.size()>=1 and diagnostic.chain.size()<=8
		if chain_valid:
			for entry in diagnostic.chain:
				if not entry is Dictionary or entry.size()!=2 or not entry.has("type") or not entry.has("hresult"):
					chain_valid = false
					break
				if not entry.type is String or entry.type.is_empty() or entry.type.length()>128 or typeof(entry.hresult) not in [TYPE_INT,TYPE_FLOAT] or not is_finite(float(entry.hresult)) or floor(float(entry.hresult))!=float(entry.hresult) or entry.hresult < -2147483648 or entry.hresult > 2147483647:
					chain_valid = false
					break
				for i in entry.type.length():
					var code: int = entry.type.unicode_at(i)
					if not (code>=65 and code<=90 or code>=97 and code<=122 or code>=48 and code<=57 or code in [95,46,43,96]): chain_valid = false
		_check(chain_valid,"codec_share_locked_error_closed_type_hresult_chain")
		_check(not save_error.contains(target) and not save_error.contains(target.get_base_dir()) and not save_error.contains(target.get_base_dir().replace("/","\\")) and not save_error.contains(".tmp-"),"codec_share_locked_error_excludes_target_temporary_paths")
		_check(preserved,"codec_share_locked_original_bytes_preserved")
		_check(retained,"codec_share_locked_temporary_bytes_retained")
	_trace("lock_release_before")
	var held_before_release: bool = OS.is_process_running(pid) and not FileAccess.file_exists(done)
	# Publish only a complete closed signal; the child never reads this sibling pending file.
	var release_pending: String = release+".pending"
	var fresh_signal: bool = not FileAccess.file_exists(release) and not DirAccess.dir_exists_absolute(release) and not FileAccess.file_exists(release_pending) and not DirAccess.dir_exists_absolute(release_pending)
	var signal_file = FileAccess.open(release_pending,FileAccess.WRITE) if fresh_signal else null
	var signal_rename: int = ERR_CANT_CREATE
	if signal_file != null:
		signal_file.store_string("RELEASE")
		signal_file.flush()
		var signal_error: int = signal_file.get_error()
		signal_file.close()
		if signal_error==OK and not FileAccess.file_exists(release) and not DirAccess.dir_exists_absolute(release):
			signal_rename=DirAccess.rename_absolute(release_pending,release)
	var release_written := held_before_release and signal_rename==OK and FileAccess.file_exists(release) and FileAccess.get_file_as_string(release)=="RELEASE"
	_check(release_written,"codec_lock_release_signal_written")
	_trace("lock_release_after")
	_trace("lock_retirement_before")
	deadline = Time.get_ticks_msec()+5000
	while OS.is_process_running(pid) and Time.get_ticks_msec()<deadline:
		OS.delay_msec(20)
	var joined := not OS.is_process_running(pid)
	var close_marker := FileAccess.file_exists(done) and FileAccess.get_file_as_string(done)=="CLOSED"
	if not joined: OS.kill(pid) # Only the PID just created by this fixture; timeout still fails.
	_check(joined and close_marker,"codec_owned_lock_child_retired")
	_trace("lock_retirement_after")
	return {"tested":locked,"held_through_save":held_through_save,"held_before_release":held_before_release,"save_error":save_error,"rejected":rejected,"old_bytes_preserved":preserved,"temporary_retained":retained,"release_signal_written":release_written,"close_marker_observed":close_marker,"fixture_child_retired":joined}

func _run() -> Dictionary:
	_trace_enabled = OS.get_environment("FLIGHT_INPUT_PREFLIGHT_TRACE")=="1"
	_trace_started_usec = Time.get_ticks_usec()
	_trace("run_begin")
	var decoded = JSON.parse_string(FileAccess.get_file_as_string("res://input_tests/reference.json"))
	_check(decoded is Dictionary and decoded.get("case_count",0) == 38,"independent_reference_loaded")
	if not decoded is Dictionary: return {"passed":false,"checks":checks,"failures":failures}
	for row in decoded.cases: references[row.id] = row
	_check(JOY_AXIS_MAX > JOY_AXIS_LEFT_Y and JOY_BUTTON_MAX > 0,"actual_backend_enum_bounds")
	_trace("mapping_before")
	_mapping()
	_trace("mapping_after")
	_trace("digital_before")
	_digital()
	_trace("digital_after")
	_trace("latch_before")
	_latch()
	_trace("latch_after")
	_trace("lifecycle_before")
	_lifecycle()
	_trace("lifecycle_after")
	_trace("invalid_and_copies_before")
	_invalid_and_copies()
	_trace("invalid_and_copies_after")
	_trace("edges_and_failures_before")
	_edges_and_failures()
	_trace("edges_and_failures_after")
	_trace("codec_before")
	_codec()
	_trace("codec_after")
	_check(covered.size() == 38,"all_independent_cases_exercised")
	_trace("run_complete")
	return {"schema_version":1,"passed":failures.is_empty(),"checks":checks,"failures":failures,"analytic_reference_cases":covered.size(),"arithmetic_absolute_allowance":EPSILON,"runtime_constants":{"JOY_AXIS_MAX":JOY_AXIS_MAX,"JOY_BUTTON_MAX":JOY_BUTTON_MAX},"file_evidence":file_evidence,"scope":"Actual pure mapper/codec with synthetic copied readings; no physical device/native/GPU/human qualification. File evidence does not prove interrupted power-loss durability."}
