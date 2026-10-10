extends RefCounted
# Original MIT. ADR018 copied display over qualified native truth. The only IO
# reads this immutable res:// fixture; no native object, clock, scene or mutator.
const Readings = preload("res://cockpit/instruments/native_readings.gd")
const WindCue = preload("res://world/wind/wind_cue.gd")
const U64 = preload("res://simulation/uint64.gd")
const FIXTURE_ID: String = "original-practice-circuit"
const FIXTURE_REVISION: int = 1
const FIXTURE_PATH: String = "res://content/world/synthetic/practice-circuit.json"
const FIXTURE_SHA256: String = "2a4540d99d4500e326a1b1f0673583bd6f8ea99d430b991fcca1130befbbddcc"
const POINTS: Array = [[0,0,100],[0,0,-2700],[-1400,0,-2700],[-1400,0,1300],[0,0,1300],[0,0,100]]
const LABELS: Array = ["Departure","Crosswind","Downwind","Base","Final"]
const VIEW_KEYS: Array = ["available","state","session_id","tick","fixture_id","fixture_revision","ownship_anchor_eus_m","points_anchor_eus_m","leg_labels","error"]
const CONTENT_KEYS: Array = ["id","revision","license","license_source","author","kind","world_sha256","selected_runway","frame","points_anchor_eus_m","leg_labels","provenance","endpoint","limits"]

static func unavailable(reason: String) -> Dictionary:
	return {"available":false,"state":"unavailable","session_id":null,"tick":null,
		"fixture_id":FIXTURE_ID,"fixture_revision":FIXTURE_REVISION,"ownship_anchor_eus_m":null,
		"points_anchor_eus_m":[],"leg_labels":[],"error":reason.left(1024) if not reason.is_empty() else "Circuit reference unavailable"}

static func _keys(value: Variant, names: Array) -> bool:
	if not value is Dictionary or value.size()!=names.size():
		return false
	for key in value:
		if not key is String or not names.has(key): return false
	return true

static func _triple(value: Variant) -> bool:
	if not value is Array or value.size()!=3: return false
	for scalar in value:
		if not (typeof(scalar) in [TYPE_INT,TYPE_FLOAT]) or not is_finite(float(scalar)): return false
	return true

static func _points(value: Variant) -> bool:
	if not value is Array or value.size()!=6: return false
	for i in 6:
		if not _triple(value[i]): return false
		for j in 3:
			if value[i][j]!=POINTS[i][j]: return false
	return true

static func _fixture() -> Dictionary:
	# No cache: missing or changed resource bytes cannot keep stale admitted data.
	if not FileAccess.file_exists(FIXTURE_PATH): return {}
	return _fixture_from_bytes(FileAccess.get_file_as_bytes(FIXTURE_PATH))

static func _fixture_from_bytes(bytes: PackedByteArray) -> Dictionary:
	if bytes.is_empty(): return {}
	var hash_context := HashingContext.new()
	if hash_context.start(HashingContext.HASH_SHA256)!=OK or hash_context.update(bytes)!=OK: return {}
	if hash_context.finish().hex_encode()!=FIXTURE_SHA256: return {}
	var value: Variant = JSON.parse_string(bytes.get_string_from_utf8())
	if not _keys(value,CONTENT_KEYS): return {}
	if value.id!=FIXTURE_ID or value.revision!=FIXTURE_REVISION or value.license!="MIT" or value.license_source!="LICENSE": return {}
	if value.world_sha256!=Readings.WORLD or value.selected_runway!=36 or not _points(value.points_anchor_eus_m) or value.leg_labels!=LABELS: return {}
	if not value.limits is Array or value.limits.size()!=3: return {}
	for key in ["author","kind","frame","provenance","endpoint"]:
		if not value[key] is String or value[key].is_empty(): return {}
	for point in value.points_anchor_eus_m:
		if not _triple(point): return {}
	for limit in value.limits:
		if not limit is String or limit.is_empty(): return {}
	return value

static func valid_view(value: Variant) -> bool:
	# Defensive display boundary. Unknown fields or retained geometry fail closed.
	if not _keys(value,VIEW_KEYS): return false
	if typeof(value.available)!=TYPE_BOOL or typeof(value.fixture_id)!=TYPE_STRING or value.fixture_id!=FIXTURE_ID or typeof(value.fixture_revision)!=TYPE_INT or value.fixture_revision!=FIXTURE_REVISION: return false
	if not value.state is String or not value.error is String or value.error.length()>1024: return false
	if not value.points_anchor_eus_m is Array or not value.leg_labels is Array: return false
	if not value.available:
		return value.state=="unavailable" and value.session_id==null and value.tick==null and value.ownship_anchor_eus_m==null and value.points_anchor_eus_m.is_empty() and value.leg_labels.is_empty() and not value.error.is_empty()
	if not value.state in ["live","paused"] or not value.session_id is String or value.session_id.is_empty() or value.session_id.length()>128 or not U64.valid(value.tick) or not value.error.is_empty(): return false
	if not _triple(value.ownship_anchor_eus_m) or not _points(value.points_anchor_eus_m) or value.leg_labels!=LABELS: return false
	for point in value.points_anchor_eus_m:
		if not _triple(point): return false
	for label in value.leg_labels:
		if not label is String: return false
	return true

static func view(readback: Variant, current_wind: String, selected_runway: int) -> Dictionary:
	var fixture: Dictionary = _fixture()
	if fixture.is_empty(): return unavailable("Original circuit fixture missing or changed")
	var readings: Dictionary = Readings.from_readback(readback)
	if not readings.state in ["live","paused"]: return unavailable("Circuit reference needs current live or paused native truth")
	if not readback.error.is_empty() or not readback.native_fault.is_empty() or not readback.native_outcome in ["completed","paused"]: return unavailable("Current native publication is faulted or blocked")
	var cue: Dictionary = WindCue.from_readback(readback)
	if not cue.state in ["live","paused"]: return unavailable(cue.error)
	if readback.model_identity!=Readings.LEGACY_PROFILE or readback.named_start!="ground-ready": return unavailable("Circuit reference unavailable for this start")
	if current_wind!="calm": return unavailable("Circuit reference requires adopted calm wind")
	for component in cue.wind_toward_ned_mps:
		if component!=0.0: return unavailable("Circuit reference requires actual zero wind")
	if selected_runway!=36: return unavailable("Circuit reference available only for runway36")
	# Preserve all three binary64 scalars and the absolute decimal tick String.
	# In particular, never pass canonical values through a Vector3/float32.
	var source: Array = readback.canonical.anchor_eus_position_m
	return {"available":true,"state":readings.state,"session_id":readings.session_id,"tick":readings.tick,
		"fixture_id":FIXTURE_ID,"fixture_revision":FIXTURE_REVISION,
		"ownship_anchor_eus_m":[source[0],source[1],source[2]],
		"points_anchor_eus_m":fixture.points_anchor_eus_m.duplicate(true),"leg_labels":fixture.leg_labels.duplicate(true),"error":""}
