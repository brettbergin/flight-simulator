extends RefCounted
# Original MIT. Actual accepted worker; copied synthetic released Raw only.
const Scene = preload("res://simulation/flight_scene.gd")
const Recorder = preload("res://replay/observed/recorder.gd")
const RouteFixture = preload("res://freeflight_tests/scene_checks.gd")
class TrackingRecorder extends Recorder:
	var history_copies := 0
	func recording() -> Variant:
		history_copies+=1
		return super.recording()
class SyntheticScene extends Scene:
	var synthetic_raw: Dictionary={"keys":[],"mouse_buttons":[],"devices":[]}
	var missing_models := false
	var expected_start_errors: Array[String]=[]
	func _init() -> void:
		observed_recorder=TrackingRecorder.new()
	func collect_input_raw(_preset: Dictionary={}) -> Dictionary:
		return synthetic_raw.duplicate(true)
	func flight_model_root(profile_id: Variant=null) -> String:
		return ProjectSettings.globalize_path("res://__missing_observed_test_models__") if missing_models else super.flight_model_root(profile_id)
	func fail(message: String) -> bool:
		if not missing_models: return super.fail(message)
		# Expected actual facade inventory rejection. Suppress only push_error;
		# retain the production failure state without fabricating native replies.
		expected_start_errors.append(message)
		render_pose.clear()
		status=message+" | R starts a fresh attempt"
		paused=true
		blocked=true
		failures.append(message)
		return false
var _host: Node
var _checks := 0
var _failures: Array[String]=[]
var _counter: RefCounted
var _capture_helper: RefCounted=RouteFixture.new()
func _check(ok: bool, name: String) -> void:
	_checks+=1
	if not ok: _failures.append(name)
	_host.call("check",ok,"observed_scene_"+name)
func _capture(scene: Node) -> Dictionary:
	_capture_helper.set("_observed",_counter)
	return _capture_helper.call("_capture",scene)
