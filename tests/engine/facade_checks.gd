extends RefCounted
# Original MIT. Actual six-operation delegation with explicitly synthetic faults.
# These checks establish host behavior, never a second physical reference suite.
const Facade=preload("res://simulation/session_facade.gd")
const U64=preload("res://simulation/uint64.gd")
const SYSTEM_ORDER: Array=["engine.ignition_left","engine.ignition_right","engine.starter","fuel.feed"]
var checks: int=0
var failures: Array[String]=[]
var adapters: Array=[]
var mode: String=""
var fault_position: int=0
var disposable_models: Dictionary={}

class ObservedAdapter extends RefCounted:
	var native: RefCounted=ClassDB.instantiate("FlightInteractiveSession") as RefCounted
	var mode: String
	var position: int
	var calls: Array=[]
	var submitted: Array=[]
	var integrated: int=0
	var joined: bool=false
	var closes: int=0
	func _init(kind: String="",at: int=0) -> void:
		mode=kind
		position=at
	func open_session(root: String,start: String,wind: Variant="calm",profile: Variant="original-interactive-prototype") -> Dictionary:
		calls.append(["open",start,wind,profile])
		var value: Dictionary=native.call("open_session",root,start,wind,profile)
		if mode=="missing_method": value.erase("angular_integration_method")
		elif mode=="wrong_method": value.angular_integration_method="event_aware_constant_power_v1"
		elif mode=="extra_open": value.unknown=true
		elif mode=="wrong_fingerprint": value.native_source_fingerprint=("0" if Facade.NATIVE[0]!="0" else "1")+Facade.NATIVE.substr(1)
		elif mode.begins_with("initial_"):
			var aircraft: Dictionary=JSON.parse_string(value.aircraft_json)
			match mode:
				"initial_fuel": _system(aircraft,"fuel.total").value=99.0
				"initial_shaft": _system(aircraft,"propeller.angular_speed").value=0.01
				"initial_running": _system(aircraft,"engine.running").value=true
				"initial_starved": _system(aircraft,"engine.starved").value=true
				"initial_ignition": _system(aircraft,"engine.ignition_left").value=true
				"initial_feed": _system(aircraft,"fuel.feed").value=false
				"initial_duplicate": aircraft.systems.append(aircraft.systems[0].duplicate(true))
				"initial_wrong_unit": _system(aircraft,"propeller.angular_speed").quantity="rpm"
				"initial_numeric_bool": _system(aircraft,"engine.running").value=0.0
				"initial_mixture":
					_system(aircraft,"engine.mixture").value=1.0
					value.held_axes.mixture=1.0
			value.aircraft_json=JSON.stringify(aircraft)
		return value
	func _system(aircraft: Dictionary,id: String) -> Dictionary:
		for system in aircraft.systems:
			if system.id==id: return system
		return {}
	func read_state() -> Dictionary:
		calls.append(["read"])
		return native.call("read_state")
	func submit(command: Dictionary) -> Dictionary:
		calls.append(["submit",command.payload.duplicate(true)])
		submitted.append(command.duplicate(true))
		if mode=="reject_before" and submitted.size()==position:
			var rejected: Dictionary=native.call("read_state")
			rejected.rejection=1
			rejected.queued=false
			return rejected
		var reply: Dictionary=native.call("submit",command)
		if mode=="corrupt_ack" and submitted.size()==position: reply.erase("queued")
		return reply
	func session_control(control: Dictionary) -> Dictionary:
		calls.append(["lifecycle",control.payload.duplicate(true)])
		return native.call("session_control",control)
	func step_fixed(count: int) -> Dictionary:
		calls.append(["step",count])
		var reply: Dictionary=native.call("step_fixed",count)
		integrated+=int(reply.get("completed",0))
		if mode=="wrong_echo" and not reply.applied_commands_json.is_empty():
			var record: Dictionary=JSON.parse_string(reply.applied_commands_json[-1])
			record.payload.value=not record.payload.value
			reply.applied_commands_json[-1]=JSON.stringify(record)
		return reply
	func close() -> Dictionary:
		calls.append(["close"])
		closes+=1
		var reply: Dictionary=native.call("close")
		joined=reply.get("ok")==true and reply.get("joined")==true
		return reply

static func run(root: String) -> Dictionary:
	return new()._run(root)

