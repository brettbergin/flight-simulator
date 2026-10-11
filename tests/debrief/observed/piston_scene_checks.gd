extends RefCounted
# Original MIT. Actual cold native observations; synthetic Raw, never forged truth.
const Previous = preload("res://observed_tests/scene_checks.gd")
const RouteFixture = preload("res://freeflight_tests/scene_checks.gd")
const Facade = preload("res://simulation/session_facade.gd")
const EngineStatus = preload("res://cockpit/instruments/engine_status.gd")
const Codec = preload("res://replay/observed_archive/codec.gd")
const ReferenceChecks = preload("res://observed_archive_tests/archive_checks.gd")
var _host: Node
var _checks := 0
var _failures: Array[String] = []
var _counter: RefCounted
var _capture_helper: RefCounted = RouteFixture.new()

func _check(ok: bool, name: String) -> void:
	_checks += 1
	if not ok: _failures.append(name)
	_host.call("check",ok,"piston_review_scene_"+name)

func _capture(scene: Node) -> PackedByteArray:
	_capture_helper.set("_observed",_counter)
	return var_to_bytes({"base":_capture_helper.call("_capture",scene),
		"raw":scene.synthetic_raw.duplicate(true),"pointer":scene.mapper.pointer_view(),
		"mapper_v2":_mapper_v2(scene.mapper),
		"rearm":scene.engine_pointer_rearm.duplicate(),"pending_systems":scene.pending_systems.duplicate(true),
		"held_systems":scene.held_systems.duplicate(true),"controls":scene.controls.duplicate(true),
		"record":scene.observed_recorder.recording(),"status":scene.observed_status.duplicate(true)})

func _mapper_v2(mapper: RefCounted) -> Dictionary:
	var value: Dictionary={}
	for key in ["_held_systems","_system_intents","_system_edges","_pointer_begin","_pointer_terminal","_pointer_pending","_pointer_disabled","_pointer_rearm","_pointer_error"]:
		var item: Variant=mapper.get(key)
		value[key]=item.duplicate(true) if item is Dictionary or item is Array else item
	return value

func _intervals(scene: Node, keys: Array, count: int) -> void:
	scene.synthetic_raw.keys=keys.duplicate()
	for i in count:
		scene.process_input_interval(250000)
		scene.show_state(0.0)

