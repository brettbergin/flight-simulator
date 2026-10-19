extends "res://interactive/preview.gd"
# Original MIT production-loop scene using the accepted native facade.
# The original preview remains separately runnable; legacy proof flags keep its
# frozen test driver. Ordinary interactive flight uses exactly one facade.
const Facade = preload("res://simulation/session_facade.gd")
const Worlds = preload("res://world/world_admission.gd")
const GridReader = preload("res://world/terrain/resident_grid_reader.gd")
const KawoWorld = preload("res://world/terrain/kawo_world.gd")
const KawoEvergreens = preload("res://world/decoration/kawo_evergreens.gd")
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
const FirstFlightPanel = preload("res://ui/first_flight/briefing_panel.gd")
const CircuitGeometry = preload("res://world/synthetic/circuit_geometry.gd")
const CircuitReferenceCard = preload("res://ui/first_flight/circuit_guide.gd")
const AudioCues = preload("res://audio/audio_cues.gd")
const AudioOptions = preload("res://audio/audio_options.gd")
const AudioPanel = preload("res://ui/audio/audio_panel.gd")
const ViewPolicy = preload("res://camera/view_policy.gd")
const ViewsPanel = preload("res://ui/camera/views_panel.gd")
const TaxiLayout = preload("res://world/taxi/taxi_layout.gd")
const TaxiNavigation = preload("res://world/taxi/taxi_navigation.gd")
const TaxiPanel = preload("res://ui/taxi/taxi_panel.gd")
var taxi_panel: Control
var taxi_navigation: RefCounted
var taxi_button: Button
var taxi_open: bool=false
var _taxi_layout: Dictionary={}
var _taxi_opening: Dictionary={}
var _taxi_callbacks: Dictionary={}
var _taxi_owner: int=OS.get_thread_caller_id()
var _taxi_marker: Node3D
var view_settings: Dictionary=ViewPolicy.defaults()
var views_panel: Control
var views_button: Button
var views_open: bool=false
var _views_opening: Dictionary={}
var _views_callback: Callable
var _views_dismiss_callback: Callable
var audio_options: Dictionary={"enabled":true,"engine_gain":1.0,"airflow_gain":1.0,"show_panel_captions":true}
var audio_panel: Control
var audio_button: Button
var audio_open: bool=false
var _audio_opening: Dictionary={}
var _audio_callback: Callable
var _audio_dismiss_callback: Callable
var first_flight_panel: Control
var first_flight_open: bool=false
var circuit_card: Control
var circuit_aid_enabled: bool=false
var circuit_checkbox: CheckBox
var wind_draft: String="calm"
var current_wind_profile: String="calm"
var wind_panel: Control
var wind_label: Label
var wind_card: Panel
var look_release_label: Label
var windsock_visual: MeshInstance3D
var archive_files: RefCounted=ArchiveFiles.new()
var archive_dialog: FileDialog
var archive_operation: Dictionary={}
var archive_imported: bool=false
var archive_message: String=""
var _archive_link_feedback: Dictionary={}
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
const PropellerU64 = preload("res://simulation/uint64.gd")
const EngineStatus = preload("res://cockpit/instruments/engine_status.gd")
const EngineControls = preload("res://cockpit/engine_controls.gd")
var engine_controls: Control
var engine_controls_session: String=""
var engine_pointer_terminal: Dictionary={}
var engine_pointer_rearm: Array[int]=[]
var engine_pointer_look_active: bool=false
# These identify only the last fully adopted fresh flight, never a menu draft.
var selected_profile: String="original-interactive-prototype"
var selected_world: String="original-synthetic"
var world_button: Button
var _synthetic_world_root: Node3D
var _kawo_world_root: Node3D
var _kawo_decoration_root: Node3D
var _kawo_geometry: Dictionary={}
var _synthetic_landmarks: Array=[]
var _world_candidate: Dictionary={}
var adopted_session_id: String=""
var profile_presets: Dictionary={}
var engine_status: Dictionary={}
# Scene-local endpoint-sampled presentation; never native rotor angle/state.
var _propeller_phase: Dictionary={}
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

const PlayerController = preload("res://persistence/local_players_controller.gd")
const PlayerOptions = preload("res://ui/profiles/player_options.gd")
const PlayersPage = preload("res://ui/profiles/players_panel.gd")
const PlayerNamePage = preload("res://ui/profiles/player_name_panel.gd")
const PracticePage = preload("res://ui/history/practice_panel.gd")
const PracticeDetailsPage = preload("res://ui/history/practice_details.gd")
const PlayerExportPage = preload("res://ui/history/player_export_panel.gd")
const PlayerRecoveryPage = preload("res://ui/history/recovery_panel.gd")
const PlayerNativeIdentity = preload("res://build/native_identity.gd")
var player_controller: RefCounted
var players_button: Button
var _player_canvas: CanvasLayer
var _player_ui: Dictionary = {}
var _player_save_ui: Dictionary = {}
var _player_opening: int = 0
var _player_seed: Dictionary = PlayerOptions.default_seed()
var _player_state: Dictionary = {"dirty":false,"pending":false,"unknown":false}
var _player_exit: Dictionary = {}
var _player_transition: bool = false
var _player_history_waiting: bool = false
var _player_audio_retired: bool = false
var _player_close_reason: String = "user_end"
var _player_quit_pending: bool = false
var _player_storage_quit: bool = false
var _recording_player_context: Dictionary = {}
var _player_restart_after_history: Dictionary = {}
var _player_flight_buttons: Array[Button] = []

func _ready() -> void:
	if ("--pointer-checks" in OS.get_cmdline_user_args() or "--pointer-visual-smoke" in OS.get_cmdline_user_args()) and get_parent()==get_tree().root:
		set_process(false)
		var harness: Script=load("res://pointer_checks.gd")
		if harness==null or not harness.can_instantiate():
			push_error("Pointer checks harness unavailable")
			get_tree().quit(1)
			return
		add_child(harness.new())
		return
	if "--camera-checks" in OS.get_cmdline_user_args() and get_parent()==get_tree().root:
		set_process(false)
		set_physics_process(false)
		var harness: Script=load("res://camera_checks.gd")
		if harness==null or not harness.can_instantiate():
			push_error("Camera checks harness unavailable")
			get_tree().quit(1)
			return
		add_child(harness.new())
		return
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
	_start_local_players()
	if not smoke and not _cockpit_asset_ready:
		return
	if not legacy_proof and "--cockpit-asset-visual-smoke" in OS.get_cmdline_user_args():
		set_process(false)
		set_physics_process(false)
		set_process_input(false)
		set_process_unhandled_input(false)
		set_process_unhandled_key_input(false)
		set_process_shortcut_input(false)
		call_deferred("run_cockpit_asset_visual")
		return
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

func _make_world_presentation() -> Dictionary:
	if legacy_proof: return super._make_world_presentation()
	var builder: RefCounted=load("res://interactive/flight_world.gd").new()
	var admitted: Dictionary=TaxiLayout.load()
	if admitted.ok and builder.configure_taxi_layout(admitted.value):
		_taxi_layout=admitted.value.duplicate(true)
		taxi_navigation=TaxiNavigation.new()
		if not taxi_navigation.configure(_taxi_layout).ok:
			taxi_navigation=null
	var presentation: Dictionary=builder.build(self)
	_synthetic_landmarks=presentation.get("landmarks",[]).duplicate(true)
	return presentation

func make_world() -> void:
	super.make_world()
	if not _cockpit_asset_ready:
		return
	if legacy_proof:
		return
	# Ordinary audio must be silent before any provisional worker is adopted.
	if sound!=null:
		sound.set_options(audio_options)
		sound.observe({})
	world_root=Node3D.new()
	world_root.name="CanonicalWorld"
	_synthetic_world_root=world_root
	light_root=Node3D.new()
	light_root.name="CanonicalLighting"
	var world_children: Array=get_children()
	add_child(world_root)
	add_child(light_root)
	for child in world_children:
		if child is Node3D and child!=airplane and child!=camera and child!=cockpit.root:
			child.reparent(light_root if child is Light3D else world_root,true)
	windsock_visual=world_root.find_child("SteadyWindsock",true,false) as MeshInstance3D
	_taxi_marker=Node3D.new()
	_taxi_marker.name="OptionalTaxiReference"
	world_root.add_child(_taxi_marker)
	var ring:=MeshInstance3D.new()
	var mesh:=TorusMesh.new()
	mesh.inner_radius=1.7
	mesh.outer_radius=2.0
	ring.mesh=mesh
	var material:=StandardMaterial3D.new()
	material.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color=Color(0.2,0.9,1.0,0.8)
	ring.material_override=material
	ring.position.y=0.08
	_taxi_marker.add_child(ring)
	var caption:=Label3D.new()
	caption.name="ReferenceLabel"
	caption.position.y=2.5
	caption.billboard=BaseMaterial3D.BILLBOARD_ENABLED
	caption.font_size=42
	caption.pixel_size=0.014
	caption.no_depth_test=false
	_taxi_marker.add_child(caption)
	_taxi_marker.hide()

func close_session() -> bool:
	if legacy_proof:
		return super.close_session()
	if not archive_operation.is_empty(): return false
	retire_taxi_panel()
	retire_views_panel()
	retire_audio_panel()
	retire_first_flight()
	if taxi_navigation!=null: taxi_navigation.retire()
	if flight_map!=null: flight_map.set_taxi_navigation(null)
	if _taxi_marker!=null: _taxi_marker.hide()
	clear_circuit_reference("Session closing")
	if facade!=null: invalidate_engine_pointer("Session closing")
	render_pose.clear()
	if facade==null:
		_retire_kawo_decoration()
		_propeller_phase.clear()
		_observe_audio({})
		bridge=null
		return true
	var before_close: Dictionary=facade.readback()
	var history_reason: String="native_terminal" if before_close.host_mode in ["coverage_blocked","discarded"] else _player_close_reason
	var result: Dictionary=facade.close()
	if result.ok and player_controller!=null:
		# This actual joined result supplies the final endpoint, before facade retirement.
		player_controller.flight_closed(result.readback,history_reason,_player_utc())
	_observe_audio(result.readback)
	# Retain the old prefix when replacement fails, but still label its actual
	# confirmed stop. New-session publications remain held until begin succeeds.
	if initializing_recording and not observed_status.is_empty():
		var ended: Dictionary=observed_recorder.observe(result.readback)
		if ended.status!=null: observed_status=ended.status
	else:
		observe_flight(result.readback)
	if result.ok:
		_retire_kawo_decoration()
		for button in _player_flight_buttons: button.disabled=true
		_propeller_phase.clear()
		review_joined=true
		facade=null
		bridge=null
	else:
		adopt_result(result)
	return result.ok

func _make_facade() -> RefCounted:
	# Internal construction seam: tests can observe the real native adapter from
	# its first open through the existing Facade callable factory.
	return Facade.new()

func restart(replace_confirmed: bool=false, selected_wind: Variant=null, requested_profile: Variant=null, requested_start: Variant=null, requested_world: Variant=null) -> bool:
	if _player_transition: return false
	# Explicit --smoke is the existing native-only harness; ordinary flights admit the fixed cockpit first.
	if not smoke and not _cockpit_asset_ready:
		return false
	if legacy_proof:
		return super.restart()
	if taxi_open: return false
	if not archive_operation.is_empty(): return false
	var next_profile: Variant=selected_profile if requested_profile==null else requested_profile
	var next_start: Variant=named_start if requested_start==null else requested_start
	var requested_wind: Variant=current_wind_profile if selected_wind==null else selected_wind
	var next_world: Variant=selected_world if requested_world==null else requested_world
	if not Facade.valid_profile(next_profile) or typeof(next_start)!=TYPE_STRING:
		status="Invalid fresh profile/start selection; flight unchanged"
		return false
	var model_root: String=flight_model_root(next_profile)
	# Inventory/root/recipe/wind admission runs before old worker destruction.
	var selection_error: String=Facade._selection_error(model_root,next_start,requested_wind,next_profile,next_world)
	if not selection_error.is_empty():
		status=selection_error+"; flight unchanged"
		return false
	var provisional: Dictionary=_prepare_world_candidate(model_root,next_world,next_profile,next_start,requested_wind)
	if not provisional.ok:
		status=provisional.error+"; flight unchanged"
		return false
	if recorded_flight_advanced() and not replace_confirmed:
		_dispose_world_candidate()
		request_discard("restart",next_start,requested_wind,next_profile,false,next_world)
		return false
	if recorded_flight_advanced() and not review_boundary():
		status="Recorded flight replacement requires a verified paused or joined boundary; flight unchanged"
		_dispose_world_candidate()
		return false
	# Keep independent guest presets; never promote a legacy preset implicitly.
	var next_presets: Dictionary=profile_presets.duplicate(true)
	if not active_preset.is_empty(): next_presets[selected_profile]=active_preset.duplicate(true)
	initializing_recording=true
	_player_close_reason="user_restart"
	if not close_session():
		initializing_recording=false
		_dispose_world_candidate()
		return fail("Native worker did not join")
	if player_controller!=null and player_controller.history_exit_pending():
		_player_restart_after_history={"start":next_start,"wind":requested_wind,"profile":next_profile,"world":next_world}
		_dispose_world_candidate()
		initializing_recording=false
		_show_history_wait()
		return false
	held_systems.clear()
	pending_systems.clear()
	engine_status.clear()
	facade=_make_facade()
	if facade==null:
		return restart_failed("Flight session construction failed")
	# The inherited view reference never owns a native executive.
	bridge=facade
	var result: Dictionary=facade.start(model_root,next_start,requested_wind,next_profile,next_world)
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
	if not _attach_world_candidate(result.readback,next_world):
		return restart_failed("Prepared world presentation did not match actual native source")
	if not flight_map.set_compiled_airport(_kawo_geometry if next_world=="kawo-prototype-v1" else {}):
		return restart_failed("Compiled runway locator rejected selected geometry")
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
		if item.id=="world" and next_world=="kawo-prototype-v1":
			var registered_world: Dictionary=facade.render_origin.register_participant("world",world_root,["world"])
			if not registered_world.ok: return restart_failed(registered_world.error)
			continue
		node.set_script(null)
		node.set_script(Participant)
		if not node.call("configure",snapshot.session_id,prepared.ecef,prepared.rotation,[float(node.position.x),float(node.position.y),float(node.position.z)],node.basis):
			return restart_failed("Invalid canonical scene participant "+item.id)
		if item.id in ["ownship","cockpit"] and not node.call("set_canonical_pose",result.readback.canonical.ecef_position_m,node.basis):
			return restart_failed("Invalid binary64 ownship origin source")
		var registered: Dictionary=facade.render_origin.register_participant(item.id,node,item.categories)
		if not registered.ok:
			return restart_failed(registered.error)
	if next_world=="kawo-prototype-v1":
		if not is_instance_valid(_kawo_decoration_root): return restart_failed("Decorative KAWO world was not adopted")
		var registered_decoration: Dictionary=facade.render_origin.register_participant("kawo-decoration",_kawo_decoration_root,[])
		if not registered_decoration.ok: return restart_failed(registered_decoration.error)
	if not facade.render_origin.register_participant("nonspatial",null,["spatial_audio","local_particles"]).ok:
		return restart_failed("Required absent origin categories rejected")
	var adopted: Dictionary=facade.render_origin.rebase(prepared.ecef)
	if not adopted.ok:
		return restart_failed(adopted.error)
	camera_ready=false
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
	# ADR022 chooses the recording revision from this complete adopted source.
	# Failed qualification retains the previous profile's observed history.
	var begun: Dictionary=observed_recorder.begin(facade.readback(),true)
	if not begun.ok:
		return restart_failed("Flight observation recording unavailable: "+begun.error)
	observed_status=begun.status
	initializing_recording=false
	active_preset=next_preset.duplicate(true)
	profile_presets=next_presets
	profile_presets[next_profile]=active_preset.duplicate(true)
	selected_profile=next_profile
	selected_world=next_world
	named_start=next_start
	adopted_session_id=result.readback.session_id
	# Bind only after recorder/source/mapper adoption has succeeded.
	if taxi_navigation!=null and selected_world=="original-synthetic": taxi_navigation.fresh_session(facade.readback())
	if selected_world=="kawo-prototype-v1":
		flight_map.set_landmarks([])
		clear_circuit_reference("Synthetic circuit is unavailable at KAWO")
	else: flight_map.set_landmarks(_synthetic_landmarks)
	review_joined=false
	current_wind_profile=requested_wind
	circuit_aid_enabled=false
	# Commit camera defaults only with the fully adopted replacement session.
	view_settings=ViewPolicy.defaults()
	camera_distance=13.0
	super.set_camera_mode(0)
	_ensure_player_audio()
	_observe_audio(facade.readback())
	_player_flight_adopted()
	_notify_player_options()
	for button in _player_flight_buttons: button.disabled=button==taxi_button and taxi_navigation==null
	if taxi_button!=null and selected_world=="kawo-prototype-v1": taxi_button.disabled=true
	_dispose_world_candidate()
	return true

func _dispose_world_candidate() -> void:
	var root: Variant=_world_candidate.get("root")
	if is_instance_valid(root) and root is Node3D and root!=world_root: root.free()
	var decoration: Variant=_world_candidate.get("decoration")
	if is_instance_valid(decoration) and decoration is Node3D and decoration!=_kawo_decoration_root: decoration.free()
	_world_candidate.clear()

func _retire_kawo_decoration() -> void:
	if is_instance_valid(_kawo_decoration_root):
		_kawo_decoration_root.hide()
		_kawo_decoration_root.free()
	_kawo_decoration_root=null

func _prepare_world_candidate(model_root: String, selector: Variant, profile: Variant, start: Variant, wind: Variant) -> Dictionary:
	_dispose_world_candidate()
	var bytes: Dictionary=Facade.preflight_world(model_root,selector,profile,start,wind)
	if not bytes.ok: return {"ok":false,"error":bytes.error}
	if selector=="original-synthetic":
		_world_candidate={"entry":bytes.entry,"root":null,"decoration":null,"geometry":{}}
		return {"ok":true,"error":""}
	if not Facade._native_identity_valid() or not ClassDB.class_exists("FlightInteractiveSession"):
		return {"ok":false,"error":"Qualified geographic native module unavailable"}
	var decoded: Dictionary=GridReader.decode(bytes.files["ground.fgrd"],bytes.entry)
	if not decoded.ok: return {"ok":false,"error":decoded.error}
	var receipt: Dictionary=Facade._pack_json(bytes.files["compile-receipt.json"]).value
	var frame: Dictionary=Frames.anchor(bytes.entry.world_anchor.latitude_rad,bytes.entry.world_anchor.longitude_rad,bytes.entry.world_anchor.ellipsoid_height_m)
	if frame.is_empty(): return {"ok":false,"error":"Invalid geographic anchor frame"}
	var built: Dictionary=KawoWorld.prepare(decoded.grid,receipt.airport_geometry,"",frame.ecef,frame.rotation)
	if not built.ok: return {"ok":false,"error":built.error}
	var decorated: Dictionary=KawoEvergreens.prepare(decoded.grid,receipt.airport_geometry,"",frame.ecef,frame.rotation)
	if not decorated.ok:
		built.root.free()
		return {"ok":false,"error":decorated.error}
	_world_candidate={"entry":bytes.entry,"root":built.root,"decoration":decorated.root,"geometry":receipt.airport_geometry.duplicate(true)}
	return {"ok":true,"error":""}

