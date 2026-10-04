extends RefCounted
# Private presentation regression checks, never an aircraft-state authority.

func check_mesh(host: Node) -> void:
	var shell: MeshInstance3D=host.airplane.get_node("ContinuousCabinShell")
	var mesh: ArrayMesh=shell.mesh
	host.check(mesh.get_surface_count()==2,"aircraft_body_and_glass_share_one_shell")
	var seen: Dictionary={}
	var duplicate: bool=false
	var valid_normals: bool=true
	var counts: Array[int]=[]
	for surface in range(mesh.get_surface_count()):
		var arrays: Array=mesh.surface_get_arrays(surface)
		var vertices: PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array=arrays[Mesh.ARRAY_NORMAL]
		counts.append(vertices.size()/3)
		for normal in normals:
			valid_normals=valid_normals and normal.is_finite() and absf(normal.length()-1)<0.0001
		for index in range(0,vertices.size(),3):
			var corners: Array[String]=[]
			for vertex in [vertices[index],vertices[index+1],vertices[index+2]]:
				corners.append("%.6f,%.6f,%.6f" % [vertex.x,vertex.y,vertex.z])
			corners.sort()
			var key: String=";".join(corners)
			if seen.has(key):
				duplicate=true
			seen[key]=true
	host.check(not duplicate,"aircraft_glazing_has_no_duplicate_shell_faces")
	host.check(valid_normals and counts[0]>0 and counts[1]>0,"aircraft_material_partitions_have_finite_unit_normals")
	host.evidence["aircraft_shell_triangle_counts"]=counts

func capture_views(host: Node) -> void:
	var was_paused: bool=host.paused
	host.check(host.pause_session(true),"aircraft_observer_native_paused")
	var before: Dictionary=host.bridge.call("read_state").duplicate(true)
	var controls: Dictionary=host.controls.duplicate(true)
	var sequence: int=host.command_sequence
	var submitted: int=host.submitted_count
	var saved_fov: float=host.camera.fov
	var saved_size: Vector2i=host.get_window().size
	host.get_window().size=Vector2i(1280,720)
	host.show_state()
	host.airplane.show()
	host.cockpit.root.hide()
	host.panel.call("set_panel_visible",false)
	host.camera.fov=42
	var target: Vector3=host.airplane.global_transform*Vector3(0,0.25,-0.4)
	var views: Array[Array]=[
		["view-aircraft-nose",Vector3(5,2.3,-7)],
		["view-aircraft-right",Vector3(6,0.45,-0.4)],
		["view-aircraft-left",Vector3(-6,0.45,-0.4)],
		["view-aircraft-aft",Vector3(4,2.4,7)]
	]
	for view in views:
		host.camera.position=host.airplane.global_transform*view[1]
		host.camera.look_at(target,Vector3.UP)
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
		var image: Image=host.get_viewport().get_texture().get_image()
		host.check(image.save_png(host.output_directory().path_join(view[0]+".png"))==OK,view[0]+"_PNG_saved")
	host.check(host.bridge.call("read_state")==before and host.controls==controls and host.command_sequence==sequence and host.submitted_count==submitted,"aircraft_observer_preserves_native_state_and_commands")
	host.evidence["aircraft_views_scope"]="Four paused camera-only GPU views of the original continuous shell; no native teleport, force change or flight-quality claim."
	host.camera.fov=saved_fov
	host.get_window().size=saved_size
	host.check(host.pause_session(was_paused),"aircraft_observer_restores_pause")
	host.show_state()
