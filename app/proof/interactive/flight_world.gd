extends RefCounted
# Original generic high-wing presentation. No manufacturer dimensions, native
# forces, colliders, imported assets or real-airfield operational data.
# Local aircraft axes: right +X, up +Y, aft +Z. Parent applies accepted ECEF pose.

func material(color: Color, roughness: float = 0.65, metallic: float = 0.0) -> StandardMaterial3D:
	var value := StandardMaterial3D.new()
	value.albedo_color = color
	value.roughness = roughness
	value.metallic = metallic
	return value

func mesh_node(parent: Node3D, mesh: Mesh, at: Vector3, paint: Material) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.material_override = paint
	node.position = at
	parent.add_child(node)
	return node

func box(parent: Node3D, size: Vector3, at: Vector3, paint: Material) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	return mesh_node(parent, mesh, at, paint)

func ball(parent: Node3D, size: Vector3, at: Vector3, paint: Material) -> MeshInstance3D:
	var mesh := SphereMesh.new()
	mesh.radius = 0.5
	mesh.height = 1.0
	mesh.radial_segments = 24
	mesh.rings = 12
	var node := mesh_node(parent, mesh, at, paint)
	node.scale = size
	return node

func rod(parent: Node3D, a: Vector3, b: Vector3, radius: float, paint: Material) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = a.distance_to(b)
	mesh.radial_segments = 12
	var node := mesh_node(parent, mesh, (a+b)*0.5, paint)
	node.quaternion = Quaternion(Vector3.UP, (b-a).normalized())
	return node

func polygon(parent: Node3D, points: Array[Vector3], paint: Material) -> MeshInstance3D:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(1, points.size()-1):
		for point in [points[0],points[i+1],points[i]]:
			surface.add_vertex(point)
	surface.generate_normals()
	return mesh_node(parent, surface.commit(), Vector3.ZERO, paint)

func fuselage(parent: Node3D, paint: Material) -> void:
	# Elliptical loft with a cabin shoulder and tapering tail, rounded normals.
	var stations: Array[Vector4] = [Vector4(-3.02,0.00,0.25,0.29),Vector4(-2.65,0.02,0.45,0.44),Vector4(-1.72,0.04,0.59,0.56),Vector4(-0.80,0.10,0.68,0.67),Vector4(0.65,0.08,0.63,0.62),Vector4(1.30,0.05,0.44,0.44),Vector4(2.42,0.12,0.23,0.24),Vector4(3.55,0.18,0.07,0.12)]
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	surface.set_smooth_group(0)
	for row in range(stations.size()-1):
		for segment in range(40):
			var corners: Array[Vector3] = []
			for index in [row,row+1]:
				var station: Vector4 = stations[index]
				for angle in [TAU*segment/40.0,TAU*(segment+1)/40.0]:
					corners.append(Vector3(cos(angle)*station.z,station.y+sin(angle)*station.w,station.x))
			for index in [0,1,2,1,3,2]:
				surface.add_vertex(corners[index])
	surface.generate_normals()
	mesh_node(parent,surface.commit(),Vector3.ZERO,paint)

func wing(parent: Node3D, span: float, chord: float, height: float, aft: float, paint: Material) -> void:
	# Cambered original airfoil surface; purely visual, not aerodynamic input.
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	surface.set_smooth_group(0)
	var chord_stations: Array[Vector2] = [Vector2(-0.52,0),Vector2(-0.40,0.070),Vector2(-0.14,0.092),Vector2(0.23,0.045),Vector2(0.48,0),Vector2(0.23,-0.017),Vector2(-0.14,-0.024),Vector2(-0.40,-0.015)]
	for band in range(18):
		for index in range(chord_stations.size()):
			var corners: Array[Vector3] = []
			for side in [band,band+1]:
				var x: float = -span*0.5+span*side/18.0
				var taper: float = 1.0-0.20*absf(x)/(span*0.5)
				for edge in [index,(index+1)%chord_stations.size()]:
					var section: Vector2 = chord_stations[edge]
					corners.append(Vector3(x,height+0.025*absf(x)+section.y*chord*taper,aft+section.x*chord*taper+0.10*absf(x)/(span*0.5)))
			for vertex in [0,1,2,1,3,2]:
				surface.add_vertex(corners[vertex])
	surface.generate_normals()
	mesh_node(parent,surface.commit(),Vector3.ZERO,paint)

