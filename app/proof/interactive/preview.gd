extends Node3D

const AircraftChecks = preload("res://interactive/flight_aircraft_checks.gd")
const RenderPose = preload("res://interactive/flight_render_pose.gd")
const RenderPoseChecks = preload("res://interactive/flight_render_pose_checks.gd")
const CameraChecks = preload("res://interactive/flight_camera_checks.gd")
var render_pose: RefCounted=RenderPose.new()
var camera_follow_offset := Vector3.ZERO

const HZ: int = 120
const BUDGET_DENOMINATOR: int = 1000000
const DEBT_LIMIT: int = 250000 * HZ
var bridge: RefCounted
var snapshot: Dictionary = {}
var atmosphere: Dictionary = {}
var initial: Dictionary = {}
var controls: Dictionary = {}
var last_submitted: Dictionary = {}
var command_sequence: int = 0
var lifecycle_sequence: int = 0
var debt: int = 0
var paused: bool = false
var stalled: bool = false
var blocked: bool = false
var last_wall_us: int = 0
var status: String = ""
var origin_ecef: Dictionary = {}
var latitude: float = 0.0
var longitude: float = 0.0
var airplane: Node3D
var camera: Camera3D
var label: Label
var panel: Control
var cockpit_panel: Control
var panel_viewport: SubViewport
var cockpit_builder: RefCounted
var cockpit: Dictionary = {}
var flight_map: Control
var map_visible: bool = false
var menu: PanelContainer
var menu_title: Label
var menu_message: Label
var resume_button: Button
var menu_open: bool = false
var help_visible: bool = false
var panel_visible: bool = true
var camera_mode: int = 0
var look_angles := Vector2.ZERO
var camera_distance: float = 13.0
var camera_ready: bool = false
var input_sensitivity: float = 1.0
var joy_device: int = -1
var audio_enabled: bool = true
var sound: Node
var quitting: bool = false
var propeller: Node3D
var smoke: bool = false
var visual_smoke: bool = false
var attempt: int = 0
var named_start: String = "ground-ready"
var held_controls: Dictionary = {}
var world_anchor: Dictionary = {}
var plane_clearance: float = 0.0
var ground_valid: bool = false
var native_outcome: String = "completed"
var forward_view: bool = false
var brake_hold: bool = true
var gears: Dictionary = {}
var trace_file: FileAccess
var last_aircraft_json: String = ""
var last_atmosphere_json: String = ""
var failures: Array[String] = []
var evidence: Dictionary = {}
var submitted_count: int = 0
var event_count: int = 0

func _ready() -> void:
	get_tree().auto_accept_quit=false
	get_window().min_size=Vector2i(960,540)
	smoke = "--smoke" in OS.get_cmdline_user_args()
	visual_smoke = "--visual-smoke" in OS.get_cmdline_user_args()
	if "--airborne" in OS.get_cmdline_user_args():
		named_start = "airborne-prepared"
	if not smoke:
		make_world()
	if not restart():
		if smoke or visual_smoke:
			finish_smoke()
		return
	if visual_smoke:
		set_process(false)
		run_visual_smoke()
	elif smoke:
		set_process(false)
		run_smoke()
	else:
		last_wall_us = Time.get_ticks_usec()
		Input.joy_connection_changed.connect(on_joy_connection_changed)
		get_window().focus_exited.connect(on_focus_lost)
		open_menu("Ready for your flight")

func close_session() -> bool:
	render_pose.clear()
	if bridge == null:
		return true
	var closed: Dictionary = bridge.call("close")
	bridge = null
	return closed.get("ok", false) and closed.get("joined", false)

func restart() -> bool:
	if not close_session():
		return fail("Native worker did not join")
	if not ClassDB.class_exists("FlightInteractiveSession"):
		return fail("Contract98 FlightInteractiveSession extension unavailable")
	bridge = ClassDB.instantiate("FlightInteractiveSession") as RefCounted
	var model_root: String = ProjectSettings.globalize_path("res://models") if OS.has_feature("editor") else OS.get_executable_path().get_base_dir().path_join("models")
	var reply: Dictionary = bridge.call("open_session", model_root, named_start)
	if not reply.get("ok", false):
		return fail("Initialization failed: " + str(reply))
	if reply.prepared_world_sha256 != "04bff5a0bcf3509990f6276b2548a28268f57fc96d218a7ca51cab1990ec1ff5":
		return fail("Prepared world identity mismatch")
	initial = {"solved_controls":reply.held_axes.duplicate(true)}
	accept_reply(reply)
	initial["accepted_aircraft"] = snapshot.duplicate(true)
	controls = held_controls.duplicate(true)
	last_submitted = controls.duplicate(true)
	world_anchor = reply.world_anchor.duplicate(true)
	latitude = float(world_anchor.latitude_rad)
	longitude = float(world_anchor.longitude_rad)
	var eccentricity: float = (1.0/298.257223563)*(2.0-1.0/298.257223563)
	var radius: float = 6378137.0/sqrt(1.0-eccentricity*sin(latitude)*sin(latitude))
	var height: float = float(world_anchor.ellipsoid_height_m)
	origin_ecef = {"x":(radius+height)*cos(latitude)*cos(longitude),"y":(radius+height)*cos(latitude)*sin(longitude),"z":(radius*(1.0-eccentricity)+height)*sin(latitude)}
	debt = 0
	camera_ready = false
	look_angles = Vector2.ZERO
	paused = false
	stalled = false
	blocked = false
	brake_hold = float(controls.left_brake)>0.5 and float(controls.right_brake)>0.5
	command_sequence = 0
	lifecycle_sequence = 0
	submitted_count = 0
	event_count = 0
	attempt += 1
	reset_render_pose()
	status = "LIVE | %s | fresh attempt %d | engine already running" % [named_start,attempt]
	last_wall_us = Time.get_ticks_usec()
	evidence["runtime_modules"] = reply.runtime_modules
	evidence["native_source_fingerprint"] = reply.native_source_fingerprint
	evidence["prepared_world_sha256"] = reply.prepared_world_sha256
	evidence["world_anchor"] = world_anchor
	evidence["user_data_directory"] = OS.get_user_data_dir()
	return true

func accept_reply(reply: Dictionary) -> void:
	last_aircraft_json = reply.aircraft_json
	last_atmosphere_json = reply.atmosphere_json
	snapshot = JSON.parse_string(last_aircraft_json)
	atmosphere = JSON.parse_string(last_atmosphere_json)
	held_controls = reply.held_axes.duplicate(true)
	ground_valid = reply.ground_query_valid
	plane_clearance = float(reply.plane_clearance_m)
	native_outcome = reply.outcome

func fail(message: String) -> bool:
	render_pose.clear()
	status = message + " | R starts a fresh attempt"
	paused = true
	blocked = true
	failures.append(message)
	push_error(message)
	return false

func pause_session(value: bool) -> bool:
	if bridge == null:
		return false
	if blocked and not value:
		status = "Native session stopped; R starts a fresh attempt"
		return false
	if stalled and not value:
		status = "STALL: preserved %.3fs debt; R explicitly starts a fresh attempt" % (float(debt) / (HZ * BUDGET_DENOMINATOR))
		return false
	lifecycle_sequence += 1
	var reply: Dictionary = bridge.call("session_control", {"type":"SessionControl", "schema_version":1, "tick":snapshot.tick, "session_id":snapshot.session_id, "sequence":str(lifecycle_sequence), "source_id":"session.owner", "payload":{"kind":"pause", "paused":value}})
	if not reply.get("ok", false) or reply.get("rejection", -1) != 0:
		return fail("Pause rejected: " + str(reply))
	paused = value
	reset_render_pose()
	last_wall_us = Time.get_ticks_usec()
	status = "PAUSED | P resumes; R starts a fresh attempt" if value else "LIVE | original synthetic model"
	return true

