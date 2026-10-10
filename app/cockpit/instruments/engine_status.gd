extends RefCounted
# Original MIT. ADR010 completed-tick observations; never an engine controller.
const Readings = preload("res://cockpit/instruments/native_readings.gd")
const UNITS: Dictionary = {
	"fuel.total":"kg","engine.throttle":"fraction","engine.mixture":"fraction",
	"propeller.angular_speed":"radps","engine.running":"bool",
	"engine.ignition_left":"bool","engine.ignition_right":"bool",
	"engine.starter":"bool","fuel.feed":"bool","engine.starved":"bool"}
const CONTROL_IDS: Array = ["engine.ignition_left","engine.ignition_right","engine.starter","fuel.feed"]

static func _channel(value: Variant, unit: String, error: String="") -> Dictionary:
	return {"value":value,"unit":unit,"valid":value!=null,"error":error}

static func _unavailable(state: String, error: String) -> Dictionary:
	var channels: Dictionary = {}
	for id in UNITS:
		channels[id]=_channel(null,UNITS[id],error)
	return {"session_id":null,"tick":null,"state":state,"native_truth":true,"readings":channels,"error":error}

static func from_readback(value: Variant) -> Dictionary:
	# Owned input copies prevent a caller from retaining mutable publication data.
	var source: Variant = value.duplicate(true) if value is Dictionary else value
	var error: String = Readings._validate(source)
	if not error.is_empty():
		return _unavailable("invalid",error)
	if source.aircraft==null:
		return _unavailable("empty","No verified source publication")
	if source.model_identity!=Readings.PISTON_PROFILE:
		return _unavailable("invalid","Engine status requires the original piston profile")
	var channels: Dictionary = {}
	for id in UNITS:
		channels[id]=_channel(null,UNITS[id],"Native %s is unavailable" % id)
	for system in source.aircraft.systems:
		if not UNITS.has(system.id):
			continue
		if system.validity!="valid" or system.quantity!=UNITS[system.id]:
			channels[system.id]=_channel(null,UNITS[system.id],"Native %s lacks valid %s quantity" % [system.id,UNITS[system.id]])
		elif UNITS[system.id]=="bool":
			channels[system.id]=_channel(system.value,"bool")
		else:
			channels[system.id]=_channel(float(system.value),UNITS[system.id])
	var state: String = "historical" if source.historical or Readings.TERMINAL.has(source.host_mode) else ("paused" if source.paused else "live")
	return {"session_id":source.session_id,"tick":source.tick,"state":state,"native_truth":true,"readings":channels,"error":""}

static func held_systems_from_readback(value: Variant) -> Dictionary:
	var status: Dictionary = from_readback(value)
	if status.state in ["invalid","empty"]:
		return {"ok":false,"error":status.error,"value":null}
	var held: Dictionary = {}
	for id in CONTROL_IDS:
		var channel: Dictionary = status.readings[id]
		if not channel.valid or typeof(channel.value)!=TYPE_BOOL:
			return {"ok":false,"error":channel.error,"value":null}
		held[id]=channel.value
	return {"ok":true,"error":"","value":held}