func _attach_world_candidate(readback: Dictionary, selector: String) -> bool:
	if _world_candidate.is_empty(): return false
	var relation: Dictionary=Worlds.source(readback.model_identity,readback.named_start,readback.prepared_world_sha256,readback.world_anchor)
	if not relation.ok or relation.selector!=selector: return false
	if selector=="kawo-prototype-v1":
		var root: Node3D=_world_candidate.root
		var bound: Dictionary=root.bind_session(readback.session_id)
		if not bound.ok: return false
		var identity: Dictionary=root.source_binding()
		if identity.session_id!=readback.session_id or identity.payload_sha256!=readback.prepared_world_sha256 or identity.world_anchor!=readback.world_anchor or identity.anchor_ecef_m!=prepared.ecef or identity.ecef_to_eus!=prepared.rotation: return false
		var decoration: Variant=_world_candidate.get("decoration")
		if not is_instance_valid(decoration) or not decoration is Node3D or not decoration.bind_session(readback.session_id).ok: return false
		var decoration_identity: Dictionary=decoration.source_binding()
		if decoration_identity!=identity: return false
		if is_instance_valid(world_root): world_root.hide()
		if is_instance_valid(_kawo_world_root): _kawo_world_root.free()
		_retire_kawo_decoration()
		world_root=root
		_kawo_world_root=root
		_kawo_decoration_root=decoration
		_world_candidate.root=null
		_world_candidate.decoration=null
		_kawo_geometry=_world_candidate.geometry.duplicate(true)
		root.hide()
		add_child(root)
		decoration.hide()
		add_child(decoration)
	else:
		if not is_instance_valid(_synthetic_world_root): return false
		_retire_kawo_decoration()
		if is_instance_valid(_kawo_world_root):
			_kawo_world_root.free()
			_kawo_world_root=null
		world_root=_synthetic_world_root
		_kawo_geometry.clear()
		world_root.hide()
	return true

func choose_world() -> void:
	if _player_transition or not paused or not pending_discard.is_empty() or not archive_operation.is_empty(): return
	var next: String="kawo-prototype-v1" if selected_world=="original-synthetic" else "original-synthetic"
	request_discard("restart","ground-ready","calm",Facade.LEGACY_PROFILE.id,false,next)

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
	var configured: Dictionary=mapper.configure_v2(preset,held_controls,initial.solved_controls,collect_input_raw(preset),source.model_identity,systems.value)
	if not configured.ok: return configured
	return mapper.bind_pointer_session(source.session_id)

func suspend_mapper(reason: String) -> void:
	if mapper==null: return
	remember_pointer_rearm()
	engine_pointer_terminal.clear()
	engine_pointer_look_active=false
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
	if engine_controls!=null: engine_controls.invalidate_local(reason)
	# This clears only local intent. Facade owns release admission before resume.

func choose_profile() -> void:
	if selected_world=="kawo-prototype-v1":
		status="KAWO supports the ready-to-fly original prototype; switch World to synthetic for the cold piston aircraft"
		return
	if views_open or taxi_open: return
	if audio_open: return
	# Draft selection remains separate from the current adopted profile and preset.
	if not paused or facade==null or facade.readback().host_mode!="paused": return
	if review_open or scan_open or route_open or not archive_operation.is_empty() or not pending_discard.is_empty(): return
	if controls_panel!=null and controls_panel.visible: return
	var draft_profile: String=Facade.LEGACY_PROFILE.id if selected_profile==Facade.PISTON_PROFILE.id else Facade.PISTON_PROFILE.id
	var draft_start: String="piston-cold-ground" if draft_profile==Facade.PISTON_PROFILE.id else "ground-ready"
	var draft_wind: String="calm" if draft_profile==Facade.PISTON_PROFILE.id else current_wind_profile
	request_discard("restart",draft_start,draft_wind,draft_profile)

# Private numerical presentation estimate, not a native rotor angle. Scene
# adopts one aggregate Readback; Facade's internal [due-1,1] replies are not
# individual samples here. Endpoint trapezoids approximate changing shaft rate.
static func _next_propeller_phase(previous: Dictionary, source: Dictionary) -> Dictionary:
	var status: Dictionary=EngineStatus.from_readback(source)
	if status.state not in ["live","paused"]:
		return {}
	var shaft: Dictionary=status.readings["propeller.angular_speed"]
	if not shaft.valid or typeof(shaft.value)!=TYPE_FLOAT or not is_finite(shaft.value) or shaft.value<0.0:
		return {}
	var identity: Dictionary={"session_id":source.session_id,"model_identity":source.model_identity.duplicate(true),
		"native_source_fingerprint":source.native_source_fingerprint,"prepared_world_sha256":source.prepared_world_sha256,
		"world_anchor":source.world_anchor.duplicate(true),"named_start":source.named_start,"clock":source.aircraft.clock.duplicate(true)}
	var next: Dictionary={"identity":identity,"tick":source.tick,"rate":shaft.value,"angle":0.0,"source_elapsed_s":source.aircraft.elapsed_s}
	if previous.is_empty() or previous.identity!=identity:
		return next
	var progress: Dictionary=PropellerU64.small_difference(source.tick,previous.tick,32)
	if not progress.ok:
		# New valid boundary seeds a fresh local reference; never bridge a reset,
		# backwards tick or unsupported (>32) gap with an invented large angle.
		return next
	if progress.value==0:
		return previous.duplicate(true)
	var interval: float=float(progress.value)/float(source.aircraft.clock.tick_rate_hz)
	var mean_rate: float=(float(previous.rate)+float(shaft.value))*0.5
	var increment: float=mean_rate*interval
	if not is_finite(mean_rate) or not is_finite(increment):
		return {}
	# Wrap the increment before addition, retaining bounded local phase. No
	# absolute uint64 tick or rounded absolute elapsed-time subtraction is used.
	next.angle=fposmod(float(previous.angle)+fposmod(increment,TAU),TAU)
	if not is_finite(next.angle):
		return {}
	return next

func _adopt_propeller_phase(source: Dictionary) -> void:
	_propeller_phase=_next_propeller_phase(_propeller_phase,source)


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
	_adopt_propeller_phase(state)
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
	_observe_audio(state)
	_observe_views_source()

func pause_session(value: bool) -> bool:
	if legacy_proof:
		return super.pause_session(value)
	if views_open or taxi_open: return false
	if audio_open and not value: return false
	if not archive_operation.is_empty(): return false
	if facade==null:
		return false
	if not value:
		if mapper==null:
			status="CONTROLS PAUSED | "+input_problem
			return false
		var resume_raw: Dictionary=collect_input_raw()
		var checked_raw: Dictionary=Preset.validate_raw(resume_raw)
		if checked_raw.ok:
			for button in engine_pointer_rearm:
				if button in checked_raw.value.mouse_buttons:
					input_problem="Release engine pointer button before Resume: "+str(button)
					status="CONTROLS PAUSED | "+input_problem
					return false
		var ready: Dictionary=mapper.resume_confirmed(resume_raw)
		if not ready.ok:
			input_problem=ready.error
			status="CONTROLS PAUSED | "+input_problem
			return false
		observe_pointer_release(resume_raw)
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
	if views_open or taxi_open: return false
	var result: Dictionary=facade.set_axes(axes)
	adopt_result(result)
	return result.ok

func advance_wall_us(elapsed_us: int) -> bool:
	if legacy_proof:
		return super.advance_wall_us(elapsed_us)
	if views_open or taxi_open: return false
	var result: Dictionary=facade.advance_wall_us(elapsed_us)
	adopt_result(result)
	return result.ok

func _process(delta: float) -> void:
	if legacy_proof:
		super._process(delta)
		return
	if player_controller!=null: player_controller.pump()
	_update_player_history_wait()
	var now: int=Time.get_ticks_usec()
	var elapsed: int=now-last_wall_us
	last_wall_us=now
	process_input_interval(elapsed)
	show_state(clampf(float(elapsed)/1000000.0,0.0,0.25))

func process_input_interval(elapsed: int) -> void:
	if not _player_ui.is_empty(): return
	if views_open or taxi_open: return
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
		# A lost GUI release is reconciled using complete validated Raw, through
		# the same explicit terminal seam. Never rewrite physical button readings.
		if not reconcile_pointer_release(raw): return
		var sample: Dictionary=mapper.sample(raw,elapsed)
		wheel_pulses.clear()
		if not sample.ok:
			pause_for_input(sample.error)
			return
		controls=sample.axes.duplicate(true)
		brake_hold=sample.brake_hold
		takeover_targets=sample.takeover.duplicate()
		var sampled_facade: RefCounted=facade
		var sampled_session: String=facade.readback().session_id
		observe_pointer_release(raw)
		update_engine_controls()
		for action in sample.actions:
			dispatching_input=true
			dispatch_input_action(action)
			dispatching_input=false
			if facade!=sampled_facade or paused or menu_open or input_blocked:
				return
		if piston_mode() and (not pointer_session_live() or facade.readback().session_id!=sampled_session):
			invalidate_engine_pointer("Flight input owner changed")
			return
		engine_pointer_look_active=Mapper.action_pressed(active_preset,raw,"look_hold")
		Input.mouse_mode=Input.MOUSE_MODE_CAPTURED if engine_pointer_look_active else Input.MOUSE_MODE_VISIBLE
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
			observe_pointer_release(raw)
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
	engine_controls=EngineControls.new()
	canvas.add_child(engine_controls)
	engine_controls.z_index=2
	engine_controls.set_expanded(false)
	engine_controls.gesture_requested.connect(on_engine_gesture.bind(engine_controls))
	engine_controls.capture_invalidated.connect(on_engine_retired.bind(engine_controls))
	engine_controls.denied_press.connect(on_engine_denied.bind(engine_controls))
	engine_controls.expansion_changed.connect(func(_expanded: bool): layout_live_flight_aids())
	engine_controls.hide()
	_player_canvas=canvas
	var box: VBoxContainer=menu.get_child(0)
	# Calibration replaces the old global sensitivity and implicit pad picker.
	for child in box.get_children():
		if child is HSlider or (child is Label and child!=menu_title and child!=menu_message) or (child is Button and child.text.begins_with("Keyboard / gamepad")):
			box.remove_child(child)
			child.queue_free()
	var controls_button: Button=add_menu_button(box,"Controls and calibration  (F7)",open_controls)
	profile_button=add_menu_button(box,"Aircraft: ready-to-fly prototype",choose_profile)
	profile_button.add_theme_font_size_override("font_size",15)
	world_button=add_menu_button(box,"World: synthetic airfield  ·  switch to KAWO",choose_world)
	world_button.add_theme_font_size_override("font_size",15)
	var scan_button: Button=add_menu_button(box,"Instrument scan",open_instrument_scan)
	var route_button: Button=add_menu_button(box,"Landmark route",open_landmark_route)
	var review_button: Button=add_menu_button(box,"Flight review",open_observed_review)
	var wind_button: Button=add_menu_button(box,"Wind",open_wind)
	var first_button: Button=add_menu_button(box,"First flight",open_first_flight)
	first_button.tooltip_text="Supported starts, current controls and optional synthetic circuit reference"
	controls_button.text="Controls (F7)"
	controls_button.tooltip_text="Controls and calibration"
	var cockpit_row:=HBoxContainer.new()
	cockpit_row.add_theme_constant_override("separation",8)
	box.add_child(cockpit_row)
	box.move_child(cockpit_row,5)
	for button in [first_button,controls_button,scan_button,route_button,review_button,wind_button]:
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
	var speed_audio_row:=HBoxContainer.new()
	speed_audio_row.add_theme_constant_override("separation",8)
	box.add_child(speed_audio_row)
	box.move_child(speed_audio_row,6)
	speed_button.reparent(speed_audio_row)
	speed_button.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	audio_button=Button.new()
	audio_button.text="Audio"
	audio_button.custom_minimum_size=Vector2(92,32)
	audio_button.add_theme_font_size_override("font_size",18)
	audio_button.pressed.connect(open_audio)
	speed_audio_row.add_child(audio_button)
	views_button=Button.new()
	views_button.name="Views"
	views_button.text="Views"
	views_button.tooltip_text="Paused lookout presets and field of view. Recenter selected view keeps its preset."
	views_button.custom_minimum_size=Vector2(92,32)
	views_button.add_theme_font_size_override("font_size",18)
	views_button.pressed.connect(open_views)
	speed_audio_row.add_child(views_button)
	taxi_button=Button.new()
	taxi_button.name="Taxi"
	taxi_button.text="Taxi"
	taxi_button.tooltip_text="Paused synthetic taxi diagram and manual runway/parking references"
	taxi_button.custom_minimum_size=Vector2(76,32)
	taxi_button.add_theme_font_size_override("font_size",18)
	taxi_button.pressed.connect(open_taxi)
	taxi_button.disabled=taxi_navigation==null
	speed_audio_row.add_child(taxi_button)
	players_button=Button.new()
	players_button.name="Players"
	players_button.text="Players ï¿½ Guest"
	players_button.custom_minimum_size=Vector2(100,32)
	players_button.clip_text=true
	players_button.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS
	players_button.pressed.connect(open_players)
	# Reuse the aircraft row height; the six flight tools remain on their row.
	var player_row:=HBoxContainer.new()
	box.add_child(player_row)
	box.move_child(player_row,profile_button.get_index())
	profile_button.reparent(player_row)
	profile_button.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	player_row.add_child(players_button)
	_player_flight_buttons=[first_button,controls_button,scan_button,route_button,wind_button,speed_button,audio_button,views_button,taxi_button]
	taxi_panel=TaxiPanel.new()
	canvas.add_child(taxi_panel)
	taxi_panel.z_index=3
	taxi_panel.hide()
	views_panel=ViewsPanel.new()
	canvas.add_child(views_panel)
	views_panel.z_index=3
	views_panel.hide()
	audio_panel=AudioPanel.new()
	canvas.add_child(audio_panel)
	audio_panel.z_index=3
	audio_panel.hide()
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
	discard_layer.z_index=4
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
	look_release_label=Label.new()
	# PASS permits standard full-alias tooltip hover without consuming input.
	look_release_label.mouse_filter=Control.MOUSE_FILTER_PASS
	look_release_label.add_theme_font_size_override("font_size",10)
	look_release_label.add_theme_color_override("font_color",Color("d1e9ec"))
	look_release_label.add_theme_color_override("font_shadow_color",Color.BLACK)
	look_release_label.add_theme_constant_override("shadow_offset_x",1)
	look_release_label.add_theme_constant_override("shadow_offset_y",1)
	look_release_label.hide()
	canvas.add_child(look_release_label)
	first_flight_panel=FirstFlightPanel.new()
	canvas.add_child(first_flight_panel)
	first_flight_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	first_flight_panel.z_index=3
	first_flight_panel.hide()
	first_flight_panel.choice_requested.connect(on_first_flight_choice.bind(first_flight_panel))
	first_flight_panel.controls_requested.connect(on_first_flight_controls.bind(first_flight_panel))
	first_flight_panel.back_requested.connect(on_first_flight_back.bind(first_flight_panel))
	circuit_checkbox=CheckBox.new()
	circuit_checkbox.text="Show optional synthetic circuit reference (not evaluated)"
	circuit_checkbox.add_theme_font_size_override("font_size",16)
	circuit_checkbox.custom_minimum_size.y=36
	first_flight_panel.circuit_slot.add_child(circuit_checkbox)
	circuit_checkbox.toggled.connect(func(enabled: bool) -> void:
		on_circuit_enabled(enabled,first_flight_panel._source_session(),first_flight_panel))
	circuit_card=CircuitReferenceCard.new()
	canvas.add_child(circuit_card)
	circuit_card.mouse_filter=Control.MOUSE_FILTER_IGNORE
	circuit_card.enabled_requested.connect(on_circuit_enabled.bind(circuit_card))
	circuit_card.hide()
	menu.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	menu.custom_minimum_size=Vector2(560,490)
	layout_flight_menu()
	for page in [menu,first_flight_panel,controls_panel,wind_panel,observed_panel,discard_layer,scan_panel,audio_panel,views_panel,taxi_panel]:
		page.visibility_changed.connect(func():
			if look_release_label!=null and not pointer_modal_free(): look_release_label.hide())

func layout_flight_menu() -> void:
	if menu==null:
		return
	menu.size=menu.get_combined_minimum_size()
	var available: Vector2=get_viewport().get_visible_rect().size
	menu.position=Vector2(maxf(8.0,(available.x-menu.size.x)*0.5),maxf(8.0,(available.y-menu.size.y)*0.5))

func set_flight_scale(value: float) -> bool:
	if views_open or taxi_open: return false
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
	if _player_transition: return
	if not _player_ui.is_empty(): return
	if legacy_proof:
		return
	if views_open or taxi_open: return
	# _input precedes GUI handling, while Input polling still sees that click.
	# Disabled binding paint must not allow the mapped flight action to fire.
	if event is InputEventMouseButton and event.pressed and event.button_index==MOUSE_BUTTON_LEFT:
		update_engine_controls()
		if pointer_ui_eligible() and engine_controls!=null and not engine_controls.hit_control(engine_controls.get_global_transform_with_canvas().affine_inverse()*event.position).is_empty():
			var conflict: String=pointer_button_binding(int(event.button_index))
			if not conflict.is_empty():
				pause_for_input("Left button bound to "+conflict+"; release / remap in Controls")
				get_viewport().set_input_as_handled()
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
	if _player_transition: return
	if not _player_ui.is_empty(): return
	if legacy_proof:
		super._unhandled_input(event)
		return
	if taxi_open:
		if event is InputEventJoypadButton and event.pressed:
			if _views_cancel_event(event): dismiss_taxi()
			get_viewport().set_input_as_handled()
		return
	if views_open:
		if event is InputEventJoypadButton and event.pressed:
			if _views_cancel_event(event):
				dismiss_views()
			get_viewport().set_input_as_handled()
		return
	if not archive_operation.is_empty(): return
	if audio_open:
		if event is InputEventJoypadButton and event.pressed:
			var raw: Dictionary=collect_input_raw()
			if Preset.validate_raw(raw).ok and Mapper.action_pressed(active_preset,raw,"pause_menu"):
				dismiss_audio()
				get_viewport().set_input_as_handled()
		return
	if controls_panel!=null and controls_panel.visible:
		return
	if first_flight_open:
		if event is InputEventJoypadButton and event.pressed:
			var raw: Dictionary=collect_input_raw()
			if Preset.validate_raw(raw).ok and Mapper.action_pressed(active_preset,raw,"pause_menu"):
				dismiss_first_flight()
			elif Preset.validate_raw(raw).ok and Mapper.action_pressed(active_preset,raw,"controls_panel"):
				on_first_flight_controls(first_flight_source_session(),first_flight_panel)
		get_viewport().set_input_as_handled()
		return
	if route_open or review_open or not pending_discard.is_empty():
		return
	if event is InputEventMouseMotion and not paused and pointer_modal_free() and engine_pointer_look_active and Input.mouse_mode==Input.MOUSE_MODE_CAPTURED:
		look_angles.x=clampf(look_angles.x-event.relative.x*0.004,-PI,PI)
		look_angles.y=clampf(look_angles.y-event.relative.y*0.004,-1.2,1.2)
	elif paused and event is InputEventJoypadButton and event.pressed:
		var raw: Dictionary=collect_input_raw()
		if Preset.validate_raw(raw).ok and Mapper.action_pressed(active_preset,raw,"pause_menu"):
			close_menu()

