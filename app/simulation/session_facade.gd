extends RefCounted
# Original MIT synchronous host of the accepted native worker (ADR007).
const U64 = preload("res://simulation/uint64.gd")
const Frames = preload("res://simulation/canonical_frames.gd")
const Origin = preload("res://simulation/render_origin.gd")
const Wire = preload("res://simulation/wire_validation.gd")
const QUANTA: int = 4000000
const MAX_INT: int = 9223372036854775807
const WORLD: String = "04bff5a0bcf3509990f6276b2548a28268f57fc96d218a7ca51cab1990ec1ff5"
const NATIVE: String = "35cf7b603d99b9accb123405f7569a901ed9e28d32110acbc296b376facd6416"
const INVENTORY: String = "98b30b5641ce86cc6f0af6298424606aa96a1e4a35ef3e9fcaf377bebb3f00cd"
const PISTON_INVENTORY: String = "f8ef5011243ef8cf16e13924a5cdc902c2055ba4789a4bfd0cba209533594b7a"
const LEGACY_PROFILE: Dictionary = {"id":"original-interactive-prototype","version":"0.1.0-prototype","backend_model":"original-interactive"}
const PISTON_PROFILE: Dictionary = {"id":"original-piston-prop-v1","version":"0.1.0-prototype","backend_model":"original-piston-prop"}
const SYSTEM_IDS: Array = ["engine.ignition_left","engine.ignition_right","engine.starter","fuel.feed"]
const COLD_SYSTEMS: Dictionary = {"engine.ignition_left":false,"engine.ignition_right":false,"engine.starter":false,"fuel.feed":true}

var render_origin: RefCounted
var _factory: Callable
var _bridge: RefCounted
var _root: String = ""
var _command_sequence: String = "0"
var _lifecycle_sequence: String = "0"
var _pending: Variant = null
var _admitted: Variant = null
var _profile: String = "original-interactive-prototype"
var _pending_systems: Variant = null
var _admitted_systems: Dictionary = {}
var _prepared: Dictionary = {}
var _previous: Variant = null
var _current: Variant = null
var _previous_tick: Variant = null
var _commands: Array = []
var _events: Array = []
var _complete: bool = true
var _admission: String = "none"
var _rejection: Variant = null
var _truth: Dictionary = {
	"host_mode":"closed","error":"","historical":true,"session_id":null,"tick":null,
	"aircraft":null,"atmosphere":null,"held_axes":null,"native_outcome":null,
	"native_live":false,"paused":false,"time_scale":1.0,"debt_quanta":0,
	"native_fault":"","named_start":null,"model_identity":null,
	"native_source_fingerprint":null,"prepared_world_sha256":null,"world_anchor":null,"canonical":null}
var _pending_commands: Dictionary = {}
var _pending_events: Dictionary = {}
var _delivered_command: String = "0"
var _delivered_event: String = "0"
var _origin_blocked: bool = false
var _blocked_origin_version: Variant = null
var _completed: int = 0
var _scene_ground: Dictionary={"ground_query_valid":false,"plane_clearance_m":0.0}
var _owner_thread: int

# A factory is only a fault-test seam; default is the accepted native class.
func _init(adapter_factory: Callable = Callable()) -> void:
	_factory=adapter_factory
	_owner_thread=OS.get_thread_caller_id()

func _wrong_thread() -> bool:
	return not Thread.is_main_thread() or OS.get_thread_caller_id()!=_owner_thread

func _entry_error() -> String:
	if _wrong_thread():
		return "Facade belongs to its main-thread owner"
	if render_origin!=null and render_origin.call("_is_transaction_active"):
		render_origin.call("_note_facade_reentry")
		return "Facade calls are prohibited during origin prepare/commit"
	return ""

func _rejected_readback(error: String) -> Dictionary:
	if _wrong_thread():
		# Never read/copy mutable owner data from a rejected foreign thread.
		return {"host_mode":"closed","error":error,"historical":true,"session_id":null,"tick":null,
			"aircraft":null,"atmosphere":null,"held_axes":null,"native_outcome":null,
			"native_live":false,"paused":false,"time_scale":1.0,"debt_quanta":0,
			"native_fault":"","named_start":null,"model_identity":null,
			"native_source_fingerprint":null,"prepared_world_sha256":null,"world_anchor":null,"canonical":null}
	var copy: Dictionary=_truth.duplicate(true)
	copy.error=error
	copy.historical=true
	return copy

func _entry_rejection(error: String) -> Dictionary:
	return {"ok":false,"error":error,"completed":0,"readback":_rejected_readback(error),"admission":"rejected","native_rejection":null,"applied_commands":[],"events":[],"observation_complete":false}

func _begin() -> void:
	_commands=[]
	_events=[]
	_complete=true
	_admission="none"
	_rejection=null
	_completed=0

func _result(ok: bool, error: String = "") -> Dictionary:
	return {"ok":ok,"error":error,"completed":_completed,"readback":readback(),
		"admission":_admission,"native_rejection":_rejection,
		"applied_commands":_commands.duplicate(true),"events":_events.duplicate(true),
		"observation_complete":_complete}

