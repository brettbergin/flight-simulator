extends RefCounted
# Private presentation regression checks, never an aircraft-state authority.

func check_mesh(host: Node) -> void:
	var shell: MeshInstance3D=host.airplane.get_node("ContinuousCabinShell")
	var mesh: ArrayMesh=shell.mesh
	host.check(mesh.get_surface_count()==2,"aircraft_body_and_glass_share_one_shell")
	var seen: Dictionary={}
	var duplicate: bool=false
	var valid_normals: bool=true
	var clockwise: bool=true
	var counts: Array[int]=[]
	for surface in range(mesh.get_surface_count()):
		var arrays: Array=mesh.surface_get_arrays(surface)
		var vertices: PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array=arrays[Mesh.ARRAY_NORMAL]
		counts.append(vertices.size()/3)
		for normal in normals:
			valid_normals=valid_normals and normal.is_finite() and absf(normal.length()-1)<0.0001
		for index in range(0,vertices.size(),3):
			var face: Vector3=(vertices[index+1]-vertices[index]).cross(vertices[index+2]-vertices[index])
			var outward: Vector3=normals[index]+normals[index+1]+normals[index+2]
			clockwise=clockwise and face.dot(outward)<-0.0000001
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
	host.check(clockwise,"aircraft_shell_clockwise_front_faces_match_outward_normals")
	host.evidence["aircraft_shell_triangle_counts"]=counts
	check_wing(host,"OriginalMainWing",0.89,1.55,-0.30,9.0)
	check_wing(host,"OriginalTailWing",0.28,0.88,2.92,3.20)
	check_finish(host)

func check_wing(host: Node, name: String, height: float, chord: float, aft: float, span: float) -> void:
	var wing: MeshInstance3D=host.airplane.get_node(name)
	var arrays: Array=wing.mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array=arrays[Mesh.ARRAY_NORMAL]
	var outward_clockwise: bool=true
	for index in range(0,vertices.size(),3):
		var midpoint: Vector3=(vertices[index]+vertices[index+1]+vertices[index+2])/3.0
		var taper: float=1.0-0.20*absf(midpoint.x)/(span*0.5)
		var inside:=Vector3(midpoint.x,height+0.025*absf(midpoint.x)+0.02*chord*taper,aft-0.02*chord*taper+0.10*absf(midpoint.x)/(span*0.5))
		var face: Vector3=(vertices[index+1]-vertices[index]).cross(vertices[index+2]-vertices[index])
		var normal: Vector3=normals[index]+normals[index+1]+normals[index+2]
		outward_clockwise=outward_clockwise and face.dot(midpoint-inside)<0 and normal.dot(midpoint-inside)>0
	host.check(outward_clockwise,name+"_clockwise_faces_and_outward_normals")

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

# Frozen original geometry recipe, copied before209 implementation. This is an
# explicit before-image position/partition oracle, not the new shading helper.
# Stations/subdivisions/winding are fixed accepted visual design choices,
# not Cessna dimensions or native aerodynamic/gear authority.
const FINISH_STATIONS: Array[Vector4]=[Vector4(-3.02,0.00,0.25,0.29),Vector4(-2.65,0.02,0.45,0.44),Vector4(-1.72,0.04,0.59,0.56),Vector4(-0.80,0.10,0.68,0.67),Vector4(0.65,0.08,0.63,0.62),Vector4(1.30,0.05,0.44,0.44),Vector4(2.42,0.12,0.23,0.24),Vector4(3.55,0.18,0.07,0.12)]
# Pre-observation oct16 pair allowance; see normal-packing-budget.md.
const FINISH_NORMAL_DISTANCE: float=0.0003

func _baseline_glass(z: float, angle: float) -> bool:
	var windshield: bool=z>-1.60 and z<-0.85 and angle>0.74 and angle<PI-0.74 and absf(angle-PI*0.5)>0.065
	var side_band: bool=(angle>0.20 and angle<1.02) or (angle>PI-1.02 and angle<PI-0.20)
	var side_window: bool=(z>-0.76 and z<0.15) or (z>0.26 and z<0.82)
	return windshield or (side_band and side_window)

