extends RefCounted
# Original MIT. Root owns callback identity and pumps this owner-thread producer.
# This controller never constructs a native service, chooses a root or calls flight.
const Options = preload("res://ui/profiles/player_options.gd")
const MAX_GENERATION = 9223372036854775807
const Values = preload("res://replay/observed/values.gd")
const U64 = preload("res://simulation/uint64.gd")
const Tick = preload("res://replay/observed/tick_math.gd")
const NativeIdentity = preload("res://build/native_identity.gd")
const Facade = preload("res://simulation/session_facade.gd")
const Worlds = preload("res://world/world_admission.gd")
const ADMISSION_ERRORS = ["wrong_thread","invalid_state","invalid_request","invalid_type","invalid_record","payload_limit","queue_full","out_of_memory"]
const TERMINAL_ERRORS = ["not_found","identity_conflict","revision_conflict","source_mismatch","tick_regression","invalid_transition","player_limit","history_limit","active_practice","counter_exhausted","store_locked","root_unavailable","unsupported_version","foreign_store","corrupt_store","recovery_required","recovery_limit","snapshot_failed","storage_full","busy","io_error","worker_lost","commit_unknown","verification_failed"]

signal storage_changed(status: Dictionary)
signal players_changed(opening: int, epoch: int, players: Array)
signal selection_candidate(opening: int, epoch: int, pair: Variant)
signal selection_changed(epoch: int, pair: Variant)
signal options_changed(epoch: int, committed_preferences: Variant, dirty: bool, pending: bool, unknown: bool)
signal operation_finished(opening: int, epoch: int, result: Dictionary)
signal intent_refused(opening: int, epoch: int, kind: String, reason: String, admission: Variant)
signal history_exit_resolved(epoch: int, saved: bool)
signal archive_link_changed(practice_id: String, state: Dictionary)
signal storage_closed()

var _service: RefCounted
var _started: bool = false
var _service_generation: int = 0
var _closing: bool = false
var _pumping: bool = false
var _protocol_fault: bool = false
var _status: Dictionary = {}
var _requests: Dictionary = {}
var _request_order: Array[String] = []
var _openings: Dictionary = {}
var _highest_opening: int = 0
var _epoch: int = 0
var _selected: Variant = null
var _active_seed: Dictionary = Options.default_seed()
# Values are only whole validated actual read/commit results, keyed by player ID.
var _ledger: Dictionary = {}
var _unknown_players: Dictionary = {}
var _reload_players: Dictionary = {}
var _candidate: Dictionary = {}
var _management: bool = false
var _next_management: bool = false
var _replacement_requested: bool = false
var _practice: Dictionary = {}
var _practice_cache: Dictionary = {}
# A verified file is not a durable association ACK. Retain its original owner
# and source until one ordinary mutation settles; never replay a failed intent.
var _archive_links: Dictionary = {}
var _history_barrier_epoch: int = -1

# Root-only copied views. These never construct a service or authorize callbacks.
func current_epoch() -> int:
	return _epoch

func selected_pair() -> Variant:
	return _copy(_selected)

func current_status() -> Dictionary:
	return _status.duplicate(true)

func save_state() -> Dictionary:
	var pending: bool = false
	if _selected != null:
		for route in _requests.values():
			if route.kind == "save_preferences" and route.player_id == _selected.player.id and route.epoch == _epoch:
				pending = true
	return {"dirty":_selected != null and not Options.exact_equal(_active_seed, Options.seed_from_preferences(_selected.preferences)),
		"pending":pending,"unknown":_selected != null and (_unknown_players.has(_selected.player.id) or _protocol_fault)}

func history_exit_pending() -> bool:
	return (not _practice.is_empty() and _practice.closed and not _practice.resolved) or _archive_links_unresolved()

func current_practice_context() -> Dictionary:
	if _practice.is_empty():
		return {}
	return {"practice_id":_practice.id,"source":_practice.source.duplicate(true),"player_id":_practice.player_id}

func replacement_requested() -> bool:
	return _replacement_requested

func management_requested() -> bool:
	return _next_management

func history_state() -> Dictionary:
	# Compact UI truth, never a durable Practice substitute.
	var state: Dictionary = {"active":false,"pending":false,"failed":false,"resolved":true}
	if not _practice.is_empty():
		state = {"active":not _practice.closed,"pending":_practice.inflight,"failed":_practice.failed,"resolved":_practice.resolved}
	for intent in _archive_links.values():
		if not intent.resolved:
			state.resolved = false
			state.pending = state.pending or intent.state == "inflight"
			state.failed = state.failed or intent.state in ["failed","unknown"]
	for route in _requests.values():
		if route.kind == "link_archive": state.pending = true
	return state

func attach_service(service: RefCounted) -> bool:
	if not _owner() or _service != null or service == null or _service_generation >= MAX_GENERATION:
		return false
	# A script subclass/mock must not impersonate the native persistence object.
	if service.get_script() != null or service.get_class() not in ["LocalPlayers", "LocalPlayersTest"]:
		return false
	if not ClassDB.class_exists(service.get_class()):
		return false
	var actual: Variant = service.call("status")
	if not _valid_status(actual) or actual.state != "new" or actual.pending != 0 or actual.undelivered != 0 or actual.writer_alive:
		return false
	_service = service
	_replacement_requested = false
	_service_generation += 1
	_started = false
	_closing = false
	_protocol_fault = false
	_status = actual.duplicate(true)
	storage_changed.emit(_status.duplicate(true))
	selection_changed.emit(_epoch, _copy(_selected))
	_emit_options()
	return true

func start_storage() -> void:
	if not _owner():
		return
	if _service == null or _started or _closing or _protocol_fault:
		_refuse(0, _epoch, "start", "local_guard")
		return
	_started = true
	_management = _next_management
	_admit("start_management" if _management else "start", {}, 0, _epoch, "", "", {}, true)

func open_players(opening: int, epoch: int) -> void:
	if not _owner():
		return
	if not _bind_intent(opening, epoch):
		_refuse(opening, epoch, "list_players", "local_guard")
		return
	for route in _requests.values():
		if route.kind == "list_players" and route.opening == opening:
			_refuse(opening, epoch, "list_players", "local_busy")
			return
	if _available(opening, epoch, "list_players"):
		_admit("list_players", {}, opening, epoch)

