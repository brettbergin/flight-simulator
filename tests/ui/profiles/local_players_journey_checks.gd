extends RefCounted
# Original MIT. Actual controller/native journey. Root supplies a preconfigured
# exact LocalPlayersTest from the existing bound capability. This file chooses
# no store root, descriptor, factory or process arguments and never polls native.
# Independent expected seeds stay null in both input slots in this first slice.
const Controller = preload("res://persistence/local_players_controller.gd")
const Options = preload("res://ui/profiles/player_options.gd")
var _controller: RefCounted
var _host: Node
var _terminal: Array = []
var _refusals: Array = []
var _closed: bool = false
var _opening: int = 0
var _candidate_count: int = 0
var _retained: RefCounted

func _candidate(opening: int, epoch: int, pair: Variant) -> void:
	_candidate_count += 1
	var valid: bool = pair == null or Options.validate_pair(pair).ok
	_host.check(valid, "player_journey_actual_candidate_valid")
	_controller.finish_selection(opening,epoch,valid)

func _finished(opening: int, epoch: int, result: Dictionary) -> void:
	_terminal.append({"opening":opening,"epoch":epoch,"result":result.duplicate(true)})

func _refused(opening: int, epoch: int, kind: String, reason: String, admission: Variant) -> void:
	_refusals.append([opening,epoch,kind,reason,admission])

func _storage_closed() -> void:
	_closed = true

func _utc() -> String:
	return Time.get_datetime_string_from_system(true,false) + "Z"

func _seed(engine: float = 1.0, airflow: float = 1.0) -> Dictionary:
	return {"legacy_input":null,"piston_input":null,"audio":{"enabled":true,"engine_gain":engine,"airflow_gain":airflow,"show_panel_captions":true}}

func _negative_zero() -> float:
	return PackedByteArray([0,0,0,0,0,0,0,128]).decode_double(0)

func _prepare(host: Node, service: RefCounted) -> bool:
	_host = host
	_controller = Controller.new()
	_terminal.clear()
	_refusals.clear()
	_closed = false
	_opening = 0
	_candidate_count = 0
	_controller.selection_candidate.connect(_candidate)
	_controller.operation_finished.connect(_finished)
	_controller.intent_refused.connect(_refused)
	_controller.storage_closed.connect(_storage_closed)
	var admitted: bool = service != null and service.get_script() == null and service.get_class() == "LocalPlayersTest" and _controller.attach_service(service)
	host.check(admitted, "player_journey_attaches_actual_preconfigured_test_service_only")
	return admitted

func _wait_kind(kind: String) -> Dictionary:
	var deadline: int = Time.get_ticks_msec() + 15000
	while Time.get_ticks_msec() < deadline:
		_controller.pump()
		for index in _terminal.size():
			if _terminal[index].result.kind == kind:
				var item: Dictionary = _terminal[index]
				_terminal.remove_at(index)
				var succeeded: bool = item.result.state in ["read","committed","no_change"]
				_host.check(succeeded, "player_journey_actual_"+kind+"_success")
				if not succeeded:
					return {}
				return item.result
		if not _refusals.is_empty():
			_host.check(false,"player_journey_unexpected_intent_refusal_"+kind)
			return {}
		await _host.get_tree().process_frame
	_host.check(false,"player_journey_timeout_"+kind)
	return {}

func _new_opening() -> int:
	_opening += 1
	return _opening

func _start() -> bool:
	_host.check(_controller.current_epoch() == 0 and _controller.selected_pair() == null, "player_journey_process_starts_guest_no_last_player_autoload")
	_controller.start_storage()
	var result: Dictionary = await _wait_kind("start")
	return not result.is_empty()

func _list() -> Dictionary:
	_controller.open_players(_new_opening(),_controller.current_epoch())
	return await _wait_kind("list_players")

func _load(id: String) -> Dictionary:
	_controller.choose_player(_new_opening(),_controller.current_epoch(),id)
	return await _wait_kind("load_player")

func _check_selected(id: String, name: String, revision: String, seed: Dictionary) -> void:
	var pair: Variant = _controller.selected_pair()
	_host.check(pair != null and pair.player.id == id and pair.player.name == name and pair.player.revision == revision and pair.preferences.revision == revision, "player_journey_selected_identity_and_paired_revision")
	if pair == null:
		return
	_host.check(Options.exact_equal(Options.seed_from_preferences(pair.preferences),seed), "player_journey_committed_seed_exact_types_bits_and_nulls")
	pair.player.name = "Mutation outside"
	pair.preferences.audio.engine_gain = 0.75
	var again: Dictionary = _controller.selected_pair()
	_host.check(again.player.name == name and Options.exact_equal(Options.seed_from_preferences(again.preferences),seed), "player_journey_selected_getter_recursively_owned")

func _close(service: RefCounted) -> void:
	_controller.begin_close()
	var deadline: int = Time.get_ticks_msec()+15000
	while not _closed and Time.get_ticks_msec() < deadline:
		_controller.pump()
		await _host.get_tree().process_frame
	_host.check(_closed, "player_journey_storage_closed_signal_after_join_and_drain")
	var status: Dictionary = service.status()
	var joined: bool = status.state == "closed" and status.pending == 0 and status.undelivered == 0 and not status.writer_alive and service.try_join()
	_host.check(joined, "player_journey_actual_closed_empty_joined_service")
	_host.check(_refusals.is_empty(), "player_journey_no_unexpected_refusals")
	if joined:
		_controller = null
	else:
		# Actual lifetime stays owned. Root's runner must remain alive; a timeout
		# is evidence of failure, never permission to destruct an unjoined writer.
		_retained = service

