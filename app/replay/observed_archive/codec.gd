extends RefCounted
# Original MIT. ADR012 closed schema codec; no resources, arbitrary tags or native capability.
const Strict = preload("res://replay/observed_archive/strict_json.gd")
const Values = preload("res://replay/observed/values.gd")
const CHANNELS: Array = ["tas","ground_speed","pitch","bank","heading_true","ellipsoid_height","vertical_speed","body_yaw_rate","fuel_total"]
const AXES: Array = ["roll","pitch","yaw","throttle","mixture","left_brake","right_brake","trim"]
const ENGINE_NUMBERS: Array = ["fuel.total","engine.throttle","engine.mixture","propeller.angular_speed"]
const ENGINE_BOOLEANS: Array = ["engine.running","engine.ignition_left","engine.ignition_right","engine.starter","fuel.feed","engine.starved"]
var error: String = ""

static func _failure(message: String) -> Dictionary:
	return {"ok":false,"error":message,"value":null,"payload_sha256":null}

static func _encode_binary64(value: Variant) -> Dictionary:
	if typeof(value)!=TYPE_FLOAT or not is_finite(value):
		return {"ok":false,"error":"Expected finite binary64 scalar","value":null}
	var bytes: PackedByteArray = PackedByteArray()
	bytes.resize(8)
	bytes.encode_double(0,value)
	return {"ok":true,"error":"","value":{"$binary64_le":bytes.hex_encode()}}

static func _decode_binary64(value: Variant) -> Dictionary:
	if not Values.keys(value,["$binary64_le"]) or typeof(value["$binary64_le"])!=TYPE_STRING or value["$binary64_le"].length()!=16:
		return {"ok":false,"error":"Expected closed binary64 tag","value":null}
	for code in value["$binary64_le"].to_ascii_buffer():
		if not ((code>=48 and code<=57) or (code>=97 and code<=102)):
			return {"ok":false,"error":"Binary64 tag must be lowercase hex","value":null}
	var bytes: PackedByteArray = value["$binary64_le"].hex_decode()
	if bytes.size()!=8:
		return {"ok":false,"error":"Binary64 tag byte count rejected","value":null}
	var scalar: float = bytes.decode_double(0)
	if not is_finite(scalar):
		return {"ok":false,"error":"Nonfinite binary64 tag rejected","value":null}
	return {"ok":true,"error":"","value":scalar}

static func encode(recording: Variant) -> Dictionary:
	if not Values.valid_recording(recording) or recording.state=="empty":
		return _failure("Archive requires a qualified nonempty Recording")
	var revision: int = recording.contract_version
	if revision not in [1,2]: return _failure("Unsupported archive or recording version")
	var worker = new()
	var wire: Variant = worker._record(recording,false,revision)
	if not worker.error.is_empty(): return _failure(worker.error)
	var payload: String = JSON.stringify(wire,"",true)
	var payload_bytes: PackedByteArray = payload.to_utf8_buffer()
	var checked: Dictionary = Strict.scan_piston_payload(payload_bytes) if revision==2 else Strict.scan(payload_bytes)
	if not checked.ok: return _failure(checked.error)
	var digest: String = _digest(payload_bytes)
	var envelope: Dictionary = {"format":"ObservedFlightReview","archive_version":revision,"recording_contract_version":revision,"payload_json":payload,"payload_sha256":digest}
	var bytes: PackedByteArray = JSON.stringify(envelope,"",true).to_utf8_buffer()
	checked=Strict.scan(bytes,true)
	if not checked.ok: return _failure(checked.error)
	var decoded: Dictionary = decode(bytes)
	if not decoded.ok or not _exact(recording,decoded.value):
		return _failure("Archive self-decode did not preserve exact Recording")
	return {"ok":true,"error":"","value":bytes,"payload_sha256":digest}

