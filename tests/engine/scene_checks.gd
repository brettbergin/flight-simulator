extends RefCounted
# Original MIT. Actual scene/native lifecycle with synthetic released Raw input.
# Synthetic panel/audio values are display-only and never enter the facade.
const Scene = preload("res://simulation/flight_scene.gd")
const Facade = preload("res://simulation/session_facade.gd")
const Mapper = preload("res://input/input_mapper.gd")
const EngineStatus = preload("res://cockpit/instruments/engine_status.gd")
const FlightPanel = preload("res://interactive/flight_panel.gd")
const Sound = preload("res://interactive/flight_sound.gd")
const HISTORY: String="res://engine_tests/reference/minimal.fsreview.json"
const HISTORY_BYTES: int=3023
const HISTORY_SHA256: String="e830a36a899f216a44da263df16f59fc94611c7e44a3c610f3f968d0250965bf"

class SyntheticScene extends Scene:
 var synthetic_raw: Dictionary={"keys":[],"mouse_buttons":[],"devices":[]}
 func collect_input_raw(_preset: Dictionary={}) -> Dictionary:
  return synthetic_raw.duplicate(true)

class CapturedPanel extends FlightPanel:
 var text_calls: Array[String]=[]
 func _text(_at: Vector2,text: String,_pixels: float=14.0,_color: Color=INK,_centered: bool=false) -> void:
  text_calls.append(text)
 func _box(_rect: Rect2,_fill: Color,_border: Color=LINE,_radius: int=9) -> void:
  pass

func _has_drawn_text(rows: Array[String],fragment: String) -> bool:
 for row in rows:
  if row.contains(fragment): return true
 return false

func _check_starved_rows(host: Node,panel: Control,status: Dictionary,label: String,expected: String) -> void:
 panel.size=Vector2(960,540)
 panel.set_state({},{},{},{"engine_status":status})
 panel.text_calls.clear()
 panel.call("_draw_piston_strip")
 host.check(_has_drawn_text(panel.text_calls,"STARVED "+expected),"engine_scene_strip_draws_starved_"+label)
 panel.text_calls.clear()
 panel.call("_draw_engine",Rect2(24,190,220,310))
 host.check(_has_drawn_text(panel.text_calls,"STARVED "+expected),"engine_scene_engine_area_draws_starved_"+label)

func _capture(scene: Node) -> Dictionary:
 return {"native":scene.facade.readback().duplicate(true),"profile":scene.selected_profile,
  "start":scene.named_start,"wind":scene.current_wind_profile,"adopted":scene.adopted_session_id,
  "preset":scene.active_preset.duplicate(true),"presets":scene.profile_presets.duplicate(true),
  "record":scene.observed_recorder.recording(),"observed":scene.observed_status.duplicate(true),
  "controls":scene.controls.duplicate(true),"pending_systems":scene.pending_systems.duplicate(true),
  "look":scene.look_angles,"camera_mode":scene.camera_mode}

func _channel(value: Variant,unit: String,valid: bool=true) -> Dictionary:
 return {"value":value,"unit":unit,"valid":valid,"error":"" if valid else "Declared unavailable fixture"}

func _display_status(shaft: float,running: bool,starter: bool=false) -> Dictionary:
 return {"session_id":"synthetic.presentation.only","tick":"0","state":"live","native_truth":true,
  "error":"","readings":{"propeller.angular_speed":_channel(shaft,"radps"),
  "engine.running":_channel(running,"bool"),"engine.starter":_channel(starter,"bool"),
  "engine.starved":_channel(false,"bool")}}