func _unhandled_key_input(event: InputEvent) -> void:
	if _player_transition:
		get_viewport().set_input_as_handled()
		return
	if not _player_ui.is_empty():
		if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode==KEY_ESCAPE: _dismiss_player_ui()
		get_viewport().set_input_as_handled()
		return
	if legacy_proof:
		super._unhandled_key_input(event)
		return
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	if taxi_open:
		if _views_cancel_event(event): dismiss_taxi()
		get_viewport().set_input_as_handled()
		return
	if views_open:
		if _views_cancel_event(event):
			dismiss_views()
		get_viewport().set_input_as_handled()
		return
	if audio_open:
		var raw: Dictionary=collect_input_raw()
		if event.physical_keycode==KEY_ESCAPE or (Preset.validate_raw(raw).ok and Mapper.action_pressed(active_preset,raw,"pause_menu")):
			dismiss_audio()
		get_viewport().set_input_as_handled()
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
	if first_flight_open:
		var raw: Dictionary=collect_input_raw()
		if event.physical_keycode==KEY_ESCAPE or (Preset.validate_raw(raw).ok and Mapper.action_pressed(active_preset,raw,"pause_menu")):
			dismiss_first_flight()
		elif Preset.validate_raw(raw).ok and Mapper.action_pressed(active_preset,raw,"controls_panel"):
			on_first_flight_controls(first_flight_source_session(),first_flight_panel)
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
	if _player_transition: return
	if not _player_ui.is_empty():
		if action=="pause_menu": _dismiss_player_ui()
		return
	if taxi_open:
		if action=="pause_menu": dismiss_taxi()
		return
	if views_open:
		if action=="pause_menu": dismiss_views()
		return
	if audio_open:
		if action=="pause_menu": dismiss_audio()
		return
	if not archive_operation.is_empty(): return
	if first_flight_open:
		if action=="pause_menu": dismiss_first_flight()
		elif action=="controls_panel": on_first_flight_controls(first_flight_source_session(),first_flight_panel)
		return
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
			publish_circuit_reference()
		"map_zoom_in":
			if map_visible: flight_map.call("zoom",0.5)
		"map_zoom_out":
			if map_visible: flight_map.call("zoom",2.0)
		"view_zoom_in","view_zoom_out":
			var direction: float=-1.0 if action=="view_zoom_in" else 1.0
			if camera_mode in [0,3]:
				camera.fov=clampf(camera.fov+direction*3,35,90)
				view_settings.fov_deg=float(camera.fov)
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
			var options: Dictionary=audio_options.duplicate(true)
			options.enabled=not options.enabled
			set_audio_options(options)
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
	if not _player_ui.is_empty(): return
	if legacy_proof:
		super.on_focus_lost()
		return
	retire_taxi_panel()
	retire_views_panel()
	Input.mouse_mode=Input.MOUSE_MODE_VISIBLE
	if facade!=null:
		pause_for_input("Window inactive; release controls and confirm Resume")

func pause_for_input(reason: String) -> void:
	retire_taxi_panel()
	retire_views_panel()
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
	if views_open or taxi_open: return
	if not archive_operation.is_empty(): return
	if not paused or facade==null or facade.readback().host_mode!="paused":
		return
	if not device_connections.has(device):
		input_problem="Device unavailable; explicitly reselect a connected source"
		return
	selected_slots[slot]={"device":device,"generation":device_connections[device].generation}

# ADR020: source adoption and the paused modal never own simulation/input state.
func _observe_audio(value: Variant) -> void:
	if legacy_proof: return
	var source: Dictionary={}
	if not initializing_recording and facade!=null and value is Dictionary and value.get("model_identity") is Dictionary and not adopted_session_id.is_empty():
		if value.get("session_id")==adopted_session_id and value.get("model_identity",{}).get("id")==selected_profile:
			source=value.duplicate(true)
	if sound!=null: sound.observe(source)
	if audio_open and audio_panel!=null:
		var cues: Dictionary=AudioCues.from_readback(source)
		audio_panel.set_context(cues,audio_options)
		if cues.state!="paused" or cues.session_id!=_audio_opening.get("session"):
			retire_audio_panel()
			# Do not call open_menu here: a lost publication grants no pause action.
			menu_open=true
			if menu!=null:
				menu.show()
				menu_title.text="Audio source changed Â· inspect current flight"
				resume_button.disabled=cues.state!="paused"

# Original MIT. Presentation-only Views owner; no pause or Mapper sample here.
func camera_view_settings() -> Dictionary:
	var value: Dictionary=view_settings.duplicate(true)
	if camera!=null: value.fov_deg=float(camera.fov)
	return value

func set_camera_mode(value: int) -> void:
	if legacy_proof:
		super.set_camera_mode(value)
		return
	if views_open or taxi_open: return
	var response: String=view_settings.external_response
	super.set_camera_mode(value)
	var traditional: Array[String]=["cockpit","chase","orbit","panel"]
	view_settings={"preset":traditional[camera_mode],"fov_deg":float(camera.fov),"external_response":response}

func _camera_smooth_alpha(seconds: float) -> float:
	return 1.0-exp(-9.0*clampf(seconds,0.0,0.25))

func _camera_view_label() -> String:
	var names: Dictionary={"cockpit":"COCKPIT","forward_horizon":"FORWARD HORIZON","left_window":"LEFT WINDOW","right_window":"RIGHT WINDOW","panel":"PANEL","chase":"CHASE","orbit":"ORBIT"}
	return "%s / %.1fÂ° FOV"%[names[view_settings.preset],camera.fov]

func _views_current_source() -> Dictionary:
	if legacy_proof or facade==null or initializing_recording or quitting or not paused or adopted_session_id.is_empty(): return {}
	var source: Dictionary=facade.readback()
	if not NativeReadings._validate(source).is_empty(): return {}
	if source.host_mode!="paused" or not source.native_live or not source.paused or source.historical or source.session_id!=adopted_session_id: return {}
	var profile: Dictionary=Facade.PISTON_PROFILE if selected_profile==Facade.PISTON_PROFILE.id else Facade.LEGACY_PROFILE
	if source.model_identity!=profile: return {}
	var pose: Dictionary=facade.visual_pose()
	return source if pose.valid and pose.session_id==adopted_session_id else {}

func _views_entry_source() -> Dictionary:
	if mapper==null or not menu_open or menu==null or not menu.visible or views_panel==null: return {}
	if views_open or taxi_open or audio_open or first_flight_open or scan_open or route_open or review_open or not archive_operation.is_empty() or not pending_discard.is_empty(): return {}
	if (controls_panel!=null and controls_panel.visible) or (wind_panel!=null and wind_panel.visible): return {}
	if engine_pointer_look_active or not engine_pointer_terminal.is_empty() or Input.mouse_mode!=Input.MOUSE_MODE_VISIBLE: return {}
	if mapper.pointer_view().capture!=null or not mapper.get("_pointer_pending").is_empty(): return {}
	if engine_controls!=null and not engine_controls.get("_capture").is_empty(): return {}
	return _views_current_source()

func _views_cancel_event(event: InputEvent) -> bool:
	# Read-only UI press admission. Do not sample Mapper or record a previously
	# unseen gamepad button in connection history merely to cancel this page.
	if event is InputEventKey:
		if not event.pressed or event.echo: return false
		if event.physical_keycode==KEY_ESCAPE: return true
	elif event is InputEventJoypadButton:
		if not event.pressed: return false
		if event.is_action_pressed("ui_cancel"): return true
	else: return false
	var checked: Dictionary=Preset.validate_preset_v2(active_preset) if piston_mode() else Preset.validate_preset(active_preset)
	if not checked.ok: return false
	for action in checked.value.actions:
		if action.id!="pause_menu": continue
		for source in action.sources:
			if event is InputEventKey and source.kind=="physical_keys" and event.physical_keycode in source.keys: return true
			if event is InputEventJoypadButton and source.kind=="joy_button" and source.index==event.button_index and selected_slots.has(source.slot):
				var selected: Dictionary=selected_slots[source.slot]
				if selected.device==event.device and device_connections.has(selected.device) and device_connections[selected.device].generation==selected.generation: return true
	return false

func open_views() -> bool:
	var source: Dictionary=_views_entry_source()
	if source.is_empty(): return false
	var widget: Control=views_panel
	if not widget.open(camera_view_settings(),adopted_session_id): return false
	# A fresh reference token distinguishes two openings in the same session.
	var opening: Dictionary={"active":true,"session":adopted_session_id,"token":RefCounted.new()}
	_views_opening=opening
	_views_callback=func(settings: Dictionary, source_session: Variant): _on_view_settings(settings,source_session,widget,opening)
	_views_dismiss_callback=func(source_session: Variant):
		if _views_request_valid(source_session,widget,opening): dismiss_views()
	widget.apply_requested.connect(_views_callback)
	widget.cancel_requested.connect(_views_dismiss_callback)
	views_open=true
	menu.hide()
	widget.focus_cancel()
	return true

func _views_request_valid(source_session: Variant, widget: Control, opening: Dictionary) -> bool:
	if typeof(source_session)!=TYPE_STRING or source_session.is_empty(): return false
	if not opening.get("active",false) or _views_opening.is_empty() or opening.get("token")!=_views_opening.get("token"): return false
	if not views_open or widget!=views_panel or not widget.is_visible_in_tree() or not menu_open: return false
	if source_session!=opening.get("session") or source_session!=adopted_session_id: return false
	if not archive_operation.is_empty() or not pending_discard.is_empty(): return false
	if taxi_open or audio_open or first_flight_open or scan_open or route_open or review_open: return false
	if (controls_panel!=null and controls_panel.visible) or (wind_panel!=null and wind_panel.visible): return false
	if engine_pointer_look_active or not engine_pointer_terminal.is_empty() or Input.mouse_mode!=Input.MOUSE_MODE_VISIBLE or mapper==null: return false
	if mapper.pointer_view().capture!=null or not mapper.get("_pointer_pending").is_empty(): return false
	if engine_controls!=null and not engine_controls.get("_capture").is_empty(): return false
	return not _views_current_source().is_empty()

func _on_view_settings(value: Variant, source_session: Variant, widget: Control, opening: Dictionary) -> void:
	if not _views_request_valid(source_session,widget,opening): return
	var checked: Dictionary=ViewPolicy.validate(value)
	if not checked.ok:
		widget.set_error(checked.error)
		return
	var description: Dictionary=ViewPolicy.describe(checked.value.preset)
	# Inherited resets belong only to a real traditional-mode transition.
	# Within mode0 keep manually requested aids/visibility exactly as they were.
	if description.mode!=camera_mode: super.set_camera_mode(description.mode)
	view_settings=checked.value.duplicate(true)
	camera.fov=view_settings.fov_deg
	look_angles=Vector2.ZERO
	camera_ready=false
	dismiss_views()

func retire_views_panel() -> void:
	if not _views_opening.is_empty(): _views_opening.active=false
	_views_opening={}
	if views_panel!=null:
		if _views_callback.is_valid() and views_panel.apply_requested.is_connected(_views_callback): views_panel.apply_requested.disconnect(_views_callback)
		if _views_dismiss_callback.is_valid() and views_panel.cancel_requested.is_connected(_views_dismiss_callback): views_panel.cancel_requested.disconnect(_views_dismiss_callback)
		views_panel.retire()
	_views_callback=Callable()
	_views_dismiss_callback=Callable()
	views_open=false

func dismiss_views() -> void:
	if not views_open: return
	retire_taxi_panel()
	retire_views_panel()
	menu_open=true
	menu.show()
	if views_button!=null: views_button.grab_focus()

func _observe_views_source() -> void:
	if not views_open: return
	var source_valid: bool=not _views_current_source().is_empty()
	if not source_valid or views_panel==null or not views_panel.is_visible_in_tree():
		retire_taxi_panel()
		retire_views_panel()
		# Source loss grants no pause/resume action, just an honest menu.
		menu_open=true
		if menu!=null:
			menu.show()
			menu_title.text="Flight paused" if source_valid else "View source changed Â· inspect current flight"
			resume_button.disabled=not source_valid

func _taxi_foreign() -> bool:
	return not Thread.is_main_thread() or OS.get_thread_caller_id()!=_taxi_owner

func _taxi_entry_source() -> Dictionary:
	if _taxi_foreign() or taxi_navigation==null or taxi_panel==null or _taxi_layout.is_empty(): return {}
	if taxi_open or views_open or audio_open or first_flight_open or scan_open or route_open or review_open: return {}
	if not archive_operation.is_empty() or not pending_discard.is_empty(): return {}
	if (controls_panel!=null and controls_panel.visible) or (wind_panel!=null and wind_panel.visible): return {}
	if mapper==null or engine_pointer_look_active or not engine_pointer_terminal.is_empty(): return {}
	if Input.mouse_mode!=Input.MOUSE_MODE_VISIBLE or mapper.pointer_view().capture!=null or not mapper.get("_pointer_pending").is_empty(): return {}
	if engine_controls!=null and not engine_controls.get("_capture").is_empty(): return {}
	return _views_current_source()

func open_taxi() -> bool:
	if selected_world!="original-synthetic":
		status="Synthetic taxi itineraries are unavailable at KAWO"
		return false
	if _taxi_foreign() or legacy_proof or taxi_navigation==null or taxi_panel==null or facade==null: return false
	if taxi_open or views_open or audio_open or first_flight_open or scan_open or route_open or review_open or quitting or initializing_recording: return false
	if not archive_operation.is_empty() or not pending_discard.is_empty(): return false
	if (controls_panel!=null and controls_panel.visible) or (wind_panel!=null and wind_panel.visible): return false
	# Only live entry performs the ordinary explicit pause/release transaction.
	# An already paused page entry never samples input or calls the worker.
	if not paused: open_menu("Flight paused")
	var source: Dictionary=_taxi_entry_source()
	if source.is_empty(): return false
	var view: Variant=taxi_navigation.observe(source)
	var widget: Control=taxi_panel
	if not widget.open(_taxi_layout,view,adopted_session_id): return false
	var opening: Dictionary={"active":true,"session":adopted_session_id,"token":RefCounted.new()}
	_taxi_opening=opening
	_taxi_callbacks={
		"route_requested":func(id: Variant, session: Variant): _on_taxi_request("choose",id,session,widget,opening),
		"next_requested":func(session: Variant): _on_taxi_request("next",null,session,widget,opening),
		"stop_requested":func(session: Variant): _on_taxi_request("stop",null,session,widget,opening),
		"aids_requested":func(value: Variant, session: Variant): _on_taxi_request("aids",value,session,widget,opening),
		"dismissed":func(session: Variant):
			if _taxi_request_valid(session,widget,opening): dismiss_taxi()
	}
	for signal_name in _taxi_callbacks: widget.connect(signal_name,_taxi_callbacks[signal_name])
	taxi_open=true
	menu_open=true
	menu.hide()
	widget.focus_back()
	return true

func _taxi_request_valid(session: Variant, widget: Control, opening: Dictionary) -> bool:
	if _taxi_foreign() or typeof(session)!=TYPE_STRING or session.is_empty(): return false
	if not opening.get("active",false) or _taxi_opening.is_empty() or opening.get("token")!=_taxi_opening.get("token"): return false
	if not taxi_open or widget!=taxi_panel or not widget.is_visible_in_tree() or not menu_open: return false
	if session!=opening.get("session") or session!=adopted_session_id or taxi_navigation==null: return false
	if views_open or audio_open or first_flight_open or scan_open or route_open or review_open: return false
	if not archive_operation.is_empty() or not pending_discard.is_empty(): return false
	if (controls_panel!=null and controls_panel.visible) or (wind_panel!=null and wind_panel.visible): return false
	return not _views_current_source().is_empty()

func _on_taxi_request(action: String, value: Variant, session: Variant, widget: Control, opening: Dictionary) -> void:
	if not _taxi_request_valid(session,widget,opening): return
	var source: Dictionary=_views_current_source()
	var result: Dictionary
	match action:
		"choose": result=taxi_navigation.choose(value,source)
		"next": result=taxi_navigation.next(source)
		"stop": result=taxi_navigation.stop(source)
		"aids": result=taxi_navigation.set_aids_visible(value,source)
		_: return
	widget.present(result.view)
	# A deliberate Begin is the sole synchronization point for runway selection.
	if action=="choose" and result.ok and result.view.runway!=null:
		flight_map.select_runway(result.view.runway)
	publish_taxi_navigation()

func retire_taxi_panel() -> void:
	if _taxi_foreign(): return
	if not _taxi_opening.is_empty(): _taxi_opening.active=false
	_taxi_opening={}
	if taxi_panel!=null:
		for signal_name in _taxi_callbacks:
			var callback: Callable=_taxi_callbacks[signal_name]
			if taxi_panel.is_connected(signal_name,callback): taxi_panel.disconnect(signal_name,callback)
		taxi_panel.retire()
	_taxi_callbacks.clear()
	taxi_open=false

func dismiss_taxi() -> void:
	if _taxi_foreign() or not taxi_open: return
	retire_taxi_panel()
	menu_open=true
	if menu!=null: menu.show()
	if taxi_button!=null: taxi_button.grab_focus()

func publish_taxi_navigation() -> void:
	if _taxi_foreign(): return
	var source: Dictionary=facade.readback() if facade!=null else {}
	var view: Variant=taxi_navigation.observe(source) if taxi_navigation!=null else null
	if flight_map!=null: flight_map.set_taxi_navigation(view)
	if _taxi_marker!=null:
		var available: bool=view!=null and view.qualified and view.available and view.aids_visible
		_taxi_marker.visible=available
		if available:
			var point: Array=view.target_eus_m
			_taxi_marker.position=Vector3(float(point[0]),float(point[1]),float(point[2]))
			_taxi_marker.get_node("ReferenceLabel").text="SYNTHETIC REFERENCE\n"+view.target_label
	if not taxi_open: return
	if view==null or not view.qualified or not view.paused or view.session_id!=_taxi_opening.get("session"):
		retire_taxi_panel()
		menu_open=true
		if menu!=null:
			menu.show()
			menu_title.text="Taxi source changed Â· inspect current flight"
			resume_button.disabled=true
	elif taxi_panel!=null: taxi_panel.present(view)

func set_audio_options(value: Variant) -> bool:
	if views_open or taxi_open: return false
	var checked: Dictionary=AudioOptions.validate(value)
	if not checked.ok: return false
	if sound!=null and not sound.set_options(checked.value): return false
	audio_options=checked.value.duplicate(true)
	audio_enabled=audio_options.enabled
	_player_seed.audio=audio_options.duplicate(true)
	_notify_player_options()
	if audio_open and facade!=null:
		audio_panel.set_context(AudioCues.from_readback(facade.readback()),audio_options)
	return true

func _audio_entry_source() -> Dictionary:
	if legacy_proof or facade==null or mapper==null or initializing_recording or quitting or not paused or not menu_open or menu==null or not menu.visible: return {}
	if views_open or taxi_open or audio_open or first_flight_open or scan_open or route_open or review_open or not archive_operation.is_empty() or not pending_discard.is_empty(): return {}
	if (controls_panel!=null and controls_panel.visible) or (wind_panel!=null and wind_panel.visible): return {}
	if engine_pointer_look_active or not engine_pointer_terminal.is_empty() or Input.mouse_mode==Input.MOUSE_MODE_CAPTURED: return {}
	if mapper.pointer_view().capture!=null or not mapper.get("_pointer_pending").is_empty(): return {}
	if engine_controls!=null and not engine_controls.get("_capture").is_empty(): return {}
	var source: Dictionary=facade.readback()
	var cues: Dictionary=AudioCues.from_readback(source)
	return source if cues.state=="paused" and cues.session_id==adopted_session_id and cues.profile_id==selected_profile else {}