func _check(ok: bool,label: String) -> void:
	checks+=1
	if not ok: failures.append(label)

func _factory() -> RefCounted:
	var adapter: RefCounted=ObservedAdapter.new(mode,fault_position)
	adapters.append(adapter)
	return adapter

func _host(root: String) -> RefCounted:
	var facade: RefCounted=Facade.new(_factory)
	var result: Dictionary=facade.start(root,"piston-cold-ground","calm",Facade.PISTON_PROFILE.id)
	_check(result.ok,"actual_cold_open_"+mode+"_"+str(fault_position))
	return facade

func _intent(facade: RefCounted) -> Dictionary:
	var axes: Dictionary=facade.readback().held_axes.duplicate(true)
	axes.mixture=1.0
	axes.throttle=0.15
	var systems: Dictionary=Facade.COLD_SYSTEMS.duplicate(true)
	systems["engine.ignition_left"]=true
	systems["engine.ignition_right"]=true
	systems["engine.starter"]=true
	systems["fuel.feed"]=false
	return {"axes":axes,"systems":systems}

func _selector_cases(root: String) -> void:
	mode=""
	var facade: RefCounted=_host(root)
	var adapter: RefCounted=adapters[-1]
	var before: Dictionary=facade.readback()
	var origin: RefCounted=facade.render_origin
	var calls: Array=adapter.calls.duplicate(true)
	for selectors in [["piston-cold-ground",Facade.PISTON_PROFILE.id,Facade.PISTON_PROFILE.id],["piston-cold-ground",StringName("calm"),Facade.PISTON_PROFILE.id],["piston-cold-ground","calm",StringName(Facade.PISTON_PROFILE.id)],["piston-cold-ground","calm",true],["airborne-prepared","calm",Facade.PISTON_PROFILE.id],["ground-ready","calm",Facade.PISTON_PROFILE.id],["piston-cold-ground","from-west",Facade.PISTON_PROFILE.id]]:
		var count: int=adapters.size()
		# A fresh host has no 'already open' guard that could mask bad admission.
		var fresh: RefCounted=Facade.new(_factory)
		var rejected: Dictionary=fresh.start(root,selectors[0],selectors[1],selectors[2])
		_check(not rejected.ok and adapters.size()==count and rejected.readback.tick==null and not rejected.readback.native_live,"fresh_invalid_selector_before_factory_"+str(selectors))
		fresh.close()
		var result: Dictionary=facade.start(root,selectors[0],selectors[1],selectors[2])
		_check(not result.ok and adapters.size()==count and adapter.calls==calls and facade.readback()==before and facade.render_origin==origin,"invalid_selection_before_existing_session_mutation_"+str(selectors))
	_check(not facade.reset("airborne-prepared").ok and adapter.calls==calls and facade.readback()==before,"unsupported_reset_preserves_actual_cold_session")
	_check(facade.close().ok and adapter.joined,"selector_session_joined")

func _copy_model(root: String,label: String) -> String:
	# Sibling copies share the real payload/bin module owner. A user:// copy
	# correctly fails that production check, regardless of its valid model bytes.
	# Never edit the installed model or reuse/remove a prior fixture directory.
	var target: String=root.get_base_dir().path_join("cold-model-"+label+"-"+str(OS.get_process_id())+"-"+str(Time.get_ticks_usec()))
	if DirAccess.dir_exists_absolute(target) or FileAccess.file_exists(target): return ""
	if FileAccess.get_sha256(root.path_join("inventory.json"))!=Facade.PISTON_INVENTORY: return ""
	var inventory: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(root.path_join("inventory.json")))
	var paths: Array=["inventory.json"]
	for row in inventory.files+inventory.metadata: paths.append(row.path)
	disposable_models[target]=paths.duplicate()
	for relative in paths:
		var path: String=target.path_join(relative)
		if DirAccess.make_dir_recursive_absolute(path.get_base_dir())!=OK: return ""
		var file=FileAccess.open(path,FileAccess.WRITE)
		if file==null: return ""
		file.store_buffer(FileAccess.get_file_as_bytes(root.path_join(relative)))
		file.close()
	return target

