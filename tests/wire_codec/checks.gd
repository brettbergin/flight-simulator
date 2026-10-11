extends RefCounted
# Original MIT. Frozen independent oracle; real utility/frontend and actual cold publication.
const Decoder = preload("res://simulation/native_wire_decoder.gd")
const Facade = preload("res://simulation/session_facade.gd")
const Readings = preload("res://cockpit/instruments/native_readings.gd")
const EngineStatus = preload("res://cockpit/instruments/engine_status.gd")
const REFERENCE = "res://wire_codec_tests/reference.json"
const REFERENCE_SHA = "1cab52841eb0cb063d547bf90e7a50f04a1871a5293bdfee4e0a78ddb8940ff6"
var checks: int = 0
var failures: Array = []
var evidence: Dictionary = {}
var utility: RefCounted
var fault_mode: String = ""
var fault_calls: int = 0
var adapter: RefCounted
var mutate_adjacent: bool = false

class ObservedAdapter extends RefCounted:
	var native: RefCounted = ClassDB.instantiate("FlightInteractiveSession")
	var calls: Array = []
	var replies: Array = []
	var joined: bool = false
	var mutate_adjacent: bool = false
	var mutated: bool = false
	func _record(method: String, args: Array) -> Dictionary:
		calls.append({"method":method,"arguments":args.duplicate(true)})
		var reply: Dictionary = native.callv(method,args)
		replies.append(reply.duplicate(true))
		return reply
	func open_session(root: String, start: String, wind: Variant="calm", profile: Variant="original-interactive-prototype") -> Dictionary:
		return _record("open_session",[root,start,wind,profile])
	func read_state() -> Dictionary: return _record("read_state",[])
	func submit(command: Dictionary) -> Dictionary: return _record("submit",[command])
	func session_control(command: Dictionary) -> Dictionary: return _record("session_control",[command])
	func step_fixed(count: int) -> Dictionary:
		var reply: Dictionary = _record("step_fixed",[count])
		if mutate_adjacent and reply.get("completed",0)==1:
			var regex: RegEx=RegEx.new()
			regex.compile('("id":"engine\\.mixture","quantity":"fraction","value":)([^,]+)(,"validity":"valid")')
			var matches: Array=regex.search_all(reply.aircraft_json)
			if matches.size()==1:
				var found: RegExMatch=matches[0]
				reply.aircraft_json=reply.aircraft_json.substr(0,found.get_start(2))+"0.060000000000000005"+reply.aircraft_json.substr(found.get_end(2))
				mutated=true
		return reply
	func close() -> Dictionary:
		var result: Dictionary = _record("close",[])
		joined = result.get("ok") == true and result.get("joined") == true
		return result

static func run(piston_root: String="", include_piston: bool=true) -> Dictionary:
	return new()._run(piston_root,include_piston)

func _check(ok: bool, label: String) -> bool:
	checks += 1
	if not ok: failures.append(label)
	return ok

static func _bits(value: float) -> String:
	var bytes: PackedByteArray = PackedByteArray()
	bytes.resize(8)
	bytes.encode_double(0,value)
	return bytes.hex_encode()

static func _keys(value: Variant, wanted: Array) -> bool:
	if typeof(value) != TYPE_DICTIONARY or value.size() != wanted.size(): return false
	for key in value:
		if typeof(key) != TYPE_STRING or not wanted.has(key): return false
	return true

static func _failure(value: Variant) -> bool:
	return _keys(value,["ok","error","value"]) and typeof(value.ok)==TYPE_BOOL and value.ok==false and typeof(value.error)==TYPE_STRING and not value.error.is_empty() and value.error.length()<=256 and value.value==null

static func _success(value: Variant) -> bool:
	return _keys(value,["ok","error","value"]) and typeof(value.ok)==TYPE_BOOL and value.ok==true and typeof(value.error)==TYPE_STRING and value.error.is_empty()

static func _array_success(value: Variant, count: int) -> bool:
	if not _success(value) or typeof(value.value)!=TYPE_ARRAY or value.value.size()!=count: return false
	for item in value.value:
		if typeof(item)!=TYPE_FLOAT or not is_finite(item): return false
	return true

func _batch(tokens: Variant) -> Dictionary:
	return utility.call("decode_binary64",tokens)

