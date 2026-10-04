extends "res://interactive/preview.gd"
# Original MIT production-loop scene using the accepted native facade.
# The original preview remains separately runnable; legacy proof flags keep its
# frozen test driver. Ordinary interactive flight uses exactly one facade.
const Facade = preload("res://simulation/session_facade.gd")
const Frames = preload("res://simulation/canonical_frames.gd")
const Participant = preload("res://simulation/origin_participant.gd")
var facade: RefCounted
var prepared: Dictionary={}
var speed_button: Button
var world_root: Node3D
var light_root: Node3D
var legacy_proof: bool="--smoke" in OS.get_cmdline_user_args() or "--visual-smoke" in OS.get_cmdline_user_args()
var facade_visual: bool="--facade-visual-smoke" in OS.get_cmdline_user_args()

func _ready() -> void:
	if "--facade-checks" in OS.get_cmdline_user_args():
		set_process(false)
		var harness: Script=load("res://sim_loop_checks.gd")
		if harness==null or not harness.can_instantiate():
			push_error("Facade checks harness unavailable")
			get_tree().quit(1)
			return
		add_child(harness.new())
		return
	super._ready()
	if not legacy_proof and facade_visual:
		set_process(false)
		call_deferred("run_facade_visual")

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

func close_session() -> bool:
	if legacy_proof:
		return super.close_session()
	render_pose.clear()
	if facade==null:
		bridge=null
		return true
	var result: Dictionary=facade.close()
	if result.ok:
		facade=null
		bridge=null
	else:
		adopt_result(result)
	return result.ok

func restart() -> bool:
	if legacy_proof:
		return super.restart()
	if not close_session():
		return fail("Native worker did not join")
	facade=Facade.new()
	# The inherited view checks a nonnull host reference; it never owns or calls
	# a native executive. Ordinary lifecycle/input overrides use the facade.
	bridge=facade
	var model_root: String=ProjectSettings.globalize_path("res://models") if OS.has_feature("editor") else OS.get_executable_path().get_base_dir().path_join("models")
	var result: Dictionary=facade.start(model_root,named_start)
	if not result.ok:
		return fail(result.error)
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
			return fail("Invalid canonical scene participant "+item.id)
		if item.id in ["ownship","cockpit"] and not node.call("set_canonical_pose",result.readback.canonical.ecef_position_m,node.basis):
			return fail("Invalid binary64 ownship origin source")
		var registered: Dictionary=facade.render_origin.register_participant(item.id,node,item.categories)
		if not registered.ok:
			return fail(registered.error)
	if not facade.render_origin.register_participant("nonspatial",null,["spatial_audio","local_particles"]).ok:
		return fail("Required absent origin categories rejected")
	var adopted: Dictionary=facade.render_origin.rebase(prepared.ecef)
	if not adopted.ok:
		return fail(adopted.error)
	camera_ready=false
	look_angles=Vector2.ZERO
	brake_hold=float(controls.left_brake)>0.5 and float(controls.right_brake)>0.5
	submitted_count=0
	event_count=0
	attempt+=1
	status="LIVE | %s | fresh attempt %d | engine already running"%[named_start,attempt]
	last_wall_us=Time.get_ticks_usec()
	return true

func adopt_result(result: Dictionary) -> void:
	var state: Dictionary=result.readback
	if state.aircraft!=null:
		snapshot=state.aircraft.duplicate(true)
		atmosphere=state.atmosphere.duplicate(true)
		held_controls=state.held_axes.duplicate(true)
		last_aircraft_json=JSON.stringify(snapshot,"",false,true)
		last_atmosphere_json=JSON.stringify(atmosphere,"",false,true)
		var ground: Dictionary=facade.call("_ground_display")
		ground_valid=ground.ground_query_valid
		plane_clearance=ground.plane_clearance_m
	paused=state.paused or state.host_mode!="live"
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
	if facade==null:
		return false
	var result: Dictionary=facade.set_paused(value)
	adopt_result(result)
	last_wall_us=Time.get_ticks_usec()
	return result.ok

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
	if not paused and not menu_open and facade!=null:
		read_keyboard(minf(float(elapsed)/1000000.0,0.25))
		if submit_axes(controls):
			advance_wall_us(elapsed)
	elif paused and facade!=null:
		adopt_result(facade.advance_wall_us(0))
	show_state(clampf(float(elapsed)/1000000.0,0.0,0.25))
	if sound!=null and not snapshot.is_empty():
		sound.call("update_audio",float(held_controls.get("throttle",0)),flight_speed(),paused,any_wow())

