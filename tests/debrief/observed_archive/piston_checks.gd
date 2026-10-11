extends RefCounted
# Original MIT. ADR022 synthetic format proof, never native flight evidence.
const Codec = preload("res://replay/observed_archive/codec.gd")
const Strict = preload("res://replay/observed_archive/strict_json.gd")
const Values = preload("res://replay/observed/values.gd")
const LegacyChecks = preload("res://observed_archive_tests/archive_checks.gd")
const SMALL_PATH: String = "res://observed_archive_tests/reference/piston-small.fsreview.json"
const SMALL_SHA: String = "b9b55515115d02b2eb6f4aa9426882b5cbe4633747f4d4e8788b4e5e3223a34b"
const DENSE_SHA: String = "72af4ea7ad6caabaf7d8238b9bf74b2fc3084e2d7d4a1015cfbfaf915c4266c1"
const ENGINE_NUMBERS: Array = ["fuel.total","engine.throttle","engine.mixture","propeller.angular_speed"]
const ENGINE_BOOLEANS: Array = ["engine.running","engine.ignition_left","engine.ignition_right","engine.starter","fuel.feed","engine.starved"]

static func _check(r: Dictionary, condition: bool, label: String) -> void:
	r.checks+=1
	if not condition: r.failures.append(label)

static func _report(scope: String) -> Dictionary:
	return {"passed":false,"checks":0,"failures":[],"scope":scope}

static func _same(a: Variant, b: Variant) -> bool:
	# Independent test comparison: full types and exact float bytes, no tolerance.
	if typeof(a)!=typeof(b): return false
	if typeof(a)==TYPE_FLOAT: return LegacyChecks._bits(a)==LegacyChecks._bits(b)
	if a is Dictionary:
		if a.size()!=b.size(): return false
		var actual: Array=a.keys()
		for key in b:
			var index: int=actual.find(key)
			if index<0 or typeof(actual[index])!=typeof(key) or not _same(a[key],b[key]): return false
		return true
	if a is Array:
		if a.size()!=b.size(): return false
		for i in a.size():
			if not _same(a[i],b[i]): return false
		return true
	return a==b

static func _wire(value: Variant) -> Variant:
	# Test-only construction of trusted/mutated wire. Never a production decoder.
	if typeof(value)==TYPE_FLOAT: return {"$binary64_le":LegacyChecks._bits(value)}
	if value is Dictionary:
		var result: Dictionary={}
		for key in value: result[key]=_wire(value[key])
		return result
	if value is Array:
		var result: Array=[]
		for item in value: result.append(_wire(item))
		return result
	return value

static func _envelope(payload: String, archive_version: Variant=2, recording_version: Variant=2) -> PackedByteArray:
	return JSON.stringify({"format":"ObservedFlightReview","archive_version":archive_version,"recording_contract_version":recording_version,"payload_json":payload,"payload_sha256":LegacyChecks._hash(payload.to_utf8_buffer())},"",true).to_utf8_buffer()

static func _bytes(recording: Dictionary, archive_version: Variant=2, recording_version: Variant=2) -> PackedByteArray:
	return _envelope(JSON.stringify(_wire(recording),"",true),archive_version,recording_version)

static func _result(r: Dictionary, value: Variant, success: bool, label: String) -> bool:
	return LegacyChecks._result(r,value,success,label)

static func _reject(r: Dictionary, recording: Dictionary, label: String) -> void:
	var before: Dictionary=recording.duplicate(true)
	_result(r,Codec.encode(recording),false,label+":encode")
	_result(r,Codec.decode(_bytes(recording)),false,label+":decode-recomputed-digest")
	_check(r,_same(recording,before),label+":caller-unchanged")

static func _roundtrip(r: Dictionary, recording: Dictionary, label: String) -> void:
	var before: Dictionary=recording.duplicate(true)
	_check(r,Values.valid_recording(recording),label+":qualified-synthetic-value")
	var encoded: Dictionary=Codec.encode(recording)
	if not _result(r,encoded,true,label+":encode") or not encoded.value is PackedByteArray: return
	var decoded: Dictionary=Codec.decode(encoded.value)
	if _result(r,decoded,true,label+":decode"):
		_check(r,_same(decoded.value,recording),label+":all-types-bits-identity")
	_check(r,_same(recording,before),label+":input-preserved")

