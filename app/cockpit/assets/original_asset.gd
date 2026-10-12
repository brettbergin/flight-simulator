extends RefCounted
# Original MIT. Fixed original resource; never reads simulation, input or clocks.
# The independent GLB/source/import checks remain mandatory before distribution.
const ASSET := "res://cockpit/assets/original-cockpit.glb"
const MAX_DECODED_ARRAY_BYTES := 8*1024*1024
const MAX_TRIANGLES := 20000
const MARKERS := {
	"PilotEye": Vector3(-0.27,0.67,-0.92),
	"PanelFocus": Vector3(-0.08,0.255,-1.535),
	"PanelSurfaceAnchor": Vector3(0,0.255,-1.535),
	"CopiedPilotYoke": Vector3(-0.27,0.075,-1.265),
	"CopiedLeftPedal": Vector3(-0.36,-0.47,-1.49),
	"CopiedRightPedal": Vector3(-0.18,-0.47,-1.49),
	"CopiedThrottleHandle": Vector3(0.22,-0.07,-1.305),
	"CopiedTrimWheel": Vector3(0.09,-0.26,-0.92),
}
const PARTS := {
	"Roof": ["Static", "WarmTrim"],
	"Floor": ["Static", "Cloth"],
	"LeftFrontPillar": ["Static", "WarmTrim"],
	"LeftLowerRail": ["Static", "Dark"],
	"LeftUpperRail": ["Static", "WarmTrim"],
	"LeftRearPost": ["Static", "WarmTrim"],
	"LeftLowerWall": ["Static", "WarmTrim"],
	"LeftClothInset": ["Static", "Cloth"],
	"LeftArmrest": ["Static", "Dark"],
	"LeftHandle": ["Static", "Metal"],
	"LeftLatch": ["Static", "Metal"],
	"RightFrontPillar": ["Static", "WarmTrim"],
	"RightLowerRail": ["Static", "Dark"],
	"RightUpperRail": ["Static", "WarmTrim"],
	"RightRearPost": ["Static", "WarmTrim"],
	"RightLowerWall": ["Static", "WarmTrim"],
	"RightClothInset": ["Static", "Cloth"],
	"RightArmrest": ["Static", "Dark"],
	"RightHandle": ["Static", "Metal"],
	"RightLatch": ["Static", "Metal"],
	"WindshieldTopRail": ["Static", "WarmTrim"],
	"WindshieldCenterPost": ["Static", "Dark"],
	"PanelHousing": ["Static", "Dark"],
	"PanelBacking": ["Static", "Dark"],
	"GlareTop": ["Static", "Black"],
	"GlareLip": ["Static", "Black"],
	"LowerKneePanel": ["Static", "Cloth"],
	"PanelFrameMetal": ["Static", "Metal"],
	"PanelFrameBlack": ["Static", "Black"],
	"PanelFastener00": ["Static", "Metal"],
	"PanelFastener01": ["Static", "Metal"],
	"PanelFastener10": ["Static", "Metal"],
	"PanelFastener11": ["Static", "Metal"],
	"LeftSeatCushion": ["Static", "Leather"],
	"LeftSeatBack": ["Static", "Leather"],
	"LeftSeatHeadrest": ["Static", "Leather"],
	"LeftSeatPost0": ["Static", "Metal"],
	"LeftSeatPost1": ["Static", "Metal"],
	"LeftSeatRail0": ["Static", "Metal"],
	"LeftSeatRail1": ["Static", "Metal"],
	"LeftSeatSeam0": ["Static", "Metal"],
	"LeftSeatSeam1": ["Static", "Metal"],
	"RightSeatCushion": ["Static", "Leather"],
	"RightSeatBack": ["Static", "Leather"],
	"RightSeatHeadrest": ["Static", "Leather"],
	"RightSeatPost0": ["Static", "Metal"],
	"RightSeatPost1": ["Static", "Metal"],
	"RightSeatRail0": ["Static", "Metal"],
	"RightSeatRail1": ["Static", "Metal"],
	"RightSeatSeam0": ["Static", "Metal"],
	"RightSeatSeam1": ["Static", "Metal"],
	"CenterPedestal": ["Static", "Dark"],
	"YokeStem": ["Static", "Metal"],
	"YokeHub": ["CopiedPilotYoke", "Black"],
	"YokeCrossbar": ["CopiedPilotYoke", "Black"],
	"YokeLeftGripRod": ["CopiedPilotYoke", "Black"],
	"YokeLeftGrip": ["CopiedPilotYoke", "Black"],
	"YokeRightGripRod": ["CopiedPilotYoke", "Black"],
	"YokeRightGrip": ["CopiedPilotYoke", "Black"],
	"YokeAccent": ["CopiedPilotYoke", "Accent"],
	"LeftPedalPlate": ["CopiedLeftPedal", "Metal"],
	"LeftPedalTread0": ["CopiedLeftPedal", "Black"],
	"LeftPedalTread1": ["CopiedLeftPedal", "Black"],
	"LeftPedalTread2": ["CopiedLeftPedal", "Black"],
	"RightPedalPlate": ["CopiedRightPedal", "Metal"],
	"RightPedalTread0": ["CopiedRightPedal", "Black"],
	"RightPedalTread1": ["CopiedRightPedal", "Black"],
	"RightPedalTread2": ["CopiedRightPedal", "Black"],
	"ThrottleSlot": ["Static", "Black"],
	"ThrottleShaft": ["CopiedThrottleHandle", "Metal"],
	"ThrottleKnob": ["CopiedThrottleHandle", "Black"],
	"TrimRim": ["CopiedTrimWheel", "Black"],
	"TrimSpokeY": ["CopiedTrimWheel", "Metal"],
	"TrimSpokeZ": ["CopiedTrimWheel", "Metal"],
}
const MATERIALS := {
	"WarmTrim": [0.46, 0.43, 0.36, 0.94, 0],
	"Cloth": [0.25, 0.29, 0.29, 0.95, 0],
	"Dark": [0.045, 0.058, 0.061, 0.87, 0],
	"Metal": [0.25, 0.28, 0.29, 0.78, 0.12],
	"Leather": [0.22, 0.24, 0.22, 0.92, 0],
	"Accent": [0.075, 0.39, 0.41, 0.52, 0],
	"Black": [0.013, 0.018, 0.021, 0.92, 0],
}

