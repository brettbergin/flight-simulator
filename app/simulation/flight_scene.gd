extends "res://interactive/preview.gd"
# Original MIT production-loop scene using the accepted native facade.
# The original preview remains separately runnable; legacy proof flags keep its
# frozen test driver. Ordinary interactive flight uses exactly one facade.
const Facade = preload("res://simulation/session_facade.gd")
const Frames = preload("res://simulation/canonical_frames.gd")
const Participant = preload("res://simulation/origin_participant.gd")
const Mapper = preload("res://input/input_mapper.gd")
const Preset = preload("res://input/input_preset.gd")
const ControlsPanel = preload("res://ui/controls/controls_panel.gd")
const NativeReadings = preload("res://cockpit/instruments/native_readings.gd")
const ScanPanel = preload("res://cockpit/instruments/scan_panel.gd")
const ObservedRecorder = preload("res://replay/observed/recorder.gd")
const ObservedValues = preload("res://replay/observed/values.gd")
const ObservedPanel = preload("res://ui/debrief/observed/panel.gd")
const ArchiveCodec = preload("res://replay/observed_archive/codec.gd")
const ArchiveFiles = preload("res://replay/observed_archive/files.gd")
const WindCue = preload("res://world/wind/wind_cue.gd")
const WindPanel = preload("res://ui/wind/panel.gd")
var wind_draft: String="calm"
var current_wind_profile: String="calm"
var wind_panel: Control
var wind_label: Label
var wind_card: Panel
var windsock_visual: MeshInstance3D
var archive_files: RefCounted=ArchiveFiles.new()
var archive_dialog: FileDialog
var archive_operation: Dictionary={}
var archive_imported: bool=false
var archive_message: String=""
var observed_recorder: RefCounted=ObservedRecorder.new()
var observed_panel: Control
var review_open: bool=false
var observed_status: Dictionary={}
var discard_layer: Control
var discard_message: Label
var discard_cancel: Button
var discard_accept: Button
var pending_discard: Dictionary={}
var initializing_recording: bool=false
var review_joined: bool=true
const LandmarkBoard = preload("res://ui/freeflight/landmark_board.gd")
var landmark_board: Control
var route_open: bool=false
var route_aids_visible: bool=true
var route_view: Dictionary={}
const EngineStatus = preload("res://cockpit/instruments/engine_status.gd")
# These identify only the last fully adopted fresh flight, never a menu draft.
var selected_profile: String="original-interactive-prototype"
var adopted_session_id: String=""
var profile_presets: Dictionary={}
var engine_status: Dictionary={}
var held_systems: Dictionary={}
var pending_systems: Dictionary={}
var profile_button: Button
var shared_readings: Dictionary={}
var scan_panel: Control
var scan_open: bool=false
var mapper: RefCounted
var active_preset: Dictionary={}
var controls_panel: Control
var input_problem: String=""
var input_blocked: bool=false
var takeover_targets: Array=[]
# Runtime IDs never enter a preset. Each observed set belongs to one connection.
var device_connections: Dictionary={}
var selected_slots: Dictionary={}
var wheel_pulses: Array=[]
var connection_generation: int=0
var dispatching_input: bool=false
var controls_selection_backup: Dictionary={}
var facade: RefCounted
var prepared: Dictionary={}
var speed_button: Button
var world_root: Node3D
var light_root: Node3D
var legacy_proof: bool="--smoke" in OS.get_cmdline_user_args() or "--visual-smoke" in OS.get_cmdline_user_args()
var facade_visual: bool="--facade-visual-smoke" in OS.get_cmdline_user_args()

func _ready() -> void:
	if "--facade-checks" in OS.get_cmdline_user_args() and get_parent()==get_tree().root:
		set_process(false)
		var harness: Script=load("res://sim_loop_checks.gd")
		if harness==null or not harness.can_instantiate():
			push_error("Facade checks harness unavailable")
			get_tree().quit(1)
			return
		add_child(harness.new())
		return
	if not legacy_proof:
		for device in Input.get_connected_joypads():
			observe_connection(device,true)
	super._ready()
	if not legacy_proof and "--cockpit-visual-smoke" in OS.get_cmdline_user_args():
		set_process(false)
		set_physics_process(false)
		set_process_input(false)
		set_process_unhandled_input(false)
		set_process_unhandled_key_input(false)
		set_process_shortcut_input(false)
		call_deferred("run_cockpit_visual")
		return
	if not legacy_proof and "--piston-visual-smoke" in OS.get_cmdline_user_args():
		set_process(false)
		set_process_input(false)
		set_process_unhandled_input(false)
		set_process_unhandled_key_input(false)
		call_deferred("run_piston_visual")
		return
	if not legacy_proof and "--wind-visual-smoke" in OS.get_cmdline_user_args():
		set_process(false)
		call_deferred("run_wind_visual")
		return
	if not legacy_proof and "--observed-archive-visual-smoke" in OS.get_cmdline_user_args():
		set_process(false)
		call_deferred("run_archive_visual")
		return
	if not legacy_proof and "--observed-visual-smoke" in OS.get_cmdline_user_args():
		set_process(false)
		call_deferred("run_observed_visual")
		return
	if not legacy_proof and "--landmark-visual-smoke" in OS.get_cmdline_user_args():
		set_process(false)
		call_deferred("run_landmark_visual")
		return
	if not legacy_proof and "--instrument-visual-smoke" in OS.get_cmdline_user_args():
		set_process(false)
		call_deferred("run_instrument_visual")
		return
	if not legacy_proof and facade_visual:
		set_process(false)
		call_deferred("run_facade_visual")
	elif not legacy_proof and "--input-visual-smoke" in OS.get_cmdline_user_args():
		set_process(false)
		call_deferred("run_input_visual")

func make_world() -> void:
	super.make_world()
	if legacy_proof:
		return
	world_root=Node3D.new()
	world_root.name="CanonicalWorld"
	light_root=Node3D.new()
	light_root.name="CanonicalLighting"
	var world_children: Array=get_children()
	add_child(world_root)
	add_child(light_root)
	for child in world_children:
		if child is Node3D and child!=airplane and child!=camera and child!=cockpit.root:
			child.reparent(light_root if child is Light3D else world_root,true)
	windsock_visual=world_root.find_child("SteadyWindsock",true,false) as MeshInstance3D

func close_session() -> bool:
	if legacy_proof:
		return super.close_session()
	if not archive_operation.is_empty(): return false
	render_pose.clear()
	if facade==null:
		bridge=null
		return true
	var result: Dictionary=facade.close()
	# Retain the old prefix when replacement fails, but still label its actual
	# confirmed stop. New-session publications remain held until begin succeeds.
	if initializing_recording and not piston_mode() and not observed_status.is_empty():
		var ended: Dictionary=observed_recorder.observe(result.readback)
		if ended.status!=null: observed_status=ended.status
	else:
		observe_flight(result.readback)
	if result.ok:
		review_joined=true
		facade=null
		bridge=null
	else:
		adopt_result(result)
	return result.ok

func restart(replace_confirmed: bool=false, selected_wind: Variant=null, requested_profile: Variant=null, requested_start: Variant=null) -> bool:
	if legacy_proof:
		return super.restart()
	if not archive_operation.is_empty(): return false
	var next_profile: Variant=selected_profile if requested_profile==null else requested_profile
	var next_start: Variant=named_start if requested_start==null else requested_start
	var requested_wind: Variant=current_wind_profile if selected_wind==null else selected_wind
	if not Facade.valid_profile(next_profile) or typeof(next_start)!=TYPE_STRING:
		status="Invalid fresh profile/start selection; flight unchanged"
		return false
	var model_root: String=flight_model_root(next_profile)
	# Inventory/root/recipe/wind admission runs before old worker destruction.
	var selection_error: String=Facade._selection_error(model_root,next_start,requested_wind,next_profile)
	if not selection_error.is_empty():
		status=selection_error+"; flight unchanged"
		return false
	if recorded_flight_advanced() and not replace_confirmed:
		request_discard("restart",next_start,requested_wind,next_profile)
		return false
	if recorded_flight_advanced() and not review_boundary():
		status="Recorded flight replacement requires a verified paused or joined boundary; flight unchanged"
		return false
	# Keep independent guest presets; never promote a legacy preset implicitly.
	var next_presets: Dictionary=profile_presets.duplicate(true)
	if not active_preset.is_empty(): next_presets[selected_profile]=active_preset.duplicate(true)
	initializing_recording=true
	if not close_session():
		initializing_recording=false
		return fail("Native worker did not join")
	held_systems.clear()
	pending_systems.clear()
	engine_status.clear()
	facade=Facade.new()
	# The inherited view reference never owns a native executive.
	bridge=facade
	var result: Dictionary=facade.start(model_root,next_start,requested_wind,next_profile)
	if not result.ok:
		return restart_failed(result.error)
	adopt_result(result)
	initial={"solved_controls":held_controls.duplicate(true),"accepted_aircraft":snapshot.duplicate(true)}
	controls=held_controls.duplicate(true)
	last_submitted=controls.duplicate(true)
	world_anchor=result.readback.world_anchor.duplicate(true)
	prepared=Frames.anchor(world_anchor.latitude_rad,world_anchor.longitude_rad,world_anchor.ellipsoid_height_m)
	latitude=world_anchor.latitude_rad
	longitude=world_anchor.longitude_rad
	origin_ecef={"x":prepared.ecef[0],"y":prepared.ecef[1],"z":prepared.ecef[2]}
	world_root.transform=Transform3D.IDENTITY
	light_root.transform=Transform3D.IDENTITY
	var raw: Array=result.readback.canonical.anchor_eus_position_m
	airplane.transform=Frames.transform(raw,result.readback.canonical.body_to_anchor_eus)
	cockpit.root.transform=airplane.transform
	for item in [
		{"id":"ownship","node":airplane,"categories":["ownship"]},
		{"id":"cockpit","node":cockpit.root,"categories":["cockpit"]},
		{"id":"camera","node":camera,"categories":["camera"]},
		{"id":"world","node":world_root,"categories":["world"]},
		{"id":"lighting","node":light_root,"categories":["light"]}
	]:
		var node: Node3D=item.node
		node.set_script(null)
		node.set_script(Participant)
		if not node.call("configure",snapshot.session_id,prepared.ecef,prepared.rotation,[float(node.position.x),float(node.position.y),float(node.position.z)],node.basis):
			return restart_failed("Invalid canonical scene participant "+item.id)
		if item.id in ["ownship","cockpit"] and not node.call("set_canonical_pose",result.readback.canonical.ecef_position_m,node.basis):
			return restart_failed("Invalid binary64 ownship origin source")
		var registered: Dictionary=facade.render_origin.register_participant(item.id,node,item.categories)
		if not registered.ok:
			return restart_failed(registered.error)
	if not facade.render_origin.register_participant("nonspatial",null,["spatial_audio","local_particles"]).ok:
		return restart_failed("Required absent origin categories rejected")
	var adopted: Dictionary=facade.render_origin.rebase(prepared.ecef)
	if not adopted.ok:
		return restart_failed(adopted.error)
	camera_ready=false
	look_angles=Vector2.ZERO
	# Configuration cannot run against a live native worker.
	var paused_start: Dictionary=facade.set_paused(true)
	adopt_result(paused_start)
	if not paused_start.ok:
		return restart_failed("Controls initialization could not pause native flight")
	mapper=Mapper.new()
	var next_preset: Dictionary=next_presets.get(next_profile,{}).duplicate(true)
	if next_preset.is_empty():
		next_preset=Mapper.default_preset_v2() if piston_mode() else Mapper.default_preset()
	var configured: Dictionary=configure_mapper(next_preset)
	input_blocked=not configured.ok
	input_problem="" if configured.ok else configured.error
	takeover_targets=[]
	if configured.ok:
		brake_hold=mapper.sample(collect_input_raw(next_preset),0).brake_hold
	submitted_count=0
	event_count=0
	attempt+=1
	status="PAUSED | %s | fresh attempt %d | confirm controls"%[next_start,attempt]
	last_wall_us=Time.get_ticks_usec()
	if piston_mode():
		# ADR011/012 records support only the legacy profile. Clear its history
		# only after explicit replacement and successful cold scene adoption.
		observed_recorder=ObservedRecorder.new()
		observed_status=observed_recorder.status()
	else:
		var begun: Dictionary=observed_recorder.begin(facade.readback(),true)
		if not begun.ok:
			return restart_failed("Flight observation recording unavailable: "+begun.error)
		observed_status=begun.status
	initializing_recording=false
	active_preset=next_preset.duplicate(true)
	profile_presets=next_presets
	profile_presets[next_profile]=active_preset.duplicate(true)
	selected_profile=next_profile
	named_start=next_start
	adopted_session_id=result.readback.session_id
	review_joined=false
	current_wind_profile=requested_wind
	return true

