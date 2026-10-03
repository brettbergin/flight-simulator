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
var failures: Array[String] = []
var evidence: Dictionary = {}
var submitted_count: int = 0
var event_count: int = 0

func _ready() -> void:
	smoke = "--smoke" in OS.get_cmdline_user_args()
	visual_smoke = "--visual-smoke" in OS.get_cmdline_user_args()
	if not smoke:
		make_world()
	if not restart():
		if smoke:
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
	if not ClassDB.class_exists("FlightProofSession"):
		return fail("Accepted FlightProofSession extension unavailable")
	bridge = ClassDB.instantiate("FlightProofSession") as RefCounted
	var model_root: String = ProjectSettings.globalize_path("res://models") if OS.has_feature("editor") else OS.get_executable_path().get_base_dir().path_join("models")
	var reply: Dictionary = bridge.call("open_session", model_root, FileAccess.get_file_as_bytes("res://initializer.bin"))
	if not reply.get("ok", false):
		return fail("Initialization failed: " + str(reply))
	initial = JSON.parse_string(reply.initialization_json)
	snapshot = JSON.parse_string(reply.aircraft_json)
	controls = initial.solved_controls.duplicate(true)
	last_submitted = controls.duplicate(true)
	origin_ecef = snapshot.ecef_position_m.duplicate(true)
	latitude = float(snapshot.position.latitude_rad)
	longitude = float(snapshot.position.longitude_rad)
	debt = 0
	paused = false
	stalled = false
	blocked = false
	command_sequence = 0
	lifecycle_sequence = 0
	submitted_count = 0
	event_count = 0
	attempt += 1
	status = "LIVE | fresh airborne attempt %d | original trimmed model" % attempt
	last_wall_us = Time.get_ticks_usec()
	evidence["runtime_modules"] = reply.runtime_modules
	evidence["user_data_directory"] = OS.get_user_data_dir()
	evidence["initialization"] = initial
	return true

func fail(message: String) -> bool:
	status = message + " | R starts a fresh airborne attempt"
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

func ground_limit(clearance_m: float, down_mps: float, count: int) -> bool:
	return clearance_m <= 100.0 + maxf(0.0, down_mps) * float(count) / HZ

func step_ticks(count: int) -> bool:
	var speed: Dictionary = snapshot.velocity_body_mps
	var vertical: Vector3 = body_quaternion() * Vector3(float(speed.x), float(speed.y), float(speed.z))
	if ground_limit(visual_position().y + 1000.0, vertical.z, count):
		pause_session(true)
		blocked = true
		status = "UNSUPPORTED GROUND PROXIMITY: flight paused above illustrative field; R fresh airborne attempt"
		return false
	var old_tick: int = int(snapshot.tick)
	var reply: Dictionary = bridge.call("step_fixed", count)
	if not reply.get("ok", false) or not reply.get("stepped", false):
		return fail("Native flight-only solver stopped: " + str(reply))
	var next: Dictionary = JSON.parse_string(reply.aircraft_json)
	if next.validity != "valid" or int(next.tick) != old_tick + count:
		return fail("Invalid state or unexpected native tick boundary")
	snapshot = next
	event_count += reply.events_json.size()
	return true

# Integer scaled microseconds preserve fractional120Hz ticks. A stall is frozen
# BEFORE stepping. Its debt remains visible until an explicit fresh attempt.
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
		debt -= count * BUDGET_DENOMINATOR
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
	controls.roll = clampf(float(initial.solved_controls.roll) + 0.35 * axis(KEY_RIGHT, KEY_LEFT), -1, 1)
	controls.pitch = clampf(float(initial.solved_controls.pitch) + 0.15 * axis(KEY_DOWN, KEY_UP), -1, 1)
	controls.yaw = clampf(float(initial.solved_controls.yaw) + 0.25 * axis(KEY_D, KEY_A), -1, 1)
	controls.throttle = clampf(float(controls.throttle) + 0.25 * seconds * axis(KEY_PAGEUP, KEY_PAGEDOWN), 0, 1)
	controls.trim = clampf(float(controls.trim) + 0.08 * seconds * axis(KEY_BRACKETRIGHT, KEY_BRACKETLEFT), -1, 1)

func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	if event.physical_keycode == KEY_P:
		pause_session(not paused)
	elif event.physical_keycode == KEY_R:
		restart()
	elif event.physical_keycode == KEY_ESCAPE:
		get_tree().quit(0 if close_session() else 1)

func body_quaternion() -> Quaternion:
	var q: Dictionary = snapshot.orientation_body_to_ned
	return Quaternion(float(q.x), float(q.y), float(q.z), float(q.w))

