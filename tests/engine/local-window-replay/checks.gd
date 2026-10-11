extends RefCounted
# Original MIT. Prospective ADR024 regression; no execution is claimed by this source.
const Identity = preload("res://build/native_identity.gd")
const Decoder = preload("res://simulation/native_wire_decoder.gd")
const Wire = preload("res://simulation/wire_validation.gd")
const RECIPE = "res://local_window_replay_tests/recipe.json"
const ARGUMENTS = "res://local_window_replay_tests/argument-binary64.json"
const RECIPE_SHA: String = "2ef833b13cab7127b19ae84272f9bfc015133e14c125d781c535b84ad284aba1"
const ARGUMENTS_SHA: String = "ffb39073782ac1226795df39b0b95512e0f444a4f2284224c9c34af4a5ef9b76"
const VARIANT: String = "jsbsim-1.3.1-event-aware-coupled-midpoint-local-window-v2"
const METHOD: String = "event_aware_coupled_midpoint_v1"
const HISTORICAL_SOURCE: String = "5e0abfeae9ffd249f8be3f4410d9903f30736698fcb276bdf72f3630132102e5"
const WORLD: String = "04bff5a0bcf3509990f6276b2548a28268f57fc96d218a7ca51cab1990ec1ff5"
const AXES: Array = ["roll","pitch","yaw","throttle","mixture","left_brake","right_brake","trim"]
var checks: int = 0
var failures: Array = []
var bridge: RefCounted
var joined: bool = false
var session: String = ""
var tick: String = ""
var restored_floats: int = 0
var schema_ints: int = 0
var step_ints: int = 0
var continuation_completed: int = 0
var expected_tick: int = 0
var calls: Array = []
var publications: Array = []

static func run(piston_root: String) -> Dictionary:
	return new()._run(piston_root)

func _check(ok: bool, label: String) -> bool:
	checks += 1
	if not ok: failures.append(label)
	return ok

static func _keys(value: Variant, wanted: Array) -> bool:
	if typeof(value)!=TYPE_DICTIONARY or value.size()!=wanted.size(): return false
	for key in value:
		if typeof(key)!=TYPE_STRING or not wanted.has(key): return false
	return true

func _fixture(path: String, sha: String, cap: int) -> Variant:
	if not _check(FileAccess.file_exists(path) and FileAccess.get_sha256(path)==sha,"fixture_sha_"+path.get_file()): return null
	var file: FileAccess = FileAccess.open(path,FileAccess.READ)
	if not _check(file!=null,"fixture_open_"+path.get_file()): return null
	var bounded: bool = file.get_length()<=cap
	var text: String = file.get_as_text() if bounded else ""
	file.close()
	if not _check(bounded,"fixture_bound_"+path.get_file()): return null
	var parser: JSON = JSON.new()
	if not _check(parser.parse(text)==OK,"fixture_structural_json_"+path.get_file()): return null
	return parser.data

static func _bits(value: float) -> String:
	var bytes: PackedByteArray = PackedByteArray()
	bytes.resize(8)
	bytes.encode_double(0,value)
	return bytes.hex_encode()

func _restore(payload: Dictionary, fields: Dictionary) -> bool:
	for field in fields:
		if not _check(typeof(payload.get(field))==TYPE_FLOAT and typeof(fields[field])==TYPE_STRING and fields[field].length()==16,"qualified_float_"+field): return false
		var bytes: PackedByteArray = fields[field].hex_decode()
		if not _check(bytes.size()==8 and bytes.hex_encode()==fields[field],"canonical_float_hex_"+field): return false
		var value: float = bytes.decode_double(0)
		if not _check(is_finite(value),"finite_original_float_"+field): return false
		payload[field]=value
		if not _check(typeof(payload[field])==TYPE_FLOAT and _bits(payload[field])==fields[field],"restored_original_float_"+field): return false
		restored_floats+=1
	return true

func _compact(reply: Dictionary, expected: Dictionary, index: int) -> bool:
	for key in expected:
		if not _check(reply.has(key),"compact_has_%d_%s"%[index,key]): return false
		var want: Variant = expected[key]
		var got: Variant = reply[key]
		if key in ["completed","rejection"]:
			if not _check(typeof(want)==TYPE_FLOAT and is_finite(want) and want==floor(want) and typeof(got)==TYPE_INT and got==int(want),"compact_integer_%d_%s"%[index,key]): return false
		elif not _check(typeof(got)==typeof(want) and got==want,"compact_exact_%d_%s"%[index,key]): return false
	return true