func open_audio() -> void:
	var source: Dictionary=_audio_entry_source()
	if source.is_empty() or audio_panel==null: return
	if not audio_panel.set_context(AudioCues.from_readback(source),audio_options): return
	var opening: Dictionary={"active":true,"session":adopted_session_id}
	var widget: Control=audio_panel
	_audio_opening=opening
	_audio_callback=func(options: Dictionary, source_session: String): _on_audio_options(options,source_session,widget,opening)
	_audio_dismiss_callback=func():
		if opening.active and audio_open and widget==audio_panel: dismiss_audio()
	widget.options_requested.connect(_audio_callback)
	widget.dismissed.connect(_audio_dismiss_callback)
	audio_open=true
	menu.hide()
	widget.show()
	widget.focus_back()
	_bind_player_save(widget)

func _on_audio_options(value: Variant, source_session: String, widget: Control, opening: Dictionary) -> void:
	if not opening.get("active",false) or not audio_open or widget!=audio_panel or not widget.is_visible_in_tree() or not menu_open: return
	if source_session!=opening.get("session") or source_session!=adopted_session_id or initializing_recording or not archive_operation.is_empty() or not pending_discard.is_empty() or facade==null: return
	var source: Dictionary=facade.readback()
	var cues: Dictionary=AudioCues.from_readback(source)
	if not paused or cues.state!="paused" or cues.session_id!=source_session or cues.profile_id!=selected_profile: return
	set_audio_options(value)

func retire_audio_panel() -> void:
	_retire_player_save(audio_panel)
	if not _audio_opening.is_empty(): _audio_opening.active=false
	_audio_opening={}
	if audio_panel!=null:
		if _audio_callback.is_valid() and audio_panel.options_requested.is_connected(_audio_callback): audio_panel.options_requested.disconnect(_audio_callback)
		if _audio_dismiss_callback.is_valid() and audio_panel.dismissed.is_connected(_audio_dismiss_callback): audio_panel.dismissed.disconnect(_audio_dismiss_callback)
		audio_panel.hide()
	_audio_callback=Callable()
	_audio_dismiss_callback=Callable()
	audio_open=false

func dismiss_audio() -> void:
	if not audio_open: return
	retire_audio_panel()
	menu_open=true
	menu.show()
	if audio_button!=null: audio_button.grab_focus()

func fail(message: String) -> bool:
	if not legacy_proof:
		retire_taxi_panel()
		retire_views_panel()
		retire_audio_panel()
		if sound!=null: sound.observe({})
	return super.fail(message)

func open_controls() -> void:
	if views_open or taxi_open: return
	if audio_open: return
	if not archive_operation.is_empty(): return
	if controls_panel==null or facade==null:
		return
	if not paused and not pause_session(true):
		return
	if facade.readback().host_mode!="paused":
		return
	retire_first_flight()
	if not controls_panel.visible: invalidate_engine_pointer("Controls opened")
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
	_bind_player_save(controls_panel)

func open_wind() -> void:
	if views_open or taxi_open: return
	if audio_open: return
	if legacy_proof or wind_panel==null or facade==null or not archive_operation.is_empty() or not pending_discard.is_empty(): return
	if review_open or scan_open or route_open or (controls_panel!=null and controls_panel.visible): return
	if not review_boundary():
		status="Pause the flight before choosing a wind draft"
		return
	if not wind_panel.visible: invalidate_engine_pointer("Wind chooser opened")
	menu_open=true
	menu.hide()
	Input.mouse_mode=Input.MOUSE_MODE_VISIBLE
	wind_panel.open(wind_draft,current_wind_profile,WindCue.from_readback(facade.readback()),review_boundary())

func select_wind_draft(value: Variant) -> void:
	if views_open or taxi_open: return
	if not Facade.valid_wind_profile(value) or not archive_operation.is_empty() or not pending_discard.is_empty(): return
	wind_draft=value

func start_wind_draft(start: String) -> void:
	if views_open or taxi_open: return
	if wind_panel==null or not wind_panel.visible: return
	if selected_profile==Facade.PISTON_PROFILE.id:
		if start!="ground-ready" and start!="piston-cold-ground":
			status="Cold piston has no airborne start; current flight retained"
			return
		start="piston-cold-ground"
	request_discard("restart",start,wind_draft,selected_profile)

func dismiss_wind() -> void:
	if views_open or taxi_open: return
	if wind_panel==null or not wind_panel.visible or not pending_discard.is_empty(): return
	wind_panel.hide()
	open_menu("Wind draft retained Â· current flight paused")
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
		if selected_world=="kawo-prototype-v1":
			wind_label.text="KAWO prototype | "+cue.state+" | calm wind\nDecorative trees; not surveyed obstacles"
		# Geometry is assigned once, after final map/current-state publication.
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
	if views_open or taxi_open: return
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
	_player_seed["piston_input" if piston_mode() else "legacy_input"]=active_preset.duplicate(true)
	_notify_player_options()
	_retire_player_save(controls_panel)
	controls_selection_backup.clear()
	input_blocked=false
	input_problem="Preset applied; release centered controls and confirm Resume"
	brake_hold=mapper.sample(collect_input_raw(),0).brake_hold
	controls_panel.hide()
	open_menu("Controls applied Â· guest preset")

func dismiss_controls() -> void:
	_retire_player_save(controls_panel)
	if views_open or taxi_open: return
	if not archive_operation.is_empty(): return
	selected_slots=controls_selection_backup.duplicate(true)
	controls_selection_backup.clear()
	controls_panel.hide()
	open_menu("Flight paused")

func select_controller() -> void:
	if legacy_proof: super.select_controller()
	else: open_controls()

func start_flight(start: String) -> void:
	if _player_transition: return
	if views_open or taxi_open: return
	if legacy_proof:
		super.start_flight(start)
		return
	if selected_profile==Facade.PISTON_PROFILE.id:
		if start=="airborne-prepared":
			status="This piston prototype supports a cold ground start; the current session is retained"
			return
		if start=="ground-ready": start="piston-cold-ground"
	request_discard("restart",start,wind_draft,selected_profile)

func perform_start(start: String, selected_wind: Variant=null, requested_profile: Variant=null, first_flight_continuation: bool=false, requested_world: Variant=null) -> void:
	if _player_transition: return
	if views_open or taxi_open: return
	if audio_open: return
	if not archive_operation.is_empty(): return
	var next_profile: Variant=selected_profile if requested_profile==null else requested_profile
	var profile_changed: bool=next_profile!=selected_profile
	# restart validates before close and commits selection only after adoption.
	if restart(true,selected_wind,next_profile,start,requested_world):
		if wind_panel!=null: wind_panel.hide()
		if controls_panel!=null: controls_panel.hide()
		if observed_panel!=null: observed_panel.set_open(false)
		review_open=false
		clear_imported_review()
		open_menu("Fresh flight Â· confirm controls")
		if first_flight_continuation:
			open_first_flight()
			return
		# A new profile requires an explicit paused Controls/Resume decision.
		if not profile_changed and selected_world!="kawo-prototype-v1": close_menu()
	else:
		if not _player_restart_after_history.is_empty():
			_player_restart_after_history["first_flight"]=first_flight_continuation
			return
		if first_flight_continuation:
			# A failure after close cannot truthfully retain the old live flight.
			var failure: String=status
			open_menu("Flight setup failed Â· inspect current state")
			menu_message.text=failure.left(1024)
			open_first_flight()
		else:
			open_menu("Restart failed Â· recorded flight retained")

func first_flight_source_session() -> String:
	if facade==null: return ""
	var current: Dictionary=facade.readback()
	var readings: Dictionary=NativeReadings.from_readback(current)
	if readings.state not in ["live","paused"] or readings.session_id!=adopted_session_id: return ""
	return readings.session_id

func first_flight_request_valid(widget: Object, source_session: String) -> bool:
	if views_open or taxi_open: return false
	if widget!=first_flight_panel and widget!=circuit_card: return false
	if first_flight_panel==null or not first_flight_panel.visible or not first_flight_open or not menu_open: return false
	if not archive_operation.is_empty() or initializing_recording or not pending_discard.is_empty(): return false
	if not review_boundary(): return false
	var current: Dictionary=facade.readback() if facade!=null else {}
	var readings: Dictionary=NativeReadings.from_readback(current)
	if readings.state in ["live","paused"]:
		return readings.session_id==adopted_session_id and source_session==readings.session_id
	# A failed post-close replacement may expose joined closed truth, never
	# a retained/historical or malformed publication masquerading as no session.
	return NativeReadings._validate(current).is_empty() and current.host_mode=="closed" and not current.native_live and review_joined and source_session.is_empty()

func retire_first_flight() -> void:
	first_flight_open=false
	if first_flight_panel!=null: first_flight_panel.hide()

func open_first_flight() -> void:
	if views_open or taxi_open: return
	if audio_open: return
	if legacy_proof or first_flight_panel==null or initializing_recording or not archive_operation.is_empty() or not pending_discard.is_empty(): return
	if review_open or scan_open or route_open or (controls_panel!=null and controls_panel.visible) or (wind_panel!=null and wind_panel.visible): return
	if not ensure_review_boundary(): return
	# Already-paused opening never reseeds the mapper or emits another pause.
	# Ordinary live-to-pause already retires captures. Do not increment the
	# pointer generation again merely by opening an already-paused display.
	if mapper!=null and mapper.pointer_view().capture!=null: invalidate_engine_pointer("First flight opened")
	menu_open=true
	menu.hide()
	Input.mouse_mode=Input.MOUSE_MODE_VISIBLE
	first_flight_open=true
	var current: Dictionary=facade.readback() if facade!=null else {}
	first_flight_panel.set_state(current.duplicate(true),active_preset.duplicate(true),current_wind_profile)
	if circuit_checkbox!=null: circuit_checkbox.set_pressed_no_signal(circuit_aid_enabled)
	if circuit_checkbox!=null:
		circuit_checkbox.disabled=selected_world!="original-synthetic"
		circuit_checkbox.tooltip_text="Synthetic runway36 circuit only; unavailable at KAWO" if selected_world!="original-synthetic" else ""
	first_flight_panel.show()
	first_flight_panel.focus_back()

func dismiss_first_flight() -> void:
	if not first_flight_open or not archive_operation.is_empty() or not pending_discard.is_empty(): return
	retire_first_flight()
	# Return to the existing explicit Resume control, without any lifecycle call.
	menu_open=true
	menu_title.text="Flight paused"
	menu.show()
	resume_button.grab_focus()

func on_first_flight_back(source_session: String, widget: Object) -> void:
	if widget==first_flight_panel and first_flight_request_valid(widget,source_session): dismiss_first_flight()

func on_first_flight_controls(source_session: String, widget: Object) -> void:
	if widget==first_flight_panel and first_flight_request_valid(widget,source_session): open_controls()

func on_first_flight_choice(choice_id: String, source_session: String, widget: Object) -> void:
	if widget!=first_flight_panel or not first_flight_request_valid(widget,source_session): return
	var choice: Dictionary=FirstFlightPanel.apron_choice_for(choice_id) if choice_id in FirstFlightPanel.APRON_CHOICE_IDS else FirstFlightPanel.choice_for(choice_id)
	if choice.is_empty(): return
	var profile: Variant=choice.get("model_identity")
	if profile!=Facade.LEGACY_PROFILE and profile!=Facade.PISTON_PROFILE: return
	if choice.get("wind")!="calm": return
	# The normal admission/discard/replacement spine validates before close.
	request_discard("restart",choice.named_start,"calm",profile.id,true)

func on_circuit_enabled(enabled: bool, source_session: String, widget: Object) -> void:
	if not first_flight_request_valid(widget,source_session): return
	if selected_world!="original-synthetic":
		clear_circuit_reference("Synthetic circuit is unavailable at KAWO")
		return
	circuit_aid_enabled=enabled
	if circuit_checkbox!=null: circuit_checkbox.set_pressed_no_signal(enabled)
	publish_circuit_reference()

func clear_circuit_reference(reason: String) -> void:
	var view: Dictionary=CircuitGeometry.unavailable(reason)
	if flight_map!=null: flight_map.set_circuit_reference(view)
	if circuit_card!=null:
		circuit_card.set_state(view,circuit_aid_enabled)
		circuit_card.hide()
	if landmark_board!=null:
		landmark_board.set_summary_in_map(false)
		# ADR019 assigns the dock once from the final ordinary layout. Toggling
		# wrapped labels through the old undocked size on every unavailable draw
		# repeatedly invalidates their deferred minimum-size calculation.

func publish_circuit_reference() -> void:
	if circuit_card==null or flight_map==null: return
	if selected_world!="original-synthetic":
		clear_circuit_reference("Synthetic circuit is unavailable at KAWO")
		layout_live_flight_aids()
		return
	var view: Dictionary=CircuitGeometry.unavailable("Aid off")
	if circuit_aid_enabled:
		if facade==null or adopted_session_id.is_empty():
			view=CircuitGeometry.unavailable("Current flight unavailable")
		else:
			var current: Dictionary=facade.readback()
			view=CircuitGeometry.view(current,current_wind_profile,int(flight_map.get("_runway"))) if current.get("session_id")==adopted_session_id and not blocked and not stalled else CircuitGeometry.unavailable("Current flight unavailable")
	flight_map.set_circuit_reference(view)
	circuit_card.set_state(view,circuit_aid_enabled)
	circuit_card.visible=circuit_aid_enabled and not menu_open
	layout_live_flight_aids()

func layout_live_flight_aids() -> void:
	# ADR019: one final layout per publication, independent of gaze/physics.
	if legacy_proof or flight_map==null or circuit_card==null: return
	update_engine_controls()
	var viewport_size: Vector2=get_viewport().get_visible_rect().size
	var width: float=clampf(viewport_size.x/6.0,250.0,360.0)
	var current: bool=flight_map.get("_valid") and not flight_map.get("_retained")
	var top: float=92.0 if current else 124.0
	var side_x: float=viewport_size.x-width-14.0 if camera_mode==3 else 14.0
	var ordinary: bool=pointer_modal_free()
	var stack_bottom: float=top
	var left_bottom: float=top
	var outside: bool=camera_mode not in [0,3]
	flight_map.compact_aid_layout=true
	if engine_controls!=null and engine_controls.visible:
		var engine_height: float=216.0 if engine_controls.is_expanded() else 30.0
		var target: Rect2=Rect2(side_x,top,width,engine_height)
		# Geometry retirement precedes mapping changes and preserves real Raw rearm.
		# Repeated layouts cannot change mapper generations or manufacture release.
		if engine_controls.get_rect()!=target and mapper!=null and mapper.pointer_view().get("capture")!=null:
			invalidate_engine_pointer("Engine controls layout changed")
			update_engine_controls()
		engine_controls.size.x=width
		engine_controls.position=target.position
		engine_controls.size=target.size
		stack_bottom=target.end.y
		left_bottom=stack_bottom
	var available_circuit: bool=circuit_aid_enabled and circuit_card.get("_view").get("available")==true
	circuit_card.visible=circuit_aid_enabled and ordinary
	if available_circuit and circuit_card.visible:
		circuit_card.set_compact_unavailable(false)
		var circuit_y: float=(left_bottom+8.0 if left_bottom>top else top) if outside else (stack_bottom+8.0 if stack_bottom>top else top)
		circuit_card.position=Vector2(side_x,circuit_y)
		circuit_card.size.x=width
		circuit_card.size=Vector2(width,206.0)
		if outside: left_bottom=circuit_y+206.0
		else: stack_bottom=circuit_y+206.0
	elif circuit_card.visible:
		circuit_card.set_compact_unavailable(true)
		var notice: Rect2
		if camera_mode==0:
			notice=Rect2(width+28.0,224.0 if current else 250.0,viewport_size.x-width-42.0,32.0)
		elif camera_mode==3:
			notice=Rect2(14.0,viewport_size.y-93.0,viewport_size.x-width-38.0,32.0)
		else:
			notice=Rect2(width+22.0,top+152.0,viewport_size.x-2.0*width-44.0,32.0)
		# Publish width first: Godot's previous narrow minimum may be84 high.
		circuit_card.size.x=notice.size.x
		circuit_card.position=notice.position
		circuit_card.size=notice.size
	var map_x: float=viewport_size.x-width-14.0 if outside else side_x
	var map_y: float=top if outside else (stack_bottom+8.0 if stack_bottom>top else top)
	var map_height: float=220.0 if current else 188.0
	flight_map.position=Vector2(map_x,map_y)
	flight_map.size=Vector2(width,map_height)
	flight_map.queue_redraw()
	var summary_visible: bool=map_visible and flight_map.is_visible_in_tree() and flight_map.renders_manual_summary()
	if landmark_board!=null:
		landmark_board.set_card_dock(Rect2(map_x,map_y,width,188.0))
		landmark_board.set_summary_in_map(summary_visible)
	if map_visible and flight_map.is_visible_in_tree():
		if not outside: stack_bottom=map_y+map_height
	elif landmark_board!=null and landmark_board.get("_card").is_visible_in_tree():
		if not outside: stack_bottom=map_y+188.0
	if wind_card!=null:
		wind_card.visible=ordinary and camera_mode!=3
		wind_card.position=Vector2(width+28.0,top) if camera_mode==0 else Vector2(width+22.0,top)
		wind_card.size=Vector2(viewport_size.x-width-42.0,62.0) if camera_mode==0 else Vector2(viewport_size.x-2.0*width-44.0,50.0)
		wind_label.position=Vector2(6,6)
		wind_label.size=wind_card.size-Vector2(12,12)
	if panel!=null:
		var feedback: Rect2=Rect2()
		if piston_mode():
			if camera_mode==0: feedback=Rect2(width+28.0,162.0 if current else 194.0,viewport_size.x-width-42.0,54.0)
			elif camera_mode==3: feedback=Rect2(10.0,viewport_size.y-60.0,viewport_size.x-width-34.0,54.0)
			else: feedback=Rect2(width+22.0,top+58.0,viewport_size.x-2.0*width-44.0,86.0)
		panel.set_engine_feedback_bounds(feedback)
	# The cockpit texture has a different viewport; keep its existing fallback.
	if cockpit_panel!=null: cockpit_panel.set_engine_feedback_bounds(Rect2())
	if look_release_label!=null:
		var engine_footer: bool=engine_controls!=null and engine_controls.is_visible_in_tree() and engine_controls.is_expanded()
		look_release_label.visible=ordinary and not engine_footer
		look_release_label.position=Vector2(width+34.0,top+192.0) if outside else Vector2(side_x+8.0,stack_bottom)
		look_release_label.size=Vector2(viewport_size.x-2.0*width-68.0,14.0) if outside else Vector2(width-16.0,14.0)
		look_release_label.tooltip_text=look_release_hint()
		look_release_label.text=compact_look_release(look_release_label.size.x)

func configured_action_hint(id: String) -> Dictionary:
	# Copied configured aliases, never a connected-device/availability assertion.
	var short_sources: Array[String]=[]
	var full_sources: Array[String]=[]
	for action in active_preset.get("actions",[]):
		if action.get("id")!=id: continue
		for source in action.get("sources",[]):
			if source.get("kind")=="joy_button":
				short_sources.append("cfg %s:%s"%[source.get("slot"),source.get("index")])
				full_sources.append("CONFIGURED %s button %s (availability unverified; open Controls)"%[source.get("slot"),source.get("index")])
			else:
				var alias: String=pointer_source_hint(source)
				short_sources.append(alias)
				full_sources.append(alias)
	return {"short":short_sources[0]+(" +%d"%(short_sources.size()-1) if short_sources.size()>1 else "") if not short_sources.is_empty() else "unbound",
		"full":" / ".join(full_sources) if not full_sources.is_empty() else "Binding unavailable; open Controls"}

func locator_binding_hints() -> Dictionary:
	return {"zoom_in":configured_action_hint("map_zoom_in"),"zoom_out":configured_action_hint("map_zoom_out"),"close":configured_action_hint("map_toggle")}

func look_release_hint() -> String:
	return "Look: "+configured_action_hint("look_hold").full+" Â· release to expose pointer; Escape pauses/menu; Controls: "+configured_action_hint("controls_panel").full

