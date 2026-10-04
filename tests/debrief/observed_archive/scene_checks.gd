extends RefCounted
# Original MIT. Actual unchanged worker; copied released Raw and local test files.
const Previous = preload("res://observed_tests/scene_checks.gd")
const RouteFixture = preload("res://freeflight_tests/scene_checks.gd")
const Codec = preload("res://replay/observed_archive/codec.gd")
var _host: Node
var _checks := 0
var _failures: Array[String]=[]
var _counter: RefCounted
var _capture_helper: RefCounted=RouteFixture.new()

func _check(ok: bool, label: String) -> void:
	_checks+=1
	if not ok: _failures.append(label)
	_host.call("check",ok,"archive_scene_"+label)

func _capture(scene: Node) -> Dictionary:
	_capture_helper.set("_observed",_counter)
	return {"native":_capture_helper.call("_capture",scene),"record":scene.observed_recorder.recording(),"status":scene.observed_status.duplicate(true)}

func run(host: Node) -> Dictionary:
	_host=host
	var scene:=Previous.SyntheticScene.new()
	scene.named_start="airborne-prepared"
	host.add_child(scene)
	scene.set_process(false)
	_counter=RouteFixture.CountedBridge.new(scene.facade._bridge)
	scene.facade._bridge=_counter
	_check(scene.pause_session(false),"explicit_resume")
	scene.menu_open=false;scene.menu.hide()
	for i in 4: scene.process_input_interval(250000)
	_check(scene.pause_session(true),"verified_pause")
	scene.show_state(0.0)
	scene.open_observed_review()
	_check(scene.review_open and scene.facade.readback().tick=="120","actual_recorded_review_at_120")
	var baseline: Dictionary=_capture(scene)
	scene.observed_panel.select_sample(0)
	var selected: Dictionary=scene.observed_panel.selection()
	_check(scene.begin_archive_operation("open",false),"open_gate")
	_check(not scene.pause_session(false) and not scene.restart(true),"gate_refuses_resume_and_direct_reset")
	scene.start_flight("ground-ready")
	scene.dispatch_input_action("view_chase")
	scene.open_controls()
	scene.apply_controls(scene.active_preset)
	scene.select_input_device("proof",-1)
	scene.dismiss_controls()
	scene.process_input_interval(250000)
	_check(scene.pending_discard.is_empty() and _capture(scene)==baseline,"gate_preserves_native_recorder_mapper_and_camera")
	scene.cancel_archive_operation()
	_check(scene.archive_operation.is_empty() and scene.observed_panel.selection()==selected and _capture(scene)==baseline,"chooser_cancel_preserves_cursor_and_complete_boundary")
	_check(not scene.observed_panel.set_recording({}) and scene.observed_panel.selection()==selected,"candidate_rejection_preserves_old_selection")
	# Only proof-owned unique paths; no real player/profile content is read.
	var work: String=OS.get_cache_dir().path_join("flight-review-scene-"+str(OS.get_process_id())+"-"+str(Time.get_ticks_usec()))
	_check(DirAccess.make_dir_recursive_absolute(work)==OK,"unique_local_workdir")
	var target: String=work.path_join("Recorded review — Δ flight.fsreview.json")
	var bad_path: String=work.path_join("invalid.fsreview.json")
	var bad=FileAccess.open(bad_path,FileAccess.WRITE)
	_check(bad!=null,"malformed_fixture_file_created")
	if bad!=null: bad.store_string("{}");bad.close()
	_check(scene.begin_archive_operation("open",false),"bad_open_gate")
	var bad_result: Dictionary=scene.finish_archive_operation(bad_path)
	_check(not bad_result.ok and scene.observed_panel.selection()==selected and _capture(scene)==baseline,"bad_open_preserves_current_and_selected_review")
	_check(scene.begin_archive_operation("save",false),"save_gate")
	var saved: Dictionary=scene.finish_archive_operation(target)
	if OS.get_name()=="Windows":
		_check(saved.ok and saved.state=="saved" and saved.value==null,"actual_new_NTFS_file_verified")
		_check(_capture(scene)==baseline and scene.observed_status.state=="recording","save_does_not_seal_or_mutate_current")
		var encoded: PackedByteArray=FileAccess.get_file_as_bytes(target)
		var decoded: Dictionary=Codec.decode(encoded)
		_check(decoded.ok and decoded.value==baseline.record,"actual_saved_current_record_roundtrip")
		_check(scene.begin_archive_operation("save",false),"collision_gate")
		var collision: Dictionary=scene.finish_archive_operation(target)
		_check(not collision.ok and FileAccess.get_file_as_bytes(target)==encoded and _capture(scene)==baseline,"collision_keeps_existing_bytes_and_current_state")
		# Explicit metadata-bearing historical fixture; it never enters the recorder.
		var history: Dictionary=baseline.record.duplicate(true)
		history.metadata.session_id="archive.historical.reference"
		history.metadata.native_source_fingerprint="f".repeat(64)
		for sample in history.samples: sample.readings.session_id=history.metadata.session_id
		var historical_bytes: Dictionary=Codec.encode(history)
		_check(historical_bytes.ok,"qualified_distinct_historical_candidate")
		var history_path: String=work.path_join("historical.fsreview.json")
		var written: Dictionary=scene.archive_files.save_new(history_path,historical_bytes.value)
		_check(written.ok,"actual_historical_fixture_new_file")
		_check(scene.begin_archive_operation("open",false),"historical_open_gate")
		var opened: Dictionary=scene.finish_archive_operation(history_path)
		_check(opened.ok and scene.archive_imported and scene.observed_panel.get("_record").metadata.session_id==history.metadata.session_id,"imported_identity_is_display_only")
		_check(scene.observed_panel.get("_summary").text.begins_with("OPENED FILE / HISTORICAL"),"explicit_imported_provenance")
		_check(scene.observed_panel.select_sample(0) and _capture(scene)==baseline,"historical_scrub_preserves_complete_current_state")
		var prior: Dictionary=scene.observed_panel.selection()
		_check(scene.begin_archive_operation("open",false),"imported_cancel_gate")
		scene.cancel_archive_operation()
		_check(scene.archive_imported and scene.observed_panel.selection()==prior,"cancel_preserves_previous_import_cursor")
		_check(scene.begin_archive_operation("open",false),"imported_failure_gate")
		scene.finish_archive_operation(bad_path)
		_check(scene.archive_imported and scene.observed_panel.selection()==prior and _capture(scene)==baseline,"failed_import_preserves_prior_historical_cursor")
		# Saving while viewing an import still captures the CURRENT recorder.
		var current_again: String=work.path_join("current-again.fsreview.json")
		_check(scene.begin_archive_operation("save",false),"save_from_import_gate")
		var saved_current: Dictionary=scene.finish_archive_operation(current_again)
		var reread: Dictionary=Codec.decode(FileAccess.get_file_as_bytes(current_again))
		_check(saved_current.ok and reread.ok and reread.value==baseline.record and scene.archive_imported,"save_from_import_keeps_import_and_saves_current")
		scene.show_current_review()
		_check(not scene.archive_imported and scene.observed_panel.get("_record")==baseline.record and _capture(scene)==baseline,"this_flight_returns_to_current_without_native_change")
		for file in [history_path,current_again,target]:
			_check(file.begins_with(work+"/") and DirAccess.remove_absolute(file)==OK,"remove_owned_file_"+file.get_file())
	else:
		_check(not saved.ok and not FileAccess.file_exists(target) and _capture(scene)==baseline,"nonWindows_truthful_unsupported_preserves_current")
	_check(DirAccess.remove_absolute(bad_path)==OK and DirAccess.remove_absolute(work)==OK,"remove_only_known_test_fixture_and_empty_workdir")
	scene.dismiss_observed_review()
	_check(not scene.review_open and not scene.archive_imported and scene.facade.readback().paused,"dismiss_returns_paused_without_resume")
	scene.start_flight("ground-ready")
	_check(not scene.pending_discard.is_empty(),"saved_file_does_not_bypass_discard_confirmation")
	scene.cancel_discard()
	_check(_capture(scene)==baseline,"discard_Cancel_retains_complete_current_record")
	_check(scene.close_session(),"actual_native_worker_joined")
	if scene.sound!=null: _check(bool(await scene.sound.shutdown()),"audio_joined")
	scene.queue_free()
	await host.get_tree().process_frame
	return {"passed":_failures.is_empty(),"checks":_checks,"failures":_failures.duplicate(),"scope":"Actual unchanged native worker, explicit paused Save/Open and historical display over isolated synthetic local files; native/recorder/mapper/camera/origin invariance. No device, human, aircraft or phase acceptance."}