func retire_opening(opening: int) -> void:
	if not _owner():
		return
	_openings.erase(opening)
	if not _candidate.is_empty() and _candidate.opening == opening:
		_candidate.clear()
	# Accepted requests remain associated and must drain, even for retired pages.

func choose_player(opening: int, epoch: int, player_id: String) -> void:
	if not _available(opening, epoch, "load_player"):
		return
	if not Options.id_valid(player_id) or _epoch >= MAX_GENERATION or (_unknown_players.has(player_id) and _unknown_players[player_id] >= _service_generation):
		_refuse(opening, epoch, "load_player", "local_guard")
		return
	if _selection_busy():
		_refuse(opening, epoch, "load_player", "local_busy")
		return
	_admit("load_player", {"player_id":player_id}, opening, epoch, player_id)

func choose_guest(opening: int, epoch: int) -> void:
	if not _owner() or not _bind_intent(opening, epoch) or _epoch >= MAX_GENERATION or _closing:
		_refuse(opening, epoch, "choose_guest", "local_guard")
		return
	if _selection_busy():
		_refuse(opening, epoch, "choose_guest", "local_busy")
		return
	_offer(opening, epoch, null)

func create_player(opening: int, epoch: int, name: String) -> void:
	if not _available(opening, epoch, "create_player", true):
		return
	if not Options.name_valid(name) or _epoch >= MAX_GENERATION:
		_refuse(opening, epoch, "create_player", "local_guard")
		return
	if _selection_busy():
		_refuse(opening, epoch, "create_player", "local_busy")
		return
	var bytes: PackedByteArray = Crypto.new().generate_random_bytes(16)
	var utc: String = Time.get_datetime_string_from_system(true, false) + "Z"
	if bytes.size() != 16 or not Options.utc_valid(utc):
		_refuse(opening, epoch, "create_player", "local_guard")
		return
	var id: String = bytes.hex_encode()
	_admit("create_player", {"id":id,"name":name,"utc":utc}, opening, epoch, id)

func rename_player(opening: int, epoch: int, name: String) -> void:
	if not _available(opening, epoch, "rename_player", true):
		return
	if _selected == null or not Options.name_valid(name) or _needs_reconcile():
		_refuse(opening, epoch, "rename_player", "local_guard")
		return
	if _bundle_busy(_selected.player.id):
		_refuse(opening, epoch, "rename_player", "local_busy")
		return
	var utc: String = Time.get_datetime_string_from_system(true, false) + "Z"
	if not Options.utc_valid(utc):
		_refuse(opening, epoch, "rename_player", "local_guard")
		return
	_admit("rename_player", {"player_id":_selected.player.id,"expected_revision":_selected.player.revision,"name":name,"utc":utc}, opening, epoch, _selected.player.id, _selected.player.revision, Options.seed_from_preferences(_selected.preferences))

func finish_selection(opening: int, epoch: int, adopted: bool) -> void:
	if not _owner() or not _live(opening, epoch) or _candidate.is_empty() or _candidate.opening != opening or _candidate.epoch != epoch:
		return
	var pair: Variant = _candidate.pair
	_candidate.clear()
	if not adopted or _epoch >= MAX_GENERATION:
		return
	_selected = _copy(pair)
	if pair != null:
		_unknown_players.erase(pair.player.id)
		_reload_players.erase(pair.player.id)
	_active_seed = Options.default_seed() if pair == null else Options.seed_from_preferences(pair.preferences)
	_epoch += 1
	# All previous openings lose their selected-generation authority at once.
	_openings.clear()
	selection_changed.emit(_epoch, _copy(_selected))
	_emit_options()

func current_options_changed(seed: Dictionary) -> void:
	if not _owner():
		return
	var checked: Dictionary = Options.validate_seed(seed)
	if not checked.ok:
		return
	_active_seed = checked.value.duplicate(true)
	_emit_options()

func save_snapshot(opening: int, epoch: int, seed: Dictionary, utc: String) -> void:
	if not _available(opening, epoch, "save_preferences", true):
		return
	var checked: Dictionary = Options.validate_seed(seed)
	if _selected == null or not checked.ok or not Options.utc_valid(utc) or _needs_reconcile():
		_refuse(opening, epoch, "save_preferences", "local_guard")
		return
	if _bundle_busy(_selected.player.id):
		_refuse(opening, epoch, "save_preferences", "local_busy")
		return
	# This owned snapshot never aliases today's live controls or the caller's seed.
	var snapshot: Dictionary = checked.value.duplicate(true)
	_active_seed = snapshot.duplicate(true)
	_admit("save_preferences", {"player_id":_selected.player.id,"expected_revision":_selected.player.revision,"seed":snapshot,"utc":utc}, opening, epoch, _selected.player.id, _selected.player.revision, snapshot)
	_emit_options()

func begin_close() -> void:
	if not _owner() or _service == null or _closing:
		return
	if _service.call("begin_shutdown") == true:
		_closing = true
		if not _practice.is_empty() and not _practice.resolved:
			# Any accepted final receipt still drains. Unsent history cannot be
			# quietly replayed after shutdown; Root must resolve/acknowledge it.
			_practice.failed = true
		_candidate.clear()
		_openings.clear()
		_refresh_status()

func request_history(opening: int, epoch: int, before_creation_sequence: Variant) -> void:
	if not _available(opening, epoch, "list_practice"):
		return
	if _selected == null or before_creation_sequence != null and not Options.u64_valid(before_creation_sequence):
		_refuse(opening, epoch, "list_practice", "local_guard")
		return
	_admit("list_practice", {"player_id":_selected.player.id,"before_creation_sequence":before_creation_sequence,"limit":50}, opening, epoch, _selected.player.id, "", {}, false, {"cursor":before_creation_sequence})

func request_details(opening: int, epoch: int, practice_id: String) -> void:
	if not _available(opening, epoch, "load_practice"):
		return
	if _selected == null or not Options.id_valid(practice_id):
		_refuse(opening, epoch, "load_practice", "local_guard")
		return
	_admit("load_practice", {"player_id":_selected.player.id,"practice_id":practice_id}, opening, epoch, _selected.player.id, "", {}, false, {"practice_id":practice_id})

func request_prune(opening: int, epoch: int, practice_ids: Array) -> void:
	if not _available(opening, epoch, "prune_practice", true):
		return
	if _selected == null or not _ids_valid(practice_ids,50):
		_refuse(opening, epoch, "prune_practice", "local_guard")
		return
	_admit("prune_practice", {"player_id":_selected.player.id,"practice_ids":practice_ids.duplicate()}, opening, epoch, _selected.player.id, "", {}, false, {"ids":practice_ids.duplicate()})