func submit_axes(axes: Dictionary) -> bool:
	if axes == last_submitted:
		return true
	command_sequence += 1
	var reply: Dictionary = bridge.call("submit", {"type":"ControlCommand", "schema_version":1, "tick":str(int(snapshot.tick) + 1), "session_id":snapshot.session_id, "sequence":str(command_sequence), "source_id":"pilot.controls", "authority":"pilot", "assistance":{"profile_id":"unassisted", "active":[]}, "payload":axes})
	if not reply.get("ok", false) or not reply.get("queued", false):
		return fail("Control rejected: " + str(reply))
	last_submitted = axes.duplicate(true)
	submitted_count += 1
	return true

func reset_render_pose() -> void:
	# Private visual history, cleared at lifecycle/coordinate-frame boundaries.
	if snapshot.is_empty() or origin_ecef.is_empty():
		render_pose.clear()
		return
	render_pose.reset(str(snapshot.session_id),int(snapshot.tick),visual_position(),visual_basis(body_quaternion()))

func step_ticks(count: int, retain_adjacent: bool=true) -> bool:
	# Preserve exact native ticks/commands, retain only its final adjacent pair.
	# A batch above the native cap is still rejected before any partial stepping.
	if retain_adjacent and count>=2 and count<=32:
		return step_ticks(count-1,false) and step_ticks(1,false)
	var old_tick: int = int(snapshot.tick)
	var reply: Dictionary = bridge.call("step_fixed", count)
	if not reply.get("ok", false):
		return fail("Native interactive worker stopped: " + str(reply))
	accept_reply(reply)
	var completed: int = int(reply.completed)
	if completed<0 or completed>count or snapshot.validity!="valid" or int(snapshot.tick)!=old_tick+completed:
		return fail("Invalid copied state or actual completed tick count")
	debt = maxi(0,debt-completed*BUDGET_DENOMINATOR)
	event_count += reply.events_json.size()
	if trace_file != null:
		for command_json in reply.applied_commands_json:
			trace_file.store_line(command_json)
		for event_json in reply.events_json:
			trace_file.store_line(event_json)
	if reply.outcome!="completed":
		render_pose.clear()
		paused = true
		blocked = true
		status = "NATIVE %s | %d actual ticks | %s | R fresh attempt; retained state is historical on discard" % [reply.outcome,completed,reply.fault]
		return false
	if completed>0 and not render_pose.push(str(snapshot.session_id),int(snapshot.tick),visual_position(),visual_basis(body_quaternion())):
		return fail("Invalid rigid presentation pose")
	return completed==count

func advance_wall_us(elapsed_us: int) -> bool:
	if paused or bridge == null:
		return true
	if elapsed_us < 0:
		return fail("Monotonic clock regressed")
	debt += elapsed_us * HZ
	if debt > DEBT_LIMIT:
		if not pause_session(true):
			return false
		stalled = true
		status = "STALL: %.3fs wall debt retained; R explicitly restarts (no catch-up)" % (float(debt) / (HZ * BUDGET_DENOMINATOR))
		return true
	var count: int = mini(32, debt / BUDGET_DENOMINATOR)
	if count > 0:
		if not step_ticks(count):
			return false
	return true

func _process(_delta: float) -> void:
	var now: int = Time.get_ticks_usec()
	var elapsed: int = now - last_wall_us
	last_wall_us = now
	if not paused and not menu_open and bridge != null:
		read_keyboard(minf(float(elapsed) / 1000000.0, 0.25))
		if submit_axes(controls):
			advance_wall_us(elapsed)
	if not smoke:
		show_state(clampf(float(elapsed)/1000000.0,0.0,0.25))
		if sound != null and not snapshot.is_empty():
			sound.call("update_audio",float(held_controls.get("throttle",0)),flight_speed(),paused,any_wow())

func axis(positive: Key, negative: Key) -> float:
	return float(Input.is_physical_key_pressed(positive)) - float(Input.is_physical_key_pressed(negative))

func stick_axis(raw: float) -> float:
	var dead_zone: float = 0.12
	return signf(raw)*clampf((absf(raw)-dead_zone)/(1.0-dead_zone),0,1)

func read_keyboard(seconds: float) -> void:
	var roll_input: float = axis(KEY_RIGHT,KEY_LEFT)
	var pitch_input: float = axis(KEY_DOWN,KEY_UP)
	var yaw_input: float = axis(KEY_D,KEY_A)
	var throttle_input: float = clampf(axis(KEY_PAGEUP,KEY_PAGEDOWN)+axis(KEY_W,KEY_S),-1,1)
	var pad_brake: bool = false
	if joy_device >= 0:
		roll_input = stick_axis(Input.get_joy_axis(joy_device,JOY_AXIS_LEFT_X))
		pitch_input = -stick_axis(Input.get_joy_axis(joy_device,JOY_AXIS_LEFT_Y))
		yaw_input = stick_axis(Input.get_joy_axis(joy_device,JOY_AXIS_RIGHT_X))
		throttle_input = Input.get_joy_axis(joy_device,JOY_AXIS_TRIGGER_RIGHT)-Input.get_joy_axis(joy_device,JOY_AXIS_TRIGGER_LEFT)
		pad_brake = Input.is_joy_button_pressed(joy_device,JOY_BUTTON_A)
	# Explicit keyboard/gamepad input profile: ramps pilot commands only.
	# No attitude/velocity feedback or changes to simulation state.
	var rate: float = 0.9*seconds
	controls.roll = move_toward(float(controls.roll),clampf(float(initial.solved_controls.roll)+0.35*input_sensitivity*roll_input,-1,1),rate)
	controls.pitch = move_toward(float(controls.pitch),clampf(float(initial.solved_controls.pitch)+0.15*input_sensitivity*pitch_input,-1,1),rate)
	controls.yaw = move_toward(float(controls.yaw),clampf(float(initial.solved_controls.yaw)+0.25*input_sensitivity*yaw_input,-1,1),rate)
	controls.throttle = clampf(float(controls.throttle)+0.25*seconds*throttle_input,0,1)
	controls.trim = clampf(float(controls.trim)+0.08*seconds*axis(KEY_BRACKETRIGHT,KEY_BRACKETLEFT),-1,1)
	var both: bool = brake_hold or Input.is_physical_key_pressed(KEY_SPACE) or pad_brake
	controls.left_brake = 1.0 if both or Input.is_physical_key_pressed(KEY_Q) else 0.0
	controls.right_brake = 1.0 if both or Input.is_physical_key_pressed(KEY_E) else 0.0

func on_joy_connection_changed(device: int, connected: bool) -> void:
	if device == joy_device and not connected:
		joy_device = -1
		open_menu("Controller disconnected")
		status = "CONTROLLER LOST | paused before another physics step; keyboard is selected"

func on_focus_lost() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if not smoke and not visual_smoke and not menu_open and bridge != null:
		open_menu("Flight paused while window is inactive")

func select_controller() -> void:
	if joy_device >= 0:
		joy_device = -1
	else:
		var connected: Array[int] = Input.get_connected_joypads()
		if not connected.is_empty():
			joy_device = connected[0]

func _unhandled_input(event: InputEvent) -> void:
	if menu_open:
		return
	if event is InputEventMouseButton:
		if event.button_index==MOUSE_BUTTON_RIGHT:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if event.pressed else Input.MOUSE_MODE_VISIBLE
		elif event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP,MOUSE_BUTTON_WHEEL_DOWN]:
			var direction: float = -1.0 if event.button_index==MOUSE_BUTTON_WHEEL_UP else 1.0
			if camera_mode in [0,3]:
				camera.fov=clampf(camera.fov+direction*3,35,90)
			else:
				camera_distance=clampf(camera_distance+direction,6,40)
	elif event is InputEventMouseMotion and Input.mouse_mode==Input.MOUSE_MODE_CAPTURED:
		look_angles.x=clampf(look_angles.x-event.relative.x*0.004,-PI,PI)
		look_angles.y=clampf(look_angles.y-event.relative.y*0.004,-1.2,1.2)
	elif event is InputEventJoypadButton and event.pressed and event.device==joy_device and event.button_index==JOY_BUTTON_START:
		open_menu("Flight paused")