func run(host: Node) -> Dictionary:
	_host=host
	var scene=Previous.SyntheticScene.new()
	scene.selected_profile=Facade.PISTON_PROFILE.id
	scene.named_start="piston-cold-ground"
	host.add_child(scene)
	scene.set_process(false)
	if scene.sound!=null: scene.sound.set_process(false)
	var initialized: bool=scene.facade!=null and scene.facade.readback().get("model_identity")==Facade.PISTON_PROFILE
	_check(initialized,"qualified_cold_profile_adopted")
	if not initialized:
		if scene.facade!=null: _check(scene.close_session(),"failed_initialization_joined")
		if scene.sound!=null: _check(bool(await scene.sound.shutdown()),"failed_initialization_audio_joined")
		scene.free()
		return _result()
	_counter=RouteFixture.CountedBridge.new(scene.facade._bridge)
	scene.facade._bridge=_counter
	var initial: Dictionary=scene.observed_recorder.recording()
	var initial_ok: bool=initial.get("contract_version")==2 and initial.get("samples") is Array and initial.samples.size()==1 and initial.samples[0].get("tick")=="0"
	_check(initial_ok,"initial_version2_sample")
	if not initial_ok:
		_check(scene.close_session(),"failed_recorder_initialization_joined")
		if scene.sound!=null: _check(bool(await scene.sound.shutdown()),"failed_recorder_initialization_audio_joined")
		scene.free()
		return _result()
	_check(initial.samples[0].engine_status==EngineStatus.from_readback(scene.facade.readback()),"initial_engine_from_same_owned_readback")
	_check(scene.pause_session(false),"explicit_resume")
	scene.menu_open=false
	scene.menu.hide()
	# Ordinary keyboard bindings enrich mixture/throttle and enable ignition.
	_intervals(scene,[KEY_PERIOD],12)
	_intervals(scene,[KEY_W],4)
	_intervals(scene,[KEY_F8,KEY_F9],1)
	_intervals(scene,[],1)
	_intervals(scene,[KEY_F12],16)
	var cranking: Dictionary=scene.facade.readback()
	_check(EngineStatus.from_readback(cranking).readings["engine.starter"].value==true,"actual_held_starter_published")
	# Normal pause may retire local intent. Subsequent review must not release
	# the native starter or bypass held-key admission on Resume.
	_check(scene.pause_session(true),"normal_pause_boundary")
	var held_boundary: PackedByteArray=_capture(scene)
	scene.open_observed_review()
	_check(scene.review_open and scene.observed_panel.get("_record").contract_version==2,"current_cold_review_visible")
	_check(_capture(scene)==held_boundary,"review_keeps_native_raw_controls_debt_origin_and_history")
	for index in [0,1,scene.observed_status.sample_count-1]:
		_check(scene.observed_panel.select_sample(index),"select_captured_"+str(index))
		_check(_capture(scene)==held_boundary,"scrub_is_pure_"+str(index))
	_check(scene.begin_archive_operation("save",false),"current_save_gate")
	scene.cancel_archive_operation()
	_check(_capture(scene)==held_boundary,"save_cancel_is_pure")
	scene.dismiss_observed_review()
	_check(_capture(scene)==held_boundary,"dismiss_keeps_held_boundary")
	_check(not scene.pause_session(false) and _capture(scene)==held_boundary,"held_starter_still_blocks_resume")
	scene.synthetic_raw.keys=[]
	_check(scene.pause_session(false),"released_raw_allows_ordinary_resume")
	scene.menu_open=false
	scene.menu.hide()
	_intervals(scene,[],8)
	var released: Dictionary=EngineStatus.from_readback(scene.facade.readback())
	_check(released.readings["engine.starter"].value==false,"normal_release_reaches_native")
	# Shutdown is another ordinary mapped mixture command, not a review action.
	_intervals(scene,[KEY_COMMA],16)
	_intervals(scene,[],8)
	_check(scene.pause_session(true),"shutdown_pause_boundary")
	var record: Dictionary=scene.observed_recorder.recording()
	var saw_starter := false
	var saw_running := false
	for sample in record.samples:
		var channels: Dictionary=sample.engine_status.readings
		if channels["engine.starter"].valid and channels["engine.starter"].value: saw_starter=true
		if channels["engine.running"].valid and channels["engine.running"].value: saw_running=true
		_check(sample.readings.session_id==sample.engine_status.session_id and sample.tick==sample.engine_status.tick,"sample_owned_source_identity_"+sample.tick)
	_check(record.contract_version==2 and record.samples.size()>8 and saw_starter,"actual_cold_attempt_retains_engine_samples")
	_check(saw_running,"actual_engine_running_observed")
	var final_engine: Dictionary=EngineStatus.from_readback(scene.facade.readback())
	_check(final_engine.readings["engine.mixture"].value==0.0 and not final_engine.readings["engine.running"].value,"actual_mixture_cutoff_shutdown")
	scene.open_observed_review()
	var baseline: PackedByteArray=_capture(scene)
	if OS.get_name()=="Windows":
		var directory: String=ProjectSettings.globalize_path("user://").path_join("piston-review-"+str(OS.get_process_id())+"-"+str(Time.get_ticks_usec()))
		var fresh: bool=not DirAccess.dir_exists_absolute(directory) and DirAccess.make_dir_absolute(directory)==OK
		_check(fresh,"fresh_selected_local_test_directory")
		if fresh:
			var path: String=directory.path_join("cold.fsreview.json")
			_check(scene.begin_archive_operation("save",false),"selected_new_save_gate")
			var saved: Dictionary=scene.finish_archive_operation(path)
			_check(saved.ok and _capture(scene)==baseline,"selected_save_preserves_complete_current")
			var bytes: PackedByteArray=FileAccess.get_file_as_bytes(path)
			var decoded: Dictionary=Codec.decode(bytes)
			var comparison: Dictionary={"checks":0,"failures":[]}
			if decoded.ok: ReferenceChecks._compare(comparison,decoded.value,record,"actual_cold_record")
			_check(decoded.ok and comparison.checks>0 and comparison.failures.is_empty(),"saved_record_roundtrips_exact_types_and_bits")
			_check(scene.begin_archive_operation("save",false),"collision_save_gate")
			var collision: Dictionary=scene.finish_archive_operation(path)
			_check(not collision.ok and FileAccess.get_file_as_bytes(path)==bytes and _capture(scene)==baseline,"collision_preserves_file_and_current")
			_check(scene.begin_archive_operation("open",false),"historical_open_gate")
			var opened: Dictionary=scene.finish_archive_operation(path)
			_check(opened.ok and scene.archive_imported and _capture(scene)==baseline,"import_is_historical_without_native_adoption")
			scene.show_current_review()
			_check(not scene.archive_imported and _capture(scene)==baseline,"current_view_retains_current_history")
			_check(DirAccess.remove_absolute(path)==OK and DirAccess.remove_absolute(directory)==OK,"only_owned_file_and_empty_directory_removed")
	scene.dismiss_observed_review()
	_check(_capture(scene)==baseline,"final_dismiss_is_pure")
	_check(scene.close_session(),"owned_native_worker_joined")
	if scene.sound!=null: _check(bool(await scene.sound.shutdown()),"owned_audio_joined")
	scene.free()
	return _result()

func _result() -> Dictionary:
	return {"passed":_failures.is_empty(),"checks":_checks,"failures":_failures.duplicate(),"scope":"Actual original cold native startup/shutdown samples and paused authority with synthetic keyboard Raw; selected new Windows file IO. Separate fresh-process Open, airborne attempt, GPU, pilot and aircraft qualification remain required."}