func compact_look_release(width: float) -> String:
	var alias: String=configured_action_hint("look_hold").full
	var prefix: String="Look: "
	var suffix: String=" Â· release to use"
	var font: Font=ThemeDB.fallback_font
	if font.get_string_size(prefix+alias+suffix,HORIZONTAL_ALIGNMENT_LEFT,-1,10).x<=width: return prefix+alias+suffix
	while not alias.is_empty():
		alias=alias.left(alias.length()-1)
		if font.get_string_size(prefix+alias+"â€¦"+suffix,HORIZONTAL_ALIGNMENT_LEFT,-1,10).x<=width: return prefix+alias+"â€¦"+suffix
	return prefix+"â€¦"+suffix

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
	for node in [airplane,world_root,light_root,_kawo_decoration_root]:
		if node!=null:
			node.hide()
	if cockpit.has("root"):
		cockpit.root.hide()

func show_state(seconds: float=0.0) -> void:
	if not legacy_proof: publish_taxi_navigation()
	if legacy_proof:
		super.show_state(seconds)
		return
	if facade==null:
		layout_flight_menu()
		_observe_audio({})
		_observe_views_source()
		clear_circuit_reference("Current flight unavailable")
		suppress_geometry()
		var closed_info: Dictionary={"blocked":true,"paused":true,"outcome":"discarded","locator_binding_hints":locator_binding_hints()}
		if panel!=null: publish_readings({},closed_info)
		update_wind_presentation({})
		if flight_map!=null:
			flight_map.set_state({},Vector3.ZERO,Basis.IDENTITY,closed_info)
		layout_live_flight_aids()
		return
	layout_flight_menu()
	_observe_views_source()
	var current: Dictionary=facade.readback()
	update_wind_presentation(current)
	if snapshot.is_empty() or current.aircraft==null or current.canonical==null:
		_observe_audio({})
		clear_circuit_reference("Current flight unavailable")
		suppress_geometry()
		if panel != null:
			var fault_info: Dictionary={"status":status,"outcome":"error","blocked":blocked,"stalled":stalled,"paused":paused,"input_name":active_preset.get("name","Controls")}
			fault_info.blocked=true
			fault_info.paused=true
			fault_info.locator_binding_hints=locator_binding_hints()
			publish_readings(current,fault_info)
			flight_map.call("set_state",snapshot,Vector3.ZERO,Basis.IDENTITY,fault_info)
		layout_live_flight_aids()
		return
	var truth: Dictionary=current
	var canonical: Dictionary=truth.canonical
	var native_basis: Basis=Frames.transform([0.0,0.0,0.0],canonical.body_to_anchor_eus).basis
	var raw: Array=canonical.anchor_eus_position_m
	var native_position:=Vector3(raw[0],raw[1],raw[2])
	var rendered: Dictionary=facade.visual_pose()
	if not rendered.valid:
		clear_circuit_reference("Current presentation unavailable")
		airplane.hide()
		cockpit.root.hide()
		world_root.hide()
		if is_instance_valid(_kawo_decoration_root): _kawo_decoration_root.hide()
		light_root.hide()
		status="PRESENTATION PAUSED | "+rendered.error+" | R resets"
		var fault_info: Dictionary={"status":status,"outcome":native_outcome,"historical":current.historical,"blocked":true,"stalled":stalled,"paused":true,"input_name":active_preset.get("name","Controls"),"clearance_m":plane_clearance,"ground_valid":ground_valid}
		fault_info.locator_binding_hints=locator_binding_hints()
		publish_readings(current,fault_info)
		flight_map.call("set_state",snapshot,native_position,native_basis,fault_info)
		layout_live_flight_aids()
		return
	world_root.show()
	if is_instance_valid(_kawo_decoration_root): _kawo_decoration_root.visible=selected_world=="kawo-prototype-v1"
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
		if camera_mode==0:
			match view_settings.preset:
				"forward_horizon": base_direction=Vector3(0,0,-1)
				"left_window","right_window":
					base_direction=Vector3(-1,0,0) if view_settings.preset=="left_window" else Vector3(1,0,0)
					gaze=Basis(Vector3.UP,-look_angles.x)*Basis(base_direction.cross(Vector3.UP),look_angles.y)
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
	if selected_world=="kawo-prototype-v1":
		var floor: Dictionary=world_root.camera_height(float(target_position.x),float(target_position.z))
		if not floor.ok:
			suppress_geometry()
			status="PRESENTATION PAUSED | "+floor.error
			return
		camera_floor=floor.height_m+0.35
		target_position.y=maxf(target_position.y,camera_floor)
		desired_offset=target_position-airplane.position
	if camera_mode in [0,3] or not camera_ready or paused or view_settings.external_response=="immediate":
		camera_follow_offset=desired_offset
	else:
		# Ease only the view offset; translation follows the same rendered pose.
		# Diagnostic/repeated show_state(0) calls cannot advance the camera filter.
		camera_follow_offset=camera_follow_offset.lerp(desired_offset,_camera_smooth_alpha(seconds))
	camera.position=airplane.position+camera_follow_offset
	if selected_world=="kawo-prototype-v1":
		var smoothed_floor: Dictionary=world_root.camera_height(float(camera.position.x),float(camera.position.z))
		if not smoothed_floor.ok:
			suppress_geometry()
			status="PRESENTATION PAUSED | "+smoothed_floor.error
			return
		camera_floor=smoothed_floor.height_m+0.35
		camera.position.y=maxf(camera.position.y,camera_floor)
	if camera_mode==2:
		camera.position.y=maxf(camera.position.y,camera_floor)
	camera_ready=true
	camera.look_at(look_target,up)
	if propeller!=null:
		if piston_mode():
			# Draw is read-only in time: pause/redraw cannot advance phase. Invalid
			# or fresh source uses the declared static reference, never old legacy angle.
			propeller.rotation.z=float(_propeller_phase.get("angle",0.0))
		elif not paused:
			propeller.rotate_z(clampf(seconds,0.0,0.25)*(25+float(held_controls.throttle)*65))
	var view_label: String=_camera_view_label()
	var input_name: String=active_preset.get("name","Controls")+" / guest"
	if not takeover_targets.is_empty():
		input_name+=" / match "+", ".join(takeover_targets)
	if not input_problem.is_empty():
		input_name+=" / "+input_problem
	var display_info: Dictionary={"status":status,"outcome":native_outcome,"historical":current.historical,"blocked":blocked,"stalled":stalled,"paused":paused,"brake_hold":brake_hold,"view_name":view_label,"clearance_m":plane_clearance,"ground_valid":ground_valid,"input_name":input_name,"input_label":"CONTROLS","audio_enabled":audio_enabled}
	display_info.locator_binding_hints=locator_binding_hints()
	publish_readings(current,display_info)
	flight_map.call("set_state",snapshot,native_position,native_basis,display_info)
	publish_circuit_reference()
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
	if selected_world!="original-synthetic":
		status="Synthetic landmark routes are unavailable at KAWO; use the compiled runway locator"
		return
	if views_open or taxi_open: return
	if audio_open: return
	if legacy_proof or facade==null or landmark_board==null:
		return
	if controls_panel!=null and controls_panel.visible:
		return
	if not paused and not pause_session(true):
		return
	var source: Dictionary=facade.readback()
	if source.host_mode!="paused":
		return
	if not route_open: invalidate_engine_pointer("Route chooser opened")
	scan_open=false
	menu_open=true
	route_open=true
	menu.hide()
	Input.mouse_mode=Input.MOUSE_MODE_VISIBLE
	publish_landmark_route(source)
	landmark_board.set_open(route_open)

func _route_edit_source() -> Dictionary:
	if views_open or taxi_open: return {}
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
	if views_open or taxi_open: return
	if landmark_board==null:
		return
	route_aids_visible=value
	landmark_board.set_aids_visible(value)
	if facade!=null:
		publish_landmark_route(facade.readback())

func dismiss_landmark_route() -> void:
	if views_open or taxi_open: return
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
	if views_open or taxi_open: return
	if audio_open: return
	# Selection belongs to an already paused menu. Never pauses native flight,
	# primes mapper edges, suppresses mouse bindings or changes the prior camera.
	if legacy_proof or facade==null or not paused or facade.readback().host_mode!="paused":
		return
	if controls_panel!=null and controls_panel.visible:
		return
	if not scan_open: invalidate_engine_pointer("Instrument scan opened")
	scan_open=true
	menu_open=true
	menu.hide()
	Input.mouse_mode=Input.MOUSE_MODE_VISIBLE
	show_state(0)

func dismiss_instrument_scan() -> void:
	if views_open or taxi_open: return
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
	if _player_transition: return
	if not _player_ui.is_empty() or not _player_exit.is_empty(): return
	if taxi_open: return
	if not archive_operation.is_empty(): return
	if not legacy_proof: retire_taxi_panel()
	if not legacy_proof: retire_views_panel()
	if not legacy_proof: retire_audio_panel()
	if not legacy_proof:
		if review_open: return
		if not pending_discard.is_empty(): return
		retire_first_flight()
		scan_open=false
		route_open=false
		if landmark_board!=null:
			landmark_board.set_open(false)
	super.open_menu(title)
	if not legacy_proof and facade==null:
		resume_button.disabled=true
		menu_message.text="No active flight. Choose a fresh start when ready."
	if not legacy_proof and profile_button!=null:
		profile_button.text="Aircraft: cold piston prototype  Â·  switch" if selected_profile==Facade.PISTON_PROFILE.id else "Aircraft: ready-to-fly prototype  Â·  switch"
	if world_button!=null:
		world_button.text="World: KAWO prototype  ·  switch to synthetic" if selected_world=="kawo-prototype-v1" else "World: synthetic airfield  ·  switch to KAWO"
		if piston_mode() and facade!=null:
			menu_message.text="Original piston prototype Â· idealized starter supply\nStart: brakes held, mixture rich, ignition both, hold starter.\nExpand ENGINE CONTROLS or use bindings in Controls (F7).\nRelease starter after firing; release mouse look to use the pointer.\nNative shaft RPM / combustion / switches are shown below.\nThis is an engineering interaction; no C172 procedure is claimed."

func close_menu() -> void:
	if _player_transition: return
	if not _player_ui.is_empty():
		_dismiss_player_ui()
		return
	if not _player_exit.is_empty(): return
	if not archive_operation.is_empty(): return
	if not legacy_proof and taxi_open:
		dismiss_taxi()
		return
	if not legacy_proof and views_open:
		dismiss_views()
		return
	if not legacy_proof and audio_open:
		dismiss_audio()
		return
	if not legacy_proof and not pending_discard.is_empty():
		cancel_discard()
		return
	if not legacy_proof and first_flight_open:
		dismiss_first_flight()
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
	if facade==null and not legacy_proof: return
	super.close_menu()

func restart_failed(message: String) -> bool:
	_dispose_world_candidate()
	retire_taxi_panel()
	retire_views_panel()
	retire_audio_panel()
	_observe_audio({})
	retire_first_flight()
	clear_circuit_reference("Flight setup failed")
	if facade!=null:
		var stopped: Dictionary=facade.close()
		review_joined=stopped.ok and not stopped.readback.native_live
		if stopped.ok: _retire_kawo_decoration()
		adopt_result(stopped)
		if not stopped.ok: message+="; failed setup worker join unconfirmed"
	initializing_recording=false
	var failed: bool=fail(message)
	# Publish the actual joined failure immediately. Waiting for the next draw
	# would leave the previous session's route card and map looking current.
	if panel!=null and flight_map!=null:
		var current: Dictionary=facade.readback() if facade!=null else {}
		var info: Dictionary={"status":status,"blocked":true,"paused":true,"historical":current.get("historical",false),"outcome":"error","locator_binding_hints":locator_binding_hints()}
		publish_readings(current,info)
		update_wind_presentation(current)
		flight_map.set_state({},Vector3.ZERO,Basis.IDENTITY,info)
		suppress_geometry()
		layout_live_flight_aids()
	return failed

func flight_model_root(profile_id: Variant=null) -> String:
	var profile: Variant=selected_profile if profile_id==null else profile_id
	var folder: String="piston-models" if profile==Facade.PISTON_PROFILE.id else "models"
	return ProjectSettings.globalize_path("res://"+folder) if OS.has_feature("editor") else OS.get_executable_path().get_base_dir().path_join(folder)

func observe_flight(readback: Dictionary) -> void:
	if legacy_proof or initializing_recording or observed_status.is_empty(): return
	var result: Dictionary=observed_recorder.observe(readback)
	if result.status!=null: observed_status=result.status
	if player_controller!=null: player_controller.flight_observed(readback,_player_utc())

func recorded_flight_advanced() -> bool:
	return not observed_status.is_empty() and observed_status.state!="empty" and observed_status.first_tick!=observed_status.last_observed_tick

func review_boundary() -> bool:
	if facade==null: return review_joined
	var state: Dictionary=facade.readback()
	return (state.host_mode=="paused" and state.native_live and state.paused and not state.historical) or (state.host_mode=="closed" and not state.native_live and review_joined)

func ensure_review_boundary() -> bool:
	if views_open or taxi_open: return false
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
	if views_open or taxi_open: return
	if audio_open: return
	if legacy_proof or observed_panel==null or not pending_discard.is_empty() or not archive_operation.is_empty(): return
	if controls_panel!=null and controls_panel.visible: return
	if not ensure_review_boundary():
		status="Review requires a verified pause or joined stop"
		return
	var record: Variant=observed_recorder.recording()
	if not observed_panel.set_recording(record):
		status="Recorded flight cannot be qualified for review"
		return
	# The verified pause already retired input. Retire only a real remaining
	# capture; opening a historical display cannot consume another generation.
	if mapper!=null and mapper.pointer_view().capture!=null: invalidate_engine_pointer("Flight review opened")
	archive_imported=false
	archive_message=""
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
	if views_open or taxi_open: return
	if not review_open or not pending_discard.is_empty() or not archive_operation.is_empty(): return
	observed_panel.set_open(false)
	review_open=false
	clear_imported_review()
	open_menu("Recorded flight retained Â· paused")

func clear_imported_review() -> void:
	if views_open or taxi_open: return
	# Dismiss releases imported copies without copying the current live history.
	if archive_imported and observed_panel!=null:
		observed_panel.set_recording(ObservedValues.empty_recording())
	archive_imported=false
	archive_message=""
	if observed_panel!=null: observed_panel.set_file_context(false)

func show_current_review() -> void:
	if views_open or taxi_open: return
	if not review_open or not archive_operation.is_empty() or not review_boundary(): return
	var current: Variant=observed_recorder.recording()
	if observed_panel.set_recording(current):
		archive_imported=false
		archive_message="Current paused flight. Save new review always saves this flight."
		observed_panel.set_file_context(false,archive_message)

func begin_archive_operation(action: String, show_dialog: bool=true) -> bool:
	if views_open or taxi_open: return false
	if audio_open: return false
	if legacy_proof or not review_open or not archive_operation.is_empty() or not pending_discard.is_empty() or not action in ["save","open"]: return false
	if initializing_recording or not review_boundary():
		archive_feedback("A verified pause or joined stop is required.")
		return false
	var bytes:=PackedByteArray()
	if action=="save":
		# Exactly one current snapshot, even while an imported file is displayed.
		var encoded: Dictionary=ArchiveCodec.encode(observed_recorder.recording())
		if not encoded.ok:
			archive_feedback("Review not saved: "+encoded.error)
			return false
		bytes=encoded.value.duplicate()
	if mapper!=null and mapper.pointer_view().capture!=null: invalidate_engine_pointer("Archive chooser opened")
	archive_operation={"action":action,"session_id":adopted_session_id,"bytes":bytes,"prior_message":archive_message,"prior_recent":FileDialog.get_recent_list(),"player_context":_recording_player_context.duplicate(true)}
	observed_panel.set_file_context(archive_imported,"Choose a new file." if action=="save" else "Choose a historical review file.",true)
	if show_dialog:
		archive_dialog.file_mode=FileDialog.FILE_MODE_SAVE_FILE if action=="save" else FileDialog.FILE_MODE_OPEN_FILE
		archive_dialog.title="Save new review â€” existing files are preserved" if action=="save" else "Open historical recorded review"
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
	var player_context: Dictionary=archive_operation.player_context.duplicate(true)
	var saved_recording: Dictionary={}
	if action=="save":
		var saved: Dictionary=ArchiveCodec.decode(archive_operation.bytes)
		if saved.ok: saved_recording=saved.value
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
		_archive_link_feedback.clear()
		if action=="save" and player_controller!=null and not saved_recording.is_empty() and not player_context.is_empty() and _recording_matches_source(saved_recording,player_context.source):
			var link: Dictionary={"type":"ExternalRecordedReview","version":1,"absolute_path":result.path,"payload_sha256":result.payload_sha256,"recording_session_id":saved_recording.metadata.session_id,"first_tick":saved_recording.metadata.first_tick,"last_tick":saved_recording.last_observed_tick,"linked_utc":_player_utc()}
			_archive_link_feedback={"practice_id":player_context.practice_id,"payload_sha256":result.payload_sha256}
			var association: Dictionary=player_controller.archive_saved(player_context.practice_id,link)
			_player_archive_link_changed(player_context.practice_id,association)
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

func _player_archive_link_changed(practice_id: String, state: Dictionary) -> void:
	# An old player's terminal must never label a different selected file saved.
	if _archive_link_feedback.is_empty() or _archive_link_feedback.practice_id!=practice_id or state.get("payload_sha256","")!=_archive_link_feedback.payload_sha256: return
	match state.get("state",""):
		"saved": archive_feedback("Review file saved. Its Practice association was acknowledged by storage.")
		"pending_endpoint": archive_feedback("Review file saved. Its Practice association waits for an ordinary flight observation or the actual closed endpoint; this flight remains paused.")
		"pending", "inflight": archive_feedback("Review file saved. Its Practice association is pending; storage has not acknowledged the link yet.")
		"unknown": archive_feedback("Review file saved. Its Practice association status is unknown; it will not be automatically retried. "+String(state.get("error","")))
		"failed": archive_feedback("Review file saved. Its Practice association was not acknowledged. "+String(state.get("error","")))

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
	discard_cancel.text="Cancel Â· keep recorded flight"
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

func request_discard(action: String, start: String="", selected_wind: Variant=null, requested_profile: Variant=null, first_flight_continuation: bool=false, requested_world: Variant=null) -> void:
	if _player_transition: return
	if views_open or taxi_open: return
	if audio_open: return
	if not archive_operation.is_empty(): return
	if not pending_discard.is_empty() or not action in ["restart","quit"]: return
	var next_profile: Variant=selected_profile if requested_profile==null else requested_profile
	var requested_wind: Variant=current_wind_profile if selected_wind==null else selected_wind
	var next_world: Variant=selected_world if requested_world==null else requested_world
	if action=="restart":
		if not Facade.valid_profile(next_profile):
			status="Invalid fresh profile; flight unchanged"
			return
		var selection_error: String=Facade._selection_error(flight_model_root(next_profile),start,requested_wind,next_profile,next_world)
		if not selection_error.is_empty():
			status=selection_error+"; flight unchanged"
			return
	if not recorded_flight_advanced():
		if action=="restart": perform_start(start,requested_wind,next_profile,first_flight_continuation,next_world)
		else: await perform_quit()
		return
	if not ensure_review_boundary():
		status="Cannot discard until native flight is paused or its worker has joined"
		return
	if not first_flight_continuation: invalidate_engine_pointer("Discard confirmation opened")
	pending_discard={"action":action,"start":start,"session_id":adopted_session_id,"wind_profile":requested_wind,"profile_id":next_profile,"world_selector":next_world}
	# This continuation belongs to this decision only. Cancel/stale/quit clears
	# it with the dictionary; ordinary restart behavior remains unchanged.
	if first_flight_continuation and action=="restart": pending_discard["first_flight"]=true
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
	if first_flight_open:
		first_flight_panel.focus_back()
	elif review_open:
		observed_panel.get("_back").grab_focus()
	elif controls_panel!=null and controls_panel.visible:
		pass
	elif wind_panel!=null and wind_panel.visible:
		wind_panel.get("_back").grab_focus()
	elif route_open or scan_open:
		pass
	else:
		open_menu("Recorded flight retained Â· paused")