func _baseline_geometry() -> Dictionary:
	var result: Array[PackedVector3Array]=[PackedVector3Array(),PackedVector3Array()]
	var keys: Array[PackedStringArray]=[PackedStringArray(),PackedStringArray()]
	var cells: Array[Vector3i]=[]
	for row in range(FINISH_STATIONS.size()-1):
		var a: Vector4=FINISH_STATIONS[row]
		var b: Vector4=FINISH_STATIONS[row+1]
		for span in range(16):
			var start: Vector4=a.lerp(b,span/16.0)
			var end: Vector4=a.lerp(b,(span+1)/16.0)
			for segment in range(64):
				var angle: float=TAU*(segment+0.5)/64.0
				var z: float=(start.x+end.x)*0.5
				var partition: int=1 if _baseline_glass(z,angle) else 0
				if partition==0: cells.append(Vector3i(row,span,segment))
				var corners: Array[Vector3]=[]
				for station in [start,end]:
					for theta in [TAU*segment/64.0,TAU*(segment+1)/64.0]:
						corners.append(Vector3(cos(theta)*station.z,station.y+sin(theta)*station.w,station.x))
				for index in [0,2,1,1,2,3]:
					result[partition].append(corners[index])
					var ring: int=row*16+span+(1 if index>=2 else 0)
					var angular: int=(segment+index%2)%64
					keys[partition].append("%d/%d" % [ring,angular])
	return {"vertices":result,"keys":keys,"cells":cells}

func _normal_groups(vertices: Array[PackedVector3Array], normals: Array[PackedVector3Array], keys: Array[PackedStringArray]) -> Dictionary:
	var groups: Dictionary={}
	for surface in range(2):
		for i in range(vertices[surface].size()):
			var point: Vector3=vertices[surface][i]
			# Frozen topological ring/angular keys join both row endpoints and
			# angular64/0 despite harmless binary32 lerp/sin representation drift.
			# Exact geometry/partition is independently asserted before grouping.
			var key: String=keys[surface][i]
			if not groups.has(key): groups[key]=[]
			groups[key].append({"point":point,"normal":normals[surface][i],"surface":surface})
	return groups

func _continuous(groups: Dictionary) -> bool:
	for entries in groups.values():
		var first: Vector3=entries[0].normal
		for entry in entries:
			if not entry.normal.is_finite() or first.distance_to(entry.normal)>FINISH_NORMAL_DISTANCE: return false
	return true

func _packed_palette() -> Array[Color]:
	# Pinned Godot4.7.2 ARRAY_COLOR stores uint8(clamp(channel*255)), then byte/255.
	# Quantize authored Color float32 channels explicitly; no fitted color epsilon.
	var out: Array[Color]=[]
	for color in [Color(0.91,0.94,0.93),Color(0.06,0.53,0.55),Color(0.025,0.10,0.17)]:
		out.append(Color(float(int(color.r*255.0))/255.0,float(int(color.g*255.0))/255.0,float(int(color.b*255.0))/255.0,1.0))
	return out

func _rod_matches(node: Node, a: Vector3, b: Vector3, radius: float) -> bool:
	if not node is MeshInstance3D or not node.mesh is CylinderMesh: return false
	var mesh: CylinderMesh=node.mesh
	var axis: Vector3=node.quaternion*Vector3.UP
	return node.position.distance_to((a+b)*0.5)<0.000001 and absf(mesh.height-a.distance_to(b))<0.000001 and absf(mesh.top_radius-radius)<0.0000001 and absf(mesh.bottom_radius-radius)<0.0000001 and axis.distance_to((b-a).normalized())<0.000001

func _find_rod(parent: Node, a: Vector3, b: Vector3, radius: float) -> int:
	var count: int=0
	for node in parent.get_children():
		if _rod_matches(node,a,b,radius): count+=1
	return count

func _sphere_matches(node: Node, at: Vector3, size: Vector3) -> bool:
	return node is MeshInstance3D and node.mesh is SphereMesh and node.position==at and node.scale==size and node.mesh.radius==0.5 and node.mesh.height==1.0 and node.mesh.radial_segments==24 and node.mesh.rings==12

func _box_matches(node: Node, at: Vector3, size: Vector3) -> bool:
	return node is MeshInstance3D and node.mesh is BoxMesh and node.position==at and node.mesh.size==size

