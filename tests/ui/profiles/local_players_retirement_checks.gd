extends RefCounted
# Original MIT. Actual native flight and production Audio subclass. The only
# controlled fixtures are an explicit pre-shutdown gate and one labelled false
# return; the retry delegates to real shutdown. No actual timeout is claimed.
# No fabricated native closure or OS audio-thread join is claimed.
const SceneChecks = preload("res://player_tests/local_players_scene_checks.gd")
const Controller = preload("res://persistence/local_players_controller.gd")
const Sound = preload("res://interactive/flight_sound.gd")

class DelayedSound extends Sound:
	var entered: bool = false
	var release: bool = false
	var completed: bool = false
	var actual_result: bool = false
	var calls: int = 0
	func shutdown() -> bool:
		calls += 1
		entered = true
		if calls == 1:
			while not release:
				await get_tree().process_frame
			# Explicit labelled branch fixture, not a physical playback timeout.
			return false
		actual_result = bool(await super.shutdown())
		completed = true
		return actual_result

class QuitObservedScene extends SceneChecks.FixtureScene:
	var quit_continuations: int = 0
	func _finish_player_quit() -> void:
		# Only the post-retirement continuation is observed to keep this test
		# process alive. Flight close and playback shutdown remain production.
		# No storage shutdown/tree-exit proof is asserted by this fixture.
		quit_continuations += 1

var _retained: Array = []

func _retry_button(node: Node) -> Button:
	if node is Button and node.text == "Retry playback shutdown":
		return node
	for child: Node in node.get_children():
		var found: Button = _retry_button(child)
		if found != null:
			return found
	return null

func _without_flight_snapshot(scene: Node) -> PackedByteArray:
	return var_to_bytes({"recording":scene.observed_recorder.recording(),"recorder_status":scene.observed_status.duplicate(true),
		"player":scene.player_controller.selected_pair(),"epoch":scene.player_controller.current_epoch(),"save":scene.player_controller.save_state(),
		"audio":scene.audio_options.duplicate(true),"seed":scene.capture_current_player_seed(),"context":scene._recording_player_context.duplicate(true),
		"active_preset":scene.active_preset.duplicate(true),"presets":scene.profile_presets.duplicate(true),"view":scene.view_settings.duplicate(true),
		"camera_transform":scene.camera.global_transform,"camera_fov":scene.camera.fov,"mode":scene.camera_mode,"look":scene.look_angles,
		"distance":scene.camera_distance,"follow":scene.camera_follow_offset})

