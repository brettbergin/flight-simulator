extends RefCounted
# Original MIT implementation of ADR008. Presentation input only; no native calls.
const Preset = preload("res://input/input_preset.gd")
const Wire = preload("res://simulation/wire_validation.gd")
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
# ADR017 metadata reserves one gesture; requested controls change only at sample commit.
const POINTER_LIMIT: int = 2147483647
const POINTER_CONTROLS = ["throttle","mixture","engine.ignition_left","engine.ignition_right","fuel.feed","engine.starter"]
const POINTER_BUTTONS = [1,2,3,8,9]
var _pointer_session: Variant = null
var _pointer_generation: int = 0
var _pointer_last_token: int = 0
var _pointer_capture: Variant = null
var _pointer_begin: Dictionary = {}
var _pointer_terminal: Dictionary = {}
var _pointer_pending: Array[Dictionary] = []
var _pointer_rearm: Array[int] = []
var _pointer_error: String = ""
var _pointer_disabled: bool = true

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
	_pointer_configured()
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
	if _live or _pointer_capture!=null or not _pointer_pending.is_empty(): invalidate_pointer(_reason)
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
	var was_live: bool = _live
	_live=false
	var checked: Dictionary = Preset.validate_raw(current_raw)
	if not checked.ok:
		return {"ok":false,"error":checked.error}
	var raw: Dictionary = checked.value
	var error: String = _check_raw(raw,_preset,_pins)
	if not error.is_empty():
		return {"ok":false,"error":error}
	for button in _pointer_rearm:
		if button in raw.mouse_buttons: return {"ok":false,"error":"Release pointer button before resume: "+str(button)}
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
	if not was_live: invalidate_pointer("resume")
	_pointer_observe_release(raw)
	_live=true
	return {"ok":true,"error":""}

func _failure(error: String) -> Dictionary:
	return {"ok":false,"error":error,"axes":null,"actions":[],"takeover":[],"brake_hold":_brake_hold if Thread.is_main_thread() else false}

func _sample_axes(raw: Dictionary, elapsed_us: int, pointer_axes: Dictionary={}) -> Dictionary:
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
		if pointer_axes.has(target):
			_values[target]=pointer_axes[target]
			continue
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
	_pointer_configured()
	_v2=true; _preset=checked.value.duplicate(true); _values=held_axes.duplicate(true); _start=start_axes.duplicate(true); _pins=pins
	_edges.clear(); _system_edges.clear(); _held_systems=held_systems.duplicate(true); _system_intents=held_systems.duplicate(true)
	_arm_takeover()
	if not _configured: _brake_hold=float(start_axes.left_brake)>0.5 and float(start_axes.right_brake)>0.5
	_configured=true; _live=false
	return {"ok":true,"error":""}
func suspend_v2(_reason: String, held_axes: Dictionary, held_systems: Dictionary) -> Dictionary:
	if not Thread.is_main_thread(): return {"ok":false,"error":"Input mapper requires main thread"}
	if _live or _pointer_capture!=null or not _pointer_pending.is_empty(): invalidate_pointer(_reason)
	_live=false; _edges.clear(); _system_edges.clear()
	if _v2: _system_intents["engine.starter"]=false
	if not _configured or not _v2 or not Preset.valid_axes_v2(held_axes) or not Preset.valid_systems(held_systems): return {"ok":false,"error":"Invalid held controls or unconfigured piston mapper"}
	_values=held_axes.duplicate(true); _held_systems=held_systems.duplicate(true); _system_intents=held_systems.duplicate(true)
	_system_intents["engine.starter"]=false
	_arm_takeover()
	return {"ok":true,"error":""}
