extends RefCounted
# Original MIT. Full accepted v1 shape plus schemas/validate.mjs semantics.
# This validator checks wire data; facade source/authority/ledger policy is separate.
const U64 = preload("res://simulation/uint64.gd")
const EPSILON: float = 2.220446049250313e-16

static func _keys(value: Variant, names: Array) -> bool:
	if not value is Dictionary or value.size() != names.size():
		return false
	for key in value:
		if not key is String or not names.has(key):
			return false
	return true

static func _number(value: Variant) -> bool:
	return (typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT) and is_finite(float(value))

static func _range(value: Variant, low: float, high: float) -> bool:
	return _number(value) and value >= low and value <= high

static func _choice(value: Variant, choices: Array) -> bool:
	return value is String and choices.has(value)

static func _numeric_choice(value: Variant, choices: Array) -> bool:
	if not _number(value):
		return false
	for choice in choices:
		if float(value) == float(choice):
			return true
	return false

static func _id(value: Variant) -> bool:
	if not value is String or value.is_empty() or value.length() > 128:
		return false
	if value.unicode_at(0) < 97 or value.unicode_at(0) > 122:
		return false
	var separator: bool = false
	for i in value.length():
		var code: int = value.unicode_at(i)
		if (code >= 97 and code <= 122) or (code >= 48 and code <= 57):
			separator = false
		elif code == 46 or code == 95 or code == 45:
			if separator:
				return false
			separator = true
		else:
			return false
	return not separator

static func _version(value: Variant) -> bool:
	if not value is String or value.is_empty() or value.length() > 64:
		return false
	var dash: int = value.find("-")
	var base: String = value if dash < 0 else value.substr(0,dash)
	var parts: PackedStringArray = base.split(".",true)
	if parts.size() != 3:
		return false
	for part in parts:
		if part.is_empty():
			return false
		for i in part.length():
			if part.unicode_at(i) < 48 or part.unicode_at(i) > 57:
				return false
	if dash >= 0:
		var suffix: String = value.substr(dash+1)
		if suffix.is_empty():
			return false
		for i in suffix.length():
			var code: int = suffix.unicode_at(i)
			if not ((code >= 97 and code <= 122) or (code >= 48 and code <= 57) or code == 46 or code == 45):
				return false
	return true

static func _vector(value: Variant) -> bool:
	return _keys(value,["x","y","z"]) and _number(value.x) and _number(value.y) and _number(value.z)

static func _position(value: Variant) -> bool:
	return _keys(value,["latitude_rad","longitude_rad","ellipsoid_height_m"]) and _range(value.latitude_rad,-PI*0.5,PI*0.5) and _range(value.longitude_rad,-PI,PI) and _range(value.ellipsoid_height_m,-2000.0,10000000.0)

static func _header(value: Dictionary, type_name: String) -> bool:
	return _choice(value.type,[type_name]) and _number(value.schema_version) and value.schema_version == 1 and U64.valid(value.tick) and _id(value.session_id)

static func _quaternion(value: Variant) -> bool:
	if not _keys(value,["w","x","y","z"]):
		return false
	var squared: float = 0.0
	for key in ["w","x","y","z"]:
		if not _range(value[key],-1.0,1.0):
			return false
		squared += float(value[key])*float(value[key])
	return absf(sqrt(squared)-1.0) <= 1e-9

static func _ecef_matches(position: Dictionary, actual: Dictionary) -> bool:
	var flattening: float = 1.0/298.257223563
	var eccentricity: float = flattening*(2.0-flattening)
	var sine: float = sin(float(position.latitude_rad))
	var cosine: float = cos(float(position.latitude_rad))
	var normal: float = 6378137.0/sqrt(1.0-eccentricity*sine*sine)
	var height: float = float(position.ellipsoid_height_m)
	var dx: float = float(actual.x)-(normal+height)*cosine*cos(float(position.longitude_rad))
	var dy: float = float(actual.y)-(normal+height)*cosine*sin(float(position.longitude_rad))
	var dz: float = float(actual.z)-(normal*(1.0-eccentricity)+height)*sine
	return sqrt(dx*dx+dy*dy+dz*dz) <= 0.0001