func _utility_cases() -> void:
	if not _check(FileAccess.get_sha256(REFERENCE)==REFERENCE_SHA,"frozen49_reference_bytes"): return
	# This oracle contains String tokens/hex, bools and metadata only, no numeric expectations.
	var fixture: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(REFERENCE))
	if not _check(fixture.cases.size()==49,"frozen49_reference_count"): return
	var tokens: Array = []
	var expected: Array = []
	for case in fixture.cases:
		var result: Dictionary = _batch([case.token])
		if case.ok:
			var valid: bool = _success(result) and typeof(result.value)==TYPE_ARRAY and result.value.size()==1 and typeof(result.value[0])==TYPE_FLOAT and is_finite(result.value[0])
			_check(valid and _bits(result.value[0])==case.le_hex if valid else false,"oracle_"+case.id)
			tokens.append(case.token); expected.append(case.le_hex)
		else: _check(_failure(result),"oracle_reject_"+case.id)
	var combined: Dictionary = _batch(tokens)
	var exact: bool = _success(combined) and typeof(combined.value)==TYPE_ARRAY and combined.value.size()==expected.size()
	if exact:
		for i in expected.size(): exact = exact and typeof(combined.value[i])==TYPE_FLOAT and _bits(combined.value[i])==expected[i]
	_check(exact,"actual_utility_mixed_finite_batch_order_bits")
	for at in [0,tokens.size()/2,tokens.size()]:
		var invalid: Array = tokens.duplicate(true)
		invalid.insert(int(at),"1e999")
		_check(_failure(_batch(invalid)),"atomic_invalid_token_position_"+str(at))
	for value in [null,{},"0",StringName("0"),PackedStringArray(["0"]),true,0.0]:
		_check(_failure(_batch(value)),"direct_exact_array_type_"+str(typeof(value)))
	for value in [StringName("0"),0,0.0,true,null,{}]:
		_check(_failure(_batch(["0",value,"1"])),"direct_exact_string_member_"+str(typeof(value)))
	# Godot replaces NUL before this boundary. The pure native fixture retains
	# a real embedded-NUL token; this engine String negative uses actual SOH.
	var control_token: String="0"+String.chr(1)
	_check(control_token.length()==2 and control_token.unicode_at(1)==1,"utility_runtime_soh_exact_codepoint")
	_check(_failure(_batch([control_token])),"utility_runtime_soh_rejected")
	for token in [" 0","0 ","0x1","NaN","Infinity","1true","١"]:
		_check(_failure(_batch([token])),"utility_whole_ascii_grammar")
	var zeros: Array = []
	_check(_array_success(_batch([]),0),"utility_empty_batch_closed_success")
	zeros.resize(8192); zeros.fill("0")
	_check(_array_success(_batch(zeros),8192),"utility_inclusive_count8192")
	zeros.append("0"); _check(_failure(_batch(zeros)),"utility_count8193")
	var long_zero: String = "0."+"0".repeat(2046)
	_check(_array_success(_batch([long_zero]),1),"utility_token2048")
	_check(_failure(_batch([long_zero+"0"])),"utility_token2049")
	zeros.resize(512); zeros.fill(long_zero)
	_check(_array_success(_batch(zeros),512),"utility_combined1048576")
	zeros.append("0"); _check(_failure(_batch(zeros)),"utility_combined1048577")
	var first: Dictionary = _batch(["1","2"])
	if _success(first): first.value[0]=999.0
	var next: Dictionary = _batch(["1","2"])
	_check(_success(next) and next.value==[1.0,2.0],"utility_stateless_owned_array")
	evidence.oracle={"cases":49,"sha256":REFERENCE_SHA,"actual_classdb":true}