func confirm_discard() -> void:
	if pending_discard.is_empty(): return
	if pending_discard.session_id!=adopted_session_id or not review_boundary():
		status="Discard request no longer matches the verified flight boundary"
		cancel_discard()
		return
	var decision: Dictionary=pending_discard.duplicate(true)
	pending_discard.clear()
	discard_layer.hide()
	if decision.action=="restart": perform_start(decision.start,decision.wind_profile,decision.profile_id,decision.get("first_flight")==true,decision.get("world_selector",selected_world))
	else: await perform_quit()

func quit_flight() -> void:
	if _player_transition: return
	if taxi_open: return
	if not legacy_proof:
		retire_taxi_panel()
		retire_views_panel()
		retire_audio_panel()
	if legacy_proof:
		await super.quit_flight()
	else:
		await request_discard("quit")

func perform_quit() -> void:
	if _player_transition: return
	if not archive_operation.is_empty(): return
	retire_taxi_panel()
	retire_views_panel()
	retire_audio_panel()
	retire_first_flight()
	clear_circuit_reference("Flight closing")
	await _quit_with_players()

func _exit_tree() -> void:
	retire_players_ui()
	for entry in _player_save_ui.values(): _retire_player_save(entry.widget)
	if player_controller!=null: player_controller.begin_close()
	quitting=true
	retire_taxi_panel()
	retire_views_panel()
	retire_audio_panel()
	invalidate_engine_pointer("Scene retired")
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
		observed_panel.get("_title").text="SYNTHETIC UI FIXTURE Â· gaps / unavailable fuel"
		observed_panel.set("_channel","fuel_total")
		observed_panel.get("_graph_choice").select(4)
		observed_panel.select_sample(2)
		await save_view(prefix+"-gap")
		var limited: RefCounted=ObservedRecorder.new()
		check(limited.begin(fixture.call("_source","0",0.0,0.0)).ok,"observed_visual_synthetic_limit_begin_"+str(index))
		check(limited.observe(fixture.call("_source","61",3.0,4.0)).ok,"observed_visual_synthetic_limit_sample_"+str(index))
		check(limited.observe(fixture.call("_source","144001",20.0,30.0)).ok,"observed_visual_synthetic_beyond_window_"+str(index))
		check(observed_panel.set_recording(limited.recording()),"observed_visual_synthetic_limit_record_"+str(index))
		observed_panel.get("_title").text="SYNTHETIC UI FIXTURE Â· sealed recording limit"
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

# ADR017 host routing. The panel is a copied display and gesture producer only.
func pointer_session_live() -> bool:
	if legacy_proof or facade==null or mapper==null or not piston_mode() or paused or input_blocked: return false
	var source: Dictionary=facade.readback()
	return source.get("host_mode")=="live" and source.get("native_live")==true and source.get("paused")==false and source.get("session_id")==adopted_session_id and mapper.pointer_view().session_id==adopted_session_id and pointer_modal_free()

func pointer_modal_free() -> bool:
	return not menu_open and not views_open and not taxi_open and not audio_open and not first_flight_open and not scan_open and not route_open and not review_open and archive_operation.is_empty() and pending_discard.is_empty() and (controls_panel==null or not controls_panel.visible) and (wind_panel==null or not wind_panel.visible)

func pointer_ui_eligible() -> bool:
	return pointer_session_live() and engine_pointer_rearm.is_empty() and not engine_pointer_look_active and Input.mouse_mode==Input.MOUSE_MODE_VISIBLE

func remember_pointer_rearm() -> void:
	if mapper==null: return
	var view: Dictionary=mapper.pointer_view()
	for button in view.rearm_buttons:
		if not button in engine_pointer_rearm: engine_pointer_rearm.append(button)
	if view.capture!=null and not view.capture.button in engine_pointer_rearm: engine_pointer_rearm.append(view.capture.button)
	engine_pointer_rearm.sort()

func observe_pointer_release(raw: Dictionary) -> void:
	# Call only after successful full mapper validation, never from a GUI up.
	for i in range(engine_pointer_rearm.size()-1,-1,-1):
		if not engine_pointer_rearm[i] in raw.mouse_buttons: engine_pointer_rearm.remove_at(i)

func invalidate_engine_pointer(reason: String) -> void:
	remember_pointer_rearm()
	engine_pointer_terminal.clear()
	if mapper!=null: mapper.invalidate_pointer(reason)
	if engine_controls!=null: engine_controls.invalidate_local(reason)

func on_engine_retired(reason: String, widget: Control) -> void:
	# An old widget/session must never retire a newer mapper capture.
	if quitting or widget!=engine_controls or mapper==null: return
	if engine_controls_session!=mapper.pointer_view().session_id: return
	# An already-paused, capture-free briefing may hide the copied widget. The
	# pause/lifecycle owner has already retired input; this paint transition is
	# not another input generation. Real captures always take the retirement path.
	if reason=="Engine controls hidden" and paused and mapper.pointer_view().capture==null: return
	invalidate_engine_pointer(reason)

func on_engine_denied(_control: String, reason: String, widget: Control) -> void:
	if widget==engine_controls and pointer_ui_eligible(): pause_for_input(reason)

func on_engine_gesture(gesture: Dictionary, widget: Control) -> void:
	if widget!=engine_controls or mapper==null: return
	# Old, fully valid terminal events are deliberately accepted inert by mapper.
	# Nonterminal requests require the same live, visible, no-modal UI owner.
	if gesture.get("phase") not in ["end","cancel"] and not pointer_ui_eligible():
		pause_for_input("Engine pointer is unavailable; release before Resume")
		return
	var result: Dictionary=mapper.queue_pointer(gesture)
	if not result.ok: pause_for_input(result.error)
	elif gesture.get("phase") in ["end","cancel"]:
		var view: Dictionary=mapper.pointer_view()
		if view.session_id==gesture.session_id and view.generation==gesture.generation and view.capture!=null and view.capture.token==gesture.token:
			engine_pointer_terminal=gesture.duplicate(true)
	update_engine_controls()

func pointer_button_binding(button: int) -> String:
	for binding in active_preset.get("axes",[])+active_preset.get("actions",[])+active_preset.get("systems",[]):
		for source in binding.get("sources",[binding]):
			if source.get("kind")=="mouse_button" and source.get("button")==button:
				return str(binding.get("id",binding.get("target","unknown")))
	return ""

func reconcile_pointer_release(raw: Dictionary) -> bool:
	if not piston_mode(): return true
	var checked: Dictionary=Preset.validate_raw(raw)
	# The ordinary mapper still performs all Raw/device validation atomically.
	if not checked.ok: return true
	var view: Dictionary=mapper.pointer_view()
	var capture: Variant=view.capture
	if capture==null or capture.button in checked.value.mouse_buttons: return true
	# A GUI terminal already queued must win; do not replace its final value.
	if engine_pointer_terminal.get("session_id")==view.session_id and engine_pointer_terminal.get("generation")==view.generation and engine_pointer_terminal.get("token")==capture.token: return true
	var terminal: Dictionary={"session_id":view.session_id,"generation":view.generation,"token":capture.token,"control":capture.control,"phase":"end" if capture.control=="engine.starter" else "cancel","button":capture.button,"value":false if capture.control=="engine.starter" else null}
	var result: Dictionary=mapper.queue_pointer(terminal)
	if not result.ok:
		pause_for_input(result.error)
		return false
	engine_pointer_terminal=terminal.duplicate(true)
	return true

func update_engine_controls() -> void:
	if engine_controls==null: return
	var shown: bool=not legacy_proof and piston_mode() and facade!=null and pointer_modal_free()
	engine_controls.visible=shown
	if not shown: return
	var view: Dictionary=mapper.pointer_view() if mapper!=null else {}
	if view.get("capture")==null or view.get("session_id")!=engine_pointer_terminal.get("session_id") or view.get("generation")!=engine_pointer_terminal.get("generation"):
		engine_pointer_terminal.clear()
	engine_controls_session=str(view.get("session_id",""))
	var reason: String=input_problem if input_blocked else str(view.get("error")) if not str(view.get("error","")).is_empty() else "Release left button before a fresh press" if not engine_pointer_rearm.is_empty() else "Release mouse look to use engine controls" if engine_pointer_look_active or Input.mouse_mode==Input.MOUSE_MODE_CAPTURED else "Paused / retained / unavailable Â· resume explicitly" if not pointer_ui_eligible() else ""
	engine_controls.set_state(view,engine_status,active_preset,pointer_ui_eligible(),reason,look_release_hint())

func pointer_source_hint(source: Dictionary) -> String:
	match source.get("kind"):
		"physical_keys":
			var names: PackedStringArray=[]
			for key in source.get("keys",[]): names.append(OS.get_keycode_string(int(key)))
			return "/".join(names)
		"mouse_button": return "Mouse "+str(source.get("button"))
		"joy_button": return "Button %s:%s"%[source.get("slot"),source.get("index")]
	return "Unavailable binding"

# Original MIT. Opt-in engineering observer. Reuse the existing cockpit observer's
# full snapshots, fresh PNG writer, target guard, output containment and joins.
# This private capture route never supplies its own independent pixel approval.
func run_cockpit_asset_visual() -> void:
	var runner := CockpitAssetVisualObserver.new()
	await runner.run(self)

