extends RefCounted
# Original MIT. Pure owned options; no storage, devices, mapper or flight calls.
const Preset = preload("res://input/input_preset.gd")
const Audio = preload("res://audio/audio_options.gd")
const U64_MAX = "18446744073709551615"
const U64 = preload("res://simulation/uint64.gd")
const Tick = preload("res://replay/observed/tick_math.gd")
const LEGACY = {"id":"original-interactive-prototype","version":"0.1.0-prototype","backend_model":"original-interactive"}
const PISTON = {"id":"original-piston-prop-v1","version":"0.1.0-prototype","backend_model":"original-piston-prop"}
const VARIANTS = ["jsbsim-1.3.1-upstream","jsbsim-1.3.1-event-aware-constant-power-v1","jsbsim-1.3.1-event-aware-coupled-midpoint-v1","jsbsim-1.3.1-event-aware-coupled-midpoint-local-window-v2"]

static func closed(value: Variant, keys: Array) -> bool:
	if not value is Dictionary or value.size() != keys.size():
		return false
	for key in value:
		if typeof(key) != TYPE_STRING or not keys.has(key):
			return false
	return true

static func exact_equal(a: Variant, b: Variant) -> bool:
	if typeof(a) != typeof(b):
		return false
	match typeof(a):
		TYPE_FLOAT:
			var left := PackedByteArray()
			var right := PackedByteArray()
			left.resize(8)
			right.resize(8)
			left.encode_double(0, a)
			right.encode_double(0, b)
			return left == right
		TYPE_DICTIONARY:
			if a.size() != b.size():
				return false
			for key in a:
				if typeof(key) != TYPE_STRING or not b.has(key) or not exact_equal(a[key], b[key]):
					return false
			for key in b:
				if typeof(key) != TYPE_STRING:
					return false
			return true
		TYPE_ARRAY:
			if a.size() != b.size():
				return false
			for index in a.size():
				if not exact_equal(a[index], b[index]):
					return false
			return true
		TYPE_NIL, TYPE_BOOL, TYPE_INT, TYPE_STRING:
			return a == b
	return false

static func default_seed() -> Dictionary:
	return {"legacy_input":null, "piston_input":null, "audio":{
		"enabled":true, "engine_gain":1.0, "airflow_gain":1.0, "show_panel_captions":true}}

static func validate_seed(value: Variant) -> Dictionary:
	if not closed(value, ["legacy_input", "piston_input", "audio"]):
		return _bad("Invalid options bundle")
	var audio: Dictionary = Audio.validate(value.audio)
	if not audio.ok:
		return _bad("Invalid Audio options")
	var copy: Dictionary = {"legacy_input":null, "piston_input":null, "audio":audio.value}
	for slot in ["legacy_input", "piston_input"]:
		if value[slot] == null:
			continue
		if not _plain(value[slot], 0):
			return _bad("Invalid preset scalar types")
		var checked: Dictionary = Preset.validate_preset(value[slot]) if slot == "legacy_input" else Preset.validate_preset_v2(value[slot])
		if not checked.ok:
			return _bad("Invalid input preset")
		copy[slot] = checked.value.duplicate(true)
	return {"ok":true, "error":"", "value":copy}

static func seed_from_preferences(value: Dictionary) -> Dictionary:
	return {"legacy_input":value.legacy_input, "piston_input":value.piston_input,
		"audio":value.audio}.duplicate(true)

static func validate_pair(value: Variant) -> Dictionary:
	if not closed(value, ["player", "preferences"]):
		return _bad("Invalid player bundle")
	var player: Variant = value.player
	var preferences: Variant = value.preferences
	if not closed(player, ["type", "version", "id", "name", "created_utc", "updated_utc", "revision"]):
		return _bad("Invalid player record")
	if typeof(player.type) != TYPE_STRING or player.type != "LocalPlayer" or typeof(player.version) != TYPE_INT or player.version != 1:
		return _bad("Unsupported player record")
	if not id_valid(player.id) or not name_valid(player.name) or not utc_valid(player.created_utc) or not utc_valid(player.updated_utc) or not u64_valid(player.revision, false):
		return _bad("Invalid player fields")
	if not closed(preferences, ["type", "version", "player_id", "revision", "legacy_input", "piston_input", "audio"]):
		return _bad("Invalid preferences record")
	if typeof(preferences.type) != TYPE_STRING or preferences.type != "LocalPlayerPreferences" or typeof(preferences.version) != TYPE_INT or preferences.version != 1:
		return _bad("Unsupported preferences record")
	if typeof(preferences.player_id) != TYPE_STRING or preferences.player_id != player.id or typeof(preferences.revision) != TYPE_STRING or preferences.revision != player.revision:
		return _bad("Player/preferences mismatch")
	var seed: Dictionary = validate_seed(seed_from_preferences(preferences))
	if not seed.ok or not exact_equal(seed.value, seed_from_preferences(preferences)):
		return _bad("Unnormalized preferences record")
	return {"ok":true, "error":"", "value":value.duplicate(true)}