func _frontend_cases() -> void:
	var collision: Dictionary=Decoder.decode('{"NWD0":"NWD1","NWD2":["NWD0",0]}')
	_check(_success(collision) and collision.value=={"NWD0":"NWD1","NWD2":["NWD0",0.0]},"frontend_actual_placeholder_looking_keys_values_opaque")
	_check(_success(Decoder.decode('{}')),"frontend_empty_number_batch")
	var encoded: String = '{"a":[0.059999999999999998,-0,1,true,false,null,"0.06","__wire_0__"],"\\u0062":"\\uD83D\\uDE80","slash":"\\\\\\\"","é":"漢字","tick":"9007199254740993"}'
	var result: Dictionary = Decoder.decode(encoded)
	if _check(_success(result) and typeof(result.value)==TYPE_DICTIONARY,"frontend_nested_strings_numbers"):
		_check(_bits(result.value.a[0])=="b81e85eb51b8ae3f" and _bits(result.value.a[1])=="0000000000000080" and typeof(result.value.a[2])==TYPE_FLOAT,"frontend_bits_float_integer_negative_zero")
		_check(result.value.a.slice(3)==[true,false,null,"0.06","__wire_0__"] and result.value.b=="🚀" and result.value["é"]=="漢字" and result.value.tick=="9007199254740993","frontend_opaque_strings_unicode_u64")
		_check(result.value.keys()==["a","b","slash","é","tick"],"frontend_key_insertion_order")
		result.value.a[0]=999.0
		var again: Dictionary=Decoder.decode(encoded)
		_check(_success(again) and _bits(again.value.a[0])=="b81e85eb51b8ae3f","frontend_owned_nested_output")
	for bad in ['{"a":1,"\\u0061":2}','{1:2}','{"v":"\\q"}','{"v":"\\uD800"}','{"v":"\\uDC00"}','{"v":"\\uDC00\\uD800"}','{"v":1,}','{"v":[1,]}','{"v":01}','{"v":truefalse}','{"v":1e}','{"v":0x1}','[]','null','1','{"v":1}x','{"v":"'+String.chr(1)+'"}']:
		_check(_failure(Decoder.decode(bad)),"frontend_grammar_duplicate_root_unicode")
	# Complete-input/root and container grammar must reject before conversion.
	var malformed: Dictionary = {
		"second_object": '{} {}', "second_literal": '{} true',
		"trailing_number": '{"a":1} 2', "missing_colon": '{"a" 1}',
		"repeated_colon": '{"a"::1}', "leading_comma": '{,"a":1}',
		"repeated_comma": '{"a":1,,"b":2}', "missing_comma": '{"a":1 "b":2}',
		"array_leading_comma": '{"a":[,1]}', "array_repeated_comma": '{"a":[1,,2]}'
	}
	for label in malformed:
		fault_calls=0
		_check(_failure(Decoder.decode(malformed[label],_fault_converter)) and fault_calls==0,"frontend_before_batch_"+label)
	for bad in [StringName("{}"),null,{},PackedByteArray()]:
		_check(_failure(Decoder.decode(bad)),"frontend_exact_string_type")
	_check(_success(Decoder.decode('{"v":'+'['.repeat(23)+'0'+']'.repeat(23)+'}')),"frontend_depth24")
	_check(_failure(Decoder.decode('{"v":'+'['.repeat(24)+'0'+']'.repeat(24)+'}')),"frontend_depth25")
	var values: PackedStringArray = PackedStringArray()
	for i in 8192: values.append("0")
	_check(_success(Decoder.decode('{"v":['+','.join(values)+']}')),"frontend_array_numeric8192")
	values.append("0"); _check(_failure(Decoder.decode('{"v":['+','.join(values)+']}')),"frontend_array_numeric8193")
	values.clear()
	for i in 8192: values.append('"k'+str(i)+'":false')
	_check(_success(Decoder.decode('{'+','.join(values)+'}')),"frontend_object8192")
	values.append('"over":false'); _check(_failure(Decoder.decode('{'+','.join(values)+'}')),"frontend_object8193")
	values.clear()
	# Exact independent node count: root+key+outer=3;8191*(array+3strings)+1=32765.
	for i in 8191: values.append('["a","b","c"]')
	values.append('"z"')
	_check(_success(Decoder.decode('{"v":['+','.join(values)+']}')),"frontend_nodes32768")
	values[-1]='["z"]'; _check(_failure(Decoder.decode('{"v":['+','.join(values)+']}')),"frontend_nodes32769")
	_check(_success(Decoder.decode('{"v":"'+'x'.repeat(1048576-8)+'"}')),"frontend_input_bytes1048576")
	_check(_failure(Decoder.decode('{"v":"'+'x'.repeat(1048576-7)+'"}')),"frontend_input_bytes1048577")
	_check(_failure(Decoder.decode('{"v":"'+'é'.repeat(524285)+'"}')),"frontend_utf8_bytes_exceed_chars_within")
	evidence.cap_limits="Actual inclusive/failing reachable limits. Side entries32768 and transformed4MiB cannot independently saturate below mandatory root/node/input caps; no test bypass or claim of simultaneous maxima."