func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	if menu_open:
		if event.physical_keycode in [KEY_ESCAPE,KEY_P]:
			close_menu()
			get_viewport().set_input_as_handled()
		return
	match event.physical_keycode:
		KEY_P:
			if paused:
				pause_session(false)
			else:
				open_menu("Flight paused")
		KEY_ESCAPE:
			open_menu("Flight paused")
		KEY_R:
			restart()
		KEY_G:
			start_flight("ground-ready")
		KEY_F:
			start_flight("airborne-prepared")
		KEY_B:
			brake_hold=not brake_hold
		KEY_X:
			if not paused and not blocked and not stalled and bridge != null and not controls.is_empty():
				# Pilot intent only; the next typed command applies at the next tick.
				controls.throttle=0.0
		KEY_C:
			set_camera_mode((camera_mode+1)%4)
		KEY_1:
			set_camera_mode(0)
		KEY_2:
			set_camera_mode(1)
		KEY_3:
			set_camera_mode(2)
		KEY_4:
			set_camera_mode(3)
		KEY_TAB:
			map_visible=not map_visible
			flight_map.visible=map_visible
		KEY_T:
			if map_visible:
				flight_map.call("toggle_runway")
		KEY_EQUAL,KEY_KP_ADD:
			if map_visible:
				flight_map.call("zoom",0.5)
		KEY_MINUS,KEY_KP_SUBTRACT:
			if map_visible:
				flight_map.call("zoom",2.0)
		KEY_HOME:
			look_angles=Vector2.ZERO
		KEY_H:
			help_visible=not help_visible
			panel.call("set_help_visible",help_visible)
		KEY_V:
			panel_visible=not panel_visible
			panel.call("set_panel_visible",panel_visible)
		KEY_J:
			select_controller()
		KEY_M:
			audio_enabled=not audio_enabled
			if sound != null:
				sound.call("set_enabled",audio_enabled)
		KEY_F11:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED if DisplayServer.window_get_mode()==DisplayServer.WINDOW_MODE_FULLSCREEN else DisplayServer.WINDOW_MODE_FULLSCREEN)
	get_viewport().set_input_as_handled()

func set_camera_mode(value: int) -> void:
	camera_mode=clampi(value,0,3)
	forward_view=camera_mode in [0,3]
	look_angles=Vector2.ZERO
	camera_ready=false
	camera.fov=58 if camera_mode==3 else 72
	# Keep the nearby cockpit visible. Ground color and markings share a single
	# surface; their ordering no longer depends on the camera's depth precision.
	camera.near=0.1
	panel_visible=not forward_view
	panel.call("set_panel_visible",panel_visible)
	if panel_viewport!=null:
		panel_viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS if forward_view else SubViewport.UPDATE_DISABLED

func start_flight(start: String) -> void:
	named_start=start
	if restart():
		menu_open=false
		menu.hide()
		last_wall_us=Time.get_ticks_usec()

func open_menu(title: String="Flight paused") -> void:
	Input.mouse_mode=Input.MOUSE_MODE_VISIBLE
	if not paused:
		pause_session(true)
	menu_open=true
	menu_title.text=title
	menu_message.text="Original light-aircraft prototype · synthetic airfield
Engine already running. Instrument panel shows derived native truth.
Arrows fly · W/S throttle · X idle · A/D yaw · H help
B toggle hold · Hold Space brakes · 1/2/3/4 views · Tab map
Right mouse look · scroll zoom · Home recenter · V overlay"
	resume_button.disabled=blocked or stalled
	menu.show()
	resume_button.grab_focus()

func close_menu() -> void:
	if pause_session(false):
		menu_open=false
		menu.hide()
		last_wall_us=Time.get_ticks_usec()

func make_menu(canvas: CanvasLayer) -> void:
	menu=PanelContainer.new()
	menu.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	menu.position=Vector2(-280,-245)
	menu.custom_minimum_size=Vector2(560,490)
	var style:=StyleBoxFlat.new()
	style.bg_color=Color(0.025,0.045,0.065,0.97)
	style.border_color=Color(0.24,0.58,0.72)
	style.set_border_width_all(1)
	style.set_corner_radius_all(14)
	style.content_margin_left=28
	style.content_margin_right=28
	style.content_margin_top=22
	style.content_margin_bottom=22
	menu.add_theme_stylebox_override("panel",style)
	canvas.add_child(menu)
	var box:=VBoxContainer.new()
	box.add_theme_constant_override("separation",6)
	menu.add_child(box)
	menu_title=Label.new()
	menu_title.add_theme_font_size_override("font_size",28)
	box.add_child(menu_title)
	menu_message=Label.new()
	menu_message.add_theme_font_size_override("font_size",14)
	box.add_child(menu_message)
	resume_button=add_menu_button(box,"Resume flight",close_menu)
	add_menu_button(box,"Start on runway",func():start_flight("ground-ready"))
	add_menu_button(box,"Start airborne",func():start_flight("airborne-prepared"))
	var sensitivity:=HSlider.new()
	sensitivity.min_value=0.3
	sensitivity.max_value=1.5
	sensitivity.step=0.1
	sensitivity.value=input_sensitivity
	sensitivity.tooltip_text="Pilot input sensitivity (command mapping only; no flight stabilization)"
	sensitivity.value_changed.connect(func(value:float):input_sensitivity=value)
	box.add_child(sensitivity)
	var sensitivity_label:=Label.new()
	sensitivity_label.text="Pilot input sensitivity · smooth commands · no stabilizer"
	sensitivity_label.add_theme_font_size_override("font_size",14)
	box.add_child(sensitivity_label)
	add_menu_button(box,"Keyboard / gamepad (J)",select_controller)
	add_menu_button(box,"Quit",quit_flight)
	menu.hide()

func add_menu_button(box:VBoxContainer,text:String,action:Callable) -> Button:
	var button:=Button.new()
	button.text=text
	button.custom_minimum_size=Vector2(0,32)
	button.add_theme_font_size_override("font_size",18)
	button.pressed.connect(action)
	box.add_child(button)
	return button

func quit_flight() -> void:
	if quitting:
		return
	quitting=true
	var joined: bool = close_session()
	if sound != null:
		joined=bool(await sound.call("shutdown")) and joined
	get_tree().quit(0 if joined else 1)

func _notification(what: int) -> void:
	if what==NOTIFICATION_WM_CLOSE_REQUEST:
		quit_flight()

func body_quaternion() -> Quaternion:
	var q: Dictionary = snapshot.orientation_body_to_ned
	return Quaternion(float(q.x), float(q.y), float(q.z), float(q.w))

func ned_to_view(v: Vector3) -> Vector3:
	# Attitude is body->CURRENT NED. Rotate current NED into ECEF, then the
	# prepared anchor basis; using current NED as anchor NED would drift scenery.
	var lat: float = float(snapshot.position.latitude_rad)
	var lon: float = float(snapshot.position.longitude_rad)
	var x: float = -sin(lat)*cos(lon)*v.x-sin(lon)*v.y-cos(lat)*cos(lon)*v.z
	var y: float = -sin(lat)*sin(lon)*v.x+cos(lon)*v.y-cos(lat)*sin(lon)*v.z
	var z: float = cos(lat)*v.x-sin(lat)*v.z
	var north: float = -sin(latitude)*cos(longitude)*x-sin(latitude)*sin(longitude)*y+cos(latitude)*z
	var east: float = -sin(longitude)*x+cos(longitude)*y
	var up: float = cos(latitude)*cos(longitude)*x+cos(latitude)*sin(longitude)*y+sin(latitude)*z
	return Vector3(east,up,-north)

