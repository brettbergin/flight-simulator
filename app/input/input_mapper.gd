extends RefCounted
# Original MIT implementation of ADR008. Presentation input only; no native calls.
const Preset = preload("res://input/input_preset.gd")
const TARGETS = ["roll","pitch","yaw","throttle","mixture","left_brake","right_brake","trim"]
const HELD_ACTIONS = ["left_brake","right_brake","both_brakes","look_hold"]
var _preset: Dictionary = {}
var _values: Dictionary = {}
var _start: Dictionary = {}
var _pins: Dictionary = {}
var _edges: Dictionary = {}
var _takeover: Dictionary = {}
var _configured: bool = false
var _live: bool = false
var _brake_hold: bool = false
var _v2: bool = false
var _held_systems: Dictionary = {}
var _system_intents: Dictionary = {}
var _system_edges: Dictionary = {}

static func _pair(target: String, negative: Array, positive: Array, rate: float, gain: float, returning: bool) -> Dictionary:
	return {"target":target,"kind":"key_pair","negative":negative,"positive":positive,"rate":rate,"gain":gain,"return_to_start":returning}

static func default_preset() -> Dictionary:
	var bindings: Array = [
		_pair("roll",[KEY_LEFT],[KEY_RIGHT],0.9,0.35,true),
		_pair("pitch",[KEY_UP],[KEY_DOWN],0.9,0.15,true),
		_pair("yaw",[KEY_A],[KEY_D],0.9,0.25,true),
		_pair("throttle",[KEY_S,KEY_PAGEDOWN],[KEY_W,KEY_PAGEUP],0.25,1.0,false),
		_pair("trim",[KEY_BRACKETLEFT],[KEY_BRACKETRIGHT],0.08,1.0,false)]
	for target in ["mixture","left_brake","right_brake"]:
		bindings.append({"target":target,"kind":"fixed","value":1.0 if target=="mixture" else 0.0})
	var key_actions: Dictionary = {
		"pause_menu":[KEY_P],"restart":[KEY_R],"start_ground":[KEY_G],"start_airborne":[KEY_F],
		"idle":[KEY_X],"left_brake":[KEY_Q],"right_brake":[KEY_E],"both_brakes":[KEY_SPACE],"brake_hold":[KEY_B],
		"view_cycle":[KEY_C],"view_cockpit":[KEY_1],"view_chase":[KEY_2],"view_orbit":[KEY_3],"view_panel":[KEY_4],
		"map_toggle":[KEY_TAB],"runway_toggle":[KEY_T],"map_zoom_in":[KEY_EQUAL,KEY_KP_ADD],"map_zoom_out":[KEY_MINUS,KEY_KP_SUBTRACT],
		"recenter":[KEY_HOME],"help":[KEY_H],"overlay":[KEY_V],"controller_select":[KEY_J],"audio":[KEY_M],
		"fullscreen":[KEY_F11],"speed_down":[KEY_F5],"speed_up":[KEY_F6],"controls_panel":[KEY_F7]}
	var actions: Array = []
	for id in key_actions:
		actions.append({"id":id,"sources":[{"kind":"physical_keys","keys":key_actions[id]}]})
	for entry in [["look_hold",MOUSE_BUTTON_RIGHT],["view_zoom_in",MOUSE_BUTTON_WHEEL_UP],["view_zoom_out",MOUSE_BUTTON_WHEEL_DOWN]]:
		actions.append({"id":entry[0],"sources":[{"kind":"mouse_button","button":entry[1]}]})
	return {"type":"InputPreset","version":1,"name":"Keyboard smooth (prototype)","devices":[],"axes":bindings,"actions":actions}

static func _valid_axes(value: Variant) -> bool:
	if not value is Dictionary or value.size()!=9 or value.get("kind")!="axes":
		return false
	for target in TARGETS:
		var number: Variant = value.get(target)
		if not (number is int or number is float) or not is_finite(float(number)):
			return false
		if float(number)<(-1.0 if target in ["roll","pitch","yaw","trim"] else 0.0) or float(number)>1.0:
			return false
	return float(value.mixture)==1.0