func sample(raw: Dictionary, elapsed_us: int) -> Dictionary:
	if not _v2: return _sample_axes(raw,elapsed_us)
	# No axis/edge/latch/takeover mutation before complete Raw and pointer admission.
	var failure: String = ""
	var checked: Dictionary = Preset.validate_raw(raw)
	if not Thread.is_main_thread() or not _configured: failure="Input mapper requires configured main thread"
	elif elapsed_us<0 or elapsed_us>250000 or (not _live and elapsed_us!=0): failure="Invalid input elapsed time"
	elif not checked.ok: failure=checked.error
	else: failure=_check_raw(checked.value,_preset,_pins)
	var plan: Dictionary = {"ok":true,"error":"","axes":{},"systems":{},"terminal":false}
	if failure.is_empty() and _live:
		plan=_pointer_plan(checked.value)
		failure=plan.error
	if not failure.is_empty():
		var failed: Dictionary=_failure(failure)
		failed["systems"]=null
		return failed
	var input: Dictionary=checked.value
	var result: Dictionary=_sample_axes(input,elapsed_us,plan.axes)
	if not result.ok:
		result["systems"]=null
		return result
	if not _live:
		_pointer_observe_release(input)
		result["systems"]=_held_systems.duplicate(true)
		return result
	for binding in _preset.systems:
		var pressed: bool=_engine_pressed(binding,input)
		if binding.kind=="momentary": _system_intents[binding.id]=pressed
		elif pressed and not _system_edges.get(binding.id,false): _system_intents[binding.id]=not _system_intents[binding.id]
		_system_edges[binding.id]=pressed
	for id in plan.systems: _system_intents[id]=plan.systems[id]
	if plan.terminal:
		if _pointer_capture!=null and _pointer_capture.control in ["throttle","mixture"]:
			var axis: Dictionary=_pointer_axis(_pointer_capture.control)
			if axis.kind=="joy_axis": _takeover[axis.target]=true
		_pointer_capture=null
		_pointer_begin.clear()
		if _pointer_last_token==POINTER_LIMIT:
			_pointer_disabled=true
			_pointer_error="Pointer token exhausted; fresh mapper and fresh session required"
	_pointer_pending.clear()
	_pointer_observe_release(input)
	result["takeover"]=_takeover_names(input)
	result["systems"]=_system_intents.duplicate(true)
	return result

static func _pointer_reply(error: String="") -> Dictionary:
	return {"ok":error.is_empty(),"error":error}

func _pointer_configured() -> void:
	invalidate_pointer("configuration")
	_pointer_session=null
	_pointer_disabled=true

func bind_pointer_session(session_id: String) -> Dictionary:
	if not Thread.is_main_thread(): return _pointer_reply("Input mapper requires main thread")
	if not _configured or not _v2 or _live or not Wire._id(session_id):
		invalidate_pointer("Invalid suspended piston session binding")
		_pointer_session=null
		_pointer_disabled=true
		_pointer_error="Invalid suspended piston session binding"
		return _pointer_reply(_pointer_error)
	invalidate_pointer("session binding")
	if _pointer_generation==POINTER_LIMIT or _pointer_last_token==POINTER_LIMIT:
		_pointer_disabled=true
		_pointer_error="Pointer counters exhausted; fresh mapper and fresh session required"
		return _pointer_reply(_pointer_error)
	_pointer_session=session_id
	_pointer_disabled=false
	_pointer_error=""
	return _pointer_reply()

func pointer_view() -> Dictionary:
	if not Thread.is_main_thread():
		return {"session_id":null,"generation":0,"last_token":0,"capture":null,"requested_axes":null,"requested_systems":null,"rearm_buttons":[],"error":"Input mapper requires main thread"}
	return {"session_id":_pointer_session,"generation":_pointer_generation,"last_token":_pointer_last_token,"capture":_pointer_capture.duplicate(true) if _pointer_capture!=null else null,"requested_axes":_values.duplicate(true) if _configured and _v2 else null,"requested_systems":_system_intents.duplicate(true) if _configured and _v2 else null,"rearm_buttons":_pointer_rearm.duplicate(),"error":_pointer_error}