func readback() -> Dictionary:
	var entry_error: String=_entry_error()
	if not entry_error.is_empty():
		return _rejected_readback(entry_error)
	return _truth.duplicate(true)

static func _keys(value: Dictionary, expected: Array) -> bool:
	for key in value:
		if not key is String:
			return false
	var a: Array=value.keys()
	var b: Array=expected.duplicate()
	a.sort()
	b.sort()
	return a==b

static func _same(a: Variant, b: Variant, decoded_wire: bool=false) -> bool:
	if (a is float or a is int) and (b is float or b is int):
		if not decoded_wire:
			return float(a)==float(b)
		# Godot JSON parsing and native binary64 dictionary values can differ by
		# a few ULPs. This bounded codec allowance never applies to wire strings,
		# ordering, native trace comparisons or locally coalesced pilot intent.
		return absf(float(a)-float(b))<=8.0*2.220446049250313e-16*maxf(1.0,maxf(absf(float(a)),absf(float(b))))
	if a is Dictionary and b is Dictionary:
		if not _keys(a,b.keys()):
			return false
		for key in a:
			if not _same(a[key],b[key],decoded_wire):
				return false
		return true
	if a is Array and b is Array:
		if a.size()!=b.size():
			return false
		for index in a.size():
			if not _same(a[index],b[index],decoded_wire):
				return false
		return true
	return typeof(a)==typeof(b) and a==b

static func _finite_tree(value: Variant, depth: int=0) -> bool:
	if depth>24:
		return false
	if value is float:
		return is_finite(value)
	if value is Dictionary:
		for key in value:
			if not key is String or not _finite_tree(value[key],depth+1):
				return false
		return true
	if value is Array:
		if value.size()>8192:
			return false
		for item in value:
			if not _finite_tree(item,depth+1):
				return false
		return true
	return value==null or value is String or value is int or value is bool

static func _decode(encoded: String) -> Variant:
	if encoded.length()>1048576:
		return null
	var parser:=JSON.new()
	return parser.data if parser.parse(encoded)==OK else null

static func valid_axes(value: Variant, profile_id: String="original-interactive-prototype") -> bool:
	if profile_id not in ["original-interactive-prototype","original-piston-prop-v1"]:
		return false
	if not value is Dictionary or not _keys(value,["kind","roll","pitch","yaw","throttle","mixture","left_brake","right_brake","trim"]) or typeof(value.kind)!=TYPE_STRING or value.kind!="axes":
		return false
	for key in ["roll","pitch","yaw","throttle","mixture","left_brake","right_brake","trim"]:
		var item: Variant=value[key]
		if not (item is float or item is int) or not is_finite(float(item)):
			return false
		var low: float=-1.0 if key in ["roll","pitch","yaw","trim"] else 0.0
		if float(item)<low or float(item)>1.0:
			return false
	return profile_id=="original-piston-prop-v1" or float(value.mixture)==1.0

static func valid_systems(value: Variant) -> bool:
	if not value is Dictionary or not _keys(value,SYSTEM_IDS):
		return false
	for id in SYSTEM_IDS:
		if typeof(value[id])!=TYPE_BOOL:
			return false
	return true

static func _recipe(profile_id: String, named_start: String) -> bool:
	if profile_id=="original-piston-prop-v1":
		return named_start=="piston-cold-ground"
	return profile_id=="original-interactive-prototype" and named_start in ["ground-ready","airborne-prepared"]

static func _snapshot_systems(aircraft: Dictionary) -> Dictionary:
	var selected: Dictionary = {}
	for system in aircraft.systems:
		if SYSTEM_IDS.has(system.id):
			if system.quantity!="bool" or system.validity!="valid" or typeof(system.value)!=TYPE_BOOL:
				return {}
			selected[system.id]=system.value
	return selected if valid_systems(selected) else {}

static func _piston_publication(aircraft: Dictionary, axes: Dictionary) -> bool:
	var units: Dictionary = {"fuel.total":"kg","engine.throttle":"fraction","engine.mixture":"fraction","propeller.angular_speed":"radps","engine.running":"bool","engine.ignition_left":"bool","engine.ignition_right":"bool","engine.starter":"bool","fuel.feed":"bool","engine.starved":"bool"}
	if aircraft.systems.size()!=units.size():
		return false
	for system in aircraft.systems:
		if not units.has(system.id) or system.quantity!=units[system.id] or system.validity!="valid":
			return false
		if system.id in ["fuel.total","propeller.angular_speed"] and float(system.value)<0.0:
			return false
		if system.id=="engine.throttle" and not _same(system.value,axes.throttle,true):
			return false
		if system.id=="engine.mixture" and not _same(system.value,axes.mixture,true):
			return false
	return valid_systems(_snapshot_systems(aircraft))

