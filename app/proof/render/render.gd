extends Node
# Isolated feasibility experiment, not aircraft/world/simulation integration.
var viewport: SubViewport
var camera: Camera3D
var elapsed: float = 0.0
var frames: Array = []
var gpu_ms: Array = []
var render_cpu_ms: Array = []
var process_max_ms: Array = []
var last_us: int = 0
var start_us: int = 0
var sample_second: int = -1
var duration: float = 30.0
var warmup: float = 10.0
var capture_done := false
var peak_video_bytes: int = 0
var last_gpu_frame: int = -1
var duplicate_gpu_observations: int = 0
var raw_trace: FileAccess
var render_size := Vector2i(2560,1440)
var fov: float = 70.0
var output: String
var fixture: String = "overcast"
var world: Node3D
var sunlight: DirectionalLight3D
var origin_version: int = 0
var origin: Array = []
var original_frame: Array = []
var anchor: Array = []
var render_frame: Array = []
var spatial_audio: AudioStreamPlayer3D
var particles: GPUParticles3D
var rebase_count: int = 0
var rebase_max_pixels: float = 0.0
var rebase_max_audio_m: float = 0.0
var device_info: Dictionary
var image_pair: Dictionary
var failed := false
var tiles: Array[MeshInstance3D] = []
var tile_swap_cpu_ms: Array = []
var tile_swap_epoch: int = 0
var next_tile_swap_s: float = 5.0
var tile_swap_events: Array = []
var maximum_deferred_old_nodes: int = 0
var terrain_material: Material
const Frame = preload("res://render/frame.gd")

func require(condition: bool, message: String) -> bool:
	if not condition:
		failed=true
		push_error("RENDER_PROOF_FAILED: "+message)
		get_tree().quit(1)
	return condition

func coherent() -> bool:
	for participant in [world,camera,spatial_audio,particles,sunlight]:
		if participant.get_meta("origin_version",-1)!=origin_version:
			return false
	return true

func eye_position(time: float) -> Array:
	return Frame.canonical(origin,original_frame,[2200*sin(time*.035),180,2200*cos(time*.035)])

func apply_frame(eye: Array, time: float) -> void:
	var basis: Basis = Frame.object_basis(original_frame,render_frame)
	world.transform=Transform3D(basis,Frame.local_position(origin,anchor,render_frame))
	camera.transform=Transform3D(basis*Basis.from_euler(Vector3(-.12,time*.035,0)),Frame.local_position(eye,anchor,render_frame))
	world.force_update_transform()
	camera.force_update_transform()
	for participant in [world,camera,spatial_audio,particles,sunlight]:
		participant.set_meta("origin_version",origin_version)

func rebase(eye: Array, time: float) -> void:
	var frozen: String = JSON.stringify([origin,original_frame,eye])
	var points: Array = []
	for offset in [[0.2,-0.1,-0.8],[0.8,-0.2,-1.5],[20.0,-350.0,-600.0],[-100.0,-500.0,-2000.0],[200.0,300.0,-4000.0]]:
		var rotated: Vector3 = Basis.from_euler(Vector3(-.12,time*.035,0))*Vector3(offset[0],offset[1],offset[2])
		points.append(Frame.canonical(eye,original_frame,[float(rotated.x),float(rotated.y),float(rotated.z)]))
	var projected: Array = []
	for point in points:
		projected.append(camera.unproject_position(Frame.local_position(point,anchor,render_frame)))
	var audio_before: Vector3 = camera.global_basis.inverse()*(spatial_audio.global_position-camera.global_position)
	anchor=eye.duplicate()
	render_frame=Frame.axes_at(anchor)
	origin_version+=1
	apply_frame(eye,time)
	for index in points.size():
		var error: float = projected[index].distance_to(camera.unproject_position(Frame.local_position(points[index],anchor,render_frame)))
		require(is_finite(error) and error<=.5,"Rebase exceeded frozen half-pixel projection budget")
		rebase_max_pixels=max(rebase_max_pixels,error)
	var audio_after: Vector3 = camera.global_basis.inverse()*(spatial_audio.global_position-camera.global_position)
	var audio_error: float = audio_after.distance_to(audio_before)
	require(audio_error<=.001,"Rebase changed relative audio emitter location")
	rebase_max_audio_m=max(rebase_max_audio_m,audio_error)
	require(coherent(),"Mixed render origin versions")
	require(frozen==JSON.stringify([origin,original_frame,eye]),"Render changed canonical positions")
	# Deliberately mixed-origin negative must be detected before presentation.
	particles.set_meta("origin_version",origin_version-1)
	require(not coherent(),"Mixed-origin negative was not detected")
	particles.set_meta("origin_version",origin_version)
	rebase_count+=1