static func id_valid(value: Variant) -> bool:
	if typeof(value) != TYPE_STRING or value.length() != 32:
		return false
	for index in value.length():
		if value.unicode_at(index) not in [48,49,50,51,52,53,54,55,56,57,97,98,99,100,101,102]:
			return false
	return true

static func u64_valid(value: Variant, zero: bool = true) -> bool:
	if typeof(value) != TYPE_STRING or value.is_empty() or value.length() > 20:
		return false
	if value == "0":
		return zero
	if value[0] == "0":
		return false
	for index in value.length():
		if value.unicode_at(index) < 48 or value.unicode_at(index) > 57:
			return false
	return value.length() < 20 or value <= U64_MAX

static func name_valid(value: Variant) -> bool:
	if typeof(value) != TYPE_STRING or value.length() < 1 or value.length() > 40 or value.to_utf8_buffer().size() > 160:
		return false
	for index in value.length():
		var code: int = value.unicode_at(index)
		if code < 32 or code == 127 or code >= 0xd800 and code <= 0xdfff or code > 0x10ffff:
			return false
	return not _space(value.unicode_at(0)) and not _space(value.unicode_at(value.length()-1))

static func next_u64(value: String) -> Variant:
	if not u64_valid(value) or value == U64_MAX:
		return null
	var output: String = value
	for index in range(output.length()-1, -1, -1):
		var digit: int = output.unicode_at(index)-48
		if digit < 9:
			return output.substr(0,index) + str(digit+1) + output.substr(index+1)
		output = output.substr(0,index) + "0" + output.substr(index+1)
	return "1" + output

static func utc_valid(value: Variant) -> bool:
	if typeof(value) != TYPE_STRING or value.length() != 20:
		return false
	for index in 20:
		if index in [4,7,10,13,16,19]:
			if value[index] != {4:"-",7:"-",10:"T",13:":",16:":",19:"Z"}[index]:
				return false
		elif value.unicode_at(index) < 48 or value.unicode_at(index) > 57:
			return false
	var year: int = int(value.substr(0,4))
	var month: int = int(value.substr(5,2))
	var day: int = int(value.substr(8,2))
	if year < 2000 or month < 1 or month > 12:
		return false
	var days: Array = [31,29 if year%4 == 0 and (year%100 != 0 or year%400 == 0) else 28,31,30,31,30,31,31,30,31,30,31]
	return day >= 1 and day <= days[month-1] and int(value.substr(11,2)) <= 23 and int(value.substr(14,2)) <= 59 and int(value.substr(17,2)) <= 59

static func _space(code: int) -> bool:
	return code in [32,0x85,0xa0,0x1680,0x2028,0x2029,0x202f,0x205f,0x3000] or code >= 0x2000 and code <= 0x200a

static func _plain(value: Variant, depth: int) -> bool:
	if depth > 16:
		return false
	match typeof(value):
		TYPE_DICTIONARY:
			if value.size() > 64:
				return false
			for key in value:
				if typeof(key) != TYPE_STRING or not _plain(value[key], depth+1):
					return false
		TYPE_ARRAY:
			if value.size() > 64:
				return false
			for item in value:
				if not _plain(item, depth+1):
					return false
		TYPE_FLOAT:
			return is_finite(value)
		TYPE_STRING:
			for index in value.length():
				var code: int = value.unicode_at(index)
				if code >= 0xd800 and code <= 0xdfff or code > 0x10ffff:
					return false
		TYPE_NIL, TYPE_BOOL, TYPE_INT:
			pass
		_:
			return false
	return true

static func _bad(message: String) -> Dictionary:
	return {"ok":false, "error":message, "value":null}

# Historical structure admission does not upgrade a descriptor into native truth.
static func source_valid(value: Variant) -> bool:
	if not closed(value, ["session_id","model_identity","source_variant","native_source_fingerprint","prepared_world_sha256","named_start","wind_profile","angular_integration_method"]):
		return false
	if not session_valid(value.session_id) or not hex_valid(value.native_source_fingerprint,64) or not hex_valid(value.prepared_world_sha256,64):
		return false
	for key in ["source_variant","named_start","wind_profile"]:
		if typeof(value[key]) != TYPE_STRING:
			return false
	if value.source_variant not in VARIANTS:
		return false
	var piston: bool = exact_equal(value.model_identity, PISTON)
	if not piston and not exact_equal(value.model_identity, LEGACY):
		return false
	if value.named_start == ("piston-cold-apron" if piston else "apron-ready"):
		return value.wind_profile == "calm" and (value.source_variant == VARIANTS[3] and typeof(value.angular_integration_method) == TYPE_STRING and value.angular_integration_method == "event_aware_coupled_midpoint_v1" if piston else value.angular_integration_method == null)
	if piston:
		var method: String = "event_aware_constant_power_v1" if value.source_variant == VARIANTS[1] else "event_aware_coupled_midpoint_v1"
		return value.named_start == "piston-cold-ground" and value.wind_profile == "calm" and value.source_variant != VARIANTS[0] and typeof(value.angular_integration_method) == TYPE_STRING and value.angular_integration_method == method
	return value.named_start in ["ground-ready","airborne-prepared"] and value.wind_profile in ["calm","from-north","from-west","from-east"] and value.angular_integration_method == null

