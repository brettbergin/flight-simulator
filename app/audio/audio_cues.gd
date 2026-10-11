extends RefCounted
# Original MIT. ADR020 pure copied presentation. Structural source validation is
# not loaded-binary authority; Scene supplies its actually adopted Readback.
const Readings = preload("res://cockpit/instruments/native_readings.gd")
const EngineStatus = preload("res://cockpit/instruments/engine_status.gd")

static func _unavailable(reason: String) -> Dictionary:
	return {"session_id":null,"tick":null,"profile_id":null,"state":"unavailable",
		"engine_mode":"unavailable","shaft_radps":null,"legacy_throttle":null,
		"tas_mps":null,"starved":null,"error":_diagnostic([reason])}

static func _diagnostic(reasons: Array) -> String:
	var message: String="; ".join(reasons)
	const SUFFIX: String="... [truncated]"
	return message if message.length()<=1024 else message.left(1024-SUFFIX.length())+SUFFIX

static func _same_source(view: Dictionary, source: Dictionary, state: String) -> bool:
	return view.state==state and view.session_id==source.session_id and view.tick==source.tick

static func _channel(channel: Dictionary, unit: String, kind: int) -> bool:
	return channel.get("valid")==true and channel.get("unit")==unit and typeof(channel.get("value"))==kind

static func from_readback(value: Variant) -> Dictionary:
	var source: Variant=value.duplicate(true) if value is Dictionary else value
	var problem: String=Readings._validate(source)
	if not problem.is_empty(): return _unavailable(problem)
	if source.aircraft==null: return _unavailable("No verified source publication")
	var state: String="historical" if source.historical or source.host_mode in Readings.TERMINAL else "paused" if source.paused else "live"
	var result: Dictionary={"session_id":source.session_id,"tick":source.tick,
		"profile_id":source.model_identity.id,"state":state,"engine_mode":"unavailable",
		"shaft_radps":null,"legacy_throttle":null,"tas_mps":null,"starved":null,"error":""}
	var engine_errors: Array[String]=[]
	var airflow_errors: Array[String]=[]
	var starvation_errors: Array[String]=[]
	var readings: Dictionary=Readings.from_readback(source)
	# Full source was already validated. Derived arithmetic overflow only mutes
	# airflow; it must not erase independently valid engine observations.
	if readings.state in ["live","paused","historical"]:
		if not _same_source(readings,source,state): return _unavailable("Audio readings source mismatch")
		var tas: Dictionary=readings.readings.tas
		if _channel(tas,"m/s",TYPE_FLOAT) and is_finite(tas.value) and tas.value>=0.0:
			result.tas_mps=tas.value
		else: airflow_errors.append("Airflow unavailable: "+str(tas.get("error","Invalid TAS channel")))
	else:
		airflow_errors.append("Airflow unavailable: "+str(readings.error))
	if source.model_identity==Readings.LEGACY_PROFILE:
		result.engine_mode="legacy"
		result.legacy_throttle=float(source.held_axes.throttle)
	else:
		var status: Dictionary=EngineStatus.from_readback(source)
		if not _same_source(status,source,state): return _unavailable("Audio engine source mismatch")
		var shaft: Dictionary=status.readings["propeller.angular_speed"]
		var running: Dictionary=status.readings["engine.running"]
		if not _channel(shaft,"radps",TYPE_FLOAT) or not is_finite(shaft.value) or shaft.value<0.0:
			engine_errors.append("Engine unavailable: "+str(shaft.get("error","Invalid shaft channel")))
		if not _channel(running,"bool",TYPE_BOOL):
			engine_errors.append("Engine unavailable: "+str(running.get("error","Invalid Running channel")))
		if engine_errors.is_empty():
			if running.value and shaft.value==0.0:
				engine_errors.append("Engine unavailable: Running is true with stopped shaft")
			else:
				result.shaft_radps=shaft.value
				result.engine_mode="running" if running.value else "rotating" if shaft.value>0.0 else "stopped"
		var starved: Dictionary=status.readings["engine.starved"]
		if _channel(starved,"bool",TYPE_BOOL): result.starved=starved.value
		else: starvation_errors.append("Starvation observation unavailable: "+str(starved.get("error","Invalid starved channel")))
	var errors: Array=[]
	errors.append_array(engine_errors)
	errors.append_array(airflow_errors)
	errors.append_array(starvation_errors)
	result.error=_diagnostic(errors)
	return result
