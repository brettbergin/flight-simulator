extends Node3D

const HZ: int = 120
const BUDGET_DENOMINATOR: int = 1000000
const DEBT_LIMIT: int = 250000 * HZ
var bridge: RefCounted
var snapshot: Dictionary = {}
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

func close_session() -> bool:
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
	paused = false
	stalled = false
	blocked = false
	brake_hold = float(controls.left_brake)>0.5 and float(controls.right_brake)>0.5
	command_sequence = 0
	lifecycle_sequence = 0
	submitted_count = 0
	event_count = 0
	attempt += 1
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
	held_controls = reply.held_axes.duplicate(true)
	ground_valid = reply.ground_query_valid
	plane_clearance = float(reply.plane_clearance_m)
	native_outcome = reply.outcome

func fail(message: String) -> bool:
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

func step_ticks(count: int) -> bool:
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
		paused = true
		blocked = true
		status = "NATIVE %s | %d actual ticks | %s | R fresh attempt; retained state is historical on discard" % [reply.outcome,completed,reply.fault]
		return false
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
	if not paused and bridge != null:
		read_keyboard(minf(float(elapsed) / 1000000.0, 0.25))
		if submit_axes(controls):
			advance_wall_us(elapsed)
	if not smoke:
		show_state()

func axis(positive: Key, negative: Key) -> float:
	return float(Input.is_physical_key_pressed(positive)) - float(Input.is_physical_key_pressed(negative))

func read_keyboard(seconds: float) -> void:
	controls.roll = clampf(float(initial.solved_controls.roll)+0.35*axis(KEY_RIGHT,KEY_LEFT),-1,1)
	controls.pitch = clampf(float(initial.solved_controls.pitch)+0.15*axis(KEY_DOWN,KEY_UP),-1,1)
	controls.yaw = clampf(float(initial.solved_controls.yaw)+0.25*axis(KEY_D,KEY_A),-1,1)
	controls.throttle = clampf(float(controls.throttle)+0.25*seconds*axis(KEY_PAGEUP,KEY_PAGEDOWN),0,1)
	controls.trim = clampf(float(controls.trim)+0.08*seconds*axis(KEY_BRACKETRIGHT,KEY_BRACKETLEFT),-1,1)
	var both: bool = brake_hold or Input.is_physical_key_pressed(KEY_SPACE)
	controls.left_brake = 1.0 if both or Input.is_physical_key_pressed(KEY_Q) else 0.0
	controls.right_brake = 1.0 if both or Input.is_physical_key_pressed(KEY_E) else 0.0

func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	if event.physical_keycode==KEY_P:
		pause_session(not paused)
	elif event.physical_keycode==KEY_R:
		restart()
	elif event.physical_keycode==KEY_G:
		named_start="ground-ready"
		restart()
	elif event.physical_keycode==KEY_F:
		named_start="airborne-prepared"
		restart()
	elif event.physical_keycode==KEY_B:
		brake_hold=not brake_hold
	elif event.physical_keycode==KEY_C:
		forward_view=not forward_view
	elif event.physical_keycode==KEY_ESCAPE:
		get_tree().quit(0 if close_session() else 1)

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

func make_box(parent: Node3D, size: Vector3, at: Vector3, color: Color) -> void:
	var node := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.9
	mesh.material = material
	node.mesh = mesh
	node.position = at
	parent.add_child(node)

func make_world() -> void:
	var env := WorldEnvironment.new()
	var config := Environment.new()
	config.background_mode = Environment.BG_COLOR
	config.background_color = Color(0.32,0.58,0.83)
	config.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	config.ambient_light_color = Color(0.85,0.88,1)
	config.ambient_light_energy = 0.75
	env.environment = config
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-45,-35,0)
	sun.light_energy = 1.1
	add_child(sun)
	# Congruent immutable prepared ECEF plane. Meshes have no physics/colliders.
	make_box(self, Vector3(40000,2,40000), Vector3(0,-1,0), Color(0.22,0.38,0.18))
	make_box(self, Vector3(40,0.2,1800), Vector3(0,0.02,-800), Color(0.15,0.16,0.17))
	for i in range(20):
		make_box(self, Vector3(1.5,0.1,35), Vector3(0,0.16,-i*85), Color.WHITE)
	for i in range(-12,13):
		make_box(self, Vector3(40000,0.1,1), Vector3(0,0.12,i*1000), Color(0.30,0.45,0.22))
		make_box(self, Vector3(1,0.1,40000), Vector3(i*1000,0.12,0), Color(0.30,0.45,0.22))
	airplane = Node3D.new()
	add_child(airplane)
	make_box(airplane, Vector3(0.8,0.7,5), Vector3.ZERO, Color(0.95,0.95,0.9))
	make_box(airplane, Vector3(9,0.15,1.1), Vector3(0,0,0), Color(0.8,0.18,0.10))
	make_box(airplane, Vector3(3,0.12,0.8), Vector3(0,0,2), Color(0.8,0.18,0.10))
	make_box(airplane, Vector3(0.12,1.1,0.8), Vector3(0,0.5,2), Color(0.8,0.18,0.10))
	for id in ["gear.nose","gear.left","gear.right"]:
		var wheel := MeshInstance3D.new()
		var mesh := SphereMesh.new()
		mesh.radius=0.12
		mesh.height=0.24
		wheel.mesh=mesh
		airplane.add_child(wheel)
		gears[id]=wheel
	camera = Camera3D.new()
	camera.fov = 72
	camera.far = 50000
	camera.current = true
	add_child(camera)
	var canvas := CanvasLayer.new()
	add_child(canvas)
	var backing := ColorRect.new()
	backing.color = Color(0.01,0.02,0.03,0.85)
	backing.position = Vector2(12,12)
	backing.size = Vector2(1180,275)
	canvas.add_child(backing)
	label = Label.new()
	label.position = Vector2(24,18)
	label.add_theme_font_size_override("font_size", 17)
	canvas.add_child(label)