func run(host: Node) -> Dictionary:
	var scene: Node = SceneChecks.FixtureScene.new()
	host.add_child(scene)
	scene.set_process(false)
	scene.set_physics_process(false)
	scene.set_process_input(false)
	scene.set_process_unhandled_input(false)
	scene.set_process_unhandled_key_input(false)
	if scene.player_controller == null:
		# Labelled no-service routing only, as in the actual-flight Cancel checks.
		scene.player_controller = Controller.new()
	var actual: bool = scene.facade != null and scene.camera != null
	host.check(actual,"players_retirement_actual_flight_initialized")
	if not actual:
		_retained.append(scene)
		return {"retained":true}
	var previous_sound: Node = scene.sound
	if previous_sound != null:
		var previous_joined: bool = bool(await previous_sound.shutdown())
		host.check(previous_joined,"players_retirement_original_audio_actually_retired")
		if not previous_joined:
			_retained.append(scene)
			return {"retained":true}
		previous_sound.free()
	var delayed: Node = DelayedSound.new()
	scene.add_child(delayed)
	scene.sound = delayed
	delayed.set_process(false)
	delayed.set_options(scene.audio_options)
	scene._observe_audio(scene.facade.readback())
	scene.dismiss_first_flight()
	scene.open_menu("Controlled Audio retirement gap")
	host.check(scene.pause_session(true) and scene.advance_wall_us(0),"players_retirement_paused_settlement")
	scene.show_state(0.0)
	host.check(scene.open_players(),"players_retirement_real_exit_confirmation")
	var dialog: ConfirmationDialog = scene._player_exit.dialog
	dialog.confirmed.emit()
	await host.get_tree().process_frame
	host.check(delayed.entered and not delayed.completed and scene.facade == null and scene.review_joined,"players_retirement_actual_flight_joined_while_audio_gate_waits")
	var before: PackedByteArray = _without_flight_snapshot(scene)
	var ledger: PackedByteArray = SceneChecks.new()._ledger(scene)
	var facade_count: int = scene.facades.size()
	host.check(not scene.open_players(),"players_retirement_players_reentry_refused_during_actual_await")
	scene.start_flight("ground-ready")
	scene.perform_start("ground-ready","calm","original-interactive-prototype")
	host.check(not scene.restart(true,"calm","original-interactive-prototype","ground-ready"),"players_retirement_direct_restart_refused_during_actual_await")
	for code: int in [KEY_R,KEY_2,KEY_TAB,KEY_P]:
		var key := InputEventKey.new()
		key.keycode = code
		key.physical_keycode = code
		key.pressed = true
		scene._input(key)
		scene._unhandled_key_input(key)
	for action: String in ["restart","start_ground","view_chase","map_toggle","pause_menu"]:
		scene.dispatch_input_action(action)
	host.check(scene.facade == null and scene.facades.size() == facade_count and scene._player_ui.is_empty() and scene.pending_discard.is_empty(),"players_retirement_no_replacement_flight_or_modal_while_waiting")
	host.check(_without_flight_snapshot(scene) == before and SceneChecks.new()._ledger(scene) == ledger,"players_retirement_reentry_preserves_options_recorder_camera_and_native_ledger")
	host.check(not scene._player_quit_pending,"players_retirement_unrelated_actions_do_not_begin_quit")
	delayed.release = true
	var deadline: int = Time.get_ticks_msec()+15000
	var retry: Button
	while retry == null and Time.get_ticks_msec() < deadline:
		await host.get_tree().process_frame
		retry = _retry_button(scene)
	host.check(retry != null and scene._player_transition and scene.sound == delayed and not scene._player_audio_retired,"players_retirement_labelled_false_keeps_owned_transition_and_retry")
	host.check(not scene.open_players() and not scene.restart(true,"calm","original-interactive-prototype","ground-ready"),"players_retirement_failed_retirement_cannot_enter_or_restart")
	host.check(_without_flight_snapshot(scene) == before and SceneChecks.new()._ledger(scene) == ledger,"players_retirement_failed_retirement_retains_original_source_and_options")
	if retry == null:
		_retained.append(scene)
		return {"retained":true,"scope":"labelled_audio_retirement_false_fixture"}
	retry.pressed.emit()
	deadline = Time.get_ticks_msec()+15000
	while scene.sound != null and Time.get_ticks_msec() < deadline:
		await host.get_tree().process_frame
	host.check(scene.sound == null and scene._player_audio_retired,"players_retirement_actual_audio_completion_then_continuation")
	host.check(scene.facade == null and scene.menu_open and scene.review_joined,"players_retirement_no_service_continuation_remains_honest_no_flight")
	host.check(scene.open_players(),"players_retirement_transition_released_for_later_players_entry")
	scene.retire_players_ui()
	var joined: bool = scene.close_session()
	if scene.sound != null:
		joined = bool(await scene.sound.shutdown()) and joined
	host.check(joined,"players_retirement_final_actual_lifecycle_closed")
	if joined:
		scene.free()
	else:
		_retained.append(scene)
	return {"retained":not joined,"scope":"actual_flight_with_labelled_delay_and_one_false_audio_fixture_then_actual_retry_retirement","native_storage_exercised":false,"ordinary_keyboard_or_pixels":false}