func replace_far_tile() -> void:
	# Bounded render attachment fixture, not storage/GIS/contact streaming. The
	# same canonical geometry is replaced before presentation; no missing tile.
	var begin: int = Time.get_ticks_usec()
	var index: int = [0,7,56,63][tile_swap_epoch%4]
	var old: MeshInstance3D = tiles[index]
	var plane := PlaneMesh.new()
	plane.size=Vector2(1250,1250)
	plane.subdivide_width=32
	plane.subdivide_depth=32
	var replacement: MeshInstance3D = mesh_node(plane,old.position,world,terrain_material)
	replacement.set_meta("terrain_tile",true)
	old.queue_free()
	tiles[index]=replacement
	tile_swap_epoch+=1
	var submit_ms: float = (Time.get_ticks_usec()-begin)/1000.0
	tile_swap_cpu_ms.append(submit_ms)
	var active_nodes: int = 0
	var deferred_old_nodes: int = 0
	for child in world.get_children():
		if child.get_meta("terrain_tile",false):
			if child.is_queued_for_deletion():
				deferred_old_nodes+=1
			else:
				active_nodes+=1
	maximum_deferred_old_nodes=max(maximum_deferred_old_nodes,deferred_old_nodes)
	require(tiles.size()==64 and active_nodes==64 and deferred_old_nodes<=1,"Bounded terrain node count changed")
	tile_swap_events.append({"process_frame":Engine.get_process_frames(),"wall_s":elapsed,"scheduled_s":next_tile_swap_s,"epoch":tile_swap_epoch,"tile_index":index,"submit_ms":submit_ms,"active_nodes":active_nodes,"deferred_old_nodes":deferred_old_nodes})

func material(color: Color) -> StandardMaterial3D:
	var result := StandardMaterial3D.new()
	result.albedo_color=color
	result.roughness=0.85
	return result

func mesh_node(mesh: Mesh, at: Vector3, parent: Node3D, mat: Material) -> MeshInstance3D:
	var result := MeshInstance3D.new()
	result.mesh=mesh
	result.position=at
	result.material_override=mat
	parent.add_child(result)
	return result

func box(size: Vector3, at: Vector3, parent: Node3D, mat: Material) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size=size
	return mesh_node(mesh,at,parent,mat)

func instances(mesh: Mesh, count: int, parent: Node3D, mat: Material, cloud: bool=false) -> void:
	var node := MultiMeshInstance3D.new()
	var multi := MultiMesh.new()
	multi.transform_format=MultiMesh.TRANSFORM_3D
	multi.mesh=mesh
	multi.instance_count=count
	for index in count:
		var x: float = -4800+fmod(index*371.0,9600.0)
		var z: float = -4800+fmod(index*613.0,9600.0)
		var size: float = 0.8+fmod(index*.173,0.7)
		var scale := Vector3.ONE*size
		if cloud:
			scale=Vector3(180+size*90,50+size*20,120+size*60)
		multi.set_instance_transform(index,Transform3D(Basis.from_scale(scale),Vector3(x,900 if cloud else 7,z)))
	node.multimesh=multi
	node.material_override=mat
	parent.add_child(node)