func ned_to_view(v: Vector3) -> Vector3:
	return Vector3(v.y, -v.z, -v.x)

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
	# Illustrative tangent-plane scenery; zero ellipsoid height at start projection.
	make_box(self, Vector3(40000,2,40000), Vector3(0,-1001,0), Color(0.22,0.38,0.18))
	make_box(self, Vector3(40,0.2,1800), Vector3(0,-999.8,-2500), Color(0.15,0.16,0.17))
	for i in range(20):
		make_box(self, Vector3(1.5,0.1,35), Vector3(0,-999.6,-3350+i*85), Color.WHITE)
	for i in range(-12,13):
		make_box(self, Vector3(40000,0.1,1), Vector3(0,-999.7,i*1000), Color(0.30,0.45,0.22))
		make_box(self, Vector3(1,0.1,40000), Vector3(i*1000,-999.7,0), Color(0.30,0.45,0.22))
	airplane = Node3D.new()
	add_child(airplane)
	make_box(airplane, Vector3(0.8,0.7,5), Vector3.ZERO, Color(0.95,0.95,0.9))
	make_box(airplane, Vector3(9,0.15,1.1), Vector3(0,0,0), Color(0.8,0.18,0.10))
	make_box(airplane, Vector3(3,0.12,0.8), Vector3(0,0,2), Color(0.8,0.18,0.10))
	make_box(airplane, Vector3(0.12,1.1,0.8), Vector3(0,0.5,2), Color(0.8,0.18,0.10))
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
	backing.size = Vector2(1060,245)
	canvas.add_child(backing)
	label = Label.new()
	label.position = Vector2(24,18)
	label.add_theme_font_size_override("font_size", 19)
	canvas.add_child(label)

func show_state() -> void:
	if snapshot.is_empty():
		label.text = "AIRBORNE ENGINEERING PROTOTYPE — NOT C172S; ground contact unavailable\n" + status
		return
	var q: Quaternion = body_quaternion()
	var basis: Basis = visual_basis(q)
	airplane.transform = Transform3D(basis, visual_position())
	camera.position = airplane.position + basis * Vector3(0,3.5,13)
	camera.look_at(airplane.position + basis * Vector3(0,0,-25), basis.y)
	var forward: Vector3 = q * Vector3(1,0,0)
	var right: Vector3 = q * Vector3(0,1,0)
	var down: Vector3 = q * Vector3(0,0,1)
	var velocity: Dictionary = snapshot.velocity_body_mps
	var body_velocity := Vector3(float(velocity.x),float(velocity.y),float(velocity.z))
	var ned_velocity: Vector3 = q * body_velocity
	var bank: float = atan2(right.z, down.z)
	var pitch: float = asin(clampf(-forward.z,-1,1))
	var heading: float = fposmod(rad_to_deg(atan2(forward.y,forward.x)),360)
	label.text = "AIRBORNE ENGINEERING PROTOTYPE — NOT C172S; ground contact unavailable\n" + status + "\n" + "Ellipsoid height %.1f m | Ground-relative speed %.1f m/s | Vertical speed %.1f m/s\n" % [float(snapshot.position.ellipsoid_height_m), body_velocity.length(), -ned_velocity.z] + "True heading %.1f° | Pitch %.1f° | Bank %.1f° | Tick %s /120 Hz\n" % [heading,rad_to_deg(pitch),rad_to_deg(bank),snapshot.tick] + "Throttle %.0f%% | Trim %.3f | Unassisted | scenery: illustrative tangent plane\n" % [float(controls.throttle)*100,float(controls.trim)] + "Arrows: roll/pitch (Down = nose up) | A/D: yaw | PgUp/PgDn: throttle | [ / ]: trim\n" + "P: pause/resume | R: fresh airborne attempt | Esc: quit | No takeoff / landing model"

func check(condition: bool, description: String) -> void:
	if not condition:
		failures.append(description)
	evidence[description] = condition

