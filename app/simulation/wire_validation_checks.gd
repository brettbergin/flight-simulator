extends RefCounted
# Original MIT. Caller supplies the four accepted original contract fixtures.
# Mutants exercise the production validators, never modify native records.
const Wire = preload("res://simulation/wire_validation.gd")
const METHODS: Dictionary = {"AircraftSnapshot":"aircraft","AtmosphereSample":"atmosphere","ControlCommand":"command","OperationalEvent":"event"}

static func _check(result: Dictionary, passed: bool, label: String) -> void:
	result.checks += 1
	if not passed:
		result.failures.append(label)
		result.passed = false

static func _at(record: Dictionary, path: Array) -> Variant:
	var cursor: Variant = record
	for key in path:
		cursor = cursor[key]
	return cursor

static func _objects(value: Variant, path: Array, objects: Array, leaves: Array) -> void:
	if value is Dictionary:
		objects.append(path)
		for key in value:
			_objects(value[key],path+[key],objects,leaves)
	elif value is Array:
		for i in value.size():
			_objects(value[i],path+[i],objects,leaves)
	else:
		leaves.append([path,value])

static func _changed(base: Dictionary, path: Array, value: Variant) -> Dictionary:
	var copy: Dictionary = base.duplicate(true)
	var parent: Variant = _at(copy,path.slice(0,path.size()-1))
	parent[path[-1]] = value
	return copy