func aircraft(parent: Node3D) -> Dictionary:
	var airplane := Node3D.new()
	airplane.name = "OriginalHighWingVisual"
	parent.add_child(airplane)
	var ivory: Material = material(Color(0.91,0.94,0.93),0.36,0.12)
	var navy: Material = material(Color(0.025,0.10,0.17),0.35,0.22)
	var teal: Material = material(Color(0.06,0.53,0.55),0.38,0.15)
	var glass: Material = material(Color(0.045,0.16,0.23),0.16,0.48)
	glass.cull_mode=BaseMaterial3D.CULL_DISABLED
	navy.cull_mode=BaseMaterial3D.CULL_DISABLED
	var metal: Material = material(Color(0.48,0.55,0.58),0.32,0.72)
	var tire: Material = material(Color(0.018,0.021,0.025),0.96)
	fuselage(airplane,ivory)
	wing(airplane,9.0,1.55,0.89,-0.30,ivory)
	wing(airplane,3.20,0.88,0.28,2.92,ivory)
	# Cabin glazing has solid, opaque depth and distinct frames in both views.
	polygon(airplane,[Vector3(-0.50,0.42,-1.66),Vector3(0.50,0.42,-1.66),Vector3(0.55,0.72,-0.88),Vector3(-0.55,0.72,-0.88)],glass)
	rod(airplane,Vector3(0,0.43,-1.67),Vector3(0,0.73,-0.89),0.019,ivory)
	for side in [-1.0,1.0]:
		polygon(airplane,[Vector3(side*0.62,0.20,-0.94),Vector3(side*0.60,0.22,0.12),Vector3(side*0.47,0.64,0.14),Vector3(side*0.54,0.65,-0.85)],glass)
		polygon(airplane,[Vector3(side*0.60,0.22,0.22),Vector3(side*0.45,0.21,0.90),Vector3(side*0.35,0.49,0.80),Vector3(side*0.47,0.63,0.23)],glass)
		rod(airplane,Vector3(side*0.60,0.22,0.17),Vector3(side*0.47,0.66,0.17),0.025,ivory)
		rod(airplane,Vector3(side*0.51,-0.28,0.33),Vector3(side*2.65,0.92,0.04),0.032,ivory)
		# Painted beltline, wingtip caps and trailing-edge seams.
		rod(airplane,Vector3(side*0.575,-0.035,-1.65),Vector3(side*0.57,-0.035,0.80),0.045,teal)
		rod(airplane,Vector3(side*0.46,0.01,1.18),Vector3(side*0.13,0.12,3.08),0.038,navy)
		box(airplane,Vector3(0.36,0.055,1.19),Vector3(side*4.31,1.04,-0.19),teal)
		rod(airplane,Vector3(side*0.91,0.902,0.43),Vector3(side*4.20,1.002,0.39),0.007,navy)
		box(airplane,Vector3(0.13,0.035,0.03),Vector3(side*0.64,0.13,-0.36),metal)
		var nav := material(Color(0.95,0.08,0.04) if side<0 else Color(0.05,0.90,0.30))
		nav.emission_enabled=true
		nav.emission=nav.albedo_color
		ball(airplane,Vector3(0.075,0.055,0.085),Vector3(side*4.5,1.02,-0.28),nav)
	# Swept vertical fin and rudder cap, original proportions.
	polygon(airplane,[Vector3(-0.035,0.22,2.44),Vector3(-0.035,1.55,3.13),Vector3(-0.035,1.42,3.54),Vector3(-0.035,0.19,3.54)],navy)
	polygon(airplane,[Vector3(0.035,0.22,2.44),Vector3(0.035,1.55,3.13),Vector3(0.035,1.42,3.54),Vector3(0.035,0.19,3.54)],navy)
	rod(airplane,Vector3(0,1.45,3.18),Vector3(0,1.36,3.50),0.037,teal)
	# Small surface details make scale/readability apparent without cockpit claims.
	ball(airplane,Vector3(0.055,0.055,0.075),Vector3(0,0.28,3.57),ivory)
	rod(airplane,Vector3(0,0.84,0.37),Vector3(0,1.25,0.65),0.013,metal)
	rod(airplane,Vector3(-3.14,0.94,-0.70),Vector3(-3.14,0.94,-1.05),0.012,metal)
	ball(airplane,Vector3(0.38,0.38,0.22),Vector3(0,0,-3.06),metal)
	var propeller := Node3D.new()
	propeller.position=Vector3(0,0,-3.18)
	airplane.add_child(propeller)
	for side in [-1.0,1.0]:
		var blade := ball(propeller,Vector3(0.14,0.98,0.055),Vector3(0,side*0.53,0),navy)
		blade.rotation_degrees.z=-12
		box(propeller,Vector3(0.15,0.14,0.055),Vector3(0,side*0.98,0),ivory)
	ball(propeller,Vector3(0.26,0.26,0.32),Vector3(0,0,-0.055),ivory)
	var gears: Dictionary = {}
	for id in ["gear.nose","gear.left","gear.right"]:
		var gear := Node3D.new()
		gear.name=id.replace(".","_")+"NativeContactOrigin"
		# The caller positions this origin at the actual native contact point.
		# Tire radius offsets UP; there is no visual ground/contact solver.
		airplane.add_child(gear)
		gears[id]=gear
		var mesh := CylinderMesh.new()
		mesh.top_radius=0.25
		mesh.bottom_radius=0.25
		mesh.height=0.17
		mesh.radial_segments=32
		var wheel := mesh_node(gear,mesh,Vector3(0,0.25,0),tire)
		wheel.rotation_degrees.z=90
		rod(gear,Vector3(-0.10,0.25,0),Vector3(0.10,0.25,0),0.115,metal)
		var lean: float = 0.70 if id=="gear.left" else -0.70 if id=="gear.right" else 0.0
		rod(gear,Vector3(0,0.30,0),Vector3(lean,0.81,0.04),0.034,metal)
		rod(gear,Vector3(lean,0.57,0.04),Vector3(lean,0.85,0.04),0.052,ivory)
	return {"airplane":airplane,"gears":gears,"propeller":propeller}