func _presentation(host: Node) -> Dictionary:
 var panel: Control=CapturedPanel.new()
 var status: Dictionary=_display_status(0.0,false)
 for starved in [true,false]:
  status.readings["engine.starved"]=_channel(starved,"bool")
  panel.set_state({},{},{},{"engine_status":status})
  host.check(panel.call("_engine_switch","engine.starved")==("ON" if starved else "OFF"),"engine_scene_panel_starved_"+str(starved)+"_uses_native_bool")
  _check_starved_rows(host,panel,status,str(starved),"ON" if starved else "OFF")
 status.readings["engine.starved"]=_channel(null,"bool",false)
 panel.set_state({},{},{},{"engine_status":status})
 host.check(panel.call("_engine_switch","engine.starved")=="—","engine_scene_panel_starved_unavailable_is_not_false")
 _check_starved_rows(host,panel,status,"unavailable","—")
 status.readings["engine.starved"]=_channel(0,"bool")
 panel.set_state({},{},{},{"engine_status":status})
 host.check(panel.call("_engine_switch","engine.starved")=="—","engine_scene_panel_starved_integer_cannot_impersonate_native_bool")
 for shaft in [0.000000000001,0.2]:
  status=_display_status(shaft,false)
  panel.set_state({},{},{},{"engine_status":status})
  host.check(panel.call("_engine_phase")=="COASTING","engine_scene_panel_positive_shaft_coasts_"+str(shaft))
 for zero_index in 2:
  var shaft: float=[0.0,-0.0][zero_index]
  panel.set_state({},{},{},{"engine_status":_display_status(shaft,false)})
  host.check(panel.call("_engine_phase")=="STOPPED","engine_scene_panel_exact_zero_stops_"+str(zero_index))
 panel.set_state({},{},{},{"engine_status":_display_status(0.0,false,true)})
 host.check(panel.call("_engine_phase")=="CRANKING","engine_scene_panel_starter_is_distinct_from_combustion")
 panel.set_state({},{},{},{"engine_status":_display_status(10.0,true)})
 host.check(panel.call("_engine_phase")=="RUNNING","engine_scene_panel_running_follows_native_combustion")
 status=_display_status(1.0,false)
 status.readings["propeller.angular_speed"]=_channel(null,"radps",false)
 panel.set_state({},{},{},{"engine_status":status})
 host.check(panel.call("_engine_phase")=="UNAVAILABLE","engine_scene_panel_missing_shaft_does_not_guess_stopped")
 panel.free()

 var sound: Node=Sound.new()
 host.add_child(sound)
 sound.set_process(false)
 sound.update_audio(1.0,0.0,false,true)
 sound.update_engine_audio(_display_status(0.0,false),0.0,false,true)
 host.check(sound.native_engine and not sound.native_running and sound.native_shaft==0.0,"engine_scene_sound_full_throttle_cannot_invent_combustion_or_rotation")
 sound.update_engine_audio(_display_status(0.01,false),0.0,false,true)
 host.check(not sound.native_running and sound.native_shaft==0.01,"engine_scene_sound_positive_coast_remains_noncombustion")
 sound.update_engine_audio(_display_status(10.0,true),0.0,false,true)
 host.check(sound.native_running and sound.native_shaft==10.0,"engine_scene_sound_native_running_and_shaft_select_combustion_cue")
 status=_display_status(10.0,true)
 status.readings["propeller.angular_speed"]=_channel(null,"radps",false)
 sound.update_engine_audio(status,0.0,false,true)
 host.check(not sound.native_running and sound.native_shaft==0.0,"engine_scene_sound_missing_shaft_clears_prior_combustion_cue")
 # Exercise the production oscillator with its real generator. No audio samples
 # are read back; phase checks prove the absence of a minimum rotation pitch.
 host.check(sound.playback!=null,"engine_scene_sound_actual_generator_available")
 if sound.playback!=null:
  host.check(sound.playback.get_frames_available()>0,"engine_scene_sound_zero_fixture_has_buffer_capacity")
  sound.phase=0.0
  sound.update_engine_audio(_display_status(0.0,true),0.0,false,true)
  sound._process(0.0)
  host.check(sound.phase==0.0,"engine_scene_sound_zero_shaft_has_no_frequency_floor_even_if_running")
 # clear_buffer() rejects an active generator. The zero case fills its ring;
 # retire it and use a fresh real generator so tiny rotation processes samples.
 host.check(bool(await sound.shutdown()),"engine_scene_sound_zero_fixture_audio_retired")
 sound.free()
 sound=Sound.new()
 host.add_child(sound)
 sound.set_process(false)
 host.check(sound.playback!=null,"engine_scene_sound_tiny_actual_generator_available")
 if sound.playback!=null:
  host.check(sound.playback.get_frames_available()>0,"engine_scene_sound_tiny_fixture_has_buffer_capacity")
  sound.phase=0.0
  sound.update_engine_audio(_display_status(0.00000001,false),0.0,false,true)
  sound._process(0.0)
  host.check(sound.phase>0.0 and sound.phase<0.000001,"engine_scene_sound_tiny_positive_shaft_has_no_idle_frequency_floor")
  var phase_before_pause: float=sound.phase
  sound.update_engine_audio(_display_status(10.0,true),0.0,true,true)
  sound._process(0.0)
  host.check(sound.phase==phase_before_pause and sound.player.stream_paused,"engine_scene_sound_pause_freezes_cue_and_actual_player")
 sound.update_audio(0.25,0.0,true,true)
 host.check(not sound.native_engine and sound.throttle==0.25,"engine_scene_sound_legacy_throttle_route_remains_explicit")
 host.check(bool(await sound.shutdown()),"engine_scene_sound_fixture_audio_retired")
 sound.free()
 return {"scope":"Synthetic presentation inputs; real oscillator phase only, no calibrated sound or pixel qualification"}