func request_export(opening: int, epoch: int, target_absolute_path: String) -> void:
	if not _available(opening, epoch, "export_player"):
		return
	if _selected == null or not Options.path_valid(target_absolute_path) or _needs_reconcile():
		_refuse(opening, epoch, "export_player", "local_guard")
		return
	if _bundle_busy(_selected.player.id):
		_refuse(opening, epoch, "export_player", "local_busy")
		return
	_admit("export_player", {"player_id":_selected.player.id,"expected_revision":_selected.player.revision,"target_absolute_path":target_absolute_path}, opening, epoch, _selected.player.id, _selected.player.revision, {}, false, {"target":target_absolute_path})

func request_delete_player(opening: int, epoch: int) -> void:
	if not _available(opening, epoch, "delete_player", true):
		return
	if _selected == null or _needs_reconcile() or not _practice.is_empty() and not _practice.get("resolved",false) or _epoch >= MAX_GENERATION:
		_refuse(opening, epoch, "delete_player", "local_guard")
		return
	if _bundle_busy(_selected.player.id) or _selection_busy():
		_refuse(opening, epoch, "delete_player", "local_busy")
		return
	_admit("delete_player", {"player_id":_selected.player.id,"expected_revision":_selected.player.revision}, opening, epoch, _selected.player.id, _selected.player.revision)

func request_recovery(opening: int, epoch: int) -> void:
	if not _owner() or not _bind_intent(opening, epoch) or _service == null or not _started or _closing or _protocol_fault:
		_refuse(opening, epoch, "list_recovery", "local_guard")
		return
	_refresh_status()
	if _status.state not in ["ready","read_only","unavailable"]:
		_refuse(opening, epoch, "list_recovery", "local_guard")
		return
	_admit("list_recovery", {}, opening, epoch)

func request_delete_recovery(opening: int, epoch: int, snapshot_ids: Array) -> void:
	if not _owner() or not _live(opening,epoch) or not _ids_valid(snapshot_ids,2) or _service == null or _closing:
		_refuse(opening, epoch, "delete_recovery", "local_guard")
		return
	if not _management:
		# No deletion is queued/replayed. Root constructs the next actual service on
		# storage_closed; the user confirms deletion again in management mode.
		_next_management = true
		_replacement_requested = true
		_refuse(opening, epoch, "delete_recovery", "local_guard")
		begin_close()
		return
	_refresh_status()
	if _status.state != "unavailable" or _status.error_code != "" or _protocol_fault:
		_refuse(opening, epoch, "delete_recovery", "local_guard")
		return
	_admit("delete_recovery", {"snapshot_ids":snapshot_ids.duplicate()}, opening, epoch, "", "", {}, false, {"ids":snapshot_ids.duplicate()})

func request_reopen(opening: int, epoch: int) -> void:
	if not _owner() or not _live(opening,epoch) or _service == null or _closing:
		_refuse(opening, epoch, "reopen", "local_guard")
		return
	_next_management = false
	_replacement_requested = true
	begin_close()

# Root calls only after fully successful native/mapper/recorder adoption. It
# supplies the source fields retained by Facade.start, never recording metadata.
func flight_adopted(source: Dictionary, readback: Dictionary, utc: String) -> void:
	if not _owner():
		return
	if _selected == null:
		if _practice.is_empty() or _practice.resolved:
			_practice.clear()
		return
	if not _practice.is_empty() and not _practice.get("resolved",false) and not (_practice.failed and not _practice.inflight and _practice.row == null and not _practice.closed and Options.exact_equal(_practice.source,source)):
		_refuse(0,_epoch,"begin_practice","local_busy")
		return
	if not _practice.is_empty() and not _practice.resolved and _unknown_players.has(_practice.player_id):
		# Keep an uncertain begin's original ID/source for explicit read reconciliation.
		_refuse(0,_epoch,"begin_practice","local_guard")
		return
	if not Options.utc_valid(utc) or not _qualified_source(source,readback,true):
		_refuse(0,_epoch,"begin_practice","local_guard")
		return
	var bytes: PackedByteArray = Crypto.new().generate_random_bytes(16)
	if bytes.size() != 16:
		_refuse(0,_epoch,"begin_practice","local_guard")
		return
	_practice = {"id":bytes.hex_encode(),"player_id":_selected.player.id,"epoch":_epoch,
		"source":source.duplicate(true),"first_tick":readback.tick,"last_tick":readback.tick,
		"started_utc":utc,"utc":utc,"row":null,"inflight":false,"failed":false,
		"closed":false,"resolved":false,"end":null,"archive":null,"reconciled":false,"failed_generation":0,"unknown":false}
	if _service == null or _management or _closing or _protocol_fault or _needs_reconcile() or _status.get("state","") != "ready":
		_practice.failed = true
		_refuse(0,_epoch,"begin_practice","local_guard")
		return
	_drive_practice()

func flight_observed(readback: Dictionary, utc: String) -> void:
	if not _owner() or _practice.is_empty() or _practice.closed or _practice.resolved:
		return
	if not Options.utc_valid(utc) or not _qualified_source(_practice.source,readback,true) or U64.compare(readback.tick,_practice.last_tick) < 0:
		_refuse(0,_practice.epoch,"observe_practice","local_guard")
		return
	# Only unsent observations coalesce; an admitted request remains immutable.
	_practice.last_tick = readback.tick
	_practice.utc = utc
	_drive_practice()

func flight_closed(readback: Dictionary, end_reason: String, utc: String) -> void:
	if not _owner():
		return
	if _practice.is_empty() or _practice.resolved:
		# Guest has no durable history and no fabricated successful end receipt.
		_history_barrier_epoch = _epoch
		_finish_history_barrier(false)
		return
	if _practice.closed and not (_practice.failed and _practice.reconciled and not _practice.inflight):
		return
	if end_reason not in ["user_end","user_restart","user_quit","native_terminal"] or not Options.utc_valid(utc) or not _matching_closed_lifecycle(readback):
		_refuse(0,_practice.epoch,"end_practice","local_guard")
		return
	_history_barrier_epoch = _epoch
	if not _qualified_source(_practice.source,readback,false) or U64.compare(readback.tick,_practice.last_tick) < 0:
		# Root calls only with the owned successful Facade.close result, after
		# actual join. Matching closed lifecycle permits a truthful not-saved
		# escape; it does not qualify a missing/regressing endpoint. Preserve all
		# last acknowledged ticks/row/source and submit no guessed DB end.
		_practice.closed = true
		_practice.failed = true
		_practice.reconciled = false
		_practice.end = null
		_refuse(0,_practice.epoch,"end_practice","local_guard")
		return
	# Root has observed actual successful Facade.close join before this call.
	_practice.closed = true
	if _practice.reconciled:
		# Only this explicit qualified lifecycle call retries after a reconciled read.
		_practice.failed = false
		_practice.reconciled = false
	_practice.last_tick = readback.tick
	_practice.utc = utc
	_practice.end = {"status":"source_ended" if end_reason == "native_terminal" else "manually_ended","end_reason":end_reason}
	_drive_practice()