func paint_line(parent: Node3D, a: Vector3, b: Vector3, width: float, paint: Material) -> void:
	var strip := box(parent,Vector3(width,0.002,a.distance_to(b)),(a+b)*0.5,paint)
	strip.rotation.y=atan2(b.x-a.x,b.z-a.z)
	strip.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

func surface_text(parent: Node3D, text: String, at: Vector3, height: float, color: Color) -> void:
	var label := Label3D.new()
	label.text=text
	label.font_size=160
	label.pixel_size=height/160.0
	label.modulate=color
	label.outline_size=0
	label.no_depth_test=false
	label.shaded=false
	label.rotation_degrees.x=-90
	label.position=at
	parent.add_child(label)

func hangar(parent: Node3D, at: Vector3, paint: Material) -> void:
	var building := Node3D.new()
	building.position=at
	parent.add_child(building)
	box(building,Vector3(34,9,27),Vector3(0,4.5,0),paint)
	var dark: Material=material(Color(0.09,0.14,0.16))
	box(building,Vector3(29,7,0.06),Vector3(0,3.7,-13.55),dark)
	for i in range(10):
		box(building,Vector3(0.11,7,0.09),Vector3(-13+i*2.9,3.7,-13.61),paint)
	box(building,Vector3(35,0.25,28),Vector3(0,9.1,0),material(Color(0.29,0.34,0.34)))
	for x in [-10.0,10.0]:
		box(building,Vector3(4,1.5,0.08),Vector3(x,7.75,-13.61),material(Color(0.35,0.62,0.72),0.3))

func trees(parent: Node3D) -> void:
	var random := RandomNumberGenerator.new()
	random.seed=7061
	var bark := material(Color(0.25,0.19,0.12))
	var leaf := material(Color.WHITE)
	leaf.vertex_color_use_as_albedo=true
	var trunk := CylinderMesh.new()
	trunk.top_radius=0.13
	trunk.bottom_radius=0.21
	trunk.height=1.0
	trunk.radial_segments=7
	var crown := SphereMesh.new()
	crown.radius=0.5
	crown.height=1.0
	crown.radial_segments=12
	crown.rings=6
	var instances: Array[MultiMeshInstance3D]=[]
	for mesh in [trunk,crown,crown]:
		var multi := MultiMesh.new()
		multi.transform_format=MultiMesh.TRANSFORM_3D
		multi.use_colors=true
		multi.mesh=mesh
		multi.instance_count=260
		var node := MultiMeshInstance3D.new()
		node.multimesh=multi
		node.material_override=bark if instances.is_empty() else leaf
		parent.add_child(node)
		instances.append(node)
	for i in range(260):
		var x: float=random.randf_range(180,2700)*(1 if i%2==0 else -1)
		var z: float=random.randf_range(-3100,1700)
		var height: float=random.randf_range(6,13)
		instances[0].multimesh.set_instance_transform(i,Transform3D(Basis.from_scale(Vector3(1,height*0.65,1)),Vector3(x,height*0.325,z)))
		for layer in [1,2]:
			var size: Vector3=Vector3(height*0.62,height*0.65,height*0.60)*(1.0 if layer==1 else 0.68)
			var at: Vector3=Vector3(x+1.0*(layer-1),height*(0.65 if layer==1 else 0.85),z)
			instances[layer].multimesh.set_instance_transform(i,Transform3D(Basis.from_scale(size),at))
			instances[layer].multimesh.set_instance_color(i,Color(random.randf_range(0.18,0.30),random.randf_range(0.30,0.43),random.randf_range(0.11,0.21)))

