extends RefCounted
# Original MIT. Actual native scene, with explicitly synthetic released input.
const Scene=preload("res://simulation/flight_scene.gd")
const Cue=preload("res://world/wind/wind_cue.gd")
class ReleasedScene extends Scene:
	var missing_models: bool=false
	var expected_start_errors: Array[String]=[]
	func collect_input_raw(_preset: Dictionary={}) -> Dictionary:
		return {"keys":[],"mouse_buttons":[],"devices":[]}
	func flight_model_root(profile_id: Variant=null) -> String:
		return ProjectSettings.globalize_path("res://__missing_wind_test_models__") if missing_models else super.flight_model_root(profile_id)
	func fail(message: String) -> bool:
		if not missing_models: return super.fail(message)
		# Suppress only the expected error log; retain the production failure state.
		expected_start_errors.append(message)
		render_pose.clear()
		status=message+" | R starts a fresh attempt"
		paused=true
		blocked=true
		failures.append(message)
		return false
var checks: int=0
var failures: Array[String]=[]
var _host: Node

func _check(ok: bool, label: String) -> void:
	checks+=1
	if not ok: failures.append(label)
	_host.call("check",ok,"wind_scene_"+label)

func _capture(scene: Node) -> Dictionary:
	var mapper: Dictionary={}
	for name in ["_preset","_values","_start","_pins","_edges","_takeover","_configured","_live","_brake_hold"]:
		var value: Variant=scene.mapper.get(name)
		mapper[name]=value.duplicate(true) if value is Dictionary or value is Array else value
	return {"native":scene.facade.get("_bridge").call("read_state"),"readback":scene.facade.readback(),"origin":scene.facade.render_origin.read_origin(),"mapper":mapper,"recording":scene.observed_recorder.recording(),"camera":scene.camera.transform,"camera_mode":scene.camera_mode,"controls":scene.held_controls.duplicate(true),"submitted":scene.submitted_count,"events":scene.event_count,"current":scene.current_wind_profile,"imported":scene.archive_imported}