static func _device(raw: Dictionary, slot: String) -> Dictionary:
	for device in raw.devices:
		if device.slot==slot:
			return device
	return {}

static func _reading(device: Dictionary, group: String, index: int) -> Variant:
	for item in device.get(group,[]):
		if int(item.index)==index:
			return item.value if group=="axes" else item.pressed
	return null

static func _any(keys: Array, pressed: Array) -> bool:
	for key in keys:
		if key in pressed:
			return true
	return false

# Caller supplies validated copies; useful for paused UI and held camera input.
static func action_pressed(preset: Dictionary, raw: Dictionary, id: String, include_wheel: bool=true) -> bool:
	for action in preset.get("actions",[]):
		if action.id!=id:
			continue
		for source in action.sources:
			match source.kind:
				"physical_keys":
					if _any(source.keys,raw.keys):
						return true
				"mouse_button":
					if source.button in raw.mouse_buttons and (include_wheel or not int(source.button) in [4,5,6,7]):
						return true
				"joy_button":
					if _reading(_device(raw,source.slot),"buttons",int(source.index))==true:
						return true
	return false

static func _wheel_pressed(preset: Dictionary, raw: Dictionary, id: String) -> bool:
	for action in preset.actions:
		if action.id==id:
			for source in action.sources:
				if source.kind=="mouse_button" and int(source.button) in [4,5,6,7] and source.button in raw.mouse_buttons:
					return true
	return false

func _required(preset: Dictionary) -> Dictionary:
	var required: Dictionary = {}
	for axis in preset.axes:
		if axis.kind=="joy_axis":
			if not required.has(axis.slot):
				required[axis.slot]={"axes":[],"buttons":[]}
			required[axis.slot].axes.append(int(axis.index))
	for action in preset.actions+preset.get("systems",[]):
		for source in action.sources:
			if source.kind=="joy_button":
				if not required.has(source.slot):
					required[source.slot]={"axes":[],"buttons":[]}
				required[source.slot].buttons.append(int(source.index))
	return required

func _check_raw(raw: Dictionary, preset: Dictionary, pins: Dictionary, configuring: bool=false) -> String:
	for slot in _required(preset):
		var device: Dictionary = _device(raw,slot)
		if device.is_empty():
			return "Selected device missing: "+slot
		if not configuring and device.generation!=pins.get(slot):
			return "Selected device generation changed: "+slot
		var required: Dictionary = _required(preset)[slot]
		for group in ["axes","buttons"]:
			for index in required[group]:
				if _reading(device,group,index)==null:
					return "Selected control unobserved: %s/%s/%s" % [slot,group,index]
	return ""

func configure(preset: Dictionary, held_axes: Dictionary, start_axes: Dictionary, initial_raw: Dictionary) -> Dictionary:
	if not Thread.is_main_thread():
		return {"ok":false,"error":"Input mapper requires main thread"}
	var checked: Dictionary = Preset.validate_preset(preset)
	var raw_checked: Dictionary = Preset.validate_raw(initial_raw)
	if not checked.ok:
		return {"ok":false,"error":checked.error}
	if not raw_checked.ok:
		return {"ok":false,"error":raw_checked.error}
	if not _valid_axes(held_axes) or not _valid_axes(start_axes):
		return {"ok":false,"error":"Invalid held/start complete axes"}
	var error: String = _check_raw(raw_checked.value,checked.value,{},true)
	if not error.is_empty():
		return {"ok":false,"error":error}
	var pins: Dictionary = {}
	for slot in _required(checked.value):
		pins[slot]=_device(raw_checked.value,slot).generation
	_v2=false
	_held_systems.clear(); _system_intents.clear(); _system_edges.clear()
	_preset=checked.value.duplicate(true)
	_values=held_axes.duplicate(true)
	_start=start_axes.duplicate(true)
	_pins=pins
	_edges.clear()
	_arm_takeover()
	if not _configured:
		_brake_hold=float(start_axes.left_brake)>0.5 and float(start_axes.right_brake)>0.5
	_configured=true
	_live=false
	return {"ok":true,"error":""}