func distant_ridges(parent: Node3D) -> void:
	# Irregular ridge contours beyond the resident physics RECTANGLE. This is
	# decorative background only; coverage stops before any of these slopes.
	var random := RandomNumberGenerator.new()
	random.seed=73105
	var points: Array[Vector3]=[]
	var heights: Array[float]=[]
	for i in range(97):
		var angle: float=TAU*(i%96)/96.0
		var boundary: float=20000.0/maxf(absf(cos(angle)),absf(sin(angle)))
		var height: float=1100+520*sin(angle*3+0.4)+340*sin(angle*7)+random.randf_range(-150,260)
		points.append(Vector3(cos(angle)*(boundary+1200),0,sin(angle)*(boundary+1200)))
		heights.append(height)
	heights[96]=heights[0]
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(96):
		var a: Vector3=points[i]
		var b: Vector3=points[i+1]
		var direction_a: Vector3=a.normalized()
		var direction_b: Vector3=b.normalized()
		var c: Vector3=a+direction_a*4200+Vector3.UP*heights[i]
		var d: Vector3=b+direction_b*4200+Vector3.UP*heights[i+1]
		var e: Vector3=a+direction_a*10000
		var f: Vector3=b+direction_b*10000
		for triangle in [[a,c,b],[b,c,d],[c,e,d],[d,e,f]]:
			var normal: Vector3=(triangle[1]-triangle[0]).cross(triangle[2]-triangle[0]).normalized()
			if normal.y<0:
				triangle.reverse()
				normal=-normal
			for vertex in triangle:
				surface.set_normal(normal)
				surface.add_vertex(vertex)
	var ridge := mesh_node(parent,surface.commit(),Vector3.ZERO,material(Color(0.12,0.21,0.18),0.98))
	ridge.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