func piston_mode() -> bool:
	# During fresh adoption the verified facade identity precedes scene commit.
	if facade!=null:
		var identity: Variant=facade.readback().get("model_identity")
		if identity!=null: return identity==Facade.PISTON_PROFILE
	return selected_profile==Facade.PISTON_PROFILE.id

func configure_mapper(preset: Dictionary) -> Dictionary:
	if not piston_mode():
		return mapper.configure(preset,held_controls,initial.solved_controls,collect_input_raw(preset))
	var source: Dictionary=facade.readback()
	var systems: Dictionary=EngineStatus.held_systems_from_readback(source)
	if not systems.ok:
		return {"ok":false,"error":systems.error}
	return mapper.configure_v2(preset,held_controls,initial.solved_controls,collect_input_raw(preset),source.model_identity,systems.value)

func suspend_mapper(reason: String) -> void:
	if mapper==null: return
	if not piston_mode():
		mapper.suspend(reason,held_controls)
		return
	var feedback: Dictionary=EngineStatus.held_systems_from_readback(facade.readback())
	var result: Dictionary=mapper.suspend_v2(reason,held_controls,feedback.value if feedback.ok else {})
	pending_systems.clear()
	if not result.ok:
		input_blocked=true
		input_problem=result.error
	else:
		pending_systems=feedback.value.duplicate(true)
		pending_systems["engine.starter"]=false
	# This clears only local intent. Facade owns release admission before resume.

func choose_profile() -> void:
	# Draft selection remains separate from the current adopted profile and preset.
	if not paused or facade==null or facade.readback().host_mode!="paused": return
	if review_open or scan_open or route_open or not archive_operation.is_empty() or not pending_discard.is_empty(): return
	if controls_panel!=null and controls_panel.visible: return
	var draft_profile: String=Facade.LEGACY_PROFILE.id if selected_profile==Facade.PISTON_PROFILE.id else Facade.PISTON_PROFILE.id
	var draft_start: String="piston-cold-ground" if draft_profile==Facade.PISTON_PROFILE.id else "ground-ready"
	var draft_wind: String="calm" if draft_profile==Facade.PISTON_PROFILE.id else current_wind_profile
	request_discard("restart",draft_start,draft_wind,draft_profile)

func adopt_result(result: Dictionary) -> void:
	var was_paused: bool=paused
	var state: Dictionary=result.readback
	observe_flight(state)
	if state.aircraft!=null:
		snapshot=state.aircraft.duplicate(true)
		atmosphere=state.atmosphere.duplicate(true)
		held_controls=state.held_axes.duplicate(true)
		last_aircraft_json=JSON.stringify(snapshot,"",false,true)
		last_atmosphere_json=JSON.stringify(atmosphere,"",false,true)
		var ground: Dictionary=facade.call("_ground_display")
		ground_valid=ground.ground_query_valid
		plane_clearance=ground.plane_clearance_m
	if piston_mode():
		engine_status=EngineStatus.from_readback(state)
		var feedback: Dictionary=EngineStatus.held_systems_from_readback(state)
		held_systems=feedback.value.duplicate(true) if feedback.ok else {}
	paused=state.paused or state.host_mode!="live"
	if paused and mapper!=null and (not was_paused or not result.ok):
		suspend_mapper("Native flight paused or rejected")
	stalled=state.host_mode=="stalled"
	blocked=state.host_mode in ["coverage_blocked","discarded"]
	native_outcome=state.native_outcome if state.native_outcome!=null else "error"
	debt=state.debt_quanta
	submitted_count+=result.applied_commands.size()
	event_count+=result.events.size()
	if not result.ok:
		status=state.error if not state.error.is_empty() else result.error
	elif state.host_mode=="live":
		status="LIVE | %.2fx | original synthetic model"%state.time_scale
	elif state.host_mode=="paused":
		status="PAUSED | P resumes; R fresh attempt"

func pause_session(value: bool) -> bool:
	if legacy_proof:
		return super.pause_session(value)
	if not archive_operation.is_empty(): return false
	if facade==null:
		return false
	if not value:
		if mapper==null:
			status="CONTROLS PAUSED | "+input_problem
			return false
		var ready: Dictionary=mapper.resume_confirmed(collect_input_raw())
		if not ready.ok:
			input_problem=ready.error
			status="CONTROLS PAUSED | "+input_problem
			return false
		if piston_mode() and not pending_systems.is_empty(): pending_systems["engine.starter"]=false
	else:
		input_blocked=true
	var result: Dictionary=facade.set_paused(value)
	adopt_result(result)
	last_wall_us=Time.get_ticks_usec()
	if value and mapper!=null:
		suspend_mapper("Native flight paused")
	if not result.ok:
		input_blocked=true
		input_problem="Native pause/resume rejected; start a fresh attempt"
		if mapper!=null:
			suspend_mapper(input_problem)
		# A failed requested pause cannot leave a worker advancing unnoticed.
		if value:
			adopt_result(facade.close())
		return false
	input_blocked=false
	if not value:
		input_problem=""
	return true

func submit_axes(axes: Dictionary) -> bool:
	if legacy_proof:
		return super.submit_axes(axes)
	var result: Dictionary=facade.set_axes(axes)
	adopt_result(result)
	return result.ok

func advance_wall_us(elapsed_us: int) -> bool:
	if legacy_proof:
		return super.advance_wall_us(elapsed_us)
	var result: Dictionary=facade.advance_wall_us(elapsed_us)
	adopt_result(result)
	return result.ok

func _process(delta: float) -> void:
	if legacy_proof:
		super._process(delta)
		return
	var now: int=Time.get_ticks_usec()
	var elapsed: int=now-last_wall_us
	last_wall_us=now
	process_input_interval(elapsed)
	show_state(clampf(float(elapsed)/1000000.0,0.0,0.25))
	if sound!=null and not snapshot.is_empty():
		if piston_mode():
			sound.call("update_engine_audio",engine_status,flight_speed(),paused,any_wow())
		else:
			sound.call("update_audio",float(held_controls.get("throttle",0)),flight_speed(),paused,any_wow())

func process_input_interval(elapsed: int) -> void:
	if not archive_operation.is_empty(): return
	if facade==null or mapper==null:
		return
	var raw: Dictionary=collect_input_raw(controls_panel.get_draft() if controls_panel!=null and controls_panel.visible else {})
	if not paused and not menu_open and not input_blocked:
		# Preserve overload semantics before touching input filters; never clamp time.
		if elapsed<0 or elapsed>250000:
			adopt_result(facade.advance_wall_us(elapsed))
			suspend_mapper("Host timing requires recovery")
			input_blocked=true
			input_problem="Host timing requires a fresh attempt"
			return
		var sample: Dictionary=mapper.sample(raw,elapsed)
		wheel_pulses.clear()
		if not sample.ok:
			pause_for_input(sample.error)
			return
		controls=sample.axes.duplicate(true)
		brake_hold=sample.brake_hold
		takeover_targets=sample.takeover.duplicate()
		var sampled_facade: RefCounted=facade
		for action in sample.actions:
			dispatching_input=true
			dispatch_input_action(action)
			dispatching_input=false
			if facade!=sampled_facade or paused or menu_open or input_blocked:
				return
		Input.mouse_mode=Input.MOUSE_MODE_CAPTURED if Mapper.action_pressed(active_preset,raw,"look_hold") else Input.MOUSE_MODE_VISIBLE
		if piston_mode():
			pending_systems=sample.systems.duplicate(true)
			var intent: Dictionary=facade.set_pilot_intent(controls,pending_systems)
			adopt_result(intent)
			if intent.ok:
				advance_wall_us(elapsed)
			else:
				pause_for_input("Native pilot intent rejected; release controls before Resume")
		else:
			if submit_axes(controls):
				advance_wall_us(elapsed)
	else:
		wheel_pulses.clear()
		var diagnostic: Dictionary=mapper.sample(raw,0)
		if diagnostic.ok:
			brake_hold=diagnostic.brake_hold
			takeover_targets=diagnostic.takeover.duplicate()
		elif not input_blocked:
			input_problem=diagnostic.error
		adopt_result(facade.advance_wall_us(0))
		if controls_panel!=null and controls_panel.visible:
			controls_panel.update_diagnostics(raw,diagnostic.axes if diagnostic.ok else held_controls,held_controls,controls_diagnostics())