func _remove_model_copy(target: String) -> void:
	# Remove only this process's explicitly created fixture names, never recurse
	# through an installed model or read paths from a mutated inventory.
	_check(disposable_models.has(target),"disposable_cleanup_owned_root")
	if not disposable_models.has(target): return
	var paths: Array=disposable_models[target].duplicate()
	paths.append_array(["unexpected.txt",".unexpected"])
	for relative in paths:
		var path: String=target.path_join(relative)
		if FileAccess.file_exists(path):
			_check(DirAccess.remove_absolute(path)==OK,"disposable_cleanup_file_"+str(relative))
	for relative in ["aircraft/original-piston-prop","aircraft","engine",""]:
		var path: String=target if relative.is_empty() else target.path_join(relative)
		if DirAccess.dir_exists_absolute(path):
			_check(DirAccess.remove_absolute(path)==OK,"disposable_cleanup_directory_"+str(relative))
	_check(not DirAccess.dir_exists_absolute(target),"disposable_model_copy_retired")
	disposable_models.erase(target)

func _preclose_model_cases(root: String) -> void:
	mode=""
	for defect in ["inventory","engine_same_length","metadata","missing_engine","extra","hidden_extra"]:
		var copy: String=_copy_model(root,defect)
		_check(not copy.is_empty(),"disposable_model_copy_"+defect)
		if copy.is_empty(): continue
		_check(Facade._selection_error(copy,"piston-cold-ground","calm",Facade.PISTON_PROFILE.id).is_empty(),"disposable_copy_has_complete_reviewed_model_"+defect)
		var facade: RefCounted=_host(copy)
		if not facade.readback().native_live:
			facade.close()
			_remove_model_copy(copy)
			continue
		var adapter: RefCounted=adapters[-1]
		var before: Dictionary=facade.readback()
		var origin: RefCounted=facade.render_origin
		var calls: Array=adapter.calls.duplicate(true)
		var path: String=copy.path_join("inventory.json" if defect=="inventory" else "engine/original-piston.xml" if defect in ["engine_same_length","missing_engine"] else "README.md" if defect=="metadata" else ".unexpected" if defect=="hidden_extra" else "unexpected.txt")
		if defect=="missing_engine":
			_check(DirAccess.remove_absolute(path)==OK,"remove_disposable_engine")
		else:
			var content: PackedByteArray=FileAccess.get_file_as_bytes(path) if FileAccess.file_exists(path) else PackedByteArray([88])
			if defect=="engine_same_length":
				# Change content without changing length or the original inventory.
				content[0]=33 if content[0]!=33 else 34
			else: content.append(88)
			var file=FileAccess.open(path,FileAccess.WRITE)
			_check(file!=null,"disposable_mutation_open_"+defect)
			if file!=null:
				file.store_buffer(content)
				file.close()
		var count: int=adapters.size()
		var result: Dictionary=facade.reset("piston-cold-ground")
		_check(not result.ok and adapters.size()==count and adapter.calls==calls and facade.readback()==before and facade.render_origin==origin and not adapter.joined,"model_tamper_rejected_before_old_close_"+defect)
		_check(facade.close().ok and adapter.joined,"tamper_session_joined_"+defect)
		_remove_model_copy(copy)
	# These raw spellings must exercise actual Facade normalization, not just
	# a test-side rewrite or rejection before reaching the real native bridge.
	for valid_root in [root,root+"/",root+"\\"]:
		var facade: RefCounted=_host(valid_root)
		_check(facade.close().ok,"valid_root_normalization_"+valid_root)

func _open_mutants(root: String) -> void:
	for mutant in ["missing_method","wrong_method","extra_open","wrong_fingerprint","initial_fuel","initial_shaft","initial_running","initial_starved","initial_ignition","initial_feed","initial_duplicate","initial_wrong_unit","initial_numeric_bool","initial_mixture"]:
		mode=mutant
		var facade: RefCounted=Facade.new(_factory)
		var result: Dictionary=facade.start(root,"piston-cold-ground","calm",Facade.PISTON_PROFILE.id)
		var adapter: RefCounted=adapters[-1]
		_check(not result.ok and adapter.joined and adapter.closes==1 and adapter.integrated==0,"mutated_actual_open_joined_zero_run_"+mutant)
		_check(adapter.calls.size()==2 and adapter.calls[0][0]=="open" and adapter.calls[1][0]=="close","mutated_open_no_step_submit_lifecycle_"+mutant)
		_check(result.readback.tick==null and not result.readback.native_live and result.readback.native_source_fingerprint==null,"mutated_open_no_live_publication_"+mutant)
		facade.close()