func _baseline_wing(span: float, chord: float, height: float, aft: float) -> PackedVector3Array:
	var result:=PackedVector3Array()
	var sections: Array[Vector2]=[Vector2(-0.52,0),Vector2(-0.40,0.070),Vector2(-0.14,0.092),Vector2(0.23,0.045),Vector2(0.48,0),Vector2(0.23,-0.017),Vector2(-0.14,-0.024),Vector2(-0.40,-0.015)]
	for band in range(18):
		for index in range(sections.size()):
			var corners: Array[Vector3]=[]
			for side in [band,band+1]:
				var x: float=-span*0.5+span*side/18.0
				var taper: float=1.0-0.20*absf(x)/(span*0.5)
				for edge in [index,(index+1)%sections.size()]:
					var section: Vector2=sections[edge]
					corners.append(Vector3(x,height+0.025*absf(x)+section.y*chord*taper,aft+section.x*chord*taper+0.10*absf(x)/(span*0.5)))
			for vertex in [0,2,1,1,2,3]: result.append(corners[vertex])
	return result

func _has_visual_physics(node: Node) -> bool:
	if node is PhysicsBody3D or node is Area3D or node is CollisionShape3D or node is CollisionPolygon3D: return true
	for child in node.get_children():
		if _has_visual_physics(child): return true
	return false

func _radially_outward(point: Vector3, normal: Vector3) -> bool:
	for row in range(FINISH_STATIONS.size()-1):
		var a: Vector4=FINISH_STATIONS[row]
		var b: Vector4=FINISH_STATIONS[row+1]
		if point.z>=a.x-0.000001 and point.z<=b.x+0.000001:
			var ratio: float=clampf((point.z-a.x)/(b.x-a.x),0.0,1.0)
			var center: float=lerpf(a.y,b.y,ratio)
			return normal.dot(Vector3(point.x,point.y-center,0))>0
	return false