func visual_position() -> Vector3:
	var p: Dictionary = snapshot.ecef_position_m
	# Subtract Earth-scale ECEF in binary64 scalars before renderVector3 conversion.
	var dx: float = float(p.x) - float(origin_ecef.x)
	var dy: float = float(p.y) - float(origin_ecef.y)
	var dz: float = float(p.z) - float(origin_ecef.z)
	var n: float = -sin(latitude)*cos(longitude)*dx - sin(latitude)*sin(longitude)*dy + cos(latitude)*dz
	var e: float = -sin(longitude)*dx + cos(longitude)*dy
	var d: float = -cos(latitude)*cos(longitude)*dx - cos(latitude)*sin(longitude)*dy - sin(latitude)*dz
	return Vector3(e, -d, -n)

func visual_basis(q: Quaternion) -> Basis:
	return Basis(ned_to_view(q * Vector3(0,1,0)), ned_to_view(q * Vector3(0,0,-1)), ned_to_view(q * Vector3(-1,0,0)))

func make_world() -> void:
	var scene: Dictionary = load("res://interactive/flight_world.gd").new().build(self)
	airplane=scene.airplane
	camera=scene.camera
	gears=scene.gears
	propeller=scene.get("propeller",null)
	var canvas:=CanvasLayer.new()
	add_child(canvas)
	panel=load("res://interactive/flight_panel.gd").new()
	canvas.add_child(panel)
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel_viewport=SubViewport.new()
	panel_viewport.size=Vector2i(2048,1024)
	panel_viewport.disable_3d=true
	panel_viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	add_child(panel_viewport)
	cockpit_panel=load("res://interactive/flight_panel.gd").new()
	panel_viewport.add_child(cockpit_panel)
	# Keep the authored panel in logical pixels; only its texture is sampled at2x.
	# Full-rect anchors would double the layout as well as the render target.
	cockpit_panel.size=Vector2(1024,512)
	cockpit_panel.scale=Vector2(2,2)
	cockpit_panel.call("set_cockpit_surface",true)
	cockpit_builder=load("res://interactive/flight_cockpit.gd").new()
	cockpit=cockpit_builder.call("build",self,panel_viewport.get_texture())
	flight_map=load("res://interactive/flight_map.gd").new()
	canvas.add_child(flight_map)
	flight_map.call("set_landmarks",scene.get("landmarks",[]))
	flight_map.hide()
	make_menu(canvas)
	if ResourceLoader.exists("res://interactive/flight_sound.gd"):
		sound=load("res://interactive/flight_sound.gd").new()
		add_child(sound)
	set_camera_mode(0)

func show_state(seconds: float=0.0) -> void:
	var map_top: float=124.0 if snapshot.is_empty() or blocked or stalled or native_outcome in ["discarded","error","coverage_blocked"] else 92.0
	flight_map.size=Vector2(minf(420,get_viewport().get_visible_rect().size.x*0.42),minf(500,get_viewport().get_visible_rect().size.y-map_top-14))
	flight_map.position=Vector2(get_viewport().get_visible_rect().size.x-flight_map.size.x-14,map_top)
	if snapshot.is_empty():
		if panel != null:
			var fault_info: Dictionary={"status":status,"outcome":"error","blocked":blocked,"stalled":stalled,"paused":paused,"input_name":"Keyboard"}
			panel.call("set_state",{}, {},held_controls,fault_info)
			cockpit_panel.call("set_state",{}, {},held_controls,fault_info)
			flight_map.call("set_state",{},Vector3.ZERO,Basis.IDENTITY,fault_info)
		return
	var native_basis: Basis=visual_basis(body_quaternion())
	var native_position: Vector3=visual_position()
	var native_pose:=Transform3D(native_basis,native_position)
	var live: bool=not paused and not blocked and not stalled and native_outcome=="completed"
	var presentation: Transform3D=render_pose.sample(float(debt)/BUDGET_DENOMINATOR,live) if render_pose.has_pose() else native_pose
	# Fault/pause displays the copied native endpoint, never a historical blend.
	if not live:
		presentation=native_pose
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
		target_position.y=maxf(target_position.y,0.35)
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
		camera.position.y=maxf(camera.position.y,0.35)
	camera_ready=true
	camera.look_at(look_target,up)
	if propeller!=null and not paused:
		propeller.rotate_z(clampf(seconds,0.0,0.25)*(25+float(held_controls.throttle)*65))
	var view_names: Array[String]=["COCKPIT","CHASE","ORBIT","PANEL"]
	var input_name: String = "Keyboard %.1fx · smooth" % input_sensitivity if joy_device<0 else "Gamepad %.1fx · " % input_sensitivity+Input.get_joy_name(joy_device)
	var display_info: Dictionary={"status":status,"outcome":native_outcome,"blocked":blocked,"stalled":stalled,"paused":paused,"brake_hold":brake_hold,"view_name":view_names[camera_mode],"clearance_m":plane_clearance,"ground_valid":ground_valid,"input_name":input_name,"audio_enabled":audio_enabled}
	panel.call("set_state",snapshot,atmosphere,held_controls,display_info)
	cockpit_panel.call("set_state",snapshot,atmosphere,held_controls,display_info)
	flight_map.call("set_state",snapshot,native_position,native_basis,display_info)

func check(condition: bool, description: String) -> void:
	if not condition:
		failures.append(description)
	evidence[description] = condition

func run_smoke() -> void:
	make_world()
	show_state()
	var profile: String = OS.get_environment("FLIGHT_PREVIEW_PROFILE_ROOT")
	check(not profile.is_empty() and OS.get_user_data_dir().begins_with(profile+"/"),"userdata_isolated")
	check(snapshot.tick=="0" and absf(float(snapshot.position.ellipsoid_height_m)-1.05)<0.00001,"ground_tick_zero_no_hidden_settling")
	check(snapshot.contacts.size()==3 and controls.left_brake==1 and controls.right_brake==1,"ground_ready_native_three_gears_and_held_brakes")
	check(absf(visual_position().y-1.05)<0.001 and absf(visual_position().x)<0.001 and absf(visual_position().z)<0.001,"prepared_plane_position_alignment")
	check(visual_basis(Quaternion.IDENTITY).is_equal_approx(Basis.IDENTITY),"current_NED_anchor_EUS_pose")
	var ground_session: String = snapshot.session_id
	# Explicit automated test driver through the pilot API, never human-mode feedback.
	run_automated_loop()
	check(pause_session(true),"native_ground_pause")
	var saved: String = JSON.stringify(snapshot)
	var stopped: Dictionary = bridge.call("step_fixed",32)
	check(stopped.get("ok",false) and stopped.completed==0 and stopped.outcome=="paused" and JSON.stringify(JSON.parse_string(stopped.aircraft_json))==saved,"paused_batch_actual_zero_ticks")
	check(pause_session(false),"native_ground_resume")
	check(not bridge.call("step_fixed",33).get("ok",true),"batch_over_32_rejected")
	named_start="airborne-prepared"
	check(restart(),"airborne_named_start")
	check(snapshot.session_id!=ground_session and snapshot.tick=="0","fresh_epoch_session_id")
	check(absf(float(snapshot.position.ellipsoid_height_m)-1000)<0.001 and not any_wow(),"airborne_actual_trimmed_state")
	controls.roll=clampf(float(controls.roll)+0.15,-1,1)
	controls.pitch=clampf(float(controls.pitch)+0.015,-1,1)
	controls.yaw=clampf(float(controls.yaw)+0.015,-1,1)
	controls.throttle=clampf(float(controls.throttle)+0.05,0,1)
	controls.trim=0.01
	check(submit_axes(controls),"typed_roll_pitch_yaw_throttle_trim_queued")
	for i in range(4):
		check(step_ticks(30),"controlled_batch_%d" % i)
	check(snapshot.tick=="120" and snapshot.orientation_body_to_ned!=initial.accepted_aircraft.orientation_body_to_ned and absf(float(held_controls.trim)-0.01)<1e-12,"actual_airborne_control_response")
	var copied: Dictionary = bridge.call("read_state")
	check(copied.aircraft_json==last_aircraft_json and copied.held_axes==held_controls,"owned_readback_truth")
	var unauthorized: Dictionary = {"type":"ControlCommand","schema_version":1,"tick":"121","session_id":snapshot.session_id,"sequence":"999","source_id":"scenario.proof","authority":"scenario","assistance":{"profile_id":"unassisted","active":[]},"payload":controls}
	check(not bridge.call("submit",unauthorized).get("ok",true),"scenario_authority_not_exposed")
	check(advance_wall_us(10000) and snapshot.tick=="121" and debt==200000,"fractional_120Hz_debt_retained")
	check(advance_wall_us(300000) and paused and stalled and snapshot.tick=="121" and debt==36200000,"wall_stall_no_silent_tick_or_debt_drop")
	check(not pause_session(false),"stall_cannot_silently_resume")
	var previous_id: String = snapshot.session_id
	named_start="ground-ready"
	check(restart() and snapshot.tick=="0" and debt==0 and snapshot.session_id!=previous_id,"explicit_fresh_ground_reset")
	run_ux_checks()
	show_state()
	check(close_session(),"final_worker_joined")
	finish_smoke()