func make_menu(canvas: CanvasLayer) -> void:
	super.make_menu(canvas)
	if legacy_proof:
		return
	var box: VBoxContainer=menu.get_child(0)
	# Calibration replaces the old global sensitivity and implicit pad picker.
	for child in box.get_children():
		if child is HSlider or (child is Label and child!=menu_title and child!=menu_message) or (child is Button and child.text.begins_with("Keyboard / gamepad")):
			box.remove_child(child)
			child.queue_free()
	var controls_button: Button=add_menu_button(box,"Controls and calibration  (F7)",open_controls)
	profile_button=add_menu_button(box,"Aircraft: ready-to-fly prototype",choose_profile)
	profile_button.add_theme_font_size_override("font_size",15)
	var scan_button: Button=add_menu_button(box,"Instrument scan",open_instrument_scan)
	var route_button: Button=add_menu_button(box,"Landmark route",open_landmark_route)
	var review_button: Button=add_menu_button(box,"Flight review",open_observed_review)
	var wind_button: Button=add_menu_button(box,"Wind",open_wind)
	controls_button.text="Controls (F7)"
	controls_button.tooltip_text="Controls and calibration"
	var cockpit_row:=HBoxContainer.new()
	cockpit_row.add_theme_constant_override("separation",8)
	box.add_child(cockpit_row)
	box.move_child(cockpit_row,5)
	for button in [controls_button,scan_button,route_button,review_button,wind_button]:
		button.reparent(cockpit_row)
		button.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		button.add_theme_font_size_override("font_size",15)
	scan_panel=ScanPanel.new()
	canvas.add_child(scan_panel)
	scan_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scan_panel.hide()
	scan_panel.focus_selected.connect(on_instrument_selected)
	scan_panel.dismissed.connect(dismiss_instrument_scan)
	speed_button=add_menu_button(box,"Flight speed: 1x  (F5 / F6)",cycle_flight_scale)
	box.move_child(speed_button,6)
	controls_panel=ControlsPanel.new()
	canvas.add_child(controls_panel)
	controls_panel.hide()
	controls_panel.applied.connect(apply_controls)
	controls_panel.dismissed.connect(dismiss_controls)
	controls_panel.device_selected.connect(select_input_device)
	landmark_board=LandmarkBoard.new()
	canvas.add_child(landmark_board)
	landmark_board.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var configured: Dictionary=landmark_board.configure(flight_map.get("_landmarks").duplicate(true))
	if not configured.ok:
		push_error("Landmark board unavailable: "+configured.error)
	landmark_board.route_requested.connect(choose_landmark_route)
	landmark_board.next_requested.connect(next_landmark_leg)
	landmark_board.stop_requested.connect(stop_landmark_route)
	landmark_board.return_requested.connect(return_to_runway)
	landmark_board.dismissed.connect(dismiss_landmark_route)
	landmark_board.aids_requested.connect(set_route_aids_visible)
	observed_panel=ObservedPanel.new()
	canvas.add_child(observed_panel)
	observed_panel.set_open(false)
	observed_panel.dismissed.connect(dismiss_observed_review)
	observed_panel.save_requested.connect(func():begin_archive_operation("save"))
	observed_panel.open_requested.connect(func():begin_archive_operation("open"))
	observed_panel.current_requested.connect(show_current_review)
	archive_dialog=FileDialog.new()
	archive_dialog.access=FileDialog.ACCESS_FILESYSTEM
	archive_dialog.filters=PackedStringArray(["*.fsreview.json ; Recorded flight review"])
	archive_dialog.use_native_dialog=false
	for flag in [FileDialog.CUSTOMIZATION_OVERWRITE_WARNING,FileDialog.CUSTOMIZATION_DELETE,FileDialog.CUSTOMIZATION_CREATE_FOLDER,FileDialog.CUSTOMIZATION_FAVORITES,FileDialog.CUSTOMIZATION_RECENT]:
		archive_dialog.set_customization_flag_enabled(flag,false)
	# Selected-file guest interchange starts beside the executable; no automatic
	# profile location or Known Folder lookup is introduced by this feature.
	archive_dialog.current_dir=OS.get_executable_path().get_base_dir()
	archive_dialog.file_selected.connect(finish_archive_operation)
	archive_dialog.canceled.connect(cancel_archive_operation)
	observed_panel.add_child(archive_dialog)
	# The pinned dialog checks DELETE customization only for its context menu,
	# not its delete shortcut. Keep file management outside this guest chooser.
	archive_dialog.set_process_shortcut_input(false)
	make_discard_confirmation(canvas)
	wind_panel=WindPanel.new()
	canvas.add_child(wind_panel)
	wind_panel.draft_selected.connect(select_wind_draft)
	wind_panel.start_requested.connect(start_wind_draft)
	wind_panel.dismissed.connect(dismiss_wind)
	wind_card=Panel.new()
	wind_card.mouse_filter=Control.MOUSE_FILTER_IGNORE
	wind_card.clip_contents=true
	var wind_style:=StyleBoxFlat.new()
	wind_style.bg_color=Color(0.02,0.05,0.08,0.96)
	wind_style.set_content_margin_all(6.0)
	wind_style.set_corner_radius_all(4)
	wind_card.add_theme_stylebox_override("panel",wind_style)
	canvas.add_child(wind_card)
	wind_label=Label.new()
	wind_label.mouse_filter=Control.MOUSE_FILTER_IGNORE
	wind_label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	wind_label.clip_text=true
	wind_label.add_theme_font_size_override("font_size",12)
	wind_label.add_theme_color_override("font_color",Color("d1e9ec"))
	wind_label.add_theme_color_override("font_shadow_color",Color.BLACK)
	wind_label.add_theme_constant_override("shadow_offset_x",1)
	wind_label.add_theme_constant_override("shadow_offset_y",1)
	wind_card.add_child(wind_label)
	menu.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	menu.custom_minimum_size=Vector2(560,490)
	layout_flight_menu()

func layout_flight_menu() -> void:
	if menu==null:
		return
	menu.size=menu.get_combined_minimum_size()
	var available: Vector2=get_viewport().get_visible_rect().size
	menu.position=Vector2(maxf(8.0,(available.x-menu.size.x)*0.5),maxf(8.0,(available.y-menu.size.y)*0.5))

func set_flight_scale(value: float) -> bool:
	if facade==null:
		return false
	var now: int=Time.get_ticks_usec()
	if not dispatching_input:
		var settled: Dictionary=facade.advance_wall_us(now-last_wall_us)
		last_wall_us=now
		adopt_result(settled)
		if not settled.ok:
			return false
	var result: Dictionary=facade.set_time_scale(value)
	adopt_result(result)
	if result.ok and speed_button!=null:
		speed_button.text="Flight speed: %.2fx  (F5 / F6)"%value
	return result.ok

func cycle_flight_scale() -> void:
	var scales: Array=[0.25,0.5,1.0,2.0,4.0]
	var current: float=facade.readback().time_scale if facade!=null else 1.0
	var index: int=scales.find(current)
	set_flight_scale(scales[(index+1)%scales.size()])

func _input(event: InputEvent) -> void:
	if legacy_proof:
		return
	if event is InputEventJoypadMotion or event is InputEventJoypadButton:
		var device: int=event.device
		if not device_connections.has(device):
			return
		var connection: Dictionary=device_connections[device]
		if event is InputEventJoypadMotion and event.axis>=0 and event.axis<JOY_AXIS_MAX:
			connection.axes[event.axis]=true
		elif event is InputEventJoypadButton and event.button_index>=0 and event.button_index<JOY_BUTTON_MAX:
			connection.buttons[event.button_index]=true
	elif event is InputEventMouseButton and event.pressed and event.button_index in [4,5,6,7]:
		if not paused and not menu_open and (controls_panel==null or not controls_panel.visible) and not event.button_index in wheel_pulses:
			wheel_pulses.append(event.button_index)

func _unhandled_input(event: InputEvent) -> void:
	if legacy_proof:
		super._unhandled_input(event)
		return
	if not archive_operation.is_empty(): return
	if controls_panel!=null and controls_panel.visible:
		return
	if route_open or review_open or not pending_discard.is_empty():
		return
	if event is InputEventMouseMotion and not paused and not menu_open and Input.mouse_mode==Input.MOUSE_MODE_CAPTURED:
		look_angles.x=clampf(look_angles.x-event.relative.x*0.004,-PI,PI)
		look_angles.y=clampf(look_angles.y-event.relative.y*0.004,-1.2,1.2)
	elif paused and event is InputEventJoypadButton and event.pressed:
		var raw: Dictionary=collect_input_raw()
		if Preset.validate_raw(raw).ok and Mapper.action_pressed(active_preset,raw,"pause_menu"):
			close_menu()

func _unhandled_key_input(event: InputEvent) -> void:
	if legacy_proof:
		super._unhandled_key_input(event)
		return
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	if not archive_operation.is_empty():
		get_viewport().set_input_as_handled()
		return
	if controls_panel!=null and controls_panel.visible:
		return
	if not pending_discard.is_empty():
		if event.physical_keycode==KEY_ESCAPE: cancel_discard()
		get_viewport().set_input_as_handled()
		return
	if wind_panel!=null and wind_panel.visible:
		if event.physical_keycode==KEY_ESCAPE: dismiss_wind()
		get_viewport().set_input_as_handled()
		return
	if review_open:
		if event.physical_keycode==KEY_ESCAPE: dismiss_observed_review()
		get_viewport().set_input_as_handled()
		return
	if route_open:
		if event.physical_keycode==KEY_ESCAPE:
			dismiss_landmark_route()
		get_viewport().set_input_as_handled()
		return
	if event.physical_keycode==KEY_ESCAPE:
		if menu_open:
			close_menu()
		else:
			open_menu("Flight paused")
		get_viewport().set_input_as_handled()
		return
	if paused or menu_open:
		# UI press event, not a flight sample: no axis/filter/edge advancement.
		var raw: Dictionary=collect_input_raw()
		raw.keys=[event.physical_keycode]
		raw.mouse_buttons=[]
		for device in raw.devices:
			for button in device.buttons: button.pressed=false
		if not Preset.validate_raw(raw).ok:
			return
		for action in active_preset.actions:
			if Mapper.action_pressed(active_preset,raw,action.id):
				if action.id=="pause_menu":
					close_menu()
				else:
					dispatch_input_action(action.id)
		get_viewport().set_input_as_handled()

func dispatch_input_action(action: String) -> void:
	if not archive_operation.is_empty(): return
	match action:
		"pause_menu": open_menu("Flight paused")
		"restart": start_flight(named_start)
		"start_ground": start_flight("ground-ready")
		"start_airborne": start_flight("airborne-prepared")
		"view_cycle": set_camera_mode((camera_mode+1)%4)
		"view_cockpit": set_camera_mode(0)
		"view_chase": set_camera_mode(1)
		"view_orbit": set_camera_mode(2)
		"view_panel": set_camera_mode(3)
		"map_toggle":
			map_visible=not map_visible
			flight_map.visible=map_visible
		"runway_toggle":
			if map_visible: flight_map.call("toggle_runway")
		"map_zoom_in":
			if map_visible: flight_map.call("zoom",0.5)
		"map_zoom_out":
			if map_visible: flight_map.call("zoom",2.0)
		"view_zoom_in","view_zoom_out":
			var direction: float=-1.0 if action=="view_zoom_in" else 1.0
			if camera_mode in [0,3]: camera.fov=clampf(camera.fov+direction*3,35,90)
			else: camera_distance=clampf(camera_distance+direction,6,40)
		"recenter": look_angles=Vector2.ZERO
		"help":
			help_visible=not help_visible
			panel.call("set_help_visible",help_visible)
		"overlay":
			panel_visible=not panel_visible
			panel.call("set_panel_visible",panel_visible)
		"controls_panel","controller_select": open_controls()
		"audio":
			audio_enabled=not audio_enabled
			if sound!=null: sound.call("set_enabled",audio_enabled)
		"fullscreen":
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED if DisplayServer.window_get_mode()==DisplayServer.WINDOW_MODE_FULLSCREEN else DisplayServer.WINDOW_MODE_FULLSCREEN)
		"speed_down","speed_up":
			var scales: Array=[0.25,0.5,1.0,2.0,4.0]
			var index: int=scales.find(facade.readback().time_scale)
			set_flight_scale(scales[clampi(index+(-1 if action=="speed_down" else 1),0,scales.size()-1)])

func observe_connection(device: int, connected: bool) -> void:
	if connection_generation==9223372036854775807:
		selected_slots.clear()
		device_connections.clear()
		pause_for_input("Connection generation exhausted; restart application")
		return
	connection_generation+=1
	if connected:
		device_connections[device]={"generation":connection_generation,"axes":{},"buttons":{}}
	else:
		device_connections.erase(device)

func on_joy_connection_changed(device: int, connected: bool) -> void:
	if legacy_proof:
		super.on_joy_connection_changed(device,connected)
		return
	var active: bool=false
	for slot in selected_slots:
		if selected_slots[slot].device==device:
			active=true
	observe_connection(device,connected)
	if active:
		pause_for_input("Selected controller disconnected or changed generation; reselect in Controls")

func on_focus_lost() -> void:
	if legacy_proof:
		super.on_focus_lost()
		return
	Input.mouse_mode=Input.MOUSE_MODE_VISIBLE
	if facade!=null:
		pause_for_input("Window inactive; release controls and confirm Resume")