func _ready() -> void:
	set_process(false)
	output=ProjectSettings.globalize_path("res://")
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("duration="):
			duration=float(argument.trim_prefix("duration="))
		if argument.begins_with("width="):
			render_size.x=int(argument.trim_prefix("width="))
		if argument.begins_with("height="):
			render_size.y=int(argument.trim_prefix("height="))
		if argument.begins_with("fov="):
			fov=float(argument.trim_prefix("fov="))
		if argument.begins_with("output="):
			output=argument.trim_prefix("output=")
		if argument.begins_with("fixture="):
			fixture=argument.trim_prefix("fixture=")
	if not require(DisplayServer.get_name()!="headless","GPU benchmark cannot be headless"):
		return
	if not require(RenderingServer.get_current_rendering_method()=="forward_plus" and RenderingServer.get_current_rendering_driver_name()=="vulkan","Unintended renderer fallback"):
		return
	if not require(RenderingServer.get_video_adapter_name()=="NVIDIA GeForce RTX 3090","Reference adapter mismatch"):
		return
	if not require(fixture in ["clear","dusk","overcast"] and is_finite(duration) and duration>0 and duration<=600,"Invalid bounded benchmark configuration"):
		return
	Engine.max_fps=120
	DisplayServer.window_set_size(Vector2i(1360,768))
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	if not require(DisplayServer.window_get_size()==Vector2i(1360,768) and DisplayServer.window_get_vsync_mode()==DisplayServer.VSYNC_DISABLED,"Requested presentation window/VSync settings unavailable"):
		return
	raw_trace=FileAccess.open(output.path_join("frames.csv"),FileAccess.WRITE)
	raw_trace.store_line("process_frame,wall_us,frame_ms,gpu_timestamp_frame,new_gpu_sample,gpu_render_ms,cpu_render_ms,video_bytes,origin_version")
	viewport=SubViewport.new()
	viewport.size=render_size
	viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	viewport.msaa_3d=Viewport.MSAA_2X
	viewport.use_taa=false
	viewport.scaling_3d_scale=1.0
	viewport.own_world_3d=true
	add_child(viewport)
	var screen := TextureRect.new()
	screen.texture=viewport.get_texture()
	screen.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
	screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(screen)
	var container := Node3D.new()
	viewport.add_child(container)
	world=Node3D.new()
	container.add_child(world)
	var environment := WorldEnvironment.new()
	var settings := Environment.new()
	settings.background_mode=Environment.BG_SKY
	var sky := Sky.new()
	sky.sky_material=ProceduralSkyMaterial.new()
	settings.sky=sky
	settings.ambient_light_source=Environment.AMBIENT_SOURCE_SKY
	settings.ambient_light_energy=0.8
	settings.fog_enabled=true
	settings.fog_density=0.00006
	environment.environment=settings
	container.add_child(environment)
	sunlight=DirectionalLight3D.new()
	sunlight.rotation_degrees=Vector3(-35,-30,0)
	sunlight.shadow_enabled=true
	sunlight.directional_shadow_mode=DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sunlight.directional_shadow_max_distance=6000
	if fixture=="dusk":
		sunlight.rotation_degrees.x=-8
		sunlight.light_color=Color(1,.55,.30)
		sunlight.light_energy=.55
		settings.ambient_light_energy=.35
	elif fixture=="overcast":
		sunlight.light_energy=.6
	world.add_child(sunlight)
	var grass := material(Color(0.14,0.23,0.10))
	terrain_material=grass
	for x in 8:
		for z in 8:
			var plane := PlaneMesh.new()
			plane.size=Vector2(1250,1250)
			plane.subdivide_width=32
			plane.subdivide_depth=32
			var tile := mesh_node(plane,Vector3(-4375+x*1250,0,-4375+z*1250),world,grass)
			tile.set_meta("terrain_tile",true)
			tiles.append(tile)
	box(Vector3(30,0.15,1200),Vector3(0,.12,-200),world,material(Color(.06,.07,.075)))
	var white := material(Color(.86,.87,.83))
	for index in 24:
		box(Vector3(1.2,.04,20),Vector3(0,.22,-770+index*50),world,white)
	for index in 60:
		box(Vector3(25+index%5*8,10+index%4*5,35),Vector3(100+index%10*80,5,-1000+index/10*140),world,material(Color(.25,.27,.30)))
	var tree := CylinderMesh.new()
	tree.top_radius=0
	tree.bottom_radius=4
	tree.height=14
	tree.radial_segments=12
	instances(tree,2400,world,material(Color(.045,.12,.055)))
	var cloud_mesh := SphereMesh.new()
	cloud_mesh.radial_segments=24
	cloud_mesh.rings=12
	instances(cloud_mesh,0 if fixture=="clear" else 96,world,material(Color(.77,.8,.83)),true)
	camera=Camera3D.new()
	camera.position=Vector3(0,180,400)
	camera.rotation.x=-.16
	camera.fov=fov
	camera.keep_aspect=Camera3D.KEEP_HEIGHT
	camera.near=.05
	camera.far=15000
	container.add_child(camera)
	camera.current=true
	var panel_view := SubViewport.new()
	panel_view.size=Vector2i(1024,448)
	panel_view.render_target_update_mode=SubViewport.UPDATE_ONCE
	add_child(panel_view)
	var panel := Node2D.new()
	panel.set_script(load("res://render/panel.gd"))
	panel_view.add_child(panel)
	box(Vector3(1.3,.56,.04),Vector3(0,-.30,-1),camera,material(Color(.035,.035,.04)))
	var face := PlaneMesh.new()
	face.size=Vector2(1.25,.547)
	var panel_mat := StandardMaterial3D.new()
	panel_mat.albedo_texture=panel_view.get_texture()
	panel_mat.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
	var face_node := mesh_node(face,Vector3(0,-.30,-.976),camera,panel_mat)
	face_node.rotation.x=PI/2
	# Actual reviewed Blender -> GLB resource in the target Forward+ renderer.
	var pipeline: Node3D = (load("res://pipeline/pipeline_fixture.glb") as PackedScene).instantiate()
	pipeline.position=Vector3(-.6,.5,-2)
	pipeline.rotation.y=-.6
	camera.add_child(pipeline)
	var pivot_animation: AnimationPlayer = pipeline.find_child("AnimationPlayer",true,false)
	pivot_animation.play("PivotSweep")
	pivot_animation.seek(.5,true)
	pivot_animation.pause()
	spatial_audio=AudioStreamPlayer3D.new()
	spatial_audio.position=Vector3(200,3,-300)
	var silence := AudioStreamWAV.new()
	silence.format=AudioStreamWAV.FORMAT_16_BITS
	silence.mix_rate=44100
	var silence_samples := PackedByteArray()
	silence_samples.resize(2048)
	silence.data=silence_samples
	silence.loop_mode=AudioStreamWAV.LOOP_FORWARD
	silence.loop_end=1024
	spatial_audio.stream=silence
	world.add_child(spatial_audio)
	spatial_audio.play()
	spatial_audio.stream_paused=true # Silent spatial transform participant; no audible continuity claim.
	particles=GPUParticles3D.new()
	particles.position=Vector3(80,8,-100)
	particles.amount=64
	particles.local_coords=true
	particles.lifetime=4
	var particle_material := ParticleProcessMaterial.new()
	particle_material.initial_velocity_min=2
	particle_material.initial_velocity_max=3
	particle_material.gravity=Vector3(0,1,0)
	particles.process_material=particle_material
	var particle_mesh := SphereMesh.new()
	particle_mesh.radius=.4
	particle_mesh.height=.8
	particles.draw_pass_1=particle_mesh
	world.add_child(particles)
	origin=Frame.geographic(.8,-2,1000)
	original_frame=Frame.axes(.8,-2)
	anchor=origin.duplicate()
	render_frame=original_frame.duplicate(true)
	apply_frame(eye_position(0),0)
	RenderingServer.viewport_set_measure_render_time(viewport.get_viewport_rid(),true)
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(),true)
	var actual_window: Vector2i = DisplayServer.window_get_size()
	device_info={"adapter":RenderingServer.get_video_adapter_name(),"vendor":RenderingServer.get_video_adapter_vendor(),"driver":RenderingServer.get_current_rendering_driver_name(),"method":RenderingServer.get_current_rendering_method(),"engine":Engine.get_version_info(),"resolution":[viewport.size.x,viewport.size.y],"presentation_window":[actual_window.x,actual_window.y],"vsync_mode":DisplayServer.window_get_vsync_mode(),"msaa_mode":viewport.msaa_3d,"taa":viewport.use_taa,"render_scale":viewport.scaling_3d_scale,"fov_deg":camera.fov,"fov_axis":"vertical" if camera.keep_aspect==Camera3D.KEEP_HEIGHT else "horizontal","near_m":camera.near,"far_m":camera.far,"shadow_cascades":4,"shadow_atlas_size":ProjectSettings.get_setting("rendering/lights_and_shadows/directional_shadow/size"),"max_fps":Engine.max_fps,"fixture":fixture,"scope":"offscreen Forward+ cockpit/terrain/shadow/cloud geometry proxy; no volumetric weather or simulation"}
	print("RENDER_DEVICE "+JSON.stringify(device_info))
	call_deferred("verify_rendered_rebase")

