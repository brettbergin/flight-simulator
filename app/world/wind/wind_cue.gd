extends RefCounted
# Original MIT. ADR013: pure copied native-truth presentation, no native calls.
const Readings = preload("res://cockpit/instruments/native_readings.gd")
# One integrator-owned reviewed closure pin; loading this script creates no facade.
# Source/build evidence, not this string alone, establishes the uniform-NED field.
const Closure = preload("res://simulation/session_facade.gd")
const SUPPORTED_SOURCE: String = Closure.NATIVE

static func _unavailable(state: String, error: String) -> Dictionary:
	return {"state":state,"session_id":null,"tick":null,"wind_toward_ned_mps":null,
		"speed_mps":null,"from_true_rad":null,"wind_toward_airfield_eus_mps":null,
		"error":error.left(1024)}

static func from_readback(value: Variant) -> Dictionary:
	var qualified: Dictionary = Readings.from_readback(value)
	if qualified.state in ["invalid","empty"]:
		return _unavailable(qualified.state,qualified.error)
	# ADR009 qualifies the full closed Readback and wire pair, original model/world.
	# ADR013 additionally pins the semantics needed for the fixed-anchor projection.
	var weather: Dictionary = value.atmosphere
	if typeof(value.native_source_fingerprint)!=TYPE_STRING or value.native_source_fingerprint!=SUPPORTED_SOURCE:
		return _unavailable("invalid","Unsupported native wind source closure")
	if typeof(weather.seed)!=TYPE_STRING or weather.seed!="42" or typeof(weather.model_id)!=TYPE_STRING or weather.model_id!="jsbsim-dry-isa":
		return _unavailable("invalid","Unsupported native atmosphere source or seed")
	if weather.relative_humidity!=0.0 or weather.turbulence_ned_mps.x!=0.0 or weather.turbulence_ned_mps.y!=0.0 or weather.turbulence_ned_mps.z!=0.0:
		return _unavailable("invalid","Steady dry-ISA cue requires zero turbulence")
	var wind: Array = [float(weather.wind_toward_ned_mps.x),float(weather.wind_toward_ned_mps.y),float(weather.wind_toward_ned_mps.z)]
	var largest: float = maxf(absf(wind[0]),absf(wind[1]))
	var speed: float = 0.0
	var direction: Variant = null
	if largest!=0.0:
		var smaller: float = minf(absf(wind[0]),absf(wind[1]))/largest
		speed=largest*sqrt(1.0+smaller*smaller)
		direction=fposmod(atan2(-wind[1],-wind[0]),TAU)
		if not is_finite(speed) or speed<=0.0 or not is_finite(direction):
			return _unavailable("invalid","Wind cue arithmetic overflow or underflow")
	return {"state":qualified.state,"session_id":qualified.session_id,"tick":qualified.tick,
		"wind_toward_ned_mps":wind,"speed_mps":speed,"from_true_rad":direction,
		"wind_toward_airfield_eus_mps":[wind[1],-wind[2],-wind[0]],"error":""}