static func decode(bytes: Variant) -> Dictionary:
	var checked: Dictionary = Strict.scan(bytes,true)
	if not checked.ok: return _failure(checked.error)
	var parser: JSON = JSON.new()
	if parser.parse(bytes.get_string_from_utf8())!=OK:
		return _failure("Strict outer JSON parse failed")
	var outer: Variant = parser.data
	if not Values.keys(outer,["format","archive_version","recording_contract_version","payload_json","payload_sha256"]) or typeof(outer.format)!=TYPE_STRING or outer.format!="ObservedFlightReview" or typeof(outer.payload_json)!=TYPE_STRING or not Values.hex(outer.payload_sha256):
		return _failure("Closed archive envelope rejected")
	# A closed, exact outer pair chooses the fixed inner policy before parsing it.
	# Neither unknown versions nor failed v1 input can retry with the larger cap.
	if not _parsed_integer(outer.archive_version,1,2) or not _parsed_integer(outer.recording_contract_version,1,2) or outer.archive_version!=outer.recording_contract_version:
		return _failure("Unsupported archive or recording version")
	var revision: int = int(outer.archive_version)
	var payload_bytes: PackedByteArray = outer.payload_json.to_utf8_buffer()
	if payload_bytes.size()>Strict.MAX_BYTES or not Strict.valid_utf8(payload_bytes) or _digest(payload_bytes)!=outer.payload_sha256:
		return _failure("Payload byte bound, scalar encoding or digest rejected")
	checked=Strict.scan_piston_payload(payload_bytes) if revision==2 else Strict.scan(payload_bytes)
	if not checked.ok: return _failure(checked.error)
	if parser.parse(outer.payload_json)!=OK:
		return _failure("Strict payload JSON parse failed")
	var worker = new()
	var recording: Variant = worker._record(parser.data,true,revision)
	if not worker.error.is_empty(): return _failure(worker.error)
	if not Values.valid_recording(recording) or recording.state=="empty":
		return _failure("Restored Recording qualification rejected")
	return {"ok":true,"error":"","value":recording,"payload_sha256":outer.payload_sha256}

static func _digest(bytes: PackedByteArray) -> String:
	var hash: HashingContext = HashingContext.new()
	hash.start(HashingContext.HASH_SHA256)
	hash.update(bytes)
	return hash.finish().hex_encode()

static func _parsed_integer(value: Variant, minimum: int, maximum: int) -> bool:
	return typeof(value) in [TYPE_INT,TYPE_FLOAT] and is_finite(float(value)) and value>=minimum and value<=maximum and float(value)==floor(float(value))

func _fail(message: String) -> Variant:
	if error.is_empty(): error=message
	return null

func _integer(value: Variant, minimum: int, maximum: int, restore: bool) -> Variant:
	if not _parsed_integer(value,minimum,maximum) or (not restore and typeof(value)!=TYPE_INT):
		return _fail("Closed integer position rejected")
	return int(value)

func _float(value: Variant, restore: bool) -> Variant:
	var result: Dictionary = _decode_binary64(value) if restore else _encode_binary64(value)
	if not result.ok: return _fail(result.error)
	return result.value

func _number(value: Variant, restore: bool, minimum: int, maximum: int) -> Variant:
	if restore:
		return _float(value,true) if value is Dictionary else _integer(value,minimum,maximum,true)
	return _float(value,false) if typeof(value)==TYPE_FLOAT else _integer(value,minimum,maximum,false)

