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

# One opaque surface owns all grass, asphalt and paint. Coordinates are fixed
# to the prepared world's anchor frame, not the moving/rebased camera frame.
const GROUND_SHADER := """
shader_type spatial;
render_mode diffuse_burley, specular_disabled;
varying vec2 anchor_xz;
void vertex() { anchor_xz = VERTEX.xz; }

// Box-filter coverage preserves real widths and fades subpixel strokes instead
// of letting distant thin paint alternate between full brightness and nothing.
float rect_coverage(vec2 p, vec2 center, vec2 half_size, vec2 footprint) {
    vec2 q = p - center;
    vec2 a = max(footprint, vec2(0.0001));
    vec2 overlap = max(vec2(0.0), min(q + a, half_size) - max(q - a, -half_size));
    vec2 coverage = clamp(overlap / (2.0 * a), vec2(0.0), vec2(1.0));
    return coverage.x * coverage.y;
}
float hash21(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float value_noise(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash21(i), hash21(i + vec2(1.0, 0.0)), f.x),
               mix(hash21(i + vec2(0.0, 1.0)), hash21(i + vec2(1.0, 1.0)), f.x), f.y);
}
float digit(vec2 p, int n, vec2 aa) {
    // Original seven-segment synthetic numbers; these are decorative runway
    // cues, not real-airport data or a regulatory marking specification.
    int bits = 127;
    if (n == 1) { bits = 6; }
    if (n == 3) { bits = 79; }
    if (n == 6) { bits = 125; }
    float mask = 0.0;
    if ((bits & 1) != 0) { mask = max(mask, rect_coverage(p, vec2(0.0, 4.2), vec2(1.65, 0.35), aa)); }
    if ((bits & 2) != 0) { mask = max(mask, rect_coverage(p, vec2(1.65, 2.1), vec2(0.35, 1.9), aa)); }
    if ((bits & 4) != 0) { mask = max(mask, rect_coverage(p, vec2(1.65, -2.1), vec2(0.35, 1.9), aa)); }
    if ((bits & 8) != 0) { mask = max(mask, rect_coverage(p, vec2(0.0, -4.2), vec2(1.65, 0.35), aa)); }
    if ((bits & 16) != 0) { mask = max(mask, rect_coverage(p, vec2(-1.65, -2.1), vec2(0.35, 1.9), aa)); }
    if ((bits & 32) != 0) { mask = max(mask, rect_coverage(p, vec2(-1.65, 2.1), vec2(0.35, 1.9), aa)); }
    if ((bits & 64) != 0) { mask = max(mask, rect_coverage(p, vec2(0.0), vec2(1.65, 0.35), aa)); }
    return mask;
}
void fragment() {
    vec2 p = anchor_xz;
    vec2 aa = max(fwidth(p) * 0.5, vec2(0.0001));
    float pixel_m = max(aa.x, aa.y) * 2.0;
    float broad = mix(value_noise(p / 260.0), 0.5, smoothstep(65.0, 260.0, pixel_m));
    float middle = mix(value_noise(p / 75.0), 0.5, smoothstep(18.75, 75.0, pixel_m));
    float detail = (value_noise(p / 6.0) - 0.5) * (1.0 - smoothstep(1.0, 6.0, pixel_m));
    vec3 color = mix(vec3(0.14, 0.225, 0.085), vec3(0.21, 0.29, 0.12), broad);
    color += (middle - 0.5) * vec3(0.028, 0.032, 0.013) + detail * vec3(0.014, 0.019, 0.009);
    float runway = rect_coverage(p, vec2(0.0, -800.0), vec2(20.0, 900.0), aa);
    float paving = max(runway, rect_coverage(p, vec2(82.0, -800.0), vec2(7.5, 920.0), aa));
    paving = max(paving, rect_coverage(p, vec2(132.0, 25.0), vec2(65.0, 95.0), aa));
    for (int i = 0; i < 3; i++) {
        float z = i == 0 ? 30.0 : (i == 1 ? -800.0 : -1630.0);
        paving = max(paving, rect_coverage(p, vec2(49.0, z), vec2(32.5, 7.5), aa));
    }
    vec3 asphalt = vec3(0.105, 0.13, 0.15) + detail * 0.010;
    color = mix(color, asphalt, paving);
    // Skip the detailed marking work over the large uninterrupted grass area.
    if (p.x > -22.0 - aa.x && p.x < 200.0 + aa.x && p.y > -1720.0 - aa.y && p.y < 125.0 + aa.y) {
        float white = 0.0;
        for (int side = 0; side < 2; side++) {
            float x = side == 0 ? -18.0 : 18.0;
            white = max(white, rect_coverage(p, vec2(x, -800.0), vec2(0.175, 895.0), aa));
        }
        for (int i = 0; i < 20; i++) {
            white = max(white, rect_coverage(p, vec2(0.0, -36.0 - float(i) * 85.0), vec2(0.425, 16.0), aa));
        }
        for (int end = 0; end < 2; end++) {
            float z = -12.0 - float(end) * 1600.0;
            for (int i = 0; i < 6; i++) {
                float x = i < 3 ? -15.0 + float(i) * 4.0 : 7.0 + float(i - 3) * 4.0;
                white = max(white, rect_coverage(p, vec2(x, z), vec2(1.15, 13.5), aa));
            }
            for (int side = 0; side < 2; side++) {
                float x = side == 0 ? -11.0 : 11.0;
                white = max(white, rect_coverage(p, vec2(x, end == 0 ? -280.0 : -1320.0), vec2(2.5, 16.0), aa));
            }
        }
        vec2 south = vec2(p.x, -(p.y + 76.0));
        vec2 north = vec2(-p.x, p.y + 1528.0);
        white = max(white, digit(south - vec2(-3.0, 0.0), 3, aa));
        white = max(white, digit(south - vec2(3.0, 0.0), 6, aa));
        white = max(white, digit(north - vec2(-3.0, 0.0), 1, aa));
        white = max(white, digit(north - vec2(3.0, 0.0), 8, aa));
        color = mix(color, vec3(0.91, 0.92, 0.83), white * runway);
        float yellow = rect_coverage(p, vec2(82.0, -795.0), vec2(0.11, 893.0), aa);
        for (int i = 0; i < 3; i++) {
            float z = i == 0 ? 30.0 : (i == 1 ? -800.0 : -1630.0);
            yellow = max(yellow, rect_coverage(p, vec2(53.0, z), vec2(29.0, 0.11), aa));
            for (int j = 0; j < 4; j++) {
                float dx = j < 2 ? -1.3 + float(j) * 0.6 : 0.7 + float(j - 2) * 0.6;
                yellow = max(yellow, rect_coverage(p, vec2(30.0 + dx, z), vec2(0.10, 7.0), aa));
            }
        }
        for (int i = 0; i < 5; i++) {
            float x = 108.0 + float(i) * 19.0;
            yellow = max(yellow, rect_coverage(p, vec2(x, 34.0), vec2(0.10, 18.0), aa));
            yellow = max(yellow, rect_coverage(p, vec2(x, 16.0), vec2(5.0, 0.10), aa));
        }
        color = mix(color, vec3(0.95, 0.68, 0.17), yellow * paving);
    }
    ALBEDO = color;
    ROUGHNESS = 0.96;
}
"""

func ground(parent: Node3D) -> MeshInstance3D:
	var shader := Shader.new()
	shader.code = GROUND_SHADER
	var paint := ShaderMaterial.new()
	paint.shader = shader
	var plane := PlaneMesh.new()
	# Decorative skirt continues beneath the distant ridges so the sky cannot
	# show through their feet. Native resident coverage remains +/-20000 m.
	plane.size = Vector2(80000, 80000)
	var node := mesh_node(parent, plane, Vector3.ZERO, paint)
	node.name = "PrototypeGroundSurface"
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return node

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
	# Same prepared surface and ±20km bounds, with no colliders or depth layers.
	var ground_surface := ground(parent)
	var asphalt: Material=material(Color(0.105,0.13,0.15),0.94)
	var white: Material=material(Color(0.91,0.92,0.83))
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
	result["ground"]=ground_surface
	result["camera"]=camera
	return result
