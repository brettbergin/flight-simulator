extends RefCounted
# Actual Scene/native flight + preconfigured actual LocalPlayersTest. Only Raw
# input is synthetic. No persistence/Facade/recorder/archive methods overridden.
const Scene = preload("res://simulation/flight_scene.gd")
const Options = preload("res://ui/profiles/player_options.gd")
const Codec = preload("res://replay/observed_archive/codec.gd")
const Values = preload("res://replay/observed/values.gd")

class TestScene extends Scene:
	var preconfigured_service: RefCounted
	func collect_input_raw(_preset: Dictionary = {}) -> Dictionary:
		return {"keys":[],"mouse_buttons":[],"devices":[]}
	func _players_storage_allowed() -> bool: return true
	func _make_local_players_service() -> RefCounted: return preconfigured_service

var _host: Node
var _scene: Node
var _terminals: Array = []
var _link_states: Array = []
var _retained: Array = []

func _terminal(_opening: int, _epoch: int, result: Dictionary) -> void:
	_terminals.append(result.duplicate(true))

func _links(id: String, state: Dictionary) -> void:
	_link_states.append({"practice_id":id,"state":state.duplicate(true)})

func _matching(kind: String) -> Array:
	return _terminals.filter(func(value: Dictionary): return value.kind == kind)

func _wait(predicate: Callable, name: String) -> bool:
	var deadline: int = Time.get_ticks_msec() + 20000
	while Time.get_ticks_msec() < deadline:
		if _scene != null and _scene.player_controller != null:
			_scene.player_controller.pump() # Sole owner of service.poll.
		if predicate.call():
			_host.check(true,name)
			return true
		await _host.get_tree().process_frame
	_host.check(false,name + "_timeout")
	return false

func _page_ready() -> bool:
	return not _scene._player_ui.is_empty() and _scene._player_ui.kind == "players" and not _scene._player_ui.widget._busy

func _close_to_players() -> bool:
	_scene.dismiss_first_flight()
	if _scene.review_open: _scene.dismiss_observed_review()
	_scene.open_menu("Isolated archive-link journey")
	if not _scene.pause_session(true) or not _scene.advance_wall_us(0):
		_host.check(false,"archive_real_pause_before_close")
		return false
	_scene.show_state(0.0)
	if not _scene.open_players() or _scene._player_exit.is_empty():
		_host.check(false,"archive_real_players_confirmation")
		return false
	_scene._player_exit.dialog.confirmed.emit()
	return await _wait(_page_ready,"archive_real_actual_flight_history_audio_close_then_players")

func _create_player() -> bool:
	_scene._player_ui.widget._create.pressed.emit()
	if _scene._player_ui.is_empty() or _scene._player_ui.kind != "create":
		_host.check(false,"archive_real_create_page")
		return false
	var widget: Control = _scene._player_ui.widget
	widget._name.text = "KAWO archive isolated"
	widget._name.text_changed.emit(widget._name.text)
	widget._confirm.pressed.emit()
	return await _wait(func():
		var pair: Variant = _scene.player_controller.selected_pair()
		return pair != null and pair.player.name == "KAWO archive isolated" and _scene._player_ui.is_empty(),"archive_real_created_player_adopted")

func _cleanup(service: RefCounted) -> bool:
	var flight_joined: bool = true
	if _scene != null:
		if not _scene.archive_operation.is_empty(): _scene.cancel_archive_operation()
		_scene.retire_players_ui()
		flight_joined = _scene.close_session()
		if _scene.sound != null: flight_joined = bool(await _scene.sound.shutdown()) and flight_joined
		if _scene.player_controller != null:
			# Keep accepted end/link requests draining before storage shutdown.
			await _wait(func():
				var status: Dictionary = service.call("status")
				return status.pending == 0 and status.undelivered == 0,"archive_real_cleanup_accepted_requests_drained")
			_scene.player_controller.begin_close()
		else: service.call("begin_shutdown")
	var deadline: int = Time.get_ticks_msec() + 20000
	var storage_joined: bool = false
	while Time.get_ticks_msec() < deadline:
		if _scene != null and _scene.player_controller != null: _scene.player_controller.pump()
		var status: Dictionary = service.call("status")
		if status.state == "closed" and status.pending == 0 and status.undelivered == 0 and not status.writer_alive and service.call("try_join") == true:
			storage_joined = true
			break
		await _host.get_tree().process_frame
	_host.check(flight_joined and storage_joined,"archive_real_actual_flight_audio_and_storage_joined")
	if flight_joined and storage_joined:
		if _scene != null:
			_host.remove_child(_scene)
			_scene.free()
			_scene = null
		return true
	_retained.append(_scene)
	_retained.append(service)
	return false