func _fault_converter(_tokens: Array) -> Variant:
	fault_calls+=1
	match fault_mode:
		"empty": return {}
		"extra": return {"ok":true,"error":"","value":[0.0],"extra":true}
		"wrong_ok": return {"ok":1,"error":"","value":[0.0]}
		"name_key": return {StringName("ok"):true,"error":"","value":[0.0]}
		"name_error": return {"ok":false,"error":StringName("bad"),"value":null}
		"error_success": return {"ok":true,"error":"bad","value":[0.0]}
		"partial_failure": return {"ok":false,"error":"bad","value":[0.0]}
		"long_error": return {"ok":false,"error":"x".repeat(257),"value":null}
		"count": return {"ok":true,"error":"","value":[]}
		"packed": return {"ok":true,"error":"","value":PackedFloat64Array([0.0])}
		"integer": return {"ok":true,"error":"","value":[0]}
		"nan": return {"ok":true,"error":"","value":[NAN]}
		"inf": return {"ok":true,"error":"","value":[INF]}
		"wrong_zero": return {"ok":true,"error":"","value":[0.0]}
	return null

func _fault_shapes() -> void:
	for mode in ["empty","extra","wrong_ok","name_key","name_error","error_success","partial_failure","long_error","count","packed","integer","nan","inf","wrong_zero","null"]:
		fault_mode=mode; fault_calls=0
		_check(_failure(Decoder.decode('{"v":-0}',_fault_converter)) and fault_calls==1,"synthetic_converter_shape_"+mode)
	fault_calls=0
	_check(_failure(Decoder.decode('{"v":01}',_fault_converter)) and fault_calls==0,"scan_rejects_before_fault_converter")
	evidence.synthetic_converter_faults="Failure shapes only; no fake positive counts as helper qualification. No callable-throw test: engine script error would itself fail clean-log gate."

func _factory() -> RefCounted:
	adapter=ObservedAdapter.new()
	adapter.mutate_adjacent=mutate_adjacent
	return adapter

func _native_witness(root: String) -> void:
	var facade: RefCounted=Facade.new(_factory)
	var opened: Dictionary=facade.start(root,"piston-cold-ground","calm",Facade.PISTON_PROFILE.id)
	if not _check(opened.ok,"actual_native_cold_open"):
		facade.close(); return
	var resumed: Dictionary=facade.set_paused(false)
	var axes: Dictionary=facade.readback().held_axes.duplicate(true)
	axes.mixture=0.06; axes.throttle=0.06; axes.trim=-0.06
	_check(resumed.ok and facade.set_pilot_intent(axes,Facade.COLD_SYSTEMS.duplicate(true)).ok,"actual_complete_pilot_intent")
	var progressed: Dictionary=facade.advance_wall_us(8334)
	var source: Dictionary=facade.readback()
	_check(progressed.ok and source.tick=="1","actual_one_completed_cold_tick")
	var native_reply: Dictionary={}
	for reply in adapter.replies:
		if reply.get("completed",0)==1: native_reply=reply.duplicate(true)
	if _check(not native_reply.is_empty(),"observed_actual_completed_reply"):
		var decoded: Dictionary=Decoder.decode(native_reply.aircraft_json)
		var actual_mixture: Variant=null
		if _success(decoded):
			for system in decoded.value.systems:
				if system.id=="engine.mixture": actual_mixture=system.value
		_check(typeof(actual_mixture)==TYPE_FLOAT and _bits(actual_mixture)==_bits(native_reply.held_axes.mixture) and _bits(actual_mixture)=="b81e85eb51b8ae3f","actual_native_decimal_equals_typed_held_bits")
		var readings: Dictionary=Readings.from_readback(source)
		var engine: Dictionary=EngineStatus.from_readback(source)
		_check(readings.state=="live" and engine.state=="live" and engine.readings["engine.mixture"].valid and _bits(engine.readings["engine.mixture"].value)=="b81e85eb51b8ae3f","actual_decode_readings_engine_status_accept06")
		var regex: RegEx=RegEx.new()
		regex.compile('("id":"engine\\.mixture","quantity":"fraction","value":)([^,]+)(,"validity":"valid")')
		var matches: Array=regex.search_all(native_reply.aircraft_json)
		if _check(matches.size()==1,"unique_actual_mixture_token"):
			var found: RegExMatch=matches[0]
			var adjacent: String=native_reply.aircraft_json.substr(0,found.get_start(2))+"0.060000000000000005"+native_reply.aircraft_json.substr(found.get_end(2))
			var wrong: Dictionary=Decoder.decode(adjacent)
			var contradiction: Dictionary=source.duplicate(true)
			if _success(wrong): contradiction.aircraft=wrong.value
			_check(_success(wrong) and Readings.from_readback(contradiction).state=="invalid" and EngineStatus.from_readback(contradiction).state=="invalid","synthetic_adjacent_system_still_rejected")
			evidence.actual_mixture_token=found.get_string(2)
		var command_count: int=0
		for record in native_reply.get("applied_commands_json",[]):
			var command: Dictionary=Decoder.decode(record)
			_check(_success(command) and typeof(command.value.tick)==TYPE_STRING and typeof(command.value.sequence)==TYPE_STRING,"actual_applied_command_strings_and_numbers")
			if _success(command) and command.value.payload.kind=="axes":
				command_count+=1
				_check(_bits(command.value.payload.mixture)=="b81e85eb51b8ae3f" and _bits(command.value.payload.throttle)=="b81e85eb51b8ae3f" and _bits(command.value.payload.trim)=="b81e85eb51b8aebf","actual_applied_axes_exact_original_bits")
		_check(command_count==1,"nonvacuous_actual_applied_axes_command")
		var weather: Dictionary=Decoder.decode(native_reply.atmosphere_json)
		_check(_success(weather) and weather.value==source.atmosphere and typeof(weather.value.seed)==TYPE_STRING,"actual_weather_complete_exact_decode_seed_string")
		_check(_bits(source.held_axes.throttle)=="b81e85eb51b8ae3f" and _bits(source.held_axes.trim)=="b81e85eb51b8aebf","actual_throttle_trim_exact_held")
		evidence.native={"aircraft_json":native_reply.aircraft_json,"atmosphere_json":native_reply.atmosphere_json,"applied_commands_json":native_reply.applied_commands_json,"events_json":native_reply.events_json,"typed_held_axes":native_reply.held_axes.duplicate(true),"source_fingerprint":source.native_source_fingerprint,"tick":source.tick}
	_check(facade.set_paused(true).ok,"actual_native_pause")
	_check(facade.close().ok and adapter.joined,"actual_native_owned_close_join")
	evidence.native_calls=adapter.calls.duplicate(true)