func invalidate_pointer(_reason: String) -> void:
	if not Thread.is_main_thread(): return
	if _pointer_capture!=null:
		if not _pointer_capture.button in _pointer_rearm: _pointer_rearm.append(_pointer_capture.button)
		if _pointer_capture.control in ["throttle","mixture"] and _pointer_axis(_pointer_capture.control).kind=="joy_axis": _takeover[_pointer_capture.control]=true
	_pointer_rearm.sort()
	_pointer_capture=null
	_pointer_begin.clear()
	_pointer_terminal.clear()
	_pointer_pending.clear()
	# Lifecycle reasons are not faults: the view error is an admission gate.
	if not _pointer_disabled: _pointer_error=""
	if _pointer_generation<POINTER_LIMIT: _pointer_generation+=1
	else:
		_pointer_disabled=true
		_pointer_error="Pointer generation exhausted; fresh mapper and fresh session required"

func _pointer_observe_release(raw: Dictionary) -> void:
	for i in range(_pointer_rearm.size()-1,-1,-1):
		var button: int=_pointer_rearm[i]
		if not button in raw.mouse_buttons and (_pointer_capture==null or _pointer_capture.button!=button): _pointer_rearm.remove_at(i)

func _pointer_axis(control: String) -> Dictionary:
	for axis in _preset.axes:
		if axis.target==control: return axis
	return {}

func _pointer_bound_button(button: int) -> String:
	for binding in _preset.axes+_preset.actions+_preset.get("systems",[]):
		var sources: Array=binding.get("sources",[binding])
		for source in sources:
			if source.get("kind")=="mouse_button" and source.get("button")==button:
				return str(binding.get("id",binding.get("target","unknown")))
	return ""

static func _pointer_shape(g: Dictionary) -> bool:
	if not Wire._keys(g,["session_id","generation","token","control","phase","button","value"]) or not Wire._id(g.session_id): return false
	if typeof(g.generation)!=TYPE_INT or g.generation<0 or g.generation>POINTER_LIMIT or typeof(g.token)!=TYPE_INT or g.token<1 or g.token>POINTER_LIMIT or typeof(g.button)!=TYPE_INT or not g.button in POINTER_BUTTONS: return false
	if typeof(g.control)!=TYPE_STRING or not g.control in POINTER_CONTROLS or typeof(g.phase)!=TYPE_STRING or not g.phase in ["begin","move","end","cancel"]: return false
	if g.phase=="cancel": return g.value==null
	if g.control in ["throttle","mixture"]: return typeof(g.value)==TYPE_FLOAT and is_finite(g.value) and g.value>=0.0 and g.value<=1.0
	if g.control=="engine.starter": return typeof(g.value)==TYPE_BOOL and ((g.phase=="begin" and g.value) or (g.phase=="end" and not g.value))
	return (g.phase=="begin" and typeof(g.value)==TYPE_BOOL) or (g.phase=="end" and g.value==null)

