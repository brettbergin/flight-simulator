extends RefCounted
# Original MIT. Synthetic ADR010 capability checks; no native/hardware access.
const Preset=preload("res://input/input_preset.gd")
const Mapper=preload("res://input/input_mapper.gd")
var _checks:int=0
var _failures:Array[String]=[]
func check(value:bool,label:String)->void:
 _checks+=1
 if not value:_failures.append(label)
static func axes(mixture:float=0.0)->Dictionary:
 return {"kind":"axes","roll":0.0,"pitch":0.0,"yaw":0.0,"throttle":0.0,"mixture":mixture,"left_brake":1.0,"right_brake":1.0,"trim":0.0}
static func systems()->Dictionary:
 return {"engine.ignition_left":false,"engine.ignition_right":false,"engine.starter":false,"fuel.feed":true}
static func raw(keys:Array=[],devices:Array=[])->Dictionary:
 return {"keys":keys.duplicate(true),"mouse_buttons":[],"devices":devices.duplicate(true)}
func _binding(preset:Dictionary,id:String)->Dictionary:
 for binding in preset.systems:
  if binding.id==id:return binding
 return {}
func _state(mapper:RefCounted)->Dictionary:
 return {"preset":mapper._preset.duplicate(true),"values":mapper._values.duplicate(true),"start":mapper._start.duplicate(true),"pins":mapper._pins.duplicate(true),"edges":mapper._edges.duplicate(true),"takeover":mapper._takeover.duplicate(true),"systems":mapper._system_intents.duplicate(true),"held":mapper._held_systems.duplicate(true),"system_edges":mapper._system_edges.duplicate(true),"live":mapper._live,"brake":mapper._brake_hold}