func _call(method: String, arguments: Array=[]) -> Variant:
	if _bridge==null or not is_instance_valid(_bridge) or not _bridge.has_method(method) or OS.get_thread_caller_id()!=_owner_thread:
		return null
	return _bridge.callv(method,arguments)

func _closed_join() -> bool:
	if _bridge==null:
		return true
	var reply: Variant=_call("close")
	if not reply is Dictionary or reply.get("ok")!=true or reply.get("joined")!=true:
		_complete=false
		return false
	_bridge=null
	_truth.native_live=false
	_truth.paused=false
	return true

func _invalidate() -> void:
	_previous=null
	_current=null
	_previous_tick=null

func _halt(message: String, mode: String="discarded", incomplete: bool=true) -> void:
	_truth.host_mode=mode
	_truth.error=message
	_truth.historical=true
	_invalidate()
	_complete=_complete and not incomplete
	if not _closed_join():
		_truth.error+="; native close/join unconfirmed"

func start(model_root: String, named_start: String, profile_id: String="original-interactive-prototype") -> Dictionary:
	var entry_error: String=_entry_error()
	if not entry_error.is_empty():
		return _entry_rejection(entry_error)
	_begin()
	if _bridge!=null or _truth.host_mode!="closed":
		return _result(false,"Close before starting a fresh session")
	if OS.get_thread_caller_id()!=_owner_thread or not _recipe(profile_id,named_start):
		return _result(false,"Invalid owner thread or named start")
	# Native validates the entire authored inventory; host binds its reviewed ID.
	var inventory: String = PISTON_INVENTORY if profile_id==PISTON_PROFILE.id else INVENTORY
	if FileAccess.get_sha256(model_root.path_join("inventory.json"))!=inventory:
		return _result(false,"Reviewed model inventory identity mismatch")
	if _factory.is_valid():
		_bridge=_factory.call() as RefCounted
	elif ClassDB.class_exists("FlightInteractiveSession"):
		_bridge=ClassDB.instantiate("FlightInteractiveSession") as RefCounted
	if _bridge==null:
		return _result(false,"Native interactive session unavailable")
	_profile=profile_id
	# Preserve the exact default two-argument adapter call for legacy callers.
	var arguments: Array=[model_root,named_start] if profile_id==LEGACY_PROFILE.id else [model_root,named_start,profile_id]
	var reply: Variant=_call("open_session",arguments)
	if not reply is Dictionary or reply.get("ok")!=true or reply.get("named_start")!=named_start or reply.get("prepared_world_sha256")!=WORLD or reply.get("native_source_fingerprint")!=NATIVE:
		_closed_join()
		return _result(false,"Native initialization or pinned identity validation failed")
	var anchor_value: Variant=reply.get("world_anchor")
	if not anchor_value is Dictionary or not _keys(anchor_value,["latitude_rad","longitude_rad","ellipsoid_height_m"]) or not _finite_tree(anchor_value):
		_closed_join()
		return _result(false,"Invalid prepared anchor")
	for key in anchor_value:
		if not (anchor_value[key] is float or anchor_value[key] is int):
			_closed_join()
			return _result(false,"Invalid anchor scalar")
	_prepared=Frames.anchor(float(anchor_value.latitude_rad),float(anchor_value.longitude_rad),float(anchor_value.ellipsoid_height_m))
	if _prepared.is_empty():
		_closed_join()
		return _result(false,"Invalid prepared anchor range")
	if not _accept(reply,0,true):
		_closed_join()
		return _result(false,"Invalid native initial publication")
	_truth.world_anchor=anchor_value.duplicate(true)
	_root=model_root
	_truth.named_start=named_start
	_truth.model_identity=(PISTON_PROFILE if profile_id==PISTON_PROFILE.id else LEGACY_PROFILE).duplicate(true)
	_truth.native_source_fingerprint=NATIVE
	_truth.prepared_world_sha256=WORLD
	_truth.debt_quanta=0
	_truth.time_scale=1.0
	_truth.host_mode="live"
	_truth.error=""
	_truth.historical=false
	_command_sequence="0"
	_lifecycle_sequence="0"
	_pending_commands={}
	_pending_events={}
	_delivered_command="0"
	_delivered_event="0"
	_pending=null
	_pending_systems=null
	_origin_blocked=false
	_blocked_origin_version=null
	_admitted=_truth.held_axes.duplicate(true)
	_admitted_systems=_snapshot_systems(_truth.aircraft) if profile_id==PISTON_PROFILE.id else {}
	render_origin=Origin.new(_truth.session_id,_prepared.ecef,_prepared.rotation)
	return _result(true)

