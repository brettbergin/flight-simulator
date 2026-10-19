extends RefCounted
# Original MIT. Actual flight executive/Facade, complete synthetic Raw, observed
# native mutation ledger. No storage object is created and no mapper/native
# lifecycle is overridden. This checks modal signals, not keyboard/pixel QA.
const Scene = preload("res://simulation/flight_scene.gd")
const Facade = preload("res://simulation/session_facade.gd")
const Controller = preload("res://persistence/local_players_controller.gd")

class ObservedAdapter extends RefCounted:
	var native: RefCounted = ClassDB.instantiate("FlightInteractiveSession") as RefCounted
	var entries: Array = []
	func _forward(method: String,args: Array) -> Dictionary:
		var result: Dictionary = native.callv(method,args)
		entries.append({"method":method,"arguments":args.duplicate(true),"reply":result.duplicate(true)})
		return result
	func open_session(root: String,start: String,wind: String,profile: String) -> Dictionary:
		return _forward("open_session",[root,start,wind,profile])
	func submit(command: Dictionary) -> Dictionary:
		return _forward("submit",[command])
	func session_control(command: Dictionary) -> Dictionary:
		return _forward("session_control",[command])
	func step_fixed(count: int) -> Dictionary:
		return _forward("step_fixed",[count])
	func read_state() -> Dictionary:
		return native.call("read_state")
	func close() -> Dictionary:
		return _forward("close",[])

class CountedFacade extends Facade:
	var pause_attempts: Array = []
	var advances: Array = []
	var intent_attempts: Array = []
	func _init(factory: Callable) -> void:
		super(factory)
	func set_paused(value: bool) -> Dictionary:
		pause_attempts.append(value)
		return super.set_paused(value)
	func advance_wall_us(elapsed: int) -> Dictionary:
		advances.append(elapsed)
		return super.advance_wall_us(elapsed)
	func set_axes(axes: Dictionary) -> Dictionary:
		intent_attempts.append({"api":"set_axes","axes":axes.duplicate(true)})
		return super.set_axes(axes)
	func set_pilot_intent(axes: Dictionary,systems: Dictionary) -> Dictionary:
		intent_attempts.append({"api":"set_pilot_intent","axes":axes.duplicate(true),"systems":systems.duplicate(true)})
		return super.set_pilot_intent(axes,systems)

class FixtureScene extends Scene:
	var adapters: Array = []
	var facades: Array = []
	func collect_input_raw(_preset: Dictionary = {}) -> Dictionary:
		return {"keys":[],"mouse_buttons":[],"devices":[]}
	func _observed_adapter() -> RefCounted:
		var adapter: RefCounted = ObservedAdapter.new()
		adapters.append(adapter)
		return adapter
	func _make_facade() -> RefCounted:
		var created: RefCounted = CountedFacade.new(Callable(self,"_observed_adapter"))
		facades.append(created)
		return created
	func _players_storage_allowed() -> bool:
		return true
	func _make_local_players_service() -> RefCounted:
		# Explicit no-service Guest controller; never open the owner's KnownFolder.
		return null

var _retained_scene: Node

func _copy(value: Variant) -> Variant:
	return value.duplicate(true) if value is Dictionary or value is Array else value

func _snapshot(scene: Node) -> PackedByteArray:
	var mapper: Dictionary = {}
	for key in ["_preset","_values","_start","_pins","_edges","_takeover","_configured","_live","_brake_hold","_v2","_held_systems","_system_intents","_system_edges","_pointer_session","_pointer_generation","_pointer_last_token","_pointer_capture","_pointer_begin","_pointer_terminal","_pointer_pending","_pointer_rearm","_pointer_error","_pointer_disabled"]:
		mapper[key] = _copy(scene.mapper.get(key))
	var facade: Dictionary = {}
	for key in ["_command_sequence","_lifecycle_sequence","_pending","_admitted","_pending_systems","_admitted_systems","_previous","_current","_previous_tick","_commands","_events","_pending_commands","_pending_events","_delivered_command","_delivered_event","_complete","_admission","_rejection","_completed","_origin_blocked","_blocked_origin_version"]:
		facade[key] = _copy(scene.facade.get(key))
	var state: Dictionary = {"readback":scene.facade.readback(),"native":scene.facade.get("_bridge").call("read_state"),"mapper":mapper,"facade":facade,
		"recording":scene.observed_recorder.recording(),"recorder_status":scene.observed_status.duplicate(true),"origin":scene.facade.render_origin.read_origin(),
		"selected_pair":scene.player_controller.selected_pair(),"player_epoch":scene.player_controller.current_epoch(),"save_state":scene.player_controller.save_state()}
	for key in ["controls","held_controls","last_submitted","held_systems","pending_systems","brake_hold","takeover_targets","engine_pointer_rearm","engine_pointer_terminal","engine_pointer_look_active","submitted_count","event_count","adopted_session_id","current_wind_profile","selected_profile","active_preset","profile_presets","audio_options","audio_enabled","view_settings","camera_mode","look_angles","camera_distance","camera_ready","forward_view","camera_follow_offset","input_sensitivity","_player_seed","_player_state","_recording_player_context"]:
		state[key] = _copy(scene.get(key))
	if is_instance_valid(scene.camera):
		state.camera_transform = scene.camera.global_transform
		state.camera_fov = scene.camera.fov
	return var_to_bytes(state)

