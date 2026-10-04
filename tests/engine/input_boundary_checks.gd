extends RefCounted
# Independent ADR010 interaction cases; rational expectations and synthetic raw
# devices only. Does not load a native model or approve physical hardware.
const Mapper=preload("res://input/input_mapper.gd")
const Preset=preload("res://input/input_preset.gd")
const Facade=preload("res://simulation/session_facade.gd")
var checks: int=0
var failures: Array=[]
func check(ok: bool,label: String) -> void:
	checks+=1
	if not ok: failures.append(label)
func raw(keys: Array=[]) -> Dictionary:
	return {"keys":keys,"mouse_buttons":[],"devices":[]}
func axes() -> Dictionary:
	return {"kind":"axes","roll":0.0,"pitch":0.0,"yaw":0.0,"throttle":0.0,"mixture":0.0,"left_brake":1.0,"right_brake":1.0,"trim":0.0}
func run() -> Dictionary:
	var preset: Dictionary=Mapper.default_preset_v2()
	check(Preset.validate_preset_v2(preset).ok,"default_v2_valid")
	check(not Preset.validate_preset(preset).ok,"v1_cannot_silently_activate_v2")
	var old: Dictionary=Mapper.default_preset()
	check(not Preset.validate_preset_v2(old).ok,"v2_cannot_silently_activate_v1")
	var draft: Dictionary=Preset.migrate_v1_draft(old)
	check(draft.ok and draft.value.axes[5].target=="mixture" and draft.value.axes[5].value==1.0 and not Preset.validate_preset_v2(draft.value).ok,"migration_fullrich_unbound_not_active")
	var mapper: RefCounted=Mapper.new()
	var held: Dictionary=Facade.COLD_SYSTEMS.duplicate(true)
	held["engine.starter"]=true
	check(mapper.configure_v2(preset,axes(),axes(),raw(),Facade.PISTON_PROFILE,held).ok,"configure_verified_controls")
	var sample: Dictionary=mapper.sample(raw(),0)
	check(sample.keys().size()==7 and sample.systems["engine.starter"] and sample.axes.mixture==0.0 and sample.actions.is_empty(),"suspended_feedback_starter_true_mixture_cold")
	check(not mapper.resume_confirmed(raw([KEY_F12])).ok,"held_starter_blocks_resume")
	check(not mapper.resume_confirmed(raw([KEY_F8])).ok,"held_ignition_blocks_resume")
	check(mapper.resume_confirmed(raw()).ok,"released_explicit_resume")
	sample=mapper.sample(raw([KEY_PERIOD]),250000)
	check(sample.axes.mixture==0.0625 and not sample.systems["engine.starter"],"quarter_second_mixture_exact_no_automatic_crank")
	# Failed input must not consume an ignition edge or change mixture intent.
	var invalid_raw: Dictionary=raw([KEY_F8]);invalid_raw.keys.append(KEY_F8)
	var rejected: Dictionary=mapper.sample(invalid_raw,250000)
	check(not rejected.ok and rejected.axes==null and rejected.systems==null and rejected.actions.is_empty(),"invalid_raw_closed_failure")
	sample=mapper.sample(raw([KEY_F8]),0)
	check(sample.systems["engine.ignition_left"] and sample.axes.mixture==0.0625,"bad_sample_preserves_toggle_edge_and_mixture")
	sample=mapper.sample(raw([KEY_F8]),100000)
	check(sample.systems["engine.ignition_left"],"held_toggle_never_repeats")
	mapper.sample(raw(),0);sample=mapper.sample(raw([KEY_F8]),0)
	check(not sample.systems["engine.ignition_left"],"second_rising_edge_toggles_once")
	sample=mapper.sample(raw([KEY_F12]),0)
	check(sample.systems["engine.starter"],"momentary_starter_held")
	sample=mapper.sample(raw(),0)
	check(not sample.systems["engine.starter"],"momentary_release")
	check(mapper.suspend_v2("focus",axes(),held).ok,"suspend_valid_native_feedback")
	sample=mapper.sample(raw([KEY_F8]),0)
	check(sample.systems["engine.starter"] and not sample.systems["engine.ignition_left"],"paused_sample_no_guess_or_toggle")
	check(not mapper.sample(raw(),1).ok,"paused_elapsed_rejected")
	var bad_systems: Dictionary=held.duplicate(true);bad_systems["engine.starter"]=1
	check(not mapper.suspend_v2("bad feedback",axes(),bad_systems).ok,"invalid_feedback_suspend_rejects")
	check(mapper.sample(raw(),0).systems["engine.starter"],"invalid_feedback_preserves_diagnostic_truth")
	var conflict: Dictionary=preset.duplicate(true);conflict.systems[0].sources[0].keys=[KEY_W]
	check(not Preset.validate_preset_v2(conflict).ok,"engine_axis_physical_conflict")
	conflict=preset.duplicate(true);conflict.systems[0].sources=[{"kind":"physical_keys","keys":[KEY_F8,KEY_F9]}]
	check(not Preset.validate_preset_v2(conflict).ok,"overlapping_alias_conflict")
	conflict=preset.duplicate(true);conflict.systems[2].sources=[{"kind":"mouse_button","button":4}]
	check(not Preset.validate_preset_v2(conflict).ok,"wheel_cannot_latch_starter")
	conflict=preset.duplicate(true);conflict.systems[2].sources=[{"kind":"physical_keys","keys":[KEY_ESCAPE]}]
	check(not Preset.validate_preset_v2(conflict).ok,"escape_reserved")
	var encoded: Dictionary=Preset.encode_v2(preset)
	check(encoded.ok and Preset.decode_v2(encoded.value).ok,"explicit_v2_interchange")
	var text: String=encoded.value.get_string_from_utf8().replace('"capability_revision": "piston-controls-v1"','"capability_revision": "piston-controls-v1", "capability_revision": "piston-controls-v1"')
	check(not Preset.decode_v2(text.to_utf8_buffer()).ok,"duplicate_json_key_rejects")
	# One absolute unsigned mixture control: takeover retains native zero until
	# physically matched within the declared .03, then follows actual raw input.
	preset.devices=[{"slot":"knob","label":"Synthetic mixture fixture","match":{"guid":"","name":"","vendor_id":"","product_id":""}}]
	for i in preset.axes.size():
		if preset.axes[i].target=="mixture":
			preset.axes[i]={"target":"mixture","kind":"joy_axis","slot":"knob","index":0,"range":"unsigned","minimum":0.0,"center":0.0,"maximum":1.0,"invert":false,"deadzone":0.0,"saturation":1.0,"gain":1.0,"slew_per_s":0.0}
	var analog: Dictionary=raw();analog.devices=[{"slot":"knob","generation":1,"axes":[{"index":0,"value":0.8}],"buttons":[]}]
	mapper=Mapper.new()
	check(mapper.configure_v2(preset,axes(),axes(),analog,Facade.PISTON_PROFILE,Facade.COLD_SYSTEMS).ok and mapper.resume_confirmed(analog).ok,"observed_unsigned_mixture_configure")
	sample=mapper.sample(analog,100000)
	check(sample.axes.mixture==0.0 and "mixture" in sample.takeover,"analog_mixture_retains_native_until_matched")
	analog.devices[0].axes[0].value=0.02
	sample=mapper.sample(analog,100000)
	check(sample.axes.mixture==0.02 and not "mixture" in sample.takeover,"analog_mixture_takeover_within_three_percent")
	analog.devices[0].axes[0].value=0.6
	check(mapper.sample(analog,100000).axes.mixture==0.6,"matched_mixture_follows_real_raw")
	analog.devices[0].generation=2
	check(not mapper.sample(analog,100000).ok,"device_generation_requires_explicit_rearm")
	return {"passed":failures.is_empty(),"checks":checks,"failures":failures.duplicate(),"scope":"Independent rational input semantics on synthetic raw sources; hardware and native integration separate"}
