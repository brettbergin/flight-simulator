extends RefCounted
# Original MIT. Synthetic observation/admission tests; no backend execution.
const Status = preload("res://cockpit/instruments/engine_status.gd")
const Readings = preload("res://cockpit/instruments/native_readings.gd")
var checks: int=0
var failures: Array=[]

func check(ok: bool, label: String) -> void:
	checks+=1
	if not ok:
		failures.append(label)

func fixture() -> Dictionary:
	var reference: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://instrument_tests/reference.json"))
	var value: Dictionary=reference.cases[0].input.duplicate(true)
	value.debt_quanta=0
	value.model_identity=Readings.PISTON_PROFILE.duplicate(true)
	value.named_start="piston-cold-ground"
	value.held_axes.mixture=0.0
	value.aircraft.systems=[]
	for id in Status.UNITS:
		var quantity: String=Status.UNITS[id]
		var datum: Variant=false if quantity=="bool" else 0.0
		if id=="fuel.total": datum=100.0
		if id=="fuel.feed": datum=true
		value.aircraft.systems.append({"id":id,"quantity":quantity,"value":datum,"validity":"valid"})
	return value

func invalid(value: Variant,label: String) -> void:
	var result: Dictionary=Status.from_readback(value)
	check(result.state=="invalid" and result.session_id==null and result.tick==null and not result.error.is_empty(),label+"_invalid_identity")
	check(result.readings.size()==10,label+"_ten_channels")
	for id in Status.UNITS:
		check(result.readings[id].value==null and not result.readings[id].valid,label+"_clears_"+id)
	check(not Status.held_systems_from_readback(value).ok,label+"_no_guessed_controls")

func run() -> Dictionary:
	var input: Dictionary=fixture()
	var before: Dictionary=input.duplicate(true)
	var result: Dictionary=Status.from_readback(input)
	check(result.keys()==["session_id","tick","state","native_truth","readings","error"],"exact_six_keys")
	check(result.state=="live" and result.native_truth and result.readings.size()==10,"synthetic_live_ten")
	check(input==before,"source_owned_unmodified")
	for id in Status.UNITS:
		var channel: Dictionary=result.readings[id]
		check(channel.keys()==["value","unit","valid","error"] and channel.unit==Status.UNITS[id] and channel.valid and channel.error.is_empty(),"exact_channel_"+id)
		check(typeof(channel.value)==(TYPE_BOOL if channel.unit=="bool" else TYPE_FLOAT),"channel_type_"+id)
	var selected: Dictionary=Status.held_systems_from_readback(input)
	check(selected=={"ok":true,"error":"","value":{"engine.ignition_left":false,"engine.ignition_right":false,"engine.starter":false,"fuel.feed":true}},"cold_systems_exact")
	result.readings["fuel.total"].value=-123.0
	selected.value["fuel.feed"]=false
	check(input==before and Status.from_readback(input).readings["fuel.total"].value==100.0,"returned_values_owned")
	# Shaft may spin while Running=false; throttle cannot manufacture combustion.
	input.aircraft.systems[1].value=0.7
	input.held_axes.throttle=0.7
	input.aircraft.systems[3].value=50.0
	result=Status.from_readback(input)
	check(result.readings["propeller.angular_speed"].value==50.0 and not result.readings["engine.running"].value,"coasting_not_throttle_running")
	input=fixture()
	input.host_mode="paused";input.paused=true
	input.aircraft.systems[7].value=true
	result=Status.from_readback(input)
	check(result.state=="paused" and result.readings["engine.starter"].value and Status.held_systems_from_readback(input).value["engine.starter"],"paused_starter_true_remains_truthful")
	input.host_mode="closed";input.historical=true;input.native_live=false;input.paused=false
	check(Status.from_readback(input).state=="historical","joined_retained_truth")
	input=fixture();input.aircraft.systems.remove_at(7)
	result=Status.from_readback(input)
	check(result.state=="live" and result.readings["fuel.total"].valid and not result.readings["engine.starter"].valid and result.readings["engine.starter"].value==null,"missing_individual_not_off")
	check(not Status.held_systems_from_readback(input).ok,"missing_control_rejects_configuration")
	input=fixture();input.aircraft.systems[7].quantity="fraction";input.aircraft.systems[7].value=1.0
	check(not Status.from_readback(input).readings["engine.starter"].valid,"wrong_quantity_unavailable")
	for mutant in ["legacy","unknown_profile","recipe","numeric_bool","duplicate","nonfinite","extra_readback","wrong_weather_tick","contradictory_pause"]:
		input=fixture()
		match mutant:
			"legacy": input.model_identity=Readings.LEGACY_PROFILE.duplicate(true);input.named_start="ground-ready";input.held_axes.mixture=1.0
			"unknown_profile": input.model_identity.version="future"
			"recipe": input.named_start="ground-ready"
			"numeric_bool": input.aircraft.systems[7].value=1
			"duplicate": input.aircraft.systems.append(input.aircraft.systems[7].duplicate(true))
			"nonfinite": input.aircraft.systems[3].value=INF
			"extra_readback": input.engine=true
			"wrong_weather_tick": input.atmosphere.tick="1"
			"contradictory_pause": input.paused=true
		invalid(input,mutant)
	invalid(null,"null_source")
	input=fixture();input.model_identity=Readings.LEGACY_PROFILE.duplicate(true);input.named_start="ground-ready"
	check(Readings.from_readback(input).state=="invalid","legacy_mixture_zero_stays_rejected")
	input.held_axes.mixture=1.0
	check(Readings.from_readback(input).state=="live","legacy_fullrich_preserved")
	return {"passed":failures.is_empty(),"checks":checks,"failures":failures.duplicate(),"scope":"Synthetic status copies only; native model and package proof separate"}
