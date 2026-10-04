extends RefCounted
# Original MIT. Actual production scene/facade with explicitly synthetic Raw
# readings. No OS input injection, controller polling, device/human qualification.
const Scene = preload("res://simulation/flight_scene.gd")
const Mapper = preload("res://input/input_mapper.gd")
class SyntheticScene extends Scene:
 var synthetic_raw: Dictionary = {"keys":[],"mouse_buttons":[],"devices":[]}
 func collect_input_raw(_preset: Dictionary = {}) -> Dictionary:
  return synthetic_raw.duplicate(true)

func _hide_menu(scene: Node) -> void:
 scene.menu_open=false
 scene.menu.hide()
 if scene.controls_panel!=null: scene.controls_panel.hide()

func _preserved(before: Dictionary, after: Dictionary) -> bool:
 return before.tick==after.tick and before.aircraft==after.aircraft and before.atmosphere==after.atmosphere and before.held_axes==after.held_axes

func _device_raw(generation: int, value: float = 0.0) -> Dictionary:
 return {"keys":[],"mouse_buttons":[],"devices":[{"slot":"test_stick","generation":generation,"axes":[{"index":JOY_AXIS_LEFT_X,"value":value}],"buttons":[]}]}

func _device_preset() -> Dictionary:
 var preset: Dictionary=Mapper.default_preset()
 preset.devices=[{"slot":"test_stick","label":"Declared synthetic sparse stick","match":{"guid":"","name":"","vendor_id":"","product_id":""}}]
 for i in preset.axes.size():
  if preset.axes[i].target=="yaw":
   preset.axes[i]={"target":"yaw","kind":"joy_axis","slot":"test_stick","index":JOY_AXIS_LEFT_X,"range":"centered","minimum":-1.0,"center":0.0,"maximum":1.0,"invert":false,"deadzone":0.0,"saturation":1.0,"gain":1.0,"slew_per_s":0.0}
 return preset