func check_finish(host: Node) -> void:
	var shell: MeshInstance3D=host.airplane.get_node("ContinuousCabinShell")
	var baseline_geometry: Dictionary=_baseline_geometry()
	var baseline: Array[PackedVector3Array]=baseline_geometry.vertices
	var vertices: Array[PackedVector3Array]=[]
	var normals: Array[PackedVector3Array]=[]
	var outward: bool=true
	for surface in range(2):
		var arrays: Array=shell.mesh.surface_get_arrays(surface)
		vertices.append(arrays[Mesh.ARRAY_VERTEX])
		normals.append(arrays[Mesh.ARRAY_NORMAL])
		host.check(vertices[surface]==baseline[surface],"aircraft_finish_exact_baseline_positions_partition_surface"+str(surface))
		for i in range(vertices[surface].size()): outward=outward and _radially_outward(vertices[surface][i],normals[surface][i])
	host.check(vertices[0].size()+vertices[1].size()==7*16*64*6,"aircraft_finish_original_tessellation_and_triangle_order")
	host.check(outward,"aircraft_finish_all_shell_normals_point_radially_outward")
	var groups: Dictionary=_normal_groups(vertices,normals,baseline_geometry.keys)
	var stations: int=0
	var angular: int=0
	var materials: int=0
	var perturb_key: String=""
	for key in groups:
		var entries: Array=groups[key]
		var parts: PackedStringArray=key.split("/")
		var ring: int=int(parts[0])
		var is_station: bool=ring>0 and ring<112 and ring%16==0
		if is_station and entries.size()>1:
			stations+=1
			if perturb_key.is_empty(): perturb_key=key
		if parts[1]=="0" and entries.size()>1: angular+=1
		var surfaces: Dictionary={}
		for entry in entries: surfaces[entry.surface]=true
		if surfaces.size()==2: materials+=1
	host.check(_continuous(groups),"aircraft_finish_shared_row_angular_material_normals_continuous")
	host.check(stations>=6*64 and angular==113 and materials>0,"aircraft_finish_continuity_observes_station_wrap_and_glass_boundaries")
	var mutant: Dictionary=groups.duplicate(true)
	if not perturb_key.is_empty():
		var normal: Vector3=mutant[perturb_key][0].normal
		var axis: Vector3=Vector3.UP if absf(normal.y)<0.9 else Vector3.RIGHT
		mutant[perturb_key][0].normal=(normal+normal.cross(axis).normalized()*0.125).normalized()
	host.check(not _continuous(mutant),"aircraft_finish_rejects_one_unit_boundary_normal_perturbation")
	host.check(_continuous(groups),"aircraft_finish_negative_fixture_did_not_mutate_actual_normals")
	var palette: Array[Color]=_packed_palette()
	var body_arrays: Array=shell.mesh.surface_get_arrays(0)
	var colors: PackedColorArray=body_arrays[Mesh.ARRAY_COLOR]
	var valid_colors: bool=colors.size()==vertices[0].size()
	var used: Dictionary={}
	for color in colors:
		valid_colors=valid_colors and is_finite(color.r) and is_finite(color.g) and is_finite(color.b) and is_finite(color.a) and color in palette
		used[color]=true
	host.check(valid_colors and used.size()==3,"aircraft_finish_body_uses_only_finite_original_packed_palette")
	var mirrored: Dictionary={}
	var uniform_mirrored: bool=valid_colors
	var cells: Array[Vector3i]=baseline_geometry.cells
	uniform_mirrored=uniform_mirrored and cells.size()*6==colors.size()
	if valid_colors:
		for i in range(0,vertices[0].size(),6):
			for j in range(6): uniform_mirrored=uniform_mirrored and colors[i+j]==colors[i]
			mirrored[cells[i/6]]=colors[i]
		for cell in cells:
			var counterpart:=Vector3i(cell.x,cell.y,(31-cell.z+64)%64)
			uniform_mirrored=uniform_mirrored and mirrored.has(counterpart) and mirrored[cell]==mirrored.get(counterpart)
	host.check(uniform_mirrored,"aircraft_finish_each_quad_uniform_and_mirrored_flush_paint")
	var glass_colors: Variant=shell.mesh.surface_get_arrays(1)[Mesh.ARRAY_COLOR]
	host.check(glass_colors==null or (glass_colors is PackedColorArray and glass_colors.is_empty()),"aircraft_finish_glass_has_no_vertex_paint")
	var body: StandardMaterial3D=shell.mesh.surface_get_material(0)
	var glass: StandardMaterial3D=shell.mesh.surface_get_material(1)
	var main: MeshInstance3D=host.airplane.get_node("OriginalMainWing")
	var tail: MeshInstance3D=host.airplane.get_node("OriginalTailWing")
	var ivory: StandardMaterial3D=main.material_override
	host.check(shell.transform==Transform3D.IDENTITY and main.transform==Transform3D.IDENTITY and tail.transform==Transform3D.IDENTITY,"aircraft_finish_original_local_mesh_transforms_preserved")
	host.check(host.airplane.name=="OriginalHighWingVisual" and not _has_visual_physics(host.airplane),"aircraft_finish_visual_root_identity_has_no_physics_colliders")
	host.check(body!=ivory and body!=glass and body.albedo_color==Color.WHITE and body.vertex_color_use_as_albedo and body.vertex_color_is_srgb,"aircraft_finish_body_material_isolated_white_vertex_color_base")
	host.check(tail.material_override==ivory and ivory.albedo_color==Color(0.91,0.94,0.93) and not ivory.vertex_color_use_as_albedo and absf(ivory.roughness-0.36)<0.0000001 and absf(ivory.metallic-0.12)<0.0000001,"aircraft_finish_shared_wing_ivory_unchanged")
	host.check(glass.albedo_color==Color(0.045,0.16,0.23) and not glass.vertex_color_use_as_albedo and glass.cull_mode==BaseMaterial3D.CULL_DISABLED and absf(glass.roughness-0.16)<0.0000001 and absf(glass.metallic-0.48)<0.0000001,"aircraft_finish_glass_material_unchanged")
	host.check(main.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]==_baseline_wing(9.0,1.55,0.89,-0.30),"aircraft_finish_main_wing_exact_baseline_positions")
	host.check(tail.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]==_baseline_wing(3.20,0.88,0.28,2.92),"aircraft_finish_tail_wing_exact_baseline_positions")
	var structural: bool=true
	var decorative: int=0
	for side in [-1.0,1.0]:
		structural=structural and _find_rod(host.airplane,Vector3(side*0.51,-0.28,0.33),Vector3(side*2.65,0.92,0.04),0.032)==1
		structural=structural and _find_rod(host.airplane,Vector3(side*0.91,0.902,0.43),Vector3(side*4.20,1.002,0.39),0.007)==1
		decorative+=_find_rod(host.airplane,Vector3(side*0.575,-0.035,-1.65),Vector3(side*0.57,-0.035,0.80),0.045)
		decorative+=_find_rod(host.airplane,Vector3(side*0.46,0.01,1.18),Vector3(side*0.13,0.12,3.08),0.038)
	structural=structural and _find_rod(host.airplane,Vector3(0,1.45,3.18),Vector3(0,1.36,3.50),0.037)==1
	structural=structural and _find_rod(host.airplane,Vector3(0,0.84,0.37),Vector3(0,1.25,0.65),0.013)==1
	structural=structural and _find_rod(host.airplane,Vector3(-3.14,0.94,-0.70),Vector3(-3.14,0.94,-1.05),0.012)==1
	var cylinder_count: int=0
	for child in host.airplane.get_children():
		if child is MeshInstance3D and child.mesh is CylinderMesh: cylinder_count+=1
	host.check(decorative==0 and cylinder_count==7,"aircraft_finish_only_four_decorative_rods_removed")
	host.check(structural,"aircraft_finish_structural_struts_seams_antenna_pitot_preserved")
	var gear_keys: Array=host.gears.keys();gear_keys.sort()
	host.check(gear_keys==["gear.left","gear.nose","gear.right"],"aircraft_finish_native_gear_return_handles_preserved")
	for id in gear_keys:
		var gear: Node3D=host.gears[id]
		var lean: float=0.70 if id=="gear.left" else -0.70 if id=="gear.right" else 0.0
		var preserved: bool=gear.get_parent()==host.airplane and gear.name==id.replace(".","_")+"NativeContactOrigin" and gear.get_child_count()==4
		preserved=preserved and _find_rod(gear,Vector3(-0.10,0.25,0),Vector3(0.10,0.25,0),0.115)==1
		preserved=preserved and _find_rod(gear,Vector3(0,0.30,0),Vector3(lean,0.81,0.04),0.034)==1
		preserved=preserved and _find_rod(gear,Vector3(lean,0.57,0.04),Vector3(lean,0.85,0.04),0.052)==1
		var wheel: MeshInstance3D=gear.get_child(0)
		preserved=preserved and wheel.mesh is CylinderMesh and wheel.position==Vector3(0,0.25,0) and wheel.mesh.top_radius==0.25 and wheel.mesh.bottom_radius==0.25 and absf(wheel.mesh.height-0.17)<0.0000001 and wheel.mesh.radial_segments==32 and absf(wheel.rotation_degrees.z-90)<0.00001
		host.check(preserved,"aircraft_finish_native_"+id+"_handle_and_local_visual_geometry_preserved")
	var rotor: Node3D=host.propeller
	var rotor_ok: bool=rotor!=null and rotor.get_parent()==host.airplane and rotor.position==Vector3(0,0,-3.18) and rotor.get_child_count()==5
	if rotor_ok:
		for i in range(2):
			var side: float=-1.0 if i==0 else 1.0
			rotor_ok=rotor_ok and _sphere_matches(rotor.get_child(i*2),Vector3(0,side*0.53,0),Vector3(0.14,0.98,0.055)) and absf(rotor.get_child(i*2).rotation_degrees.z+12)<0.00001
			rotor_ok=rotor_ok and _box_matches(rotor.get_child(i*2+1),Vector3(0,side*0.98,0),Vector3(0.15,0.14,0.055))
		rotor_ok=rotor_ok and _sphere_matches(rotor.get_child(4),Vector3(0,0,-0.055),Vector3(0.26,0.26,0.32))
	host.check(rotor_ok,"aircraft_finish_native_propeller_pivot_blades_spinner_preserved")
	host.evidence["aircraft_finish_scope"]="Original visual-only geometry/partition, station/wrap/material normals, source-quantized palette and preserved native-owned handles/local gear geometry (not contact-to-origin mapping). Paired GPU/native invariance and existing native-driven propeller checks remain separate."
	host.evidence["aircraft_finish_continuity_groups"]={"station":stations,"angular":angular,"material":materials}