func run(host: Node) -> Dictionary:
	_host=host
	var scene:=SyntheticScene.new()
	scene.named_start="airborne-prepared"
	host.add_child(scene)
	scene.set_process(false)
	_counter=RouteFixture.CountedBridge.new(scene.facade._bridge)
	scene.facade._bridge=_counter
	scene.show_state(0.0)
	_check(scene.observed_status.sample_count==1 and scene.observed_status.first_tick=="0" and scene.observed_status.last_sample_tick=="0","qualified_initial_sample")
	_check(scene.observed_recorder.history_copies==0,"initialization_uses_bounded_status_only")
	_check(scene.pause_session(false),"explicit_resume")
	scene.menu_open=false;scene.menu.hide()
	for i in 4:
		scene.process_input_interval(250000)
		scene.show_state(0.0)
	_check(scene.facade.readback().tick=="120" and scene.observed_status.sample_count==3 and scene.observed_status.last_sample_tick=="120" and _counter.completed==120,"four_actual_intervals_capture_three_real_grid_samples")
	_check(scene.observed_recorder.history_copies==0,"live_adoption_does_not_copy_full_history")
	_check(scene.pause_session(true),"explicit_pause")
	scene.show_state(0.0)
	var baseline: Dictionary=_capture(scene)
	scene.open_observed_review()
	_check(scene.review_open and scene.observed_panel.visible and not scene.menu.visible,"paused_review_visible")
	_check(scene.observed_recorder.history_copies==1,"explicit_review_copies_history_once")
	var record: Dictionary=scene.observed_panel.get("_record").duplicate(true)
	_check(record.samples.size()==3 and record.samples[0].tick=="0" and record.samples[1].tick=="60" and record.samples[2].tick=="120","review_contains_actual_ticks")
	_check(record.samples[0].anchor_eus_position_m!=record.samples[2].anchor_eus_position_m,"actual_airborne_path_has_displacement")
	for index in [0,1,2]:
		_check(scene.observed_panel.select_sample(index),"select_actual_sample_"+str(index))
		var selected: Dictionary=scene.observed_panel.selection()
		_check(selected.historical and selected.sample.tick==record.samples[index].tick,"selected_values_labeled_historical_"+str(index))
		selected.sample.held_axes.throttle=0.999
		_check(scene.observed_panel.selection().sample==record.samples[index],"selection_owned_copy_"+str(index))
		scene.show_state(0.0)
		_check(_capture(scene)==baseline,"scrub_complete_native_input_origin_camera_invariant_"+str(index))
	_check(not scene.observed_panel.select_sample(-1) and scene.observed_panel.selection().sample.tick=="120","invalid_cursor_keeps_selection")
	var key:=InputEventKey.new();key.pressed=true;key.physical_keycode=KEY_R
	scene._unhandled_key_input(key)
	_check(scene.pending_discard.is_empty() and _capture(scene)==baseline,"review_key_cannot_dispatch_restart")
	scene.dismiss_observed_review()
	_check(not scene.review_open and scene.paused and scene.menu.visible and _capture(scene)==baseline,"dismiss_keeps_paused_baseline")
	var old_start: String=scene.named_start
	scene.start_flight("ground-ready")
	_check(not scene.pending_discard.is_empty() and scene.pending_discard.start=="ground-ready" and scene.discard_layer.visible,"advanced_flight_requires_discard_choice")
	_check(scene.get_viewport().gui_get_focus_owner()==scene.discard_cancel,"cancel_is_default_focus")
	_check(scene.named_start==old_start and _capture(scene)==baseline,"request_does_not_change_start_or_native_state")
	scene.cancel_discard()
	_check(scene.pending_discard.is_empty() and not scene.discard_layer.visible and scene.named_start==old_start and _capture(scene)==baseline,"cancel_preserves_complete_paused_baseline")
	scene.open_observed_review()
	_check(scene.observed_panel.get("_record")==record,"cancel_preserves_recorded_review")
	scene.dismiss_observed_review()
	_check(scene.pause_session(false),"resume_before_live_review")
	scene.menu_open=false;scene.menu.hide()
	var completed_before: int=_counter.completed
	var lifecycle_before: int=_counter.lifecycle.size()
	scene.open_observed_review()
	_check(scene.paused and scene.review_open and _counter.completed==completed_before and _counter.lifecycle.size()==lifecycle_before+1,"live_review_only_takes_normal_explicit_pause")
	var paused_again: Dictionary=_capture(scene)
	scene.dismiss_observed_review()
	_check(_capture(scene)==paused_again,"live_open_dismiss_does_not_resume")
	var before_invalid_reset: Dictionary=_capture(scene)
	var record_before_invalid_reset: Dictionary=scene.observed_recorder.recording()
	var writes_before_invalid_reset: Dictionary=_counter.writes()
	scene.missing_models=true
	scene.start_flight("ground-ready")
	scene.confirm_discard()
	_check(not _counter.joined and _counter.writes()==writes_before_invalid_reset and scene.expected_start_errors.is_empty() and scene.status.contains("Reviewed model inventory identity mismatch"),"missing_inventory_rejected_before_existing_worker_mutation")
	var retained: Dictionary=scene.observed_recorder.recording()
	_check(_capture(scene)==before_invalid_reset and retained==record_before_invalid_reset and not scene.initializing_recording,"preflight_rejection_preserves_complete_paused_flight_and_recording")
	scene.open_observed_review()
	_check(scene.review_open and scene.observed_panel.get("_record")==retained,"rejected_reset_review_remains_available_on_unchanged_worker")
	scene.dismiss_observed_review()
	scene.missing_models=false
	scene.start_flight("ground-ready")
	_check(not scene.pending_discard.is_empty(),"retry_still_requires_explicit_discard")
	scene.confirm_discard()
	_counter=RouteFixture.CountedBridge.new(scene.facade._bridge);scene.facade._bridge=_counter
	_check(scene.facade.readback().session_id!=record.metadata.session_id and scene.observed_status.first_tick=="0" and scene.observed_status.sample_count==1,"successful_confirmed_reset_replaces_only_with_new_qualified_session")
	_check(not scene.recorded_flight_advanced(),"initialization_only_record_needs_no_extra_confirmation")
	_check(scene.close_session(),"final_actual_worker_joined")
	_check(scene.observed_status.state=="sealed" and scene.observed_status.seal_reason=="closed","joined_close_seals_valid_prefix")
	if scene.sound!=null: _check(bool(await scene.sound.call("shutdown")),"audio_thread_joined")
	scene.free()
	return {"passed":_failures.is_empty(),"checks":_checks,"failures":_failures,"scope":"Actual accepted worker and scene with synthetic released Raw; 120 flight ticks, paused review/cursor/native invariance, default-Cancel discard and actual inventory-rejected reset preserving old review. No pilot/GPU/sensed aircraft/phase acceptance."}
