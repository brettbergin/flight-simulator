extends RefCounted
# Original MIT. No-service checks exercise actual controller guards/Guest only.
# No synthetic object is accepted as native storage.
const Controller = preload("res://persistence/local_players_controller.gd")
var _controller: RefCounted
var _events: Array = []
var _adopt: bool = false

func _candidate(opening: int, epoch: int, pair: Variant) -> void:
	_events.append(["candidate",opening,epoch,pair])
	_controller.finish_selection(opening,epoch,_adopt)

func _refused(opening: int, epoch: int, kind: String, reason: String, admission: Variant) -> void:
	_events.append(["refused",opening,epoch,kind,reason,admission])

func _storage(_status: Dictionary) -> void:
	_events.append(["storage"])

func _finished(_opening: int, _epoch: int, _result: Dictionary) -> void:
	_events.append(["finished"])

func run(host: Node) -> Dictionary:
	_controller = Controller.new()
	_controller.selection_candidate.connect(_candidate)
	_controller.intent_refused.connect(_refused)
	_controller.storage_changed.connect(_storage)
	_controller.operation_finished.connect(_finished)
	host.check(not _controller.attach_service(RefCounted.new()), "player_controller_refuses_non_native_service")
	host.check(_controller.current_status().is_empty() and _controller.selected_pair() == null and _controller.current_epoch() == 0, "player_controller_unbound_guest_no_fabricated_status")
	_controller.start_storage()
	host.check(_events == [["refused",0,0,"start","local_guard",null]], "player_controller_unbound_start_is_local_guard_not_native_result")
	_events.clear()
	_controller.choose_guest(1,0)
	host.check(_events == [["candidate",1,0,null]] and _controller.current_epoch() == 0, "player_controller_declined_guest_candidate_does_not_adopt")
	_adopt = true
	_events.clear()
	_controller.choose_guest(1,0)
	host.check(_events == [["candidate",1,0,null]] and _controller.current_epoch() == 1 and _controller.selected_pair() == null, "player_controller_synchronous_guest_adoption_advances_once")
	_controller.finish_selection(1,0,true)
	host.check(_controller.current_epoch() == 1, "player_controller_duplicate_candidate_ack_no_epoch_change")
	_events.clear()
	_controller.choose_guest(1,0)
	host.check(_events == [["refused",1,0,"choose_guest","local_guard",null]], "player_controller_old_epoch_cannot_choose")
	_events.clear()
	_controller.retire_opening(1)
	_controller.pump()
	host.check(_events.is_empty() and _controller.current_status().is_empty(), "player_controller_unbound_pump_has_no_storage_or_terminal")
	var state: Dictionary = _controller.save_state()
	state.dirty = true
	host.check(_controller.save_state() == {"dirty":false,"pending":false,"unknown":false}, "player_controller_guest_save_view_owned_and_not_persistent")
	_controller = null
	return {"scope":"no_service_controller_guards", "native_persistence_exercised":false}