func _accept(reply: Dictionary, requested: int, initial: bool=false, step_reply: bool=false) -> bool:
	if reply.get("ok")!=true or reply.get("schema_version")!=1 or not reply.get("completed") is int or reply.completed<0 or reply.completed>requested:
		return false
	if not reply.get("aircraft_json") is String or not reply.get("atmosphere_json") is String or not valid_axes(reply.get("held_axes"),_profile):
		return false
	if not reply.get("live") is bool or not reply.get("paused") is bool or not reply.get("historical") is bool or not reply.get("fault") is String or not (reply.get("time_scale") is float or reply.get("time_scale") is int):
		return false
	if reply.historical==reply.live or float(reply.time_scale) not in [0.25,0.5,1.0,2.0,4.0] or reply.get("outcome") not in ["completed","paused","coverage_blocked","discarded"]:
		return false
	if not reply.get("ground_query_valid") is bool or not (reply.get("plane_clearance_m") is float or reply.get("plane_clearance_m") is int) or not is_finite(float(reply.plane_clearance_m)):
		return false
	var aircraft: Variant=_decode(reply.aircraft_json)
	var weather: Variant=_decode(reply.atmosphere_json)
	if not aircraft is Dictionary or not weather is Dictionary or not _finite_tree(aircraft) or not _finite_tree(weather):
		return false
	if not _keys(aircraft,["type","schema_version","tick","session_id","clock","elapsed_s","position","ecef_position_m","orientation_body_to_ned","velocity_body_mps","angular_rate_body_radps","acceleration_body_mps2","mass_kg","center_of_gravity_body_m","configuration","systems","contacts","validity"]):
		return false
	if not _keys(weather,["type","schema_version","tick","session_id","position","pressure_pa","temperature_k","density_kgpm3","relative_humidity","wind_toward_ned_mps","turbulence_ned_mps","seed","model_id"]):
		return false
	if aircraft.type!="AircraftSnapshot" or weather.type!="AtmosphereSample" or aircraft.schema_version!=1 or weather.schema_version!=1 or not U64.valid(aircraft.tick) or not U64.valid(weather.tick) or not aircraft.session_id is String or aircraft.session_id.is_empty() or aircraft.tick!=weather.tick or aircraft.session_id!=weather.session_id or aircraft.position!=weather.position or aircraft.validity!="valid":
		return false
	if not aircraft.clock is Dictionary or not _same(aircraft.clock,{"tick_rate_hz":120,"purpose":"runtime"}):
		return false
	if initial:
		if aircraft.tick!="0" or reply.completed!=0 or not reply.live or reply.paused or reply.outcome!="completed" or float(reply.time_scale)!=1.0:
			return false
	else:
		var delta: Dictionary=U64.small_difference(aircraft.tick,_truth.tick,32)
		if aircraft.session_id!=_truth.session_id or not delta.ok or delta.value!=reply.completed:
			return false
		if reply.completed==0 and (aircraft!=_truth.aircraft or weather!=_truth.atmosphere):
			return false
	if not Wire.aircraft(aircraft) or not Wire.atmosphere(weather) or not U64.valid(weather.seed) or aircraft.configuration.flap_fraction!=0 or aircraft.configuration.gear_fraction!=1:
		return false
	if _profile==PISTON_PROFILE.id and not _piston_publication(aircraft,reply.held_axes):
		return false
	if reply.outcome=="completed" and (not reply.live or reply.paused):
		return false
	if reply.outcome=="paused" and (not reply.live or not reply.paused):
		return false
	if reply.outcome=="discarded" and reply.live:
		return false
	var canonical: Dictionary=Frames.derive(aircraft,_prepared)
	if canonical.is_empty() or not Frames.finite_array(canonical.anchor_eus_position_m,3):
		return false
	var commands: Variant=_records(reply.get("applied_commands_json"),"ControlCommand",aircraft.session_id,aircraft.tick)
	var events: Variant=_records(reply.get("events_json"),"OperationalEvent",aircraft.session_id,aircraft.tick)
	if commands==null or events==null:
		return false
	if initial and (not commands.is_empty() or not events.is_empty()):
		return false
	var command_cursor: String=_delivered_command
	var event_cursor: String=_delivered_event
	var expected_axes: Variant=null if initial else _truth.held_axes
	var expected_systems: Dictionary = COLD_SYSTEMS.duplicate(true) if initial else (_snapshot_systems(_truth.aircraft) if _profile==PISTON_PROFILE.id else {})
	for record in commands:
		var next: Dictionary=U64.increment(command_cursor)
		if not Wire.command(record) or not next.ok or record.sequence!=next.value or not _pending_commands.has(record.sequence) or not _same(record,_pending_commands[record.sequence],true):
			return false
		command_cursor=record.sequence
		if record.payload.kind=="axes":
			expected_axes=record.payload
		elif _profile==PISTON_PROFILE.id and record.payload.kind=="system" and SYSTEM_IDS.has(record.payload.control_id) and typeof(record.payload.value)==TYPE_BOOL:
			expected_systems[record.payload.control_id]=record.payload.value
		else:
			return false
	for record in events:
		var next: Dictionary=U64.increment(event_cursor)
		if not Wire.event(record) or not next.ok or record.sequence!=next.value or not _pending_events.has(record.sequence):
			return false
		var expected: Dictionary=_pending_events[record.sequence]
		if record.tick!=expected.tick or not _same(record.payload,expected.payload,true) or record.source_id!="session.owner" or record.confidence!="observed" or record.content_version!="0.1.0-prototype":
			return false
		event_cursor=record.sequence
	if step_reply:
		var observed_commands: Dictionary={}
		var observed_events: Dictionary={}
		for record in commands:
			observed_commands[record.sequence]=true
		for record in events:
			observed_events[record.sequence]=true
		for sequence in _pending_commands:
			var expected: Dictionary=_pending_commands[sequence]
			if U64.compare(expected.tick,aircraft.tick)<=0 and not observed_commands.has(sequence):
				return false
		for sequence in _pending_events:
			if not observed_events.has(sequence):
				return false
	elif not commands.is_empty() or not events.is_empty():
		return false
	if expected_axes!=null and not _same(reply.held_axes,expected_axes,true):
		return false
	if _profile==PISTON_PROFILE.id and not _same(_snapshot_systems(aircraft),expected_systems):
		return false
	if not _same(aircraft.configuration.trim_fraction,reply.held_axes.trim,true):
		return false
	var adjacent: bool=false
	if _current!=null and _truth.session_id==aircraft.session_id:
		var difference: Dictionary=U64.small_difference(aircraft.tick,_truth.tick,1)
		adjacent=difference.ok and difference.value==1
	if reply.completed>0 or initial:
		_previous=_current.duplicate(true) if adjacent else canonical.duplicate(true)
		_previous_tick=_truth.tick if adjacent else aircraft.tick
		_current=canonical.duplicate(true)
	_truth.session_id=aircraft.session_id
	_truth.tick=aircraft.tick
	_truth.aircraft=aircraft.duplicate(true)
	_truth.atmosphere=weather.duplicate(true)
	_truth.held_axes=reply.held_axes.duplicate(true)
	_truth.canonical=canonical.duplicate(true)
	_truth.native_outcome=reply.outcome
	_truth.native_live=reply.live
	_truth.paused=reply.paused
	_truth.time_scale=float(reply.time_scale)
	_truth.native_fault=reply.fault
	_scene_ground={"ground_query_valid":reply.ground_query_valid,"plane_clearance_m":float(reply.plane_clearance_m)}
	_truth.historical=reply.historical
	for record in commands:
		_pending_commands.erase(record.sequence)
	for record in events:
		_pending_events.erase(record.sequence)
	_delivered_command=command_cursor
	_delivered_event=event_cursor
	_commands.append_array(commands)
	_events.append_array(events)
	return true

