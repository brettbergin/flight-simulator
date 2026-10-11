extends RefCounted
# Original MIT. Frozen references are decoded from bits, never decimal text.
const Policy=preload("res://camera/view_policy.gd")
const REFERENCE="res://camera_tests/expected-v1.json"
const REFERENCE_SHA="d3ee38b2a2455e7a21c61ae46f01461dd901663c3743581059e19c5193f513cd"
const PRESETS=["cockpit","forward_horizon","left_window","right_window","panel","chase","orbit"]
const DIRECTION_ERROR=3e-6
const POSITION_ERROR=1e-4
const RAY_ERROR=3e-4
const ALPHA_ERROR=2e-14

static func check(result: Dictionary, ok: bool, label: String) -> void:
	result.checks+=1
	if not ok: result.failures.append(label)

static func receipt(scope: String) -> Dictionary:
	return {"passed":false,"checks":0,"failures":[],"scope":scope}

static func finish(result: Dictionary) -> Dictionary:
	result.passed=result.failures.is_empty() and result.checks>0
	return result

static func closed(value: Variant, names: Array) -> bool:
	if typeof(value)!=TYPE_DICTIONARY or value.size()!=names.size(): return false
	for key in value:
		if typeof(key)!=TYPE_STRING or not names.has(key): return false
	return true

static func exact(a: Variant,b: Variant) -> bool:
	# Captures integer/float distinctions and all binary64 bits, including -0.
	return var_to_bytes(a)==var_to_bytes(b)

static func number(descriptor: Dictionary) -> float:
	return str(descriptor.binary64_le).hex_decode().decode_double(0)

static func decode(value: Variant) -> Variant:
	if value is Dictionary:
		if value.has("binary64_le"): return number(value)
		var out: Dictionary={}
		for key in value: out[key]=decode(value[key])
		return out
	if value is Array:
		var out: Array=[]
		for entry in value: out.append(decode(entry))
		return out
	return value

static func references(result: Dictionary) -> Dictionary:
	check(result,FileAccess.get_sha256(REFERENCE)==REFERENCE_SHA,"frozen_reference_bytes")
	if not result.failures.is_empty(): return {}
	var value: Variant=JSON.parse_string(FileAccess.get_file_as_string(REFERENCE))
	check(result,value is Dictionary and value.get("direction_cases",[]).size()==31,"reference_structure")
	return value if value is Dictionary else {}

static func settings(value: Variant) -> bool:
	return closed(value,["preset","fov_deg","external_response"]) and typeof(value.preset)==TYPE_STRING and typeof(value.fov_deg)==TYPE_FLOAT and typeof(value.external_response)==TYPE_STRING

static func mutated(row: Dictionary) -> Variant:
	var value: Variant=decode(row.base_input)
	var edit: Dictionary=row.edit
	if edit.has("remove"): value.erase(edit.remove)
	elif edit.has("add"): value.merge(edit.add)
	elif edit.has("key_type"):
		var previous: Variant=value[edit.key]
		value.erase(edit.key)
		value[StringName(edit.key)]=previous
	elif edit.has("binary64_le"): value.fov_deg=number(edit)
	elif edit.has("replace_root_variant"):
		match edit.replace_root_variant:
			"NIL": value=null
			"ARRAY": value=[]
			"OBJECT": value=RefCounted.new()
	elif edit.has("field"):
		match edit.variant:
			"INT": value[edit.field]=int(edit.value)
			"BOOL": value[edit.field]=bool(edit.value)
			"STRING": value[edit.field]=str(edit.value)
			"STRING_NAME": value[edit.field]=StringName(edit.value)
	return value

static func validated(result: Dictionary, value: Variant, expected_ok: bool, label: String) -> Variant:
	var before: PackedByteArray=var_to_bytes(value) if not value is Object else PackedByteArray()
	var reply: Variant=Policy.validate(value)
	check(result,closed(reply,["ok","error","value"]),label+"_closed_result")
	if not closed(reply,["ok","error","value"]): return null
	check(result,typeof(reply.ok)==TYPE_BOOL and typeof(reply.error)==TYPE_STRING,label+"_result_types")
	check(result,reply.ok==expected_ok,label+"_admission")
	if expected_ok:
		check(result,reply.error=="" and settings(reply.value) and exact(reply.value,value),label+"_owned_exact_value")
	else:
		check(result,reply.error!="" and reply.value==null,label+"_rejection")
	if not value is Object: check(result,var_to_bytes(value)==before,label+"_input_unmodified")
	return reply.value

static func run() -> Dictionary:
	var result: Dictionary=receipt("Pure policy admission/copies only; no scene, native, hardware or visual acceptance")
	var refs: Dictionary=references(result)
	if refs.is_empty(): return finish(result)
	var defaults: Variant=Policy.defaults()
	check(result,settings(defaults) and exact(defaults,decode(refs.defaults.settings)),"defaults_exact")
	for row in refs.mappings:
		var item: Variant=Policy.describe(row.preset)
		check(result,closed(item,["mode","base_direction","default_fov_deg"]),row.preset+"_closed_description")
		if not closed(item,["mode","base_direction","default_fov_deg"]): continue
		check(result,typeof(item.mode)==TYPE_INT and item.mode==int(row.mode) and typeof(item.default_fov_deg)==TYPE_FLOAT and exact(item.default_fov_deg,number(row.default_fov)),row.preset+"_mode_and_fov")
		if row.base_direction==null:
			check(result,item.base_direction==null,row.preset+"_host_direction")
		else:
			check(result,typeof(item.base_direction)==TYPE_ARRAY and item.base_direction.size()==3,row.preset+"_direction_array")
			if typeof(item.base_direction)==TYPE_ARRAY and item.base_direction.size()==3:
				for i in range(3):
					check(result,typeof(item.base_direction[i])==TYPE_FLOAT and is_finite(item.base_direction[i]) and absf(item.base_direction[i]-number(row.base_direction[i]))<=DIRECTION_ERROR,row.preset+"_component_"+str(i))
		var old: Dictionary=item.duplicate(true)
		item.mode=-7
		if item.base_direction is Array: item.base_direction[0]=999.0
		check(result,exact(Policy.describe(row.preset),old),row.preset+"_description_owned")
	for bad in [null,0,1.0,true,&"cockpit","Cockpit","unknown",[],{},RefCounted.new()]:
		check(result,Policy.describe(bad)==null,"describe_reject_type_"+str(typeof(bad)))
	for row in refs.settings_positive_cases:
		validated(result,decode(row.input),true,row.id)
	for row in refs.settings_negative_cases:
		validated(result,mutated(row),false,row.id)
	# Four frozen ownership recipes, with mutations in both directions.
	var initial: Dictionary=decode(refs.defaults.settings)
	var first: Dictionary=Policy.defaults()
	first.preset="orbit"
	check(result,exact(Policy.defaults(),initial),"C01_defaults_owned")
	var source: Dictionary=decode(refs.lifecycle_initial_camera.settings)
	var original: Dictionary=source.duplicate(true)
	var accepted: Variant=validated(result,source,true,"copy_setup")
	if accepted is Dictionary:
		source.fov_deg=35.0
		check(result,exact(accepted,original),"C02_input_does_not_alias_output")
		accepted.external_response="smooth"
		check(result,source.external_response=="immediate","C03_output_does_not_alias_input")
		check(result,exact(Policy.validate(original).value,original),"C04_later_validation_owned")
	return finish(result)