func run_ux_checks() -> void:
	AircraftChecks.new().check_mesh(self)
	RenderPoseChecks.new().run(self)
	var saved: String = last_aircraft_json
	var saved_controls: Dictionary = held_controls.duplicate(true)
	open_menu("UX functional test")
	check(menu_open and paused and menu.visible,"ux_menu_visibly_pauses_native")
	var result: Dictionary = bridge.call("step_fixed",32)
	check(result.completed==0 and result.aircraft_json==saved and held_controls==saved_controls,"ux_menu_preserves_aircraft_and_controls")
	var key:=InputEventKey.new()
	key.physical_keycode=KEY_F
	key.pressed=true
	_unhandled_key_input(key)
	check(named_start=="ground-ready" and last_aircraft_json==saved,"ux_menu_consumes_flight_shortcuts")
	var menu_intent: Dictionary=controls.duplicate(true)
	controls.throttle=0.65
	var menu_idle_intent: Dictionary=controls.duplicate(true)
	var menu_idle_count: int=submitted_count
	var menu_idle_sequence: int=command_sequence
	key.physical_keycode=KEY_X
	_unhandled_key_input(key)
	check(controls==menu_idle_intent and held_controls==saved_controls and last_aircraft_json==saved and submitted_count==menu_idle_count and command_sequence==menu_idle_sequence,"ux_menu_x_idle_has_no_intent_or_native_side_effect")
	controls=menu_intent
	for view in range(4):
		set_camera_mode(view)
		show_state()
		check(last_aircraft_json==saved and held_controls==saved_controls,"ux_camera_%d_does_not_mutate_flight" % view)
	check(absf(stick_axis(0.1))<0.000001 and absf(stick_axis(-1)+1)<0.000001 and absf(stick_axis(1)-1)<0.000001,"ux_gamepad_dead_zone_and_signed_endpoints")
	close_menu()
	check(not menu_open and not paused and last_aircraft_json==saved,"ux_menu_resume_same_native_state")
	joy_device=123
	on_joy_connection_changed(123,false)
	check(joy_device==-1 and menu_open and paused and last_aircraft_json==saved,"ux_synthetic_gamepad_disconnect_pauses_before_step")
	close_menu()
	set_camera_mode(0)
	# Synthetic engine input event exercises the same physical-key reader.
	key.physical_keycode=KEY_RIGHT
	key.keycode=KEY_RIGHT
	Input.parse_input_event(key)
	Input.flush_buffered_events()
	read_keyboard(0.1)
	check(absf(float(controls.roll)-0.09)<0.00001,"ux_keyboard_press_ramps_command")
	read_keyboard(0.4)
	check(absf(float(controls.roll)-0.35)<0.00001,"ux_keyboard_hold_reaches_profile_limit")
	var release:=InputEventKey.new()
	release.keycode=KEY_RIGHT
	release.physical_keycode=KEY_RIGHT
	release.pressed=false
	Input.parse_input_event(release)
	Input.flush_buffered_events()
	read_keyboard(0.1)
	check(absf(float(controls.roll)-0.26)<0.00001,"ux_keyboard_release_ramps_to_neutral")
	read_keyboard(0.4)
	check(absf(float(controls.roll))<0.00001,"ux_keyboard_neutral_preserves_trim_baseline")
	var saved_snapshot: Dictionary = snapshot.duplicate(true)
	var saved_status: String = status
	snapshot={}
	blocked=true
	status="Initialization unavailable; R starts a fresh attempt"
	show_state()
	check(panel.get("_info").blocked and panel.get("_info").status==status,"ux_missing_initial_state_fault_reaches_panel")
	check(cockpit_panel.get("_info").blocked and not panel.get("_panel_visible"),"ux_fault_visible_with_cockpit_overlay_hidden")
	# Error publications reserve the fault strip before blocked becomes true.
	var saved_outcome: String=native_outcome
	snapshot=saved_snapshot
	blocked=false
	native_outcome="error"
	show_state()
	check(flight_map.position.y==124.0 and panel.get("_info").outcome=="error","ux_error_publication_map_clears_retained_control_strip")
	native_outcome=saved_outcome
	snapshot=saved_snapshot
	blocked=false
	status=saved_status
	var climb: Dictionary=snapshot.duplicate(true)
	climb.orientation_body_to_ned={"w":1.0,"x":0.0,"y":0.0,"z":0.0}
	climb.velocity_body_mps={"x":30.0,"y":40.0,"z":12.0}
	var readings: Dictionary=panel.call("_derive_readings",climb,atmosphere)
	check(absf(float(readings.ground_kt)-50.0*1.9438444924406)<0.000001,"ux_groundspeed_excludes_vertical_component")
	show_state()
	check(cockpit_panel.get("_readings")==panel.get("_readings"),"ux_live_dashboard_and_overlay_same_native_truth")
	check(cockpit.root.transform.is_equal_approx(airplane.transform),"ux_cockpit_uses_authoritative_aircraft_pose")
	set_camera_mode(3)
	show_state()
	check(cockpit.root.visible and not airplane.visible and not panel_visible,"ux_panel_view_has_interior_without_external_shell_or_overlay")
	var map_state: Dictionary=snapshot.duplicate(true)
	flight_map.set("extent_m",4000.0)
	map_state.session_id="map-readonly-fixture"
	map_state.tick="0"
	flight_map.call("set_state",map_state,Vector3(150,3,-400),Basis.IDENTITY)
	var chart:=Rect2(10,10,300,300)
	var runway_point: Vector2=flight_map.call("_point",Vector2(0,-800),chart)
	check(runway_point.distance_to(Vector2(148.75,130))<0.0001,"ux_map_same_tangent_frame_runway_projection")
	flight_map.call("set_state",map_state,Vector3(150,3,-400),Basis.IDENTITY)
	check(flight_map.get("_trail").size()==1 and flight_map.get("_direction")==Vector2.UP,"ux_map_pause_no_duplicate_trail_and_north_heading")
	flight_map.call("set_state",map_state,Vector3(150,3,-400),Basis(Vector3.UP,-PI*0.5))
	check(flight_map.get("_heading_valid") and flight_map.get("_direction").distance_to(Vector2.RIGHT)<0.00001,"ux_map_actual_east_nose_heading")
	flight_map.call("set_state",map_state,Vector3(150,3,-400),Basis(Vector3.RIGHT,PI*0.5))
	check(not flight_map.get("_heading_valid"),"ux_map_vertical_nose_has_no_fabricated_heading")
	for tick in range(1,650):
		map_state.tick=str(tick*120)
		flight_map.call("set_state",map_state,Vector3(tick,3,-400),Basis.IDENTITY)
	check(flight_map.get("_trail").size()==600,"ux_map_history_bounded")
	flight_map.call("zoom",0.00001)
	check(flight_map.get("extent_m")==1000.0,"ux_map_zoom_lower_bound")
	flight_map.call("zoom",100000.0)
	check(flight_map.get("extent_m")==32000.0,"ux_map_zoom_upper_bound")
	flight_map.set("extent_m",8000.0)
	flight_map.call("set_state",snapshot,airplane.position,airplane.basis)
	check(flight_map.get("_trail").size()==1 and flight_map.get("_session")==snapshot.session_id,"ux_map_new_native_session_clears_history")
	check(last_aircraft_json==saved and held_controls==saved_controls,"ux_map_dashboard_and_panel_view_do_not_mutate_native_state")
	# The idle shortcut changes only pilot intent, then uses normal next-tick admission.
	controls={"kind":"axes","roll":0.02,"pitch":0.01,"yaw":-0.03,"throttle":0.6,"mixture":1.0,"left_brake":0.2,"right_brake":0.8,"trim":0.04}
	check(submit_axes(controls) and step_ticks(1),"ux_idle_fixture_actual_nonzero_native_throttle")
	var before_idle: Dictionary=held_controls.duplicate(true)
	var idle_tick: String=snapshot.tick
	var idle_count: int=submitted_count
	var idle_key:=InputEventKey.new()
	idle_key.physical_keycode=KEY_X
	idle_key.pressed=true
	_unhandled_key_input(idle_key)
	var expected_idle: Dictionary=before_idle.duplicate(true)
	expected_idle.throttle=0.0
	check(controls==expected_idle and held_controls==before_idle and snapshot.tick==idle_tick and submitted_count==idle_count,"ux_x_idle_changes_only_pending_pilot_throttle")
	check(submit_axes(controls) and step_ticks(1),"ux_x_idle_uses_normal_next_tick_pilot_command")
	check(held_controls==expected_idle and int(snapshot.tick)==int(idle_tick)+1,"ux_x_idle_actual_native_zero_preserves_all_other_axes")
	show_state()
	var strip: Dictionary=panel.call("_control_strip_values")
	check(strip.throttle_percent==0 and strip.left_percent==20 and strip.right_percent==80 and absf(float(strip.ground_kt)-float(panel.get("_readings").ground_kt))<0.000001,"ux_compact_strip_uses_native_held_axes_and_horizontal_speed")
	run_locator_checks()
	CameraChecks.new().run(self)
	set_camera_mode(0)
	evidence["ux_scope"]="Actual menu/native state and camera checks; synthetic keyboard/gamepad mapping, not hardware acceptance"

