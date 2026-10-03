extends Node
# This scene proves boundary/loading/lifetime only. The original synthetic model
# is uncalibrated and provides no C172S or pilot-training qualification.
var bridge: RefCounted
var records: Array[Dictionary] = []
var mode: String = "normal"
var label: Label

func require(condition: bool, message: String) -> bool:
	if not condition:
		push_error("FLIGHT_PROOF_FAILED: " + message)
		if bridge != null:
			bridge.call("close")
		get_tree().quit(1)
	return condition

func record(kind: String, value: Dictionary) -> void:
	var entry: Dictionary = {"kind": kind, "value": value}
	records.append(entry)
	print("FLIGHT_PROOF_RECORD " + JSON.stringify(entry))

func _ready() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--proof-mode="):
			mode = argument.trim_prefix("--proof-mode=")
	if DisplayServer.get_name() != "headless":
		label = Label.new()
		label.position = Vector2(28, 28)
		label.text = "Native integration proof\nOriginal synthetic model — uncalibrated\nChecking DLL, commands, snapshots and shutdown…"
		add_child(label)
	call_deferred("run_proof")

func run_proof() -> void:
	if not require(ClassDB.class_exists("FlightProofSession"), "Native extension unavailable"):
		return
	bridge = ClassDB.instantiate("FlightProofSession") as RefCounted
	if not require(bridge != null, "Native construction failed"):
		return
	var base: String = OS.get_executable_path().get_base_dir() if OS.has_feature("standalone") else ProjectSettings.globalize_path("res://")
	var model_root: String = base.path_join("models")
	var initializer: PackedByteArray = FileAccess.get_file_as_bytes("res://initializer.bin")
	if mode == "bad-initializer":
		initializer[0] = 0
	var opened: Dictionary = bridge.call("open_session", model_root, initializer)
	if mode == "bad-model" or mode == "bad-initializer":
		if not require(not opened.get("ok", false), "Corrupt input must fail closed"):
			return
		if not require(bridge.call("close").get("joined", false), "Failed open must close"):
			return
		bridge = null
		print("FLIGHT_PROOF_EXPECTED_REJECTION")
		get_tree().quit(0)
		return
	if not require(opened.get("ok", false), "Initialization rejected: " + str(opened.get("error", ""))):
		return
	record("initialization", JSON.parse_string(opened["initialization_json"]))
	record("runtime_modules", opened.get("runtime_modules", {}))
	if not require(not bridge.call("open_session", model_root, initializer).get("ok", true), "Duplicate open must reject without closing session"):
		return
	if not require(not bridge.call("step_fixed", 33).get("ok", true), "Unbounded step batch accepted"):
		return
	var initial: Dictionary = JSON.parse_string(opened["aircraft_json"])
	record("initial_aircraft", initial)
	var controls: Dictionary = {"type":"ControlCommand", "schema_version":1,
		"tick":"1", "session_id":initial["session_id"], "sequence":"9007199254740993",
		"source_id":"pilot.controls", "authority":"pilot",
		"assistance":{"profile_id":"unassisted", "active":[]},
		"payload":{"kind":"axes", "roll":0.02, "pitch":0.025, "yaw":0.04,
			"throttle":0.65, "mixture":1, "left_brake":0, "right_brake":0, "trim":0}}
	# Boundary faults must not consume sequence or change the native sample.
	for fault: String in ["numeric-sequence", "unknown-field", "authority", "version", "nonfinite"]:
		var corrupt: Dictionary = controls.duplicate(true)
		if fault == "numeric-sequence":
			corrupt["sequence"] = 9007199254740993
		elif fault == "unknown-field":
			corrupt["extra"] = true
		elif fault == "authority":
			corrupt["authority"] = "instructor"
		elif fault == "version":
			corrupt["schema_version"] = 2
		else:
			corrupt["payload"]["roll"] = NAN
		if not require(not bridge.call("submit", corrupt).get("ok", true), "Invalid boundary accepted: " + fault):
			return
	var submitted: Dictionary = bridge.call("submit", controls)
	if not require(submitted.get("queued", false), "Pilot command was not queued"):
		return
	var stepped: Dictionary = bridge.call("step_fixed", 1)
	if not require(stepped.get("ok", false) and stepped.get("stepped", false), "Authoritative fixed step failed"):
		return
	var applied: Array = stepped["applied_commands_json"]
	if not require(applied.size() == 1, "Applied command evidence missing"):
		return
	var applied_command: Dictionary = JSON.parse_string(applied[0])
	if not require(applied_command["sequence"] == "9007199254740993", "uint64 precision lost"):
		return
	record("applied_command", applied_command)
	for _batch: int in range(4):
		stepped = bridge.call("step_fixed", 30)
		if not require(stepped.get("ok", false), "Fixed batch rejected"):
			return
	var snapshot: Dictionary = JSON.parse_string(stepped["aircraft_json"])
	if not require(snapshot["tick"] == "121", "Unexpected fixed-step tick"):
		return
	record("aircraft", snapshot)
	record("atmosphere", JSON.parse_string(stepped["atmosphere_json"]))
	var pause: Dictionary = {"type":"SessionControl", "schema_version":1,
		"tick":"121", "session_id":snapshot["session_id"], "sequence":"1",
		"source_id":"session.owner", "payload":{"kind":"pause", "paused":true}}
	var paused: Dictionary = bridge.call("session_control", pause)
	if not require(paused.get("ok", false) and paused["rejection"] == 0, "Boundary pause rejected"):
		return
	var held: Dictionary = bridge.call("step_fixed", 1)
	if not require(not held["stepped"] and JSON.parse_string(held["aircraft_json"])["tick"] == "121", "Pause advanced physics"):
		return
	for event_json: String in held["events_json"]:
		record("event", JSON.parse_string(event_json))
	if mode == "destructor":
		bridge = null # Destructor must join without an explicit close call.
	else:
		var closed: Dictionary = bridge.call("close")
		if not require(closed.get("joined", false), "Worker was not joined"):
			return
		if not require(not bridge.call("step_fixed", 1).get("ok", true), "Closed session accepted work"):
			return
		if not require(bridge.call("close").get("joined", false), "Close is not idempotent"):
			return
		bridge = null
	print("FLIGHT_PROOF_OK")
	if label != null:
		label.text = "Native integration proof passed\nOriginal synthetic model — uncalibrated\n121 fixed ticks, versioned command/snapshot, joined shutdown\nNo cockpit, aircraft fidelity or training qualification claimed."
	if DisplayServer.get_name() == "headless":
		get_tree().quit(0)

func _exit_tree() -> void:
	if bridge != null:
		bridge.call("close")
		bridge = null