static func _finite3(value: Vector3) -> bool:
	return is_finite(value.x) and is_finite(value.y) and is_finite(value.z)

static func _derived_tangents_valid(value: Variant, normals: PackedVector3Array) -> bool:
	# Fixed pinned-engine derived channel; original GLB attributes stay closed.
	if not value is PackedFloat32Array or value.is_empty() or value.size() != normals.size()*4:
		return false
	for component: float in value:
		if not is_finite(component) or component < -1.0 or component > 1.0:
			return false
	for index in range(normals.size()):
		var offset: int = index*4
		var tangent := Vector3(value[offset],value[offset+1],value[offset+2])
		var handedness: float = value[offset+3]
		if handedness != -1.0 and handedness != 1.0:
			return false
		if not _finite3(normals[index]) or absf(tangent.length_squared()-1.0)>0.00001 or absf(tangent.dot(normals[index]))>0.00025:
			return false
	return true

static func _identity(node: Node3D) -> bool:
	return node.transform == Transform3D.IDENTITY

static func _part_pose(name: String, node: Node3D) -> bool:
	# Only the two frozen original source SeatBack frames are unbaked. No root,
	# live copied-control pivot, other part or arbitrary transform is admitted.
	if name not in ["LeftSeatBack", "RightSeatBack"]:
		return _identity(node)
	var expected_position := Vector3(-0.29 if name=="LeftSeatBack" else 0.29,0.08,0.06)
	var expected_basis := Basis.from_euler(Vector3(deg_to_rad(-8.0),0,0))
	return _finite3(node.position) and node.position.distance_to(expected_position)<=0.000001 and _finite3(node.basis.x) and _finite3(node.basis.y) and _finite3(node.basis.z) and node.basis.x.distance_to(expected_basis.x)<=0.000001 and node.basis.y.distance_to(expected_basis.y)<=0.000001 and node.basis.z.distance_to(expected_basis.z)<=0.000001