func run()->Dictionary:
 var preset:Dictionary=Mapper.default_preset_v2()
 check(Preset.validate_preset_v2(preset).ok,"default_v2_valid")
 check(not Preset.validate_preset(preset).ok,"v1_rejects_v2")
 check(not Preset.validate_preset_v2(Mapper.default_preset()).ok,"v2_rejects_v1")
 var encoded:Dictionary=Preset.encode_v2(preset)
 check(encoded.ok and Preset.decode_v2(encoded.value).value==preset,"v2_utf8_roundtrip")
 check(not Preset.decode_v2('{"version":2,"version":2}'.to_utf8_buffer()).ok,"v2_duplicate_json_keys")
 check(not Preset.decode_v2(PackedByteArray([0xc0,0xaf])).ok,"v2_invalid_utf8")
 check(not Preset.decode_v2(encoded.value.slice(0,encoded.value.size()-1)).ok,"v2_truncated_json")
 var directory:String=ProjectSettings.globalize_path("user://synthetic-piston-preset-"+str(OS.get_process_id())+"-"+str(Time.get_ticks_usec()))
 check(DirAccess.make_dir_recursive_absolute(directory)==OK,"unique_synthetic_interchange_directory")
 var path:String=directory.path_join("v2.json")
 var saved:Dictionary=Preset.save_v2(path,preset)
 if OS.get_name()=="Windows":
  check(saved.ok and Preset.decode_v2(FileAccess.get_file_as_bytes(path)).ok,"v2_explicit_windows_save_verified")
 else:check(not saved.ok,"v2_nonwindows_save_explicitly_unsupported")
 var legacy_path:String=directory.path_join("v1-preserve.json")
 var legacy_bytes:PackedByteArray=Preset.encode(Mapper.default_preset()).value
 var legacy_file=FileAccess.open(legacy_path,FileAccess.WRITE)
 if legacy_file!=null: legacy_file.store_buffer(legacy_bytes); legacy_file.close()
 check(legacy_file!=null,"synthetic_v1_target_written")
 var refused:Dictionary=Preset.save_v2(legacy_path,preset)
 check(not refused.ok and FileAccess.get_file_as_bytes(legacy_path)==legacy_bytes,"v2_export_preserves_existing_v1_bytes")
 var legacy_temporary:bool=false
 for name in DirAccess.get_files_at(directory):
  if name.begins_with("v1-preserve.json.tmp-"): legacy_temporary=true
 check(not legacy_temporary,"v1_preservation_before_temporary_creation")
 check(not Preset.save_v2("user://not-explicit.json",preset).ok,"v2_no_automatic_user_path")
 var draft:Dictionary=Preset.migrate_v1_draft(Mapper.default_preset()).value
 check(draft.version==2 and not Preset.validate_preset_v2(draft).ok,"migration_is_not_active")
 var mixture:Dictionary={}
 for axis in draft.axes:
  if axis.target=="mixture":mixture=axis
 check(mixture.kind=="fixed" and mixture.value==1.0 and draft.systems.all(func(b:Dictionary):return b.sources.is_empty()),"migration_exposes_full_rich_and_unbound")
 var mutations:Array=[]
 var bad:Dictionary=preset.duplicate(true);bad.profile.id="other";mutations.append(bad)
 bad=preset.duplicate(true);bad.capability_revision="other";mutations.append(bad)
 bad=preset.duplicate(true);bad.systems[0].kind="momentary";mutations.append(bad)
 bad=preset.duplicate(true);bad.systems[2].kind="toggle";mutations.append(bad)
 bad=preset.duplicate(true);bad.systems[0].sources=[];mutations.append(bad)
 bad=preset.duplicate(true);bad.systems[1].id=bad.systems[0].id;mutations.append(bad)
 bad=preset.duplicate(true);bad.systems[0].sources=[{"kind":"mouse_button","button":4}];mutations.append(bad)
 bad=preset.duplicate(true);bad.systems[0].sources=[{"kind":"physical_keys","keys":[KEY_W,KEY_F8]}];mutations.append(bad)
 bad=preset.duplicate(true);bad.systems[0].sources=[{"kind":"physical_keys","keys":[KEY_P]}];mutations.append(bad)
 bad=preset.duplicate(true);bad.systems[0].sources=[{"kind":"physical_keys","keys":[KEY_F12]}];mutations.append(bad)
 bad=preset.duplicate(true);bad.systems[0].sources=[{"kind":"physical_keys","keys":[KEY_ESCAPE]}];mutations.append(bad)
 bad=preset.duplicate(true);bad.systems[0].kind=StringName("toggle");mutations.append(bad)
 bad=preset.duplicate(true);bad.profile.id=StringName(bad.profile.id);mutations.append(bad)
 bad=preset.duplicate(true);bad.axes.append(bad.axes[0].duplicate(true));mutations.append(bad)
 bad=preset.duplicate(true);bad.systems.append(bad.systems[0].duplicate(true));mutations.append(bad)
 bad=preset.duplicate(true);bad.actions=[]
 for i in 65:bad.actions.append(preset.actions[0].duplicate(true))
 mutations.append(bad)
 bad=preset.duplicate(true);bad.actions[0].sources=[]
 for i in 5:bad.actions[0].sources.append(preset.actions[0].sources[0].duplicate(true))
 mutations.append(bad)
 for axis in preset.axes:
  if axis.target=="mixture":
   bad=preset.duplicate(true)
   for b in bad.axes:
    if b.target=="mixture":b.return_to_start=true
   mutations.append(bad)
 for i in mutations.size():check(not Preset.validate_preset_v2(mutations[i]).ok,"closed_v2_mutant_"+str(i))
 var mapper=Mapper.new()
 check(mapper.configure_v2(preset,axes(),axes(),raw(),Preset.PISTON_PROFILE,systems()).ok,"configure_cold_suspended")
 var sample:Dictionary=mapper.sample(raw([KEY_F12,KEY_F8,KEY_PERIOD]),0)
 check(sample.size()==7 and sample.keys().all(func(k:Variant):return typeof(k)==TYPE_STRING and k in ["ok","error","axes","actions","takeover","brake_hold","systems"]),"exact_seven_keys")
 check(sample.systems==systems() and sample.axes==axes() and sample.actions.is_empty(),"paused_no_starter_toggle_or_slew")
 var before:Dictionary=_state(mapper)
 check(not mapper.sample(raw(),1).ok and _state(mapper)==before,"paused_nonzero_rejected_atomic")
 check(not mapper.resume_confirmed(raw([KEY_F12])).ok and not mapper._live,"release_starter_before_resume")
 check(not mapper.resume_confirmed(raw([KEY_F8])).ok,"release_ignition_before_resume")
 check(not mapper.resume_confirmed(raw([KEY_F10])).ok,"release_feed_before_resume")
 check(mapper.resume_confirmed(raw()).ok,"released_resume")
 sample=mapper.sample(raw([KEY_PERIOD,KEY_F8,KEY_F12]),100000)
 check(absf(sample.axes.mixture-0.025)<1e-12 and sample.systems["engine.ignition_left"] and sample.systems["engine.starter"],"digital_mixture_crank_deliberate")
 check(sample.axes.left_brake==1.0 and sample.axes.right_brake==1.0 and sample.brake_hold,"initial_brake_hold")
 sample=mapper.sample(raw([KEY_F8,KEY_F12]),1000)
 check(sample.systems["engine.ignition_left"] and sample.systems["engine.starter"],"held_toggle_no_repeat")
 sample=mapper.sample(raw(),1000)
 check(not sample.systems["engine.starter"],"starter_release_false")
 sample=mapper.sample(raw([KEY_F8]),1000)
 check(not sample.systems["engine.ignition_left"],"second_rising_toggle")
 before=_state(mapper)
 var fail:Dictionary=mapper.sample({"keys":[KEY_F12],"mouse_buttons":[],"devices":[{}]},1000)
 check(not fail.ok and fail.axes==null and fail.systems==null and fail.actions.is_empty() and fail.takeover.is_empty() and fail.size()==7 and _state(mapper)==before,"bad_raw_no_partial_axis_system_mutation")
 var held:Dictionary=systems();held["engine.starter"]=true
 check(mapper.suspend_v2("focus",sample.axes,held).ok,"suspend_actual_starter_true")
 sample=mapper.sample(raw([KEY_F12]),0)
 check(sample.systems["engine.starter"] and not mapper._system_intents["engine.starter"],"held_true_truth_pending_false")
 check(mapper.resume_confirmed(raw()).ok and not mapper.sample(raw(),0).systems["engine.starter"],"first_live_false_replacement")
 var held_snapshot:Dictionary=mapper._held_systems.duplicate(true)
 var invalid_held:Dictionary=held.duplicate(true);invalid_held["engine.starter"]=1
 check(not mapper.suspend_v2("invalid",axes(),invalid_held).ok and not mapper._live and mapper._held_systems==held_snapshot,"bad_suspend_stays_suspended_preserves_diagnostics")
 before=_state(mapper)
 check(not mapper.configure_v2(preset,axes(),axes(),raw(),{},systems()).ok and _state(mapper)==before,"bad_configure_atomic")
 # OR aliases coalesce, and release/rearm checks every source, including observed buttons.
 var analog:Dictionary=preset.duplicate(true)
 analog.devices=[{"slot":"lever","label":"Synthetic lever","match":{"guid":"fixture","name":"fixture","vendor_id":"","product_id":""}}]
 for i in analog.axes.size():
  if analog.axes[i].target=="mixture":analog.axes[i]={"target":"mixture","kind":"joy_axis","slot":"lever","index":0,"range":"unsigned","minimum":-1.0,"center":0.0,"maximum":1.0,"invert":false,"deadzone":0.0,"saturation":1.0,"gain":1.0,"slew_per_s":0.0}
 _binding(analog,"engine.starter").sources.append({"kind":"joy_button","slot":"lever","index":2})
 _binding(analog,"engine.ignition_left").sources.append({"kind":"physical_keys","keys":[KEY_K]})
 var device:Dictionary={"slot":"lever","generation":4,"axes":[{"index":0,"value":1.0}],"buttons":[{"index":2,"pressed":false}]}
 var a=Mapper.new()
 check(a.configure_v2(analog,axes(0.4),axes(0.0),raw([], [device]),Preset.PISTON_PROFILE,systems()).ok,"analog_mixture_observed_configure")
 check(a.sample(raw([], [device]),0).takeover==["mixture"],"mixture_takeover_visible")
 check(a.resume_confirmed(raw([], [device])).ok,"absolute_mixture_not_center_gate")
 check(a.sample(raw([], [device]),1000).axes.mixture==0.4,"unmatched_mixture_held")
 device.axes[0].value=-0.2
 check(absf(a.sample(raw([], [device]),1000).axes.mixture-0.4)<1e-12 and not a._takeover.mixture,"mixture_takeover_matches")
 device.axes[0].value=0.0
 check(a.sample(raw([KEY_F8,KEY_K], [device]),1000).systems["engine.ignition_left"],"simultaneous_alias_single_toggle")
 check(a.sample(raw([KEY_K], [device]),1000).systems["engine.ignition_left"],"persistent_alias_blocks_repeat")
 a.sample(raw([], [device]),1000)
 check(not a.sample(raw([KEY_K], [device]),1000).systems["engine.ignition_left"],"all_alias_release_then_flip")
 before=_state(a);var absent:Dictionary=device.duplicate(true);absent.buttons=[]
 check(not a.sample(raw([], [absent]),1000).ok and _state(a)==before,"unobserved_engine_button_atomic")
 var changed:Dictionary=device.duplicate(true);changed.generation=5
 check(not a.sample(raw([], [changed]),1000).ok and _state(a)==before,"engine_connection_generation_pin")
 a.suspend_v2("disconnect",axes(0.4),held)
 device.buttons[0].pressed=true
 check(not a.resume_confirmed(raw([], [device])).ok,"joy_starter_released_gate")
 device.buttons[0].pressed=false
 check(a.resume_confirmed(raw([], [device])).ok,"joy_starter_rearmed")
 var copied:Dictionary=a.sample(raw([], [device]),0);copied.systems["fuel.feed"]=false;copied.axes.mixture=1.0
 check(a._system_intents["fuel.feed"] and a._values.mixture!=1.0,"owned_return_copies")
 return {"passed":_failures.is_empty(),"checks":_checks,"failures":_failures.duplicate()}