func show_state() -> void:
	if snapshot.is_empty():
		label.text="WHOLE-FLIGHT ENGINEERING PROTOTYPE — NOT C172S\n"+status
		return
	var q: Quaternion = body_quaternion()
	var basis: Basis = visual_basis(q)
	airplane.transform=Transform3D(basis,visual_position())
	for contact in snapshot.contacts:
		if gears.has(contact.id):
			var point: Dictionary = contact.point_body_m
			gears[contact.id].position=Vector3(float(point.y),-float(point.z),-float(point.x))
	airplane.visible=not forward_view
	camera.position=airplane.position+basis*(Vector3(0,0.7,-1.5) if forward_view else Vector3(0,3.5,13))
	camera.look_at(airplane.position+basis*Vector3(0,0.7,-60),basis.y)
	var forward: Vector3 = q*Vector3(1,0,0)
	var right: Vector3 = q*Vector3(0,1,0)
	var down: Vector3 = q*Vector3(0,0,1)
	var v: Dictionary = snapshot.velocity_body_mps
	var body_velocity := Vector3(float(v.x),float(v.y),float(v.z))
	var ned_velocity: Vector3 = q*body_velocity
	var bank: float = atan2(right.z,down.z)
	var pitch: float = asin(clampf(-forward.z,-1,1))
	var heading: float = fposmod(rad_to_deg(atan2(forward.y,forward.x)),360)
	var wow_text: String = ""
	for contact in snapshot.contacts:
		var force: Dictionary = contact.force_body_n
		var magnitude: float = sqrt(float(force.x)*float(force.x)+float(force.y)*float(force.y)+float(force.z)*float(force.z))
		wow_text += "%s: %s %.0fN   " % [contact.id,"WOW" if contact.on_ground else "AIR",magnitude]
	var clearance: String = "%.2f m" % plane_clearance if ground_valid else "UNAVAILABLE"
	label.text="WHOLE-FLIGHT ENGINEERING PROTOTYPE — NOT C172S | engine already running; no startup procedures\n"+status+"\n"+"CG ellipsoid height %.2f m | Synthetic-plane clearance %s | Earth-relative speed %.1f m/s\n" % [float(snapshot.position.ellipsoid_height_m),clearance,body_velocity.length()]+"True heading %.1f° | Pitch %.1f° | Bank %.1f° | Vertical speed %.1f m/s | Tick %s /120Hz\n" % [heading,rad_to_deg(pitch),rad_to_deg(bank),-ned_velocity.z,snapshot.tick]+wow_text+"\n"+"ACTUAL throttle %.0f%% | trim %.3f | brakes L %.0f%% / R %.0f%% | B hold %s | %s view\n" % [float(held_controls.throttle)*100,float(held_controls.trim),float(held_controls.left_brake)*100,float(held_controls.right_brake)*100,"ON" if brake_hold else "OFF","forward engineering" if forward_view else "chase"]+"Arrows roll/pitch (Down nose-up) | A/D yaw+steer | PgUp/PgDn throttle | [ / ] trim\n"+"B toggle brake hold | Space both service brakes | Q/E left/right brake | C camera | P pause | R fresh | G ground / F airborne | Esc quit\n"+"Synthetic 40km prepared plane; generic original airframe; no calibrated performance, systems or training-credit claim"

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
	show_state()
	check(close_session(),"final_worker_joined")
	finish_smoke()

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

func run_visual_smoke() -> void:
	if DisplayServer.get_name() == "headless":
		fail("Visual smoke requires the coordinator-owned GPU window")
		finish_smoke()
		return
	await save_view("view-ground-initial")
	named_start="airborne-prepared"
	check(restart(),"visual_airborne_named_start")
	await save_view("view-airborne-initial")
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
	check(close_session(), "visual_final_joined")
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