func _record(input: Variant, restore: bool, revision: int) -> Variant:
	if not Values.keys(input,["contract_version","state","metadata","last_observed_tick","samples","seal_reason","error","skipped_target_count","late_sample_count","uncaptured_tail_targets"]):
		return _fail("Closed Recording root rejected")
	var admitted_revision: Variant = _integer(input.contract_version,revision,revision,restore)
	if not error.is_empty(): return null
	if not input.samples is Array or input.samples.is_empty() or input.samples.size()>2401:
		return _fail("Nonempty sample array bound rejected")
	var result: Dictionary = input.duplicate(true)
	result.contract_version=admitted_revision
	for key in ["skipped_target_count","late_sample_count","uncaptured_tail_targets"]:
		result[key]=_integer(input[key],0,2400,restore)
	var metadata: Variant = input.metadata
	if not Values.keys(metadata,["session_id","model_identity","native_source_fingerprint","prepared_world_sha256","world_anchor","seed","clock","named_start","first_tick"]) or not Values.keys(metadata.world_anchor,["latitude_rad","longitude_rad","ellipsoid_height_m"]) or not Values.keys(metadata.clock,["purpose","tick_rate_hz"]):
		return _fail("Closed Recording metadata rejected")
	for key in ["latitude_rad","longitude_rad","ellipsoid_height_m"]:
		result.metadata.world_anchor[key]=_float(metadata.world_anchor[key],restore)
	result.metadata.clock.tick_rate_hz=_number(metadata.clock.tick_rate_hz,restore,120,120)
	for i in input.samples.size():
		var item: Variant = input.samples[i]
		var sample_keys: Array = ["tick","target_tick","late_by_ticks","skipped_targets_before","gap_before","elapsed_s","anchor_eus_position_m","readings","held_axes"]
		if revision==2: sample_keys.append("engine_status")
		if not Values.keys(item,sample_keys) or not item.anchor_eus_position_m is Array or item.anchor_eus_position_m.size()!=3:
			return _fail("Closed sample geometry rejected")
		var target: Dictionary = result.samples[i]
		target.late_by_ticks=_integer(item.late_by_ticks,0,59,restore)
		target.skipped_targets_before=_integer(item.skipped_targets_before,0,2400,restore)
		target.elapsed_s=_float(item.elapsed_s,restore)
		for j in 3: target.anchor_eus_position_m[j]=_float(item.anchor_eus_position_m[j],restore)
		if not Values.keys(item.readings,["session_id","tick","state","native_truth","readings","error"]) or not Values.keys(item.readings.readings,CHANNELS) or not Values.keys(item.held_axes,["kind","roll","pitch","yaw","throttle","mixture","left_brake","right_brake","trim"]):
			return _fail("Closed sample channels or axes rejected")
		for name in CHANNELS:
			var channel: Variant = item.readings.readings[name]
			if not Values.keys(channel,["value","unit","valid","error"]):
				return _fail("Closed channel rejected")
			if channel.value!=null:
				target.readings.readings[name].value=_float(channel.value,restore)
		for name in AXES:
			target.held_axes[name]=_number(item.held_axes[name],restore,-1 if name in ["roll","pitch","yaw","trim"] else 0,1)
		if revision==2:
			_engine_status(item.engine_status,target.engine_status,restore)
		if not error.is_empty(): return null
	return result

func _engine_status(input: Variant, target: Variant, restore: bool) -> void:
	if not Values.keys(input,["session_id","tick","state","native_truth","readings","error"]) or not Values.keys(input.readings,ENGINE_NUMBERS+ENGINE_BOOLEANS):
		_fail("Closed EngineStatus rejected")
		return
	for name in ENGINE_NUMBERS+ENGINE_BOOLEANS:
		var channel: Variant = input.readings[name]
		if not Values.keys(channel,["value","unit","valid","error"]):
			_fail("Closed engine channel rejected")
			return
		if channel.value==null: continue
		if name in ENGINE_NUMBERS:
			target.readings[name].value=_float(channel.value,restore)
		elif typeof(channel.value)!=TYPE_BOOL:
			_fail("Engine Boolean channel requires a Boolean")
			return
		if not error.is_empty(): return

static func _exact(a: Variant, b: Variant) -> bool:
	if typeof(a)!=typeof(b): return false
	if typeof(a)==TYPE_FLOAT:
		return _encode_binary64(a).value==_encode_binary64(b).value
	if a is Dictionary:
		if a.size()!=b.size(): return false
		for key in a:
			if not b.has(key) or not _exact(a[key],b[key]): return false
		return true
	if a is Array:
		if a.size()!=b.size(): return false
		for i in a.size():
			if not _exact(a[i],b[i]): return false
		return true
	return a==b
