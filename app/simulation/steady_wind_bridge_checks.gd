extends RefCounted
# Original MIT. Direct actual GDExtension producer checks, not a facade mock.
# Coordinator runs this only against the reviewed new native source closure.
const PROFILES: Array[String] = ["calm", "from-north", "from-west", "from-east"]
const STARTS: Array[String] = ["ground-ready", "airborne-prepared"]
const VECTORS: Array = [[0.0, 0.0, 0.0], [-5.0, 0.0, 0.0], [0.0, 5.0, 0.0], [0.0, -5.0, 0.0]]
var _checks: int = 0
var _failures: Array[String] = []

func _check(ok: bool, message: String) -> void:
	_checks += 1
	if not ok:
		_failures.append(message)

func _foreign_open(bridge: RefCounted, root: String) -> Dictionary:
	return bridge.call("open_session", root, "ground-ready", "calm")

func _foreign_close(bridge: RefCounted) -> Dictionary:
	return bridge.call("close")

func _weather(reply: Dictionary, nominal: Array) -> void:
	_check(reply.get("ok") == true, "Actual wind producer reply rejected")
	if reply.get("ok") != true:
		return
	var aircraft: Variant = JSON.parse_string(reply.aircraft_json)
	var weather: Variant = JSON.parse_string(reply.atmosphere_json)
	_check(aircraft is Dictionary and weather is Dictionary, "Actual wire pair unavailable")
	if not aircraft is Dictionary or not weather is Dictionary:
		return
	_check(aircraft.tick == weather.tick and aircraft.session_id == weather.session_id, "Actual wind publication identity mismatch")
	_check(weather.seed == "42" and weather.model_id == "jsbsim-dry-isa", "Atmosphere source/seed changed")
	_check(weather.position == aircraft.position, "Atmosphere actual position changed")
	var wind: Dictionary = weather.wind_toward_ned_mps
	for k in range(3):
		_check(absf(float(wind[["x", "y", "z"][k]]) - nominal[k]) <= 0.000001, "Actual nominal wind component mismatch")
	_check(weather.turbulence_ned_mps == {"x": 0.0, "y": 0.0, "z": 0.0}, "Turbulence enabled")

func run(model_root: String) -> Dictionary:
	_checks = 0
	_failures = []
	_check(ClassDB.class_exists("FlightInteractiveSession"), "Actual native class missing")
	if not ClassDB.class_exists("FlightInteractiveSession"):
		return {"passed": false, "checks": _checks, "failures": _failures.duplicate()}
	var invalid: Array = [null, false, 0, 0.0, &"calm", [], {}, "", "Calm", "from-south", " calm", "calm "]
	for start in STARTS:
		var bridge: RefCounted = ClassDB.instantiate("FlightInteractiveSession") as RefCounted
		# Actual two-argument bind must supply calm, not a coerced missing Variant.
		var opened: Dictionary = bridge.call("open_session", model_root, start)
		_check(opened.get("ok") == true and opened.get("wind_profile") is String and opened.get("wind_profile") == "calm", "Two-argument default calm binding failed")
		_weather(opened, VECTORS[0])
		var before: Dictionary = bridge.call("read_state")
		for bad in invalid:
			var rejected: Dictionary = bridge.call("open_session", model_root, start, bad)
			_check(rejected.keys().size() == 2 and rejected.get("ok") == false and rejected.get("error") is String and not rejected.error.is_empty(), "Malformed profile was not rejected exactly")
			_check(bridge.call("read_state") == before, "Rejected profile changed existing native state")
		var thread := Thread.new()
		_check(thread.start(_foreign_open.bind(bridge, model_root)) == OK, "Foreign open test did not start")
		var foreign: Variant = thread.wait_to_finish()
		_check(foreign is Dictionary and foreign.get("ok") == false, "Foreign native open accepted")
		_check(bridge.call("read_state") == before, "Foreign native open changed prior state")
		thread = Thread.new()
		_check(thread.start(_foreign_close.bind(bridge)) == OK, "Foreign close test did not start")
		foreign = thread.wait_to_finish()
		_check(foreign is Dictionary and foreign.get("ok") == false, "Foreign native close accepted")
		_check(bridge.call("read_state") == before, "Foreign native close changed prior state")
		var closed: Dictionary = bridge.call("close")
		_check(closed.get("ok") == true and closed.get("joined") == true, "Default calm close not joined")
		for index in range(PROFILES.size()):
			opened = bridge.call("open_session", model_root, start, PROFILES[index])
			_check(opened.get("ok") == true and opened.get("wind_profile") is String and opened.get("wind_profile") == PROFILES[index], "Actual three-argument profile binding failed")
			_weather(opened, VECTORS[index])
			if opened.get("ok") == true:
				for _batch in range(4):
					var reply: Dictionary = bridge.call("step_fixed", 32)
					_check(reply.get("completed") == 32 and reply.get("outcome") == "completed", "Bounded actual wind steps failed")
					_weather(reply, VECTORS[index])
			closed = bridge.call("close")
			_check(closed.get("ok") == true and closed.get("joined") == true, "Actual selected wind close not joined")
	# Rejections on a fresh class must happen before a bad model path is inspected.
	var fresh: RefCounted = ClassDB.instantiate("FlightInteractiveSession") as RefCounted
	for bad in invalid:
		var rejected: Dictionary = fresh.call("open_session", "invalid-model-path", "ground-ready", bad)
		_check(rejected.get("ok") == false and ("Wind profile" in rejected.get("error", "") or "steady-wind profile" in rejected.get("error", "")), "Profile rejection did not precede model allocation")
	_check(fresh.call("close").get("joined") == true, "Rejected fresh worker close not joined")
	return {"passed": _failures.is_empty(), "checks": _checks, "failures": _failures.duplicate()}