class CockpitAssetVisualObserver extends "res://instrument_tests/cockpit_visual.gd":
	const AssetMatrix = preload("res://instrument_tests/cockpit_asset_visual.gd")
	const Policy = preload("res://camera/view_policy.gd")
	const Readings = preload("res://cockpit/instruments/native_readings.gd")
	const ScanLeaf = preload("res://cockpit/instruments/scan_panel.gd")
	var _context: String=""
	var _captures: Array[Dictionary]=[]
	var _interactions: Array[Dictionary]=[]
	var _restorations: Array[Dictionary]=[]

	func _truth() -> Dictionary:
		var value: Dictionary=super._truth()
		# This additional field is precisely the accepted three-field presentation
		# contract. Raw/Mapper, controls, commands, clocks/debt and origins remain.
		value.scene.erase("view_settings")
		value.copied_readings={"shared":_scene.shared_readings.duplicate(true),"overlay":_scene.panel.get("_readings").duplicate(true),"physical":_scene.cockpit_panel.get("_readings").duplicate(true),"scan":_scene.scan_panel.get("_reading_set").duplicate(true)}
		return value

	func _sources() -> Dictionary:
		var value: Dictionary=super._sources()
		for path: String in ["res://instrument_tests/cockpit_asset_visual.gd","res://instrument_tests/cockpit_asset_checks.gd","res://instrument_tests/cockpit_asset_baseline.gd","res://cockpit/assets/original_asset.gd","res://camera/view_policy.gd","res://ui/camera/views_panel.gd","res://cockpit/instruments/scan_panel.gd"]:
			value[path]={"bytes":FileAccess.get_file_as_bytes(path).size(),"sha256":FileAccess.get_sha256(path)}
		return value

	func _save_presentation() -> Dictionary:
		var saved: Dictionary=super._save_presentation()
		saved.settings=_scene.view_settings.duplicate(true)
		saved.scan_data=_data(_scene.scan_panel)
		saved.scan_visible=_scene.scan_panel.visible
		return saved

	func _restore_presentation(saved: Dictionary) -> void:
		super._restore_presentation(saved)
		_scene.view_settings=saved.settings.duplicate(true)
		_scene.show_state(0.0)
		for key: String in PRESENTATION: _scene.set(key,saved.fields[key])
		_scene.camera.transform=saved.camera
		_scene.camera.fov=saved.fov
		for key: String in saved.scan_data: _scene.scan_panel.set(key,saved.scan_data[key])
		_scene.scan_panel.visible=saved.scan_visible
		_scene.scan_panel.queue_redraw()

	func _pin(path: String) -> Dictionary:
		return {"path":path,"bytes":FileAccess.get_file_as_bytes(path).size(),"sha256":FileAccess.get_sha256(path)}

	func _shot(name: String,size: Vector2i,before: Dictionary,fixture: String="actual paused tick0",boundary: bool=false) -> bool:
		var path: String=_output.path_join(name+".png")
		if not _check(not FileAccess.file_exists(path),"fresh_png_"+name): return false
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
		var image: Image=_scene.get_viewport().get_texture().get_image()
		if not _check(image!=null and image.get_width()==size.x and image.get_height()==size.y,"actual_dimensions_"+name): return false
		if not _check(image.save_png(path)==OK,"png_written_"+name): return false
		var after: Dictionary=_truth()
		if not _check(var_to_bytes(before)==var_to_bytes(after),"full_truth_unchanged_"+name): return false
		var target: Dictionary=_target()
		# Outside is the unchanged production chase baseline: the physical panel
		# target is disabled there. Internal captures retain UPDATE_ALWAYS exactly.
		var expected_update: int=SubViewport.UPDATE_ALWAYS if _scene.camera_mode in [0,3] else SubViewport.UPDATE_DISABLED
		if not _check(target.size==[2048,1024] and target.texture_size==[2048,1024] and target.logical_size==[1024.0,512.0] and target.scale==[2.0,2.0] and target.anchors==[0.0,0.0,0.0,0.0] and target.update_mode==expected_update,"unchanged_panel_target_"+name): return false
		if not _check(_scene.camera.near==Vector3(0.1,0,0).x,"unchanged_near_clip_"+name): return false
		_views.append({"file":name+".png","bytes":FileAccess.get_file_as_bytes(path).size(),"sha256":FileAccess.get_sha256(path),"width":size.x,"height":size.y,"mode":_scene.camera_mode,"fov":_scene.camera.fov,"look":[_scene.look_angles.x,_scene.look_angles.y],"camera_transform":_scene.camera.transform,"near":_scene.camera.near,"eye":_scene.cockpit.eye,"panel_focus":_scene.cockpit.panel_focus,"target":target,"tick":before.readback.tick,"session_id":before.readback.session_id,"profile":before.readback.model_identity,"native_source_fingerprint":before.readback.native_source_fingerprint,"fixture":fixture,"reading_state":_scene.shared_readings.state,"boundary_view":boundary,"before_sha256":_digest(before),"after_sha256":_digest(after)})
		return true

	func _binary(label: String,value: Dictionary) -> Dictionary:
		var path: String=_output.path_join(label+".bin")
		if not _check(not FileAccess.file_exists(path),"fresh_binary_"+label): return {}
		var stream: FileAccess=FileAccess.open(path,FileAccess.WRITE)
		if not _check(stream!=null,"binary_open_"+label): return {}
		stream.store_buffer(var_to_bytes(value));stream.close()
		return _pin(path)

	func _actual_view(preset: String,fov: Variant=null) -> bool:
		var actual: String="chase" if preset=="outside" else preset
		var description: Variant=Policy.describe(actual)
		if not _check(description!=null,"known_preset_"+preset): return false
		# Exercise the existing paused Views request and its session/opening token.
		_scene.menu_open=true;_scene.menu.show()
		if not _check(_scene.open_views(),"actual_views_open_"+preset): return false
		var request: Dictionary={"preset":actual,"fov_deg":float(description.default_fov_deg) if fov==null else float(fov),"external_response":"smooth"}
		_scene.views_panel.apply_requested.emit(request,_scene.adopted_session_id)
		if not _check(not _scene.views_open and _scene.camera_view_settings()==request,"actual_views_applied_"+preset): return false
		_scene.menu_open=false;_scene.menu.hide()
		_scene.show_state(0.0)
		return true

	func _observe(row: Dictionary,before: Dictionary,joined: bool) -> bool:
		var label: String="asset-"+str(_captures.size()).pad_zeros(2)
		var after: Dictionary=_truth()
		if not _check(var_to_bytes(before)==var_to_bytes(after),"interaction_authority_equal_"+row.id): return false
		var proofs: Dictionary={"before":_binary(label+"-before",before),"after_interaction":_binary(label+"-after-interaction",after)}
		if proofs.before.is_empty() or proofs.after_interaction.is_empty(): return false
		if not await _shot(label,Vector2i(row.size[0],row.size[1]),after,str(row.display)): return false
		proofs.after_capture=_binary(label+"-after-capture",_truth())
		if proofs.after_capture.is_empty(): return false
		var actual: Dictionary=_views.back()
		var publication: Dictionary=_scene.facade.readback()
		var qualified: bool=Readings._validate(publication).is_empty() and publication.session_id==_scene.adopted_session_id and publication.tick=="0"
		qualified=qualified and ((row.display=="current" and publication.native_live and publication.paused and not publication.historical and _scene.shared_readings.state=="paused") or (row.display!="current" and joined and not publication.native_live and publication.historical and _scene.shared_readings.state==("invalid" if row.display=="explicitly_invalid" else "historical")))
		if not _check(qualified,"actual_publication_"+row.id): return false
		_captures.append({"fixture":row.duplicate(true),"image":_pin(_output.path_join(label+".png")),"actual_dimensions":[actual.width,actual.height],"qualified_publication":qualified,"joined_before_synthetic":joined})
		_interactions.append({"execution_index":_interactions.size(),"fixture_id":row.id,"binary_snapshots":proofs,"before_sha256":_digest(before),"after_interaction_sha256":_digest(after),"after_capture_sha256":_digest(_truth()),"actual_view":_scene.camera_view_settings(),"scan_selection":_scene.scan_panel.focused(),"native_source_fingerprint":publication.native_source_fingerprint,"session_id":publication.session_id,"tick":publication.tick})
		return true

	func _size_sequence(rows: Array[Dictionary],size: Vector2i) -> bool:
		if not _check(_scene.restart(true,"calm",Facade.LEGACY_PROFILE.id,"ground-ready"),"fresh_paused_session_"+str(size)): return false
		_scene.menu_open=false;_scene.menu.hide();_scene.map_visible=false;_scene.flight_map.hide()
		_scene.scan_open=false;_scene.scan_panel.clear_focus();_scene.scan_panel.hide()
		DisplayServer.window_set_size(size);_scene.get_viewport().size=size
		_scene.show_state(0.0)
		var saved: Dictionary=_save_presentation()
		var initial: Dictionary=_truth()
		var poses: Dictionary={}
		for row: Dictionary in rows:
			if row.display!="current": continue
			var before: Dictionary=_truth()
			_scene.scan_panel.clear_focus();_scene.scan_open=false;_scene.scan_panel.hide()
			_scene.menu_open=false;_scene.menu.hide()
			if not _actual_view("cockpit" if row.kind=="scan" else row.preset,row.fov): return false
			if row.kind=="scan":
				if not _check(_scene.scan_panel.focus(ScanLeaf.INSTRUMENTS[row.scan]),"actual_scan_focus_"+row.id): return false
				_scene.menu_open=false;_scene.menu.hide();_scene.scan_open=false;_scene.show_state(0.0)
			if row.kind=="default" and row.preset in ["cockpit","panel"]: poses[row.preset]=_save_presentation()
			if not await _observe(row,before,false): return false
		_restore_presentation(saved)
		var restored: Dictionary=_save_presentation()
		if not _check(restored==saved and var_to_bytes(initial)==var_to_bytes(_truth()),"exact_saved_view_and_authority_restored_"+str(size)): return false
		_restorations.append({"size":[size.x,size.y],"saved":saved,"restored":restored,"authority_before_sha256":_digest(initial),"authority_after_sha256":_digest(_truth()),"equal":true})
		var result: Dictionary=_scene.facade.close()
		if not _check(result.ok and not result.readback.native_live and result.readback.historical,"actual_join_before_display_"+str(size)): return false
		_scene.adopt_result(result)
		var closed: Dictionary=_scene.facade.readback()
		for row: Dictionary in rows:
			if row.display=="current": continue
			var synthetic_before: Dictionary=_truth()
			var pose: Dictionary=poses[row.preset]
			_scene.set_camera_mode(pose.fields.camera_mode)
			_scene.view_settings=pose.settings.duplicate(true)
			_scene.camera.fov=pose.fov;_scene.camera.transform=pose.camera
			var publication: Dictionary=closed.duplicate(true)
			var invalid: bool=row.display=="explicitly_invalid"
			if invalid: publication.tick=0.0
			_scene.publish_readings(publication,{"status":"SYNTHETIC INVALID DISPLAY ONLY AFTER JOIN" if invalid else "CONFIRMED CLOSED / RETAINED NATIVE TRUTH","paused":false,"view_name":"UNAVAILABLE" if invalid else "RETAINED","historical":not invalid})
			var synthetic_after: Dictionary=_truth()
			var native_before: Dictionary=synthetic_before.duplicate(true)
			var native_after: Dictionary=synthetic_after.duplicate(true)
			# Only this explicitly joined fixture is allowed to change copied display
			# sets. Keep their full raw snapshots, compare all remaining authority.
			for authority: Dictionary in [native_before,native_after]:
				authority.erase("copied_readings");authority.scene.erase("shared_readings")
				# publish_readings also publishes the copied landmark route to the
				# hidden map. Retain its complete original snapshots above; exempt
				# only these source-fixed derived display fields after actual join.
				authority.scene.erase("route_view")
				for key: String in ["_route","_manual_summary","_presentation"]: authority.map.erase(key)
			if not _check(var_to_bytes(native_before)==var_to_bytes(native_after),"synthetic_authority_equal_"+row.id): return false
			var synthetic_proofs: Dictionary={"before":_binary("asset-"+str(_captures.size()).pad_zeros(2)+"-synthetic-before",synthetic_before),"after":_binary("asset-"+str(_captures.size()).pad_zeros(2)+"-synthetic-after",synthetic_after)}
			if synthetic_proofs.before.is_empty() or synthetic_proofs.after.is_empty(): return false
			# Publication changes only copied presentation. No redraw via show_state
			# is permitted to replace it; native complete binary truth stays closed.
			if not _check(_scene.facade.readback()==closed,"closed_native_truth_"+row.id): return false
			if not await _observe(row,_truth(),true): return false
			_interactions.back().synthetic_publication=synthetic_proofs
			if not _check(_scene.facade.readback()==closed,"closed_native_truth_after_"+row.id): return false
		_sessions.append({"size":[size.x,size.y],"actual_join":result,"native_closed":closed,"scope":"One legitimate paused ground-ready session; no native advance. Display fixture publications are copied only after join."})
		return true

	func run(scene: Node) -> void:
		_scene=scene;_window_before=scene.get_viewport().size;_gui_before=scene.get_viewport().gui_disable_input
		scene.get_viewport().gui_disable_input=true;scene.process_mode=Node.PROCESS_MODE_DISABLED
		_disconnect(scene.get_viewport().focus_exited,Callable(scene,"on_focus_lost"))
		_disconnect(Input.joy_connection_changed,Callable(scene,"on_joy_connection_changed"))
		var args: PackedStringArray=OS.get_cmdline_user_args()
		var at: int=args.find("--cockpit-asset-visual-output")
		if at>=0 and at+1<args.size() and args.count("--cockpit-asset-visual-output")==1 and _output_ok(args[at+1]): _output=args[at+1]
		at=args.find("--cockpit-asset-visual-context")
		if at>=0 and at+1<args.size() and args.count("--cockpit-asset-visual-context")==1 and args[at+1] in AssetMatrix.CONTEXTS: _context=args[at+1]
		if not _check(not _output.is_empty() and not _context.is_empty(),"fresh_external_output_and_closed_context"): await _finish();return
		if not _check(OS.has_feature("editor")==(_context=="editor"),"actual_editor_feature_matches_context"): await _finish();return
		if not _check(OS.get_name()=="Windows" and DisplayServer.get_name()!="headless" and RenderingServer.get_current_rendering_method()=="gl_compatibility","actual_Windows_Compatibility_GPU"): await _finish();return
		# Godot consumes renderer CLI flags; Root separately witnesses explicit launch argv.
		# Observe the fixed capture policy directly, with no fallback driver accepted.
		if not _check(RenderingServer.get_current_rendering_driver_name()=="opengl3","actual_opengl3_driver_matches_fixed_capture_policy"): await _finish();return
		var adapter: String=RenderingServer.get_video_adapter_name().to_lower()
		if not _check(not adapter.is_empty(),"actual_adapter_present"): await _finish();return
		for fallback: String in ["llvmpipe","softpipe","software","warp","microsoft basic render"]:
			if not _check(not adapter.contains(fallback),"no_software_"+fallback): await _finish();return
		if not _check(scene.facade!=null and scene.mapper!=null and scene.sound!=null and scene._cockpit_asset_ready,"actual_asset_and_owners_ready"): await _finish();return
		_audio_joined=bool(await scene.sound.shutdown())
		if not _check(_audio_joined,"audio_retired_before_capture"): await _finish();return
		_sources_before=_sources()
		for path: String in _sources_before:
			if not _check(_sources_before[path].bytes>0 and str(_sources_before[path].sha256).length()==64,"source_present_"+path): await _finish();return
		var matrix: Array[Dictionary]=AssetMatrix.matrix()
		if not _check(matrix.size()==60,"frozen_exact60_matrix"): await _finish();return
		for size: Vector2i in AssetMatrix.SIZES:
			var selected: Array[Dictionary]=[]
			for row: Dictionary in matrix:
				if row.size==[size.x,size.y]: selected.append(row)
			if not _check(selected.size()==20,"exact20_per_size"): await _finish();return
			if not await _size_sequence(selected,size): await _finish();return
		await _finish()

	func _finish() -> void:
		var joined: bool=_scene.close_session()
		if _scene.sound!=null: _audio_joined=bool(await _scene.sound.shutdown())
		_check(joined and _audio_joined,"actual_native_audio_joined")
		var after: Dictionary=_sources() if not _sources_before.is_empty() else {}
		if not _sources_before.is_empty(): _check(_sources_before==after,"all_source_bytes_unchanged")
		# Preserve execution order in interactions and image names. Serialize the
		# capture inventory in the unchanged fixture matrix's canonical order:
		# its display/FOV rows interleave, so actual native rows execute before
		# joining and the four copied-display rows execute afterwards.
		if _captures.size()==60:
			var ordered: Array[Dictionary]=[]
			for row: Dictionary in AssetMatrix.matrix():
				var matches: Array[Dictionary]=[]
				for capture: Dictionary in _captures:
					if capture.fixture==row: matches.append(capture)
				if not _check(matches.size()==1,"exact_unique_fixture_"+row.id): break
				ordered.append(matches[0])
			if ordered.size()==60: _captures=ordered
		DisplayServer.window_set_size(_window_before);_scene.get_viewport().size=_window_before
		_scene.get_viewport().gui_disable_input=_gui_before
		for hook: Dictionary in _hooks:
			var signal_value: Signal=hook["signal"]
			var callback: Callable=hook["callback"]
			if not signal_value.is_connected(callback): signal_value.connect(callback)
		var receipt: Dictionary={"schema":"PrivateOriginalCockpitAssetVisualCapture/v1","passed":_failures.is_empty() and _captures.size()==60 and _restorations.size()==3,"failures":_failures,"context":_context,"captures":_captures,"interactions":_interactions,"restorations":_restorations,"sessions":_sessions,"views":_views,"source_before":_sources_before,"source_after":after,"renderer":{"method":RenderingServer.get_current_rendering_method(),"display_server":DisplayServer.get_name()},"driver":{"name":RenderingServer.get_current_rendering_driver_name(),"adapter":RenderingServer.get_video_adapter_name()},"reference_hardware":{"cpu":OS.get_processor_name(),"logical_processor_count":OS.get_processor_count(),"gpu":RenderingServer.get_video_adapter_name(),"scope":"Actual exposed CPU/GPU identifiers; external reference-PC/driver-version witness required."},"engine":Engine.get_version_info(),"executable":_pin(OS.get_executable_path()),"native_joined":joined,"audio_joined":_audio_joined,"independent_pixel_review":{"approved":false,"capture_ids":[],"observations":[],"scope":"Pending independent review of all60 original images and external qualified context/source/PCK/native/driver witnesses. Raw capture success is not visual acceptance."},"scope":"Engineering capture only; 60 frozen views, original ground-ready paused tick0 publications, joined copied display fixtures. No new aircraft, sensed-instrument, FPS, human or phase acceptance. Existing camera coverage remains separately required."}
		if not _output.is_empty():
			var path: String=_output.path_join("cockpit-asset-visual-capture.json")
			if not _check(not FileAccess.file_exists(path),"fresh_capture_receipt"): receipt.passed=false
			else:
				var stream: FileAccess=FileAccess.open(path,FileAccess.WRITE)
				if stream==null: receipt.passed=false;push_error("Cockpit asset capture receipt write failed")
				else: stream.store_string(JSON.stringify(receipt,"  ",false,true));stream.close()
		print("COCKPIT_ASSET_VISUAL_COMPLETE ",JSON.stringify({"passed":receipt.passed,"captures":_captures.size(),"native_joined":joined,"audio_joined":_audio_joined,"independent_pixels_approved":false}))
		_scene.get_tree().quit(0 if receipt.passed else 1)

# Local players are deliberately absent from automated flight-only runs. The
# isolated UI harness overrides this internal construction seam with the real
# qualified test extension; no page/CLI may supply a root or service factory.
func _players_storage_allowed() -> bool:
	return not legacy_proof and OS.get_cmdline_user_args().is_empty()

func _make_local_players_service() -> RefCounted:
	return ClassDB.instantiate("LocalPlayers") as RefCounted if ClassDB.class_exists("LocalPlayers") else null

func _start_local_players() -> void:
	if player_controller!=null or not _players_storage_allowed(): return
	player_controller=PlayerController.new()
	player_controller.storage_changed.connect(_player_storage_changed)
	player_controller.players_changed.connect(_player_list_changed)
	player_controller.selection_candidate.connect(_player_selection_candidate)
	player_controller.selection_changed.connect(_player_selection_changed)
	player_controller.options_changed.connect(_player_options_changed)
	player_controller.operation_finished.connect(_player_operation_finished)
	player_controller.intent_refused.connect(_player_intent_refused)
	player_controller.history_exit_resolved.connect(_player_history_resolved)
	player_controller.archive_link_changed.connect(_player_archive_link_changed)
	player_controller.storage_closed.connect(_player_storage_closed)
	var service: RefCounted=_make_local_players_service()
	if service!=null and player_controller.attach_service(service): player_controller.start_storage()
	else:
		# No attached service owns a lifetime to close. Preserve ordinary Quit.
		player_controller=null
		if players_button!=null:
			players_button.disabled=true
			players_button.tooltip_text="Player storage is unavailable in this build; Guest flight remains available"

func _player_utc() -> String:
	return Time.get_datetime_string_from_system(true,false)+"Z"

func _player_epoch() -> int:
	return player_controller.current_epoch() if player_controller!=null else 0

func _player_pair() -> Variant:
	return player_controller.selected_pair() if player_controller!=null else null

func _player_id() -> Variant:
	var pair: Variant=_player_pair()
	return null if pair==null else pair.player.id

func _next_player_opening() -> int:
	if _player_opening==9223372036854775807: return 0
	_player_opening+=1
	return _player_opening

func _player_entry_allowed() -> bool:
	if _player_transition: return false
	if legacy_proof or quitting or initializing_recording or _player_canvas==null or player_controller==null: return false
	if not menu_open or menu==null or not menu.visible or not paused: return false
	if views_open or taxi_open or audio_open or first_flight_open or scan_open or route_open or review_open: return false
	if not archive_operation.is_empty() or not pending_discard.is_empty() or not _player_ui.is_empty() or not _player_exit.is_empty(): return false
	if controls_panel!=null and controls_panel.visible or wind_panel!=null and wind_panel.visible: return false
	if facade==null: return review_joined
	if Input.mouse_mode==Input.MOUSE_MODE_CAPTURED or engine_pointer_look_active or not engine_pointer_terminal.is_empty(): return false
	if mapper!=null and (mapper.pointer_view().capture!=null or not mapper.get("_pointer_pending").is_empty()): return false
	if engine_controls!=null and not engine_controls.get("_capture").is_empty(): return false
	var source: Dictionary=facade.readback()
	var qualified: Dictionary=ObservedValues.qualify(source)
	return qualified.ok and qualified.kind=="current" and source.paused and source.host_mode=="paused" and source.session_id==adopted_session_id

func _register_player_widget(widget: Control, kind: String) -> int:
	var opening: int=_next_player_opening()
	if opening==0: return 0
	var pair: Variant=_player_pair()
	_player_ui={"widget":widget,"opening":opening,"epoch":_player_epoch(),"player_id":_player_id(),
		"revision":null if pair==null else pair.player.revision,"session":adopted_session_id,
		"kind":kind,"callbacks":{}}
	return opening

func _connect_player(signal_value: Signal, callback: Callable) -> void:
	signal_value.connect(callback)
	_player_ui.callbacks[signal_value]=callback

func _player_guard(widget: Control, opening: int, epoch: int) -> bool:
	if _player_ui.is_empty() or widget==null or not is_instance_valid(widget) or not widget.is_visible_in_tree(): return false
	if _player_ui.widget!=widget or _player_ui.opening!=opening or _player_ui.epoch!=epoch or epoch!=_player_epoch(): return false
	if _player_ui.player_id!=_player_id() or _player_ui.session!=adopted_session_id or not menu_open: return false
	var pair: Variant=_player_pair()
	return _player_ui.revision==(null if pair==null else pair.player.revision)

func retire_players_ui() -> void:
	if _player_ui.is_empty(): return
	var prior: Dictionary=_player_ui
	_player_ui={}
	if player_controller!=null: player_controller.retire_opening(prior.opening)
	for signal_value: Signal in prior.callbacks:
		var callback: Callable=prior.callbacks[signal_value]
		if signal_value.is_connected(callback): signal_value.disconnect(callback)
	var widget: Control=prior.widget
	if is_instance_valid(widget):
		if widget.has_method("retire"): widget.retire()
		widget.hide()
		widget.queue_free()

func open_players() -> bool:
	if not _player_entry_allowed(): return false
	if facade==null:
		_show_players_page()
		return true
	var dialog:=ConfirmationDialog.new()
	dialog.title="End this flight to choose a player?"
	dialog.dialog_text="The current flight will stop. Its recorded review stays available.\nCancel keeps this flight and all current settings."
	dialog.ok_button_text="End flight and choose player"
	dialog.cancel_button_text="Cancel Â· keep this flight"
	dialog.get_ok_button().focus_mode=Control.FOCUS_ALL
	# A Window is not a Control: the actual confirmation widget is its content.
	var identity:=Control.new()
	identity.name="PlayerExitIdentity"
	_player_canvas.add_child(identity)
	identity.show()
	_player_canvas.add_child(dialog)
	var opening: int=_register_player_widget(identity,"exit")
	if opening==0:
		dialog.queue_free(); identity.queue_free(); return false
	_player_exit={"opening":opening,"epoch":_player_epoch(),"dialog":dialog,"identity":identity}
	_connect_player(dialog.canceled,func(): cancel_players_exit(opening,_player_exit.get("epoch",-1)))
	_connect_player(dialog.confirmed,func(): confirm_players_exit(opening,_player_exit.get("epoch",-1)))
	dialog.popup_centered(Vector2i(560,230))
	dialog.get_cancel_button().grab_focus()
	return true

func _retire_player_exit() -> void:
	var dialog: Window=_player_exit.get("dialog")
	_player_exit={}
	retire_players_ui()
	if is_instance_valid(dialog): dialog.hide(); dialog.queue_free()

func cancel_players_exit(opening: int, epoch: int) -> void:
	if _player_exit.is_empty() or not _player_guard(_player_exit.identity,opening,epoch): return
	_retire_player_exit()
	if players_button!=null: players_button.grab_focus()

func confirm_players_exit(opening: int, epoch: int) -> void:
	if _player_transition or _player_exit.is_empty() or not _player_guard(_player_exit.identity,opening,epoch): return
	# Own this transition across asynchronous playback retirement. No modal can
	# activate settings or start a new flight while the old audio still exists.
	if facade==null or facade.readback().session_id!=adopted_session_id or not review_boundary(): return
	_player_transition=true
	var source_session: String=adopted_session_id
	var retiring_sound: Node=sound
	_retire_player_exit()
	menu.hide()
	_player_close_reason="user_end"
	if not close_session():
		_player_transition=false
		status="Flight did not join; player selection is unavailable"
		open_menu(status)
		return
	_player_history_waiting=player_controller.history_exit_pending()
	await _finish_player_retirement(epoch,source_session,retiring_sound)

func _finish_player_retirement(epoch: int, source_session: String, retiring_sound: Node) -> void:
	_player_audio_retired=retiring_sound==null or bool(await retiring_sound.shutdown())
	if not _player_transition or epoch!=_player_epoch() or source_session!=adopted_session_id or facade!=null or sound!=retiring_sound:
		_show_player_audio_wait(epoch,source_session,retiring_sound,false)
		return
	if not _player_audio_retired:
		_show_player_audio_wait(epoch,source_session,retiring_sound,true)
		return
	if is_instance_valid(retiring_sound): retiring_sound.queue_free()
	sound=null
	_player_transition=false
	if _player_history_waiting: _show_history_wait()
	elif _player_quit_pending: _finish_player_quit()
	else: _show_players_page()

func _show_player_audio_wait(epoch: int, source_session: String, retiring_sound: Node, retryable: bool) -> void:
	# A timeout is not a join. Keep flight/settings entry blocked and expose
	# only a deliberate retry of the same playback owner.
	retire_players_ui()
	var card:=VBoxContainer.new()
	_player_canvas.add_child(card)
	card.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	card.position=Vector2(-250,-85)
	card.custom_minimum_size=Vector2(500,170)
	var label:=Label.new()
	label.text="Audio playback is still retiring. Retry before continuing." if retryable else "Player transition changed. Selection remains unavailable."
	label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	card.add_child(label)
	var retry:=Button.new()
	retry.text="Retry playback shutdown"
	retry.disabled=not retryable
	card.add_child(retry)
	var opening: int=_register_player_widget(card,"audio_wait")
	_connect_player(retry.pressed,func():
		if _player_guard(card,opening,epoch) and _player_transition and facade==null and sound==retiring_sound and adopted_session_id==source_session:
			retire_players_ui()
			_finish_player_retirement(epoch,source_session,retiring_sound))
	menu.hide()
	card.show()
	if retryable: retry.grab_focus()