static func _system(value: Variant) -> bool:
	if not _keys(value,["id","quantity","value","validity"]) or not _id(value.id) or not _choice(value.quantity,["fraction","radps","pa","k","kg","a","v","bool"]) or not _choice(value.validity,["valid","unavailable"]):
		return false
	if value.quantity == "bool":
		return typeof(value.value) == TYPE_BOOL
	if not _number(value.value):
		return false
	if value.quantity == "fraction":
		return _range(value.value,0.0,1.0)
	if value.quantity == "k":
		return value.value > 0.0
	return true

static func aircraft(value: Variant) -> bool:
	if not _keys(value,["type","schema_version","tick","session_id","clock","elapsed_s","position","ecef_position_m","orientation_body_to_ned","velocity_body_mps","angular_rate_body_radps","acceleration_body_mps2","mass_kg","center_of_gravity_body_m","configuration","systems","contacts","validity"]):
		return false
	if not _header(value,"AircraftSnapshot") or not _choice(value.validity,["valid","invalid","initializing"]):
		return false
	if not _keys(value.clock,["tick_rate_hz","purpose"]) or not _numeric_choice(value.clock.tick_rate_hz,[60,120,240]) or not _choice(value.clock.purpose,["runtime","convergence"]):
		return false
	if value.clock.purpose == "runtime" and value.clock.tick_rate_hz != 120:
		return false
	if not _number(value.elapsed_s) or value.elapsed_s < 0.0 or not _position(value.position) or not _vector(value.ecef_position_m) or not _quaternion(value.orientation_body_to_ned):
		return false
	for field in ["velocity_body_mps","angular_rate_body_radps","acceleration_body_mps2","center_of_gravity_body_m"]:
		if not _vector(value[field]):
			return false
	if not _range(value.mass_kg,0.001,1000000.0) or not _keys(value.configuration,["flap_fraction","gear_fraction","trim_fraction"]):
		return false
	if not _range(value.configuration.flap_fraction,0.0,1.0) or not _range(value.configuration.gear_fraction,0.0,1.0) or not _range(value.configuration.trim_fraction,-1.0,1.0):
		return false
	if not value.systems is Array or value.systems.size() > 256 or not value.contacts is Array or value.contacts.size() > 32:
		return false
	var ids: Dictionary = {}
	for system in value.systems:
		if not _system(system) or ids.has(system.id):
			return false
		ids[system.id] = true
	ids = {}
	for contact in value.contacts:
		if not _keys(contact,["id","point_body_m","force_body_n","on_ground"]) or not _id(contact.id) or ids.has(contact.id) or not _vector(contact.point_body_m) or not _vector(contact.force_body_n) or typeof(contact.on_ground) != TYPE_BOOL:
			return false
		ids[contact.id] = true
	# Conversion serves ONLY the schema's derived binary64 elapsed-time check.
	# Tick validation/order/increment use canonical strings through U64 instead.
	var expected_time: float = float(value.tick)/float(value.clock.tick_rate_hz)
	return _ecef_matches(value.position,value.ecef_position_m) and absf(float(value.elapsed_s)-expected_time) <= maxf(1e-9,expected_time*EPSILON*4.0)

static func atmosphere(value: Variant) -> bool:
	if not _keys(value,["type","schema_version","tick","session_id","position","pressure_pa","temperature_k","density_kgpm3","relative_humidity","wind_toward_ned_mps","turbulence_ned_mps","seed","model_id"]):
		return false
	return _header(value,"AtmosphereSample") and _position(value.position) and _range(value.pressure_pa,1.0,200000.0) and _range(value.temperature_k,1.0,400.0) and _range(value.density_kgpm3,0.000001,10.0) and _range(value.relative_humidity,0.0,1.0) and _vector(value.wind_toward_ned_mps) and _vector(value.turbulence_ned_mps) and U64.valid(value.seed) and _id(value.model_id)