static func session_valid(value: Variant) -> bool:
	if typeof(value) != TYPE_STRING or value.length() < 1 or value.length() > 128:
		return false
	var separator: bool = false
	for index in value.length():
		var code: int = value.unicode_at(index)
		if code >= 97 and code <= 122 or index > 0 and code >= 48 and code <= 57:
			separator = false
		elif index > 0 and code in [46,95,45] and not separator:
			separator = true
		else:
			return false
	return not separator

static func hex_valid(value: Variant, count: int) -> bool:
	if typeof(value) != TYPE_STRING or value.length() != count:
		return false
	for index in value.length():
		var code: int = value.unicode_at(index)
		if not (code >= 48 and code <= 57 or code >= 97 and code <= 102):
			return false
	return true

static func path_valid(value: Variant) -> bool:
	if typeof(value) != TYPE_STRING or value.length() < 4 or value.to_utf8_buffer().size() > 4096:
		return false
	var drive: int = value.unicode_at(0)
	if not (drive >= 65 and drive <= 90 or drive >= 97 and drive <= 122) or value[1] != ":" or value[2] not in ["/","\\"]:
		return false
	var parts: PackedStringArray = value.substr(3).replace("\\","/").split("/")
	for part in parts:
		if part.is_empty() or part in [".",".."] or part.ends_with(".") or part.ends_with(" "):
			return false
		for index in part.length():
			var code: int = part.unicode_at(index)
			if code < 32 or code == 127 or code >= 0xd800 and code <= 0xdfff or code > 0x10ffff or part[index] in [":","*","?","\"","<",">","|"]:
				return false
	return true

static func archive_valid(value: Variant, source: Dictionary) -> bool:
	if value == null:
		return true
	if not closed(value, ["type","version","absolute_path","payload_sha256","recording_session_id","first_tick","last_tick","linked_utc"]):
		return false
	return typeof(value.type) == TYPE_STRING and value.type == "ExternalRecordedReview" and typeof(value.version) == TYPE_INT and value.version == 1 and path_valid(value.absolute_path) and hex_valid(value.payload_sha256,64) and session_valid(value.recording_session_id) and value.recording_session_id == source.session_id and u64_valid(value.first_tick) and u64_valid(value.last_tick) and U64.compare(value.first_tick,value.last_tick) <= 0 and utc_valid(value.linked_utc)

static func practice_valid(value: Variant, summary: bool = false) -> bool:
	if not closed(value, ["type","version","id","player_id","source","started_utc","last_observed_utc","first_tick","last_tick","observed_ticks","tick_rate_hz","status","end_reason","revision","creation_sequence","commit_sequence","archive"]):
		return false
	if typeof(value.type) != TYPE_STRING or value.type != "LocalPractice" or typeof(value.version) != TYPE_INT or value.version != 1 or typeof(value.tick_rate_hz) != TYPE_INT or value.tick_rate_hz != 120 or typeof(value.status) != TYPE_STRING:
		return false
	if not id_valid(value.id) or not id_valid(value.player_id) or not source_valid(value.source) or not utc_valid(value.started_utc) or not utc_valid(value.last_observed_utc):
		return false
	for key in ["first_tick","last_tick","observed_ticks","revision","creation_sequence","commit_sequence"]:
		if not u64_valid(value[key], key in ["first_tick","last_tick","observed_ticks"]):
			return false
	var difference: Dictionary = Tick.subtract(value.last_tick,value.first_tick)
	if not difference.ok or difference.value != value.observed_ticks or U64.compare(value.creation_sequence,value.commit_sequence) > 0:
		return false
	if summary:
		if not closed(value.archive,["linked"]) or typeof(value.archive.linked) != TYPE_BOOL:
			return false
	elif not archive_valid(value.archive,value.source):
		return false
	elif value.archive != null and (U64.compare(value.archive.first_tick,value.first_tick) < 0 or U64.compare(value.archive.last_tick,value.last_tick) > 0):
		return false
	match value.status:
		"active": return value.end_reason == null
		"manually_ended": return typeof(value.end_reason) == TYPE_STRING and value.end_reason in ["user_end","user_restart","user_quit"]
		"source_ended": return typeof(value.end_reason) == TYPE_STRING and value.end_reason == "native_terminal"
		"interrupted": return typeof(value.end_reason) == TYPE_STRING and value.end_reason == "previous_process_incomplete"
	return false
