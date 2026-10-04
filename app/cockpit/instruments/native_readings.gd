extends RefCounted
# Original MIT. ADR009 native truth: pure binary64 scalar reading derivation.
# This leaf never calls the simulator, devices, clocks, facade or scene.
const Wire = preload("res://simulation/wire_validation.gd")
const U64 = preload("res://simulation/uint64.gd")
const Frames = preload("res://simulation/canonical_frames.gd")
const WORLD: String = "04bff5a0bcf3509990f6276b2548a28268f57fc96d218a7ca51cab1990ec1ff5"
const LEGACY_PROFILE: Dictionary = {"id":"original-interactive-prototype","version":"0.1.0-prototype","backend_model":"original-interactive"}
const PISTON_PROFILE: Dictionary = {"id":"original-piston-prop-v1","version":"0.1.0-prototype","backend_model":"original-piston-prop"}
const UNITS: Dictionary = {"tas":"m/s","ground_speed":"m/s","pitch":"rad","bank":"rad","heading_true":"rad","ellipsoid_height":"m","vertical_speed":"m/s","body_yaw_rate":"rad/s","fuel_total":"kg"}
const KEYS: Array = ["host_mode","error","historical","session_id","tick","aircraft","atmosphere","held_axes","native_outcome","native_live","paused","time_scale","debt_quanta","native_fault","named_start","model_identity","native_source_fingerprint","prepared_world_sha256","world_anchor","canonical"]
const NULLABLE: Array = ["session_id","tick","aircraft","atmosphere","held_axes","native_outcome","named_start","model_identity","native_source_fingerprint","prepared_world_sha256","world_anchor","canonical"]
const TERMINAL: Array = ["closed","stalled","coverage_blocked","discarded"]

static func _keys(value: Variant, names: Array) -> bool:
	if not value is Dictionary or value.size()!=names.size():
		return false
	for key in value:
		if not key is String or not names.has(key):
			return false
	return true

static func _number(value: Variant) -> bool:
	return (typeof(value)==TYPE_FLOAT or typeof(value)==TYPE_INT) and is_finite(float(value))

static func _text(value: Variant, limit: int) -> bool:
	return value is String and value.length()<=limit

static func _hex(value: Variant) -> bool:
	if not value is String or value.length()!=64:
		return false
	for i in value.length():
		var code: int = value.unicode_at(i)
		if not ((code>=48 and code<=57) or (code>=97 and code<=102)):
			return false
	return true

static func _axes(value: Variant, piston: bool=false) -> bool:
	if not _keys(value,["kind","roll","pitch","yaw","throttle","mixture","left_brake","right_brake","trim"]) or not value.kind is String or value.kind!="axes":
		return false
	for key in ["roll","pitch","yaw","trim"]:
		if not _number(value[key]) or value[key]<-1.0 or value[key]>1.0:
			return false
	for key in ["throttle","mixture","left_brake","right_brake"]:
		if not _number(value[key]) or value[key]<0.0 or value[key]>1.0:
			return false
	return piston or value.mixture==1.0

