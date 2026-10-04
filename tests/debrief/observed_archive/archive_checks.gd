extends RefCounted
# Original MIT. Frozen independent references; no native authority.
const ArchiveCodec = preload("res://replay/observed_archive/codec.gd")
const ObservedValues = preload("res://replay/observed/values.gd")
const REFERENCE: String = "res://observed_archive_tests/reference/"

static func _check(r: Dictionary, condition: bool, label: String) -> void:
	r.checks += 1
	if not condition:
		r.failures.append(label)

static func _keys(v: Variant, names: Array) -> bool:
	if not v is Dictionary or v.size() != names.size():
		return false
	for key in v:
		if typeof(key) != TYPE_STRING or not names.has(key):
			return false
	return true

static func _bits(value: float) -> String:
	var bytes := PackedByteArray()
	bytes.resize(8)
	bytes.encode_double(0, value)
	return bytes.hex_encode()

static func _hash(bytes: PackedByteArray) -> String:
	var context := HashingContext.new()
	if context.start(HashingContext.HASH_SHA256) != OK or context.update(bytes) != OK:
		return ""
	return context.finish().hex_encode()

static func _restore_reference(v: Variant) -> Variant:
	# Trusted reference JSON only, never an input decoder. Frozen raw numbers
	# are canonical small ints; trusted tags encode the exact float branches.
	if v is Dictionary:
		if v.size() == 1 and v.has("$binary64_le"):
			return String(v["$binary64_le"]).hex_decode().decode_double(0)
		var result := {}
		for key in v:
			result[key] = _restore_reference(v[key])
		return result
	if v is Array:
		var result: Array = []
		for element in v:
			result.append(_restore_reference(element))
		return result
	return int(v) if typeof(v) == TYPE_FLOAT else v

static func _compare(r: Dictionary, a: Variant, b: Variant, path: String) -> void:
	_check(r, typeof(a) == typeof(b), path + ":type")
	if typeof(a) != typeof(b):
		return
	if typeof(b) == TYPE_FLOAT:
		_check(r, _bits(a) == _bits(b), path + ":bits")
	elif b is Dictionary:
		# Mutant input may intentionally contain non-String keys. Preservation
		# compares their actual type too; success-result shape remains strict.
		_check(r, a.size() == b.size(), path + ":keys")
		var actual_keys: Array = a.keys()
		for key in b:
			var key_index: int = actual_keys.find(key)
			_check(r, key_index >= 0 and typeof(actual_keys[key_index]) == typeof(key), path + ":key-type")
			if a.has(key):
				_compare(r, a[key], b[key], path + "/" + key)
	elif b is Array:
		_check(r, a.size() == b.size(), path + ":length")
		for index in mini(a.size(), b.size()):
			_compare(r, a[index], b[index], path + "/" + str(index))
	else:
		_check(r, a == b, path + ":value")

static func _nodes(v: Variant) -> int:
	var count: int = 1
	if v is Dictionary or v is Array:
		for item in v.values() if v is Dictionary else v:
			count += _nodes(item)
	return count

static func _depth(v: Variant) -> int:
	if not (v is Dictionary or v is Array):
		return 0
	var depth: int = 0
	for item in v.values() if v is Dictionary else v:
		depth = maxi(depth, _depth(item))
	return depth + 1

static func _result(r: Dictionary, v: Variant, success: bool, label: String) -> bool:
	var closed: bool = _keys(v, ["ok", "error", "value", "payload_sha256"])
	_check(r, closed, label + ":closed-result")
	if not closed:
		return false
	_check(r, typeof(v.ok) == TYPE_BOOL and v.ok == success, label + ":outcome")
	_check(r, typeof(v.error) == TYPE_STRING and v.error.length() <= 1024, label + ":error-bound")
	if success:
		_check(r, v.error == "" and typeof(v.payload_sha256) == TYPE_STRING and v.payload_sha256.length() == 64, label + ":success-fields")
	else:
		_check(r, v.error != "" and v.value == null and v.payload_sha256 == null, label + ":no-partial-value")
	return v.ok == success