func acknowledge_history_not_saved(opening: int, epoch: int) -> void:
	var state: Dictionary = history_state()
	if not _owner() or not _bind_intent(opening,epoch) or _history_barrier_epoch < 0 or not state.failed or state.pending:
		_refuse(opening,epoch,"end_practice","local_guard")
		return
	for route in _requests.values():
		if route.kind in ["begin_practice","observe_practice","end_practice","link_archive"]:
			_refuse(opening,epoch,"end_practice","local_busy")
			return
	if not _practice.is_empty():
		if not _practice.closed:
			_refuse(opening,epoch,"end_practice","local_guard")
			return
		_practice.resolved = true
	for id in _archive_links.keys():
		if not _archive_links[id].resolved:
			_set_archive_link(id,"failed","Explicitly continued without a saved association",true)
	_finish_history_barrier(false)

func archive_link_state(practice_id: String) -> Dictionary:
	if not _archive_links.has(practice_id): return {}
	var intent: Dictionary = _archive_links[practice_id]
	return {"practice_id":practice_id,"payload_sha256":intent.archive.payload_sha256,"state":intent.state,"error":intent.error}

func archive_saved(practice_id: String, archive: Dictionary) -> Dictionary:
	var refused: Dictionary = {"practice_id":practice_id,"payload_sha256":archive.get("payload_sha256",""),"state":"failed","error":"Association rejected; file remains saved"}
	if not _owner() or not Options.id_valid(practice_id): return refused
	var retained: Dictionary = {}
	if not _practice.is_empty() and _practice.id == practice_id:
		# This window comes only from qualified actual flight observations/close.
		retained = {"source":_practice.source,"player_id":_practice.player_id,"first_tick":_practice.first_tick,"last_tick":_practice.last_tick}
	elif _practice_cache.has(practice_id): retained = _practice_cache[practice_id]
	if retained.is_empty() or not Options.archive_valid(archive,retained.source) or U64.compare(archive.first_tick,retained.first_tick) < 0 or U64.compare(archive.last_tick,retained.last_tick) > 0 or _service == null or _closing or _management or _protocol_fault:
		_refuse(0,_epoch,"link_archive","local_guard")
		return refused
	if _archive_links.has(practice_id):
		var previous: Dictionary = _archive_links[practice_id]
		if Options.exact_equal(previous.archive,archive): return archive_link_state(practice_id)
		if not previous.resolved:
			refused.error = "A different verified file association is still unresolved"
			_refuse(0,_epoch,"link_archive","local_busy")
			return refused
	# Keep at most sixteen unresolved owned intents; resolved receipts are copied
	# to Scene, and may be retired here without changing a durable Practice row.
	for id in _archive_links.keys():
		if _archive_links[id].resolved: _archive_links.erase(id)
	if _archive_links.size() >= 16:
		_refuse(0,_epoch,"link_archive","local_busy")
		return refused
	_archive_links[practice_id] = {"player_id":retained.player_id,"source":retained.source.duplicate(true),"archive":archive.duplicate(true),"state":"pending_endpoint","error":"","resolved":false}
	_set_archive_link(practice_id,"pending_endpoint","")
	_drive_archive_links()
	return archive_link_state(practice_id)

func _archive_links_unresolved() -> bool:
	for intent in _archive_links.values():
		if not intent.resolved: return true
	return false

func _set_archive_link(id: String, state: String, error: String, resolved: bool = false) -> void:
	var intent: Dictionary = _archive_links[id]
	intent.state = state
	intent.error = error
	intent.resolved = resolved
	archive_link_changed.emit(id,archive_link_state(id))

func _finish_history_barrier(saved: bool) -> void:
	if _history_barrier_epoch < 0 or _archive_links_unresolved() or (not _practice.is_empty() and (not _practice.closed or not _practice.resolved)): return
	var epoch: int = _history_barrier_epoch
	_history_barrier_epoch = -1
	history_exit_resolved.emit(epoch,saved)

func _drive_archive_links() -> void:
	for id in _archive_links.keys():
		var intent: Dictionary = _archive_links[id]
		if intent.resolved or intent.state in ["inflight","failed","unknown"]: continue
		if _service == null or _closing or _management or _protocol_fault or _status.get("state","") in ["read_only","unavailable","closed"] or _unknown_players.has(intent.player_id) or _reload_players.has(intent.player_id) or (not _practice.is_empty() and _practice.id == id and _practice.failed):
			_set_archive_link(id,"failed","Association was not submitted; history/storage requires explicit resolution")
			continue
		if _status.get("state","") != "ready" or _status.get("pending",0) != 0: continue
		var busy: bool = false
		for route in _requests.values():
			if route.context.get("practice_id","") == id: busy = true
		if busy or not _practice_cache.has(id): continue
		var row: Dictionary = _practice_cache[id]
		if row.player_id != intent.player_id or not Options.exact_equal(row.source,intent.source) or U64.compare(intent.archive.first_tick,row.first_tick) < 0:
			_set_archive_link(id,"failed","Acknowledged Practice source/window does not match the retained file")
			continue
		if U64.compare(intent.archive.last_tick,row.last_tick) > 0: continue
		_set_archive_link(id,"pending","")
		# Exactly one attempt against the latest actual acknowledged revision.
		if _admit("link_archive",{"practice_id":id,"player_id":intent.player_id,"expected_revision":row.revision,"expected_source":intent.source.duplicate(true),"archive":intent.archive.duplicate(true)},0,_epoch,intent.player_id,row.revision,{},false,{"practice_id":id,"source":intent.source.duplicate(true),"archive":intent.archive.duplicate(true)}):
			_set_archive_link(id,"inflight","")
		else: _set_archive_link(id,"failed","Association admission was rejected; no automatic retry")

