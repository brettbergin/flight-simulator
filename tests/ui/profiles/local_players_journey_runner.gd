extends SceneTree
# Dedicated source-bound test host. Root supplies exactly the existing native
# four context/descriptor argv pairs. No custom root/factory or phase arguments.
const Journey = preload("res://player_tests/local_players_journey_checks.gd")

class Host extends Node:
	var checked: int = 0
	var failures: Array[String] = []
	func check(condition: bool, name: String) -> void:
		checked += 1
		if not condition:
			failures.append(name)
			push_error(name)

var _service: RefCounted
var _journey: RefCounted
var _host: Node

func _phase() -> String:
	return "first"

func _initialize() -> void:
	call_deferred("_run")

func _read_json(path: String, cap: int) -> Variant:
	var file: FileAccess = FileAccess.open(path,FileAccess.READ)
	if file == null or file.get_length() < 1 or file.get_length() > cap:
		return null
	var raw: PackedByteArray = file.get_buffer(file.get_length())
	file.close()
	return JSON.parse_string(raw.get_string_from_utf8())

func _descriptor() -> Variant:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() != 8:
		return null
	var allowed: Array = ["--local-players-test-context","--local-players-test-context-sha256","--local-players-test-descriptor","--local-players-test-descriptor-sha256"]
	var values: Dictionary = {}
	for index in range(0,8,2):
		if args[index] not in allowed or values.has(args[index]):
			return null
		values[args[index]] = args[index+1]
	return _read_json(values["--local-players-test-descriptor"],16384)

func _write_result(expected: Dictionary, joined: bool) -> void:
	var result: Dictionary = {"type":"LocalPlayersControllerJourney","version":1,"phase":_phase(),"checked":_host.checked,"failures":_host.failures,"actual_joined":joined,"expected":expected}
	var path: String = "res://controller-" + _phase() + "-result.json"
	var file: FileAccess = FileAccess.open(path,FileAccess.WRITE)
	if file == null:
		_host.check(false,"player_journey_result_output_failed")
	else:
		file.store_string(JSON.stringify(result))
		file.close()
	print(JSON.stringify(result))

func _run() -> void:
	_host = Host.new()
	root.add_child(_host)
	_host.check(ClassDB.class_exists("LocalPlayersTest"),"player_journey_actual_test_class_registered")
	var descriptor: Variant = _descriptor()
	_host.check(descriptor is Dictionary,"player_journey_existing_bound_descriptor_read")
	if not ClassDB.class_exists("LocalPlayersTest") or not descriptor is Dictionary:
		_write_result({},false)
		quit(1)
		return
	_service = ClassDB.instantiate("LocalPlayersTest")
	var configured: bool = _service != null and _service.call("configure_test_root",descriptor) == true
	_host.check(configured,"player_journey_actual_bound_service_configured_once")
	if not configured:
		_write_result({},false)
		# Failed configuration never began a worker or accepted work.
		quit(1)
		return
	_journey = Journey.new()
	var expected: Dictionary = {}
	if _phase() == "first":
		expected = await _journey.run_first(_host,_service)
	else:
		var prior: Variant = _read_json("res://controller-first-result.json",16384)
		_host.check(prior is Dictionary and prior.get("actual_joined") == true and prior.get("failures") == [] and prior.get("expected") is Dictionary,"player_journey_first_process_receipt_before_resume")
		if prior is Dictionary and prior.get("actual_joined") == true and prior.get("failures") == [] and prior.get("expected") is Dictionary:
			expected = await _journey.run_resume(_host,_service,prior.expected)
		else:
			_service.call("begin_shutdown")
			var deadline: int = Time.get_ticks_msec()+15000
			while not _service.call("try_join") and Time.get_ticks_msec() < deadline:
				await process_frame
	var status: Dictionary = _service.call("status")
	var joined: bool = status.state == "closed" and status.pending == 0 and status.undelivered == 0 and not status.writer_alive and _service.call("try_join") == true
	_write_result(expected,joined)
	if not joined:
		# Keep SceneTree, actual service, controller and host alive for Root.
		# No process exit/destructor is relabelled an actual native join.
		print("LOCAL_PLAYERS_JOURNEY_RETAINED_UNJOINED")
		return
	var failed: bool = not _host.failures.is_empty()
	_service = null
	_journey = null
	_host.free()
	quit(1 if failed else 0)