static func _validate(value: Variant) -> String:
	if not _keys(value,KEYS):
		return "Malformed exact Readback shape"
	if not value.host_mode is String or not ["live","paused","closed","stalled","coverage_blocked","discarded"].has(value.host_mode):
		return "Unknown host mode"
	if not _text(value.error,1024) or not _text(value.native_fault,1024):
		return "Invalid bounded diagnostic"
	for key in ["historical","native_live","paused"]:
		if typeof(value[key])!=TYPE_BOOL:
			return "Readback flags must be bool"
	if typeof(value.time_scale)!=TYPE_FLOAT or not is_finite(value.time_scale) or not [0.25,0.5,1.0,2.0,4.0].has(value.time_scale):
		return "Invalid time scale"
	if typeof(value.debt_quanta)!=TYPE_INT or value.debt_quanta<0:
		return "Debt must be a nonnegative signed integer"
	if value.host_mode=="closed" and (value.native_live or value.paused or value.debt_quanta!=0):
		return "Closed state cannot claim live native state or debt"
	if value.host_mode=="live" and (not value.native_live or value.paused):
		return "Contradictory live native flags"
	if value.host_mode=="paused" and (not value.native_live or not value.paused):
		return "Contradictory paused native flags"
	if value.paused and not value.native_live:
		return "Paused native state is not live"
	if TERMINAL.has(value.host_mode) and not value.historical:
		return "Terminal state must label retained truth historical"
	if value.aircraft==null or value.atmosphere==null:
		if value.aircraft!=null or value.atmosphere!=null:
			return "Incomplete source pair"
		for key in NULLABLE:
			if value[key]!=null:
				return "Empty Readback retains nullable metadata"
		if value.host_mode!="closed" or not value.historical or value.time_scale!=1.0:
			return "Empty Readback must be closed historical truth"
		return ""
	if not Wire.aircraft(value.aircraft) or not Wire.atmosphere(value.atmosphere):
		return "Malformed v1 source shape or semantics"
	var aircraft: Dictionary = value.aircraft
	var weather: Dictionary = value.atmosphere
	if aircraft.validity!="valid" or aircraft.clock.purpose!="runtime" or aircraft.clock.tick_rate_hz!=120:
		return "Source publication must be valid runtime120Hz"
	if not value.session_id is String or not U64.valid(value.tick) or aircraft.session_id!=value.session_id or weather.session_id!=value.session_id or aircraft.tick!=value.tick or weather.tick!=value.tick or aircraft.position!=weather.position:
		return "Source pair/session/tick/position mismatch"
	if not _keys(value.model_identity,["id","version","backend_model"]):
		return "Malformed model identity"
	for key in ["id","version","backend_model"]:
		if not value.model_identity[key] is String:
			return "Model identity values must be Strings"
	if value.model_identity!=LEGACY_PROFILE and value.model_identity!=PISTON_PROFILE:
		return "Unexpected model identity"
	var piston: bool = value.model_identity==PISTON_PROFILE
	if not _axes(value.held_axes,piston):
		return "Invalid or missing native-held axes"
	if not value.native_outcome is String or not ["completed","paused","coverage_blocked","discarded"].has(value.native_outcome):
		return "Missing or unknown native outcome"
	if not value.named_start is String or (value.named_start!="piston-cold-ground" if piston else not ["ground-ready","airborne-prepared"].has(value.named_start)):
		return "Unknown named start"
	# Fingerprint structure is checked here; the leaf cannot prove binary authority.
	if not _hex(value.native_source_fingerprint) or not _hex(value.prepared_world_sha256) or value.prepared_world_sha256!=WORLD:
		return "Invalid source fingerprint or prepared world identity"
	if not _keys(value.world_anchor,["latitude_rad","longitude_rad","ellipsoid_height_m"]):
		return "Malformed world anchor"
	for key in ["latitude_rad","longitude_rad","ellipsoid_height_m"]:
		if typeof(value.world_anchor[key])!=TYPE_FLOAT or not is_finite(value.world_anchor[key]):
			return "Nonfinite world anchor"
	if value.world_anchor.latitude_rad!=0.8 or value.world_anchor.longitude_rad!=-2.0 or value.world_anchor.ellipsoid_height_m!=0.0:
		return "Unexpected prepared world anchor"
	if value.canonical==null:
		if not value.historical and not TERMINAL.has(value.host_mode):
			return "Current source lacks canonical metadata"
	else:
		if not _keys(value.canonical,["ecef_position_m","anchor_eus_position_m","body_to_anchor_eus"]) or not Frames.finite_array(value.canonical.ecef_position_m,3) or not Frames.finite_array(value.canonical.anchor_eus_position_m,3) or not Frames.rigid(value.canonical.body_to_anchor_eus):
			return "Malformed canonical metadata"
		var point: Dictionary = aircraft.ecef_position_m
		if value.canonical.ecef_position_m!=[point.x,point.y,point.z]:
			return "Canonical ECEF differs from native publication"
	return ""

