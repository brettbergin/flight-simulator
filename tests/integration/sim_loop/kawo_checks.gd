extends SceneTree
# Private check host. The scene suite uses actual native flight and no storage.
class CheckHost extends Node:
	var checks: int = 0
	var failures: Array = []
	func check(good: bool, name: String) -> void:
		checks += 1
		if not good: failures.append(name)

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() != 1 or args[0] not in ["source","scene"]:
		print("FOCUSED_FRONTEND_REFUSED_ARGUMENTS")
		quit(1)
		return
	var host = CheckHost.new()
	root.add_child(host)
	var path: String = "res://sim_loop_tests/kawo_" + args[0] + "_checks.gd"
	var suite: RefCounted = load(path).new()
	var result: Dictionary = suite.run(host)
	var joined: bool = result.get("joined",true)
	var passed: bool = host.failures.is_empty() and result.get("failures",["missing"]).is_empty() and host.checks > 0 and joined
	print("FOCUSED_FRONTEND_RESULT=" + JSON.stringify({"suite":args[0],"passed":passed,"checks":host.checks,"failures":host.failures,"result":result,"actual_storage_exercised":false}))
	if not joined:
		# Preserve the suite's retained scene/worker; outer timeout is a failure,
		# never evidence of a successful native join or normal destruction.
		return
	host.free()
	quit(0 if passed else 1)