func _command_cases(root: String) -> void:
	mode=""
	var facade: RefCounted=_host(root)
	var adapter: RefCounted=adapters[-1]
	var intent: Dictionary=_intent(facade)
	var before: Array=adapter.calls.duplicate(true)
	var stored: Dictionary=facade.set_pilot_intent(intent.axes,intent.systems)
	_check(stored.ok and stored.admission=="intent_stored" and adapter.calls==before,"complete_intent_local_before_due_boundary")
	intent.axes.mixture=0.2
	intent.systems["engine.starter"]=false
	var invalid: Dictionary=intent.systems.duplicate(true)
	invalid["engine.starter"]=1
	_check(not facade.set_pilot_intent(intent.axes,invalid).ok,"numeric_boolean_rejects_entire_local_replacement")
	var advanced: Dictionary=facade.advance_wall_us(8334)
	_check(advanced.ok and advanced.completed==1 and adapter.integrated==1 and adapter.submitted.size()==5 and advanced.applied_commands.size()==5,"five_actual_submissions_one_native_tick")
	if advanced.ok:
		_check(advanced.readback.held_axes.mixture==1.0,"copied_intent_survives_caller_and_invalid_replacement")
	for i in adapter.submitted.size():
		var command: Dictionary=adapter.submitted[i]
		_check(command.sequence==str(i+1) and command.tick=="1" and command.source_id=="pilot.controls" and command.authority=="pilot" and command.assistance=={"profile_id":"unassisted","active":[]},"shared_exact_uint64_lane_identity_"+str(i))
		_check(command.payload.kind=="axes" if i==0 else command.payload.kind=="system" and command.payload.control_id==SYSTEM_ORDER[i-1] and typeof(command.payload.value)==TYPE_BOOL,"axes_then_fixed_boolean_order_"+str(i))
	var count: int=adapter.submitted.size()
	_check(facade.set_pilot_intent(_intent(facade).axes,_intent(facade).systems).ok and facade.advance_wall_us(8333).ok and adapter.submitted.size()==count,"unchanged_intent_not_resubmitted")
	_check(facade.set_paused(true).ok,"actual_pause")
	var paused: Dictionary=facade.readback()
	_check(Facade._snapshot_systems(paused.aircraft)["engine.starter"]==true,"paused_actual_starter_true_retained")
	var marker: int=adapter.calls.size()
	var ticks: int=adapter.integrated
	_check(facade.set_paused(false).ok and adapter.integrated==ticks,"resume_admission_has_no_run")
	var release_index: int=-1
	var resume_index: int=-1
	for i in range(marker,adapter.calls.size()):
		var call: Array=adapter.calls[i]
		if call[0]=="submit" and call[1]=={"kind":"system","control_id":"engine.starter","value":false}: release_index=i
		if call[0]=="lifecycle" and call[1]=={"kind":"pause","paused":false}: resume_index=i
	_check(release_index>=marker and resume_index>release_index,"starter_false_ack_precedes_unpause")
	advanced=facade.advance_wall_us(8334)
	_check(advanced.ok and not Facade._snapshot_systems(advanced.readback.aircraft)["engine.starter"],"actual_next_boundary_starter_release")
	_check(facade.close().ok and adapter.joined,"command_session_joined")