static func _reference(r: Dictionary, bytes: PackedByteArray, sha: String, label: String) -> Dictionary:
	_check(r,LegacyChecks._hash(bytes)==sha,label+":immutable-wire-bytes")
	if LegacyChecks._hash(bytes)!=sha: return {}
	var outer: Dictionary=JSON.parse_string(bytes.get_string_from_utf8())
	var raw: Dictionary=JSON.parse_string(outer.payload_json)
	var expected: Dictionary=LegacyChecks._restore_reference(raw)
	_check(r,Values.valid_recording(expected),label+":independent-value-qualification")
	var decoded: Dictionary=Codec.decode(bytes)
	if not _result(r,decoded,true,label+":decode") or not decoded.value is Dictionary: return {}
	_check(r,_same(decoded.value,expected),label+":complete-independent-types-bits")
	_check(r,decoded.payload_sha256==outer.payload_sha256,label+":payload-digest")
	_roundtrip(r,expected,label+":roundtrip")
	decoded.value.samples[0].engine_status.readings["engine.running"].value=true
	var again: Dictionary=Codec.decode(bytes)
	_check(r,again.ok and _same(again.value,expected),label+":fresh-owned-decode")
	return expected

static func run() -> Dictionary:
	var r: Dictionary=_report("Pure ADR022 archive2: pinned authored3-sample reference, engine tag/null/type/profile negatives and exact250k/400k scanner boundaries; existing legacy suite separate; no native/IO/GPU or flight inference")
	var bytes: PackedByteArray=FileAccess.get_file_as_bytes(SMALL_PATH)
	var small: Dictionary=_reference(r,bytes,SMALL_SHA,"small")
	if not small.is_empty():
		_check(r,small.samples.size()==3 and small.samples[0].tick=="0" and small.samples[1].tick=="60" and small.samples[2].tick=="120","small:three-independent-sample-identities")
		_check(r,small.samples[0].engine_status.readings["engine.starter"].value==false and small.samples[1].engine_status.readings["engine.starter"].value==true and small.samples[2].engine_status.readings["engine.running"].value==true,"small:authored-engine-values-not-events")
		_variants(r,small)
		_negatives(r,small)
	_boundaries(r)
	r.passed=r.failures.is_empty()
	return r

static func run_dense(bytes: PackedByteArray) -> Dictionary:
	# Root supplies isolated public-generator output, never a shipped7.4MB asset.
	var r: Dictionary=_report("Separate source-bound dense ADR022 synthetic wire proof supplied as bytes: exact2401 samples/types/bits, fixed limits and production codec roundtrip; no native/IO/GPU")
	var dense: Dictionary=_reference(r,bytes,DENSE_SHA,"dense")
	if not dense.is_empty():
		var outer: Dictionary=JSON.parse_string(bytes.get_string_from_utf8())
		var raw: Dictionary=JSON.parse_string(outer.payload_json)
		var payload: PackedByteArray=outer.payload_json.to_utf8_buffer()
		_check(r,bytes.size()==7419985 and payload.size()==6339255,"dense:independent-byte-counts")
		_check(r,LegacyChecks._nodes(raw)==372186 and dense.samples.size()==2401 and dense.samples[0].tick=="0" and dense.samples[-1].tick=="144000","dense:independent-node-sample-tick-counts")
		_check(r,not Strict.scan(payload).ok and Strict.scan_piston_payload(payload).ok,"dense:v1-node-rejection-and-fixed-v2-admission")
	r.passed=r.failures.is_empty()
	return r

static func _negative_zero() -> float:
	# Construct the sign bit explicitly: literals may share folded zero constants.
	return PackedByteArray([0,0,0,0,0,0,0,128]).decode_double(0)

static func _variants(r: Dictionary, source: Dictionary) -> void:
	var unavailable: Dictionary=source.duplicate(true)
	for sample in unavailable.samples:
		for name in ENGINE_NUMBERS+ENGINE_BOOLEANS:
			var channel: Dictionary=sample.engine_status.readings[name]
			channel.value=null
			channel.valid=false
			channel.error="Synthetic unavailable engine channel"
		sample.readings.readings.fuel_total.value=null
		sample.readings.readings.fuel_total.valid=false
		sample.readings.readings.fuel_total.error="Different unavailable fuel producer wording"
	_roundtrip(r,unavailable,"all-engine-unavailable")
	var partial: Dictionary=source.duplicate(true)
	partial.samples[1].engine_status.readings["engine.starved"]={"value":null,"unit":"bool","valid":false,"error":"Synthetic missing source channel"}
	_roundtrip(r,partial,"partial-engine-unavailable")
	var mixed: Dictionary=source.duplicate(true)
	var negative_zero: float=_negative_zero()
	_check(r,LegacyChecks._bits(negative_zero)=="0000000000000080" and LegacyChecks._bits(0.0)=="0000000000000000","negative-zero:independent-binary64-construction")
	for sample in mixed.samples:
		sample.held_axes.throttle=0
		sample.engine_status.readings["engine.throttle"].value=negative_zero
		sample.held_axes.mixture=0.5
		sample.engine_status.readings["engine.mixture"].value=0.5
		sample.readings.readings.fuel_total.value=negative_zero
		sample.engine_status.readings["fuel.total"].value=negative_zero
		sample.engine_status.readings["propeller.angular_speed"].value="0100000000000000".hex_decode().decode_double(0)
		_check(r,LegacyChecks._bits(sample.readings.readings.fuel_total.value)=="0000000000000080" and LegacyChecks._bits(sample.engine_status.readings["fuel.total"].value)=="0000000000000080" and LegacyChecks._bits(sample.engine_status.readings["engine.throttle"].value)=="0000000000000080","negative-zero:positive-variant-real-sign-"+sample.tick)
	mixed.metadata.clock.tick_rate_hz=120.0
	_roundtrip(r,mixed,"axes-int-clock-float-negative-zero-positive-subnormal")
	var historical: Dictionary=source.duplicate(true)
	historical.metadata.native_source_fingerprint="a".repeat(64)
	_roundtrip(r,historical,"copied-foreign-build-fingerprint-not-authenticated")