func pump() -> void:
	if not _owner() or _service == null or _pumping:
		return
	_pumping = true
	_refresh_status()
	# Sole poll owner. Closed services can still hold accepted terminal receipts.
	var batch: Variant = _service.call("poll", 16)
	if not batch is Array or batch.size() > 16:
		_protocol_fault = true
	else:
		for result in batch:
			_receive(result)
	_refresh_status()
	if not _practice.is_empty() and not _practice.resolved and not _practice.inflight and _status.get("state","") in ["read_only","unavailable","closed"]:
		_practice.failed = true
	_drive_practice()
	if _protocol_fault:
		for id in _archive_links.keys():
			if _archive_links[id].state == "inflight": _set_archive_link(id,"unknown","Storage protocol failed; association status is unknown")
	_drive_archive_links()
	if _closing and _service.call("try_join") == true:
		_refresh_status()
		if _requests.is_empty() and not _status.is_empty() and _status.state == "closed" and _status.pending == 0 and _status.undelivered == 0 and not _status.writer_alive:
			# Retire the actual joined/drained binding before notifying Root.
			_service = null
			_pumping = false
			storage_closed.emit()
			return
	_pumping = false

func _available(opening: int, epoch: int, kind: String, write: bool = false) -> bool:
	if not _owner():
		return false
	if not _bind_intent(opening, epoch) or _service == null or not _started or _closing or _protocol_fault:
		_refuse(opening, epoch, kind, "local_guard")
		return false
	_refresh_status()
	if _status.is_empty() or _status.state not in (["ready"] if write else ["ready","read_only"]):
		_refuse(opening, epoch, kind, "local_guard")
		return false
	return true

func _admit(kind: String, payload: Dictionary, opening: int, epoch: int, player_id: String = "", revision: String = "", snapshot: Dictionary = {}, start: bool = false, context: Dictionary = {}) -> bool:
	if _requests.size() >= 16:
		_refuse(opening, epoch, kind, "local_busy")
		return false
	var admission: Variant = _service.call(kind) if start else _service.call("submit", {"kind":kind,"payload":payload.duplicate(true)})
	if not _valid_admission(admission):
		_protocol_fault = true
		return false
	if not admission.accepted:
		_refuse(opening, epoch, kind, "native_rejected", admission)
		return false
	if _requests.has(admission.request_id):
		_protocol_fault = true
		return false
	_requests[admission.request_id] = {"kind":kind,"opening":opening,"epoch":epoch,"player_id":player_id,"revision":revision,"snapshot":snapshot.duplicate(true),"context":context.duplicate(true),"service_generation":_service_generation}
	_request_order.append(admission.request_id)
	_refresh_status()
	return true

func _receive(raw: Variant) -> void:
	if not Options.closed(raw, ["request_id","kind","state","error_code","commit_sequence","value"]) or not Options.id_valid(raw.request_id) or not _requests.has(raw.request_id) or _request_order.is_empty() or _request_order[0] != raw.request_id:
		_protocol_fault = true
		return
	var route: Dictionary = _requests[raw.request_id]
	_requests.erase(raw.request_id)
	_request_order.pop_front()
	if not _valid_terminal(raw, route.kind):
		_protocol_fault = true
		return
	var result: Dictionary = raw.duplicate(true)
	var success: bool = result.state in ["read","committed","no_change"]
	if success and route.kind == "start" and not _valid_start(result.value):
		_protocol_fault = true
		return
	if success and route.kind == "start_management" and (not Options.closed(result.value,["management_only"]) or typeof(result.value.management_only) != TYPE_BOOL or not result.value.management_only):
		_protocol_fault = true
		return
	if result.state == "uncertain" and not route.player_id.is_empty():
		_unknown_players[route.player_id] = _service_generation
	if result.error_code == "revision_conflict" and not route.player_id.is_empty():
		_reload_players[route.player_id] = true
	if success and route.kind in ["create_player","load_player","rename_player","save_preferences"]:
		var checked: Dictionary = Options.validate_pair(result.value)
		if not checked.ok or checked.value.player.id != route.player_id:
			_protocol_fault = true
			return
		var pair: Dictionary = checked.value
		if route.kind == "create_player" and (pair.player.revision != "1" or not Options.exact_equal(Options.seed_from_preferences(pair.preferences), Options.default_seed())):
			_protocol_fault = true
			return
		if route.kind in ["save_preferences","rename_player"] and (pair.player.revision != (route.revision if result.state == "no_change" else Options.next_u64(route.revision)) or not Options.exact_equal(Options.seed_from_preferences(pair.preferences), route.snapshot)):
			_protocol_fault = true
			return
		_ledger[route.player_id] = pair.duplicate(true)
		if route.kind in ["create_player","load_player"]:
			if _live(route.opening, route.epoch) and _candidate.is_empty():
				_offer(route.opening, route.epoch, pair)
		elif _selected != null and _selected.player.id == route.player_id and _epoch == route.epoch:
			# ACK updates committed truth but never overwrites edits made meanwhile.
			_selected = pair.duplicate(true)
			_unknown_players.erase(route.player_id)
			_reload_players.erase(route.player_id)
			selection_changed.emit(_epoch, _selected.duplicate(true))
	if success and route.kind == "list_players":
		if not _valid_players(result.value):
			_protocol_fault = true
			return
		if _live(route.opening, route.epoch):
			players_changed.emit(route.opening, route.epoch, result.value.players.duplicate(true))
	if not _settle_extra(result,route,success):
		_protocol_fault = true
		return
	_emit_options()
	# Route even stale actual terminals. Root suppresses presentation by registry;
	# controller has already settled their original player's ledger exactly once.
	operation_finished.emit(route.opening, route.epoch, result.duplicate(true))

func _offer(opening: int, epoch: int, pair: Variant) -> void:
	_candidate = {"opening":opening,"epoch":epoch,"pair":_copy(pair)}
	# Root must synchronously adopt and finish_selection; a signal alone is not ACK.
	selection_candidate.emit(opening, epoch, _copy(pair))

func _emit_options() -> void:
	var preferences: Variant = null if _selected == null else _selected.preferences.duplicate(true)
	var state: Dictionary = save_state()
	options_changed.emit(_epoch, preferences, state.dirty, state.pending, state.unknown)