func _arm_takeover() -> void:
	_takeover.clear()
	for axis in _preset.get("axes",[]):
		if axis.kind=="joy_axis" and axis.target in (["throttle","trim","mixture"] if _v2 else ["throttle","trim"]):
			_takeover[axis.target]=true

static func _normalized(axis: Dictionary, value: float) -> float:
	var result: float
	if axis.range=="centered":
		result=(value-float(axis.center))/(float(axis.maximum)-float(axis.center) if value>=float(axis.center) else float(axis.center)-float(axis.minimum))
		result=clampf(result,-1.0,1.0)
		return -result if axis.invert else result
	result=clampf((value-float(axis.minimum))/(float(axis.maximum)-float(axis.minimum)),0.0,1.0)
	return 1.0-result if axis.invert else result

# Independent mathematical kernel, also testable for unsigned ranges without runtime mixture support.
static func mapped_axis(axis: Dictionary, value: float) -> float:
	var normalized: float = _normalized(axis,value)
	var magnitude: float = clampf((absf(normalized)-float(axis.deadzone))/(float(axis.saturation)-float(axis.deadzone)),0.0,1.0)*float(axis.gain)
	return signf(normalized)*magnitude if axis.range=="centered" else magnitude

static func _command_axis(axis: Dictionary, value: float) -> float:
	return clampf(mapped_axis(axis,value),-1.0 if axis.target in ["roll","pitch","yaw","trim"] else 0.0,1.0)

func _takeover_names(raw: Dictionary) -> Array[String]:
	var names: Array[String] = []
	for axis in _preset.get("axes",[]):
		if _takeover.get(axis.target,false):
			var mapped: float = _command_axis(axis,float(_reading(_device(raw,axis.slot),"axes",int(axis.index))))
			if absf(mapped-float(_values[axis.target]))>0.03:
				names.append(axis.target)
	names.sort()
	return names

func suspend(_reason: String, held_axes: Dictionary) -> Dictionary:
	if not Thread.is_main_thread():
		return {"ok":false,"error":"Input mapper requires main thread"}
	_live=false
	_edges.clear()
	if not _configured or not _valid_axes(held_axes):
		return {"ok":false,"error":"Invalid held axes or unconfigured mapper"}
	_values=held_axes.duplicate(true)
	_arm_takeover()
	return {"ok":true,"error":""}

func resume_confirmed(current_raw: Dictionary) -> Dictionary:
	if not Thread.is_main_thread() or not _configured:
		return {"ok":false,"error":"Input mapper requires configured main thread"}
	_live=false
	var checked: Dictionary = Preset.validate_raw(current_raw)
	if not checked.ok:
		return {"ok":false,"error":checked.error}
	var raw: Dictionary = checked.value
	var error: String = _check_raw(raw,_preset,_pins)
	if not error.is_empty():
		return {"ok":false,"error":error}
	for axis in _preset.axes:
		if axis.kind=="key_pair" and (_any(axis.negative,raw.keys) or _any(axis.positive,raw.keys)):
			return {"ok":false,"error":"Release flight keys before resume"}
		if axis.kind=="joy_axis" and (axis.range=="centered" or axis.target in ["left_brake","right_brake"]):
			var value: float = _normalized(axis,float(_reading(_device(raw,axis.slot),"axes",int(axis.index))))
			if absf(value)>0.05:
				return {"ok":false,"error":"Center/release flight axis: "+axis.target}
	if _v2:
		for binding in _preset.systems:
			if _engine_pressed(binding,raw):
				return {"ok":false,"error":"Release engine source: "+binding.id}
	for id in ["idle","left_brake","right_brake","both_brakes","brake_hold"]:
		if action_pressed(_preset,raw,id,false):
			return {"ok":false,"error":"Release flight override: "+id}
	_edges.clear()
	for action in _preset.actions:
		_edges[action.id]=action_pressed(_preset,raw,action.id,false)
	if _v2:
		_system_edges.clear()
		for id in Preset.SYSTEM_IDS: _system_edges[id]=false
		_system_intents["engine.starter"]=false
	_live=true
	return {"ok":true,"error":""}

