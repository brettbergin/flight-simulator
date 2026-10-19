extends "res://player_tests/local_players_journey_runner.gd"
# Root-bound dedicated resource; inherits existing four-pair descriptor reader.
const Integrated = preload("res://player_tests/local_players_integrated_checks.gd")

func _run() -> void:
	_host = Host.new()
	root.add_child(_host)
	var descriptor: Variant = _descriptor()
	_host.check(ClassDB.class_exists("LocalPlayersTest") and ClassDB.class_exists("FlightInteractiveSession"),"players_integrated_both_actual_native_classes")
	_host.check(descriptor is Dictionary,"players_integrated_existing_descriptor")
	if not ClassDB.class_exists("LocalPlayersTest") or not ClassDB.class_exists("FlightInteractiveSession") or not descriptor is Dictionary:
		quit(1)
		return
	_service = ClassDB.instantiate("LocalPlayersTest")
	var configured: bool = _service.call("configure_test_root",descriptor) == true
	_host.check(configured,"players_integrated_existing_bound_capability_configures_once")
	if not configured:
		quit(1)
		return
	_journey = Integrated.new()
	var result: Dictionary = await _journey.run(_host,_service)
	var receipt: Dictionary = {"type":"LocalPlayersSceneIntegration","version":1,"checked":_host.checked,"failures":_host.failures,"result":result}
	var file: FileAccess = FileAccess.open("res://controller-integrated-result.json",FileAccess.WRITE)
	if file == null:
		_host.check(false,"players_integrated_output_failed")
	else:
		file.store_string(JSON.stringify(receipt))
		file.close()
	print(JSON.stringify(receipt))
	if result.get("retained",true):
		print("LOCAL_PLAYERS_INTEGRATED_RETAINED_UNJOINED")
		return
	var failed: bool = not _host.failures.is_empty()
	_service = null
	_journey = null
	_host.free()
	quit(1 if failed else 0)