func pause_for_input(reason: String) -> void:
	if not archive_operation.is_empty(): return
	input_blocked=true
	if facade!=null:
		pause_session(true)
	input_blocked=true
	input_problem=reason
	if mapper!=null:
		suspend_mapper(reason)
	wheel_pulses.clear()
	open_menu("Controls paused")
	status="CONTROLS PAUSED | "+reason

func collect_input_raw(preset: Dictionary={}) -> Dictionary:
	var selected: Dictionary=active_preset if preset.is_empty() else preset
	var key_codes: Dictionary={}
	for binding in selected.get("axes",[]):
		if binding.kind=="key_pair":
			for code in binding.negative+binding.positive: key_codes[code]=true
	for action in selected.get("actions",[]):
		for source in action.sources:
			if source.kind=="physical_keys":
				for code in source.keys: key_codes[code]=true
	for binding in selected.get("systems",[]):
		for source in binding.sources:
			if source.kind=="physical_keys":
				for code in source.keys: key_codes[code]=true
	key_codes[KEY_ESCAPE]=true
	var keys: Array=[]
	for code in key_codes:
		if Input.is_physical_key_pressed(code): keys.append(code)
	keys.sort()
	var mouse: Array=[]
	for button in [1,2,3,8,9]:
		if Input.is_mouse_button_pressed(button): mouse.append(button)
	mouse.append_array(wheel_pulses)
	var devices: Array=[]
	for slot in selected_slots:
		var selection: Dictionary=selected_slots[slot]
		if not device_connections.has(selection.device):
			continue
		var connection: Dictionary=device_connections[selection.device]
		if connection.generation!=selection.generation:
			continue
		var axes: Array=[]
		for index in connection.axes:
			axes.append({"index":index,"value":Input.get_joy_axis(selection.device,index)})
		var buttons: Array=[]
		for index in connection.buttons:
			buttons.append({"index":index,"pressed":Input.is_joy_button_pressed(selection.device,index)})
		devices.append({"slot":slot,"generation":connection.generation,"axes":axes,"buttons":buttons})
	return {"keys":keys,"mouse_buttons":mouse,"devices":devices}

func controls_diagnostics() -> Dictionary:
	var connected: Array=[]
	for device in Input.get_connected_joypads():
		connected.append({"id":device,"name":Input.get_joy_name(device),"guid":Input.get_joy_guid(device)})
	var info: Dictionary={"error":input_problem,"takeover":takeover_targets.duplicate(),"brake_hold":brake_hold,"connected_devices":connected,"transient":true}
	if piston_mode():
		info.profile=Facade.PISTON_PROFILE.duplicate(true)
		info.held_systems=held_systems.duplicate(true)
		info.pending_systems=pending_systems.duplicate(true)
	return info

func select_input_device(slot: String, device: int) -> void:
	if not archive_operation.is_empty(): return
	if not paused or facade==null or facade.readback().host_mode!="paused":
		return
	if not device_connections.has(device):
		input_problem="Device unavailable; explicitly reselect a connected source"
		return
	selected_slots[slot]={"device":device,"generation":device_connections[device].generation}

func open_controls() -> void:
	if not archive_operation.is_empty(): return
	if controls_panel==null or facade==null:
		return
	if not paused and not pause_session(true):
		return
	if facade.readback().host_mode!="paused":
		return
	menu_open=true
	menu.hide()
	Input.mouse_mode=Input.MOUSE_MODE_VISIBLE
	wheel_pulses.clear()
	controls_selection_backup=selected_slots.duplicate(true)
	if piston_mode():
		controls_panel.open_v2(active_preset,collect_input_raw(),held_controls,initial.solved_controls,Facade.PISTON_PROFILE,held_systems)
	else:
		controls_panel.open(active_preset,collect_input_raw(),held_controls,initial.solved_controls)
	controls_panel.update_diagnostics(collect_input_raw(),held_controls,held_controls,controls_diagnostics())

func open_wind() -> void:
	if legacy_proof or wind_panel==null or facade==null or not archive_operation.is_empty() or not pending_discard.is_empty(): return
	if review_open or scan_open or route_open or (controls_panel!=null and controls_panel.visible): return
	if not review_boundary():
		status="Pause the flight before choosing a wind draft"
		return
	menu_open=true
	menu.hide()
	Input.mouse_mode=Input.MOUSE_MODE_VISIBLE
	wind_panel.open(wind_draft,current_wind_profile,WindCue.from_readback(facade.readback()),review_boundary())

func select_wind_draft(value: Variant) -> void:
	if not Facade.valid_wind_profile(value) or not archive_operation.is_empty() or not pending_discard.is_empty(): return
	wind_draft=value

func start_wind_draft(start: String) -> void:
	if wind_panel==null or not wind_panel.visible: return
	if selected_profile==Facade.PISTON_PROFILE.id:
		if start!="ground-ready" and start!="piston-cold-ground":
			status="Cold piston has no airborne start; current flight retained"
			return
		start="piston-cold-ground"
	request_discard("restart",start,wind_draft,selected_profile)

func dismiss_wind() -> void:
	if wind_panel==null or not wind_panel.visible or not pending_discard.is_empty(): return
	wind_panel.hide()
	open_menu("Wind draft retained · current flight paused")
	resume_button.grab_focus()
	show_state(0)

func update_wind_presentation(readback: Dictionary) -> void:
	var cue: Dictionary=WindCue.from_readback(readback)
	# A newly opened worker is not the current scene until setup and recording
	# adoption succeed. Failed replacement cannot present its wind as current.
	if cue.state not in ["empty","invalid"] and (adopted_session_id.is_empty() or cue.session_id!=adopted_session_id):
		cue=WindCue.from_readback({})
	if wind_label!=null:
		wind_label.text="SYNTHETIC STEADY WIND / NATIVE TRUTH\n"+WindPanel.describe(cue)
		# Reserve the lower cockpit for its actual instrument faces. Wrapping
		# prevents a long wind description from growing over the heading dial.
		var available: Vector2=get_viewport().get_visible_rect().size
		# Manual bounded geometry avoids the first-frame wrapped-container
		# minimum-size race; no deferred sort can cover the instrument panel.
		wind_card.size=Vector2(minf(300.0,available.x*0.31),92.0)
		wind_label.position=Vector2(6,6)
		wind_label.size=wind_card.size-Vector2(12,12)
		var stopped: bool=readback.get("host_mode") in ["coverage_blocked","stalled","discarded","closed"] or readback.get("native_outcome") in ["discarded","error","coverage_blocked"]
		wind_card.position=Vector2(16,92.0+(58.0 if piston_mode() else 0.0)+(32.0 if stopped else 0.0))
		wind_card.visible=not menu_open and camera_mode!=3
	if wind_panel!=null and wind_panel.visible:
		wind_panel.set_context(wind_draft,current_wind_profile,cue,review_boundary() and archive_operation.is_empty() and pending_discard.is_empty())
	flight_map.call("set_wind_cue",cue)
	if windsock_visual==null: return
	windsock_visual.visible=cue.state in ["live","paused"]
	if not windsock_visual.visible: return
	if cue.speed_mps==0.0:
		windsock_visual.position=Vector3(-52,5.8,80)
		windsock_visual.basis=Basis(Vector3.FORWARD,deg_to_rad(8.0))
		return
	var flow: Array=cue.wind_toward_airfield_eus_mps
	var largest: float=maxf(absf(flow[0]),absf(flow[2]))
	var direction: Vector3=Vector3(flow[0]/largest,0.0,flow[2]/largest).normalized()
	# Cylinder mouth is +Y, its downstream narrow end is -Y.
	var upstream: Vector3=-direction
	var across: Vector3=Vector3.UP.cross(upstream).normalized()
	windsock_visual.basis=Basis(across,upstream,across.cross(upstream))
	windsock_visual.position=Vector3(-52,6.8,80)+direction

func apply_controls(preset: Dictionary) -> void:
	if not archive_operation.is_empty(): return
	if facade==null or mapper==null or facade.readback().host_mode!="paused":
		return
	var applied: Dictionary=configure_mapper(preset)
	if not applied.ok:
		input_problem=applied.error
		controls_panel.update_diagnostics(collect_input_raw(),held_controls,held_controls,controls_diagnostics())
		return
	active_preset=preset.duplicate(true)
	profile_presets[selected_profile]=active_preset.duplicate(true)
	controls_selection_backup.clear()
	input_blocked=false
	input_problem="Preset applied; release centered controls and confirm Resume"
	brake_hold=mapper.sample(collect_input_raw(),0).brake_hold
	controls_panel.hide()
	open_menu("Controls applied · guest preset")

func dismiss_controls() -> void:
	if not archive_operation.is_empty(): return
	selected_slots=controls_selection_backup.duplicate(true)
	controls_selection_backup.clear()
	controls_panel.hide()
	open_menu("Flight paused")

func select_controller() -> void:
	if legacy_proof: super.select_controller()
	else: open_controls()

func start_flight(start: String) -> void:
	if legacy_proof:
		super.start_flight(start)
		return
	if selected_profile==Facade.PISTON_PROFILE.id:
		if start=="airborne-prepared":
			status="This piston prototype supports a cold ground start; the current session is retained"
			return
		if start=="ground-ready": start="piston-cold-ground"
	request_discard("restart",start,wind_draft,selected_profile)

func perform_start(start: String, selected_wind: Variant=null, requested_profile: Variant=null) -> void:
	if not archive_operation.is_empty(): return
	var next_profile: Variant=selected_profile if requested_profile==null else requested_profile
	var profile_changed: bool=next_profile!=selected_profile
	# restart validates before close and commits selection only after adoption.
	if restart(true,selected_wind,next_profile,start):
		if wind_panel!=null: wind_panel.hide()
		if controls_panel!=null: controls_panel.hide()
		if observed_panel!=null: observed_panel.set_open(false)
		review_open=false
		clear_imported_review()
		open_menu("Fresh flight · confirm controls")
		# A new profile requires an explicit paused Controls/Resume decision.
		if not profile_changed: close_menu()
	else:
		open_menu("Restart failed · recorded flight retained")

func update_canonical_scene_sources() -> void:
	var visual_ecef: Variant=facade.call("_visual_ecef")
	if visual_ecef==null:
		return
	airplane.call("set_canonical_pose",visual_ecef,airplane.basis)
	cockpit.root.call("set_canonical_pose",visual_ecef,cockpit.root.basis)
	# Camera geometry is reconstructed from the same canonical aircraft point
	# plus the current visual offset, never accumulated rebase displacement.
	var offset: Vector3=camera.position-airplane.position
	var r: Array=prepared.rotation
	var camera_ecef: Array=[]
	for axis_index in 3:
		camera_ecef.append(float(visual_ecef[axis_index])+float(r[axis_index])*float(offset.x)+float(r[3+axis_index])*float(offset.y)+float(r[6+axis_index])*float(offset.z))
	camera.call("set_canonical_pose",camera_ecef,camera.basis)

func suppress_geometry() -> void:
	for node in [airplane,world_root,light_root]:
		if node!=null:
			node.hide()
	if cockpit.has("root"):
		cockpit.root.hide()

