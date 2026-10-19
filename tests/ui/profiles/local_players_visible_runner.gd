extends "res://player_tests/local_players_journey_runner.gd"
# Test-only host. Root wrote the fixed capture resource and existing capability.
const IntegratedChecks = preload("res://player_tests/local_players_integrated_checks.gd")
const Observer = preload("res://player_tests/keyboard_visual_checks.gd")

class PumpHost extends Node:
	var checked: int = 0
	var failures: Array[String] = []
	var scene: Node
	func check(condition: bool, label: String) -> void:
		checked += 1
		if not condition:
			failures.append(label)
	func _process(_delta: float) -> void:
		if scene != null and is_instance_valid(scene) and scene.player_controller != null:
			scene.player_controller.pump()

var _scene: Node

func _wait_ready() -> bool:
	var deadline: int = Time.get_ticks_msec()+15000
	while Time.get_ticks_msec() < deadline:
		if _scene.player_controller != null and _scene.player_controller.current_status().get("state") == "ready":
			return true
		await process_frame
	return false

func _cleanup() -> bool:
	if _scene == null:
		return true
	_scene.retire_players_ui()
	var flight_closed: bool = _scene.close_session()
	var audio_retired: bool = true
	if _scene.sound != null:
		audio_retired = bool(await _scene.sound.shutdown())
	if _scene.player_controller == null:
		return false
	_scene.player_controller.begin_close()
	var deadline: int = Time.get_ticks_msec()+15000
	var joined: bool = false
	while Time.get_ticks_msec() < deadline:
		var status: Dictionary = _service.call("status")
		if status.state == "closed" and status.pending == 0 and status.undelivered == 0 and not status.writer_alive and _service.call("try_join") == true:
			joined = true
			break
		await process_frame
	return flight_closed and audio_retired and joined

func _run() -> void:
	_host = PumpHost.new()
	root.add_child(_host)
	root.size = Vector2i(960,540)
	var observer_result: Dictionary = {"passed":false,"checks":0,"failures":["setup_incomplete"],"captures":[]}
	var descriptor: Variant = _descriptor()
	_host.check(DisplayServer.get_name() != "headless", "visible_window_required")
	_host.check(ClassDB.class_exists("LocalPlayersTest") and ClassDB.class_exists("FlightInteractiveSession"), "actual_flight_and_isolated_storage_registered")
	_host.check(descriptor is Dictionary, "existing_capability_descriptor_read")
	var config: Variant = _read_json("res://players-visible-output.json",16384)
	var valid_config: bool = config is Dictionary and config.size() == 1 and typeof(config.get("capture_directory")) == TYPE_STRING and config.capture_directory.is_absolute_path() and DirAccess.dir_exists_absolute(config.capture_directory)
	_host.check(valid_config,"root_precreated_capture_directory")
	if not _host.failures.is_empty():
		_write_visible_result(observer_result,false)
		quit(1)
		return
	_service = ClassDB.instantiate("LocalPlayersTest")
	var configured: bool = _service != null and _service.call("configure_test_root",descriptor) == true
	_host.check(configured,"actual_isolated_service_configured_once")
	if not configured:
		_write_visible_result(observer_result,false)
		quit(1)
		return
	_scene = IntegratedChecks.IntegratedScene.new()
	_scene.preconfigured_service = _service
	_host.scene = _scene
	_host.add_child(_scene)
	# Stop automatic native advancement only. Ordinary GUI/input processing stays on.
	_scene.set_process(false)
	_scene.set_physics_process(false)
	var ready: bool = await _wait_ready()
	_host.check(ready and _scene.facade != null,"actual_flight_and_storage_ready")
	if ready and _scene.facade != null:
		_scene.dismiss_first_flight()
		_scene.open_menu("Players UI keyboard observation")
		_host.check(_scene.pause_session(true) and _scene.advance_wall_us(0),"actual_paused_native_settlement")
		_scene.show_state(0.0)
		if _host.failures.is_empty():
			_journey = Observer.new()
			observer_result = await _journey.run(_scene,config.capture_directory)
	var joined: bool = await _cleanup()
	_write_visible_result(observer_result,joined)
	if not joined:
		print("LOCAL_PLAYERS_VISIBLE_RETAINED_UNJOINED")
		return
	_host.scene = null
	_scene.free()
	_scene = null
	_service = null
	_journey = null
	var failed: bool = not observer_result.get("passed",false) or not _host.failures.is_empty()
	_host.free()
	quit(1 if failed else 0)

func _write_visible_result(observer_result: Dictionary, joined: bool) -> void:
	var result: Dictionary = {"type":"LocalPlayersVisibleObservation","version":1,"setup_checks":_host.checked,"setup_failures":_host.failures.duplicate(),"actual_joined":joined,"observer":observer_result.duplicate(true)}
	var file: FileAccess = FileAccess.open("res://players-visible-result.json",FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(result))
		file.close()
	else:
		_host.check(false,"visible_result_write_failed")
	print(JSON.stringify(result))
