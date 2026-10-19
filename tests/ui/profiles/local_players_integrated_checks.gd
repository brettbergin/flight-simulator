extends RefCounted
# Original MIT. Real flight + real qualified LocalPlayersTest through the
# production Scene bindings. Only complete Raw/observed adapter are fixtures.
const SceneChecks = preload("res://player_tests/local_players_scene_checks.gd")
const Options = preload("res://ui/profiles/player_options.gd")

class IntegratedScene extends SceneChecks.FixtureScene:
	var preconfigured_service: RefCounted
	func _make_local_players_service() -> RefCounted:
		return preconfigured_service

var _scene: Node
var _host: Node
var _terminals: Array = []
var _retained: Array = []

func _terminal(_opening: int,_epoch: int,result: Dictionary) -> void:
	_terminals.append(result.duplicate(true))

func _wait(predicate: Callable,label: String) -> bool:
	var deadline: int = Time.get_ticks_msec()+15000
	while Time.get_ticks_msec() < deadline:
		if _scene.player_controller != null:
			_scene.player_controller.pump()
		if predicate.call():
			_host.check(true,label)
			return true
		await _host.get_tree().process_frame
	_host.check(false,label+"_timeout")
	return false

func _page_ready() -> bool:
	return not _scene._player_ui.is_empty() and _scene._player_ui.kind == "players" and not _scene._player_ui.widget._busy

func _flight_authority() -> PackedByteArray:
	var snapshot: Dictionary = bytes_to_var(SceneChecks.new()._snapshot(_scene))
	# Save ACK may update paired revision and presentation status, never these
	# flight/recorder/camera/mapper values or current applied Audio.
	for key in ["selected_pair","player_epoch","save_state","_player_state","_player_seed"]:
		snapshot.erase(key)
	return var_to_bytes(snapshot)

func _matching(kind: String) -> Array:
	var rows: Array = []
	for result: Dictionary in _terminals:
		if result.kind == kind:
			rows.append(result)
	return rows

func _close_to_chooser() -> bool:
	_scene.dismiss_first_flight()
	if _scene.audio_open:
		_scene.dismiss_audio()
	_scene.open_menu("Players integration check")
	_host.check(_scene.pause_session(true) and _scene.advance_wall_us(0),"players_integrated_paused_settlement")
	_scene.show_state(0.0)
	if not _scene.open_players():
		_host.check(false,"players_integrated_menu_players_opens")
		return false
	var dialog: ConfirmationDialog = _scene._player_exit.dialog
	await _host.get_tree().process_frame
	var modal_state: PackedByteArray = SceneChecks.new()._snapshot(_scene)
	var modal_calls: PackedByteArray = SceneChecks.new()._ledger(_scene)
	for code: int in [KEY_2,KEY_R,KEY_TAB,KEY_P]:
		var key := InputEventKey.new()
		key.keycode = code
		key.physical_keycode = code
		key.pressed = true
		_scene._input(key)
		_scene._unhandled_key_input(key)
	for action: String in ["restart","view_chase","map_toggle"]:
		_scene.dispatch_input_action(action)
	_host.check(not _scene._player_exit.is_empty() and SceneChecks.new()._snapshot(_scene) == modal_state and SceneChecks.new()._ledger(_scene) == modal_calls,"players_integrated_modal_methods_cannot_leak_view_restart_map_or_resume")
	dialog.confirmed.emit()
	return await _wait(_page_ready,"players_integrated_actual_close_history_audio_then_chooser")

func _create(name: String) -> bool:
	if not _page_ready():
		_host.check(false,"players_integrated_create_requires_ready_actual_page")
		return false
	_scene._player_ui.widget._create.pressed.emit()
	_host.check(_scene._player_ui.kind == "create","players_integrated_actual_create_route")
	var widget: Control = _scene._player_ui.widget
	widget._name.text = name
	widget._name.text_changed.emit(name)
	widget._confirm.pressed.emit()
	return await _wait(func():
		var pair: Variant = _scene.player_controller.selected_pair()
		return pair != null and pair.player.name == name and _scene._player_ui.is_empty(),"players_integrated_created_pair_adopted_by_root")