static func _negatives(r: Dictionary, source: Dictionary) -> void:
	for name in ["root-revision","root-extra","legacy-model","unknown-model","wrong-start","wrong-world","wrong-source","engine-missing","engine-extra","engine-null","engine-array","status-session","status-tick","status-state","status-native-truth","status-error","channel-missing","channel-extra","channel-object","channel-unit","channel-valid-null","channel-unavailable-nonnull","channel-unavailable-empty-error","channel-extra-key","channel-error-overlong","boolean-int","boolean-tag","numeric-int","numeric-nan","fuel-negative","shaft-negative","fraction-high","fraction-negative","fuel-validity-conflict","fuel-value-conflict","fuel-signed-zero-conflict","throttle-held-conflict","mixture-held-conflict"]:
		var value: Dictionary=source.duplicate(true)
		var sample: Dictionary=value.samples[0]
		var channels: Dictionary=sample.engine_status.readings
		match name:
			"root-revision": value.contract_version=1
			"root-extra": value.extra=true
			"legacy-model": value.metadata.model_identity={"id":"original-interactive-prototype","version":"0.1.0-prototype","backend_model":"original-interactive"}
			"unknown-model": value.metadata.model_identity.id="unknown-piston"
			"wrong-start": value.metadata.named_start="ground-ready"
			"wrong-world": value.metadata.prepared_world_sha256="0".repeat(64)
			"wrong-source": value.metadata.native_source_fingerprint="invalid"
			"engine-missing": sample.erase("engine_status")
			"engine-extra": sample.engine_status.extra=true
			"engine-null": sample.engine_status=null
			"engine-array": sample.engine_status=[]
			"status-session": sample.engine_status.session_id="other.session"
			"status-tick": sample.engine_status.tick="1"
			"status-state": sample.engine_status.state="historical"
			"status-native-truth": sample.engine_status.native_truth=false
			"status-error": sample.engine_status.error="not-qualified"
			"channel-missing": channels.erase("engine.starved")
			"channel-extra": channels["engine.other"]={"value":false,"unit":"bool","valid":true,"error":""}
			"channel-object": channels["engine.running"]=[]
			"channel-unit": channels["propeller.angular_speed"].unit="rpm"
			"channel-valid-null": channels["engine.running"].value=null
			"channel-unavailable-nonnull": channels["engine.running"].valid=false
			"channel-unavailable-empty-error": channels["engine.running"]={"value":null,"unit":"bool","valid":false,"error":""}
			"channel-extra-key": channels["engine.running"].extra=0
			"channel-error-overlong": channels["engine.running"]={"value":null,"unit":"bool","valid":false,"error":"x".repeat(1025)}
			"boolean-int": channels["engine.running"].value=0
			"boolean-tag": channels["engine.running"].value={"$binary64_le":"0000000000000000"}
			"numeric-int": channels["propeller.angular_speed"].value=0
			"numeric-nan": channels["propeller.angular_speed"].value=NAN
			"fuel-negative": channels["fuel.total"].value=-1.0;sample.readings.readings.fuel_total.value=-1.0
			"shaft-negative": channels["propeller.angular_speed"].value=-1.0
			"fraction-high": channels["engine.mixture"].value=1.1
			"fraction-negative": channels["engine.throttle"].value=-0.1
			"fuel-validity-conflict": channels["fuel.total"]={"value":null,"unit":"kg","valid":false,"error":"missing"}
			"fuel-value-conflict": channels["fuel.total"].value=99.0
			"fuel-signed-zero-conflict":
				channels["fuel.total"].value=_negative_zero()
				sample.readings.readings.fuel_total.value=0.0
				_check(r,LegacyChecks._bits(channels["fuel.total"].value)=="0000000000000080" and LegacyChecks._bits(sample.readings.readings.fuel_total.value)=="0000000000000000","fuel-signed-zero-conflict:independent-opposite-sign-bits")
			"throttle-held-conflict": channels["engine.throttle"].value=0.5
			"mixture-held-conflict": channels["engine.mixture"].value=0.5
		_reject(r,value,name)
	# Wire-only malformed tags are independent of recomputed checksum rejection.
	for name in ["tag-extra","tag-uppercase","tag-infinity","tag-error-position","tag-tick-position","engine-channel-duplicate"]:
		var raw: Dictionary=_wire(source)
		match name:
			"tag-extra": raw.samples[0].engine_status.readings["propeller.angular_speed"].value.extra=0
			"tag-uppercase": raw.samples[0].engine_status.readings["propeller.angular_speed"].value={"$binary64_le":"000000000000F03F"}
			"tag-infinity": raw.samples[0].engine_status.readings["propeller.angular_speed"].value={"$binary64_le":"000000000000f07f"}
			"tag-error-position": raw.samples[0].engine_status.readings["engine.running"].error={"$binary64_le":"0000000000000000"}
			"tag-tick-position": raw.samples[0].engine_status.tick={"$binary64_le":"0000000000000000"}
		var payload: String=JSON.stringify(raw,"",true)
		if name=="engine-channel-duplicate":
			payload=payload.replace('"engine.running":','"engine.running":{"value":false,"unit":"bool","valid":true,"error":""},"engine.running":')
		_result(r,Codec.decode(_envelope(payload)),false,name+":wire-reject")
	for pair in [[1,2],[2,1],[3,3],[0,0],[true,true],["2","2"]]:
		var result: Dictionary=Codec.decode(_envelope("not-json",pair[0],pair[1]))
		_result(r,result,false,"outer-pair-before-inner-"+str(pair))
		_check(r,result.error=="Unsupported archive or recording version","outer-pair-precedes-payload-parser-"+str(pair))
	var raw_inner: Dictionary=_wire(source)
	raw_inner.contract_version=1
	_result(r,Codec.decode(_envelope(JSON.stringify(raw_inner,"",true))),false,"admitted-outer2-rejects-inner1")
	_result(r,Codec.decode(_bytes(source,1,1)),false,"admitted-outer1-rejects-inner2")

