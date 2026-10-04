extends RefCounted
# Original MIT. Explicit bounded proof flag only; actual native + disposable files.
const Codec=preload("res://replay/observed_archive/codec.gd")
var _scene: Node
var _failures: Array[String]=[]
var _checks:=0

func _check(ok: bool, label: String) -> void:
	_checks+=1
	if not ok: _failures.append(label)
	_scene.check(ok,"archive_visual_"+label)

func run(scene: Node) -> void:
	_scene=scene
	var sizes: Array[Vector2i]=[Vector2i(960,540),Vector2i(1920,1080),Vector2i(2560,1440)]
	var work: String=OS.get_cache_dir().path_join("archive-visual-"+str(OS.get_process_id())+"-"+str(Time.get_ticks_usec()))
	_check(DirAccess.make_dir_recursive_absolute(work)==OK,"unique_fixture_root")
	scene.archive_dialog.current_dir=work
	for index in sizes.size():
		scene.named_start="airborne-prepared"
		_check(scene.restart(true),"fresh_paused_worker_"+str(index))
		scene.menu_open=false;scene.menu.hide()
		_check(scene.pause_session(false),"explicit_resume_"+str(index))
		for frame in 24: _check(scene.advance_wall_us(250000),"interval_"+str(index)+"_"+str(frame))
		_check(scene.pause_session(true),"verified_pause_"+str(index))
		scene.show_state(0.0)
		var native: Dictionary=scene.facade.readback()
		var recorded: Dictionary=scene.observed_recorder.recording()
		_check(native.tick=="720" and recorded.samples.size()==13,"actual_six_seconds_"+str(index))
		scene.get_window().size=sizes[index]
		await scene.get_tree().process_frame
		await scene.get_tree().process_frame
		var prefix: String="observed-archive-"+str(sizes[index].x)
		scene.open_observed_review()
		await scene.save_view(prefix+"-current")
		_check(scene.begin_archive_operation("save"),"chooser_gate_"+str(index))
		await scene.save_view(prefix+"-choose-save")
		_check(scene.archive_dialog.visible and not scene.archive_operation.is_empty(),"visible_save_chooser_"+str(index))
		_check(not scene.pause_session(false) and not scene.restart(true),"modal_controls_blocked_"+str(index))
		scene.cancel_archive_operation()
		var saved_path: String=work.path_join("current-"+str(index)+".fsreview.json")
		_check(scene.begin_archive_operation("save",false),"save_gate_"+str(index))
		var saved: Dictionary=scene.finish_archive_operation(saved_path)
		_check(saved.ok,"actual_save_"+str(index))
		await scene.save_view(prefix+"-saved")
		var historical: Dictionary=recorded.duplicate(true)
		historical.metadata.session_id="archive.visual.historical"
		historical.metadata.native_source_fingerprint="f".repeat(64)
		for sample in historical.samples:sample.readings.session_id=historical.metadata.session_id
		var encoded: Dictionary=Codec.encode(historical)
		_check(encoded.ok,"qualified_synthetic_historical_metadata_"+str(index))
		var historical_path: String=work.path_join("historical-"+str(index)+".fsreview.json")
		_check(scene.archive_files.save_new(historical_path,encoded.value).ok,"historical_fixture_saved_"+str(index))
		_check(scene.begin_archive_operation("open"),"open_chooser_"+str(index))
		await scene.save_view(prefix+"-choose-open")
		var opened: Dictionary=scene.finish_archive_operation(historical_path)
		_check(opened.ok and scene.archive_imported,"actual_opened_historical_"+str(index))
		scene.observed_panel.select_sample(0)
		await scene.save_view(prefix+"-opened")
		var viewport: Rect2=scene.get_viewport().get_visible_rect()
		for key in ["_title","_back","_save_file","_open_file","_current_file","_details_button","_cursor","_summary","_instant","_controls","_graph_choice"]:
			var control: Control=scene.observed_panel.get(key)
			if control.visible:_check(viewport.encloses(control.get_global_rect()),"inside_"+str(index)+"_"+key)
		_check(scene.begin_archive_operation("save",false),"collision_gate_"+str(index))
		_check(not scene.finish_archive_operation(saved_path).ok,"actual_collision_refused_"+str(index))
		await scene.save_view(prefix+"-collision")
		var recovery_path: String=work.path_join("recovery-"+str(index)+".fsreview.json")
		scene.archive_files.set("_fault","post_verify")
		_check(scene.begin_archive_operation("save",false),"recovery_gate_"+str(index))
		var uncertain: Dictionary=scene.finish_archive_operation(recovery_path)
		scene.archive_files.set("_fault","")
		_check(not uncertain.ok and uncertain.state=="recovery_required" and FileAccess.file_exists(recovery_path),"actual_injected_unverified_target_"+str(index))
		scene.observed_panel.get("_details").popup_centered(Vector2i(720,330))
		await scene.save_view(prefix+"-recovery-details")
		# The qualified Windows receipt resolves separators; require the complete
		# selected path after that representation change, not just its filename.
		_check(scene.observed_panel.get("_details_text").text.replace("\\","/").contains(recovery_path.replace("\\","/")),"copyable_full_recovery_path_"+str(index))
		scene.observed_panel.get("_details").hide()
		_check(scene.facade.readback()==native and scene.observed_recorder.recording()==recorded,"all_views_preserve_actual_flight_"+str(index))
		scene.dismiss_observed_review()
		for path in [saved_path,historical_path,recovery_path]:
			_check(path.begins_with(work+"/") and DirAccess.remove_absolute(path)==OK,"remove_owned_fixture_"+str(index)+"_"+path.get_file())
		for name in ["current","choose-save","saved","choose-open","opened","collision","recovery-details"]:
			var image: Image=Image.load_from_file(scene.output_directory().path_join(prefix+"-"+name+".png"))
			_check(image!=null and image.get_width()==sizes[index].x and image.get_height()==sizes[index].y,"exact_dimensions_"+str(index)+"_"+name)
	_check(DirAccess.remove_absolute(work)==OK,"empty_fixture_root_removed")
	var joined: bool=scene.close_session()
	if scene.sound!=null: joined=bool(await scene.sound.shutdown()) and joined
	_check(joined,"native_and_audio_joined")
	var result: Dictionary={"passed":_failures.is_empty(),"checks":_checks,"failures":_failures,"scope":"21 bounded GPU views over6 actual simulated seconds/13 observations per size, selected synthetic historical metadata, actual new-file/open/collision and explicitly injected post-verification recovery; no pilot/device/aircraft/phase acceptance.","context":"editor" if OS.has_feature("editor") else "exported","windows":[[960,540],[1920,1080],[2560,1440]]}
	var file:=FileAccess.open(scene.output_directory().path_join("observed-archive-visual-receipt.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify(result,"  "));file.close()
	print("OBSERVED_ARCHIVE_VISUAL_SMOKE ",JSON.stringify(result))
	scene.get_tree().quit(0 if result.passed else 1)
