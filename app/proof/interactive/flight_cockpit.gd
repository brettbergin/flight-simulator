extends RefCounted
# Original generic interior, not a manufacturer cockpit or calibrated system.
# All dimensions are presentation choices. Local axes right/up/aft (+X/+Y/+Z).
# No colliders, input handling, session access or control-command writes.
var yoke: Node3D
var pedals: Array[Node3D]=[]
var throttle_handle: Node3D
var trim_wheel: Node3D
const YOKE_HOME := Vector3(-0.27,0.075,-1.265)
const THROTTLE_HOME := Vector3(0.22,-0.07,-1.305)
# Align the six rings to the unchanged 1024x512 physical drawing coordinates.
const PANEL_SIZE := Vector2(1.115,0.5575)
const PANEL_CENTER := Vector3(0,0.255,-1.535)
const BEZEL_SEGMENTS: int = 48
const BEZEL_INNER: float = (91.59+4.0)*1.115/1024.0
const BEZEL_OUTER: float = (91.59+9.0)*1.115/1024.0
const BEZEL_REAR_Z: float = -1.534
const BEZEL_DEPTH: float = 0.004

func _bezel_quad(vertices: PackedVector3Array, normals: PackedVector3Array, points: Array[Vector3], face_normals: Array[Vector3]) -> void:
	# Godot front faces wind clockwise when viewed from the outward normal.
	for index in [0,1,2,0,2,3]:
		vertices.append(points[index])
		normals.append(face_normals[index])

func _bezel_mesh() -> ArrayMesh:
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	for segment in range(BEZEL_SEGMENTS):
		var a: float = TAU*float(segment)/float(BEZEL_SEGMENTS)
		var b: float = TAU*float(segment+1)/float(BEZEL_SEGMENTS)
		var n0 := Vector3(cos(a),sin(a),0)
		var n1 := Vector3(cos(b),sin(b),0)
		var i0: Vector3 = n0*BEZEL_INNER
		var i1: Vector3 = n1*BEZEL_INNER
		var o0: Vector3 = n0*BEZEL_OUTER
		var o1: Vector3 = n1*BEZEL_OUTER
		var front := Vector3(0,0,BEZEL_DEPTH)
		_bezel_quad(vertices,normals,[i0+front,i1+front,o1+front,o0+front],[Vector3.BACK,Vector3.BACK,Vector3.BACK,Vector3.BACK])
		_bezel_quad(vertices,normals,[o0,o1,i1,i0],[Vector3.FORWARD,Vector3.FORWARD,Vector3.FORWARD,Vector3.FORWARD])
		_bezel_quad(vertices,normals,[o0,o0+front,o1+front,o1],[n0,n0,n1,n1])
		_bezel_quad(vertices,normals,[i0+front,i0,i1,i1+front],[-n0,-n0,-n1,-n1])
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX]=vertices
	arrays[Mesh.ARRAY_NORMAL]=normals
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	return mesh

func _build_bezels(parent: Node3D, material: Material) -> void:
	# Shared geometry/material: six mesh instances, 2304 triangles, no caps/glass.
	var mesh: ArrayMesh = _bezel_mesh()
	for index in range(6):
		var u: float = 130.5+float(index%3)*221.0
		var v: float = 145.59+float(index/3)*219.0
		var at := Vector3(-PANEL_SIZE.x*0.5+u*PANEL_SIZE.x/1024.0,PANEL_CENTER.y+PANEL_SIZE.y*0.5-v*PANEL_SIZE.y/512.0,BEZEL_REAR_Z)
		var ring := mesh_node(parent,mesh,at,material)
		ring.name="OriginalDialBezel"+str(index)
		ring.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func paint(color: Color, roughness: float=0.65, metallic: float=0.0) -> StandardMaterial3D:
	var value := StandardMaterial3D.new()
	value.albedo_color=color
	value.roughness=roughness
	value.metallic=metallic
	return value

func mesh_node(parent: Node3D, mesh: Mesh, at: Vector3, material: Material) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.mesh=mesh
	node.material_override=material
	node.position=at
	parent.add_child(node)
	return node

func box(parent: Node3D, size: Vector3, at: Vector3, material: Material) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size=size
	return mesh_node(parent,mesh,at,material)

func ellipsoid(parent: Node3D, size: Vector3, at: Vector3, material: Material) -> MeshInstance3D:
	var mesh := SphereMesh.new()
	mesh.radius=0.5
	mesh.height=1.0
	mesh.radial_segments=24
	mesh.rings=12
	var node := mesh_node(parent,mesh,at,material)
	node.scale=size
	return node

func rod(parent: Node3D, a: Vector3, b: Vector3, radius: float, material: Material) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius=radius
	mesh.bottom_radius=radius
	mesh.height=a.distance_to(b)
	mesh.radial_segments=12
	var node := mesh_node(parent,mesh,(a+b)*0.5,material)
	node.quaternion=Quaternion(Vector3.UP,(b-a).normalized())
	return node

