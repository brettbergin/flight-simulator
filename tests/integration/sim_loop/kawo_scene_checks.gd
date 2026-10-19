extends RefCounted
# Original MIT. Real Scene/Facade/native/renderer, fixed synthetic Raw and no
# storage service. This proves no Players persistence, hardware or manual flight.
const Scene=preload("res://simulation/flight_scene.gd")
const Facade=preload("res://simulation/session_facade.gd")
const Codec=preload("res://replay/observed_archive/codec.gd")
const Participant=preload("res://simulation/origin_participant.gd")
var _retained_scene: Node

class FixtureScene extends Scene:
	func collect_input_raw(_preset: Dictionary={}) -> Dictionary:
		return {"keys":[],"mouse_buttons":[],"devices":[]}
	func _players_storage_allowed() -> bool: return false
	func _make_local_players_service() -> RefCounted: return null

func run(host: Node) -> Dictionary:
	var scene: Node=FixtureScene.new()
	host.add_child(scene)
	scene.set_process(false)
	scene.set_physics_process(false)
	scene.set_process_input(false)
	scene.set_process_unhandled_input(false)
	scene.set_process_unhandled_key_input(false)
	scene.retire_first_flight()
	var failures: Array[String]=[]
	var adoption_diagnostic: Dictionary={}
	var checks: int=0
	var check: Callable=func(ok: bool,name: String):
		if not ok: failures.append(name)
		host.call("check",ok,"kawo_scene_"+name)
	if scene.facade==null:
		check.call(false,"initial_native_available")
		_retained_scene=scene
		return {"checks":1,"failures":failures,"joined":false}
	check.call(scene.pause_session(true),"initial_actual_pause"); checks+=1
	var old: RefCounted=scene.facade
	var baseline: Dictionary=old.readback()
	check.call(not scene.restart(true,"calm",Facade.LEGACY_PROFILE.id,"ground-ready",StringName("kawo-prototype-v1")) and old.readback()==baseline,"wrong_type_preserves_old"); checks+=1
	check.call(not scene.restart(true,"from-west",Facade.LEGACY_PROFILE.id,"ground-ready","kawo-prototype-v1") and old.readback()==baseline,"crossed_wind_preserves_old"); checks+=1
	check.call(not scene.restart(true,"calm",Facade.LEGACY_PROFILE.id,"airborne-prepared","kawo-prototype-v1") and old.readback()==baseline,"unsupported_start_preserves_old"); checks+=1
	var adopted: bool=scene.restart(true,"calm",Facade.LEGACY_PROFILE.id,"ground-ready","kawo-prototype-v1")
	if not adopted:
		# Fixed isolated fixture only: preserve the rejected transaction's actual
		# message before final close changes the scene/facade state.
		var rejected: Dictionary=scene.facade.readback() if scene.facade!=null else {}
		adoption_diagnostic={"scene_status":scene.status,"facade_error":rejected.get("error",null)}
	check.call(adopted,"actual_geographic_adoption"); checks+=1
	if adopted:
		var source: Dictionary=scene.facade.readback()
		check.call(old.readback().host_mode=="closed" and not old.readback().native_live,"old_actual_joined"); checks+=1
		check.call(scene.selected_world=="kawo-prototype-v1" and source.host_mode=="paused" and source.tick=="0" and source.prepared_world_sha256=="b2c53308fdc427900d84b541aff51ba66cbb71bc483fcee0ea16d067dbd15cfb","paused_tick0_source"); checks+=1
		check.call(scene.world_root.get_script()!=null and scene.world_root.get_script()!=Participant and scene.world_root.source_binding().session_id==source.session_id,"custom_origin_script_survives"); checks+=1
		check.call(scene.facade.render_origin.read_origin().valid,"actual_origin_adopted"); checks+=1
		check.call(scene.observed_recorder.recording().contract_version==3,"actual_recorder_version3"); checks+=1
		check.call(not scene.open_taxi(),"no_synthetic_taxi"); checks+=1
		scene.open_landmark_route()
		check.call(not scene.route_open,"no_synthetic_landmarks"); checks+=1
		scene.open_first_flight()
		check.call(scene.circuit_checkbox.disabled,"no_synthetic_circuit"); checks+=1
		scene.retire_first_flight()
		scene.menu_open=false
		scene.menu.hide()
		scene.show_state(0.0)
		check.call(scene.wind_card.is_visible_in_tree() and scene.wind_label.text.contains("Decorative trees") and scene.wind_label.text.contains("not surveyed obstacles") and scene.wind_label.text.contains("Prototype paint: unsurveyed"),"visible_unsurveyed_scenery_notice"); checks+=1
		check.call(scene.facade.readback()==source,"presentation_queries_do_not_advance"); checks+=1
		check.call(scene.flight_map.get("_runway")==34 and scene.flight_map.get("_compiled_runways").size()==2,"compiled_locator_all_runways"); checks+=1
		for expected in [16,11,29,34]:
			scene.flight_map.toggle_runway()
			check.call(scene.flight_map.get("_runway")==expected,"locator_select_"+str(expected)); checks+=1
		scene.observed_recorder.seal("manual")
		var recording: Dictionary=scene.observed_recorder.recording()
		var encoded: Dictionary=Codec.encode(recording)
		check.call(encoded.ok and Codec._exact(Codec.decode(encoded.value).value,recording),"actual_revision3_archive_roundtrip"); checks+=1
		var geographic: RefCounted=scene.facade
		check.call(scene.restart(true,"calm",Facade.LEGACY_PROFILE.id,"ground-ready","original-synthetic"),"actual_return_to_synthetic"); checks+=1
		check.call(not geographic.readback().native_live and geographic.readback().host_mode=="closed","geographic_actual_joined"); checks+=1
		check.call(scene.selected_world=="original-synthetic" and scene.observed_recorder.recording().contract_version==1 and scene.world_root==scene.get("_synthetic_world_root"),"synthetic_source_and_geometry_restored"); checks+=1
	var joined: bool=scene.close_session()
	check.call(joined,"final_actual_join"); checks+=1
	if joined:
		host.remove_child(scene)
		scene.free()
	else: _retained_scene=scene
	return {"checks":checks,"failures":failures,"joined":joined,"adoption_diagnostic":adoption_diagnostic}