func run_locator_checks() -> void:
	check(pause_session(true),"locator_native_paused")
	var native_before: Dictionary=bridge.call("read_state").duplicate(true)
	var inputs_before: Dictionary=controls.duplicate(true)
	var count_before: int=submitted_count
	var sequence_before: int=command_sequence
	var fixture: Dictionary=snapshot.duplicate(true)
	fixture.session_id="locator-geometry-fixture"
	fixture.tick="0"
	flight_map.call("select_runway",36)
	flight_map.call("set_state",fixture,Vector3(100,999,1100),Basis.IDENTITY,{"ground_valid":true,"clearance_m":80.0,"paused":true})
	var south: Dictionary=flight_map.call("_runway_metrics")
	check(absf(south.range_m-sqrt(1010000.0))<0.0001 and absf(south.bearing_deg-354.2894068625)<0.0001,"locator_south_end_range_and_true_bearing")
	check(south.along_m== -1000.0 and south.cross_m==100.0,"locator_36_before_end_and_right_axis")
	check(south.clearance_valid and south.clearance_m==80.0,"locator_height_uses_native_plane_reference_not_render_altitude")
	var trail_count: int=flight_map.get("_trail").size()
	flight_map.call("set_state",fixture,Vector3(100,999,1100),Basis.IDENTITY,{"paused":true})
	check(flight_map.get("_trail").size()==trail_count,"locator_paused_repeat_does_not_duplicate_trail")
	flight_map.call("select_runway",18)
	flight_map.call("set_state",fixture,Vector3(100,80,-2700),Basis.IDENTITY)
	var north: Dictionary=flight_map.call("_runway_metrics")
	check(north.along_m== -1000.0 and north.cross_m== -100.0 and absf(north.bearing_deg-185.7105931375)<0.0001,"locator_18_reciprocal_axis_and_bearing")
	flight_map.call("select_runway",36)
	flight_map.call("set_state",fixture,Vector3(-100,10,-200),Basis(Vector3.RIGHT,PI*0.5))
	var past: Dictionary=flight_map.call("_runway_metrics")
	check(past.along_m==300.0 and past.cross_m== -100.0 and not flight_map.get("_heading_valid"),"locator_past_end_signed_geometry_survives_vertical_nose")
	flight_map.call("set_state",fixture,Vector3(0,10,100),Basis.IDENTITY)
	var zero: Dictionary=flight_map.call("_runway_metrics")
	check(zero.range_m==0.0 and not zero.bearing_valid,"locator_exact_end_has_no_invented_bearing")
	flight_map.call("set_state",fixture,Vector3(100,80,1100),Basis.IDENTITY,{"blocked":true,"outcome":"error","ground_valid":true,"clearance_m":80.0})
	check(flight_map.call("_runway_metrics").is_empty() and flight_map.get("_retained"),"locator_terminal_fault_suppresses_live_guidance")
	flight_map.call("set_state",{},Vector3.ZERO,Basis.IDENTITY)
	check(flight_map.call("_runway_metrics").is_empty() and not flight_map.get("_heading_valid"),"locator_missing_state_has_no_stale_numbers")
	var key:=InputEventKey.new()
	key.physical_keycode=KEY_T
	key.pressed=true
	map_visible=false
	_unhandled_key_input(key)
	check(flight_map.get("_runway")==36,"locator_hidden_map_ignores_runway_key")
	map_visible=true
	_unhandled_key_input(key)
	check(flight_map.get("_runway")==18,"locator_visible_map_selects_reciprocal")
	open_menu("Locator focus test")
	_unhandled_key_input(key)
	check(flight_map.get("_runway")==18,"locator_menu_owns_key_focus")
	menu_open=false
	menu.hide()
	map_visible=false
	flight_map.hide()
	flight_map.call("select_runway",36)
	flight_map.call("set_state",snapshot,airplane.position,airplane.basis,{"paused":true,"ground_valid":ground_valid,"clearance_m":plane_clearance})
	check(flight_map.get("_trail").size()==1,"locator_returns_to_fresh_native_session_trail")
	var landmarks: Array=flight_map.get("_landmarks")
	check(landmarks.size()==6,"locator_six_original_scene_references")
	var expected: Dictionary={"East Farm":Vector3(850,0,-650),"North Water Tank":Vector3(600,0,-2500),"West Pond":Vector3(-1050,0,-900),"South Village":Vector3(950,0,1250),"North Orchard":Vector3(-650,0,-2800)}
	var matching: bool=true
	var seen: Dictionary={}
	for landmark in landmarks:
		seen[landmark.label]=true
		if expected.has(landmark.label):
			matching=matching and landmark.position_eus_m==expected[landmark.label]
		elif landmark.label=="River Bridge":
			matching=matching and absf(landmark.position_eus_m.x-(-2400+260*sin(-2600.0/900.0)+130*sin(-2600.0/390.0)))<0.001 and landmark.position_eus_m.z== -2600.0
		else:
			matching=false
	check(matching and seen.size()==6,"locator_landmarks_match_original_scene_anchor_positions")
	var original_label: String=landmarks[0].label
	var copied_landmarks: Array=landmarks.duplicate(true)
	flight_map.call("set_landmarks",copied_landmarks)
	copied_landmarks[0].label="mutated diagnostic copy"
	check(flight_map.get("_landmarks")[0].label==original_label,"locator_landmark_input_is_copied")
	check(bridge.call("read_state")==native_before and controls==inputs_before and submitted_count==count_before and command_sequence==sequence_before,"locator_selection_and_landmarks_preserve_actual_native_state_and_commands")
	check(pause_session(false),"locator_native_resumed")