func show_state(seconds: float=0.0) -> void:
	if legacy_proof:
		super.show_state(seconds)
		return
	if facade==null:
		return
	layout_flight_menu()
	var map_top: float=124.0 if snapshot.is_empty() or blocked or stalled or native_outcome in ["discarded","error","coverage_blocked"] else 92.0
	if piston_mode():
		map_top+=58.0
	flight_map.size=Vector2(minf(420,get_viewport().get_visible_rect().size.x*0.42),minf(500,get_viewport().get_visible_rect().size.y-map_top-14))
	flight_map.position=Vector2(get_viewport().get_visible_rect().size.x-flight_map.size.x-14,map_top)
	var current: Dictionary=facade.readback()
	update_wind_presentation(current)
	if snapshot.is_empty() or current.aircraft==null or current.canonical==null:
		suppress_geometry()
		if panel != null:
			var fault_info: Dictionary={"status":status,"outcome":"error","blocked":blocked,"stalled":stalled,"paused":paused,"input_name":active_preset.get("name","Controls")}
			fault_info.blocked=true
			fault_info.paused=true
			publish_readings(current,fault_info)
			flight_map.call("set_state",snapshot,Vector3.ZERO,Basis.IDENTITY,fault_info)
		return
	var truth: Dictionary=current
	var canonical: Dictionary=truth.canonical
	var native_basis: Basis=Frames.transform([0.0,0.0,0.0],canonical.body_to_anchor_eus).basis
	var raw: Array=canonical.anchor_eus_position_m
	var native_position:=Vector3(raw[0],raw[1],raw[2])
	var rendered: Dictionary=facade.visual_pose()
	if not rendered.valid:
		airplane.hide()
		cockpit.root.hide()
		world_root.hide()
		light_root.hide()
		status="PRESENTATION PAUSED | "+rendered.error+" | R resets"
		var fault_info: Dictionary={"status":status,"outcome":native_outcome,"historical":current.historical,"blocked":true,"stalled":stalled,"paused":true,"input_name":active_preset.get("name","Controls"),"clearance_m":plane_clearance,"ground_valid":ground_valid}
		publish_readings(current,fault_info)
		flight_map.call("set_state",snapshot,native_position,native_basis,fault_info)
		return
	world_root.show()
	light_root.show()
	var presentation: Transform3D=rendered.transform
	var origin: Dictionary=facade.render_origin.read_origin()
	var floor_point: Array=Frames.project(prepared.ecef,origin.committed.origin_ecef_m,prepared.rotation)
	var camera_floor: float=float(floor_point[1])+0.35
	var basis: Basis=presentation.basis
	airplane.transform=presentation
	cockpit.root.transform=airplane.transform
	cockpit.root.visible=camera_mode in [0,3]
	cockpit_builder.call("update_controls",held_controls)
	for contact in snapshot.contacts:
		if gears.has(contact.id):
			var point: Dictionary = contact.point_body_m
			gears[contact.id].position=Vector3(float(point.y),-float(point.z),-float(point.x))
	airplane.visible=camera_mode not in [0,3]
	var target_position: Vector3
	var look_target: Vector3
	var up: Vector3 = Vector3.UP
	if camera_mode in [0,3]:
		var eye: Vector3=cockpit.eye
		target_position=airplane.position+basis*eye
		var base_direction: Vector3=(cockpit.panel_focus-eye).normalized() if camera_mode==3 else Vector3(0,-0.268,-1).normalized()
		var gaze: Basis=Basis(Vector3.UP,-look_angles.x)*Basis(Vector3.RIGHT,look_angles.y)
		look_target=target_position+basis*(gaze*base_direction)*60
		up=basis.y
	elif camera_mode==1:
		target_position=airplane.position+basis*Vector3(sin(look_angles.x)*camera_distance,3.5+look_angles.y*5,cos(look_angles.x)*camera_distance)
		look_target=airplane.position+basis*Vector3(0,0.5,-4)
	else:
		target_position=airplane.position+Vector3(sin(look_angles.x)*camera_distance,(0.25+sin(look_angles.y))*camera_distance,cos(look_angles.x)*camera_distance)
		target_position.y=maxf(target_position.y,camera_floor)
		look_target=airplane.position+Vector3.UP*0.4
	var desired_offset: Vector3=target_position-airplane.position
	if camera_mode in [0,3] or not camera_ready or paused:
		camera_follow_offset=desired_offset
	else:
		# Ease only the view offset; translation follows the same rendered pose.
		# Diagnostic/repeated show_state(0) calls cannot advance the camera filter.
		camera_follow_offset=camera_follow_offset.lerp(desired_offset,1.0-exp(-9.0*clampf(seconds,0.0,0.25)))
	camera.position=airplane.position+camera_follow_offset
	if camera_mode==2:
		camera.position.y=maxf(camera.position.y,camera_floor)
	camera_ready=true
	camera.look_at(look_target,up)
	if propeller!=null and not paused:
		if piston_mode():
			var shaft: Dictionary=engine_status.get("readings",{}).get("propeller.angular_speed",{})
			if engine_status.get("state")=="live" and shaft.get("valid")==true:
				propeller.rotate_z(clampf(seconds,0.0,0.25)*float(shaft.value))
		else:
			propeller.rotate_z(clampf(seconds,0.0,0.25)*(25+float(held_controls.throttle)*65))
	var view_names: Array[String]=["COCKPIT","CHASE","ORBIT","PANEL"]
	var input_name: String=active_preset.get("name","Controls")+" / guest"
	if not takeover_targets.is_empty():
		input_name+=" / match "+", ".join(takeover_targets)
	if not input_problem.is_empty():
		input_name+=" / "+input_problem
	var display_info: Dictionary={"status":status,"outcome":native_outcome,"historical":current.historical,"blocked":blocked,"stalled":stalled,"paused":paused,"brake_hold":brake_hold,"view_name":view_names[camera_mode],"clearance_m":plane_clearance,"ground_valid":ground_valid,"input_name":input_name,"input_label":"CONTROLS","audio_enabled":audio_enabled}
	publish_readings(current,display_info)
	flight_map.call("set_state",snapshot,native_position,native_basis,display_info)
	update_canonical_scene_sources()

