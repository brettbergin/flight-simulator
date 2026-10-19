extends SceneTree
# Root supplies exactly the existing four native context/descriptor argv pairs.
# No fresh root, fake service, caller phase or capability-construction API here.
const Checks = preload("res://player_tests/kawo_archive_link_checks.gd")
class Host extends Node:
	var checked: int = 0
	var failures: Array = []
	func check(good: bool, name: String) -> void:
		checked += 1
		if not good:
			failures.append(name)
			push_error(name)

var _host: Node
var _service: RefCounted
var _journey: RefCounted

func _initialize() -> void:
	call_deferred("_run")

func _descriptor() -> Variant:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() != 8: return null
	var names: Array = ["--local-players-test-context","--local-players-test-context-sha256","--local-players-test-descriptor","--local-players-test-descriptor-sha256"]
	var pairs: Dictionary = {}
	for index in range(0,8,2):
		if args[index] not in names or pairs.has(args[index]): return null
		pairs[args[index]] = args[index+1]
	var file: FileAccess = FileAccess.open(pairs["--local-players-test-descriptor"],FileAccess.READ)
	if file == null or file.get_length() < 1 or file.get_length() > 16384: return null
	var raw: PackedByteArray = file.get_buffer(file.get_length())
	file.close()
	# Actual native configure independently verifies both raw argv digests and
	# same-live-parent context/capability. This is the existing descriptor reader.
	return JSON.parse_string(raw.get_string_from_utf8())

func _run() -> void:
	_host = Host.new()
	root.add_child(_host)
	var descriptor: Variant = _descriptor()
	var available: bool = ClassDB.class_exists("LocalPlayersTest") and ClassDB.class_exists("FlightInteractiveSession") and descriptor is Dictionary
	_host.check(available,"archive_real_actual_both_native_classes_and_descriptor")
	if not available:
		quit(1)
		return
	_service = ClassDB.instantiate("LocalPlayersTest") as RefCounted
	var configured: bool = _service != null and _service.call("configure_test_root",descriptor) == true
	_host.check(configured,"archive_real_actual_capability_configured_once")
	if not configured:
		quit(1)
		return
	_journey = Checks.new()
	var result: Dictionary = await _journey.run(_host,_service)
	var receipt: Dictionary = {"kind":"actual-isolated-kawo-archive-link","checked":_host.checked,"failures":_host.failures,"result":result,"passed":_host.failures.is_empty() and not result.get("retained",true)}
	var file: FileAccess = FileAccess.open("res://kawo-archive-link-result.json",FileAccess.WRITE)
	if file == null:
		_host.check(false,"archive_real_result_write_failed")
	else:
		file.store_string(JSON.stringify(receipt))
		file.close()
	print("KAWO_ARCHIVE_LINK_RESULT=" + JSON.stringify(receipt))
	if result.get("retained",true):
		print("KAWO_ARCHIVE_LINK_RETAINED_UNJOINED")
		return
	_service = null
	_journey = null
	var failed: bool = not _host.failures.is_empty()
	_host.free()
	quit(1 if failed else 0)
