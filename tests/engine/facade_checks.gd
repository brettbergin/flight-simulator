extends RefCounted
# Original MIT. Explicit synthetic six-operation adapter, NEVER solver evidence.
const Facade=preload("res://simulation/session_facade.gd")
const StatusChecks=preload("res://engine_tests/status_checks.gd")
const U64=preload("res://simulation/uint64.gd")
var checks: int=0
var failures: Array=[]
var adapter: RefCounted
var mode: String=""

class SyntheticAdapter extends RefCounted:
	var aircraft: Dictionary
	var weather: Dictionary
	var axes: Dictionary
	var paused: bool=false
	var queued: Array=[]
	var submitted: Array=[]
	var events: Array=[]
	var calls: int=0
	var runs: int=0
	var joined: bool=false
	var mode: String
	var opened: Array=[]
	func _init(mutant: String="") -> void:
		mode=mutant
		var source: Dictionary=StatusChecks.new().fixture()
		aircraft=source.aircraft.duplicate(true)
		weather=source.atmosphere.duplicate(true)
		axes=source.held_axes.duplicate(true)
		axes.throttle=0.0;axes.mixture=0.0;axes.left_brake=1.0;axes.right_brake=1.0
	func reply() -> Dictionary:
		return {"ok":true,"schema_version":1,"completed":0,"aircraft_json":JSON.stringify(aircraft),"atmosphere_json":JSON.stringify(weather),"held_axes":axes.duplicate(true),"live":true,"paused":paused,"historical":false,"fault":"","time_scale":1.0,"outcome":"paused" if paused else "completed","ground_query_valid":true,"plane_clearance_m":1.05,"applied_commands_json":[],"events_json":[]}
	func open_session(root: String,start: String,profile: String="original-interactive-prototype") -> Dictionary:
		opened=[root,start,profile]
		var value: Dictionary=reply()
		value.named_start=start;value.prepared_world_sha256=Facade.WORLD;value.native_source_fingerprint=Facade.NATIVE
		value.world_anchor={"latitude_rad":0.8,"longitude_rad":-2.0,"ellipsoid_height_m":0.0}
		return value
	func read_state() -> Dictionary:
		return reply()
	func submit(command: Dictionary) -> Dictionary:
		calls+=1
		submitted.append(command.duplicate(true))
		var value: Dictionary=reply()
		value.rejection=1 if mode=="reject_second" and calls==2 else 0
		value.queued=value.rejection==0
		if value.queued: queued.append(command.duplicate(true))
		return value
	func session_control(control: Dictionary) -> Dictionary:
		paused=control.payload.paused
		events.append({"type":"OperationalEvent","schema_version":1,"tick":aircraft.tick,"session_id":aircraft.session_id,"sequence":control.sequence,"source_id":"session.owner","confidence":"observed","content_version":"0.1.0-prototype","payload":control.payload.duplicate(true)})
		var value: Dictionary=reply();value.rejection=0
		return value
	func step_fixed(count: int) -> Dictionary:
		var applied: Array=[]
		if not paused:
			for i in count:
				runs+=1
				var tick: String=U64.increment(aircraft.tick).value
				for command in queued:
					if command.payload.kind=="axes":
						axes=command.payload.duplicate(true)
						aircraft.configuration.trim_fraction=axes.trim
						for system in aircraft.systems:
							if system.id=="engine.throttle": system.value=axes.throttle
							if system.id=="engine.mixture": system.value=axes.mixture
					else:
						for system in aircraft.systems:
							if system.id==command.payload.control_id: system.value=command.payload.value
					applied.append(JSON.stringify(command))
				queued.clear()
				aircraft.tick=tick;aircraft.elapsed_s=float(tick)/120.0;weather.tick=tick
		var value: Dictionary=reply()
		value.completed=0 if paused else count
		value.applied_commands_json=applied
		for event in events: value.events_json.append(JSON.stringify(event))
		events.clear()
		if mode=="wrong_system_echo" and not applied.is_empty():
			var mutant: Dictionary=JSON.parse_string(applied[-1])
			mutant.payload.value=not mutant.payload.value
			value.applied_commands_json[-1]=JSON.stringify(mutant)
		return value
	func close() -> Dictionary:
		joined=true
		return {"ok":true,"joined":true}

func check(ok: bool,label: String) -> void:
	checks+=1
	if not ok: failures.append(label)
func factory() -> RefCounted:
	adapter=SyntheticAdapter.new(mode)
	return adapter
func host(root: String) -> RefCounted:
	var facade: RefCounted=Facade.new(factory)
	var result: Dictionary=facade.start(root,"piston-cold-ground",Facade.PISTON_PROFILE.id)
	check(result.ok,"synthetic_cold_open_"+mode)
	return facade