static func _envelope(payload: String) -> PackedByteArray:
	return JSON.stringify({"format":"ObservedFlightReview", "archive_version":1, "recording_contract_version":1, "payload_json":payload, "payload_sha256":_hash(payload.to_utf8_buffer())}).to_utf8_buffer()

static func _reject(r: Dictionary, bytes: Variant, label: String) -> void:
	_result(r, ArchiveCodec.decode(bytes), false, label)

static func run() -> Dictionary:
	var r := {"checks":0, "failures":[], "passed":false,
		"scope":"Independent pure codec: frozen26 scalar bits and40 archive cases, all2401 dense types/ticks/bits, copies and contract negatives; no native/IO/GPU",
		"reference_cases":40, "reference_sha256":"961d8903f702f1d46374998db06b7517a1ca067333b3613bd2adbf3a8c06b15e",
		"binary64_cases":26, "binary64_sha256":"406b00475e444f71f6e1f57fd37100c52b86c076e0dccbf664bb5bfc05c028d8"}
	var scalar: Variant = JSON.parse_string(FileAccess.get_file_as_string(REFERENCE + "expected-binary64-v1.json"))
	var manifest: Variant = JSON.parse_string(FileAccess.get_file_as_string(REFERENCE + "expected-text-v1.json"))
	_check(r, scalar is Dictionary and manifest is Dictionary, "reference-files")
	if not scalar is Dictionary or not manifest is Dictionary:
		return r
	_check(r, _hash(FileAccess.get_file_as_bytes(REFERENCE + "expected-binary64-v1.json")) == "406b00475e444f71f6e1f57fd37100c52b86c076e0dccbf664bb5bfc05c028d8", "frozen-bit-manifest")
	_check(r, _hash(FileAccess.get_file_as_bytes(REFERENCE + "expected-text-v1.json")) == "961d8903f702f1d46374998db06b7517a1ca067333b3613bd2adbf3a8c06b15e", "frozen-text-manifest")
	for case in scalar.cases:
		var decoded: Dictionary = ArchiveCodec._decode_binary64({"$binary64_le":case.binary64_le_hex})
		_check(r, _keys(decoded, ["ok","error","value"]) and decoded.ok == case.finite, case.name + ":scalar-admission")
		if case.finite and decoded.ok:
			_check(r, typeof(decoded.value) == TYPE_FLOAT and _bits(decoded.value) == case.binary64_le_hex, case.name + ":scalar-bits")
			var encoded: Dictionary = ArchiveCodec._encode_binary64(decoded.value)
			_check(r, encoded.ok and _keys(encoded.value, ["$binary64_le"]) and encoded.value["$binary64_le"] == case.binary64_le_hex, case.name + ":scalar-encode")
		else:
			_check(r, decoded.value == null and decoded.error != "", case.name + ":nonfinite-null")
	var minimal := {}
	for case in manifest.positives:
		var bytes := FileAccess.get_file_as_bytes(REFERENCE + case.file)
		_check(r, _hash(bytes) == case.sha256, case.id + ":immutable-bytes")
		var outer: Dictionary = JSON.parse_string(bytes.get_string_from_utf8())
		var raw: Dictionary = JSON.parse_string(outer.payload_json)
		var expected: Dictionary = _restore_reference(raw)
		_check(r, ObservedValues.valid_recording(expected), case.id + ":source-qualification")
		_check(r, bytes.size() == int(case.metrics.file_bytes) and outer.payload_json.to_utf8_buffer().size() == int(case.metrics.payload_bytes), case.id + ":byte-count")
		_check(r, _nodes(raw) == int(case.metrics.payload_values) and _depth(raw) == int(case.metrics.payload_depth), case.id + ":nodes-depth")
		var decoded: Dictionary = ArchiveCodec.decode(bytes)
		if not _result(r, decoded, true, case.id + ":decode") or not decoded.value is Dictionary:
			continue
		_check(r, decoded.payload_sha256 == outer.payload_sha256 and decoded.payload_sha256 == case.payload_sha256, case.id + ":digest")
		_compare(r, decoded.value, expected, case.id + ":decode")
		var before: Dictionary = decoded.value.duplicate(true)
		var encoded: Dictionary = ArchiveCodec.encode(decoded.value)
		if _result(r, encoded, true, case.id + ":encode") and encoded.value is PackedByteArray:
			var again: Dictionary = ArchiveCodec.decode(encoded.value)
			if _result(r, again, true, case.id + ":roundtrip"):
				_compare(r, again.value, expected, case.id + ":roundtrip")
		_compare(r, decoded.value, before, case.id + ":input-unchanged")
		decoded.value.samples[0].held_axes.roll = 0.875
		var fresh: Dictionary = ArchiveCodec.decode(bytes)
		_check(r, fresh.ok and _bits(float(fresh.value.samples[0].held_axes.roll)) == _bits(float(expected.samples[0].held_axes.roll)), case.id + ":owned-copies")
		if case.id == "minimal":
			minimal = expected.duplicate(true)
	for case in manifest.negatives:
		var filename: String = "nul-input.bin" if case.file == "nul.bin" else case.file
		var bytes := FileAccess.get_file_as_bytes(REFERENCE + filename)
		_check(r, _hash(bytes) == case.sha256, case.id + ":immutable-negative")
		_reject(r, bytes, case.id)
	if not minimal.is_empty():
		_boundaries(r, minimal)
	r.passed = r.failures.is_empty()
	return r