func run_smoke() -> void:
	make_world()
	show_state()
	check(ground_limit(90,0,32) and ground_limit(110,60,32) and not ground_limit(1000,0,32), "explicit_illustrative_ground_guard_math")
	var profile: String = OS.get_environment("FLIGHT_PREVIEW_PROFILE_ROOT").replace("\\", "/")
	check(not profile.is_empty() and OS.get_user_data_dir().replace("\\", "/").begins_with(profile + "/"), "user_data_isolated_to_preview")
	check(snapshot.tick == "0", "starts_at_accepted_tick_zero")
	check(absf(float(snapshot.position.ellipsoid_height_m)-1000) < 0.001, "actual_ellipsoid_start_1000m")
	check(visual_position().length() < 0.001, "initial_tangent_origin")
	check(visual_basis(Quaternion.IDENTITY).is_equal_approx(Basis.IDENTITY), "FRD_NED_render_mapping_identity")
	for i in range(300):
		if not step_ticks(32):
			break
	check(snapshot.tick == "9600", "uncontrolled_80_second_native_flight")
	evidence["80s_aircraft"] = snapshot.duplicate(true)
	check(restart(), "restart_joined_fresh_trimmed_worker")
	var baseline: Dictionary = controls.duplicate(true)
	controls.roll = clampf(float(controls.roll)+0.15,-1,1)
	controls.pitch = clampf(float(controls.pitch)+0.015,-1,1)
	controls.yaw = clampf(float(controls.yaw)+0.015,-1,1)
	controls.throttle = clampf(float(controls.throttle)+0.05,0,1)
	controls.trim = 0.01
	check(submit_axes(controls), "typed_pilot_axes_queued")
	for i in range(4):
		if not step_ticks(30):
			break
	check(snapshot.tick == "120", "actual_controlled_120_ticks")
	check(snapshot.orientation_body_to_ned != initial.accepted_aircraft.orientation_body_to_ned, "actual_attitude_response")
	check(absf(float(snapshot.configuration.trim_fraction)-0.01)<1e-12, "actual_trim_response")
	var saved: String = JSON.stringify(snapshot)
	check(pause_session(true), "native_pause_accepted")
	var no_step: Dictionary = bridge.call("step_fixed",1)
	check(no_step.get("ok",false) and not no_step.get("stepped",true) and JSON.stringify(JSON.parse_string(no_step.aircraft_json))==saved, "paused_native_state_unchanged")
	check(pause_session(false), "native_resume_accepted")
	check(submit_axes(baseline), "neutral_release_to_solved_controls")
	check(advance_wall_us(10000), "integer_wall_step")
	check(snapshot.tick == "121" and debt == 200000, "fractional_tick_debt_retained")
	var prior_tick: String = snapshot.tick
	check(advance_wall_us(300000), "wall_stall_frozen")
	check(stalled and paused and snapshot.tick==prior_tick and debt==36200000, "overrun_preserved_without_physics_step")
	check(not pause_session(false) and snapshot.tick==prior_tick, "overrun_cannot_silently_resume_or_drop")
	check(restart() and debt==0 and snapshot.tick=="0", "explicit_fresh_attempt_resets_debt")
	show_state()
	evidence["controlled_aircraft"] = JSON.parse_string(saved)
	check(close_session(), "final_worker_joined")
	finish_smoke()

func finish_smoke() -> void:
	evidence["scope"] = "Original-model airborne preview; headless functional evidence only, no GPU, C172S or ground claim"
	evidence["failures"] = failures
	evidence["passed"] = failures.is_empty()
	var receipt_path: String = ProjectSettings.globalize_path("res://smoke-receipt.json") if OS.has_feature("editor") else OS.get_executable_path().get_base_dir().path_join("smoke-receipt.json")
	var file := FileAccess.open(receipt_path,FileAccess.WRITE)
	file.store_string(JSON.stringify(evidence,"\t"))
	file.close()
	print("AIRBORNE_PREVIEW_SMOKE ", JSON.stringify({"passed":failures.is_empty(),"failures":failures}))
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
	await save_view("view-initial")
	controls.roll = clampf(float(controls.roll)+0.15,-1,1)
	controls.pitch = clampf(float(controls.pitch)+0.015,-1,1)
	check(submit_axes(controls), "visual_control_queued")
	for i in range(4):
		check(step_ticks(30), "visual_fixed_step_%d" % i)
	check(pause_session(true), "visual_native_paused")
	await save_view("view-controlled-paused")
	check(pause_session(false), "visual_native_resumed")
	check(restart(), "visual_fresh_attempt_joined")
	await save_view("view-reset")
	check(close_session(), "visual_final_joined")
	evidence["scope"] = "Actual GPU visual smoke; original synthetic airborne model only"
	evidence["frames_drawn"] = Engine.get_frames_drawn()
	evidence["controlled_native_ticks"] = 120
	evidence["final_tick"] = snapshot.tick
	evidence["failures"] = failures
	evidence["passed"] = failures.is_empty()
	var output: String = OS.get_executable_path().get_base_dir() if not OS.has_feature("editor") else ProjectSettings.globalize_path("res://")
	var receipt := FileAccess.open(output.path_join("visual-receipt.json"),FileAccess.WRITE)
	receipt.store_string(JSON.stringify(evidence,"\t"))
	receipt.close()
	print("AIRBORNE_PREVIEW_VISUAL ", JSON.stringify({"passed":failures.is_empty(),"failures":failures}))
	get_tree().quit(0 if failures.is_empty() else 1)

func _exit_tree() -> void:
	close_session()