func run(host: Node) -> Dictionary:
 var scene: Node=SyntheticScene.new()
 host.add_child(scene)
 scene.set_process(false)
 host.check(scene.facade!=null and scene.mapper!=null and scene.facade.readback().host_mode=="paused","input_scene_actual_fresh_native_and_mapper_start_paused")
 if scene.facade==null or scene.mapper==null or scene.facade.readback().aircraft==null:
  if scene.sound!=null: await scene.sound.call("shutdown")
  scene.free()
  return {"passed":false,"scope":"Initialization unavailable; no synthetic input qualification"}
 var first: Dictionary=scene.facade.readback()
 host.check(scene.mapper.sample(scene.synthetic_raw,0).brake_hold,"input_scene_actual_ground_start_seeds_brake_hold")
 host.check(scene.pause_session(false),"input_scene_actual_explicit_keyboard_resume")
 _hide_menu(scene)
 scene.synthetic_raw.keys=[KEY_W]
 scene.process_input_interval(25000)
 var flying: Dictionary=scene.facade.readback()
 host.check(flying.tick=="3" and flying.host_mode=="live" and flying.held_axes.throttle>first.held_axes.throttle,"input_scene_actual_mapper_command_reaches_three_native_ticks")
 host.check(flying.held_axes.left_brake==1.0 and flying.held_axes.right_brake==1.0,"input_scene_actual_ground_hold_remains_native_full_brakes")
 var submitted: int=scene.submitted_count
 scene.on_focus_lost()
 scene.process_input_interval(25000)
 var focused: Dictionary=scene.facade.readback()
 host.check(focused.host_mode=="paused" and focused.paused and _preserved(flying,focused) and scene.submitted_count==submitted,"input_scene_actual_focus_pauses_before_another_native_tick_or_command")
 host.check(scene.mapper.sample(scene.synthetic_raw,0).brake_hold,"input_scene_actual_focus_preserves_hold_latch")
 host.check(not scene.pause_session(false) and scene.facade.readback().tick==flying.tick,"input_scene_held_throttle_key_blocks_explicit_resume")
 scene.synthetic_raw.keys=[]
 host.check(scene.pause_session(false),"input_scene_released_keyboard_allows_explicit_native_resume")
 _hide_menu(scene)
 host.check(scene.pause_session(true),"input_scene_pause_before_device_configuration")
 scene.observe_connection(42,true) # Fixture-local fake connection, never polled.
 var generation: int=scene.device_connections[42].generation
 scene.selected_slots={"test_stick":{"device":42,"generation":generation}}
 scene.synthetic_raw=_device_raw(generation)
 var preset := _device_preset()
 scene.apply_controls(preset)
 host.check(scene.active_preset==preset and scene.mapper.sample(scene.synthetic_raw,0).brake_hold,"input_scene_actual_Apply_preserves_ground_hold")
 host.check(scene.pause_session(false),"input_scene_neutral_observed_synthetic_source_resume")
 _hide_menu(scene)
 scene.process_input_interval(8334)
 var before_removal: Dictionary=scene.facade.readback()
 submitted=scene.submitted_count
 scene.on_joy_connection_changed(42,false)
 scene.synthetic_raw={"keys":[],"mouse_buttons":[],"devices":[]}
 scene.process_input_interval(8334)
 var removed: Dictionary=scene.facade.readback()
 host.check(removed.host_mode=="paused" and removed.paused and _preserved(before_removal,removed) and scene.submitted_count==submitted,"input_scene_actual_selected_source_removal_pauses_before_solver_or_axis_submission")
 host.check(not scene.pause_session(false) and scene.facade.readback().tick==removed.tick,"input_scene_missing_source_cannot_resume")
 scene.observe_connection(42,true)
 generation=scene.device_connections[42].generation
 scene.synthetic_raw=_device_raw(generation)
 host.check(not scene.pause_session(false),"input_scene_reused_slot_new_generation_cannot_silently_resume")
 scene.select_input_device("test_stick",42)
 scene.apply_controls(preset)
 host.check(scene.pause_session(false),"input_scene_explicit_reselection_Apply_and_resume_recovers")
 _hide_menu(scene)
 scene.process_input_interval(8334)
 var before_bad: Dictionary=scene.facade.readback()
 submitted=scene.submitted_count
 scene.synthetic_raw=_device_raw(generation,NAN)
 scene.process_input_interval(8334)
 var bad: Dictionary=scene.facade.readback()
 host.check(bad.host_mode=="paused" and _preserved(before_bad,bad) and scene.submitted_count==submitted,"input_scene_actual_invalid_raw_pauses_before_solver_or_axis_submission")
 scene.synthetic_raw=_device_raw(generation)
 var active_before: Dictionary=scene.active_preset.duplicate(true)
 var invalid_preset: Dictionary=preset.duplicate(true)
 invalid_preset.axes[0].gain=NAN
 scene.apply_controls(invalid_preset)
 host.check(scene.active_preset==active_before and scene.facade.readback().tick==bad.tick and scene.facade.readback().held_axes==bad.held_axes,"input_scene_failed_Apply_preserves_active_preset_and_native_held_axes")
 # Actual Controls false-validity branch: mutate only the declared test draft,
 # leaving accepted active/native state intact. No UI event or device injection.
 scene.open_controls()
 var controls_ui: Control=scene.controls_panel
 var emitted: Array=[]
 controls_ui.applied.connect(func(value: Dictionary): emitted.append(value.duplicate(true)))
 var invalid_draft: Dictionary=controls_ui.get_draft()
 for i in invalid_draft.axes.size():
  if invalid_draft.axes[i].target=="roll": invalid_draft.axes[i]={"target":"roll","kind":"fixed","value":2.0}
 var native_before_ui: Dictionary=scene.facade.readback().duplicate(true)
 var active_before_ui: Dictionary=scene.active_preset.duplicate(true)
 controls_ui.set("_draft",invalid_draft)
 controls_ui.call("_rebuild")
 host.check(controls_ui.get("_apply_button").disabled and not controls_ui.get("_message").text.is_empty(),"input_scene_actual_invalid_draft_branch_disables_Apply_and_shows_error")
 controls_ui.call("_apply")
 host.check(emitted.is_empty() and scene.facade.readback()==native_before_ui and scene.active_preset==active_before_ui,"input_scene_actual_invalid_draft_direct_Apply_has_no_emission_or_native_active_mutation")
 controls_ui.call("_cancel")
 host.check(not controls_ui.visible and scene.facade.readback()==native_before_ui and scene.active_preset==active_before_ui,"input_scene_actual_invalid_draft_Cancel_preserves_native_active_and_closes_UI")
 scene.open_controls()
 host.check(controls_ui.get_draft()==active_before_ui and not controls_ui.get("_apply_button").disabled,"input_scene_actual_reopened_controls_restore_accepted_draft")
 controls_ui.call("_cancel")
 scene.synthetic_raw={"keys":[],"mouse_buttons":[],"devices":[]}
 scene.apply_controls(Mapper.default_preset())
 var previous_mapper: RefCounted=scene.mapper
 scene.named_start="airborne-prepared"
 host.check(scene.restart(true),"input_scene_fresh_airborne_restart_joins_old_session")
 scene.set_process(false)
 var fresh: Dictionary=scene.facade.readback()
 host.check(fresh.session_id!=first.session_id and fresh.tick=="0" and fresh.host_mode=="paused" and scene.mapper!=previous_mapper and scene.mapper.sample(scene.synthetic_raw,0).ok and not scene.mapper.sample(scene.synthetic_raw,0).brake_hold,"input_scene_actual_fresh_airborne_mapper_resets_latch_and_edges")
 host.check(scene.close_session(),"input_scene_actual_fixture_worker_joined")
 if scene.sound!=null: host.check(bool(await scene.sound.call("shutdown")),"input_scene_actual_fixture_audio_retired")
 scene.free()
 return {"scope":"Actual existing native facade/production controller with synthetic copied Raw, focus/removal/generation/NaN faults; no physical hardware, GPU, pilot, or flight performance qualification","initial_tick":first.tick,"focus_retained_tick":focused.tick,"removed_retained_tick":removed.tick,"invalid_retained_tick":bad.tick,"fresh_tick":fresh.tick}
