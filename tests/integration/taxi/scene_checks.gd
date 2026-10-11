extends RefCounted
# Original MIT. Real production/native lifecycle; only released Raw is synthetic.
# Existing spies forward to the actual native adapter and count every mutation.
const Existing=preload("res://first_flight_scene_tests/scene_checks.gd")
const NavigationChecks=preload("res://taxi_tests/navigation_checks.gd")
const Layout=preload("res://world/taxi/taxi_layout.gd")
const Briefing=preload("res://ui/first_flight/briefing_panel.gd")
class CountedReadAdapter extends Existing.ObservedAdapter:
	var read_calls: int=0
	func read_state() -> Dictionary:
		read_calls+=1
		return super.read_state()
class CountedTaxiScene extends Existing.SyntheticScene:
	var raw_reads: int=0
	func make_observed_adapter() -> RefCounted:
		var adapter: RefCounted=CountedReadAdapter.new()
		adapter.inject_open_failure=inject_next_open_failure
		inject_next_open_failure=false
		observed_adapters.append(adapter)
		return adapter
	func collect_input_raw(preset: Dictionary={}) -> Dictionary:
		raw_reads+=1
		return super.collect_input_raw(preset)

var _checks: int=0
var _failures: Array[String]=[]
var _host: Node
var _observer: RefCounted=Existing.new()
var _observer_read_credits: Dictionary={}

func _check(ok: bool,label: String) -> void:
	_checks+=1
	if not ok: _failures.append(label)
	_host.call("check",ok,"taxi_scene_"+label)

func _authority(scene: Node) -> PackedByteArray:
	var adapter: RefCounted=scene.facade.get("_bridge")
	var before: int=adapter.read_calls
	var complete: PackedByteArray=_observer._snapshot(scene)
	# The accepted complete snapshot itself reads the real adapter exactly once.
	# Credit that explicit observation only; all consumer reads remain counted.
	_check(adapter.read_calls==before+1,"authority_observer_makes_one_known_native_read")
	var id: int=adapter.get_instance_id()
	_observer_read_credits[id]=_observer_read_credits.get(id,0)+1
	var native_reads: Array=[]
	for observed in scene.observed_adapters:
		native_reads.append(observed.read_calls-_observer_read_credits.get(observed.get_instance_id(),0))
	return var_to_bytes({"complete":complete,"calls":_observer._ledger(scene),"raw_reads":scene.raw_reads,"native_read_calls":native_reads})

func _presentation(scene: Node) -> PackedByteArray:
	return var_to_bytes({"camera":scene.camera_view_settings(),"mode":scene.camera_mode,"look":scene.look_angles,
		"distance":scene.camera_distance,"map_visible":scene.map_visible,"map_widget_visible":scene.flight_map.visible,
		"runway":scene.flight_map._runway,"map_zoom":scene.flight_map.extent_m,"panel_visible":scene.panel_visible,
		"audio_options":scene.audio_options.duplicate(true),"taxi_marker_visible":scene._taxi_marker.visible})

func _press(page: Node,name: String) -> void:
	var button: Button=page.find_child(name,true,false) as Button
	_check(button!=null and not button.disabled,"enabled_"+name)
	if button!=null and not button.disabled: button.pressed.emit()