func verify_rendered_rebase() -> void:
	# Identical canonical camera/scene; temporal antialiasing is disabled. Freeze
	# the local emitter for this paired comparison; benchmark resumes it below.
	particles.speed_scale=0
	var eye: Array = eye_position(0)
	apply_frame(eye,0)
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var before: Image = viewport.get_texture().get_image()
	before.convert(Image.FORMAT_RGBA8)
	before.save_png(output.path_join("origin-before.png"))
	rebase(eye,0)
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var after: Image = viewport.get_texture().get_image()
	after.convert(Image.FORMAT_RGBA8)
	after.save_png(output.path_join("origin-after.png"))
	var first: PackedByteArray = before.get_data()
	var second: PackedByteArray = after.get_data()
	if not require(first.size()==second.size() and first.size()==render_size.x*render_size.y*4,"Unexpected paired viewport image size"):
		return
	var changed: int = 0
	var maximum: int = 0
	for index in range(0,first.size(),4):
		var delta: int = max(absi(first[index]-second[index]),max(absi(first[index+1]-second[index+1]),absi(first[index+2]-second[index+2])))
		maximum=max(maximum,delta)
		if delta>8:
			changed+=1
	var fraction: float = float(changed)/(render_size.x*render_size.y)
	require(fraction<=.01,"Paired rendered origin shift exceeded preselected image budget")
	image_pair={"changed_pixels":changed,"pixels":render_size.x*render_size.y,"changed_fraction":fraction,"channel_delta_threshold":8,"maximum_channel_delta":maximum,"changed_fraction_budget":.01,"scope":"two actual GPU images at identical canonical state, local emitter frozen, TAA disabled"}
	print("RENDERED_ORIGIN_PAIR "+JSON.stringify(image_pair))
	particles.speed_scale=1
	last_us=Time.get_ticks_usec()
	start_us=last_us
	set_process(true)