static func command(value: Variant) -> bool:
	if not _keys(value,["type","schema_version","tick","session_id","sequence","source_id","authority","assistance","payload"]):
		return false
	if not _header(value,"ControlCommand") or not U64.valid(value.sequence) or not _id(value.source_id) or not _choice(value.authority,["pilot","avionics","scenario","instructor"]):
		return false
	if not _keys(value.assistance,["profile_id","active"]) or not _id(value.assistance.profile_id) or not value.assistance.active is Array or value.assistance.active.size() > 64:
		return false
	for assist in value.assistance.active:
		if not _id(assist):
			return false
	var payload: Variant = value.payload
	if not payload is Dictionary or not payload.get("kind") is String:
		return false
	if payload.get("kind") == "axes":
		if not _keys(payload,["kind","roll","pitch","yaw","throttle","mixture","left_brake","right_brake","trim"]):
			return false
		for axis in ["roll","pitch","yaw","trim"]:
			if not _range(payload[axis],-1.0,1.0):
				return false
		for axis in ["throttle","mixture","left_brake","right_brake"]:
			if not _range(payload[axis],0.0,1.0):
				return false
		return true
	if payload.get("kind") == "system":
		return _keys(payload,["kind","control_id","value"]) and _id(payload.control_id) and (typeof(payload.value) == TYPE_BOOL or _range(payload.value,-1.0,1.0))
	return false

static func event(value: Variant) -> bool:
	if not _keys(value,["type","schema_version","tick","session_id","sequence","source_id","confidence","content_version","payload"]):
		return false
	if not _header(value,"OperationalEvent") or not U64.valid(value.sequence) or not _id(value.source_id) or not _choice(value.confidence,["observed","derived","unknown"]) or not _version(value.content_version):
		return false
	var payload: Variant = value.payload
	if not payload is Dictionary or not payload.get("kind") is String:
		return false
	match payload.get("kind"):
		"command-rejected":
			return _keys(payload,["kind","command_sequence","reason"]) and U64.valid(payload.command_sequence) and _choice(payload.reason,["late","duplicate","invalid","unsupported-control","wrong-session","unauthorized-source","capacity"])
		"system-state":
			return _keys(payload,["kind","system_id","state"]) and _id(payload.system_id) and _id(payload.state)
		"failure":
			return _keys(payload,["kind","failure_id","active"]) and _id(payload.failure_id) and typeof(payload.active) == TYPE_BOOL
		"procedure":
			return _keys(payload,["kind","procedure_id","step_id","result"]) and _id(payload.procedure_id) and _id(payload.step_id) and _choice(payload.result,["observed","omitted","incorrect"])
		"clearance":
			return _keys(payload,["kind","clearance_id","aircraft_id","acknowledged"]) and _id(payload.clearance_id) and _id(payload.aircraft_id) and typeof(payload.acknowledged) == TYPE_BOOL
		"assistance":
			return _keys(payload,["kind","assistance_id","active"]) and _id(payload.assistance_id) and typeof(payload.active) == TYPE_BOOL
		"pause":
			return _keys(payload,["kind","paused"]) and typeof(payload.paused) == TYPE_BOOL
		"time-scale":
			return _keys(payload,["kind","scale"]) and _numeric_choice(payload.scale,[0.25,0.5,1,2,4])
		"session-branch":
			return _keys(payload,["kind","parent_session_id","parent_tick"]) and _id(payload.parent_session_id) and U64.valid(payload.parent_tick)
		"save":
			return _keys(payload,["kind","checkpoint_id","result"]) and _id(payload.checkpoint_id) and _choice(payload.result,["saved","failed"])
	return false
