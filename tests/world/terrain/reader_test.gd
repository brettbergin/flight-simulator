extends SceneTree
const Checks=preload("res://terrain_tests/reader_checks.gd")
func _initialize() -> void:
	var result: Dictionary=Checks.new().run()
	print(JSON.stringify(result))
	quit(0 if result.failures.is_empty() else 1)
