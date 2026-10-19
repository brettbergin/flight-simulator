extends SceneTree
const Checks = preload("res://player_tests/local_players_retirement_checks.gd")
class Host extends Node:
 var checked: int = 0
 var failures: Array[String] = []
 func check(condition: bool, label: String) -> void:
  checked += 1
  if not condition: failures.append(label); push_error(label)
var host: Node
var checks: RefCounted
func _initialize() -> void: call_deferred("run")
func run() -> void:
 host=Host.new(); root.add_child(host); checks=Checks.new()
 var result: Dictionary=await checks.run(host)
 var quit_result: Dictionary=await checks.run_quit(host)
 result['quit_fixture']=quit_result
 print(JSON.stringify({"type":"PlayersRetirementChecks","checked":host.checked,"failures":host.failures,"result":result}))
 if result.get("retained",true): return
 var failed: bool=not host.failures.is_empty()
 checks=null; host.free(); quit(1 if failed else 0)