func _publication(reply: Dictionary, index: int) -> bool:
	if not _check(typeof(reply.get("aircraft_json"))==TYPE_STRING and typeof(reply.get("atmosphere_json"))==TYPE_STRING,"native_text_%d"%index): return false
	var a: Dictionary = Decoder.decode(reply.aircraft_json)
	var w: Dictionary = Decoder.decode(reply.atmosphere_json)
	if not _check(a.ok and w.ok and Wire.aircraft(a.value) and Wire.atmosphere(w.value),"full_wire_%d"%index): return false
	if index==0:
		session=a.value.session_id
		if not _check(typeof(session)==TYPE_STRING and not session.is_empty() and session!="@session_id","fresh_session"): return false
		if not _check(reply.get("native_source_fingerprint")==Identity.SOURCE_FINGERPRINT and reply.get("angular_integration_method")==METHOD,"actual_source_and_method"): return false
		if not _check(reply.get("prepared_world_sha256")==WORLD,"unchanged_prepared_world"): return false
		if not _check(reply.get("named_start")=="piston-cold-ground" and reply.get("wind_profile")=="calm","actual_cold_calm_start"): return false
	if not _check(a.value.session_id==session and w.value.session_id==session and a.value.tick==w.value.tick,"native_pair_%d"%index): return false
	if not _check(a.value.validity=="valid" and a.value.clock.tick_rate_hz==120.0 and a.value.clock.purpose=="runtime" and a.value.position==w.value.position and w.value.model_id=="jsbsim-dry-isa" and w.value.seed=="42","qualified_runtime_pair_%d"%index): return false
	var held: Variant = reply.get("held_axes")
	if not _check(_keys(held,["kind","roll","pitch","yaw","throttle","mixture","left_brake","right_brake","trim"]) and held.kind=="axes","typed_held_axes_%d"%index): return false
	for axis in AXES:
		if not _check(typeof(held[axis])==TYPE_FLOAT and is_finite(held[axis]),"finite_held_%d_%s"%[index,axis]): return false
	var channels: Dictionary = {}
	for channel in a.value.systems: channels[channel.id]=channel
	for pair in [["engine.throttle","throttle"],["engine.mixture","mixture"]]:
		var channel: Variant = channels.get(pair[0])
		if not _check(typeof(channel)==TYPE_DICTIONARY and channel.quantity=="fraction" and channel.validity=="valid" and typeof(channel.value)==TYPE_FLOAT and _bits(channel.value)==_bits(held[pair[1]]),"exact_native_held_fraction_%d_%s"%[index,pair[0]]): return false
	tick=a.value.tick
	if not _check(tick==str(expected_tick),"exact_completed_tick_%d"%index): return false
	if not _check(reply.get("live")==true and reply.get("historical")==false and reply.get("fault")=="","nonterminal_native_%d"%index): return false
	if index in [0,295,296]:
		var checkpoint_tick: String = {0:"0",295:"1579",296:"1607"}[index]
		if not _check(tick==checkpoint_tick,"checkpoint_tick_%d"%index): return false
		publications.append({"index":index,"tick":tick,"aircraft_json":reply.aircraft_json,"atmosphere_json":reply.atmosphere_json,"held_axes":held.duplicate(true)})
	return true

func _finish() -> Dictionary:
	# Only failure cleanup may add a close. It never counts toward the298-call pass.
	if bridge!=null and not joined:
		var cleanup: Variant = bridge.call("close")
		_check(typeof(cleanup)==TYPE_DICTIONARY and cleanup.get("ok")==true and cleanup.get("joined")==true,"failure_cleanup_joined")
		joined=typeof(cleanup)==TYPE_DICTIONARY and cleanup.get("ok")==true and cleanup.get("joined")==true
	bridge=null
	return {"passed":failures.is_empty() and calls.size()==298 and publications.size()==3 and joined and tick=="1607" and continuation_completed==28 and restored_floats==138 and schema_ints==31 and step_ints==265,
		"checks":checks,"failures":failures.duplicate(true),"scope":"Actual original298 calls; prospective local-window-v2 completion, full native v1 publications and joined close. No scene, assists, state injection, fitted golden or aircraft validation.",
		"recipe_sha256":RECIPE_SHA,"argument_binary64_sha256":ARGUMENTS_SHA,"source_fingerprint":Identity.SOURCE_FINGERPRINT,"source_variant":Identity.SOURCE_VARIANT,"angular_integration_method":METHOD,
		"argument_float_fields":restored_floats,"schema_integer_fields":schema_ints,"step_integer_fields":step_ints,"final_tick":tick,"continuation_completed":continuation_completed,"joined":joined,"calls":calls.duplicate(true),"publications":publications.duplicate(true)}