static func _channel(value: Variant, unit: String, error: String = "") -> Dictionary:
	return {"value":value,"unit":unit,"valid":value!=null,"error":error}

static func _unavailable(state: String, error: String) -> Dictionary:
	var channels: Dictionary = {}
	for key in UNITS:
		channels[key]=_channel(null,UNITS[key],error)
	return {"session_id":null,"tick":null,"state":state,"native_truth":true,"readings":channels,"error":error}

static func from_readback(value: Variant) -> Dictionary:
	var error: String = _validate(value)
	if not error.is_empty():
		return _unavailable("invalid",error)
	if value.aircraft==null:
		return _unavailable("empty","No verified source publication")
	var aircraft: Dictionary = value.aircraft
	var weather: Dictionary = value.atmosphere
	var q: Dictionary = aircraft.orientation_body_to_ned
	var w: float = float(q.w)
	var x: float = float(q.x)
	var y: float = float(q.y)
	var z: float = float(q.z)
	var rotation: Array = [1.0-2.0*(y*y+z*z),2.0*(x*y-w*z),2.0*(x*z+w*y),2.0*(x*y+w*z),1.0-2.0*(x*x+z*z),2.0*(y*z-w*x),2.0*(x*z-w*y),2.0*(y*z+w*x),1.0-2.0*(x*x+y*y)]
	var velocity: Dictionary = aircraft.velocity_body_mps
	var ned: Array = []
	var air: Array = []
	var components: Array = ["x","y","z"]
	for row in 3:
		var component: float = rotation[row*3]*float(velocity.x)+rotation[row*3+1]*float(velocity.y)+rotation[row*3+2]*float(velocity.z)
		ned.append(component)
		air.append(component-float(weather.wind_toward_ned_mps[components[row]])-float(weather.turbulence_ned_mps[components[row]]))
	var tas_squared: float = air[0]*air[0]+air[1]*air[1]+air[2]*air[2]
	var gs_squared: float = ned[0]*ned[0]+ned[1]*ned[1]
	if not Frames.finite_array(ned,3) or not Frames.finite_array(air,3) or not is_finite(tas_squared) or not is_finite(gs_squared):
		return _unavailable("invalid","Derived arithmetic overflow")
	var pitch: float = asin(clampf(2.0*(w*y-z*x),-1.0,1.0))
	var bank: Variant = null
	if absf(cos(pitch))>1e-6:
		bank=atan2(2.0*(w*x+y*z),1.0-2.0*(x*x+y*y))
	var heading: Variant = null
	if sqrt(rotation[0]*rotation[0]+rotation[3]*rotation[3])>1e-6:
		heading=fposmod(atan2(rotation[3],rotation[0]),TAU)
	var values: Dictionary = {"tas":sqrt(tas_squared),"ground_speed":sqrt(gs_squared),"pitch":pitch,"bank":bank,"heading_true":heading,"ellipsoid_height":float(aircraft.position.ellipsoid_height_m),"vertical_speed":-float(ned[2]),"body_yaw_rate":float(aircraft.angular_rate_body_radps.z),"fuel_total":null}
	var fuel_error: String = "Native fuel.total is unavailable"
	for system in aircraft.systems:
		if system.id=="fuel.total":
			if system.validity=="valid" and system.quantity=="kg":
				values.fuel_total=float(system.value)
			else:
				fuel_error="Native fuel.total lacks valid kg quantity"
	var channels: Dictionary = {}
	for key in UNITS:
		if values[key]!=null and not is_finite(float(values[key])):
			return _unavailable("invalid","Derived arithmetic overflow")
		var reason: String = ""
		if values[key]==null:
			reason=fuel_error if key=="fuel_total" else "Euler singularity: native %s unavailable" % key
		channels[key]=_channel(values[key],UNITS[key],reason)
	var state: String = "historical" if value.historical or TERMINAL.has(value.host_mode) else ("paused" if value.paused else "live")
	return {"session_id":value.session_id,"tick":value.tick,"state":state,"native_truth":true,"readings":channels,"error":""}