func _refresh_status() -> void:
	if _service == null:
		return
	var actual: Variant = _service.call("status")
	if not _valid_status(actual):
		_protocol_fault = true
		return
	if not Options.exact_equal(_status, actual):
		_status = actual.duplicate(true)
		storage_changed.emit(_status.duplicate(true))

func _selection_busy() -> bool:
	if _archive_links_unresolved(): return true
	if not _practice.is_empty() and not _practice.get("resolved",false):
		return true
	if not _candidate.is_empty():
		return true
	for route in _requests.values():
		if route.kind in ["create_player","load_player"]:
			return true
	return false

func _bundle_busy(id: String) -> bool:
	for route in _requests.values():
		if route.player_id == id and route.kind in ["rename_player","save_preferences","delete_player"]:
			return true
	return false

func _needs_reconcile() -> bool:
	return _selected != null and (_unknown_players.has(_selected.player.id) or _reload_players.has(_selected.player.id))

func _live(opening: int, epoch: int) -> bool:
	return epoch == _epoch and _openings.has(opening) and _openings[opening] == epoch

func _bind_intent(opening: int, epoch: int) -> bool:
	# Only Root calls intents after its actual widget/Callable guard. This binds
	# fresh Controls/Audio/name openings without an extra native list request.
	if _live(opening, epoch):
		return true
	if epoch != _epoch or opening <= _highest_opening or opening <= 0 or opening >= MAX_GENERATION:
		return false
	_highest_opening = opening
	_openings[opening] = epoch
	return true

func _refuse(opening: int, epoch: int, kind: String, reason: String, admission: Variant = null) -> void:
	if _owner():
		intent_refused.emit(opening, epoch, kind, reason, _copy(admission))

func _owner() -> bool:
	return Thread.is_main_thread()

func _copy(value: Variant) -> Variant:
	return value.duplicate(true) if value is Dictionary or value is Array else value

func _valid_admission(value: Variant) -> bool:
	if not Options.closed(value, ["accepted","error_code","request_id"]) or typeof(value.accepted) != TYPE_BOOL or typeof(value.error_code) != TYPE_STRING:
		return false
	return value.error_code == "" and Options.id_valid(value.request_id) if value.accepted else value.error_code in ADMISSION_ERRORS and value.request_id == null

func _valid_status(value: Variant) -> bool:
	if not Options.closed(value, ["state","error_code","pending","undelivered","writer_alive","resolved_root","store_version"]):
		return false
	if typeof(value.state) != TYPE_STRING or value.state not in ["new","opening","ready","closing","closed","read_only","unavailable"] or typeof(value.error_code) != TYPE_STRING or (value.error_code != "" and value.error_code not in TERMINAL_ERRORS) or typeof(value.writer_alive) != TYPE_BOOL:
		return false
	if typeof(value.pending) != TYPE_INT or typeof(value.undelivered) != TYPE_INT or value.pending < 0 or value.undelivered < 0 or value.pending + value.undelivered > 16:
		return false
	return (value.resolved_root == null or typeof(value.resolved_root) == TYPE_STRING) and (value.store_version == null or typeof(value.store_version) == TYPE_INT and value.store_version == 1)

func _valid_terminal(value: Dictionary, kind: String) -> bool:
	if typeof(value.kind) != TYPE_STRING or value.kind != kind or typeof(value.state) != TYPE_STRING or typeof(value.error_code) != TYPE_STRING:
		return false
	if value.state in ["read","committed","no_change"]:
		if value.error_code != "":
			return false
		if value.state == "read":
			if value.commit_sequence != null:
				return false
		elif not Options.u64_valid(value.commit_sequence, false):
			return false
		var states: Dictionary = {"start":["read","committed"],"start_management":["read"],"list_players":["read"],"create_player":["committed","no_change"],"load_player":["read"],"rename_player":["committed","no_change"],"save_preferences":["committed","no_change"],"list_practice":["read"],"load_practice":["read"],"prune_practice":["committed"],"delete_player":["committed"],"export_player":["read"],"list_recovery":["read"],"delete_recovery":["read"],"begin_practice":["committed","no_change"],"observe_practice":["committed","no_change"],"end_practice":["committed","no_change"],"link_archive":["committed","no_change"]}
		return states.has(kind) and value.state in states[kind]
	if kind == "export_player":
		return value.state in ["failed","recovery_required"] and value.commit_sequence == null and value.error_code in TERMINAL_ERRORS + ["target_exists","path_rejected","file_create_failed","file_write_failed","file_flush_failed","file_verify_failed","file_recovery_required"] and value.value is Dictionary
	if kind == "delete_recovery" and value.state == "failed" and value.commit_sequence == null and value.error_code == "snapshot_failed" and value.value is Dictionary:
		return true
	if value.state not in ["failed","uncertain"] or value.commit_sequence != null or value.value != null or value.error_code not in TERMINAL_ERRORS:
		return false
	return value.state != "uncertain" or value.error_code in ["commit_unknown","verification_failed"]

func _valid_start(value: Variant) -> bool:
	return Options.closed(value, ["store_version","interrupted_rows","created"]) and typeof(value.store_version) == TYPE_INT and value.store_version == 1 and typeof(value.interrupted_rows) == TYPE_INT and value.interrupted_rows >= 0 and value.interrupted_rows <= 1 and typeof(value.created) == TYPE_BOOL

func _valid_players(value: Variant) -> bool:
	if not Options.closed(value, ["players"]) or not value.players is Array or value.players.size() > 8:
		return false
	var seen: Array = []
	for player in value.players:
		if not Options.closed(player, ["id","name","revision"]) or not Options.id_valid(player.id) or not Options.name_valid(player.name) or not Options.u64_valid(player.revision, false) or seen.has(player.id):
			return false
		seen.append(player.id)
	return true

func _ids_valid(value: Array, maximum: int) -> bool:
	if value.is_empty() or value.size() > maximum:
		return false
	var seen: Array = []
	for id in value:
		if not Options.id_valid(id) or seen.has(id):
			return false
		seen.append(id)
	return true