func _records(value: Variant, kind: String, session: String, tick: String) -> Variant:
	if not value is Array or value.size()>4096:
		return null
	var output: Array=[]
	for encoded in value:
		if not encoded is String:
			return null
		var record: Variant=_decode(encoded)
		if not record is Dictionary or not _finite_tree(record) or record.get("type")!=kind or record.get("schema_version")!=1 or record.get("session_id")!=session or not U64.valid(record.get("tick")) or not U64.valid(record.get("sequence")) or U64.compare(record.tick,tick)>0:
			return null
		output.append(record.duplicate(true))
	return output

func set_axes(axes: Dictionary) -> Dictionary:
	var entry_error: String=_entry_error()
	if not entry_error.is_empty():
		return _entry_rejection(entry_error)
	_begin()
	if _truth.host_mode!="live" or _profile!=LEGACY_PROFILE.id or not valid_axes(axes):
		return _result(false,"Complete normalized unassisted axes require a live unpaused session")
	_pending=axes.duplicate(true)
	_admission="intent_stored"
	return _result(true)

func set_pilot_intent(axes: Dictionary, systems: Dictionary) -> Dictionary:
	var entry_error: String=_entry_error()
	if not entry_error.is_empty():
		return _entry_rejection(entry_error)
	_begin()
	if _truth.host_mode!="live" or _profile!=PISTON_PROFILE.id or not valid_axes(axes,_profile) or not valid_systems(systems):
		return _result(false,"Complete piston axes and bool systems require a live unpaused session")
	_pending=axes.duplicate(true)
	_pending_systems=systems.duplicate(true)
	_admission="intent_stored"
	return _result(true)

func _queue_pending() -> bool:
	if _profile==PISTON_PROFILE.id:
		return _queue_piston_pending()
	if _pending==null or _same(_pending,_admitted):
		_pending=null
		return true
	var next_tick: Dictionary=U64.increment(_truth.tick)
	var next_sequence: Dictionary=U64.increment(_command_sequence)
	if not next_tick.ok or not next_sequence.ok:
		_halt("Pilot tick or sequence exhausted", "discarded", false)
		return false
	var command: Dictionary={"type":"ControlCommand","schema_version":1,"tick":next_tick.value,"session_id":_truth.session_id,"sequence":next_sequence.value,"source_id":"pilot.controls","authority":"pilot","assistance":{"profile_id":"unassisted","active":[]},"payload":_pending.duplicate(true)}
	var reply: Variant=_call("submit",[command])
	if not reply is Dictionary or not reply.get("rejection") is int:
		_halt("Unverified native admission reply")
		return false
	_rejection=reply.rejection
	if reply.get("ok")!=true or reply.get("queued")!=true or reply.rejection!=0 or not _accept(reply,0):
		_admission="rejected"
		_halt("Pilot command rejected or acknowledgement inconsistent")
		return false
	_pending_commands[next_sequence.value]=command.duplicate(true)
	_command_sequence=next_sequence.value
	_admitted=_pending.duplicate(true)
	_pending=null
	_admission="queued"
	return true