func any_wow() -> bool:
	for contact in snapshot.contacts:
		if contact.on_ground:
			return true
	return false

func all_wow() -> bool:
	if snapshot.contacts.size()!=3:
		return false
	for contact in snapshot.contacts:
		if not contact.on_ground:
			return false
	return true

func flight_speed() -> float:
	var v: Dictionary = snapshot.velocity_body_mps
	return sqrt(float(v.x)*float(v.x)+float(v.y)*float(v.y)+float(v.z)*float(v.z))

func angles64() -> Vector2:
	var q: Dictionary = snapshot.orientation_body_to_ned
	return Vector2(atan2(2*(float(q.w)*float(q.x)+float(q.y)*float(q.z)),1-2*(float(q.x)*float(q.x)+float(q.y)*float(q.y))),asin(clampf(2*(float(q.w)*float(q.y)-float(q.z)*float(q.x)),-1,1)))

func automated_axes(desired_pitch: float, throttle: float, brakes: bool=false) -> void:
	# TEST-ONLY feedback, explicitly recorded. Human _process never calls this.
	var q: Dictionary = snapshot.orientation_body_to_ned
	var bank: float = atan2(2*(float(q.w)*float(q.x)+float(q.y)*float(q.z)),1-2*(float(q.x)*float(q.x)+float(q.y)*float(q.y)))
	var pitch: float = asin(clampf(2*(float(q.w)*float(q.y)-float(q.z)*float(q.x)),-1,1))
	var v: Dictionary = snapshot.velocity_body_mps
	var rate: Dictionary = snapshot.angular_rate_body_radps
	var alpha: float = atan2(float(v.z),float(v.x))
	controls={"kind":"axes","roll":clampf(-2*bank-0.3*float(rate.x),-0.25,0.25),"pitch":clampf((alpha-0.02)/0.7+2*(desired_pitch-pitch)-0.5*float(rate.y),-0.4,0.4),"yaw":0.0,"throttle":throttle,"mixture":1.0,"left_brake":1.0 if brakes else 0.0,"right_brake":1.0 if brakes else 0.0,"trim":0.0}

func output_directory() -> String:
	return ProjectSettings.globalize_path("res://") if OS.has_feature("editor") else OS.get_executable_path().get_base_dir()

func run_automated_loop() -> void:
	status="AUTOMATED FUNCTIONAL TEST DRIVER - NOT HUMAN HANDLING EVIDENCE"
	trace_file=FileAccess.open(output_directory().path_join("loop.records.ndjson"),FileAccess.WRITE)
	trace_file.store_line(last_aircraft_json)
	trace_file.store_line(last_atmosphere_json)
	var phase: int = 0
	var phase_ticks: int = 0
	var stationary: bool = false
	var takeoff_tick: int = 0
	var touchdown_tick: int = 0
	var bank_response: bool = false
	var maximum_clearance: float = 0.0
	for i in range(21600):
		var height: float = plane_clearance
		var speed: float = flight_speed()
		var wow: bool = any_wow()
		maximum_clearance=maxf(maximum_clearance,height)
		if phase==0:
			controls={"kind":"axes","roll":0.0,"pitch":0.0,"yaw":0.0,"throttle":0.0,"mixture":1.0,"left_brake":1.0,"right_brake":1.0,"trim":0.0}
			if i>=600:
				stationary=wow and speed<0.05
				phase=1
				phase_ticks=0
		elif phase==1:
			automated_axes(0.12 if speed>32 else 0.0,1.0)
			if not wow and height>3:
				takeoff_tick=int(snapshot.tick)
				phase=2
				phase_ticks=0
		elif phase==2:
			automated_axes(0.08,0.9)
			if height>30:
				phase=3
				phase_ticks=0
		elif phase==3:
			automated_axes(0.03,0.6)
			if phase_ticks<60:
				controls.roll=float(controls.roll)+0.02
			bank_response=bank_response or absf(float(angles64().x))>0.001
			if phase_ticks>360:
				phase=4
				phase_ticks=0
		elif phase==4:
			var velocity: Dictionary = snapshot.velocity_body_mps
			automated_axes(atan2(float(velocity.z),float(velocity.x))-(0.045 if height>4 else 0.018),0.3 if height>4 else 0.0)
			if wow:
				touchdown_tick=int(snapshot.tick)
				phase=5
				phase_ticks=0
		else:
			automated_axes(0.0,0.0,true)
			if phase_ticks>600 and speed<0.1:
				break
		if not submit_axes(controls) or not step_ticks(1):
			break
		if i%12==0:
			trace_file.store_line(last_aircraft_json)
			trace_file.store_line(last_atmosphere_json)
		phase_ticks+=1
	trace_file.store_line(last_aircraft_json)
	trace_file.store_line(last_atmosphere_json)
	trace_file.close()
	trace_file=null
	check(stationary,"automated_driver_settled_through_visible_native_ticks")
	check(takeoff_tick>0 and touchdown_tick>takeoff_tick and all_wow() and flight_speed()<0.1,"automated_single_executive_takeoff_touchdown_allWOW_stop")
	check(bank_response,"automated_airborne_roll_response")
	evidence["automated_loop"]={"scope":"Test-only scripted feedback via pilot API; not unassisted human handling","takeoff_tick":str(takeoff_tick),"touchdown_tick":str(touchdown_tick),"stop_tick":snapshot.tick,"maximum_plane_clearance_m":maximum_clearance,"final_speed_mps":flight_speed(),"all_wow":all_wow(),"last_state":snapshot.duplicate(true)}

func finish_smoke() -> void:
	if sound != null:
		check(bool(await sound.call("shutdown")),"audio_resources_retired")
	evidence["scope"] = "Original combined-model whole-flight preview; headless functional proof only; automated driver distinct from human handling"
	evidence["failures"] = failures
	evidence["passed"] = failures.is_empty()
	var receipt_path: String = ProjectSettings.globalize_path("res://smoke-receipt.json") if OS.has_feature("editor") else OS.get_executable_path().get_base_dir().path_join("smoke-receipt.json")
	var file := FileAccess.open(receipt_path,FileAccess.WRITE)
	file.store_string(JSON.stringify(evidence,"\t"))
	file.close()
	print("WHOLE_FLIGHT_PREVIEW_SMOKE ", JSON.stringify({"passed":failures.is_empty(),"failures":failures}))
	get_tree().quit(0 if failures.is_empty() else 1)

func save_view(name: String) -> void:
	show_state()
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var output: String = OS.get_executable_path().get_base_dir() if not OS.has_feature("editor") else ProjectSettings.globalize_path("res://")
	var image: Image = get_viewport().get_texture().get_image()
	check(image.save_png(output.path_join(name + ".png")) == OK, name + "_PNG_saved")
	evidence[name+"_size"]={"width":image.get_width(),"height":image.get_height()}

func save_environment_view(name: String, eye: Vector3, target: Vector3) -> Image:
	# GPU diagnostic observer only. Never teleport or command the native aircraft.
	show_state()
	airplane.hide()
	cockpit.root.hide()
	panel.call("set_panel_visible",false)
	camera.position=eye
	camera.look_at(target,Vector3.UP)
	camera.fov=60
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var image: Image=get_viewport().get_texture().get_image()
	check(image.save_png(output_directory().path_join(name+".png"))==OK,name+"_PNG_saved")
	evidence[name+"_observer"]={"eye_eus_m":[eye.x,eye.y,eye.z],"target_eus_m":[target.x,target.y,target.z],"width":image.get_width(),"height":image.get_height()}
	return image