func run_quit(host: Node) -> Dictionary:
	var scene: Node = QuitObservedScene.new()
	host.add_child(scene)
	scene.set_process(false)
	scene.set_physics_process(false)
	scene.set_process_input(false)
	scene.set_process_unhandled_input(false)
	scene.set_process_unhandled_key_input(false)
	if scene.player_controller == null:
		scene.player_controller = Controller.new()
	if scene.facade == null:
		host.check(false,"players_quit_retirement_actual_flight_initialized")
		_retained.append(scene)
		return {"retained":true}
	var previous_sound: Node = scene.sound
	if previous_sound != null:
		var retired: bool = bool(await previous_sound.shutdown())
		host.check(retired,"players_quit_retirement_original_audio_actually_retired")
		if not retired:
			_retained.append(scene)
			return {"retained":true}
		previous_sound.free()
	var delayed: Node = DelayedSound.new()
	scene.add_child(delayed)
	scene.sound = delayed
	delayed.set_process(false)
	delayed.set_options(scene.audio_options)
	scene._observe_audio(scene.facade.readback())
	scene.dismiss_first_flight()
	scene.open_menu("Controlled Quit retirement gap")
	scene.pause_session(true)
	scene.advance_wall_us(0)
	scene.show_state(0.0)
	var prior_facade: RefCounted = scene.facade
	scene.perform_quit()
	await host.get_tree().process_frame
	var rb: Dictionary = prior_facade.readback()
	host.check(delayed.entered and not delayed.completed and scene.facade == null and rb.host_mode == "closed" and not rb.native_live,"players_quit_retirement_actual_join_before_audio_await")
	host.check(scene._player_transition and scene._player_quit_pending and scene.quit_continuations == 0,"players_quit_retirement_holds_transition_before_completion")
	var before: PackedByteArray = _without_flight_snapshot(scene)
	var ledger: PackedByteArray = SceneChecks.new()._ledger(scene)
	var count: int = scene.facades.size()
	host.check(not scene.open_players() and not scene.restart(true,"calm","original-interactive-prototype","ground-ready"),"players_quit_retirement_no_players_or_direct_restart")
	scene.start_flight("ground-ready")
	scene.perform_start("ground-ready","calm","original-interactive-prototype")
	scene.dispatch_input_action("restart")
	scene.quit_flight()
	scene.perform_quit()
	host.check(scene.facade == null and scene.facades.size() == count and scene.quit_continuations == 0 and _without_flight_snapshot(scene) == before and SceneChecks.new()._ledger(scene) == ledger,"players_quit_retirement_reentry_cannot_start_or_finish_early")
	delayed.release = true
	var deadline: int = Time.get_ticks_msec()+15000
	var retry: Button
	while retry == null and Time.get_ticks_msec() < deadline:
		await host.get_tree().process_frame
		retry = _retry_button(scene)
	host.check(retry != null and scene._player_transition and scene._player_quit_pending and scene.quit_continuations == 0,"players_quit_retirement_labelled_false_keeps_quit_owned_until_retry")
	if retry == null:
		_retained.append(scene)
		return {"retained":true}
	retry.pressed.emit()
	deadline = Time.get_ticks_msec()+15000
	while scene.quit_continuations == 0 and Time.get_ticks_msec() < deadline:
		await host.get_tree().process_frame
	host.check(scene.sound == null and scene._player_audio_retired and scene.quit_continuations == 1,"players_quit_retirement_actual_audio_success_before_single_continuation")
	host.check(scene.facade == null and SceneChecks.new()._ledger(scene) == ledger,"players_quit_retirement_no_new_flight_before_continuation")
	# Test-only observer cleanup after proving the production continuation edge.
	# This neither claims nor simulates the separate storage-join/tree-exit edge.
	scene._player_quit_pending = false
	scene._player_transition = false
	scene.retire_players_ui()
	var joined: bool = scene.close_session()
	if scene.sound != null:
		joined = bool(await scene.sound.shutdown()) and joined
	if joined:
		scene.free()
	else:
		_retained.append(scene)
	return {"retained":not joined,"scope":"actual_flight_audio_quit_edge_with_labelled_delay_false_and_observed_post_retirement_continuation","native_storage_or_tree_exit_exercised":false}