func _modal_matrix(scene: Node,label: String) -> void:
	var before: PackedByteArray=_authority(scene)
	_check(scene.open_taxi() and scene.taxi_panel.visible,label+"_paused_open")
	_check(_authority(scene)==before,label+"_paused_open_no_native_mapper_recorder_calls")
	_check(scene.get_viewport().gui_get_focus_owner()==scene.taxi_panel.get_back_button(),label+"_default_Back_focus")
	for elapsed in [0,8334,250000]:
		scene.process_input_interval(elapsed)
		scene.show_state(0.0)
		_check(scene.taxi_open and _authority(scene)==before,label+"_interval_"+str(elapsed)+"_inert")
	for request in [["pause_session",[false]],["advance_wall_us",[8334]],["submit_axes",[scene.controls.duplicate(true)]],["set_flight_scale",[0.5]],["restart",[true,"calm","original-interactive-prototype","ground-ready"]]]:
		var reply: Variant=scene.callv(request[0],request[1])
		_check(typeof(reply)==TYPE_BOOL and not reply and scene.taxi_open and _authority(scene)==before,label+"_direct_"+request[0]+"_inert")
	for method in ["open_menu","quit_flight","open_controls","open_wind","open_audio","open_views","open_first_flight","open_landmark_route","open_instrument_scan","open_observed_review"]:
		scene.call(method)
		_check(scene.taxi_open and scene.taxi_panel.visible and _authority(scene)==before,label+"_other_modal_"+method+"_inert")
	var presentation: PackedByteArray=_presentation(scene)
	for action in ["restart","start_ground","start_airborne","view_cycle","view_panel","map_toggle","runway_toggle","map_zoom_in","speed_up","audio","controls_panel"]:
		scene.dispatch_input_action(action)
		_check(scene.taxi_open and _authority(scene)==before and _presentation(scene)==presentation,label+"_action_"+action+"_inert")
	_check(not scene.begin_archive_operation("open",false) and _authority(scene)==before,label+"_archive_inert")
	var stale: Callable=scene._taxi_callbacks.route_requested
	var session: String=scene.adopted_session_id
	var layout: Dictionary=Layout.load().value
	# All six routes remain manual and make no native/input/recorder calls.
	for route_index in layout.itineraries.size():
		var row: Dictionary=layout.itineraries[route_index]
		var picker: OptionButton=scene.taxi_panel.find_child("Itinerary",true,false) as OptionButton
		picker.select(route_index)
		picker.item_selected.emit(route_index)
		_press(scene.taxi_panel,"BeginItinerary")
		var view: Dictionary=scene.taxi_navigation.observe(scene.facade.readback())
		_check(view.itinerary_id==row.id and view.point_index==0 and view.target_eus_m==row.points[0].point_eus_m,label+"_choose_"+row.id)
		_check(_authority(scene)==before,label+"_choose_"+row.id+"_preserves_full_authority")
		if row.runway!=null: _check(scene.flight_map._runway==row.runway,label+"_explicit_runway_sync_"+row.id)
		for index in row.points.size():
			_press(scene.taxi_panel,"NextPoint")
			view=scene.taxi_navigation.observe(scene.facade.readback())
			_check(view.point_index==mini(index+1,row.points.size()-1) and view.state==("manual-ended" if index==row.points.size()-1 else "active"),label+"_manual_next_"+row.id+"_"+str(index))
		_check(_authority(scene)==before,label+"_manual_progress_is_not_aircraft_movement_"+row.id)
	_press(scene.taxi_panel,"Back")
	_check(not scene.taxi_open and scene.paused and scene.menu_open and _authority(scene)==before,label+"_Back_keeps_paused")
	_check(scene.open_taxi(),label+"_same_session_reopen")
	var navigation: PackedByteArray=var_to_bytes(scene.taxi_navigation.observe(scene.facade.readback()))
	stale.call(layout.itineraries[0].id,session)
	_check(var_to_bytes(scene.taxi_navigation.observe(scene.facade.readback()))==navigation and _authority(scene)==before,label+"_retired_same_session_callback_inert")
	var current: Callable=scene._taxi_callbacks.route_requested
	current.call(layout.itineraries[0].id,"wrong-session")
	current.call(layout.itineraries[0].id,StringName(session))
	_check(var_to_bytes(scene.taxi_navigation.observe(scene.facade.readback()))==navigation and _authority(scene)==before,label+"_foreign_or_wrong_type_session_callback_inert")
	var escape:=InputEventKey.new()
	escape.physical_keycode=KEY_ESCAPE; escape.pressed=true
	scene._unhandled_key_input(escape)
	_check(not scene.taxi_open and scene.paused and scene.menu_open and _authority(scene)==before,label+"_Escape_closes_page_only")