func run(root: String) -> Dictionary:
	var facade: RefCounted=host(root)
	var axes: Dictionary=facade.readback().held_axes.duplicate(true)
	var systems: Dictionary=Facade.COLD_SYSTEMS.duplicate(true)
	axes.mixture=1.0;axes.throttle=0.15
	systems["engine.ignition_left"]=true;systems["engine.ignition_right"]=true;systems["engine.starter"]=true;systems["fuel.feed"]=false
	var stored: Dictionary=facade.set_pilot_intent(axes,systems)
	check(stored.ok and stored.admission=="intent_stored" and adapter.calls==0 and adapter.runs==0,"local_copy_before_boundary")
	axes.mixture=0.2;systems["engine.starter"]=false
	var advanced: Dictionary=facade.advance_wall_us(8334)
	check(advanced.ok and adapter.calls==5 and adapter.runs==1,"five_separate_submits_one_run")
	check(advanced.applied_commands.size()==5 and advanced.readback.held_axes.mixture==1.0,"intent_owned_and_all_echoes")
	check(adapter.submitted[0].payload.kind=="axes","axes_first")
	for i in 5:
		check(adapter.submitted[i].sequence==str(i+1) and adapter.submitted[i].tick=="1","shared_lane_"+str(i))
		if i>0: check(adapter.submitted[i].payload.control_id==Facade.SYSTEM_IDS[i-1] and typeof(adapter.submitted[i].payload.value)==TYPE_BOOL,"ordered_bool_"+str(i))
	check(facade.set_paused(true).ok and adapter.runs==1,"pause_no_run")
	var actual: Dictionary=facade.readback()
	check(actual.paused and actual.aircraft.systems[7].value,"paused_starter_request_true")
	check(facade.set_paused(false).ok and adapter.runs==1,"release_admitted_before_resume_run")
	check(adapter.submitted[-1].payload=={"kind":"system","control_id":"engine.starter","value":false} and adapter.submitted[-1].tick=="2","recorded_next_boundary_release")
	advanced=facade.advance_wall_us(8334)
	check(advanced.ok and not advanced.readback.aircraft.systems[7].value,"completed_release_echo")
	var before: Dictionary=facade.readback()
	check(not facade.reset("airborne-prepared").ok and facade.readback()==before and not adapter.joined,"unsupported_reset_nondestructive")
	facade.close()
	for mutant in ["reject_second","wrong_system_echo"]:
		mode=mutant;facade=host(root)
		axes=facade.readback().held_axes.duplicate(true);axes.mixture=1.0
		systems=Facade.COLD_SYSTEMS.duplicate(true);systems["engine.starter"]=true
		check(facade.set_pilot_intent(axes,systems).ok,"mutant_stored_"+mutant)
		advanced=facade.advance_wall_us(8334)
		check(not advanced.ok and adapter.joined and advanced.readback.host_mode=="discarded" and advanced.readback.tick=="0","terminal_retained_last_completed_"+mutant)
		check(adapter.runs==(0 if mutant=="reject_second" else 1),"honest_actual_prefix_runs_"+mutant)
		check(not facade.advance_wall_us(8334).ok,"terminal_cannot_resume_"+mutant)
	mode="";facade=host(root)
	axes=facade.readback().held_axes.duplicate(true);axes.mixture=1.0
	systems=Facade.COLD_SYSTEMS.duplicate(true);systems["engine.starter"]=true
	check(facade.set_pilot_intent(axes,systems).ok,"valid_before_invalid")
	var bad: Dictionary=systems.duplicate(true);bad["engine.starter"]=1
	axes.mixture=0.0
	check(not facade.set_pilot_intent(axes,bad).ok,"numeric_bool_rejects_complete_intent")
	advanced=facade.advance_wall_us(8334)
	check(advanced.ok and advanced.readback.held_axes.mixture==1.0 and advanced.readback.aircraft.systems[7].value,"invalid_intent_atomic_local_preserves_valid")
	facade.close()
	mode="";facade=host(root)
	axes=facade.readback().held_axes.duplicate(true);axes.mixture=1.0
	systems=Facade.COLD_SYSTEMS.duplicate(true);systems["engine.starter"]=true
	facade.set("_command_sequence","18446744073709551614")
	facade.set_pilot_intent(axes,systems)
	advanced=facade.advance_wall_us(8334)
	check(not advanced.ok and adapter.calls==0 and adapter.runs==0 and adapter.joined,"reserve_all_sequences_before_submit")
	return {"passed":failures.is_empty(),"checks":checks,"failures":failures.duplicate(),"scope":"Synthetic six-operation adapter; no native engine or coupling evidence"}