func _cleanup(service: RefCounted) -> bool:
	_scene.retire_players_ui()
	var flight_joined: bool = _scene.close_session()
	if _scene.sound != null:
		flight_joined = bool(await _scene.sound.shutdown()) and flight_joined
	# Every named flight was explicitly closed and history was already resolved.
	_scene.player_controller.begin_close()
	var joined: bool = await _wait(func():
		var status: Dictionary = service.status()
		return status.state == "closed" and status.pending == 0 and status.undelivered == 0 and not status.writer_alive and service.try_join(),"players_integrated_actual_storage_joined_empty")
	_host.check(flight_joined,"players_integrated_actual_flight_audio_joined")
	if flight_joined and joined:
		_scene.free()
		_scene = null
		return true
	_retained.append(_scene)
	_retained.append(service)
	return false

func run(host: Node,service: RefCounted) -> Dictionary:
	_host = host
	_terminals.clear()
	_scene = IntegratedScene.new()
	_scene.preconfigured_service = service
	host.add_child(_scene)
	_scene.set_process(false)
	_scene.set_physics_process(false)
	_scene.set_process_input(false)
	_scene.set_process_unhandled_input(false)
	_scene.set_process_unhandled_key_input(false)
	if _scene.sound != null:
		_scene.sound.set_process(false)
	var valid: bool = _scene.facade != null and _scene.player_controller != null and service.get_class() == "LocalPlayersTest"
	host.check(valid,"players_integrated_actual_scene_flight_and_native_storage_attached")
	if not valid:
		_retained.append(_scene)
		_retained.append(service)
		return {"retained":true}
	_scene.player_controller.operation_finished.connect(_terminal)
	if not await _wait(func(): return _scene.player_controller.current_status().get("state") == "ready","players_integrated_actual_storage_ready"):
		return {"retained":not await _cleanup(service)}
	if not await _close_to_chooser() or not await _create("Alpha"):
		return {"retained":not await _cleanup(service)}
	var a: Dictionary = _scene.player_controller.selected_pair()
	host.check(a.player.revision == "1" and Options.exact_equal(Options.seed_from_preferences(a.preferences),Options.default_seed()),"players_integrated_create_default_pair_no_flight")
	host.check(_scene.facade == null and _scene.review_joined,"players_integrated_selection_never_starts_flight")
	host.check(_scene.restart(true,"calm","original-interactive-prototype","ground-ready"),"players_integrated_named_fresh_actual_flight")
	_scene.dismiss_first_flight()
	_scene.open_menu("Named actual flight")
	if not await _wait(func(): return not _matching("begin_practice").is_empty(),"players_integrated_actual_begin_practice_receipt"):
		return {"retained":not await _cleanup(service)}
	var begun: Dictionary = _matching("begin_practice").back()
	host.check(begun.state == "committed" and begun.value.practice.player_id == a.player.id and begun.value.practice.source.session_id == _scene.adopted_session_id,"players_integrated_practice_bound_actual_player_session")
	# A short actual native interval supplies a meaningful closed endpoint. No
	# trajectory, lesson score or real-flight fidelity is asserted here.
	_scene.close_menu()
	for index in 125:
		_scene.process_input_interval(8334)
	_scene.open_menu("Save integration check")
	_scene.pause_session(true)
	_scene.advance_wall_us(0)
	_scene.show_state(0.0)
	if not await _wait(func():
		var status: Dictionary = _scene.player_controller.current_status()
		return status.pending == 0 and status.undelivered == 0,"players_integrated_observation_receipts_drained_before_save"):
		return {"retained":not await _cleanup(service)}
	_scene.open_audio()
	host.check(_scene.audio_open and _scene.audio_panel.visible,"players_integrated_actual_audio_entry")
	var audio: Control = _scene.audio_panel
	var changed: Dictionary = {"enabled":true,"engine_gain":0.5,"airflow_gain":1.0,"show_panel_captions":true}
	audio.options_requested.emit(changed,_scene.adopted_session_id)
	host.check(Options.exact_equal(_scene.audio_options,changed) and _scene._player_state.dirty,"players_integrated_audio_change_applied_dirty_through_root")
	var before: PackedByteArray = _flight_authority()
	var calls: PackedByteArray = SceneChecks.new()._ledger(_scene)
	var recorder_context: PackedByteArray = var_to_bytes(_scene._recording_player_context)
	audio._player_save_button.pressed.emit()
	host.check(_scene._player_state.pending,"players_integrated_explicit_save_admitted_pending")
	if not await _wait(func(): return not _scene._player_state.pending and not _matching("save_preferences").is_empty(),"players_integrated_actual_save_ack"):
		return {"retained":not await _cleanup(service)}
	var saved: Dictionary = _matching("save_preferences").back()
	var pair: Dictionary = _scene.player_controller.selected_pair()
	host.check(saved.state == "committed" and pair.player.revision == "2" and pair.preferences.revision == "2" and not _scene._player_state.dirty,"players_integrated_ack_updates_paired_revision_clean")
	host.check(pair.preferences.legacy_input == null and pair.preferences.piston_input == null and Options.exact_equal(pair.preferences.audio,changed),"players_integrated_audio_save_preserves_untouched_null_input_slots")
	host.check(_flight_authority() == before and SceneChecks.new()._ledger(_scene) == calls and var_to_bytes(_scene._recording_player_context) == recorder_context,"players_integrated_save_does_not_modify_native_mapper_recorder_camera_or_source")
	if not await _close_to_chooser():
		return {"retained":not await _cleanup(service)}
	var ended: Array = _matching("end_practice")
	host.check(ended.size() == 1 and ended[0].state == "committed" and ended[0].value.practice.player_id == a.player.id and ended[0].value.practice.status == "manually_ended" and ended[0].value.practice.end_reason == "user_end","players_integrated_actual_named_history_end_before_chooser")
	if not ended.is_empty():
		host.check(ended[0].value.practice.last_tick != "0" and ended[0].value.practice.source.session_id == begun.value.practice.source.session_id,"players_integrated_history_uses_same_actual_source_nonzero_endpoint")
	var recording: PackedByteArray = var_to_bytes(_scene.observed_recorder.recording())
	var original_context: PackedByteArray = var_to_bytes(_scene._recording_player_context)
	_scene._player_ui.widget._guest.pressed.emit()
	host.check(_scene.player_controller.selected_pair() == null and _scene.facade == null and Options.exact_equal(_scene.audio_options,Options.default_seed().audio),"players_integrated_guest_adoption_resets_options_without_flight")
	host.check(var_to_bytes(_scene.observed_recorder.recording()) == recording and var_to_bytes(_scene._recording_player_context) == original_context,"players_integrated_guest_preserves_original_recording_source")
	_scene.open_menu("Create second player")
	host.check(_scene.open_players(),"players_integrated_no_flight_chooser_entry")
	if not await _wait(_page_ready,"players_integrated_second_chooser_actual_list") or not await _create("Bravo"):
		return {"retained":not await _cleanup(service)}
	var b: Dictionary = _scene.player_controller.selected_pair()
	host.check(b.player.id != a.player.id and b.player.revision == "1" and Options.exact_equal(Options.seed_from_preferences(b.preferences),Options.default_seed()),"players_integrated_second_player_independent_defaults")
	var joined: bool = await _cleanup(service)
	return {"scope":"actual_scene_flight_menu_storage_save_history","retained":not joined,"native_storage_exercised":true,"ordinary_keyboard_or_pixels":false}