func run(host: Node, service: RefCounted) -> Dictionary:
	_host = host
	_scene = TestScene.new()
	_scene.preconfigured_service = service
	host.add_child(_scene)
	_scene.set_process(false)
	_scene.set_physics_process(false)
	_scene.set_process_input(false)
	_scene.set_process_unhandled_input(false)
	_scene.set_process_unhandled_key_input(false)
	if _scene.sound != null: _scene.sound.set_process(false)
	var attached: bool = service != null and service.get_script() == null and service.get_class() == "LocalPlayersTest" and _scene.player_controller != null and _scene.facade != null
	host.check(attached,"archive_real_actual_flight_and_exact_test_store_attached")
	if not attached: return {"retained":not await _cleanup(service)}
	_scene.player_controller.operation_finished.connect(_terminal)
	_scene.player_controller.archive_link_changed.connect(_links)
	if not await _wait(func(): return _scene.player_controller.current_status().get("state") == "ready","archive_real_storage_ready"):
		return {"retained":not await _cleanup(service)}
	if not await _close_to_players() or not await _create_player(): return {"retained":not await _cleanup(service)}
	var player: Dictionary = _scene.player_controller.selected_pair()
	host.check(_scene.restart(true,"calm","original-interactive-prototype","ground-ready","kawo-prototype-v1"),"archive_real_kawo_actual_named_flight")
	if _scene.facade == null or _scene.selected_world != "kawo-prototype-v1": return {"retained":not await _cleanup(service)}
	_scene.dismiss_first_flight()
	if not await _wait(func(): return _matching("begin_practice").size() == 1,"archive_real_begin_ack"):
		return {"retained":not await _cleanup(service)}
	var begun: Dictionary = _matching("begin_practice")[0]
	if begun.state != "committed" or not begun.value is Dictionary or not begun.value.get("practice") is Dictionary:
		host.check(false,"archive_real_begin_must_commit_before_flight_interval")
		return {"retained":not await _cleanup(service)}
	var context: Dictionary = _scene._recording_player_context.duplicate(true)
	host.check(begun.state == "committed" and begun.value.practice.first_tick == "0" and begun.value.practice.last_tick == "0" and begun.value.practice.player_id == player.player.id and Options.exact_equal(begun.value.practice.source,context.source),"archive_real_begin_source_owner_tick0")
	_scene.close_menu()
	for _index in 61: _scene.process_input_interval(8334)
	_scene.open_menu("Save at native tick 61")
	host.check(_scene.pause_session(true) and _scene.advance_wall_us(0),"archive_real_verified_pause61")
	_scene.show_state(0.0)
	var paused: Dictionary = _scene.facade.readback()
	var original: Dictionary = _scene.observed_recorder.recording()
	host.check(paused.tick == "61" and paused.host_mode == "paused" and original.contract_version == 3 and original.metadata.first_tick == "0" and original.last_observed_tick == "61" and Values.valid_recording(original),"archive_real_native61_and_recording3_actual_endpoints")
	if paused.tick != "61" or original.last_observed_tick != "61": return {"retained":not await _cleanup(service)}
	_scene.open_observed_review()
	host.check(_scene.review_open and _scene.begin_archive_operation("save",false),"archive_real_scene_save_operation")
	var folder: String = ProjectSettings.globalize_path("res://journey-artifacts")
	if DirAccess.make_dir_recursive_absolute(folder) != OK:
		host.check(false,"archive_real_fresh_artifact_directory")
		return {"retained":not await _cleanup(service)}
	var path: String = folder.path_join("tick61.fsreview.json")
	host.check(not FileAccess.file_exists(path),"archive_real_new_file_only")
	var saved: Dictionary = _scene.finish_archive_operation(path)
	host.check(saved.ok and saved.state == "saved" and saved.payload_sha256 != null,"archive_real_actual_archive_writer_verified_file")
	if not saved.ok: return {"retained":not await _cleanup(service)}
	var link: Dictionary = _scene.player_controller.archive_link_state(context.practice_id)
	host.check(link.get("state") == "pending_endpoint" and link.get("payload_sha256") == saved.payload_sha256,"archive_real_file_saved_link_waits_for_endpoint_ack")
	# Explicit idle pumps never create a sub-120 observation or infer ticks from
	# archive metadata. The live paused readback and recorder remain exact.
	for _index in 8:
		_scene.player_controller.pump()
		await host.get_tree().process_frame
	host.check(_matching("observe_practice").is_empty() and _matching("end_practice").is_empty() and _matching("link_archive").is_empty(),"archive_real_no_forced_observe_or_early_link")
	host.check(Codec._exact(_scene.facade.readback(),paused) and Codec._exact(_scene.observed_recorder.recording(),original) and Options.exact_equal(_scene._recording_player_context,context),"archive_real_save_preserves_native_recorder_original_context")
	# The real native close supplies endpoint61. Its real end ACK must precede
	# the one durable link mutation; no resumed flight or forced observation.
	if not await _close_to_players(): return {"retained":not await _cleanup(service)}
	var ended: Array = _matching("end_practice")
	var linked: Array = _matching("link_archive")
	host.check(_matching("observe_practice").is_empty() and ended.size() == 1 and linked.size() == 1,"archive_real_exactly_one_actual_end_and_link_no_observe")
	if ended.size() != 1 or linked.size() != 1: return {"retained":not await _cleanup(service)}
	if ended[0].state != "committed" or linked[0].state != "committed" or not linked[0].value is Dictionary or not Options.practice_valid(linked[0].value.get("practice")):
		host.check(false,"archive_real_end_and_link_must_return_actual_committed_rows")
		return {"retained":not await _cleanup(service)}
	var durable: Dictionary = linked[0].value.practice
	host.check(ended[0].state == "committed" and ended[0].value.practice.last_tick == "61" and ended[0].value.practice.status == "manually_ended" and ended[0].value.practice.end_reason == "user_end","archive_real_end_uses_actual_closed61")
	host.check(linked[0].state == "committed" and _terminals.find(ended[0]) < _terminals.find(linked[0]) and _scene.player_controller.archive_link_state(context.practice_id).state == "saved","archive_real_link_saved_only_after_actual_ordered_ack")
	host.check(durable.player_id == player.player.id and durable.id == context.practice_id and Options.exact_equal(durable.source,context.source) and durable.archive.absolute_path == saved.path and durable.archive.payload_sha256 == saved.payload_sha256 and durable.archive.recording_session_id == original.metadata.session_id and durable.archive.first_tick == "0" and durable.archive.last_tick == "61","archive_real_durable_original_owner_full_source_ticks_digest")
	# Actual store load drives the real Scene details page and guarded linked Open.
	_scene.player_controller.request_details(_scene._player_ui.opening,_scene._player_ui.epoch,context.practice_id)
	if not await _wait(func(): return _matching("load_practice").size() == 1 and not _scene._player_ui.is_empty() and _scene._player_ui.kind == "details","archive_real_reloaded_actual_practice_details"):
		return {"retained":not await _cleanup(service)}
	var reloaded: Dictionary = _matching("load_practice")[0].value.practice
	host.check(Options.exact_equal(reloaded,durable),"archive_real_store_reload_matches_link_ack")
	_scene._player_ui.widget._open.pressed.emit()
	host.check(_scene.archive_imported and _scene.review_open and _scene.facade == null and _scene.review_joined,"archive_real_guarded_linked_open_is_historical_no_new_flight")
	host.check(Codec._exact(_scene.observed_panel._record,original),"archive_real_recording3_reopened_exact_bits_and_source")
	var joined: bool = await _cleanup(service)
	return {"retained":not joined,"scope":"actual isolated KAWO tick61 archive3/controller/Practice end+link ACK/load/Scene linked Open","actual_store":true,"actual_flight":true,"forced_observation":false,"player_id":player.player.id,"practice_id":context.practice_id,"payload_sha256":saved.payload_sha256,"first_tick":"0","last_tick":"61","link_states":_link_states}