func _retire_history_fixture(host: Node,path: String) -> void:
 # Only the single file and fresh directory created by this fixture; no recursion.
 if FileAccess.file_exists(path):
  host.check(DirAccess.remove_absolute(path)==OK,"engine_scene_history_fixture_file_retired")
 host.check(DirAccess.remove_absolute(path.get_base_dir())==OK,"engine_scene_history_fixture_directory_retired")

func _materialize_history_fixture(host: Node) -> String:
 # res:// is virtual inside a PCK. The production Open actor deliberately accepts
 # ordinary local files only, so materialize the exact public fixture outside the
 # payload rather than weakening its filesystem or privacy checks.
 var bytes: PackedByteArray=FileAccess.get_file_as_bytes(HISTORY)
 var pinned: bool=bytes.size()==HISTORY_BYTES and FileAccess.get_sha256(HISTORY)==HISTORY_SHA256
 host.check(pinned,"engine_scene_history_resource_matches_pinned_public_fixture")
 if not pinned: return ""
 var directory: String=ProjectSettings.globalize_path("user://").path_join("cold-scene-history-"+str(OS.get_process_id())+"-"+str(Time.get_ticks_usec()))
 var fresh: bool=not DirAccess.dir_exists_absolute(directory) and not FileAccess.file_exists(directory)
 host.check(fresh,"engine_scene_history_fixture_directory_is_fresh")
 if not fresh: return ""
 var created: bool=DirAccess.make_dir_absolute(directory)==OK
 host.check(created,"engine_scene_history_fixture_directory_created")
 if not created: return ""
 var path: String=directory.path_join("minimal.fsreview.json")
 var file: FileAccess=FileAccess.open(path,FileAccess.WRITE)
 host.check(file!=null,"engine_scene_history_fixture_file_created")
 if file==null:
  _retire_history_fixture(host,path)
  return ""
 var written: bool=file.store_buffer(bytes)
 file.flush()
 written=written and file.get_error()==OK
 file.close()
 var exact: bool=written and FileAccess.get_file_as_bytes(path)==bytes and FileAccess.get_sha256(path)==HISTORY_SHA256
 host.check(exact,"engine_scene_history_fixture_copy_is_byte_exact")
 if not exact:
  _retire_history_fixture(host,path)
  return ""
 return path

# Authored pure presentation inputs copied from the admitted cold baseline.
# These rates/ticks never enter a facade, native adapter or live flight.
func _propeller_source(base: Dictionary,tick: String,rate: Variant,elapsed: float) -> Dictionary:
 var source: Dictionary=base.duplicate(true)
 source.host_mode="live";source.historical=false;source.native_live=true;source.paused=false
 source.native_outcome="completed";source.tick=tick;source.aircraft.tick=tick;source.atmosphere.tick=tick
 source.aircraft.elapsed_s=elapsed
 for system in source.aircraft.systems:
  if system.id=="propeller.angular_speed": system.value=rate;system.validity="valid";system.quantity="radps"
  if system.id=="engine.running": system.value=false
 return source