func run_facade_visual() -> void:
	failures=[]
	check(set_flight_scale(0.5),"facade_visual_paused_half_speed")
	check(set_flight_scale(1.0),"facade_visual_paused_normal_speed")
	await save_view("facade-view-menu")
	menu_open=false
	menu.hide()
	check(pause_session(false),"facade_visual_resume")
	var captured_session: String=snapshot.session_id
	var source_before: String=facade.readback().prepared_world_sha256
	for mode in [0,1,2,3]:
		set_camera_mode(mode)
		controls.throttle=0.0
		check(submit_axes(controls),"facade_visual_intent")
		for interval in [5000,11000,17000,23000]:
			check(advance_wall_us(interval),"facade_visual_actual_advance")
			show_state(float(interval)/1000000.0)
		await save_view("facade-view-"+str(mode))
	check(pause_session(true),"facade_visual_pause")
	var truth: Dictionary=facade.readback()
	var before: Dictionary=truth.duplicate(true)
	update_canonical_scene_sources()
	var origin: Dictionary=facade.render_origin.rebase(truth.canonical.ecef_position_m)
	check(origin.ok,"facade_visual_explicit_origin")
	set_camera_mode(2)
	await save_view("facade-view-rebased")
	var after: Dictionary=facade.readback()
	check(before==after and captured_session==snapshot.session_id and source_before==after.prepared_world_sha256,"facade_visual_origin_does_not_mutate_native_truth")
	var close_result: Dictionary=facade.close()
	check(close_result.ok,"facade_visual_worker_joined")
	facade=null
	bridge=null
	if sound!=null:
		check(bool(await sound.call("shutdown")),"facade_visual_audio_retired")
	evidence["facade_visual"]={"session_id":captured_session,"native_ticks":truth.tick,"origin_version":origin.origin.committed.version if origin.ok else null,"scope":"Short actual facade/controller viewport fixture; no pilot or full-game performance qualification"}
	evidence["passed"]=failures.is_empty()
	evidence["failures"]=failures
	var file:=FileAccess.open(output_directory().path_join("facade-visual-receipt.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify(evidence,"\t",false,true))
	file.close()
	print("FACADE_VISUAL_SMOKE ",JSON.stringify({"passed":failures.is_empty(),"failures":failures}))
	get_tree().quit(0 if failures.is_empty() else 1)

func run_input_visual() -> void:
	# Short actual viewport/controller fixture; gestures/devices remain synthetic.
	failures=[]
	var original: Dictionary=active_preset.duplicate(true)
	var native_before: Dictionary=facade.readback()
	get_window().size=Vector2i(960,540)
	await get_tree().process_frame
	open_controls()
	process_input_interval(0)
	await save_view("controls-960")
	var viewport: Rect2=get_viewport().get_visible_rect()
	check(controls_panel.visible and viewport.encloses(controls_panel.get_global_rect()),"controls_actual_minimum_panel_inside_viewport")
	for button in [controls_panel._apply_button]:
		check(viewport.encloses(button.get_global_rect()),"controls_actual_minimum_apply_visible")
	check(facade.readback().tick==native_before.tick and facade.readback().held_axes==native_before.held_axes,"controls_open_does_not_change_native_tick_or_axes")
	controls_panel._learn({"mode":"key","target":"roll","side":"positive"})
	controls_panel.update_diagnostics({"keys":[],"mouse_buttons":[],"devices":[]},held_controls,held_controls,controls_diagnostics())
	var learned:=InputEventKey.new()
	learned.pressed=true
	learned.physical_keycode=KEY_L
	controls_panel._input(learned)
	var draft: Dictionary=controls_panel.get_draft()
	var learned_axis: Dictionary={}
	for axis in draft.axes:
		if axis.target=="roll": learned_axis=axis
	check(learned_axis.positive==[KEY_L] and active_preset==original,"controls_actual_learn_changes_draft_only")
	controls_panel._apply()
	check(active_preset==draft and menu_open and paused and not controls_panel.visible,"controls_actual_apply_coordinator_ack_keeps_native_paused")
	check(facade.readback().tick==native_before.tick and facade.readback().held_axes==native_before.held_axes and brake_hold,"controls_actual_apply_preserves_ground_brake_latch_and_native_truth")
	get_window().size=Vector2i(1280,720)
	await get_tree().process_frame
	open_controls()
	process_input_interval(0)
	await save_view("controls-1280-remapped")
	var export_path: String=output_directory().path_join("controls-visual-preset.json")
	controls_panel._save_dialog=true
	controls_panel._file_selected(export_path)
	var exported: Dictionary=Preset.decode(FileAccess.get_file_as_bytes(export_path))
	check(exported.ok and exported.value==active_preset,"controls_actual_selected_path_export_roundtrip")
	controls_panel._defaults()
	controls_panel._save_dialog=false
	controls_panel._file_selected(export_path)
	check(controls_panel.get_draft()==active_preset,"controls_actual_load_updates_draft_without_apply")
	var malformed: Dictionary=controls_panel.get_draft()
	for axis in malformed.axes:
		if axis.target=="roll":
			axis.clear()
			axis.merge({"target":"roll","kind":"fixed","value":2.0})
	controls_panel._draft=malformed
	controls_panel._rebuild()
	check(controls_panel._apply_button.disabled,"controls_actual_invalid_draft_disables_apply")
	controls_panel._apply()
	check(active_preset==draft and facade.readback().tick==native_before.tick,"controls_actual_invalid_apply_preserves_active_and_native")
	await save_view("controls-invalid")
	controls_panel._cancel()
	check(menu_open and paused and not controls_panel.visible and active_preset==draft,"controls_actual_cancel_returns_to_paused_flight")
	on_focus_lost()
	process_input_interval(8334)
	check(paused and facade.readback().tick==native_before.tick and facade.readback().held_axes==native_before.held_axes,"controls_actual_focus_pause_before_next_tick")
	await save_view("controls-paused-menu")
	var closing: Dictionary=facade.close()
	check(closing.ok,"controls_actual_visual_worker_joined")
	facade=null
	bridge=null
	if sound!=null: check(bool(await sound.call("shutdown")),"controls_actual_visual_audio_retired")
	var report: Dictionary={"schema_version":1,"passed":failures.is_empty(),"failures":failures,"scope":"Short actual Windows Controls viewport/preset/native fixture; synthetic key Learn and focus; no human or gamepad/yoke/pedal qualification","windows":[[960,540],[1280,720]],"held_axes":native_before.held_axes,"native_tick":native_before.tick,"preset":draft.name}
	var receipt:=FileAccess.open(output_directory().path_join("controls-visual-receipt.json"),FileAccess.WRITE)
	receipt.store_string(JSON.stringify(report,"  "))
	receipt.close()
	print("CONTROLS_VISUAL_SMOKE ",JSON.stringify(report))
	get_tree().quit(0 if failures.is_empty() else 1)

# Original MIT view-only instrument routing over accepted native readback.
func publish_landmark_route(readback: Dictionary, info: Dictionary={}) -> void:
	if landmark_board==null:
		return
	var usable: bool=readback.get("historical")==true or (not info.get("blocked",false) and not info.get("stalled",false))
	landmark_board.set_aids_visible(route_aids_visible)
	route_view=landmark_board.observe(readback if usable else null)
	if route_open and not route_view.available:
		route_open=false
		landmark_board.set_open(false)
		menu.show()
		menu_message.text="Current landmark guidance unavailable. Flight remains paused."
	landmark_board.z_index=2 if route_open else -1 if menu_open else 0
	flight_map.call("set_route",route_view if route_aids_visible else {})

func open_landmark_route() -> void:
	if legacy_proof or facade==null or landmark_board==null:
		return
	if controls_panel!=null and controls_panel.visible:
		return
	if not paused and not pause_session(true):
		return
	var source: Dictionary=facade.readback()
	if source.host_mode!="paused":
		return
	scan_open=false
	menu_open=true
	route_open=true
	menu.hide()
	Input.mouse_mode=Input.MOUSE_MODE_VISIBLE
	publish_landmark_route(source)
	landmark_board.set_open(route_open)

func _route_edit_source() -> Dictionary:
	if not route_open or not paused or facade==null or landmark_board==null:
		return {}
	var source: Dictionary=facade.readback()
	return source if source.host_mode=="paused" else {}

func choose_landmark_route(indices: Array) -> void:
	var source: Dictionary=_route_edit_source()
	if source.is_empty():
		return
	var result: Dictionary=landmark_board.choose(indices,source)
	if result.ok:
		dismiss_landmark_route()

func next_landmark_leg() -> void:
	var source: Dictionary=_route_edit_source()
	if source.is_empty():
		return
	if landmark_board.next(source).ok:
		publish_landmark_route(source)

func stop_landmark_route() -> void:
	var source: Dictionary=_route_edit_source()
	if source.is_empty():
		return
	if landmark_board.stop(source).ok:
		dismiss_landmark_route()

func return_to_runway(runway: int) -> void:
	var source: Dictionary=_route_edit_source()
	if source.is_empty():
		return
	if landmark_board.choose_return(runway,source).ok:
		flight_map.call("select_runway",runway)
		dismiss_landmark_route()

func set_route_aids_visible(value: bool) -> void:
	if landmark_board==null:
		return
	route_aids_visible=value
	landmark_board.set_aids_visible(value)
	if facade!=null:
		publish_landmark_route(facade.readback())

func dismiss_landmark_route() -> void:
	if legacy_proof or not paused or landmark_board==null:
		return
	route_open=false
	landmark_board.set_open(false)
	menu.show()
	resume_button.grab_focus()
	show_state(0)

func publish_readings(readback: Dictionary, info: Dictionary) -> void:
	shared_readings=NativeReadings.from_readback(readback)
	publish_landmark_route(readback,info)
	if piston_mode():
		engine_status=EngineStatus.from_readback(readback)
		info.engine_status=engine_status.duplicate(true)
	var source: Dictionary=readback.aircraft if readback.get("aircraft") is Dictionary else {}
	var held: Dictionary=readback.held_axes if readback.get("held_axes") is Dictionary else {}
	panel.call("set_native_readings",shared_readings,source,held,info)
	cockpit_panel.call("set_native_readings",shared_readings,source,held,info)
	if scan_panel!=null:
		var scan_info: Dictionary={"view_name":str(info.get("view_name",["COCKPIT","CHASE","ORBIT","PANEL"][camera_mode])).left(128),"paused":shared_readings.state=="paused","historical":shared_readings.state=="historical","status":str(info.get("status",status)).left(1024)}
		scan_panel.call("set_readings",shared_readings,scan_info)
		scan_panel.visible=scan_open or scan_panel.call("focused")!=null
		# Full-rect scan UI captures clicks only when its paused selection screen
		# is open. The ordinary menu and Resume remain accessible otherwise.
		scan_panel.mouse_filter=Control.MOUSE_FILTER_PASS if scan_open and shared_readings.state=="paused" else Control.MOUSE_FILTER_IGNORE
		scan_panel.z_index=-1 if menu_open and not scan_open else 1

func open_instrument_scan() -> void:
	# Selection belongs to an already paused menu. Never pauses native flight,
	# primes mapper edges, suppresses mouse bindings or changes the prior camera.
	if legacy_proof or facade==null or not paused or facade.readback().host_mode!="paused":
		return
	if controls_panel!=null and controls_panel.visible:
		return
	scan_open=true
	menu_open=true
	menu.hide()
	Input.mouse_mode=Input.MOUSE_MODE_VISIBLE
	show_state(0)

func dismiss_instrument_scan() -> void:
	if legacy_proof or not paused:
		return
	scan_open=false
	menu.show()
	resume_button.grab_focus()
	show_state(0)

func on_instrument_selected(_instrument: String) -> void:
	# The selected dial remains alongside flight after explicit Resume through
	# the existing released-control/native-acceptance gate.
	dismiss_instrument_scan()

func open_menu(title: String="Flight paused") -> void:
	if not archive_operation.is_empty(): return
	if not legacy_proof:
		if review_open: return
		if not pending_discard.is_empty(): return
		scan_open=false
		route_open=false
		if landmark_board!=null:
			landmark_board.set_open(false)
	super.open_menu(title)
	if not legacy_proof and profile_button!=null:
		profile_button.text="Aircraft: cold piston prototype  ·  switch" if selected_profile==Facade.PISTON_PROFILE.id else "Aircraft: ready-to-fly prototype  ·  switch"
		if piston_mode():
			menu_message.text="Original piston prototype · idealized starter supply\nStart: brakes held, mixture rich, ignition both, hold starter.\nUse your engine bindings in Controls (F7). Release starter after firing.\nNative shaft RPM / combustion / switches are shown below.\nThis is an engineering interaction; no C172 procedure is claimed."

func close_menu() -> void:
	if not archive_operation.is_empty(): return
	if not legacy_proof and not pending_discard.is_empty():
		cancel_discard()
		return
	if not legacy_proof and wind_panel!=null and wind_panel.visible:
		dismiss_wind()
		return
	if not legacy_proof and review_open:
		dismiss_observed_review()
		return
	if not legacy_proof and route_open:
		dismiss_landmark_route()
		return
	if not legacy_proof and scan_open:
		# Escape/P returns to the menu first. Only the ordinary Resume action
		# performs the existing native/mapper lifecycle operation.
		dismiss_instrument_scan()
		return
	super.close_menu()

func restart_failed(message: String) -> bool:
	if facade!=null:
		var stopped: Dictionary=facade.close()
		if not stopped.ok: message+="; failed setup worker join unconfirmed"
	initializing_recording=false
	return fail(message)

func flight_model_root(profile_id: Variant=null) -> String:
	var profile: Variant=selected_profile if profile_id==null else profile_id
	var folder: String="piston-models" if profile==Facade.PISTON_PROFILE.id else "models"
	return ProjectSettings.globalize_path("res://"+folder) if OS.has_feature("editor") else OS.get_executable_path().get_base_dir().path_join(folder)

func observe_flight(readback: Dictionary) -> void:
	if legacy_proof or initializing_recording or piston_mode() or observed_status.is_empty(): return
	var result: Dictionary=observed_recorder.observe(readback)
	if result.status!=null: observed_status=result.status

func recorded_flight_advanced() -> bool:
	return not observed_status.is_empty() and observed_status.state!="empty" and observed_status.first_tick!=observed_status.last_observed_tick

func review_boundary() -> bool:
	if facade==null: return review_joined
	var state: Dictionary=facade.readback()
	return (state.host_mode=="paused" and state.native_live and state.paused and not state.historical) or (state.host_mode=="closed" and not state.native_live and review_joined)

func ensure_review_boundary() -> bool:
	if review_boundary(): return true
	if facade==null: return false
	var state: Dictionary=facade.readback()
	if state.host_mode=="live":
		return pause_session(true) and review_boundary()
	if state.host_mode in ["closed","stalled","coverage_blocked","discarded"]:
		var result: Dictionary=facade.close()
		adopt_result(result)
		review_joined=result.ok and not result.readback.native_live
		return review_joined
	return false

func open_observed_review() -> void:
	if legacy_proof or observed_panel==null or not pending_discard.is_empty() or not archive_operation.is_empty(): return
	if controls_panel!=null and controls_panel.visible: return
	if not ensure_review_boundary():
		status="Review requires a verified pause or joined stop"
		return
	var record: Variant=observed_recorder.recording()
	if not observed_panel.set_recording(record):
		status="Recorded flight cannot be qualified for review"
		return
	archive_imported=false
	archive_message="Cold-engine flight recording is unavailable. Open may display a saved legacy flight; it never resumes or records this airplane." if selected_profile==Facade.PISTON_PROFILE.id else ""
	observed_panel.set_file_context(false,archive_message)
	scan_open=false
	route_open=false
	if landmark_board!=null: landmark_board.set_open(false)
	menu_open=true
	menu.hide()
	Input.mouse_mode=Input.MOUSE_MODE_VISIBLE
	review_open=true
	observed_panel.set_open(true)

func dismiss_observed_review() -> void:
	if not review_open or not pending_discard.is_empty() or not archive_operation.is_empty(): return
	observed_panel.set_open(false)
	review_open=false
	clear_imported_review()
	open_menu("Recorded flight retained · paused")

func clear_imported_review() -> void:
	# Dismiss releases imported copies without copying the current live history.
	if archive_imported and observed_panel!=null:
		observed_panel.set_recording(ObservedValues.empty_recording())
	archive_imported=false
	archive_message=""
	if observed_panel!=null: observed_panel.set_file_context(false)

func show_current_review() -> void:
	if not review_open or not archive_operation.is_empty() or not review_boundary(): return
	var current: Variant=observed_recorder.recording()
	if observed_panel.set_recording(current):
		archive_imported=false
		archive_message="Cold-engine flight recording is unavailable. Opened legacy history stays separate; Save cannot record this cold flight." if selected_profile==Facade.PISTON_PROFILE.id else "Current paused flight. Save new review always saves this flight."
		observed_panel.set_file_context(false,archive_message)

func begin_archive_operation(action: String, show_dialog: bool=true) -> bool:
	if legacy_proof or not review_open or not archive_operation.is_empty() or not pending_discard.is_empty() or not action in ["save","open"]: return false
	if initializing_recording or not review_boundary():
		archive_feedback("A verified pause or joined stop is required.")
		return false
	var bytes:=PackedByteArray()
	if action=="save":
		if selected_profile==Facade.PISTON_PROFILE.id:
			archive_feedback("Review not saved: cold-engine flight recording is unsupported; an opened legacy file is historical only.")
			return false
		# Exactly one current snapshot, even while an imported file is displayed.
		var encoded: Dictionary=ArchiveCodec.encode(observed_recorder.recording())
		if not encoded.ok:
			archive_feedback("Review not saved: "+encoded.error)
			return false
		bytes=encoded.value.duplicate()
	archive_operation={"action":action,"session_id":adopted_session_id,"bytes":bytes,"prior_message":archive_message,"prior_recent":FileDialog.get_recent_list()}
	observed_panel.set_file_context(archive_imported,"Choose a new file." if action=="save" else "Choose a historical review file.",true)
	if show_dialog:
		archive_dialog.file_mode=FileDialog.FILE_MODE_SAVE_FILE if action=="save" else FileDialog.FILE_MODE_OPEN_FILE
		archive_dialog.title="Save new review — existing files are preserved" if action=="save" else "Open historical recorded review"
		if action=="save":
			var stamp: String=Time.get_datetime_string_from_system(true).replace(":","-")
			archive_dialog.current_file="flight-review-"+stamp+"-"+str(Time.get_ticks_usec())+".fsreview.json"
		archive_dialog.popup_centered_ratio(0.82)
	return true

func cancel_archive_operation() -> void:
	if archive_operation.is_empty(): return
	archive_message=archive_operation.prior_message
	FileDialog.set_recent_list(archive_operation.prior_recent)
	archive_operation.clear()
	if archive_dialog!=null: archive_dialog.hide()
	observed_panel.set_file_context(archive_imported,archive_message)

func finish_archive_operation(path: String) -> Dictionary:
	var rejected: Dictionary={"ok":false,"error":"No matching paused file operation","state":"rejected","path":"","temp_path":null,"value":null,"payload_sha256":null}
	if archive_operation.is_empty(): return rejected
	if initializing_recording or not review_boundary() or archive_operation.session_id!=adopted_session_id:
		cancel_archive_operation()
		archive_feedback(rejected.error)
		return rejected
	var action: String=archive_operation.action
	var result: Dictionary=archive_files.save_new(path,archive_operation.bytes) if action=="save" else archive_files.open(path)
	# The operation gate stays held until the file owner has joined its helper.
	if result.ok and action=="open":
		if observed_panel.set_recording(result.value):
			archive_imported=true
		else:
			result=rejected.duplicate(true)
			result.error="Historical candidate could not be qualified; previous view retained"
	# The pinned chooser adds an in-memory global recent before its selected signal,
	# even when the list is hidden. Restore unrelated chooser state immediately.
	FileDialog.set_recent_list(archive_operation.prior_recent)
	archive_operation.clear()
	if archive_dialog!=null: archive_dialog.hide()
	if result.ok:
		archive_feedback("Saved new review. This flight remains paused or stopped; its memory record is retained." if action=="save" else "Opened historical file. Its author is unverified; the current airplane is unchanged.")
	else:
		var message: String=result.error
		if action=="open": message="Review not opened: "+message
		elif result.state!="recovery_required" and not message.begins_with("Review not saved:"): message="Review not saved: "+message
		if result.temp_path!=null: message+="\nAvailable temporary: "+result.temp_path
		if result.state=="recovery_required" and not result.path.is_empty(): message+="\nInspect selected target: "+result.path
		archive_feedback(message)
	return result.duplicate(true)

func archive_feedback(message: String) -> void:
	archive_message=message
	observed_panel.set_file_context(archive_imported,message)

func make_discard_confirmation(canvas: CanvasLayer) -> void:
	discard_layer=Control.new()
	canvas.add_child(discard_layer)
	discard_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	discard_layer.z_index=45
	var shade:=ColorRect.new()
	shade.color=Color("101923ed")
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter=Control.MOUSE_FILTER_STOP
	discard_layer.add_child(shade)
	var card:=PanelContainer.new()
	card.custom_minimum_size=Vector2(540,210)
	discard_layer.add_child(card)
	var margin:=MarginContainer.new()
	for side in ["left","right","top","bottom"]: margin.add_theme_constant_override("margin_"+side,20)
	card.add_child(margin)
	var box:=VBoxContainer.new()
	box.add_theme_constant_override("separation",14)
	margin.add_child(box)
	var title:=Label.new()
	title.text="Discard this recorded flight?"
	title.add_theme_font_size_override("font_size",22)
	box.add_child(title)
	discard_message=Label.new()
	discard_message.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	discard_message.custom_minimum_size.x=480
	discard_message.add_theme_font_size_override("font_size",16)
	box.add_child(discard_message)
	var buttons:=HBoxContainer.new()
	buttons.add_theme_constant_override("separation",12)
	box.add_child(buttons)
	discard_cancel=Button.new()
	discard_cancel.text="Cancel · keep recorded flight"
	discard_cancel.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	discard_cancel.pressed.connect(cancel_discard)
	buttons.add_child(discard_cancel)
	discard_accept=Button.new()
	discard_accept.pressed.connect(confirm_discard)
	discard_accept.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	buttons.add_child(discard_accept)
	discard_layer.resized.connect(func():
		card.size=card.get_combined_minimum_size()
		card.position=(discard_layer.size-card.size)*0.5)
	discard_layer.hide()

func request_discard(action: String, start: String="", selected_wind: Variant=null, requested_profile: Variant=null) -> void:
	if not archive_operation.is_empty(): return
	if not pending_discard.is_empty() or not action in ["restart","quit"]: return
	var next_profile: Variant=selected_profile if requested_profile==null else requested_profile
	var requested_wind: Variant=current_wind_profile if selected_wind==null else selected_wind
	if action=="restart":
		if not Facade.valid_profile(next_profile):
			status="Invalid fresh profile; flight unchanged"
			return
		var selection_error: String=Facade._selection_error(flight_model_root(next_profile),start,requested_wind,next_profile)
		if not selection_error.is_empty():
			status=selection_error+"; flight unchanged"
			return
	if not recorded_flight_advanced():
		if action=="restart": perform_start(start,requested_wind,next_profile)
		else: await perform_quit()
		return
	if not ensure_review_boundary():
		status="Cannot discard until native flight is paused or its worker has joined"
		return
	pending_discard={"action":action,"start":start,"session_id":adopted_session_id,"wind_profile":requested_wind,"profile_id":next_profile}
	menu_open=true
	Input.mouse_mode=Input.MOUSE_MODE_VISIBLE
	discard_message.text="This flight has %d recorded observations. %s discards its in-memory review. Cancel keeps the flight paused and the review available. Only explicitly saved review files remain on disk."%[observed_status.sample_count,"Restarting" if action=="restart" else "Quitting"]
	discard_accept.text="Discard and restart" if action=="restart" else "Discard and quit"
	discard_layer.show()
	discard_layer.move_to_front()
	discard_cancel.grab_focus()

func cancel_discard() -> void:
	if pending_discard.is_empty(): return
	pending_discard.clear()
	discard_layer.hide()
	if review_open:
		observed_panel.get("_back").grab_focus()
	elif controls_panel!=null and controls_panel.visible:
		pass
	elif wind_panel!=null and wind_panel.visible:
		wind_panel.get("_back").grab_focus()
	elif route_open or scan_open:
		pass
	else:
		open_menu("Recorded flight retained · paused")

func confirm_discard() -> void:
	if pending_discard.is_empty(): return
	if pending_discard.session_id!=adopted_session_id or not review_boundary():
		status="Discard request no longer matches the verified flight boundary"
		cancel_discard()
		return
	var decision: Dictionary=pending_discard.duplicate(true)
	pending_discard.clear()
	discard_layer.hide()
	if decision.action=="restart": perform_start(decision.start,decision.wind_profile,decision.profile_id)
	else: await perform_quit()

func quit_flight() -> void:
	if legacy_proof:
		await super.quit_flight()
	else:
		await request_discard("quit")

func perform_quit() -> void:
	if not archive_operation.is_empty(): return
	await super.quit_flight()

func _exit_tree() -> void:
	# Forced shutdown can lose an unsaved review, but native ownership must join.
	archive_operation.clear()
	super._exit_tree()

func run_piston_visual() -> void:
	# The observer disables the ordinary host loop: keep audio silent separately.
	if sound!=null:
		sound.set_enabled(false)
		sound.set_process(false)
	await load("res://engine_tests/visual_checks.gd").new().run(self)

func run_wind_visual() -> void:
	await load("res://wind_scene_tests/visual_checks.gd").new().run(self)

func run_archive_visual() -> void:
	await load("res://observed_archive_tests/visual_checks.gd").new().run(self)

func run_observed_visual() -> void:
	# Bounded observer: actual fixed-intent flight first; additional display-only
	# records are conspicuously synthetic and never enter the live recorder.
	failures=[]
	var dimensions: Array[Vector2i]=[Vector2i(960,540),Vector2i(1920,1080),Vector2i(2560,1440)]
	var inputs: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://instrument_tests/reference.json"))
	var fixture: RefCounted=load("res://observed_tests/recorder_checks.gd").new()
	fixture.set("_seed",inputs.cases[0].input.duplicate(true))
	for index in dimensions.size():
		named_start="airborne-prepared"
		check(restart(true),"observed_visual_fresh_actual_worker_"+str(index))
		menu_open=false;menu.hide()
		check(pause_session(false),"observed_visual_explicit_resume_"+str(index))
		for frame in 300:
			check(advance_wall_us(250000),"observed_visual_actual_interval_"+str(index)+"_"+str(frame))
		check(pause_session(true),"observed_visual_explicit_pause_"+str(index))
		show_state(0.0)
		var native: Dictionary=facade.readback()
		check(native.tick=="9000" and observed_status.sample_count==151,"observed_visual_real_75s_151_samples_"+str(index))
		get_window().size=dimensions[index]
		await get_tree().process_frame
		await get_tree().process_frame
		var prefix: String="observed-"+str(dimensions[index].x)
		open_observed_review()
		observed_panel.set("_channel","tas")
		observed_panel.get("_graph_choice").select(0)
		observed_panel.get("_painting").queue_redraw()
		await save_view(prefix+"-flight")
		check(observed_panel.visible and observed_panel.get("_record").samples.size()==151,"observed_visual_actual_record_open_"+str(index))
		var viewport: Rect2=get_viewport().get_visible_rect()
		for control in [observed_panel.get("_back"),observed_panel.get("_cursor"),observed_panel.get("_summary"),observed_panel.get("_instant"),observed_panel.get("_controls"),observed_panel.get("_graph_choice")]:
			check(viewport.encloses(control.get_global_rect()),"observed_visual_inside_"+str(index)+"_"+str(control.get_index()))
		observed_panel.select_sample(0)
		observed_panel.set("_channel","ellipsoid_height")
		observed_panel.get("_graph_choice").select(2)
		observed_panel.get("_painting").queue_redraw()
		await save_view(prefix+"-height")
		var synthetic: RefCounted=ObservedRecorder.new()
		check(synthetic.begin(fixture.call("_source","0",0.0,0.0)).ok,"observed_visual_synthetic_gap_begin_"+str(index))
		check(synthetic.observe(fixture.call("_source","61",3.0,4.0)).ok,"observed_visual_synthetic_late_"+str(index))
		var unavailable: Dictionary=fixture.call("_source","181",6.0,8.0)
		unavailable.aircraft.systems=[]
		check(synthetic.observe(unavailable).ok,"observed_visual_synthetic_gap_fuel_unavailable_"+str(index))
		check(synthetic.observe(fixture.call("_source","241",9.0,12.0)).ok,"observed_visual_synthetic_gap_end_"+str(index))
		check(observed_panel.set_recording(synthetic.recording()),"observed_visual_synthetic_gap_record_"+str(index))
		observed_panel.get("_title").text="SYNTHETIC UI FIXTURE · gaps / unavailable fuel"
		observed_panel.set("_channel","fuel_total")
		observed_panel.get("_graph_choice").select(4)
		observed_panel.select_sample(2)
		await save_view(prefix+"-gap")
		var limited: RefCounted=ObservedRecorder.new()
		check(limited.begin(fixture.call("_source","0",0.0,0.0)).ok,"observed_visual_synthetic_limit_begin_"+str(index))
		check(limited.observe(fixture.call("_source","61",3.0,4.0)).ok,"observed_visual_synthetic_limit_sample_"+str(index))
		check(limited.observe(fixture.call("_source","144001",20.0,30.0)).ok,"observed_visual_synthetic_beyond_window_"+str(index))
		check(observed_panel.set_recording(limited.recording()),"observed_visual_synthetic_limit_record_"+str(index))
		observed_panel.get("_title").text="SYNTHETIC UI FIXTURE · sealed recording limit"
		await save_view(prefix+"-limit")
		check(facade.readback()==native,"observed_visual_display_fixtures_do_not_change_native_"+str(index))
		dismiss_observed_review()
		observed_panel.get("_title").text="Recorded flight review"
		start_flight("ground-ready")
		check(not pending_discard.is_empty() and pending_discard.session_id==native.session_id and get_viewport().gui_get_focus_owner()==discard_cancel,"observed_visual_discard_default_cancel_"+str(index))
		await save_view(prefix+"-discard")
		cancel_discard()
		check(facade.readback()==native,"observed_visual_cancel_preserves_actual_flight_"+str(index))
		for name in ["flight","height","gap","limit","discard"]:
			var image: Image=Image.load_from_file(output_directory().path_join(prefix+"-"+name+".png"))
			check(image!=null and image.get_width()==dimensions[index].x and image.get_height()==dimensions[index].y,"observed_visual_exact_dimensions_"+str(index)+"_"+name)
	var joined: bool=close_session()
	if sound!=null: joined=bool(await sound.call("shutdown")) and joined
	check(joined,"observed_visual_worker_audio_joined")
	var report: Dictionary={"passed":failures.is_empty(),"failures":failures,"scope":"Fifteen bounded exported GPU views. Each size has 75 actual simulated seconds/151 observed samples; gap/unavailable/limit records are explicit independent synthetic display fixtures. No human flight, aircraft or phase acceptance.","windows":[[960,540],[1920,1080],[2560,1440]]}
	var file:=FileAccess.open(output_directory().path_join("observed-visual-receipt.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"  ",false,true));file.close()
	print("OBSERVED_VISUAL_SMOKE ",JSON.stringify(report))
	get_tree().quit(0 if report.passed else 1)

func run_landmark_visual() -> void:
	# Observer captures only: the accepted native model remains paused at tick 0.
	failures=[]
	evidence={"scope":"Optional synthetic route UI over unchanged original native model","views":[]}
	var dimensions: Array=[Vector2i(960,540),Vector2i(1920,1080),Vector2i(2560,1440)]
	for index in dimensions.size():
		if index>0:
			named_start="airborne-prepared"
			check(restart(),"landmark_visual_fresh_worker_"+str(index))
		DisplayServer.window_set_size(dimensions[index])
		await get_tree().process_frame
		await get_tree().process_frame
		var prefix: String="landmark-"+str(dimensions[index].x)
		var native: Dictionary=facade.readback()
		check(native.host_mode=="paused" and native.tick=="0","landmark_visual_paused_tick0_"+str(index))
		set_camera_mode(1)
		open_menu()
		await save_view(prefix+"-menu")
		open_landmark_route()
		await save_view(prefix+"-chooser")
		check(route_open and landmark_board.get("_chooser").visible,"landmark_visual_chooser_open_"+str(index))
		choose_landmark_route([0,1,2])
		menu_open=false;menu.hide()
		map_visible=true;flight_map.show()
		await save_view(prefix+"-target")
		check(route_view.active and route_view.available and not flight_map.get("_route").is_empty(),"landmark_visual_current_target_"+str(index))
		check(flight_map.get("_valid") and not flight_map.get("_retained") and not flight_map.call("_runway_metrics").is_empty(),"landmark_visual_paused_locator_current_"+str(index))
		set_route_aids_visible(false)
		await save_view(prefix+"-hidden")
		check(not landmark_board.get("_card").visible and flight_map.get("_route").is_empty() and not route_view.aid_visible,"landmark_visual_aids_hidden_"+str(index))
		set_route_aids_visible(true)
		check(facade.readback()==native,"landmark_visual_all_edits_native_unchanged_"+str(index))
		for name in ["menu","chooser","target","hidden"]:
			var actual: Dictionary=evidence.get(prefix+"-"+name+"_size",{})
			check(actual.get("width")==dimensions[index].x and actual.get("height")==dimensions[index].y,"landmark_visual_dimensions_"+str(index)+"_"+name)
		evidence.views.append({"width":dimensions[index].x,"height":dimensions[index].y,"session_id":native.session_id,"tick":native.tick,"readback_unchanged":facade.readback()==native})
	var joined: bool=close_session()
	if sound!=null:
		joined=bool(await sound.call("shutdown")) and joined
	check(joined,"landmark_visual_worker_and_audio_joined")
	var receipt: Dictionary={"passed":failures.is_empty(),"failures":failures,"evidence":evidence,"scope":"Twelve actual GPU observer captures; native paused at tick 0. Manual synthetic geometry only."}
	var file=FileAccess.open(output_directory().path_join("landmark-visual-receipt.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify(receipt,"  "));file.close()
	print("LANDMARK_VISUAL_PASSED" if receipt.passed else "LANDMARK_VISUAL_FAILED")
	get_tree().quit(0 if receipt.passed else 1)

func run_instrument_visual() -> void:
	# Bounded GPU evidence over the actual original native model. Synthetic bad
	# publications below are view fixtures after a confirmed worker join only.
	failures=[]
	evidence={"scope":"Original prototype native-truth cockpit presentation; no sensor, C172, hardware or phase qualification","views":[]}
	var dimensions: Array=[Vector2i(960,540),Vector2i(1920,1080),Vector2i(2560,1440)]
	for index in dimensions.size():
		if index>0:
			check(restart(),"instrument_visual_fresh_worker_"+str(index))
		DisplayServer.window_set_size(dimensions[index])
		await get_tree().process_frame
		await get_tree().process_frame
		var prefix: String="instrument-"+str(dimensions[index].x)
		var native: Dictionary=facade.readback()
		check(native.host_mode=="paused" and native.tick=="0","instrument_visual_actual_paused_tick0_"+str(index))
		menu_open=false;menu.hide();scan_open=false
		set_camera_mode(1)
		await save_view(prefix+"-outside")
		check(facade.readback()==native,"instrument_visual_outside_native_unchanged_"+str(index))
		set_camera_mode(0)
		await save_view(prefix+"-cockpit")
		set_camera_mode(3)
		await save_view(prefix+"-dashboard")
		set_camera_mode(1)
		open_instrument_scan()
		await save_view(prefix+"-scan")
		for instrument in ["tas","attitude","ellipsoid_height","heading_true","body_yaw_rate","vertical_speed"]:
			open_instrument_scan()
			check(scan_panel.call("focus",instrument),"instrument_visual_paused_focus_"+str(index)+"_"+instrument)
			menu_open=false;menu.hide();scan_open=false
			await save_view(prefix+"-"+instrument)
			check(facade.readback()==native,"instrument_visual_focus_native_unchanged_"+str(index)+"_"+instrument)
		var closed: Dictionary=facade.close()
		check(closed.ok and not closed.readback.native_live,"instrument_visual_confirmed_join_"+str(index))
		adopt_result(closed)
		await save_view(prefix+"-retained")
		check(shared_readings.state=="historical" and panel.get("_info").retained and cockpit_panel.get("_info").retained,"instrument_visual_retained_all_views_"+str(index))
		var invalid: Dictionary=closed.readback.duplicate(true)
		invalid.tick=0.0
		publish_readings(invalid,{"status":"SYNTHETIC INVALID VIEW FIXTURE","paused":true,"view_name":"UNAVAILABLE"})
		scan_open=true;scan_panel.show()
		# save_view republishes actual truth; capture this explicitly labeled bad
		# view after it has drawn without republishing or advancing the facade.
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
		var output: String=OS.get_executable_path().get_base_dir() if not OS.has_feature("editor") else ProjectSettings.globalize_path("res://")
		var image: Image=get_viewport().get_texture().get_image()
		check(image.save_png(output.path_join(prefix+"-invalid.png"))==OK,"instrument_visual_invalid_png_"+str(index))
		check(image.get_width()==dimensions[index].x and image.get_height()==dimensions[index].y,"instrument_visual_actual_invalid_dimensions_"+str(index))
		check(shared_readings.state=="invalid" and not panel.get("_readings").valid and not cockpit_panel.get("_readings").valid,"instrument_visual_invalid_all_views_"+str(index))
		check(facade.readback()==closed.readback,"instrument_visual_closed_native_unchanged_"+str(index))
		for name in ["outside","cockpit","dashboard","scan","tas","attitude","ellipsoid_height","heading_true","body_yaw_rate","vertical_speed","retained"]:
			var actual_size: Dictionary=evidence.get(prefix+"-"+name+"_size",{})
			check(actual_size.get("width")==dimensions[index].x and actual_size.get("height")==dimensions[index].y,"instrument_visual_actual_dimensions_"+str(index)+"_"+name)
		evidence.views.append({"width":image.get_width(),"height":image.get_height(),"native_tick":native.tick,"session_id":native.session_id,"default_eye":[cockpit.eye.x,cockpit.eye.y,cockpit.eye.z],"default_panel_focus":[cockpit.panel_focus.x,cockpit.panel_focus.y,cockpit.panel_focus.z]})
	var joined: bool=close_session()
	if sound!=null:
		joined=bool(await sound.call("shutdown")) and joined
	check(joined,"instrument_visual_final_worker_and_audio_joined")
	var output: String=OS.get_executable_path().get_base_dir() if not OS.has_feature("editor") else ProjectSettings.globalize_path("res://")
	var receipt: Dictionary={"passed":failures.is_empty(),"failures":failures,"evidence":evidence,"scope":"Actual exported GPU observer with paused native model; view fixtures explicitly labeled. No input hardware, sensed instruments, aircraft or phase acceptance."}
	var file=FileAccess.open(output.path_join("instrument-visual-receipt.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify(receipt,"  "));file.close()
	print("INSTRUMENT_VISUAL_PASSED" if receipt.passed else "INSTRUMENT_VISUAL_FAILED")
	get_tree().quit(0 if receipt.passed else 1)

func run_cockpit_visual() -> void:
	# Opt-in view-only engineering observer; Root owns routing and staging.
	var observer: Script=load("res://instrument_tests/cockpit_visual.gd")
	if observer==null or not observer.can_instantiate():
		var joined: bool=close_session()
		if sound!=null: joined=bool(await sound.call("shutdown")) and joined
		push_error("Cockpit visual observer unavailable; joined="+str(joined))
		get_tree().quit(1)
		return
	var runner: RefCounted=observer.new()
	await runner.run(self)