func run(host: Node) -> Dictionary:
	_host=host
	var scene: Node=CountedTaxiScene.new()
	host.add_child(scene)
	scene.set_process(false)
	scene.set_process_input(false)
	scene.set_process_unhandled_input(false)
	scene.set_process_unhandled_key_input(false)
	var readbacks: Array=[]
	_check(scene.taxi_navigation!=null and scene.taxi_panel!=null,"configured_shared_layout_before_world_build")
	for pair in [["original-interactive-prototype","apron-ready"],["original-piston-prop-v1","piston-cold-apron"]]:
		var profile: String=pair[0]
		var start: String=pair[1]
		var opened: bool=scene.restart(true,"calm",profile,start)
		_check(opened,"actual_source_adoption_"+start)
		if not opened: continue
		scene.open_menu("Taxi test paused")
		scene.show_state(0.0)
		var source: Dictionary=scene.facade.readback()
		_check(source.named_start==start and source.model_identity.id==profile and source.tick=="0" and source.host_mode=="paused" and source.native_live and source.paused and not source.historical,"exact_actual_zero_tick_source_"+start)
		_check(scene.observed_recorder.recording().metadata.named_start==start,"recorder_uses_actual_apron_name_"+start)
		_check(scene.taxi_navigation.observe(source).state=="empty","fresh_session_has_no_route_"+start)
		readbacks.append(source.duplicate(true))
		var choice: Dictionary=Briefing.apron_choice_for(start)
		_check(choice.named_start==start and choice.model_identity==source.model_identity and choice.wind=="calm","separate_apron_choice_"+start)
		_modal_matrix(scene,start)
		# Live entry gets exactly the same existing pause lifecycle as the menu.
		_check(scene.pause_session(false),"explicit_resume_"+start)
		scene.menu_open=false; scene.menu.hide()
		var facade: RefCounted=scene.facade
		var pause_count: int=facade.pause_attempts.size()
		_check(scene.open_taxi() and scene.paused and facade.pause_attempts.size()==pause_count+1 and facade.pause_attempts.back()==true,"live_entry_ordinary_pause_once_"+start)
		scene.dismiss_taxi()
		_check(scene.open_taxi(),"open_before_explicit_close_"+start)
		var stale: Callable=scene._taxi_callbacks.route_requested
		var old_session: String=scene.adopted_session_id
		_check(scene.close_session() and not scene.taxi_open and not scene.taxi_panel.visible,"explicit_teardown_retires_before_join_"+start)
		var ended: PackedByteArray=var_to_bytes({"source":facade.readback(),"recording":scene.observed_recorder.recording(),"calls":_observer._ledger(scene)})
		stale.call("outbound36",old_session)
		_check(var_to_bytes({"source":facade.readback(),"recording":scene.observed_recorder.recording(),"calls":_observer._ledger(scene)})==ended,"closed_callback_cannot_reassign_history_"+start)
	var navigation: Dictionary=NavigationChecks.run(readbacks)
	_check(navigation.passed and navigation.checks>0 and navigation.failures.is_empty(),"both_actual_apron_navigation_sources")
	_checks+=navigation.checks
	for failure in navigation.failures: _failures.append("navigation:"+str(failure))
	if scene.facade!=null: _check(scene.close_session(),"final_native_join")
	if scene.sound!=null: _check(bool(await scene.sound.shutdown()),"final_audio_join")
	scene.free()
	return {"passed":_failures.is_empty(),"checks":_checks,"failures":_failures.duplicate(),"scope":"Actual apron adoption, complete native/Mapper/recorder/call invariants, manual page progress/lifetime and navigation over two real paused apron sources. Released Raw is synthetic. No taxi movement, rendered readability, flight journey or pilot acceptance."}