func _run(piston_root: String) -> Dictionary:
	if not _check(Identity.SOURCE_VARIANT==VARIANT and Identity.SOURCE_FINGERPRINT!=HISTORICAL_SOURCE,"qualified_new_source_variant"): return _finish()
	var recipe: Variant = _fixture(RECIPE,RECIPE_SHA,262144)
	var sidecar: Variant = _fixture(ARGUMENTS,ARGUMENTS_SHA,32768)
	if not _check(typeof(recipe)==TYPE_DICTIONARY and _keys(sidecar,["schema","recipe_sha256","argument_binary64_le"]),"fixture_objects"): return _finish()
	if not _check(recipe.schema=="PistonMixtureDecayRecipe/v1" and recipe.source_fingerprint==HISTORICAL_SOURCE and sidecar.schema=="PistonMixtureDecayArgumentBinary64/v1" and sidecar.recipe_sha256==RECIPE_SHA,"historical_provenance_preserved"): return _finish()
	if not _check(typeof(recipe.calls)==TYPE_ARRAY and recipe.calls.size()==298 and typeof(sidecar.argument_binary64_le)==TYPE_DICTIONARY,"bounded_call_and_sidecar_shapes"): return _finish()
	# Validate every portable sidecar path before allocating a native session.
	var anticipated: int = 0
	var expected_sidecar_keys: Array = []
	for index in recipe.calls.size():
		var call: Dictionary = recipe.calls[index]
		if not _check(call.index==index,"original_index_%d"%index): return _finish()
		if call.method in ["submit","session_control"]:
			var payload: Dictionary = call.arguments[0].payload
			var wanted: Array = AXES if payload.kind=="axes" else (["scale"] if payload.kind=="time_scale" else [])
			if not wanted.is_empty():
				expected_sidecar_keys.append(str(index))
				if not _check(_keys(sidecar.argument_binary64_le.get(str(index)),wanted),"closed_float_paths_%d"%index): return _finish()
				anticipated+=wanted.size()
	if not _check(_keys(sidecar.argument_binary64_le,expected_sidecar_keys) and anticipated==138,"all138_closed_float_paths"): return _finish()
	if not _check(ClassDB.class_exists("FlightInteractiveSession"),"native_class_loaded"): return _finish()
	bridge=ClassDB.instantiate("FlightInteractiveSession")
	if not _check(bridge!=null,"native_instance"): return _finish()
	for index in recipe.calls.size():
		var call: Dictionary = recipe.calls[index]
		var method: String = call.method
		var args: Array = call.arguments.duplicate(true)
		if method=="open_session":
			if not _check(index==0 and args==["@model_root","piston-cold-ground","calm","original-piston-prop-v1"],"unchanged_cold_open"): break
			args[0]=piston_root
		elif method in ["submit","session_control"]:
			if not _check(args.size()==1 and args[0].session_id=="@session_id" and typeof(args[0].schema_version)==TYPE_FLOAT and args[0].schema_version==1.0,"protocol_binding_%d"%index): break
			args[0].session_id=session
			args[0].schema_version=1
			schema_ints+=1
			if sidecar.argument_binary64_le.has(str(index)):
				if not _restore(args[0].payload,sidecar.argument_binary64_le[str(index)]): break
		elif method=="step_fixed":
			if not _check(args.size()==1 and typeof(args[0])==TYPE_FLOAT and is_finite(args[0]) and args[0]==floor(args[0]) and args[0]>=1 and args[0]<=32,"bounded_step_%d"%index): break
			args[0]=int(args[0])
			step_ints+=1
		elif not _check(method=="close" and index==297 and args.is_empty(),"unchanged_final_close"): break
		var result: Variant = bridge.callv(method,args)
		if not _check(typeof(result)==TYPE_DICTIONARY,"native_reply_%d"%index): break
		calls.append({"index":index,"method":method,"arguments":args.duplicate(true),"reply":result.duplicate(true)})
		var expected: Dictionary = call.expected.duplicate(true)
		if index==296:
			# Prospective criterion fixed before outputs; historical fixture remains unchanged.
			expected.outcome="completed"
			expected.completed=28.0
			expected.live=true
			expected.historical=false
			expected.fault=""
			if typeof(result.get("completed"))==TYPE_INT: continuation_completed=result.completed
		if expected.has("completed"): expected_tick+=int(expected.completed)
		if method=="close": joined=result.get("ok")==true and result.get("joined")==true
		elif not _publication(result,index): break
		if not _compact(result,expected,index): break
	return _finish()