func _partial_admission(root: String) -> void:
	for mutant in ["reject_before","corrupt_ack"]:
		for position in range(1,6):
			mode=mutant
			fault_position=position
			var facade: RefCounted=_host(root)
			var adapter: RefCounted=adapters[-1]
			var intent: Dictionary=_intent(facade)
			_check(facade.set_pilot_intent(intent.axes,intent.systems).ok,"partial_intent_stored")
			var result: Dictionary=facade.advance_wall_us(8334)
			_check(not result.ok and adapter.joined and adapter.integrated==0 and adapter.submitted.size()==position and result.readback.tick=="0" and result.readback.historical,"actual_accepted_prefix_no_run_terminal_"+mutant+"_"+str(position))
			_check(result.applied_commands.is_empty() and not result.observation_complete,"unverified_prefix_not_published_as_applied_"+mutant+"_"+str(position))
			_check(not facade.advance_wall_us(8334).ok,"terminal_prefix_requires_fresh_session")
			facade.close()
	fault_position=0
	for exhausted in ["18446744073709551614","18446744073709551615"]:
		mode=""
		var facade: RefCounted=_host(root)
		var adapter: RefCounted=adapters[-1]
		var intent: Dictionary=_intent(facade)
		facade.set("_command_sequence",exhausted)
		facade.set_pilot_intent(intent.axes,intent.systems)
		var result: Dictionary=facade.advance_wall_us(8334)
		_check(not result.ok and adapter.joined and adapter.integrated==0 and adapter.submitted.is_empty(),"synthetic_counter_full_reservation_before_any_actual_submit_"+exhausted)
		facade.close()
	mode="wrong_echo"
	var facade: RefCounted=_host(root)
	var adapter: RefCounted=adapters[-1]
	var intent: Dictionary=_intent(facade)
	var retained: Dictionary=facade.readback()
	facade.set_pilot_intent(intent.axes,intent.systems)
	var result: Dictionary=facade.advance_wall_us(8334)
	_check(not result.ok and adapter.joined and adapter.integrated==1 and result.readback.tick=="0" and result.applied_commands.is_empty(),"mutated_actual_applied_record_retains_last_verified_tick")
	_check(result.readback.aircraft==retained.aircraft and result.readback.atmosphere==retained.atmosphere and result.readback.held_axes==retained.held_axes,"unverified_tick_preserves_complete_last_aircraft_weather_controls")
	facade.close()

func _starter_recovery_cases(root: String) -> void:
	mode=""
	var facade: RefCounted=_host(root)
	var adapter: RefCounted=adapters[-1]
	var intent: Dictionary=_intent(facade)
	_check(facade.set_pilot_intent(intent.axes,intent.systems).ok,"pending_starter_local_intent")
	_check(facade.set_paused(true).ok and facade.set_paused(false).ok,"pending_only_pause_resume")
	_check(adapter.submitted.is_empty() and adapter.integrated==0,"unadmitted_starter_true_cleared_without_native_command")
	var result: Dictionary=facade.advance_wall_us(8334)
	_check(result.ok and not Facade._snapshot_systems(result.readback.aircraft)["engine.starter"] and adapter.submitted.is_empty(),"pending_only_starter_never_applied_after_resume")
	facade.close()
	for rejection in ["reject_before","corrupt_ack"]:
		mode=""
		facade=_host(root)
		adapter=adapters[-1]
		intent=_intent(facade)
		facade.set_pilot_intent(intent.axes,intent.systems)
		_check(facade.advance_wall_us(8334).ok and facade.set_paused(true).ok,"actual_starter_held_before_recovery_fault_"+rejection)
		var marker: int=adapter.calls.size()
		var ticks: int=adapter.integrated
		adapter.mode=rejection
		adapter.position=6
		result=facade.set_paused(false)
		_check(not result.ok and adapter.joined and adapter.integrated==ticks and result.readback.tick=="1" and result.readback.historical,"release_failure_terminal_retains_completed_truth_"+rejection)
		var unpause: bool=false
		for i in range(marker,adapter.calls.size()):
			var call: Array=adapter.calls[i]
			if call[0]=="lifecycle" and call[1]=={"kind":"pause","paused":false}: unpause=true
		_check(not unpause and not facade.advance_wall_us(8334).ok,"failed_starter_release_never_unpauses_or_runs_"+rejection)
		facade.close()

func _run(root: String) -> Dictionary:
	_check(ClassDB.class_exists("FlightInteractiveSession"),"actual_native_bridge_required")
	if ClassDB.class_exists("FlightInteractiveSession"):
		_selector_cases(root)
		_preclose_model_cases(root)
		_open_mutants(root)
		_command_cases(root)
		_partial_admission(root)
		_starter_recovery_cases(root)
	# Also retire an explicitly registered partial copy after an I/O failure.
	for target in disposable_models.keys(): _remove_model_copy(target)
	return {"passed":failures.is_empty(),"checks":checks,"failures":failures.duplicate(),"scope":"Actual original cold profile host/control delegation plus synthetic acknowledgement, publication and uint64 faults; physical lifecycle/reference and pilot gates separate"}