static func _node_text(total: int) -> PackedByteArray:
	# Independent arithmetic:1root+Cchild arrays+Szeros=Nvalues, every child<=2401.
	var children: int=105 if total<=250001 else 167
	var remaining: int=total-1-children
	var parts: PackedStringArray=[]
	for index in children:
		var count: int=mini(2401,remaining)
		parts.append("["+"0,".repeat(count-1)+"0]")
		remaining-=count
	return ("["+",".join(parts)+"]").to_utf8_buffer()

static func _boundaries(r: Dictionary) -> void:
	for total in [250000,250001,400000,400001]:
		var bytes: PackedByteArray=_node_text(total)
		_check(r,bytes.size()==2*total-1,"independent-node-boundary-text-bytes-"+str(total))
		var legacy: Dictionary=Strict.scan(bytes)
		var piston: Dictionary=Strict.scan_piston_payload(bytes)
		var outer: Dictionary=Strict.scan(bytes,true)
		_check(r,legacy.ok==(total<=250000),"fixed-legacy250k-"+str(total))
		_check(r,piston.ok==(total<=400000),"fixed-piston400k-"+str(total))
		_check(r,outer.ok==(total<=250000),"outer-stays250k-"+str(total))
		if total>250000: _check(r,legacy.error=="Archive value bound exceeded","legacy-specific-node-boundary-"+str(total))
		if total>400000: _check(r,piston.error=="Archive value bound exceeded","piston-specific-node-boundary-"+str(total))
	var too_large: PackedByteArray=PackedByteArray()
	too_large.resize(8388609)
	too_large.fill(32)
	_check(r,not Strict.scan_piston_payload(too_large).ok,"piston-byte-cap-unchanged")
	for text in ['{"x":1,"x":2}',"[".repeat(17)+"0"+"]".repeat(17),'[0,'+"0,".repeat(2399)+'0,0]', '{"x":"'+"a".repeat(1025)+'"}', '{"x":1.0}']:
		_check(r,not Strict.scan_piston_payload(text.to_utf8_buffer()).ok,"piston-retains-duplicate-depth-array-string-number-guard-"+str(text.length()))