func _propeller_reference(host: Node,base: Dictionary) -> void:
 var original: PackedByteArray=var_to_bytes(base)
 var seed: Dictionary=_propeller_source(base,"0",1.0,0.0)
 var current: Dictionary=Scene._next_propeller_phase({},seed)
 host.check(not current.is_empty() and current.angle==0.0,"propeller_reference_qualified_first_sample_seeds_local_zero")
 if current.is_empty(): return
 # Constant analytic angle = omega * simulated duration. Host sampling and
 # scales change sample boundaries, not the accepted tick clock.
 for scale in [0.25,0.5,1.0,2.0,4.0]:
  for hz in [30,60,144,240,0]:
   var phase: Dictionary=Scene._next_propeller_phase({},_propeller_source(base,"0",0.7,0.0))
   var wall: float=0.0
   var step_index: int=0
   var valid: bool=true
   while wall<1.0:
    var dt: float=1.0/float(hz) if hz>0 else [0.001,0.005,0.017,0.033,0.050][step_index%5]
    wall=minf(1.0,wall+dt);step_index+=1
    var ticks: int=int(floor(wall*scale*120.0+1e-9))
    phase=Scene._next_propeller_phase(phase,_propeller_source(base,str(ticks),0.7,float(ticks)/120.0))
    if phase.is_empty(): valid=false;break
   host.check(valid and absf(float(phase.get("angle",-1.0))-0.7*scale)<4e-12,"propeller_reference_constant_scale_"+str(scale)+"_hz_"+str(hz))
 # Linear omega(t)=2+3t has exact integral3.5 over [0,1]. A quadratic
 # omega(t)=1+2t^2 has exact integral5/3. Frozen coarse32-tick error budget
 # is0.022rad, with >3x refinement improvement per halved batch; this is a
 # presentation quadrature limit, never a shaft-physics tolerance.
 var errors: Array[float]=[]
 for batch in [32,16,8,1]:
  var linear: Dictionary=Scene._next_propeller_phase({},_propeller_source(base,"0",2.0,0.0))
  var quadratic: Dictionary=Scene._next_propeller_phase({},seed)
  var tick: int=0
  while tick<120:
   tick=mini(120,tick+batch)
   var t: float=float(tick)/120.0
   linear=Scene._next_propeller_phase(linear,_propeller_source(base,str(tick),2.0+3.0*t,t))
   quadratic=Scene._next_propeller_phase(quadratic,_propeller_source(base,str(tick),1.0+2.0*t*t,t))
  host.check(not linear.is_empty() and absf(float(linear.get("angle",-1.0))-3.5)<4e-12,"propeller_reference_linear_analytic_batch_"+str(batch))
  var error: float=absf(float(quadratic.get("angle",-1.0))-5.0/3.0)
  errors.append(error)
  host.check(not quadratic.is_empty() and error<=0.022,"propeller_reference_quadratic_frozen_budget_batch_"+str(batch))
 host.check(errors[1]<errors[0]/3.0 and errors[2]<errors[1]/3.0 and errors[3]<errors[2]/3.0,"propeller_reference_quadratic_independent_refinement")
 var prior: Dictionary=current.duplicate(true)
 var after: Dictionary=Scene._next_propeller_phase(current,_propeller_source(base,"32",1.0,32.0/120.0))
 host.check(not after.is_empty() and absf(after.angle-32.0/120.0)<1e-12 and current==prior,"propeller_reference_delta32_valid_aggregate_owned_copy")
 var spinning: Dictionary=Scene._next_propeller_phase({},_propeller_source(base,"0",100.0,0.0))
 spinning=Scene._next_propeller_phase(spinning,_propeller_source(base,"32",100.0,32.0/120.0))
 host.check(not spinning.is_empty() and absf(spinning.angle-(80.0/3.0-8.0*PI))<1e-12,"propeller_reference_multiple_turns_bounded_local_angle")
 var repeated: Dictionary=_propeller_source(base,"32",1.0,32.0/120.0)
 for paused in [false,true,false]:
  repeated.paused=paused;repeated.host_mode="paused" if paused else "live";repeated.native_outcome="paused" if paused else "completed"
  host.check(Scene._next_propeller_phase(after,repeated)==after,"propeller_reference_same_tick_pause_resume_no_angle_"+str(paused))
 var zero: Dictionary=Scene._next_propeller_phase({},_propeller_source(base,"0",0.0,0.0))
 var stopped: Dictionary=Scene._next_propeller_phase(zero,_propeller_source(base,"1",0.0,1.0/120.0))
 host.check(not stopped.is_empty() and stopped.angle==0.0,"propeller_reference_exact_zero_has_no_floor")
 var tiny: Dictionary=Scene._next_propeller_phase({},_propeller_source(base,"0",1e-12,0.0))
 tiny=Scene._next_propeller_phase(tiny,_propeller_source(base,"1",1e-12,1.0/120.0))
 host.check(not tiny.is_empty() and tiny.angle>0.0 and tiny.angle<1e-12,"propeller_reference_tiny_noncombustion_coast_moves")
 for tick in ["65","0"]:
  var rebased: Dictionary=Scene._next_propeller_phase(after,_propeller_source(base,tick,1.0,float(int(tick))/120.0))
  host.check(not rebased.is_empty() and rebased.angle==0.0 and rebased.tick==tick,"propeller_reference_gap_or_backwards_seeds_"+tick)
 for field in ["session_id","native_source_fingerprint"]:
  var changed: Dictionary=_propeller_source(base,"33",1.0,33.0/120.0)
  if field=="session_id":
   changed.session_id="authored.phase.second";changed.aircraft.session_id=changed.session_id;changed.atmosphere.session_id=changed.session_id
  else: changed.native_source_fingerprint="a".repeat(64) if base.native_source_fingerprint!="a".repeat(64) else "b".repeat(64)
  var reset: Dictionary=Scene._next_propeller_phase(after,changed)
  host.check(not reset.is_empty() and reset.angle==0.0,"propeller_reference_complete_identity_reset_"+field)
 var invalid_anchor: Dictionary=_propeller_source(base,"33",1.0,33.0/120.0)
 invalid_anchor.world_anchor.latitude_rad+=0.000001
 host.check(Scene._next_propeller_phase(after,invalid_anchor).is_empty(),"propeller_reference_unqualified_anchor_clears_not_new_world")
 # Supplied large elapsed value is only wire fixture data; the estimator uses
 # U64's checked32-tick difference across the unsigned maximum, not that float.
 var high: Dictionary=Scene._next_propeller_phase({},_propeller_source(base,"18446744073709551583",1.0,153722867280912930.0))
 high=Scene._next_propeller_phase(high,_propeller_source(base,"18446744073709551615",1.0,153722867280912930.0))
 host.check(not high.is_empty() and absf(float(high.get("angle",-1.0))-32.0/120.0)<1e-12,"propeller_reference_uint64_max_small_difference")
 for invalid in [-1.0,INF,NAN,true,"1"]:
  host.check(Scene._next_propeller_phase(after,_propeller_source(base,"33",invalid,33.0/120.0)).is_empty(),"propeller_reference_invalid_rate_"+str(invalid))
 for unavailable in ["missing","wrong_unit","invalid"]:
  var bad_channel: Dictionary=_propeller_source(base,"33",1.0,33.0/120.0)
  for i in range(bad_channel.aircraft.systems.size()-1,-1,-1):
   if bad_channel.aircraft.systems[i].id!="propeller.angular_speed": continue
   if unavailable=="missing": bad_channel.aircraft.systems.remove_at(i)
   elif unavailable=="wrong_unit": bad_channel.aircraft.systems[i].quantity="rpm"
   else: bad_channel.aircraft.systems[i].validity="unavailable"
  host.check(Scene._next_propeller_phase(after,bad_channel).is_empty(),"propeller_reference_unavailable_channel_"+unavailable)
 for token in ["01","-1","18446744073709551616"]:
  host.check(Scene._next_propeller_phase(after,_propeller_source(base,token,1.0,0.0)).is_empty(),"propeller_reference_invalid_tick_"+token)
 var huge: Dictionary=Scene._next_propeller_phase({},_propeller_source(base,"0",1.7976931348623157e308,0.0))
 host.check(not huge.is_empty() and Scene._next_propeller_phase(huge,_propeller_source(base,"1",1.7976931348623157e308,1.0/120.0)).is_empty(),"propeller_reference_finite_endpoint_sum_overflow_clears")
 for mode in ["stalled","closed","coverage_blocked","discarded"]:
  var terminal: Dictionary=_propeller_source(base,"33",1.0,33.0/120.0)
  terminal.host_mode=mode;terminal.historical=true;terminal.native_live=false;terminal.paused=false;terminal.debt_quanta=0
  terminal.native_outcome="discarded" if mode in ["closed","discarded"] else ("coverage_blocked" if mode=="coverage_blocked" else "paused")
  host.check(Scene._next_propeller_phase(after,terminal).is_empty(),"propeller_reference_terminal_clears_"+mode)
 host.check(Scene._next_propeller_phase(after,{}).is_empty() and var_to_bytes(base)==original,"propeller_reference_empty_clears_and_actual_baseline_unchanged")
 print("PROPELLER_REFERENCE ",JSON.stringify({"scope":"Authored pure rates/ticks over copied admitted source, never native flight","quadratic_batches":[32,16,8,1],"quadratic_absolute_error_rad":errors,"coarse_budget_rad":0.022,"linear_rounding_budget_rad":4e-12}))