static func _boundaries(r: Dictionary, minimal: Dictionary) -> void:
	# Explicit contract failures frozen before consumer observation.
	for bad in [null, true, 1, 1.0, "{}", {}, []]:
		_result(r, ArchiveCodec.encode(bad), false, "bad-encode-type-" + str(typeof(bad)))
		_reject(r, bad, "bad-decode-type-" + str(typeof(bad)))
	for mutation in ["empty","nan","infinity","tick-type","model","mixture","extra","missing","stringname","counts","sample-extra"]:
		var v: Dictionary = minimal.duplicate(true)
		match mutation:
			"empty": v = ObservedValues.empty_recording()
			"nan": v.samples[0].anchor_eus_position_m[0] = NAN
			"infinity": v.samples[0].readings.readings.tas.value = INF
			"tick-type": v.samples[0].tick = 0
			"model": v.metadata.model_identity.id = "another-model"
			"mixture": v.samples[0].held_axes.mixture = 0.5
			"extra": v.extra = true
			"missing": v.erase("error")
			"stringname": v.state = StringName("recording")
			"counts": v.late_sample_count = 1
			"sample-extra": v.samples[0].extra = true
		var before: Dictionary = v.duplicate(true)
		_result(r, ArchiveCodec.encode(v), false, "encode-reject-" + mutation)
		_compare(r, v, before, "rejected-input-preserved-" + mutation)
	var oversize := PackedByteArray()
	oversize.resize(8388609)
	oversize.fill(32)
	_reject(r, oversize, "file-cap-plus-one")
	_reject(r, _envelope("[".repeat(17) + "0" + "]".repeat(17)), "depth17")
	_reject(r, _envelope("[" + "0,".repeat(2401) + "0]"), "array2402")
	_reject(r, _envelope("{\"error\":\"" + "a".repeat(1025) + "\"}"), "string1025")
	_reject(r, _envelope("{\"error\":2402}"), "integer2402")
	_reject(r, _envelope("{\"error\":1.0}"), "inner-fraction")
	_reject(r, _envelope("{\"error\":-0}"), "inner-negative-zero")
	for tag in [{"$binary64_le":"000000000000000"},{"$binary64_le":"00000000000000000"},{"$binary64_le":"GG00000000000000"},{"$binary64_le":"0000000000000000","extra":0},{"$binary64_le":1},{"$binary64_le":StringName("0000000000000000")},{"other":"0000000000000000"}]:
		var v: Dictionary = ArchiveCodec._decode_binary64(tag)
		_check(r, not v.ok and v.value == null and v.error != "", "invalid-scalar-tag-" + str(tag))