func _failure(error: String) -> Dictionary:
	return {"ok":false,"error":error,"axes":null,"actions":[],"takeover":[],"brake_hold":_brake_hold if Thread.is_main_thread() else false}

func _sample_axes(raw: Dictionary, elapsed_us: int) -> Dictionary:
	if not Thread.is_main_thread() or not _configured:
		return _failure("Input mapper requires configured main thread")
	if elapsed_us<0 or elapsed_us>250000 or (not _live and elapsed_us!=0):
		return _failure("Invalid input elapsed time")
	var checked: Dictionary = Preset.validate_raw(raw)
	if not checked.ok:
		return _failure(checked.error)
	var input: Dictionary = checked.value
	var error: String = _check_raw(input,_preset,_pins)
	if not error.is_empty():
		return _failure(error)
	if not _live:
		return {"ok":true,"error":"","axes":_values.duplicate(true),"actions":[],"takeover":_takeover_names(input),"brake_hold":_brake_hold}
	var seconds: float = float(elapsed_us)/1000000.0
	var actions: Array[String] = []
	for action in _preset.actions:
		var pressed: bool = action_pressed(_preset,input,action.id,false)
		if ((pressed and not _edges.get(action.id,false)) or _wheel_pressed(_preset,input,action.id)) and not action.id in HELD_ACTIONS:
			actions.append(action.id)
		_edges[action.id]=pressed
	if "brake_hold" in actions:
		_brake_hold=not _brake_hold
	for axis in _preset.axes:
		var target: String = axis.target
		match axis.kind:
			"fixed":
				_values[target]=float(axis.value)
			"key_pair":
				var direction: float = float(int(_any(axis.positive,input.keys))-int(_any(axis.negative,input.keys)))
				if axis.return_to_start:
					_values[target]=move_toward(float(_values[target]),clampf(float(_start[target])+float(axis.gain)*direction,-1.0,1.0),float(axis.rate)*seconds)
				else:
					_values[target]=clampf(float(_values[target])+float(axis.rate)*seconds*direction,-1.0 if target in ["roll","pitch","yaw","trim"] else 0.0,1.0)
			"joy_axis":
				var desired: float = _command_axis(axis,float(_reading(_device(input,axis.slot),"axes",int(axis.index))))
				if _takeover.get(target,false):
					if absf(desired-float(_values[target]))>0.03:
						continue
					_takeover[target]=false
				_values[target]=desired if float(axis.slew_per_s)==0.0 else move_toward(float(_values[target]),desired,float(axis.slew_per_s)*seconds)
	if "idle" in actions:
		_values.throttle=0.0
		for axis in _preset.axes:
			if axis.target=="throttle" and axis.kind=="joy_axis":
				_takeover.throttle=true
	var output: Dictionary = _values.duplicate(true)
	if _brake_hold or action_pressed(_preset,input,"both_brakes"):
		output.left_brake=1.0
		output.right_brake=1.0
	else:
		if action_pressed(_preset,input,"left_brake"):
			output.left_brake=1.0
		if action_pressed(_preset,input,"right_brake"):
			output.right_brake=1.0
	return {"ok":true,"error":"","axes":output,"actions":actions,"takeover":_takeover_names(input),"brake_hold":_brake_hold}