func queue_pointer(gesture: Dictionary) -> Dictionary:
	if not Thread.is_main_thread(): return _pointer_reply("Input mapper requires main thread")
	if not _pointer_shape(gesture): return _pointer_reply("Malformed closed pointer gesture")
	var g: Dictionary=gesture.duplicate(true)
	var terminal: bool=g.phase in ["end","cancel"]
	# Fully validated obsolete terminals are inert even after session/profile retirement.
	if terminal and (g.session_id!=_pointer_session or g.generation<_pointer_generation or (g.generation==_pointer_generation and g.token<_pointer_last_token)): return _pointer_reply()
	if terminal and g==_pointer_terminal: return _pointer_reply()
	if not _configured or not _v2 or not _live or _pointer_session==null or _pointer_disabled: return _pointer_reply("Pointer requires bound live piston mapper")
	if g.session_id!=_pointer_session or g.generation!=_pointer_generation: return _pointer_reply("Pointer session or generation mismatch")
	if g.phase=="begin" and g==_pointer_begin: return _pointer_reply()
	if g.phase=="begin":
		if _pointer_capture!=null: return _pointer_reply("Pointer capture already owned")
		if _pointer_last_token==POINTER_LIMIT:
			invalidate_pointer("token exhaustion")
			_pointer_error="Pointer token exhausted; fresh mapper and fresh session required"
			_pointer_disabled=true
			return _pointer_reply(_pointer_error)
		if g.token!=_pointer_last_token+1: return _pointer_reply("Pointer begin token must advance exactly once")
		if g.button in _pointer_rearm: return _pointer_reply("Release pointer button before fresh gesture")
		var bound: String=_pointer_bound_button(g.button)
		if not bound.is_empty(): return _pointer_reply("Pointer button bound to "+bound+"; release/remap before use")
		if g.control in ["throttle","mixture"] and _pointer_axis(g.control).kind=="fixed": return _pointer_reply("Pointer lever has fixed binding: "+g.control)
	else:
		if _pointer_capture==null or g.token!=_pointer_capture.token or g.control!=_pointer_capture.control or g.button!=_pointer_capture.button: return _pointer_reply("Pointer current capture mismatch")
		if not _pointer_terminal.is_empty(): return _pointer_reply("Pointer terminal already queued")
	if g.phase=="move":
		for i in range(_pointer_pending.size()-1,-1,-1):
			if _pointer_pending[i].phase=="move":
				_pointer_pending[i]=g
				return _pointer_reply()
	if _pointer_pending.size()>=(16 if terminal else 15):
		invalidate_pointer("queue capacity")
		_pointer_error="Pointer queue capacity exceeded; fresh attempt required"
		return _pointer_reply(_pointer_error)
	if g.phase=="begin":
		_pointer_last_token=g.token
		_pointer_capture={"token":g.token,"control":g.control,"button":g.button}
		_pointer_begin=g.duplicate(true)
		_pointer_terminal.clear()
		_pointer_rearm.append(g.button)
		_pointer_rearm.sort()
	elif terminal: _pointer_terminal=g.duplicate(true)
	_pointer_pending.append(g)
	_pointer_error=""
	return _pointer_reply()

func _pointer_plan(raw: Dictionary) -> Dictionary:
	var result: Dictionary={"ok":true,"error":"","axes":{},"systems":{},"terminal":false}
	if _pointer_capture==null: return result
	if _pointer_session==null or _pointer_disabled: result.error="Pointer capture lost live binding"; result.ok=false; return result
	var control: String=_pointer_capture.control
	var bound: String=_pointer_bound_button(_pointer_capture.button)
	if not bound.is_empty(): result.error="Pointer button bound to "+bound
	var look: bool=action_pressed(_preset,raw,"look_hold",false)
	if look and (not _edges.get("look_hold",false) or not _pointer_pending.is_empty() and _pointer_pending[0].phase=="begin"): result.error="Release mouse look before pointer operation"
	if control in ["throttle","mixture"]:
		var axis: Dictionary=_pointer_axis(control)
		if axis.kind=="fixed": result.error="Pointer lever has fixed binding: "+control
		if axis.kind=="key_pair" and (_any(axis.positive,raw.keys) or _any(axis.negative,raw.keys)): result.error="Pointer/physical lever conflict: "+control
		if control=="throttle" and action_pressed(_preset,raw,"idle",false) and not _edges.get("idle",false): result.error="Pointer throttle conflicts with idle"
	else:
		for binding in _preset.systems:
			if binding.id==control and control=="engine.starter" and _engine_pressed(binding,raw): result.error="Pointer/physical starter conflict"
	if not result.error.is_empty(): result.ok=false; return result
	var canceled: bool=not _pointer_pending.is_empty() and _pointer_pending.back().phase=="cancel"
	if control in ["throttle","mixture"]:
		result.axes[control]=float(_values[control])
		if not canceled:
			for g in _pointer_pending:
				if g.phase!="cancel": result.axes[control]=g.value
	elif control=="engine.starter":
		result.systems[control]=not canceled and (_pointer_terminal.is_empty() or _pointer_terminal.phase!="end")
	elif not canceled:
		var desired: bool=_pointer_begin.value
		for binding in _preset.systems:
			if binding.id==control and _engine_pressed(binding,raw) and not _system_edges.get(control,false) and (not _system_intents[control])!=desired: result.error="Opposite pointer/physical desired switch: "+control
		result.systems[control]=desired
	result.terminal=not _pointer_terminal.is_empty()
	result.ok=result.error.is_empty()
	return result