func run_first(host: Node, service: RefCounted) -> Dictionary:
	if not _prepare(host,service):
		return {}
	if not await _start():
		await _close(service)
		return {}
	var listed: Dictionary = await _list()
	if listed.is_empty():
		await _close(service)
		return {}
	host.check(listed.value.players.is_empty(), "player_journey_first_launch_owned_store_empty")
	_controller.create_player(_opening,_controller.current_epoch(),"Alpha")
	var created: Dictionary = await _wait_kind("create_player")
	if created.is_empty():
		await _close(service)
		return {}
	var a: String = created.value.player.id
	_check_selected(a,"Alpha","1",_seed())
	host.check(_controller.save_state() == {"dirty":false,"pending":false,"unknown":false}, "player_journey_defaults_untouched_null_clean")
	var first_seed: Dictionary = _seed(_negative_zero(),1.0)
	_controller.current_options_changed(first_seed)
	_controller.save_snapshot(_new_opening(),_controller.current_epoch(),first_seed,_utc())
	host.check(_controller.save_state().pending, "player_journey_admitted_snapshot_pending_is_not_saved")
	# Admission has copied the submitted negative-zero snapshot. The live edit is
	# made before any controller poll and must survive that earlier Save ACK.
	var final_seed: Dictionary = _seed(0.5,_negative_zero())
	_controller.current_options_changed(final_seed)
	first_seed.audio.engine_gain = 0.25
	var saved: Dictionary = await _wait_kind("save_preferences")
	if saved.is_empty():
		await _close(service)
		return {}
	_check_selected(a,"Alpha","2",_seed(_negative_zero(),1.0))
	host.check(_controller.save_state() == {"dirty":true,"pending":false,"unknown":false}, "player_journey_later_edit_stays_dirty_after_snapshot_ack")
	_controller.save_snapshot(_new_opening(),_controller.current_epoch(),final_seed,_utc())
	_controller.choose_guest(_new_opening(),_controller.current_epoch())
	var guest_epoch: int = _controller.current_epoch()
	host.check(_controller.selected_pair() == null, "player_journey_guest_adopts_before_old_player_ack")
	saved = await _wait_kind("save_preferences")
	host.check(not saved.is_empty() and _controller.selected_pair() == null and _controller.current_epoch() == guest_epoch and _controller.save_state() == {"dirty":false,"pending":false,"unknown":false}, "player_journey_old_player_ack_does_not_reselect_or_dirty_guest")
	await _load(a)
	_check_selected(a,"Alpha","3",final_seed)
	_controller.create_player(_new_opening(),_controller.current_epoch(),"Bravo")
	created = await _wait_kind("create_player")
	if created.is_empty():
		await _close(service)
		return {}
	var b: String = created.value.player.id
	host.check(a != b, "player_journey_native_created_distinct_player_ids")
	_check_selected(b,"Bravo","1",_seed())
	_controller.current_options_changed(_seed(0.125,0.75))
	_controller.choose_guest(_new_opening(),_controller.current_epoch())
	await _load(a)
	_check_selected(a,"Alpha","3",final_seed)
	await _load(b)
	_check_selected(b,"Bravo","1",_seed())
	# Independent expected seeds/revisions above, with opaque native-generated
	# IDs retained solely to address the same records in Root's fresh launch.
	# JSON crosses processes only with bit strings, never numeric gains that
	# could lose -0.0 or turn FLOAT into INT during parsing.
	var expected: Dictionary = {"a_id":a,"b_id":b,"a_name":"Alpha","b_name":"Bravo","a_revision":"3","b_revision":"1","a_engine_bits":"000000000000e03f","a_airflow_bits":"0000000000000080","b_engine_bits":"000000000000f03f","b_airflow_bits":"000000000000f03f"}
	await _close(service)
	return expected

func run_resume(host: Node, service: RefCounted, expected: Dictionary) -> Dictionary:
	if not _prepare(host,service):
		return {}
	if not await _start():
		await _close(service)
		return {}
	var listed: Dictionary = await _list()
	if listed.is_empty():
		await _close(service)
		return {}
	host.check(listed.value.players.size() == 2, "player_journey_second_process_same_store_two_players")
	await _load(expected.a_id)
	_check_selected(expected.a_id,expected.a_name,expected.a_revision,_seed(String(expected.a_engine_bits).hex_decode().decode_double(0),String(expected.a_airflow_bits).hex_decode().decode_double(0)))
	_controller.choose_guest(_new_opening(),_controller.current_epoch())
	await _load(expected.b_id)
	_check_selected(expected.b_id,expected.b_name,expected.b_revision,_seed(String(expected.b_engine_bits).hex_decode().decode_double(0),String(expected.b_airflow_bits).hex_decode().decode_double(0)))
	await _close(service)
	return {"scope":"actual_native_second_process_reopen","native_persistence_exercised":true}