static func _reject(root: Node) -> Node3D:
	if is_instance_valid(root):
		root.free()
	return null

static func instantiate() -> Node3D:
	# Exports retain the fixed imported PackedScene and its remap, not raw GLB bytes.
	# Source GLB size/provenance remain enforced by the offline source/import checks.
	if not ResourceLoader.exists(ASSET, "PackedScene"):
		return null
	var scene := ResourceLoader.load(ASSET, "PackedScene") as PackedScene
	if scene == null:
		return null
	var imported := scene.instantiate()
	if not imported is Node3D:
		return _reject(imported)
	var root := imported as Node3D
	# Godot may retain its one synthetic scene container. It contributes no
	# asset node: detach only the exact sole identity named asset child.
	if root.name != "OriginalCockpitAsset":
		if root.get_class() != "Node3D" or root.get_script() != null or not _identity(root) or root.get_child_count() != 1:
			return _reject(root)
		var asset := root.get_child(0) as Node3D
		if asset == null or asset.name != "OriginalCockpitAsset":
			return _reject(root)
		root.remove_child(asset)
		root.free()
		root = asset
	if root.get_class() != "Node3D" or root.get_script() != null or not _identity(root) or root.get_child_count() != 9:
		return _reject(root)
	var groups: Dictionary = {}
	for child in root.get_children():
		if not child is Node3D or child.get_class() != "Node3D" or child.get_script() != null or groups.has(str(child.name)):
			return _reject(root)
		groups[str(child.name)] = child
	if groups.size() != 9 or not groups.has("Static") or not _identity(groups["Static"]):
		return _reject(root)
	for marker: String in MARKERS:
		if not groups.has(marker):
			return _reject(root)
		var node: Node3D = groups[marker]
		if not _finite3(node.position) or node.position.distance_to(MARKERS[marker]) > 0.000001 or node.basis != Basis.IDENTITY:
			return _reject(root)
	var materials: Dictionary = {}
	var texture_ids: Dictionary = {}
	var observed: Dictionary = {}
	var triangles: int = 0
	var storage: int = 0
	for group: Node3D in groups.values():
		for child in group.get_children():
			var name: String = str(child.name)
			if not child is MeshInstance3D or child.get_class() != "MeshInstance3D" or child.get_script() != null or child.get_child_count() != 0 or observed.has(name) or not PARTS.has(name):
				return _reject(root)
			if PARTS[name][0] != str(group.name) or not _part_pose(name,child):
				return _reject(root)
			observed[name] = true
			var mesh := child.mesh as ArrayMesh
			if mesh == null or mesh.get_surface_count() != 1 or mesh.surface_get_primitive_type(0) != Mesh.PRIMITIVE_TRIANGLES:
				return _reject(root)
			var arrays: Array = mesh.surface_get_arrays(0)
			if arrays.size()!=Mesh.ARRAY_MAX:
				return _reject(root)
			for channel in range(Mesh.ARRAY_MAX):
				if channel not in [Mesh.ARRAY_VERTEX,Mesh.ARRAY_NORMAL,Mesh.ARRAY_TANGENT,Mesh.ARRAY_TEX_UV,Mesh.ARRAY_INDEX] and arrays[channel]!=null and arrays[channel].size()!=0:
					return _reject(root)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
			var uv: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			var tangents: Variant = arrays[Mesh.ARRAY_TANGENT]
			if vertices.size() < 3 or vertices.size() != normals.size() or vertices.size() != uv.size() or indices.size() < 3 or indices.size()%3 != 0:
				return _reject(root)
			for index in range(vertices.size()):
				if not _finite3(vertices[index]) or not _finite3(normals[index]) or absf(normals[index].length_squared()-1.0)>0.00001 or not is_finite(uv[index].x) or not is_finite(uv[index].y) or uv[index].x<0 or uv[index].x>1 or uv[index].y<0 or uv[index].y>1:
					return _reject(root)
			if not _derived_tangents_valid(tangents,normals):
				return _reject(root)
			for index: int in indices:
				if index < 0 or index >= vertices.size():
					return _reject(root)
			triangles += int(indices.size()/3)
			storage += vertices.size()*12+normals.size()*12+uv.size()*8+indices.size()*4
			storage += 0 if tangents==null else tangents.size()*4
			if triangles > MAX_TRIANGLES or storage > MAX_DECODED_ARRAY_BYTES:
				return _reject(root)
			var material := mesh.surface_get_material(0) as StandardMaterial3D
			var material_name: String = PARTS[name][1]
			if material == null or str(material.resource_name) != material_name or material.next_pass != null or material.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED:
				return _reject(root)
			var expected: Array = MATERIALS[material_name]
			var color: Color = material.albedo_color
			if absf(color.r-expected[0])>0.000001 or absf(color.g-expected[1])>0.000001 or absf(color.b-expected[2])>0.000001 or color.a != 1.0 or absf(material.roughness-expected[3])>0.000001 or absf(material.metallic-expected[4])>0.000001:
				return _reject(root)
			if materials.has(material_name) and materials[material_name] != material:
				return _reject(root)
			materials[material_name] = material
			for feature in [BaseMaterial3D.FEATURE_EMISSION,BaseMaterial3D.FEATURE_NORMAL_MAPPING,BaseMaterial3D.FEATURE_HEIGHT_MAPPING,BaseMaterial3D.FEATURE_SUBSURFACE_SCATTERING,BaseMaterial3D.FEATURE_REFRACTION,BaseMaterial3D.FEATURE_DETAIL]:
				if material.get_feature(feature):
					return _reject(root)
			var textured: bool = material_name in ["Cloth","Leather","Dark","Black"]
			for channel in range(BaseMaterial3D.TEXTURE_MAX):
				if channel not in [BaseMaterial3D.TEXTURE_ALBEDO,BaseMaterial3D.TEXTURE_ROUGHNESS,BaseMaterial3D.TEXTURE_METALLIC] and material.get_texture(channel)!=null:
					return _reject(root)
			# glTF's shared metallic-roughness image may occupy both Godot slots.
			# Its B=255 leaves the source metallic factor intact; G carries roughness.
			var metallic_texture: Texture2D = material.get_texture(BaseMaterial3D.TEXTURE_METALLIC)
			if metallic_texture!=null and (not textured or metallic_texture!=material.get_texture(BaseMaterial3D.TEXTURE_ROUGHNESS) or material.metallic_texture_channel!=BaseMaterial3D.TEXTURE_CHANNEL_BLUE):
				return _reject(root)
			if textured and material.roughness_texture_channel!=BaseMaterial3D.TEXTURE_CHANNEL_GREEN:
				return _reject(root)
			for channel in [BaseMaterial3D.TEXTURE_ALBEDO,BaseMaterial3D.TEXTURE_ROUGHNESS]:
				var texture: Texture2D = material.get_texture(channel)
				if (texture != null) != textured:
					return _reject(root)
				if texture != null:
					var image := texture.get_image()
					if texture.get_width()!=256 or texture.get_height()!=256 or image==null or not image.has_mipmaps() or image.is_compressed() or image.get_format()!=Image.FORMAT_RGBA8:
						return _reject(root)
					if texture_ids.has(channel) and texture_ids[channel] != texture:
						return _reject(root)
					texture_ids[channel] = texture
			# Fixed presentation resource settings; no new image upload/clone/target.
			material.texture_repeat = true
			material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
			child.material_override = material
	if observed.size()!=74 or materials.size()!=7 or texture_ids.size()!=2 or texture_ids[BaseMaterial3D.TEXTURE_ALBEDO] == texture_ids[BaseMaterial3D.TEXTURE_ROUGHNESS]:
		return _reject(root)
	for name: String in PARTS:
		if not observed.has(name):
			return _reject(root)
	return root