func seat(parent: Node3D, at: Vector3, leather: Material, trim: Material) -> void:
	var root := Node3D.new()
	root.position=at
	parent.add_child(root)
	ellipsoid(root,Vector3(0.51,0.16,0.54),Vector3(0,-0.18,0),leather)
	var back := ellipsoid(root,Vector3(0.52,0.64,0.14),Vector3(0,0.08,0.26),leather)
	back.rotation_degrees.x=-8
	ellipsoid(root,Vector3(0.25,0.17,0.12),Vector3(0,0.47,0.28),leather)
	rod(root,Vector3(-0.11,0.33,0.25),Vector3(-0.11,0.44,0.27),0.012,trim)
	rod(root,Vector3(0.11,0.33,0.25),Vector3(0.11,0.44,0.27),0.012,trim)
	for x in [-0.14,0.14]:
		box(root,Vector3(0.03,0.22,0.38),Vector3(x,-0.34,0),trim)
	# Decorative upholstery seams, no passenger/restraint-system assertion.
	for x in [-0.15,0.15]:
		rod(root,Vector3(x,-0.13,-0.19),Vector3(x,-0.13,0.19),0.006,trim)

func build(parent: Node3D, panel_texture: Texture2D) -> Dictionary:
	var root := Node3D.new()
	root.name="OriginalReadonlyCockpit"
	parent.add_child(root)
	var warm: Material=paint(Color(0.46,0.43,0.36),0.94)
	var cloth: Material=paint(Color(0.25,0.29,0.29),0.95)
	var dark: Material=paint(Color(0.045,0.058,0.061),0.87)
	var metal: Material=paint(Color(0.25,0.28,0.29),0.78,0.12)
	var leather: Material=paint(Color(0.22,0.24,0.22),0.92)
	var accent: Material=paint(Color(0.075,0.39,0.41),0.52)
	var black: Material=paint(Color(0.013,0.018,0.021),0.92)
	var bezel: Material=paint(Color(0.055,0.065,0.071),0.90,0.08)
	# Open windshield and side-window apertures preserve outside visibility.
	# There are no opaque panes or fabricated weather/visibility effects.
	box(root,Vector3(1.40,0.08,2.06),Vector3(0,1.19,-0.37),warm)
	box(root,Vector3(1.32,0.08,1.96),Vector3(0,-0.59,-0.40),cloth)
	for side in [-1.0,1.0]:
		rod(root,Vector3(side*0.65,0.47,-1.72),Vector3(side*0.59,1.16,-1.39),0.043,warm)
		rod(root,Vector3(side*0.66,0.43,-1.60),Vector3(side*0.69,0.43,0.45),0.035,dark)
		rod(root,Vector3(side*0.63,1.15,-1.40),Vector3(side*0.69,1.15,0.50),0.038,warm)
		rod(root,Vector3(side*0.69,0.42,0.30),Vector3(side*0.69,1.16,0.30),0.032,warm)
		box(root,Vector3(0.075,0.85,1.80),Vector3(side*0.69,-0.025,-0.49),warm)
		box(root,Vector3(0.032,0.53,1.15),Vector3(side*0.639,-0.09,-0.40),cloth)
		box(root,Vector3(0.13,0.055,0.45),Vector3(side*0.62,0.15,-0.41),dark)
		rod(root,Vector3(side*0.602,0.22,-0.22),Vector3(side*0.602,0.22,-0.07),0.016,metal)
		box(root,Vector3(0.030,0.025,0.065),Vector3(side*0.61,0.29,-0.73),metal)
	rod(root,Vector3(-0.59,1.14,-1.41),Vector3(0.59,1.14,-1.41),0.041,warm)
	rod(root,Vector3(0,0.52,-1.72),Vector3(0,1.13,-1.41),0.014,dark)
	# Matte brow, gently rounded instrument housing and lower knee panel.
	ellipsoid(root,Vector3(1.37,0.64,0.26),Vector3(0,0.21,-1.75),dark)
	box(root,Vector3(1.24,0.64,0.05),Vector3(0,0.23,-1.605),dark)
	box(root,Vector3(1.39,0.055,0.40),Vector3(0,0.55,-1.755),black)
	rod(root,Vector3(-0.67,0.57,-1.59),Vector3(0.67,0.57,-1.59),0.033,black)
	box(root,Vector3(1.15,0.20,0.10),Vector3(0,-0.17,-1.72),cloth)
	# Thin accent/bezel and four fasteners frame the actual live texture.
	box(root,Vector3(1.18,0.605,0.018),Vector3(0,0.255,-1.569),metal)
	box(root,Vector3(1.15,0.585,0.020),Vector3(0,0.255,-1.552),black)
	var screen := QuadMesh.new()
	screen.size=Vector2(1.115,0.5575)
	var display := StandardMaterial3D.new()
	display.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
	display.albedo_color=Color.WHITE
	display.albedo_texture=panel_texture
	display.texture_filter=BaseMaterial3D.TEXTURE_FILTER_LINEAR
	display.cull_mode=BaseMaterial3D.CULL_DISABLED
	# QuadMesh's +Z face and canonical UVs face the eye at larger local Z:
	# texture top remains panel top; no mirror, rotation or second telemetry path.
	var panel := mesh_node(root,screen,Vector3(0,0.255,-1.535),display)
	panel.name="LiveReadonlyPanelSurface"
	panel.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_build_bezels(root,bezel)
	for x in [-0.573,0.573]:
		for y in [-0.032,0.541]:
			ellipsoid(root,Vector3(0.013,0.013,0.006),Vector3(x,y,-1.548),metal)
	seat(root,Vector3(-0.29,0,-0.20),leather,metal)
	seat(root,Vector3(0.29,0,-0.20),leather,metal)
	box(root,Vector3(0.15,0.19,0.73),Vector3(0,-0.43,-0.76),dark)
	# Pilot yoke is copied-state animation; it is never an input hit target.
	rod(root,Vector3(-0.27,-0.15,-1.56),Vector3(-0.27,0.07,-1.285),0.023,metal)
	yoke=Node3D.new()
	yoke.name="CopiedPilotYoke"
	yoke.position=YOKE_HOME
	root.add_child(yoke)
	ellipsoid(yoke,Vector3(0.115,0.075,0.056),Vector3.ZERO,black)
	rod(yoke,Vector3(-0.145,-0.027,0),Vector3(0.145,-0.027,0),0.020,black)
	for side in [-1.0,1.0]:
		rod(yoke,Vector3(side*0.143,-0.027,0),Vector3(side*0.183,0.075,-0.018),0.025,black)
		ellipsoid(yoke,Vector3(0.049,0.065,0.053),Vector3(side*0.183,0.082,-0.018),black)
	box(yoke,Vector3(0.035,0.008,0.010),Vector3(0,0.024,0.032),accent)
	pedals.clear()
	for i in range(2):
		var pedal := Node3D.new()
		pedal.name="CopiedLeftPedal" if i==0 else "CopiedRightPedal"
		pedal.position=Vector3(-0.27+(-0.09 if i==0 else 0.09),-0.47,-1.49)
		root.add_child(pedal)
		box(pedal,Vector3(0.13,0.025,0.20),Vector3(0,0.018,-0.025),metal)
		for z in [-0.075,-0.025,0.025]:
			box(pedal,Vector3(0.12,0.009,0.012),Vector3(0,0.035,z),black)
		pedals.append(pedal)
	# Generic throttle slider and trim wheel, solely copied held fractions.
	box(root,Vector3(0.075,0.044,0.27),Vector3(0.22,-0.16,-1.41),black)
	throttle_handle=Node3D.new()
	throttle_handle.name="CopiedThrottleHandle"
	throttle_handle.position=THROTTLE_HOME
	root.add_child(throttle_handle)
	rod(throttle_handle,Vector3(0,-0.09,0),Vector3(0,0.035,0),0.012,metal)
	ellipsoid(throttle_handle,Vector3(0.060,0.060,0.063),Vector3(0,0.04,0),black)
	trim_wheel=Node3D.new()
	trim_wheel.name="CopiedTrimWheel"
	trim_wheel.position=Vector3(0.09,-0.26,-0.92)
	root.add_child(trim_wheel)
	var rim := TorusMesh.new()
	rim.inner_radius=0.055
	rim.outer_radius=0.075
	rim.rings=24
	rim.ring_segments=12
	var wheel := mesh_node(trim_wheel,rim,Vector3.ZERO,black)
	wheel.rotation_degrees.z=90
	rod(trim_wheel,Vector3(0,-0.06,0),Vector3(0,0.06,0),0.007,metal)
	rod(trim_wheel,Vector3(0,0,-0.06),Vector3(0,0,0.06),0.007,metal)
	update_controls({})
	return {"root":root,"eye":Vector3(-0.27,0.67,-0.92),"panel_focus":Vector3(-0.08,0.255,-1.535)}

func update_controls(held: Dictionary) -> void:
	if yoke==null or not is_instance_valid(yoke):
		return
	var roll: float=clampf(float(held.get("roll",0.0)),-1,1)
	var pitch: float=clampf(float(held.get("pitch",0.0)),-1,1)
	var yaw: float=clampf(float(held.get("yaw",0.0)),-1,1)
	yoke.rotation.z=-roll*0.48
	yoke.position=YOKE_HOME+Vector3(0,0,pitch*0.07)
	for i in range(pedals.size()):
		var value: float=clampf(float(held.get("left_brake" if i==0 else "right_brake",0.0)),0,1)
		pedals[i].rotation.x=-value*0.28
		pedals[i].position.z=-1.49+yaw*(0.045 if i==0 else -0.045)
	throttle_handle.position=THROTTLE_HOME-Vector3(0,0,clampf(float(held.get("throttle",0.0)),0,1)*0.17)
	trim_wheel.rotation.x=clampf(float(held.get("trim",0.0)),-1,1)*PI
