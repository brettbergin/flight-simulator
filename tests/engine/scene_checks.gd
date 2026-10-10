extends RefCounted
# Original MIT. Actual scene/native lifecycle with synthetic released Raw input.
# Synthetic panel/audio values are display-only and never enter the facade.
const Scene = preload("res://simulation/flight_scene.gd")
const Facade = preload("res://simulation/session_facade.gd")
const Mapper = preload("res://input/input_mapper.gd")
const EngineStatus = preload("res://cockpit/instruments/engine_status.gd")
const Panel = preload("res://interactive/flight_panel.gd")
const Sound = preload("res://interactive/flight_sound.gd")
const HISTORY: String="res://engine_tests/reference/minimal.fsreview.json"

class SyntheticScene extends Scene:
 var synthetic_raw: Dictionary={"keys":[],"mouse_buttons":[],"devices":[]}
 func collect_input_raw(_preset: Dictionary={}) -> Dictionary:
  return synthetic_raw.duplicate(true)

class CapturedPanel extends Panel:
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
  sound.playback.clear_buffer()
  host.check(sound.playback.get_frames_available()>0,"engine_scene_sound_zero_fixture_has_buffer_capacity")
  sound.phase=0.0
  sound.update_engine_audio(_display_status(0.0,true),0.0,false,true)
  sound._process(0.0)
  host.check(sound.phase==0.0,"engine_scene_sound_zero_shaft_has_no_frequency_floor_even_if_running")
  sound.playback.clear_buffer()
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
 host.check(cold.tick=="0" and cold.host_mode=="paused" and cold.paused and scene.menu_open,"engine_scene_profile_change_stays_at_tick_zero_until_explicit_resume")
 var cold_status: Dictionary=EngineStatus.from_readback(cold)
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
 host.check(scene.observed_status.state=="empty" and scene.observed_recorder.recording().samples.is_empty(),"engine_scene_cold_adoption_has_honest_empty_unsupported_recorder")
 scene.menu_open=false;scene.menu.hide()
 host.check(scene.pause_session(false),"engine_scene_cold_resume_is_explicit")
 scene.synthetic_raw.keys=[KEY_F12]
 scene.process_input_interval(8334)
 var cranking: Dictionary=scene.facade.readback()
 var crank_status: Dictionary=EngineStatus.from_readback(cranking)
 host.check(crank_status.readings["engine.starter"].value==true and cranking.tick!="0","engine_scene_live_momentary_starter_intent_reaches_actual_native_tick")
 host.check(scene.pause_session(true),"engine_scene_pause_with_held_starter_reaches_verified_boundary")
 var paused_crank: Dictionary=_capture(scene)
 host.check(scene.pending_systems.get("engine.starter")==false,"engine_scene_pause_clears_only_local_starter_intent")
 host.check(not scene.pause_session(false) and _capture(scene)==paused_crank,"engine_scene_held_starter_blocks_resume_without_native_mutation")
 scene.synthetic_raw.keys=[]
 host.check(scene.pause_session(false) and scene.advance_wall_us(8334) and scene.pause_session(true),"engine_scene_released_starter_can_resume_and_complete_release_tick")
 var released: Dictionary=EngineStatus.from_readback(scene.facade.readback())
 host.check(released.readings["engine.starter"].value==false,"engine_scene_facade_releases_native_starter_before_recovered_flight")
 host.check(scene.observed_status.state=="empty" and scene.observed_recorder.recording().samples.is_empty(),"engine_scene_cold_completed_ticks_do_not_emit_unsupported_legacy_recording")
 var retained: Dictionary=_capture(scene)
 host.check(scene.restart(true),"engine_scene_cold_reset_uses_fresh_executive")
 var reset: Dictionary=scene.facade.readback()
 host.check(reset.session_id!=retained.native.session_id and reset.tick=="0" and reset.host_mode=="paused" and scene.active_preset==piston,"engine_scene_cold_reset_is_paused_fresh_tick_zero_and_preserves_only_matching_guest_preset")
 var reset_status: Dictionary=EngineStatus.from_readback(reset)
 host.check(reset_status.readings["propeller.angular_speed"].value==0.0 and reset_status.readings["engine.running"].value==false and reset_status.readings["engine.starter"].value==false and reset.held_axes.mixture==0.0,"engine_scene_cold_reset_does_not_retain_warm_shaft_starter_or_mixture")
 scene.open_observed_review()
 host.check(scene.review_open and not scene.archive_imported and scene.observed_panel.get("_record").state=="empty" and scene.archive_message.contains("unavailable"),"engine_scene_cold_review_opens_honest_empty_unavailable_current_view")
 var review_before: Dictionary=_capture(scene)
 host.check(not scene.begin_archive_operation("save",false) and scene.archive_operation.is_empty() and _capture(scene)==review_before,"engine_scene_cold_current_save_blocked_without_native_or_record_mutation")
 host.check(FileAccess.file_exists(HISTORY),"engine_scene_explicit_legacy_history_fixture_staged")
 host.check(scene.begin_archive_operation("open",false),"engine_scene_cold_review_allows_explicit_historical_open")
 var opened: Dictionary=scene.finish_archive_operation(ProjectSettings.globalize_path(HISTORY))
 if OS.get_name()=="Windows":
  host.check(opened.ok and scene.archive_imported and scene.observed_panel.get("_record").metadata.model_identity==Facade.LEGACY_PROFILE,"engine_scene_opened_legacy_history_is_separate_display_only")
  host.check(not scene.begin_archive_operation("save",false) and scene.archive_imported and _capture(scene)==review_before,"engine_scene_viewing_legacy_history_cannot_enable_cold_current_save")
 else:
  host.check(not opened.ok and not scene.archive_imported and _capture(scene)==review_before,"engine_scene_nonWindows_archive_io_truthfully_unsupported_without_mutation")
 scene.show_current_review()
 host.check(not scene.archive_imported and scene.observed_panel.get("_record").state=="empty" and _capture(scene)==review_before,"engine_scene_current_returns_to_empty_cold_view_without_importing_history_into_recorder")
 scene.dismiss_observed_review()
 scene.choose_profile()
 var restored: Dictionary=scene.facade.readback()
 host.check(scene.selected_profile==Facade.LEGACY_PROFILE.id and restored.model_identity==Facade.LEGACY_PROFILE and restored.host_mode=="paused" and restored.tick=="0" and scene.active_preset==legacy,"engine_scene_switch_back_restores_legacy_guest_and_requires_explicit_resume")
 scene.choose_profile()
 var restored_cold: Dictionary=scene.facade.readback()
 host.check(scene.selected_profile==Facade.PISTON_PROFILE.id and restored_cold.host_mode=="paused" and restored_cold.tick=="0" and scene.active_preset==piston,"engine_scene_switch_back_to_piston_restores_only_matching_v2_guest")
 host.check(scene.close_session(),"engine_scene_actual_fixture_worker_joined")
 if scene.sound!=null: host.check(bool(await scene.sound.shutdown()),"engine_scene_actual_fixture_audio_retired")
 scene.free()
 var presentation: Dictionary=await _presentation(host)
 return {"scope":"Actual scene/native adoption and fixed short lifecycle; synthetic Raw and display fixtures, no pilot/physics/performance qualification","initialized":true,"legacy_initial_tick":before.native.tick,"cold_initial_tick":cold.tick,"cold_reset_tick":reset.tick,"presentation":presentation}