func _settle_extra(result: Dictionary, route: Dictionary, success: bool) -> bool:
	var value: Variant = result.value
	match route.kind:
		"list_practice":
			if not success:
				return true
			if not Options.closed(value,["practice","next_before_creation_sequence"]) or not value.practice is Array or value.practice.size() > 50:
				return false
			var previous: Variant = route.context.cursor
			var seen: Array = []
			for row in value.practice:
				if not Options.practice_valid(row,true) or row.player_id != route.player_id or seen.has(row.id) or previous != null and U64.compare(row.creation_sequence,previous) >= 0:
					return false
				previous = row.creation_sequence
				seen.append(row.id)
			var next: Variant = value.next_before_creation_sequence
			return next == null or Options.u64_valid(next) and not value.practice.is_empty() and next == value.practice.back().creation_sequence
		"load_practice":
			if not success:
				return true
			if not Options.closed(value,["practice"]) or not Options.practice_valid(value.practice) or value.practice.player_id != route.player_id or value.practice.id != route.context.practice_id:
				return false
			_cache_practice(value.practice)
			_reconcile_practice(value.practice,route.service_generation)
		"prune_practice":
			if success:
				if not Options.closed(value,["deleted_ids"]) or not value.deleted_ids is Array or not _same_ids(value.deleted_ids,route.context.ids):
					return false
				for id in value.deleted_ids:
					_practice_cache.erase(id)
					# Only the validated deletion ACK establishes that this unsent
					# association can no longer obtain its acknowledged Practice.
					# Accepted link routes retain their own terminal reduction.
					if _archive_links.has(id):
						var intent: Dictionary = _archive_links[id]
						var admitted: bool = false
						for pending_route in _requests.values():
							if pending_route.kind == "link_archive" and pending_route.context.get("practice_id","") == id: admitted = true
						if intent.player_id == route.player_id and not intent.resolved and intent.state in ["pending_endpoint","pending"] and not admitted:
							_set_archive_link(id,"failed","Practice was pruned before association submission; file remains saved")
		"delete_player":
			if success:
				if not Options.closed(value,["deleted_player_id"]) or typeof(value.deleted_player_id) != TYPE_STRING or value.deleted_player_id != route.player_id:
					return false
				_ledger.erase(route.player_id)
				for id in _practice_cache.keys():
					if _practice_cache[id].player_id == route.player_id:
						_practice_cache.erase(id)
				# Never delete or relabel external archives/Root's retained recording.
				if _selected != null and _selected.player.id == route.player_id and _epoch == route.epoch:
					_reload_players[route.player_id] = true
					if _live(route.opening,route.epoch):
						_offer(route.opening,route.epoch,null)
		"export_player":
			return _valid_export(result,route)
		"list_recovery":
			if success:
				if not Options.closed(value,["snapshots"]) or not value.snapshots is Array or value.snapshots.size() > 2:
					return false
				var ids: Array = []
				for row in value.snapshots:
					if not Options.closed(row,["bytes","created_utc","id","manifest_sha256","state"]) or not Options.id_valid(row.id) or ids.has(row.id) or typeof(row.bytes) != TYPE_INT or row.bytes < 0 or typeof(row.state) != TYPE_STRING or row.state not in ["complete","partial"] or row.created_utc != null and not Options.utc_valid(row.created_utc) or row.manifest_sha256 != null and not Options.hex_valid(row.manifest_sha256,64):
						return false
					ids.append(row.id)
		"delete_recovery":
			if value != null:
				if not Options.closed(value,["deleted_ids","retained_ids"]) or not value.deleted_ids is Array or not value.retained_ids is Array:
					return false
				var all: Array = value.deleted_ids + value.retained_ids
				if not _same_ids(all,route.context.ids) or success and not value.retained_ids.is_empty():
					return false
				if not success and value.retained_ids.is_empty():
					return false
		"begin_practice","observe_practice","end_practice","link_archive":
			return _settle_practice(result,route,success)
	return true

func _same_ids(left: Array, right: Array) -> bool:
	if left.size() != right.size() or not _ids_valid(left,50):
		return false
	for id in left:
		if not right.has(id):
			return false
	return true

func _valid_export(result: Dictionary, route: Dictionary) -> bool:
	var value: Variant = result.value
	if not Options.closed(value,["operation_id","outcome","phase","target_absolute_path","temporary_absolute_path","installed","bytes","sha256","player_id","preferences_revision","practice_count"]):
		return false
	if typeof(value.operation_id) != TYPE_STRING or value.operation_id != result.request_id or typeof(value.target_absolute_path) != TYPE_STRING or value.target_absolute_path != route.context.target or typeof(value.outcome) != TYPE_STRING or value.outcome not in ["saved","not_saved","recovery_required"] or typeof(value.phase) != TYPE_STRING or value.phase not in ["read","encode","create","write","flush","verify_temp","move","verify_target","done"]:
		return false
	if value.temporary_absolute_path != null and not Options.path_valid(value.temporary_absolute_path) or value.installed != null and typeof(value.installed) != TYPE_BOOL:
		return false
	if value.bytes != null and (typeof(value.bytes) != TYPE_INT or value.bytes < 0 or value.bytes > 33554432) or value.sha256 != null and not Options.hex_valid(value.sha256,64):
		return false
	if (value.bytes == null) != (value.sha256 == null):
		return false
	if value.player_id == null:
		if value.preferences_revision != null or value.practice_count != null:
			return false
	elif typeof(value.player_id) != TYPE_STRING or value.player_id != route.player_id or typeof(value.preferences_revision) != TYPE_STRING or value.preferences_revision != route.revision or typeof(value.practice_count) != TYPE_INT or value.practice_count < 0 or value.practice_count > 2000:
		return false
	match result.state:
		"read": return value.outcome == "saved" and value.phase == "done" and value.installed == true and value.temporary_absolute_path == null and value.bytes != null and value.player_id != null
		"failed": return value.outcome == "not_saved" and value.installed == false
		"recovery_required": return value.outcome == "recovery_required" and result.error_code == "file_recovery_required"
	return false

func _cache_practice(row: Dictionary) -> void:
	if _practice_cache.has(row.id) or _practice_cache.size() < 2000:
		_practice_cache[row.id] = row.duplicate(true)