func _queue_piston_pending() -> bool:
	var payloads: Array=[]
	if _pending!=null and not _same(_pending,_admitted):
		payloads.append(_pending.duplicate(true))
	if _pending_systems!=null:
		for id in SYSTEM_IDS:
			if _pending_systems[id]!=_admitted_systems[id]:
				payloads.append({"kind":"system","control_id":id,"value":_pending_systems[id]})
	if payloads.is_empty():
		_pending=null
		_pending_systems=null
		return true
	var tick: Dictionary=U64.increment(_truth.tick)
	var sequence: String=_command_sequence
	var commands: Array=[]
	# Reserve the entire shared lane BEFORE the first individually admitted call.
	for payload in payloads:
		var next: Dictionary=U64.increment(sequence)
		if not tick.ok or not next.ok:
			_halt("Pilot tick or sequence exhausted","discarded",false)
			return false
		sequence=next.value
		commands.append({"type":"ControlCommand","schema_version":1,"tick":tick.value,"session_id":_truth.session_id,"sequence":sequence,"source_id":"pilot.controls","authority":"pilot","assistance":{"profile_id":"unassisted","active":[]},"payload":payload})
	for command in commands:
		var reply: Variant=_call("submit",[command])
		if not reply is Dictionary or not reply.get("rejection") is int:
			_halt("Unverified native piston admission reply")
			return false
		_rejection=reply.rejection
		if reply.get("ok")!=true or reply.get("queued")!=true or reply.rejection!=0 or not _accept(reply,0):
			_admission="rejected"
			_halt("Piston command rejected or acknowledgement inconsistent; no solver advance")
			return false
		_pending_commands[command.sequence]=command.duplicate(true)
		_command_sequence=command.sequence
		if command.payload.kind=="axes":
			_admitted=command.payload.duplicate(true)
		else:
			_admitted_systems[command.payload.control_id]=command.payload.value
	_pending=null
	_pending_systems=null
	_admission="queued"
	return true

func _lifecycle(payload: Dictionary) -> bool:
	var next: Dictionary=U64.increment(_lifecycle_sequence)
	if not next.ok:
		_halt("Lifecycle sequence exhausted","discarded",false)
		return false
	var command: Dictionary={"type":"SessionControl","schema_version":1,"tick":_truth.tick,"session_id":_truth.session_id,"sequence":next.value,"source_id":"session.owner","payload":payload.duplicate(true)}
	var reply: Variant=_call("session_control",[command])
	if not reply is Dictionary or not reply.get("rejection") is int:
		_halt("Unverified native lifecycle reply")
		return false
	_rejection=reply.rejection
	if reply.get("ok")!=true or reply.rejection!=0 or not _accept(reply,0):
		_admission="rejected"
		_halt("Lifecycle rejected or acknowledgement inconsistent")
		return false
	var expected_payload: Dictionary=payload.duplicate(true)
	if expected_payload.kind=="time_scale":
		expected_payload.kind="time-scale"
	_pending_events[next.value]={"tick":command.tick,"payload":expected_payload}
	_lifecycle_sequence=next.value
	_admission="lifecycle_accepted"
	return true

func _drain_paused() -> bool:
	var reply: Variant=_call("step_fixed",[1])
	if not reply is Dictionary or reply.get("completed")!=0 or reply.get("outcome")!="paused" or not _accept(reply,0,false,true):
		_halt("Paused lifecycle drain unverified")
		return false
	return true

func _collapse() -> void:
	if _current!=null:
		_previous=_current.duplicate(true)
		_previous_tick=_truth.tick

func set_paused(value: bool) -> Dictionary:
	var entry_error: String=_entry_error()
	if not entry_error.is_empty():
		return _entry_rejection(entry_error)
	_begin()
	if _truth.host_mode not in ["live","paused"]:
		return _result(false,"Reset required before changing pause")
	if not value and _origin_blocked:
		var state: Dictionary=render_origin.call("read_origin") if render_origin!=null else {}
		if not state.get("valid",false) or state.get("committed")==null or _blocked_origin_version==null or U64.compare(state.committed.version,_blocked_origin_version)<=0:
			return _result(false,"Successful origin adoption or reset required before resume")
		_origin_blocked=false
		_blocked_origin_version=null
		_truth.error=""
	if _truth.paused==value:
		return _result(true)
	if _profile==PISTON_PROFILE.id:
		# Remove all unadmitted local intent on recovery; keep native feedback true.
		_pending=null
		_pending_systems=null
		if not value and _admitted_systems.get("engine.starter",false):
			_pending_systems=_admitted_systems.duplicate(true)
			_pending_systems["engine.starter"]=false
			if not _queue_piston_pending():
				return _result(false,_truth.error)
	if not _lifecycle({"kind":"pause","paused":value}):
		return _result(false,_truth.error)
	if _truth.paused!=value:
		_halt("Native pause acknowledgement does not match request")
		return _result(false,_truth.error)
	_truth.host_mode="paused" if value else "live"
	_collapse()
	if value and not _drain_paused():
		return _result(false,_truth.error)
	return _result(true)

