extends SceneTree
# Root-run headless host for labelled synthetic page/options checks. No store.
const Checks = preload("res://player_tests/local_players_ui_checks.gd")
const ControllerChecks = preload("res://player_tests/local_players_controller_checks.gd")

class Host extends Node:
	var checked: int = 0
	var failures: Array[String] = []
	func check(condition: bool, name: String) -> void:
		checked += 1
		if not condition:
			failures.append(name)
			push_error(name)

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var host := Host.new()
	root.add_child(host)
	var result: Dictionary = Checks.new().run(host)
	ControllerChecks.new().run(host)
	print(JSON.stringify({"type":"LocalPlayersPresentationChecks", "version":1, "checked":host.checked, "failures":host.failures, "scope":result.scope, "native_persistence_exercised":false}))
	var failed: bool = not host.failures.is_empty()
	host.free()
	quit(1 if failed else 0)