func _qualified_source(source: Dictionary, readback: Dictionary, current: bool) -> bool:
	if not Options.source_valid(source) or source.source_variant != NativeIdentity.SOURCE_VARIANT or source.native_source_fingerprint != NativeIdentity.SOURCE_FINGERPRINT:
		return false
	var qualified: Dictionary = Values.qualify(readback)
	if not qualified.ok or qualified.kind != ("current" if current else "historical"):
		return false
	var world: Dictionary=Worlds.source(source.model_identity,source.named_start,source.prepared_world_sha256,readback.world_anchor)
	if not world.ok or (world.selector=="kawo-prototype-v1" and (source.wind_profile!="calm" or source.angular_integration_method!=null)):
		return false
	var wind: Array=Facade._nominal_wind(source.wind_profile)
	for axis in range(3):
		if wind.size()!=3 or absf(float(readback.atmosphere.wind_toward_ned_mps[["x","y","z"][axis]])-wind[axis])>1e-6:
			return false
	for key in ["session_id","model_identity","native_source_fingerprint","prepared_world_sha256","named_start"]:
		if not Options.exact_equal(source[key],readback[key]):
			return false
	return true

func _matching_closed_lifecycle(readback: Dictionary) -> bool:
	if typeof(readback.get("host_mode")) != TYPE_STRING or readback.host_mode != "closed" or typeof(readback.get("native_live")) != TYPE_BOOL or readback.native_live or typeof(readback.get("historical")) != TYPE_BOOL or not readback.historical:
		return false
	for key in ["session_id","model_identity","native_source_fingerprint","prepared_world_sha256","named_start"]:
		if not Options.exact_equal(_practice.source[key],readback.get(key)):
			return false
	return true

func _drive_practice() -> void:
	if not _owner() or _practice.is_empty() or _practice.resolved or _practice.failed or _practice.inflight or _service == null or _closing or _management or _protocol_fault:
		return
	if _status.is_empty() or _status.state != "ready":
		return
	# Wait for actual idle writer instead of racing its shared codec lease.
	if _status.pending != 0:
		return
	for route in _requests.values():
		if route.context.get("practice_id","") == _practice.id:
			return
	var kind: String = "begin_practice"
	var payload: Dictionary
	var context: Dictionary = {"practice_id":_practice.id,"source":_practice.source.duplicate(true)}
	var revision: String = ""
	if _practice.row == null:
		payload = {"seed":{"id":_practice.id,"player_id":_practice.player_id,
			"source":_practice.source.duplicate(true),"started_utc":_practice.started_utc,"first_tick":_practice.first_tick}}
		context["first_tick"] = _practice.first_tick
	else:
		revision = _practice.row.revision
		if _practice.end != null:
			kind = "end_practice"
		else:
			var delta: Dictionary = Tick.subtract(_practice.last_tick,_practice.row.last_tick)
			if not delta.ok or U64.compare(delta.value,"120") < 0:
				return
			kind = "observe_practice"
		payload = {"practice_id":_practice.id,"player_id":_practice.player_id,
			"expected_revision":revision,"expected_source":_practice.source.duplicate(true),
			"last_tick":_practice.last_tick,"utc":_practice.utc}
		context["last_tick"] = _practice.last_tick
		if kind == "end_practice":
			payload["status"] = _practice.end.status
			payload["end_reason"] = _practice.end.end_reason
			context["status"] = _practice.end.status
			context["end_reason"] = _practice.end.end_reason
	_practice.inflight = true
	if not _admit(kind,payload,0,_practice.epoch,_practice.player_id,revision,{},false,context):
		_practice.inflight = false
		_practice.failed = true

func _settle_practice(result: Dictionary, route: Dictionary, success: bool) -> bool:
	var bound: bool = not _practice.is_empty() and _practice.id == route.context.practice_id
	if route.kind != "link_archive" and not bound:
		return false
	if bound and route.kind != "link_archive":
		_practice.inflight = false
	if not success:
		if route.kind == "link_archive" and _archive_links.has(route.context.practice_id):
			_set_archive_link(route.context.practice_id,"unknown" if result.state == "uncertain" else "failed",String(result.error_code))
		if bound and route.kind != "link_archive":
			_practice.failed = true
			_practice.reconciled = false
			_practice.failed_generation = route.service_generation
			_practice.unknown = result.state == "uncertain"
		# No automatic replay after failure/unknown; Root sees the actual terminal.
		return true
	if not Options.closed(result.value,["practice"]) or not Options.practice_valid(result.value.practice):
		return false
	var row: Dictionary = result.value.practice
	if row.id != route.context.practice_id or row.player_id != route.player_id or not Options.exact_equal(row.source,route.context.source):
		return false
	if route.kind == "begin_practice":
		if row.first_tick != route.context.first_tick or row.status != "active" or row.revision != "1":
			return false
	else:
		if row.revision != (route.revision if result.state == "no_change" else Options.next_u64(route.revision)):
			return false
		if route.kind in ["observe_practice","end_practice"] and row.last_tick != route.context.last_tick:
			return false
		if route.kind == "observe_practice" and row.status != "active":
			return false
		if route.kind == "end_practice" and (row.status != route.context.status or row.end_reason != route.context.end_reason):
			return false
		if route.kind == "link_archive" and not Options.exact_equal(row.archive,route.context.archive):
			return false
	if route.kind == "link_archive":
		if not _archive_links.has(row.id) or _archive_links[row.id].state != "inflight" or not Options.exact_equal(_archive_links[row.id].archive,route.context.archive): return false
	_cache_practice(row)
	if route.kind == "link_archive":
		_set_archive_link(row.id,"saved","",true)
	if bound:
		_practice.row = row.duplicate(true)
		if route.kind == "end_practice":
			_practice.resolved = true
			_practice.failed = false
	_finish_history_barrier(true)
	return true

func _reconcile_practice(row: Dictionary, generation: int) -> void:
	# Only an explicit actual read can settle an uncertain mutation. The retained
	# same-process source/lifecycle binding is mandatory; rows never create one.
	if _practice.is_empty() or _practice.resolved or not _practice.failed or _practice.inflight or row.id != _practice.id or row.player_id != _practice.player_id or not Options.exact_equal(row.source,_practice.source) or row.first_tick != _practice.first_tick:
		return
	if _practice.unknown and generation <= _practice.failed_generation:
		return
	if U64.compare(row.last_tick,_practice.last_tick) > 0:
		return
	_practice.row = row.duplicate(true)
	_practice.unknown = false
	if row.status == "active":
		# Do not automatically replay the old observe/end. Root may explicitly
		# submit its retained actual closed endpoint after showing reconciliation.
		_practice.reconciled = true
		return
	if _practice.closed and _practice.end != null and row.last_tick == _practice.last_tick and row.status == _practice.end.status and row.end_reason == _practice.end.end_reason:
		_practice.resolved = true
		_practice.failed = false
		_finish_history_barrier(true)
