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

func build(parent: Node3D, panel_texture: Texture2D) -> Dictionary:
	# Clear references before admission so a failed rebuild cannot reuse old nodes.
	yoke=null
	pedals.clear()
	throttle_handle=null
	trim_wheel=null
	var asset: Node3D=preload("res://cockpit/assets/original_asset.gd").instantiate()
	if asset==null:
		return {}
	var root := Node3D.new()
	root.name="OriginalReadonlyCockpit"
	root.add_child(asset)
	yoke=asset.get_node("CopiedPilotYoke") as Node3D
	pedals.append(asset.get_node("CopiedLeftPedal") as Node3D)
	pedals.append(asset.get_node("CopiedRightPedal") as Node3D)
	throttle_handle=asset.get_node("CopiedThrottleHandle") as Node3D
	trim_wheel=asset.get_node("CopiedTrimWheel") as Node3D
	var bezel: Material=paint(Color(0.055,0.065,0.071),0.90,0.08)
	var screen := QuadMesh.new()
	screen.size=Vector2(1.115,0.5575)
	var display := StandardMaterial3D.new()
	display.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
	display.albedo_color=Color.WHITE
	display.albedo_texture=panel_texture
	display.texture_filter=BaseMaterial3D.TEXTURE_FILTER_LINEAR
	display.cull_mode=BaseMaterial3D.CULL_DISABLED
	# The live panel and shared six open bezels retain their original geometry.
	var panel := mesh_node(root,screen,Vector3(0,0.255,-1.535),display)
	panel.name="LiveReadonlyPanelSurface"
	panel.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_build_bezels(root,bezel)
	update_controls({})
	parent.add_child(root)
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