func make_menu(canvas: CanvasLayer) -> void:
	super.make_menu(canvas)
	if legacy_proof:
		return
	speed_button=add_menu_button(menu.get_child(0),"Flight speed: 1x  (F5 / F6)",cycle_flight_scale)
	menu.get_child(0).move_child(speed_button,6)
	# Keep the expanded menu inside the established minimum 960x540 window.
	menu.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	menu.custom_minimum_size=Vector2(560,516)
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

func _unhandled_key_input(event: InputEvent) -> void:
	if not legacy_proof and event is InputEventKey and event.pressed and not event.echo and event.physical_keycode in [KEY_F5,KEY_F6]:
		var scales: Array=[0.25,0.5,1.0,2.0,4.0]
		var current: float=facade.readback().time_scale if facade!=null else 1.0
		var index: int=scales.find(current)
		index=clampi(index+(-1 if event.physical_keycode==KEY_F5 else 1),0,scales.size()-1)
		set_flight_scale(scales[index])
		get_viewport().set_input_as_handled()
		return
	super._unhandled_key_input(event)

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
	flight_map.size=Vector2(minf(420,get_viewport().get_visible_rect().size.x*0.42),minf(500,get_viewport().get_visible_rect().size.y-map_top-14))
	flight_map.position=Vector2(get_viewport().get_visible_rect().size.x-flight_map.size.x-14,map_top)
	var current: Dictionary=facade.readback()
	if snapshot.is_empty() or current.aircraft==null or current.canonical==null:
		suppress_geometry()
		if panel != null:
			var fault_info: Dictionary={"status":status,"outcome":"error","blocked":blocked,"stalled":stalled,"paused":paused,"input_name":"Keyboard"}
			fault_info.blocked=true
			fault_info.paused=true
			panel.call("set_state",snapshot,atmosphere,held_controls,fault_info)
			cockpit_panel.call("set_state",snapshot,atmosphere,held_controls,fault_info)
			flight_map.call("set_state",snapshot,Vector3.ZERO,Basis.IDENTITY,fault_info)
		return
	var truth: Dictionary=facade.readback()
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
		var fault_info: Dictionary={"status":status,"outcome":native_outcome,"blocked":true,"stalled":stalled,"paused":true,"input_name":"Keyboard","clearance_m":plane_clearance,"ground_valid":ground_valid}
		panel.call("set_state",snapshot,atmosphere,held_controls,fault_info)
		cockpit_panel.call("set_state",snapshot,atmosphere,held_controls,fault_info)
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
		propeller.rotate_z(clampf(seconds,0.0,0.25)*(25+float(held_controls.throttle)*65))
	var view_names: Array[String]=["COCKPIT","CHASE","ORBIT","PANEL"]
	var input_name: String = "Keyboard %.1fx · smooth" % input_sensitivity if joy_device<0 else "Gamepad %.1fx · " % input_sensitivity+Input.get_joy_name(joy_device)
	var display_info: Dictionary={"status":status,"outcome":native_outcome,"blocked":blocked,"stalled":stalled,"paused":paused,"brake_hold":brake_hold,"view_name":view_names[camera_mode],"clearance_m":plane_clearance,"ground_valid":ground_valid,"input_name":input_name,"audio_enabled":audio_enabled}
	panel.call("set_state",snapshot,atmosphere,held_controls,display_info)
	cockpit_panel.call("set_state",snapshot,atmosphere,held_controls,display_info)
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