static func default_preset_v2() -> Dictionary:
	var preset: Dictionary=default_preset()
	preset.version=2; preset.name="Keyboard piston (prototype)"
	preset["profile"]=Preset.PISTON_PROFILE.duplicate(true); preset["capability_revision"]="piston-controls-v1"
	for i in preset.axes.size():
		if preset.axes[i].target=="mixture": preset.axes[i]=_pair("mixture",[KEY_COMMA],[KEY_PERIOD],0.25,1.0,false)
	preset["systems"]=[]
	for pair in [["engine.ignition_left",KEY_F8],["engine.ignition_right",KEY_F9],["engine.starter",KEY_F12],["fuel.feed",KEY_F10]]:
		preset.systems.append({"id":pair[0],"kind":"momentary" if pair[0]=="engine.starter" else "toggle","sources":[{"kind":"physical_keys","keys":[pair[1]]}]})
	return preset
static func _engine_pressed(binding: Dictionary, raw: Dictionary) -> bool:
	return action_pressed({"actions":[binding]},raw,binding.id,false)
func configure_v2(preset: Dictionary, held_axes: Dictionary, start_axes: Dictionary, initial_raw: Dictionary, profile: Dictionary, held_systems: Dictionary) -> Dictionary:
	if not Thread.is_main_thread(): return {"ok":false,"error":"Input mapper requires main thread"}
	var checked: Dictionary=Preset.validate_preset_v2(preset)
	var raw_checked: Dictionary=Preset.validate_raw(initial_raw)
	if not checked.ok: return {"ok":false,"error":checked.error}
	if not raw_checked.ok: return {"ok":false,"error":raw_checked.error}
	if not Preset.valid_profile(profile) or profile!=checked.value.profile or not Preset.valid_systems(held_systems) or not Preset.valid_axes_v2(held_axes) or not Preset.valid_axes_v2(start_axes): return {"ok":false,"error":"Invalid verified piston profile/held/start controls"}
	var error: String=_check_raw(raw_checked.value,checked.value,{},true)
	if not error.is_empty(): return {"ok":false,"error":error}
	var pins: Dictionary={}
	for slot in _required(checked.value): pins[slot]=_device(raw_checked.value,slot).generation
	_v2=true; _preset=checked.value.duplicate(true); _values=held_axes.duplicate(true); _start=start_axes.duplicate(true); _pins=pins
	_edges.clear(); _system_edges.clear(); _held_systems=held_systems.duplicate(true); _system_intents=held_systems.duplicate(true)
	_arm_takeover()
	if not _configured: _brake_hold=float(start_axes.left_brake)>0.5 and float(start_axes.right_brake)>0.5
	_configured=true; _live=false
	return {"ok":true,"error":""}
func suspend_v2(_reason: String, held_axes: Dictionary, held_systems: Dictionary) -> Dictionary:
	if not Thread.is_main_thread(): return {"ok":false,"error":"Input mapper requires main thread"}
	_live=false; _edges.clear(); _system_edges.clear()
	if _v2: _system_intents["engine.starter"]=false
	if not _configured or not _v2 or not Preset.valid_axes_v2(held_axes) or not Preset.valid_systems(held_systems): return {"ok":false,"error":"Invalid held controls or unconfigured piston mapper"}
	_values=held_axes.duplicate(true); _held_systems=held_systems.duplicate(true); _system_intents=held_systems.duplicate(true)
	_system_intents["engine.starter"]=false
	_arm_takeover()
	return {"ok":true,"error":""}
func sample(raw: Dictionary, elapsed_us: int) -> Dictionary:
	var result: Dictionary=_sample_axes(raw,elapsed_us)
	if not _v2: return result
	if not result.ok:
		result["systems"]=null
		return result
	if not _live:
		result["systems"]=_held_systems.duplicate(true)
		return result
	# Raw was validated before any axis, edge or engine intent mutation.
	for binding in _preset.systems:
		var pressed: bool=_engine_pressed(binding,raw)
		if binding.kind=="momentary": _system_intents[binding.id]=pressed
		elif pressed and not _system_edges.get(binding.id,false): _system_intents[binding.id]=not _system_intents[binding.id]
		_system_edges[binding.id]=pressed
	result["systems"]=_system_intents.duplicate(true)
	return result