func run(host: Node) -> Dictionary:
	_host=host
	var scene: Node=ReleasedScene.new()
	host.add_child(scene)
	scene.set_process(false)
	_check(scene.facade!=null and scene.facade.readback().aircraft!=null,"actual_initial_flight")
	if scene.facade==null or scene.facade.readback().aircraft==null:
		await _retire(scene)
		return _receipt()
	for profile in ["calm","from-north","from-west","from-east"]:
		for start_name in ["ground-ready","airborne-prepared"]:
			scene.perform_start(start_name,profile)
			_check(scene.current_wind_profile==profile and scene.facade.readback().named_start==start_name,"adopted_"+profile+"_"+start_name)
			_check(scene.pause_session(true),"actual_pause")
			scene.show_state(0.0)
			var cue: Dictionary=Cue.from_readback(scene.facade.readback())
			_check(cue.state=="paused" and scene.flight_map.get("_wind_cue")==cue,"actual_map_copied_cue")
			_check(scene.windsock_visual.visible,"paused_sock_visible")
			if cue.speed_mps>0.0:
				var flow: Array=cue.wind_toward_airfield_eus_mps
				var largest: float=maxf(absf(flow[0]),absf(flow[2]))
				var expected:=Vector3(flow[0]/largest,0.0,flow[2]/largest).normalized()
				_check((-scene.windsock_visual.basis.y).dot(expected)>0.99999,"sock_downstream_end_matches_truth")
			var baseline: Dictionary=_capture(scene)
			scene.open_wind()
			_check(scene.wind_panel.visible and _capture(scene)==baseline,"chooser_open_no_native_or_recording_change")
			scene.select_wind_draft("from-east" if profile!="from-east" else "from-west")
			_check(_capture(scene)==baseline,"valid_draft_no_current_mutation")
			var draft: String=scene.wind_draft
			for bad in [null,0,&"calm","from-south"]:
				scene.select_wind_draft(bad)
				_check(scene.wind_draft==draft and _capture(scene)==baseline,"invalid_draft_no_mutation")
			scene.dismiss_wind()
			_check(not scene.wind_panel.visible and _capture(scene)==baseline,"chooser_cancel_stays_paused")
			_check(scene.restart(true) and scene.current_wind_profile==profile,"ordinary_restart_keeps_current_not_draft")
	# Rejection before replacement admission must leave the live worker intact.
	_check(scene.pause_session(false) and scene.advance_wall_us(25000),"advanced_live_replacement_setup")
	var live_admission: Dictionary=_capture(scene)
	_check(not scene.restart(true,"from-north") and _capture(scene)==live_admission,"unverified_replacement_preserves_live_worker_and_recording")
	_check(scene.facade.readback().native_live and not scene.paused and not scene.blocked,"unverified_replacement_remains_live")
	# Create an actually observed advanced prefix for default-Cancel replacement.
	_check(scene.pause_session(false) and scene.advance_wall_us(25000) and scene.pause_session(true),"advanced_native_prefix")
	scene.show_state(0.0)
	var baseline: Dictionary=_capture(scene)
	scene.open_wind()
	scene.select_wind_draft("from-north")
	scene.start_wind_draft("ground-ready")
	_check(not scene.pending_discard.is_empty() and scene.discard_layer.visible,"advanced_apply_requires_discard")
	_check(scene.get_viewport().gui_get_focus_owner()==scene.discard_cancel,"discard_default_cancel_focus")
	var escape:=InputEventKey.new()
	escape.pressed=true
	escape.physical_keycode=KEY_ESCAPE
	scene._unhandled_key_input(escape)
	_check(scene.pending_discard.is_empty() and _capture(scene)==baseline,"escape_cancels_before_wind_modal_and_preserves_flight")
	scene.start_wind_draft("ground-ready")
	scene.confirm_discard()
	_check(scene.current_wind_profile=="from-north" and scene.facade.readback().named_start=="ground-ready","confirmed_draft_replaces_flight")
	_check(scene.pause_session(true),"confirmed_start_paused")
	scene.wind_draft="from-west"
	scene.start_flight("airborne-prepared")
	_check(scene.current_wind_profile=="from-west" and scene.facade.readback().named_start=="airborne-prepared","ordinary_fresh_start_uses_draft")
	_check(scene.pause_session(true),"fresh_start_pause")
	var old_profile: String=scene.current_wind_profile
	var old_record: Dictionary=scene.observed_recorder.recording()
	scene.missing_models=true
	scene.perform_start("ground-ready","from-east")
	scene.show_state(0.0)
	var stopped_record: Dictionary=scene.observed_recorder.recording()
	_check(scene.expected_start_errors.size()==1 and not scene.facade.readback().native_live and scene.facade.readback().host_mode=="closed","failed_fresh_start_is_closed_not_old_live")
	_check(scene.current_wind_profile==old_profile and stopped_record.metadata==old_record.metadata and stopped_record.samples==old_record.samples and stopped_record.state=="sealed","failed_start_keeps_old_choice_and_closed_recording")
	_check(not scene.windsock_visual.visible and scene.flight_map.get("_wind_cue").state in ["empty","invalid"],"failed_start_has_no_current_looking_wind")
	scene.missing_models=false
	scene.perform_start("airborne-prepared",old_profile)
	_check(scene.pause_session(true),"recovered_fresh_start_paused")
	var live_before: Dictionary=_capture(scene)
	_check(scene.pause_session(false),"live_chooser_guard_setup")
	var live: Dictionary=_capture(scene)
	scene.open_wind()
	_check(not scene.wind_panel.visible and _capture(scene)==live,"chooser_requires_existing_boundary_no_implicit_pause")
	_check(scene.pause_session(true),"live_guard_final_pause")
	_check(scene.close_session(),"actual_close_join")
	# close_session clears the facade reference; retained truth is tested directly.
	var historical: Dictionary=live_before.readback.duplicate(true)
	historical.host_mode="closed"
	historical.native_live=false
	historical.paused=false
	historical.historical=true
	scene.update_wind_presentation(historical)
	_check(not scene.windsock_visual.visible and scene.flight_map.get("_wind_cue").state=="historical","historical_sock_suppressed")
	scene.update_wind_presentation({})
	_check(not scene.windsock_visual.visible and scene.flight_map.get("_wind_cue").state in ["invalid","empty"],"invalid_sock_suppressed")
	await _retire(scene)
	return _receipt()

func _retire(scene: Node) -> void:
	if scene.facade!=null: _check(scene.close_session(),"retired_native_joined")
	if scene.sound!=null: _check(bool(await scene.sound.call("shutdown")),"retired_audio_joined")
	scene.free()

func _receipt() -> Dictionary:
	return {"passed":failures.is_empty(),"checks":checks,"failures":failures.duplicate(),"scope":"Actual native eight-start/menu/draft/discard/map/sock invariance with synthetic released input; copied historical/invalid display fixtures. No human, GPU or aircraft qualification."}