func set_time_scale(value: float) -> Dictionary:
	var entry_error: String=_entry_error()
	if not entry_error.is_empty():
		return _entry_rejection(entry_error)
	_begin()
	if value not in [0.25,0.5,1.0,2.0,4.0] or _truth.host_mode not in ["live","paused"]:
		return _result(false,"Unsupported scale or terminal session")
	if _truth.time_scale==value:
		return _result(true)
	if not _lifecycle({"kind":"time_scale","scale":value}):
		return _result(false,_truth.error)
	if _truth.time_scale!=value:
		_halt("Native scale acknowledgement does not match request")
		return _result(false,_truth.error)
	return _result(true)

func advance_wall_us(elapsed_us: int) -> Dictionary:
	var entry_error: String=_entry_error()
	if not entry_error.is_empty():
		return _entry_rejection(entry_error)
	_begin()
	if elapsed_us<0:
		return _result(false,"Negative wall interval rejected")
	if _truth.host_mode=="paused":
		return _result(true) if _origin_health(false) else _result(false,_truth.error)
	if _truth.host_mode!="live":
		return _result(false,"Session is not live; reset required")
	var multiplier: int=int(_truth.time_scale*4.0)
	var factor: int=120*multiplier
	@warning_ignore("integer_division")
	var capacity: int=(MAX_INT-_truth.debt_quanta)/factor
	if elapsed_us>capacity:
		var error: String="Unrepresentable wall accrual; prior debt retained; reset required"
		if _lifecycle({"kind":"pause","paused":true}) and _drain_paused():
			_truth.host_mode="stalled"
			_truth.historical=true
			_truth.error=error
			_collapse()
		return _result(false,_truth.error)
	if not _origin_health(false):
		return _result(false,_truth.error)
	_truth.debt_quanta+=elapsed_us*factor
	if elapsed_us>250000 or _truth.debt_quanta>30*QUANTA:
		if _lifecycle({"kind":"pause","paused":true}) and _drain_paused():
			_truth.host_mode="stalled"
			_truth.historical=true
			_truth.error="Wall overload: exact debt retained; reset required"
			_collapse()
		return _result(false,_truth.error)
	@warning_ignore("integer_division")
	var due: int=_truth.debt_quanta/QUANTA
	if due==0:
		return _result(true)
	if not _queue_pending():
		return _result(false,_truth.error)
	var segments: Array=[due-1,1] if due>1 else [1]
	for count in segments:
		var reply: Variant=_call("step_fixed",[count])
		if not reply is Dictionary or not _accept(reply,count,false,true):
			_halt("Native step reply is unverified or inconsistent")
			return _result(false,_truth.error)
		_completed+=reply.completed
		_truth.debt_quanta-=reply.completed*QUANTA
		if reply.outcome!="completed" or reply.completed!=count:
			var terminal: String="coverage_blocked" if reply.outcome=="coverage_blocked" else "discarded"
			_halt("Native %s after %d verified ticks: %s"%[reply.outcome,_completed,reply.fault],terminal,false)
			return _result(false,_truth.error)
	if not _origin_health(true):
		return _result(false,_truth.error)
	return _result(true)

func _origin_health(allow_rebase: bool) -> bool:
	if render_origin==null:
		return true
	var state: Dictionary=render_origin.call("read_origin")
	if render_origin.call("_has_terminal_failure"):
		var message: String="Render-origin commit failed: "+state.error
		if _bridge!=null and not _truth.paused:
			_lifecycle({"kind":"pause","paused":true})
		if _bridge!=null and _truth.paused:
			_drain_paused()
		_halt(message,"discarded",not _complete)
		return false
	if not state.valid:
		# First initialization can run a headless native fixture before category
		# adoption; any later registration change invalidates drawing and pauses.
		if state.committed==null:
			return true
		return _origin_pause("Complete origin re-adoption required: "+state.error)
	if not allow_rebase or _current==null:
		return true
	var local: Array=Frames.project(_current.ecef_position_m,state.committed.origin_ecef_m,state.committed.ecef_to_eus)
	if not Frames.finite_array(local,3):
		_halt("Nonfinite render-origin projection","discarded",false)
		return false
	var distance: float=sqrt(local[0]*local[0]+local[1]*local[1]+local[2]*local[2])
	if distance<1800.0:
		return true
	var adopted: Dictionary=render_origin.call("rebase",_current.ecef_position_m.duplicate(true))
	if adopted.ok:
		return true
	if render_origin.call("_has_terminal_failure"):
		return _origin_health(false)
	return _origin_pause("Origin prepare failed; drawing bounded and flight paused: "+adopted.error)