func build(parent: Node3D) -> Dictionary:
	var environment := WorldEnvironment.new()
	var config := Environment.new()
	var sky := Sky.new()
	var atmosphere := ProceduralSkyMaterial.new()
	atmosphere.sky_top_color=Color(0.065,0.25,0.50)
	atmosphere.sky_horizon_color=Color(0.47,0.66,0.80)
	atmosphere.ground_horizon_color=Color(0.47,0.66,0.80)
	atmosphere.ground_bottom_color=Color(0.21,0.27,0.18)
	atmosphere.sun_angle_max=12
	atmosphere.sun_curve=0.10
	sky.sky_material=atmosphere
	config.background_mode=Environment.BG_SKY
	config.sky=sky
	config.ambient_light_source=Environment.AMBIENT_SOURCE_SKY
	config.ambient_light_energy=0.42
	config.tonemap_mode=Environment.TONE_MAPPER_FILMIC
	config.fog_enabled=true
	config.fog_light_color=Color(0.48,0.64,0.75)
	config.fog_light_energy=0.42
	config.fog_density=0.000009
	config.fog_sky_affect=0.12
	environment.environment=config
	parent.add_child(environment)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees=Vector3(-34,-32,0)
	sun.light_color=Color(1.0,0.91,0.78)
	sun.light_energy=1.0
	sun.shadow_enabled=true
	sun.directional_shadow_mode=DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.directional_shadow_max_distance=1800
	parent.add_child(sun)
	# Exact same prepared plane: all scenery is decorative and has no collider.
	var grass: Material=material(Color(0.16,0.25,0.10))
	var asphalt: Material=material(Color(0.105,0.13,0.15),0.94)
	var white: Material=material(Color(0.91,0.92,0.83))
	var yellow: Material=material(Color(0.95,0.68,0.17))
	box(parent,Vector3(40000,2,40000),Vector3(0,-1,0),grass)
	var patches := RandomNumberGenerator.new()
	patches.seed=404
	for i in range(75):
		var x: float=patches.randf_range(-8000,8000)
		var z: float=patches.randf_range(-8000,8000)
		if absf(x)<400 and z>-2300 and z<600:
			continue
		var patch := box(parent,Vector3(patches.randf_range(300,1200),0.002,patches.randf_range(250,950)),Vector3(x,0.001,z),material(Color(patches.randf_range(0.14,0.20),patches.randf_range(0.22,0.29),patches.randf_range(0.08,0.13))))
		patch.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	box(parent,Vector3(40,0.004,1800),Vector3(0,0.002,-800),asphalt)
	for x in [-18.0,18.0]:
		paint_line(parent,Vector3(x,0.006,95),Vector3(x,0.006,-1695),0.35,white)
	for i in range(20):
		paint_line(parent,Vector3(0,0.007,-20-i*85),Vector3(0,0.007,-52-i*85),0.85,white)
	for end in [0.0,-1600.0]:
		for x in [-15.0,-11.0,-7.0,7.0,11.0,15.0]:
			box(parent,Vector3(2.3,0.003,27),Vector3(x,0.007,end-12),white)
	for x in [-11.0,11.0]:
		box(parent,Vector3(5,0.003,32),Vector3(x,0.007,-280),white)
		box(parent,Vector3(5,0.003,32),Vector3(x,0.007,-1320),white)
	surface_text(parent,"36",Vector3(0,0.012,-76),9.5,Color(0.93,0.94,0.88))
	surface_text(parent,"18",Vector3(0,0.012,-1528),9.5,Color(0.93,0.94,0.88))
	# Parallel taxiway and a small apron, directional cues without procedures.
	box(parent,Vector3(15,0.004,1840),Vector3(82,0.002,-800),asphalt)
	box(parent,Vector3(130,0.004,190),Vector3(132,0.002,25),asphalt)
	for z in [30.0,-800.0,-1630.0]:
		box(parent,Vector3(65,0.004,15),Vector3(49,0.002,z),asphalt)
		paint_line(parent,Vector3(24,0.007,z),Vector3(82,0.007,z),0.22,yellow)
		for offset in [-1.3,-0.7,0.7,1.3]:
			paint_line(parent,Vector3(30+offset,0.008,z-7),Vector3(30+offset,0.008,z+7),0.20,yellow)
	paint_line(parent,Vector3(82,0.007,98),Vector3(82,0.007,-1688),0.22,yellow)
	for i in range(5):
		var x: float=108+i*19
		paint_line(parent,Vector3(x,0.007,16),Vector3(x,0.007,52),0.20,yellow)
		paint_line(parent,Vector3(x-5,0.007,16),Vector3(x+5,0.007,16),0.20,yellow)
	for i in range(3):
		hangar(parent,Vector3(116+i*42,0,109),material(Color(0.53+0.05*i,0.57+0.02*i,0.52)))
	box(parent,Vector3(20,5,13),Vector3(181,2.5,-87),material(Color(0.68,0.64,0.52)))
	box(parent,Vector3(7,12,7),Vector3(195,6,-89),material(Color(0.63,0.66,0.64)))
	box(parent,Vector3(10,3,10),Vector3(195,13,-89),material(Color(0.07,0.20,0.25),0.25))
	# Marking lights are geometry only; they do not imply instrument navigation.
	for i in range(31):
		for x in [-21.0,21.0]:
			rod(parent,Vector3(x,0,-50-i*50),Vector3(x,0.28,-50-i*50),0.035,asphalt)
			ball(parent,Vector3(0.14,0.10,0.14),Vector3(x,0.29,-50-i*50),white)
	rod(parent,Vector3(-52,0,80),Vector3(-52,7,80),0.075,white)
	var sock := CylinderMesh.new()
	sock.top_radius=0.38
	sock.bottom_radius=0.12
	sock.height=2.0
	var windsock := mesh_node(parent,sock,Vector3(-52,5.8,80),material(Color(0.92,0.31,0.09)))
	windsock.rotation_degrees.z=8
	# Decorative drooping windsock, not a native wind sensor (prepared wind zero).
	trees(parent)
	distant_ridges(parent)
	var result: Dictionary=aircraft(parent)
	var camera := Camera3D.new()
	camera.fov=65
	camera.near=0.08
	camera.far=50000
	camera.current=true
	parent.add_child(camera)
	result["camera"]=camera
	return result