func _ledger(scene: Node) -> PackedByteArray:
	var entries: Array = []
	for facade in scene.facades:
		entries.append({"pause_attempts":facade.pause_attempts.duplicate(),"advances":facade.advances.duplicate(),"intents":facade.intent_attempts.duplicate(true)})
	for adapter in scene.adapters:
		entries.append(adapter.entries.duplicate(true))
	return var_to_bytes(entries)

func run(host: Node) -> Dictionary:
	var previous_mouse: int = Input.mouse_mode
	var scene: Node = FixtureScene.new()
	host.add_child(scene)
	# Missing-module production correctly disables its controller. This labelled
	# no-service routing fixture supplies the actual controller explicitly; it
	# never claims an attached native storage service or saves a Guest row.
	if scene.player_controller == null:
		scene.player_controller = Controller.new()
	scene.set_process(false)
	scene.set_physics_process(false)
	scene.set_process_input(false)
	scene.set_process_unhandled_input(false)
	scene.set_process_unhandled_key_input(false)
	if scene.sound != null:
		scene.sound.set_process(false)
	var initialized: bool = scene.facade != null and scene.mapper != null and scene.player_controller != null
	host.check(initialized,"players_scene_actual_flight_and_guest_controller_initialized")
	if not initialized:
		_retained_scene = scene
		return {"scope":"actual_flight_modal_signals","retained":true}
	scene.dismiss_first_flight()
	host.check(scene.restart(true,"calm","original-interactive-prototype","ground-ready"),"players_scene_actual_legacy_source_started")
	scene.open_menu("Players modal check")
	host.check(scene.pause_session(true) and scene.advance_wall_us(0),"players_scene_settled_ordinary_paused_accounting")
	scene.show_state(0.0)
	host.check(scene.open_players(),"players_scene_actual_end_flight_dialog_opens")
	await host.get_tree().process_frame
	if scene._player_exit.is_empty():
		host.check(false,"players_scene_exit_dialog_present")
		_retained_scene = scene
		return {"scope":"actual_flight_modal_signals","retained":true}
	var dialog: ConfirmationDialog = scene._player_exit.dialog
	host.check(dialog.get_cancel_button().has_focus(),"players_scene_end_flight_defaults_cancel")
	# The strict authority baseline is after ordinary modal opening/settlement.
	# Opening may legitimately retire pointer capture before this point.
	var before: PackedByteArray = _snapshot(scene)
	var calls: PackedByteArray = _ledger(scene)
	var old_confirm: Callable = scene._player_ui.callbacks[dialog.confirmed]
	dialog.canceled.emit()
	host.check(scene._player_exit.is_empty() and scene._player_ui.is_empty(),"players_scene_cancel_retires_actual_registry")
	host.check(_snapshot(scene) == before and _ledger(scene) == calls,"players_scene_cancel_preserves_full_native_mapper_recorder_camera_player_options")
	old_confirm.call()
	host.check(_snapshot(scene) == before and _ledger(scene) == calls,"players_scene_retired_confirm_cannot_close_or_mutate")
	await host.get_tree().process_frame
	host.check(scene.open_players(),"players_scene_second_end_flight_dialog_opens")
	var retained_facade: RefCounted = scene.facade
	var adapter: RefCounted = scene.adapters.back()
	var final_dialog: ConfirmationDialog = scene._player_exit.dialog
	final_dialog.confirmed.emit()
	var deadline: int = Time.get_ticks_msec()+15000
	while (scene.facade != null or not scene._player_audio_retired) and Time.get_ticks_msec() < deadline:
		await host.get_tree().process_frame
	var rb: Dictionary = retained_facade.readback()
	host.check(scene.facade == null and scene.review_joined and rb.host_mode == "closed" and not rb.native_live,"players_scene_confirm_uses_actual_joined_closed_flight")
	var close_count: int = 0
	for entry: Dictionary in adapter.entries:
		if entry.method == "close":
			close_count += 1
	host.check(close_count == 1,"players_scene_confirm_single_actual_native_close")
	host.check(scene._player_audio_retired and scene.sound == null,"players_scene_confirm_retires_actual_audio_before_chooser")
	host.check(scene.player_controller.selected_pair() == null and not scene.player_controller.history_exit_pending(),"players_scene_guest_close_does_not_fabricate_practice")
	var joined: bool = scene.close_session()
	host.check(joined,"players_scene_final_actual_joined_lifecycle")
	if scene.sound != null:
		joined = bool(await scene.sound.shutdown()) and joined
	if joined:
		scene.free()
	else:
		_retained_scene = scene
	Input.mouse_mode = previous_mouse
	return {"scope":"actual_flight_modal_signals","retained":not joined,"native_storage_exercised":false,"ordinary_keyboard_or_pixels":false}