func _show_history_wait() -> void:
	retire_players_ui()
	var card:=VBoxContainer.new()
	_player_canvas.add_child(card)
	card.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	card.position=Vector2(-250,-85)
	card.custom_minimum_size=Vector2(500,170)
	var label:=Label.new()
	label.text="Finishing practice historyâ€¦"
	label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	card.add_child(label)
	var acknowledge:=Button.new()
	acknowledge.text="Continue without saved history"
	card.add_child(acknowledge)
	var opening: int=_register_player_widget(card,"history_wait")
	_connect_player(acknowledge.pressed,func():
		if _player_guard(card,opening,_player_epoch()): player_controller.acknowledge_history_not_saved(opening,_player_epoch()))
	menu.hide()
	card.show()
	acknowledge.grab_focus()

func _player_history_resolved(epoch: int, _saved: bool) -> void:
	if epoch!=_player_epoch(): return
	_player_history_waiting=false
	if not _player_restart_after_history.is_empty():
		var next: Dictionary=_player_restart_after_history
		_player_restart_after_history={}
		retire_players_ui()
		call_deferred("perform_start",next.start,next.wind,next.profile,next.get("first_flight",false),next.get("world",selected_world))
	elif _player_quit_pending: _finish_player_quit()
	elif not _player_ui.is_empty() and _player_ui.kind=="history_wait":
		retire_players_ui()
		_show_players_page()

func _new_player_page(script: Script, kind: String) -> Control:
	retire_players_ui()
	var widget: Control=script.new()
	_player_canvas.add_child(widget)
	widget.z_index=5
	_register_player_widget(widget,kind)
	menu.hide()
	menu_open=true
	Input.mouse_mode=Input.MOUSE_MODE_VISIBLE
	return widget

func _show_players_page() -> void:
	if _player_transition: return
	if facade!=null or not review_joined or player_controller==null: return
	var widget: Control=_new_player_page(PlayersPage,"players")
	var opening: int=_player_ui.opening
	var epoch: int=_player_ui.epoch
	_connect_player(widget.player_chosen,func(o: int,e: int,id: String):
		if _player_guard(widget,o,e):
			widget.set_feedback(o,e,"Loading playerâ€¦",true)
			player_controller.choose_player(o,e,id))
	_connect_player(widget.guest_chosen,func(o: int,e: int):
		if _player_guard(widget,o,e): player_controller.choose_guest(o,e))
	_connect_player(widget.create_requested,func(o: int,e: int):
		if _player_guard(widget,o,e): _show_player_name(false))
	_connect_player(widget.rename_requested,func(o: int,e: int):
		if _player_guard(widget,o,e): _show_player_name(true))
	_connect_player(widget.history_requested,func(o: int,e: int):
		if _player_guard(widget,o,e): _show_player_history())
	_connect_player(widget.dismissed,func(o: int,e: int):
		if _player_guard(widget,o,e): _dismiss_player_ui())
	# Never fabricate a native Status if the class/module is absent.
	var storage: Dictionary=player_controller.current_status()
	if storage.is_empty():
		retire_players_ui(); open_menu("Player storage is unavailable in this build Â· Guest remains usable"); return
	var pair: Variant=_player_pair()
	var initial_players: Array=[] if pair==null else [{"id":pair.player.id,"name":pair.player.name,"revision":pair.player.revision}]
	if not widget.present(opening,epoch,initial_players,_player_id(),storage):
		retire_players_ui(); open_menu("Player chooser unavailable"); return
	widget.set_feedback(opening,epoch,"Reading saved playersâ€¦",true)
	player_controller.open_players(opening,epoch)

func _player_list_changed(opening: int, epoch: int, players: Array) -> void:
	if _player_ui.is_empty() or _player_ui.kind!="players": return
	var widget: Control=_player_ui.widget
	if _player_guard(widget,opening,epoch): widget.present(opening,epoch,players,_player_id(),player_controller.current_status())

func _show_player_name(rename: bool) -> void:
	var pair: Variant=_player_pair()
	if rename and pair==null: return
	var widget: Control=_new_player_page(PlayerNamePage,"rename" if rename else "create")
	var opening: int=_player_ui.opening
	var epoch: int=_player_ui.epoch
	_connect_player(widget.name_confirmed,func(o: int,e: int,name: String):
		if not _player_guard(widget,o,e): return
		widget.set_feedback(o,e,"Saving player nameâ€¦",true)
		if rename: player_controller.rename_player(o,e,name)
		else: player_controller.create_player(o,e,name))
	_connect_player(widget.dismissed,func(o: int,e: int):
		if _player_guard(widget,o,e): _show_players_page())
	widget.present(opening,epoch,"" if pair==null or not rename else pair.player.name,rename)

func adopt_player_bundle(opening: int, epoch: int, pair: Variant) -> bool:
	if _player_transition: return false
	if facade!=null or not review_joined or not archive_operation.is_empty() or _player_ui.is_empty(): return false
	if not _player_guard(_player_ui.widget,opening,epoch): return false
	var checked: Dictionary={"ok":true,"value":null} if pair==null else PlayerOptions.validate_pair(pair)
	if not checked.ok: return false
	var seed: Dictionary=PlayerOptions.default_seed() if pair==null else PlayerOptions.seed_from_preferences(checked.value.preferences)
	var admitted: Dictionary=PlayerOptions.validate_seed(seed)
	if not admitted.ok or not PlayerOptions.exact_equal(admitted.value,seed): return false
	# Both slots and Audio are fully validated before any option is changed.
	var next_presets: Dictionary={}
	next_presets[Facade.LEGACY_PROFILE.id]=Mapper.default_preset() if seed.legacy_input==null else seed.legacy_input.duplicate(true)
	next_presets[Facade.PISTON_PROFILE.id]=Mapper.default_preset_v2() if seed.piston_input==null else seed.piston_input.duplicate(true)
	_player_seed=seed.duplicate(true)
	profile_presets=next_presets
	active_preset=next_presets[selected_profile].duplicate(true)
	audio_options=seed.audio.duplicate(true)
	audio_enabled=audio_options.enabled
	# No mapper configure, flight creation, recorder reset or camera action here.
	return true

func _player_selection_candidate(opening: int, epoch: int, pair: Variant) -> void:
	var adopted: bool=adopt_player_bundle(opening,epoch,pair)
	player_controller.finish_selection(opening,epoch,adopted)
	if not adopted: _player_feedback(opening,epoch,"Player not activated; previous settings retained",false)

func _player_selection_changed(epoch: int, pair: Variant) -> void:
	if players_button!=null: players_button.text="Players Â· "+("Guest" if pair==null else String(pair.player.name))
	if not _player_ui.is_empty() and _player_ui.epoch!=epoch:
		retire_players_ui()
		open_menu("Player selected Â· choose a fresh start")
	elif not _player_ui.is_empty():
		_player_ui.revision=null if pair==null else pair.player.revision
	for entry in _player_save_ui.values():
		if entry.epoch==epoch and entry.player_id==_player_id(): entry.revision=null if pair==null else pair.player.revision

func capture_current_player_seed() -> Dictionary:
	# Only accepted Apply updates a slot. Loaded null remains null; the Scene's
	# other-mode draft/cache never substitutes for that committed slot.
	var pair: Variant=_player_pair()
	var seed: Dictionary=PlayerOptions.default_seed() if pair==null else PlayerOptions.seed_from_preferences(pair.preferences)
	var slot: String="piston_input" if selected_profile==Facade.PISTON_PROFILE.id else "legacy_input"
	seed[slot]=null if _player_seed[slot]==null else _player_seed[slot].duplicate(true)
	seed.audio=audio_options.duplicate(true)
	return seed

func _notify_player_options() -> void:
	if player_controller!=null: player_controller.current_options_changed(capture_current_player_seed())

func _bind_player_save(widget: Control) -> void:
	_retire_player_save(widget)
	if player_controller==null or widget==null: return
	var opening: int=_next_player_opening()
	if opening==0: return
	var epoch: int=_player_epoch()
	var pair: Variant=_player_pair()
	var callback: Callable=func(o: int,e: int):
		if _player_save_guard(widget,o,e): request_player_save(o,e)
	_player_save_ui[widget.get_instance_id()]={"widget":widget,"opening":opening,"epoch":epoch,"player_id":_player_id(),
		"revision":null if pair==null else pair.player.revision,"session":adopted_session_id,"callback":callback}
	widget.save_player_requested.connect(callback)
	_refresh_player_save(widget)

func _player_save_guard(widget: Control, opening: int, epoch: int) -> bool:
	if widget==null or not is_instance_valid(widget) or not widget.is_visible_in_tree() or not _player_save_ui.has(widget.get_instance_id()): return false
	var entry: Dictionary=_player_save_ui[widget.get_instance_id()]
	var pair: Variant=_player_pair()
	return entry.widget==widget and entry.opening==opening and entry.epoch==epoch and epoch==_player_epoch() and entry.player_id==_player_id() and entry.revision==(null if pair==null else pair.player.revision) and entry.session==adopted_session_id and menu_open and paused and facade!=null and facade.readback().host_mode=="paused"

func _retire_player_save(widget: Control) -> void:
	if widget==null or not is_instance_valid(widget) or not _player_save_ui.has(widget.get_instance_id()): return
	var entry: Dictionary=_player_save_ui[widget.get_instance_id()]
	_player_save_ui.erase(widget.get_instance_id())
	if player_controller!=null: player_controller.retire_opening(entry.opening)
	if widget.save_player_requested.is_connected(entry.callback): widget.save_player_requested.disconnect(entry.callback)
	widget.set_player_save_state(0,0,null,false,false,false)

func _refresh_player_save(widget: Control) -> void:
	if widget==null or not _player_save_ui.has(widget.get_instance_id()): return
	var entry: Dictionary=_player_save_ui[widget.get_instance_id()]
	if _player_save_guard(widget,entry.opening,entry.epoch):
		var pair: Variant=_player_pair()
		widget.set_player_save_state(entry.opening,entry.epoch,null if pair==null else pair.player,_player_state.dirty,_player_state.pending,_player_state.unknown)

func request_player_save(opening: int, epoch: int) -> void:
	var widget: Control
	for entry in _player_save_ui.values():
		if entry.opening==opening and _player_save_guard(entry.widget,opening,epoch): widget=entry.widget
	if widget==null: return
	if _player_pair()==null:
		if widget==audio_panel: dismiss_audio()
		else: dismiss_controls()
		open_players()
		return
	player_controller.save_snapshot(opening,epoch,capture_current_player_seed(),_player_utc())

func _player_options_changed(epoch: int, _preferences: Variant, dirty: bool, pending: bool, unknown: bool) -> void:
	if epoch!=_player_epoch(): return
	_player_state={"dirty":dirty,"pending":pending,"unknown":unknown}
	for entry in _player_save_ui.values(): _refresh_player_save(entry.widget)

func _player_feedback(opening: int, epoch: int, message: String, busy: bool) -> void:
	if _player_ui.is_empty(): return
	var widget: Control=_player_ui.widget
	if _player_guard(widget,opening,epoch) and widget.has_method("set_feedback"): widget.set_feedback(opening,epoch,message.left(1024),busy)

func _player_intent_refused(opening: int, epoch: int, _kind: String, reason: String, admission: Variant) -> void:
	var message: String="Storage did not accept this action: "+(String(admission.error_code) if reason=="native_rejected" else reason)
	_player_feedback(opening,epoch,message,false)
	_player_save_failure(opening,epoch,message)

func _player_save_failure(opening: int, epoch: int, message: String) -> void:
	for entry in _player_save_ui.values():
		if entry.opening!=opening or not _player_save_guard(entry.widget,opening,epoch): continue
		var dialog:=AcceptDialog.new()
		dialog.title="Player preferences"
		dialog.dialog_text=message.left(1024)
		entry.widget.add_child(dialog)
		dialog.confirmed.connect(dialog.queue_free)
		dialog.canceled.connect(dialog.queue_free)
		dialog.popup_centered(Vector2i(500,180))

func _player_storage_changed(_status: Dictionary) -> void:
	# Native Status is retained only by the controller. Never synthesize ready.
	_update_player_history_wait()

func _dismiss_player_ui() -> void:
	if not _player_exit.is_empty():
		cancel_players_exit(_player_exit.opening,_player_exit.epoch)
		return
	if not _player_ui.is_empty() and _player_ui.kind=="history_wait": return
	retire_players_ui()
	open_menu("Flight ended Â· choose a fresh start")
	if players_button!=null: players_button.grab_focus()

func _player_flight_adopted() -> void:
	if player_controller==null or facade==null: return
	var readback: Dictionary=facade.readback()
	var qualified: Dictionary=ObservedValues.qualify(readback)
	if not qualified.ok or qualified.kind!="current": return
	var source: Dictionary={"session_id":readback.session_id,"model_identity":readback.model_identity.duplicate(true),
		"source_variant":PlayerNativeIdentity.SOURCE_VARIANT,"native_source_fingerprint":readback.native_source_fingerprint,
		"prepared_world_sha256":readback.prepared_world_sha256,"named_start":readback.named_start,
		"wind_profile":current_wind_profile,"angular_integration_method":Facade.PISTON_METHOD if selected_profile==Facade.PISTON_PROFILE.id else null}
	player_controller.flight_adopted(source,readback,_player_utc())
	_recording_player_context=player_controller.current_practice_context()

func _ensure_player_audio() -> void:
	if sound!=null: return
	sound=load("res://interactive/flight_sound.gd").new()
	add_child(sound)
	sound.set_options(audio_options)

func _quit_with_players() -> void:
	if quitting or _player_quit_pending or _player_transition: return
	if player_controller==null:
		await super.quit_flight()
		return
	_player_transition=true
	retire_players_ui()
	menu.hide()
	_player_close_reason="user_quit"
	if not close_session():
		_player_transition=false
		open_menu("Flight join failed; quit is unavailable")
		return
	_player_quit_pending=true
	_player_history_waiting=player_controller.history_exit_pending()
	await _finish_player_retirement(_player_epoch(),adopted_session_id,sound)

func _finish_player_quit() -> void:
	if not _player_quit_pending or not _player_audio_retired: return
	_player_transition=true
	retire_players_ui()
	_player_storage_quit=true
	player_controller.begin_close()

func _player_storage_closed() -> void:
	if _player_storage_quit:
		quitting=true
		get_tree().quit(0)
		return
	if player_controller.replacement_requested():
		var service: RefCounted=_make_local_players_service()
		if service!=null and player_controller.attach_service(service): player_controller.start_storage()
func _show_player_history() -> void:
	if _player_id()==null or facade!=null: return
	var widget: Control=_new_player_page(PracticePage,"history")
	var opening: int=_player_ui.opening
	var epoch: int=_player_ui.epoch
	_connect_player(widget.next_requested,func(o: int,e: int,cursor: Variant):
		if _player_guard(widget,o,e):
			widget.set_feedback(o,e,"Reading practice historyâ€¦",true)
			player_controller.request_history(o,e,cursor))
	_connect_player(widget.details_requested,func(o: int,e: int,id: String):
		if _player_guard(widget,o,e):
			widget.set_feedback(o,e,"Reading practice detailsâ€¦",true)
			player_controller.request_details(o,e,id))
	_connect_player(widget.prune_requested,func(o: int,e: int,ids: Array):
		if _player_guard(widget,o,e):
			widget.set_feedback(o,e,"Removing selected historyâ€¦",true)
			player_controller.request_prune(o,e,ids))
	_connect_player(widget.dismissed,func(o: int,e: int):
		if _player_guard(widget,o,e): _show_players_page())
	widget.present(opening,epoch,_player_id(),{"practice":[],"next_before_creation_sequence":null})
	widget.set_feedback(opening,epoch,"Reading practice historyâ€¦",true)
	player_controller.request_history(opening,epoch,null)

func _show_practice_details(practice: Dictionary) -> void:
	var widget: Control=_new_player_page(PracticeDetailsPage,"details")
	var opening: int=_player_ui.opening
	var epoch: int=_player_ui.epoch
	_player_ui["practice"]=practice.duplicate(true)
	_connect_player(widget.dismissed,func(o: int,e: int):
		if _player_guard(widget,o,e): _show_player_history())
	_connect_player(widget.archive_open_requested,func(o: int,e: int,id: String):
		if not _player_guard(widget,o,e) or id!=practice.id or practice.archive==null: return
		var result: Dictionary=archive_files.open(practice.archive.absolute_path)
		if not result.ok:
			widget.set_feedback(o,e,"Recorded review unavailable: "+result.error,false)
			return
		var recording: Dictionary=result.value
		if result.payload_sha256!=practice.archive.payload_sha256 or recording.metadata.session_id!=practice.archive.recording_session_id or recording.metadata.first_tick!=practice.archive.first_tick or recording.last_observed_tick!=practice.archive.last_tick or not _recording_matches_source(recording,practice.source):
			widget.set_feedback(o,e,"Recorded review no longer matches this saved link",false)
			return
		retire_players_ui()
		if observed_panel.set_recording(recording):
			archive_imported=true
			review_open=true
			observed_panel.set_file_context(true,"Historical player review Â· read-only")
			observed_panel.set_open(true))
	widget.present(opening,epoch,practice)

static func _recording_matches_source(recording: Dictionary, source: Dictionary) -> bool:
	if not ObservedValues.valid_recording(recording) or recording.state=="empty": return false
	var metadata: Dictionary=recording.metadata
	for key in ["session_id","model_identity","native_source_fingerprint","prepared_world_sha256","named_start"]:
		if not source.has(key) or not ArchiveCodec._exact(metadata[key],source[key]): return false
	var relation: Dictionary=Worlds.source(metadata.model_identity,metadata.named_start,metadata.prepared_world_sha256,metadata.world_anchor)
	if not relation.ok or relation.recording_version!=recording.contract_version: return false
	if relation.selector=="kawo-prototype-v1" and (source.get("wind_profile")!="calm" or source.get("angular_integration_method")!=null): return false
	# The old ledger intentionally has no anchor/clock/seed fields. Compare those
	# when actually available; never fabricate them as imported archive facts.
	for key in ["world_anchor","clock","seed","wind_profile","angular_integration_method"]:
		if metadata.has(key) and source.has(key) and not ArchiveCodec._exact(metadata[key],source[key]): return false
	return true

func _player_operation_finished(opening: int, epoch: int, result: Dictionary) -> void:
	if result.kind=="save_preferences" and result.state not in ["committed","no_change"]:
		_player_save_failure(opening,epoch,("Save status unknown; reconcile before retrying. " if result.state=="uncertain" else "Preferences "+result.state+": ")+String(result.error_code))
	if _player_ui.is_empty(): return
	var widget: Control=_player_ui.widget
	if not _player_guard(widget,opening,epoch): return
	if result.state not in ["read","committed","no_change"]:
		_player_feedback(opening,epoch,"Action "+result.state+": "+String(result.error_code),false)
		return
	match result.kind:
		"rename_player": _show_players_page()
		"list_practice":
			if _player_ui.kind=="history": widget.present(opening,epoch,_player_id(),result.value)
		"load_practice": _show_practice_details(result.value.practice)
		"prune_practice": _show_player_history()
		"export_player":
			if _player_ui.kind=="export": widget.present(opening,epoch,_player_pair().player,result.value)
		"list_recovery":
			if _player_ui.kind=="recovery": widget.present(opening,epoch,result.value.snapshots,null)
		"delete_recovery":
			if _player_ui.kind=="recovery": widget.present(opening,epoch,[],result.value)

func _update_player_history_wait() -> void:
	if player_controller==null or _player_ui.is_empty() or _player_ui.kind!="history_wait": return
	var state: Dictionary=player_controller.history_state()
	var card: Control=_player_ui.widget
	var label: Label=card.get_child(0)
	var acknowledge: Button=card.get_child(1)
	acknowledge.disabled=not state.failed or state.pending
	label.text="Practice history or its review association was not acknowledged. Continue explicitly, or wait for the accepted operation to finish." if state.failed else "Finishing practice history and review association..."