static func run(fixtures: Dictionary) -> Dictionary:
	var result: Dictionary = {"passed":true,"checks":0,"failures":[]}
	var validator: RefCounted = Wire.new()
	var records: Dictionary = fixtures.duplicate(true)
	for type_name in METHODS:
		if not records.has(type_name) or not validator.call(METHODS[type_name],records[type_name]):
			_check(result,false,"Accepted fixture unavailable/invalid: "+type_name)
			return result
	# Add schema-valid contacts and bool system so nested cases are exercised.
	records.AircraftSnapshot.contacts = [{"id":"gear.nose","point_body_m":{"x":2.0,"y":0.0,"z":1.0},"force_body_n":{"x":0.0,"y":0.0,"z":-10.0},"on_ground":true}]
	records.AircraftSnapshot.systems.append({"id":"battery.on","quantity":"bool","value":true,"validity":"unavailable"})
	for type_name in METHODS:
		var base: Dictionary = records[type_name]
		var method: String = METHODS[type_name]
		_check(result,validator.call(method,base),"Schema-valid baseline "+type_name)
		for bad in [null,[],true,1,"record"]:
			_check(result,not validator.call(method,bad),"Nonobject "+type_name)
		var objects: Array = []
		var leaves: Array = []
		_objects(base,[],objects,leaves)
		for path in objects:
			var extra: Dictionary = base.duplicate(true)
			_at(extra,path)["unexpected"] = 0
			_check(result,not validator.call(method,extra),"Extra key "+type_name+JSON.stringify(path))
			for key in _at(base,path):
				var missing: Dictionary = base.duplicate(true)
				_at(missing,path).erase(key)
				_check(result,not validator.call(method,missing),"Missing key "+type_name+JSON.stringify(path+[key]))
		for leaf in leaves:
			if typeof(leaf[1]) == TYPE_INT or typeof(leaf[1]) == TYPE_FLOAT:
				for bad in [NAN,INF,-INF,true,"0"]:
					_check(result,not validator.call(method,_changed(base,leaf[0],bad)),"Numeric type/finite "+type_name+JSON.stringify(leaf[0]))
			elif typeof(leaf[1]) == TYPE_BOOL:
				_check(result,not validator.call(method,_changed(base,leaf[0],1)),"Bool is not numeric "+type_name+JSON.stringify(leaf[0]))
		for key in ["tick","sequence","seed"]:
			if base.has(key):
				for bad in ["01","-1","18446744073709551616","9e3",1]:
					_check(result,not validator.call(method,_changed(base,[key],bad)),"uint64 identity "+type_name+"/"+key)
	var finite_mutants: Array = [
		["AircraftSnapshot",["mass_kg"],-1.0],["AircraftSnapshot",["mass_kg"],0.0009],["AircraftSnapshot",["mass_kg"],1000001.0],
		["AircraftSnapshot",["elapsed_s"],1.0],["AircraftSnapshot",["clock","tick_rate_hz"],60.0],
		["AircraftSnapshot",["position","latitude_rad"],PI],["AircraftSnapshot",["position","longitude_rad"],PI+0.001],
		["AircraftSnapshot",["position","ellipsoid_height_m"],10000001.0],["AircraftSnapshot",["ecef_position_m","x"],6378137.001],
		["AircraftSnapshot",["orientation_body_to_ned","w"],0.5],
		["AircraftSnapshot",["configuration","flap_fraction"],-0.1],["AircraftSnapshot",["configuration","gear_fraction"],1.1],["AircraftSnapshot",["configuration","trim_fraction"],-1.1],
		["AircraftSnapshot",["systems",0,"quantity"],"unknown"],["AircraftSnapshot",["systems",1,"value"],1],
		["AircraftSnapshot",["contacts",0,"id"],"Invalid ID"],
		["AtmosphereSample",["pressure_pa"],0.0],["AtmosphereSample",["pressure_pa"],200001.0],
		["AtmosphereSample",["temperature_k"],401.0],["AtmosphereSample",["density_kgpm3"],-1.0],["AtmosphereSample",["density_kgpm3"],11.0],
		["AtmosphereSample",["relative_humidity"],-0.1],["AtmosphereSample",["relative_humidity"],1.1],
		["ControlCommand",["source_id"],"pilot..controls"],["ControlCommand",["authority"],"override"],
		["ControlCommand",["assistance","profile_id"],"x".repeat(129)],["ControlCommand",["payload","left_brake"],-0.1],["ControlCommand",["payload","trim"],1.1],
		["OperationalEvent",["source_id"],"Upper"],["OperationalEvent",["content_version"],"1.2"],["OperationalEvent",["confidence"],"certain"],
		["OperationalEvent",["payload","kind"],"unknown"]
	]
	for mutant in finite_mutants:
		_check(result,not validator.call(METHODS[mutant[0]],_changed(records[mutant[0]],mutant[1],mutant[2])),"Finite/schema semantic mutant "+JSON.stringify(mutant))
	for key in ["systems","contacts"]:
		var copy: Dictionary = records.AircraftSnapshot.duplicate(true)
		copy[key].append(copy[key][0].duplicate(true))
		_check(result,not Wire.aircraft(copy),"Duplicate "+key+" identifier")
		copy = records.AircraftSnapshot.duplicate(true)
		copy[key] = []
		for i in (257 if key == "systems" else 33):
			var item: Dictionary = records.AircraftSnapshot[key][0].duplicate(true)
			item.id = "bounded-"+str(i)
			copy[key].append(item)
		_check(result,not Wire.aircraft(copy),"Bounded "+key+" array")
	var assisted: Dictionary = records.ControlCommand.duplicate(true)
	assisted.assistance.active = []
	for i in 65:
		assisted.assistance.active.append("assist-"+str(i))
	_check(result,not Wire.command(assisted),"Bounded assistance array")
	for quantity in ["fraction","k"]:
		var copy: Dictionary = records.AircraftSnapshot.duplicate(true)
		copy.systems[0].quantity = quantity
		copy.systems[0].value = 1.1 if quantity == "fraction" else 0.0
		_check(result,not Wire.aircraft(copy),"System quantity semantic "+quantity)
	for payload in [{"kind":"system","control_id":"battery.master","value":true},{"kind":"system","control_id":"engine.mode","value":-1.0}]:
		_check(result,Wire.command(_changed(records.ControlCommand,["payload"],payload)),"Full-v1 system command positive")
	for authority in ["pilot","avionics","scenario","instructor"]:
		_check(result,Wire.command(_changed(records.ControlCommand,["authority"],authority)),"Full-v1 authority positive "+authority)
	_check(result,Wire.command(_changed(records.ControlCommand,["payload","mixture"],0.0)),"Full-v1 mixture zero; facade restriction is separate")
	var events: Array = [
		{"kind":"command-rejected","command_sequence":"18446744073709551615","reason":"capacity"},
		{"kind":"system-state","system_id":"engine.state","state":"running"},
		{"kind":"failure","failure_id":"engine.failure","active":true},
		{"kind":"procedure","procedure_id":"synthetic.check","step_id":"first","result":"observed"},
		{"kind":"clearance","clearance_id":"synthetic.clearance","aircraft_id":"original","acknowledged":false},
		{"kind":"assistance","assistance_id":"original.assist","active":false},
		{"kind":"pause","paused":true},{"kind":"time-scale","scale":1.0},
		{"kind":"session-branch","parent_session_id":"original-parent","parent_tick":"18446744073709551615"},
		{"kind":"save","checkpoint_id":"original-checkpoint","result":"saved"}
	]
	for payload in events:
		var copy: Dictionary = _changed(records.OperationalEvent,["payload"],payload)
		_check(result,Wire.event(copy),"Full-v1 event positive "+payload.kind)
		for key in payload:
			var missing: Dictionary = copy.duplicate(true)
			missing.payload.erase(key)
			_check(result,not Wire.event(missing),"Event required member "+payload.kind+"/"+key)
			var null_field: Dictionary = copy.duplicate(true)
			null_field.payload[key] = null
			_check(result,not Wire.event(null_field),"Event member type "+payload.kind+"/"+key)
		for key in ["command_sequence","parent_tick"]:
			if payload.has(key):
				var overflow: Dictionary = copy.duplicate(true)
				overflow.payload[key] = "18446744073709551616"
				_check(result,not Wire.event(overflow),"Event nested uint64 overflow "+key)
		copy.payload.unexpected = true
		_check(result,not Wire.event(copy),"Event payload closed "+payload.kind)
	# Exact wire identity remains a string even above signed-int/double limits.
	# Derived seconds below are the normative Number(BigInt(MAX))/120 reference.
	var maximum_air: Dictionary = records.AircraftSnapshot.duplicate(true)
	maximum_air.tick = "18446744073709551615"
	maximum_air.elapsed_s = 1.5372286728091293e17
	_check(result,Wire.aircraft(maximum_air),"Maximum uint64 wire tick with derived binary64 time")
	for type_name in ["AtmosphereSample","ControlCommand","OperationalEvent"]:
		var copy: Dictionary = records[type_name].duplicate(true)
		copy.tick = "18446744073709551615"
		if copy.has("sequence"):
			copy.sequence = "18446744073709551615"
		if copy.has("seed"):
			copy.seed = "18446744073709551615"
		copy.session_id = "a"+"1".repeat(127)
		_check(result,validator.call(METHODS[type_name],copy),"Full uint64/identifier bound positive "+type_name)
	return result