func run_environment_visual_checks() -> void:
	check(get_viewport().msaa_3d==Viewport.MSAA_4X,"environment_geometry_four_sample_antialiasing")
	evidence["environment_msaa_3d"]="4x MSAA for geometry edges; procedural ground detail uses shader footprint filtering"
	check(pause_session(true),"environment_native_paused")
	var before: Dictionary=bridge.call("read_state").duplicate(true)
	var saved_controls: Dictionary=controls.duplicate(true)
	var saved_submitted: int=submitted_count
	var saved_sequence: int=command_sequence
	var saved_camera_mode: int=camera_mode
	var saved_fov: float=camera.fov
	var configurations: Array[Array]=[
		["view-environment-runway-south",Vector3(0,1.72,80),Vector3(0,0,-500)],
		["view-environment-runway-north",Vector3(0,2,-1670),Vector3(0,0,-900)],
		["view-environment-approach",Vector3(0,35,340),Vector3(0,0,-200)],
		["view-environment-apron",Vector3(60,18,180),Vector3(100,0,10)],
		["view-environment-overhead",Vector3(180,1400,200),Vector3(0,0,-800)],
		["view-environment-fields",Vector3(3000,1200,-2600),Vector3(900,0,-1500)],
		["view-environment-boundary",Vector3(19500,900,0),Vector3(22500,0,0)],
		["view-environment-corner",Vector3(19500,1200,-19500),Vector3(22500,0,-22500)]
	]
	for landmark in flight_map.get("_landmarks"):
		var position: Vector3=landmark.position_eus_m
		configurations.append(["view-landmark-"+str(landmark.label).to_lower().replace(" ","-"),position+Vector3(220,110,260),position+Vector3.UP*8])
	for configuration in configurations:
		await save_environment_view(configuration[0],configuration[1],configuration[2])
	var first: Image
	for frame in range(5):
		var image: Image=await save_environment_view("view-environment-motion-%02d" % frame,Vector3(frame*3,15,270-frame*18),Vector3(0,0,-500))
		if frame==0:
			first=image
	var returned: Image=await save_environment_view("view-environment-motion-return",Vector3(0,15,270),Vector3(0,0,-500))
	first.convert(Image.FORMAT_RGB8)
	returned.convert(Image.FORMAT_RGB8)
	var original_bytes: PackedByteArray=first.get_data()
	var returned_bytes: PackedByteArray=returned.get_data()
	var changed: int=0
	check(original_bytes.size()==returned_bytes.size(),"environment_return_frame_same_size")
	if original_bytes.size()==returned_bytes.size():
		for index in range(original_bytes.size()):
			if absi(int(original_bytes[index])-int(returned_bytes[index]))>2:
				changed+=1
	var fraction: float=float(changed)/maxi(1,original_bytes.size())
	evidence["environment_return_view_changed_byte_fraction"]=fraction
	check(fraction<0.001,"environment_paused_return_view_stable")
	var after: Dictionary=bridge.call("read_state")
	check(after==before and controls==saved_controls and submitted_count==saved_submitted and command_sequence==saved_sequence,"environment_observer_sweep_preserves_authoritative_state_and_commands")
	evidence["environment_scope"]="20 actual GPU captures: both runway ends, approach, apron, overhead, fields, coverage boundary/corner, six named visual references and five-step camera-only sweep/return; native aircraft paused and unchanged. Observer positions are diagnostics, not flight or pilot handling evidence."
	set_camera_mode(saved_camera_mode)
	camera.fov=saved_fov
	show_state()
	check(pause_session(false),"environment_native_resumed")

func run_visual_smoke() -> void:
	if DisplayServer.get_name() == "headless":
		fail("Visual smoke requires the coordinator-owned GPU window")
		finish_smoke()
		return
	await save_view("view-ground-initial")
	await run_environment_visual_checks()
	named_start="airborne-prepared"
	check(restart(),"visual_airborne_named_start")
	await save_view("view-airborne-initial")
	set_camera_mode(3)
	await save_view("view-panel-focus")
	set_camera_mode(0)
	look_angles=Vector2(-1.1,0.05)
	await save_view("view-side-window")
	look_angles=Vector2.ZERO
	map_visible=true
	flight_map.show()
	flight_map.set("extent_m",8000.0)
	await save_view("view-flight-map")
	flight_map.call("select_runway",18)
	await save_view("view-flight-map-18")
	flight_map.call("select_runway",36)
	map_visible=false
	flight_map.hide()
	set_camera_mode(1)
	await save_view("view-chase")
	set_camera_mode(2)
	look_angles=Vector2(0.85,0.15)
	await save_view("view-orbit")
	set_camera_mode(0)
	controls.roll = clampf(float(controls.roll)+0.15,-1,1)
	controls.pitch = clampf(float(controls.pitch)+0.015,-1,1)
	check(submit_axes(controls), "visual_control_queued")
	for i in range(4):
		check(step_ticks(30), "visual_fixed_step_%d" % i)
	check(pause_session(true), "visual_native_paused")
	await save_view("view-controlled-paused")
	check(pause_session(false), "visual_native_resumed")
	check(restart(), "visual_fresh_attempt_joined")
	named_start="ground-ready"
	check(restart(),"visual_ground_fresh_reset")
	await save_view("view-reset")
	open_menu("Flight paused")
	await save_view("view-pause-menu")
	close_menu()
	panel.call("set_help_visible",true)
	await save_view("view-controls-help")
	panel.call("set_help_visible",false)
	get_window().size=Vector2i(960,540)
	await save_view("view-small-window")
	map_visible=true
	flight_map.show()
	await save_view("view-small-locator")
	map_visible=false
	flight_map.hide()
	set_camera_mode(2)
	await save_view("view-small-overlay")
	set_camera_mode(3)
	await save_view("view-small-panel")
	set_camera_mode(0)
	get_window().size=Vector2i(1920,1080)
	await save_view("view-full-hd")
	var saved_snapshot: Dictionary=snapshot.duplicate(true)
	var saved_status: String=status
	snapshot={}
	blocked=true
	status="Initialization unavailable; R starts a fresh attempt"
	map_visible=true
	flight_map.show()
	await save_view("view-locator-fault")
	map_visible=false
	flight_map.hide()
	await save_view("view-cockpit-fault")
	snapshot=saved_snapshot
	blocked=false
	status=saved_status
	show_state()
	await AircraftChecks.new().capture_views(self)
	await CameraChecks.new().capture(self)
	check(close_session(), "visual_final_joined")
	if sound != null:
		check(bool(await sound.call("shutdown")),"visual_audio_resources_retired")
	evidence["scope"] = "Actual GPU visual smoke; original combined model, no C172S claim"
	evidence["frames_drawn"] = Engine.get_frames_drawn()
	evidence["controlled_native_ticks"] = 120
	evidence["final_tick"] = snapshot.tick
	evidence["failures"] = failures
	evidence["passed"] = failures.is_empty()
	var output: String = OS.get_executable_path().get_base_dir() if not OS.has_feature("editor") else ProjectSettings.globalize_path("res://")
	var receipt := FileAccess.open(output.path_join("visual-receipt.json"),FileAccess.WRITE)
	receipt.store_string(JSON.stringify(evidence,"\t"))
	receipt.close()
	print("WHOLE_FLIGHT_PREVIEW_VISUAL ", JSON.stringify({"passed":failures.is_empty(),"failures":failures}))
	get_tree().quit(0 if failures.is_empty() else 1)

func _exit_tree() -> void:
	close_session()