# Actual-native checks below use only the existing scheduled lifecycle. Unlike
# the authored pure references, these bind the installed adoption hook to each
# actual qualified source, without calling the estimator from the assertion.
func _actual_propeller_cache_matches(scene: Node,source: Dictionary) -> bool:
 var phase: Dictionary=scene._propeller_phase
 if phase.is_empty(): return false
 var status: Dictionary=EngineStatus.from_readback(source)
 if status.state not in ["live","paused"]: return false
 var channel: Dictionary=status.readings["propeller.angular_speed"]
 if not channel.valid: return false
 var identity: Dictionary={"session_id":source.session_id,"model_identity":source.model_identity,
  "native_source_fingerprint":source.native_source_fingerprint,"prepared_world_sha256":source.prepared_world_sha256,
  "world_anchor":source.world_anchor,"named_start":source.named_start,"clock":source.aircraft.clock}
 return phase.get("identity")==identity and phase.get("tick")==source.tick and phase.get("rate")==channel.value and phase.get("source_elapsed_s")==source.aircraft.elapsed_s

func run(host: Node) -> Dictionary:
 var scene: Node=SyntheticScene.new()
 host.add_child(scene)
 scene.set_process(false)
 if scene.sound!=null: scene.sound.set_process(false)
 host.check(scene.facade!=null and scene.facade.readback().aircraft!=null,"engine_scene_actual_initial_legacy_publication")
 if scene.facade==null or scene.facade.readback().aircraft==null:
  if scene.sound!=null: host.check(bool(await scene.sound.shutdown()),"engine_scene_failed_initial_audio_retired")
  scene.free()
  return {"initialized":false,"scope":"Required actual scene initialization failed"}
 var legacy: Dictionary=Mapper.default_preset()
 legacy.name="Independent legacy guest fixture"
 scene.apply_controls(legacy)
 host.check(scene.active_preset==legacy,"engine_scene_legacy_guest_preset_accepted")
 scene.menu_open=false;scene.menu.hide()
 host.check(scene.pause_session(false) and scene.advance_wall_us(8334) and scene.pause_session(true),"engine_scene_legacy_observation_advanced_and_paused")
 host.check(scene.recorded_flight_advanced(),"engine_scene_legacy_record_requires_explicit_discard")
 var before: Dictionary=_capture(scene)
 scene.choose_profile()
 host.check(scene.pending_discard.get("profile_id")==Facade.PISTON_PROFILE.id and scene.pending_discard.get("start")=="piston-cold-ground" and scene.pending_discard.get("wind_profile")=="calm","engine_scene_cold_selection_is_explicit_paused_draft")
 host.check(_capture(scene)==before,"engine_scene_unconfirmed_profile_draft_preserves_adopted_flight_preset_and_history")
 scene.cancel_discard()
 host.check(scene.pending_discard.is_empty() and _capture(scene)==before,"engine_scene_cancel_profile_keeps_complete_old_flight")
 host.check(not scene.restart(true,"from-west","original-piston-prop-v1","piston-cold-ground") and _capture(scene)==before,"engine_scene_invalid_profile_wind_rejected_before_old_worker_destruction")
 scene.choose_profile()
 scene.confirm_discard()
 scene.set_process(false)
 var cold: Dictionary=scene.facade.readback()
 host.check(cold.model_identity==Facade.PISTON_PROFILE and scene.selected_profile==Facade.PISTON_PROFILE.id and scene.adopted_session_id==cold.session_id and cold.session_id!=before.native.session_id,"engine_scene_successful_cold_adoption_commits_verified_profile_and_new_session")
 if cold.model_identity!=Facade.PISTON_PROFILE or cold.aircraft==null:
  host.check(scene.close_session(),"engine_scene_failed_cold_adoption_worker_joined")
  if scene.sound!=null: host.check(bool(await scene.sound.shutdown()),"engine_scene_failed_cold_adoption_audio_retired")
  scene.free()
  return {"initialized":false,"scope":"Required actual cold adoption failed"}
 _propeller_reference(host,cold)
 host.check(cold.tick=="0" and cold.host_mode=="paused" and cold.paused and scene.menu_open,"engine_scene_profile_change_stays_at_tick_zero_until_explicit_resume")
 var cold_status: Dictionary=EngineStatus.from_readback(cold)
 var actual_cold_phase: Dictionary=scene._propeller_phase.duplicate(true)
 host.check(_actual_propeller_cache_matches(scene,cold) and scene._propeller_phase.get("rate")==0.0 and scene._propeller_phase.get("angle")==0.0,"propeller_actual_cold_adoption_seeds_identity_tick_zero_rate_angle")
 host.check(cold_status.state=="paused" and cold_status.readings["propeller.angular_speed"].value==0.0 and cold_status.readings["engine.running"].value==false and cold.held_axes.mixture==0.0,"engine_scene_cold_native_zero_shaft_no_combustion_and_cutoff_mixture")
 host.check(cold_status.readings["engine.ignition_left"].value==false and cold_status.readings["engine.ignition_right"].value==false and cold_status.readings["engine.starter"].value==false and cold_status.readings["fuel.feed"].value==true,"engine_scene_cold_tick_zero_has_exact_authored_four_switches")
 host.check(scene.active_preset.version==2 and scene.active_preset.profile==Facade.PISTON_PROFILE and scene.active_preset!=legacy and scene.profile_presets[Facade.LEGACY_PROFILE.id]==legacy,"engine_scene_new_profile_uses_explicit_v2_default_and_retains_separate_legacy_guest")
 var piston: Dictionary=scene.active_preset.duplicate(true)
 piston.name="Independent piston guest fixture"
 scene.apply_controls(piston)
 host.check(scene.active_preset==piston,"engine_scene_piston_guest_preset_accepted")
 var cold_before: Dictionary=_capture(scene)
 scene.apply_controls(legacy)
 host.check(_capture(scene)==cold_before,"engine_scene_legacy_preset_cannot_silently_activate_in_piston_profile")
 var cold_record: Dictionary=scene.observed_recorder.recording()
 host.check(scene.observed_status.contract_version==2 and cold_record.contract_version==2 and cold_record.samples.size()==1 and cold_record.samples[0].engine_status==cold_status,"engine_scene_cold_adoption_records_qualified_same_readback_engine_sample")
 scene.menu_open=false;scene.menu.hide()
 host.check(scene.pause_session(false),"engine_scene_cold_resume_is_explicit")
 host.check(scene._propeller_phase==actual_cold_phase,"propeller_actual_resume_ack_without_completed_ticks_preserves_cache")
 scene.synthetic_raw.keys=[KEY_F12]
 scene.process_input_interval(8334)
 var cranking: Dictionary=scene.facade.readback()
 var crank_status: Dictionary=EngineStatus.from_readback(cranking)
 host.check(crank_status.readings["engine.starter"].value==true and cranking.tick!="0","engine_scene_live_momentary_starter_intent_reaches_actual_native_tick")
 var actual_crank_phase: Dictionary=scene._propeller_phase.duplicate(true)
 var actual_crank_rate: Variant=crank_status.readings["propeller.angular_speed"].value
 var one_tick_angle: float=float(actual_crank_rate)/240.0 if actual_crank_rate is float else -1.0
 host.check(cranking.tick=="1" and actual_crank_rate is float and actual_crank_rate>0.0 and _actual_propeller_cache_matches(scene,cranking) and absf(float(actual_crank_phase.get("angle",-1.0))-one_tick_angle)<1e-12,"propeller_actual_one_tick_cranking_matches_independent_zero_endpoint_trapezoid")
 var passive_capture: Dictionary=_capture(scene)
 var passive_counts: Array=[scene.submitted_count,scene.event_count]
 for draw_index in 2:
  scene.show_state(0.125)
  host.check(scene._propeller_phase==actual_crank_phase and _capture(scene)==passive_capture and [scene.submitted_count,scene.event_count]==passive_counts,"propeller_actual_positive_duration_passive_draw_preserves_cache_and_authority_"+str(draw_index))
  # The cached angle is binary64; Node3D's Euler transform uses engine real_t.
  # This fixed float32 draw budget is not a native/shaft-physics tolerance.
  host.check(scene.propeller!=null and not actual_crank_phase.is_empty() and absf(wrapf(float(scene.propeller.rotation.z)-float(actual_crank_phase.get("angle",-1.0)),-PI,PI))<=8.0*1.1920928955078125e-7,"propeller_actual_draw_assigns_cached_angle_"+str(draw_index))
 host.check(scene.pause_session(true),"engine_scene_pause_with_held_starter_reaches_verified_boundary")
 host.check(scene._propeller_phase==actual_crank_phase and _actual_propeller_cache_matches(scene,scene.facade.readback()),"propeller_actual_pause_ack_same_tick_preserves_cache")
 var paused_crank: Dictionary=_capture(scene)
 host.check(scene.pending_systems.get("engine.starter")==false,"engine_scene_pause_clears_only_local_starter_intent")
 host.check(not scene.pause_session(false) and _capture(scene)==paused_crank,"engine_scene_held_starter_blocks_resume_without_native_mutation")
 host.check(scene._propeller_phase==actual_crank_phase,"propeller_actual_blocked_resume_preserves_cache")
 scene.synthetic_raw.keys=[]
 host.check(scene.pause_session(false) and scene.advance_wall_us(8334) and scene.pause_session(true),"engine_scene_released_starter_can_resume_and_complete_release_tick")
 var released: Dictionary=EngineStatus.from_readback(scene.facade.readback())
 host.check(released.readings["engine.starter"].value==false,"engine_scene_facade_releases_native_starter_before_recovered_flight")
 host.check(scene.observed_status.contract_version==2 and scene.observed_status.state=="recording" and scene.observed_status.last_observed_tick==scene.facade.readback().tick,"engine_scene_cold_completed_ticks_advance_version2_endpoint")
 var retained: Dictionary=_capture(scene)
 host.check(scene.restart(true),"engine_scene_cold_reset_uses_fresh_executive")
 var reset: Dictionary=scene.facade.readback()
 host.check(reset.session_id!=retained.native.session_id and reset.tick=="0" and reset.host_mode=="paused" and scene.active_preset==piston,"engine_scene_cold_reset_is_paused_fresh_tick_zero_and_preserves_only_matching_guest_preset")
 var reset_status: Dictionary=EngineStatus.from_readback(reset)
 host.check(_actual_propeller_cache_matches(scene,reset) and scene._propeller_phase.get("angle")==0.0 and scene._propeller_phase.get("rate")==0.0 and scene._propeller_phase.get("identity",{}).get("session_id")!=actual_crank_phase.get("identity",{}).get("session_id"),"propeller_actual_fresh_reset_seeds_new_identity_zero_angle")
 host.check(reset_status.readings["propeller.angular_speed"].value==0.0 and reset_status.readings["engine.running"].value==false and reset_status.readings["engine.starter"].value==false and reset.held_axes.mixture==0.0,"engine_scene_cold_reset_does_not_retain_warm_shaft_starter_or_mixture")
 scene.open_observed_review()
 host.check(scene.review_open and not scene.archive_imported and scene.observed_panel.get("_record").contract_version==2 and scene.observed_panel.get("_record").samples.size()==1,"engine_scene_cold_review_opens_current_version2_sample")
 var review_before: Dictionary=_capture(scene)
 host.check(scene.begin_archive_operation("save",false) and not scene.archive_operation.bytes.is_empty(),"engine_scene_cold_current_save_admits_qualified_version2")
 scene.cancel_archive_operation()
 host.check(scene.archive_operation.is_empty() and _capture(scene)==review_before,"engine_scene_cold_save_cancel_preserves_native_and_current_record")
 host.check(FileAccess.file_exists(HISTORY),"engine_scene_explicit_legacy_history_fixture_staged")
 var history_path: String=_materialize_history_fixture(host)
 host.check(scene.begin_archive_operation("open",false),"engine_scene_cold_review_allows_explicit_historical_open")
 var opened: Dictionary=scene.finish_archive_operation(history_path)
 if OS.get_name()=="Windows":
  host.check(opened.ok and scene.archive_imported and scene.observed_panel.get("_record").metadata.model_identity==Facade.LEGACY_PROFILE,"engine_scene_opened_legacy_history_is_separate_display_only")
  host.check(scene.begin_archive_operation("save",false) and scene.archive_imported,"engine_scene_viewing_legacy_history_can_save_separate_current_cold_record")
  scene.cancel_archive_operation()
  host.check(_capture(scene)==review_before,"engine_scene_imported_save_cancel_preserves_current_cold_record")
 else:
  host.check(not opened.ok and not scene.archive_imported and _capture(scene)==review_before,"engine_scene_nonWindows_archive_io_truthfully_unsupported_without_mutation")
 if not history_path.is_empty(): _retire_history_fixture(host,history_path)
 scene.show_current_review()
 host.check(not scene.archive_imported and scene.observed_panel.get("_record")==review_before.record and _capture(scene)==review_before,"engine_scene_current_restores_cold_record_without_importing_history_into_recorder")
 scene.dismiss_observed_review()
 scene.choose_profile()
 var restored: Dictionary=scene.facade.readback()
 host.check(scene.selected_profile==Facade.LEGACY_PROFILE.id and restored.model_identity==Facade.LEGACY_PROFILE and restored.host_mode=="paused" and restored.tick=="0" and scene.active_preset==legacy,"engine_scene_switch_back_restores_legacy_guest_and_requires_explicit_resume")
 scene.choose_profile()
 var restored_cold: Dictionary=scene.facade.readback()
 host.check(scene.selected_profile==Facade.PISTON_PROFILE.id and restored_cold.host_mode=="paused" and restored_cold.tick=="0" and scene.active_preset==piston,"engine_scene_switch_back_to_piston_restores_only_matching_v2_guest")
 host.check(_actual_propeller_cache_matches(scene,restored_cold) and not scene._propeller_phase.is_empty(),"propeller_actual_preclose_requires_nonempty_adopted_cache")
 host.check(scene.close_session(),"engine_scene_actual_fixture_worker_joined")
 host.check(scene._propeller_phase.is_empty(),"engine_scene_successful_close_clears_propeller_history")
 if scene.sound!=null: host.check(bool(await scene.sound.shutdown()),"engine_scene_actual_fixture_audio_retired")
 scene.free()
 var presentation: Dictionary=await _presentation(host)
 var observed_review: Dictionary=await load("res://observed_tests/piston_scene_checks.gd").new().run(host)
 host.check(observed_review.get("passed")==true and typeof(observed_review.get("checks"))==TYPE_INT and observed_review.checks>0 and observed_review.get("failures") is Array and observed_review.failures.is_empty(),"engine_scene_actual_observed_review_checks_required")
 return {"scope":"Actual scene/native adoption and fixed short lifecycle; synthetic Raw and display fixtures, no pilot/physics/performance qualification","initialized":true,"legacy_initial_tick":before.native.tick,"cold_initial_tick":cold.tick,"cold_reset_tick":reset.tick,"presentation":presentation,"observed_review":observed_review}