func _origin_pause(message: String) -> bool:
	_origin_blocked=true
	var origin: Dictionary=render_origin.call("read_origin")
	_blocked_origin_version=origin.committed.version if origin.committed!=null else "0"
	if not _truth.paused and not _lifecycle({"kind":"pause","paused":true}):
		return false
	if not _drain_paused():
		return false
	_truth.host_mode="paused"
	_truth.error=message
	_collapse()
	return false

func _close_current() -> bool:
	if _bridge!=null and _truth.host_mode in ["live","paused"]:
		if not _truth.paused:
			_lifecycle({"kind":"pause","paused":true})
		if _bridge!=null and _truth.paused:
			_drain_paused()
	# Rejected lifecycle/drain paths may already close through _halt. Every
	# confirmed close still crosses the same presentation/debt cleanup below.
	var joined: bool=_closed_join()
	_invalidate()
	render_origin=null
	_truth.historical=true
	_truth.debt_quanta=0
	return joined

func close() -> Dictionary:
	var entry_error: String=_entry_error()
	if not entry_error.is_empty():
		return _entry_rejection(entry_error)
	_begin()
	if not _close_current():
		_truth.host_mode="discarded"
		_truth.error="Native worker close/join unconfirmed"
		return _result(false,_truth.error)
	_truth.host_mode="closed"
	return _result(true)

func reset(named_start: String) -> Dictionary:
	var entry_error: String=_entry_error()
	if not entry_error.is_empty():
		return _entry_rejection(entry_error)
	_begin()
	if not _recipe(_profile,named_start) or _root.is_empty():
		return _result(false,"Verified model root and supported named start required")
	var previous_events: Array=[]
	if not _close_current():
		_truth.host_mode="discarded"
		_truth.error="Reset requires confirmed native join"
		_truth.historical=true
		_invalidate()
		return _result(false,_truth.error)
	previous_events=_events.duplicate(true)
	var complete: bool=_complete
	_truth.host_mode="closed"
	var result: Dictionary=start(_root,named_start,_profile)
	result.events=previous_events+result.events
	result.observation_complete=result.observation_complete and complete
	return result

# Internal scene-adoption source: binary64 interpolation in the same visual
# timeline, before float rendering. Never a native/wire aircraft publication.
func _ground_display() -> Dictionary:
	if _wrong_thread():
		return {"ground_query_valid":false,"plane_clearance_m":0.0}
	return _scene_ground.duplicate(true)

func _visual_ecef() -> Variant:
	if _wrong_thread() or _current==null or _previous==null:
		return null
	var alpha: float=1.0 if _truth.paused or _previous_tick==_truth.tick else clampf(float(_truth.debt_quanta)/float(QUANTA),0.0,1.0)
	var result: Array=[]
	for index in 3:
		result.append(float(_previous.ecef_position_m[index])*(1.0-alpha)+float(_current.ecef_position_m[index])*alpha)
	return result

func visual_pose() -> Dictionary:
	var invalid: Dictionary={"valid":false,"error":"No adopted current presentation","session_id":null,"previous_tick":null,"current_tick":null,"alpha":0.0,"origin_version":null,"transform":null}
	var entry_error: String=_entry_error()
	if not entry_error.is_empty():
		invalid.error=entry_error
		return invalid
	if _current==null or render_origin==null or _truth.host_mode not in ["live","paused"]:
		return invalid
	var origin: Dictionary=render_origin.call("read_origin")
	if not origin.valid or origin.committed==null or origin.committed.session_id!=_truth.session_id:
		invalid.error=origin.error if not origin.error.is_empty() else invalid.error
		return invalid
	var alpha: float=1.0 if _truth.paused or _previous_tick==_truth.tick else clampf(float(_truth.debt_quanta)/float(QUANTA),0.0,1.0)
	var ecef: Array=[]
	for index in 3:
		ecef.append(float(_previous.ecef_position_m[index])*(1.0-alpha)+float(_current.ecef_position_m[index])*alpha)
	var local: Array=Frames.project(ecef,origin.committed.origin_ecef_m,origin.committed.ecef_to_eus)
	if not Frames.finite_array(local,3):
		return invalid
	var distance: float=sqrt(local[0]*local[0]+local[1]*local[1]+local[2]*local[2])
	if distance>2000.0:
		invalid.error="Render-origin adoption required before presenting beyond 2km"
		return invalid
	var rotation: Array=Frames.interpolate_rotation(_previous.body_to_anchor_eus,_current.body_to_anchor_eus,alpha)
	return {"valid":true,"error":"","session_id":_truth.session_id,"previous_tick":_previous_tick,"current_tick":_truth.tick,"alpha":alpha,"origin_version":origin.committed.version,"transform":Frames.transform(local,rotation)}