func _adjacent_facade(root: String) -> void:
	mutate_adjacent=true
	var facade: RefCounted=Facade.new(_factory)
	var opened: Dictionary=facade.start(root,"piston-cold-ground","calm",Facade.PISTON_PROFILE.id)
	if _check(opened.ok,"synthetic_adjacent_actual_native_open"):
		_check(facade.set_paused(false).ok,"synthetic_adjacent_actual_native_resume")
		var axes: Dictionary=facade.readback().held_axes.duplicate(true)
		axes.mixture=0.06; axes.throttle=0.06; axes.trim=-0.06
		_check(facade.set_pilot_intent(axes,Facade.COLD_SYSTEMS.duplicate(true)).ok,"synthetic_adjacent_pilot_intent")
		var before: Dictionary=facade.readback()
		var result: Dictionary=facade.advance_wall_us(8334)
		var after: Dictionary=facade.readback()
		_check(adapter.mutated and not result.ok and after.tick==before.tick and after.aircraft==before.aircraft and after.atmosphere==before.atmosphere,"synthetic_adjacent_facade_rejects_retains_last_verified_source")
		_check(after.host_mode=="discarded" and not after.native_live,"synthetic_adjacent_terminal_fault_no_repair")
	_check(facade.close().ok and adapter.joined,"synthetic_adjacent_actual_owned_close_join")
	evidence.adjacent_fault={"mutated":adapter.mutated,"actual_calls":adapter.calls.duplicate(true),"actual_unmodified_replies":adapter.replies.duplicate(true),"scope":"Synthetic single engine.mixture token substitution on actual one-tick reply; native typed controls and all other bytes retained."}
	mutate_adjacent=false

func _run(root: String, include_piston: bool) -> Dictionary:
	if _check(ClassDB.class_exists("FlightWireNumbers"),"actual_class_registered"):
		utility=ClassDB.instantiate("FlightWireNumbers")
		if _check(utility!=null and utility.has_method("decode_binary64"),"actual_class_method"):
			_utility_cases(); _frontend_cases(); _fault_shapes()
	if include_piston:
		if _check(not root.is_empty() and ClassDB.class_exists("FlightInteractiveSession"),"actual_native_prerequisites"):
			_native_witness(root)
			_adjacent_facade(root)
	else: evidence.native_witness="Explicitly not run: upstream no-piston build. Does not qualify issue204 native-backed repair."
	utility=null
	return {"passed":failures.is_empty(),"checks":checks,"failures":failures.duplicate(),"evidence":evidence.duplicate(true),"scope":"Actual utility/frontend plus optional actual one-tick original-piston publication. No physics solver, aircraft fidelity, phase acceptance or shaft-domain repair claim."}
