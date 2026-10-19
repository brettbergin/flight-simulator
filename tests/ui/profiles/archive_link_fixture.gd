extends "res://persistence/local_players_controller.gd"
# Synthetic owner-thread reducer fixture, NOT a persistence service/mock.
# No attach_service, status, submit, poll, filesystem or native lifecycle calls.
var captured: Array = []

func _admit(kind: String, payload: Dictionary, opening: int, epoch: int, player_id: String = "", revision: String = "", snapshot: Dictionary = {}, start: bool = false, context: Dictionary = {}) -> bool:
	var id: String = "synthetic-reducer-%d" % (captured.size() + 1)
	var route: Dictionary = {"kind":kind,"opening":opening,"epoch":epoch,"player_id":player_id,"revision":revision,"snapshot":snapshot.duplicate(true),"context":context.duplicate(true),"service_generation":0}
	captured.append({"id":id,"payload":payload.duplicate(true),"route":route.duplicate(true),"start":start})
	_requests[id] = route
	return true

func take() -> Dictionary:
	# Models only the already-reviewed _receive order: remove route before reduce.
	var last: Dictionary = captured.back()
	_requests.erase(last.id)
	return last.route.duplicate(true)