func percentile(values: Array, fraction: float) -> float:
	if values.is_empty():
		return -1
	var sorted := values.duplicate()
	sorted.sort()
	return sorted[ceili(sorted.size()*fraction)-1]

func finish() -> void:
	if failed:
		return
	var sum: float = 0
	for value in frames:
		sum+=value
	var report := {"duration_s":duration,"warmup_s":warmup,"frames":frames.size(),"average_fps":1000*frames.size()/sum,"frame_ms":{"p95":percentile(frames,.95),"p99":percentile(frames,.99)},"gpu_ms":{"p95":percentile(gpu_ms,.95),"p99":percentile(gpu_ms,.99),"positive_unique_frame_samples":gpu_ms.size(),"duplicate_observations":duplicate_gpu_observations},"render_cpu_ms":{"p95":percentile(render_cpu_ms,.95)},"one_second_process_max_ms":{"p95":percentile(process_max_ms,.95),"samples":process_max_ms.size(),"scope":"Godot one-second process maxima; not per-frame main-thread CPU time"},"peak_godot_video_bytes":peak_video_bytes,"scope":"isolated visual-load experiment; not full-game performance acceptance"}
	report["device"]=device_info
	report["rendered_origin_pair"]=image_pair
	report["capture_start_us"]=start_us
	report["capture_elapsed_s"]=elapsed
	report["render_tile_attachment"]={"interval_s":5,"events":tile_swap_events,"next_scheduled_s":next_tile_swap_s,"replacements":tile_swap_epoch,"steady_tile_count":tiles.size(),"maximum_deferred_old_nodes":maximum_deferred_old_nodes,"p95_submit_cpu_ms":percentile(tile_swap_cpu_ms,.95),"maximum_submit_cpu_ms":tile_swap_cpu_ms.max() if not tile_swap_cpu_ms.is_empty() else -1,"scope":"new 32x32-subdivision plane mesh every five seconds, four far corners; missed periods skipped; CPU submission only; active/deferred scene-node bounds do not establish GPU allocator retirement; GPU allocation/upload effects included in raw callback/render samples; no disk IO, real coverage or contact streaming"}
	report["rebase"]={"transactions":rebase_count,"origin_version":origin_version,"max_projected_delta_px":rebase_max_pixels,"max_relative_audio_delta_m":rebase_max_audio_m,"canonical_unchanged":true,"mixed_version_negative_detected":true,"particle_scope":"local-coordinate GPU emitter transforms; no world-space particle history claim","audio_scope":"silent paused spatial emitter; geometry only, no audible continuity claim"}
	raw_trace.flush()
	raw_trace.close()
	var file := FileAccess.open(output.path_join("report.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"\t")+"\n")
	print("RENDER_PROBE "+JSON.stringify(report))
	spatial_audio.stream_paused=false
	spatial_audio.stop()
	spatial_audio.stream=null
	get_tree().quit(0)

func _process(delta: float) -> void:
	if not require(DisplayServer.window_get_mode()!=DisplayServer.WINDOW_MODE_MINIMIZED and DisplayServer.window_get_size()==Vector2i(1360,768) and DisplayServer.window_get_vsync_mode()==DisplayServer.VSYNC_DISABLED,"Presentation window changed/minimized during capture"):
		set_process(false)
		return
	var now: int = Time.get_ticks_usec()
	elapsed=(now-start_us)/1000000.0
	var frame_ms: float = (now-last_us)/1000.0
	last_us=now
	var eye: Array = eye_position(elapsed)
	if elapsed>=next_tile_swap_s:
		replace_far_tile()
		# Skip missed periods instead of submitting a burst after a long callback.
		next_tile_swap_s=(floor(elapsed/5.0)+1)*5.0
	apply_frame(eye,elapsed)
	if Frame.local_position(eye,anchor,render_frame).length()>2000:
		rebase(eye,elapsed)
	require(coherent(),"A frame used mixed origin versions")
	if elapsed>5 and not capture_done:
		capture_done=true
		await RenderingServer.frame_post_draw
		viewport.get_texture().get_image().save_png(output.path_join("view.png"))
	if elapsed>warmup:
		frames.append(frame_ms)
		var gpu: float = RenderingServer.viewport_get_measured_render_time_gpu(viewport.get_viewport_rid())+RenderingServer.viewport_get_measured_render_time_gpu(get_viewport().get_viewport_rid())
		var device: RenderingDevice = RenderingServer.get_rendering_device()
		var gpu_frame: int = device.get_captured_timestamps_frame()
		var unique: bool = gpu_frame>last_gpu_frame
		if unique and gpu>0:
			gpu_ms.append(gpu)
			last_gpu_frame=gpu_frame
		else:
			duplicate_gpu_observations+=1
		var cpu: float = RenderingServer.viewport_get_measured_render_time_cpu(viewport.get_viewport_rid())+RenderingServer.viewport_get_measured_render_time_cpu(get_viewport().get_viewport_rid())+RenderingServer.get_frame_setup_time_cpu()
		if unique:
			render_cpu_ms.append(cpu)
		raw_trace.store_line("%d,%d,%.6f,%d,%d,%.6f,%.6f,%d,%d" % [Engine.get_process_frames(),now,frame_ms,gpu_frame,int(unique),gpu,cpu,int(Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED)),origin_version])
		peak_video_bytes=max(peak_video_bytes,int(Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED)))
		if int(elapsed)!=sample_second:
			sample_second=int(elapsed)
			process_max_ms.append(Performance.get_monitor(Performance.TIME_PROCESS)*1000)
	if elapsed>warmup+duration:
		set_process(false)
		finish()
