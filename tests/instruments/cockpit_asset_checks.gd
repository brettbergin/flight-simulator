extends RefCounted
# Original MIT. Real imported resource against pre-output original arrays.
# Does not open a native session, change Scene authority, or advance simulation.
const Fixture = preload("res://instrument_tests/cockpit_asset_baseline.gd")
const Adapter = preload("res://cockpit/assets/original_asset.gd")
const Cockpit = preload("res://interactive/flight_cockpit.gd")
const EPS: float = 0.000001
var failures: Array[String] = []
var checks: int = 0
var host: Node

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures.append(label)
	if host != null:
		host.check(value, label)

func v3(a: Array) -> Vector3:
	return Vector3(a[0],a[1],a[2])

func basis_matches(actual: Basis, expected: Basis) -> bool:
	for column in range(3):
		for row in range(3):
			var a: float = actual[column][row]
			var e: float = expected[column][row]
			if not is_finite(a) or not is_finite(e) or absf(a-e)>EPS:
				return false
	return true

func part_frame_valid(node: MeshInstance3D) -> bool:
	if basis_matches(node.basis,Basis.IDENTITY) and node.position.is_finite() and maxf(absf(node.position.x),maxf(absf(node.position.y),absf(node.position.z)))<=EPS:
		return true
	if str(node.name) not in ["LeftSeatBack","RightSeatBack"]:
		return false
	# Frozen original reference center/rotation[-8,0,0], never fitted to export.
	var center:=Vector3(-0.29 if str(node.name)=="LeftSeatBack" else 0.29,0.08,0.06)
	var delta: Vector3=node.position-center
	return delta.is_finite() and maxf(absf(delta.x),maxf(absf(delta.y),absf(delta.z)))<=EPS and basis_matches(node.basis,Basis(Vector3.RIGHT,deg_to_rad(-8.0)))

func cell(points: Array) -> Vector3i:
	var c: Vector3 = (points[0][0]+points[1][0]+points[2][0])/3.0
	return Vector3i(floori(c.x/EPS),floori(c.y/EPS),floori(c.z/EPS))

func triangle_matches(actual: Array, expected: Array) -> bool:
	for shift in range(3):
		var fits: bool = true
		for i in range(3):
			var a: Array = actual[i]
			var e: Array = expected[(i+shift)%3]
			var delta: Vector3 = a[0]-e[0]
			var tex: Vector2 = a[2]-e[2]
			fits = fits and maxf(absf(delta.x),maxf(absf(delta.y),absf(delta.z)))<=EPS and a[1].dot(e[1])>=0.99999 and maxf(absf(tex.x),absf(tex.y))<=EPS
		if fits:
			return true
	return false

func derived_tangents_valid(value: Variant, normals: PackedVector3Array) -> bool:
	# Independent scalar check; never delegates representation admission to Adapter.
	if not value is PackedFloat32Array:
		return false
	if value.is_empty():
		return false
	if value.size() != normals.size()*4:
		return false
	for offset in range(0,value.size(),4):
		var x: float=value[offset]
		var y: float=value[offset+1]
		var z: float=value[offset+2]
		var w: float=value[offset+3]
		for component: float in [x,y,z,w]:
			if not is_finite(component) or component < -1.0 or component > 1.0:
				return false
		if w != -1.0 and w != 1.0:
			return false
		var normal: Vector3=normals[int(offset/4)]
		if not normal.is_finite() or absf(x*x+y*y+z*z-1.0)>0.00001 or absf(x*normal.x+y*normal.y+z*normal.z)>0.00025:
			return false
	return true

func geometry(node: MeshInstance3D, expected: Dictionary) -> bool:
	if not node.mesh is ArrayMesh or node.mesh.get_surface_count()!=1 or node.mesh.surface_get_primitive_type(0)!=Mesh.PRIMITIVE_TRIANGLES:
		return false
	var arrays: Array = node.mesh.surface_get_arrays(0)
	if arrays.size()!=Mesh.ARRAY_MAX:
		return false
	for channel in range(Mesh.ARRAY_MAX):
		if channel not in [Mesh.ARRAY_VERTEX,Mesh.ARRAY_NORMAL,Mesh.ARRAY_TANGENT,Mesh.ARRAY_TEX_UV,Mesh.ARRAY_INDEX] and arrays[channel]!=null and arrays[channel].size()!=0:
			return false
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var uv: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	if not derived_tangents_valid(arrays[Mesh.ARRAY_TANGENT],normals):
		return false
	if vertices.size()!=normals.size() or vertices.size()!=uv.size() or indices.size()!=expected.indices_cw.size():
		return false
	var buckets: Dictionary = {}
	for i in range(0,expected.indices_cw.size(),3):
		var triangle: Array = []
		for j in range(3):
			var index: int = int(expected.indices_cw[i+j])
			triangle.append([v3(expected.vertices_parent_m[index]),v3(expected.normals_parent[index]),Vector2(expected.uv0[index][0],expected.uv0[index][1])])
		var key: Vector3i = cell(triangle)
		if not buckets.has(key):
			buckets[key]=[]
		buckets[key].append(triangle)
	for i in range(0,indices.size(),3):
		var actual: Array = []
		for j in range(3):
			var index: int = indices[i+j]
			if index<0 or index>=vertices.size() or not vertices[index].is_finite() or not normals[index].is_finite() or not uv[index].is_finite() or absf(normals[index].length_squared()-1.0)>0.00001:
				return false
			actual.append([node.transform*vertices[index],(node.basis.inverse().transposed()*normals[index]).normalized(),Vector2(uv[index].x,1.0-uv[index].y)])
		var origin: Vector3i = cell(actual)
		var found: bool = false
		for x in range(-1,2):
			if found:break
			for y in range(-1,2):
				if found:break
				for z in range(-1,2):
					if found:break
					var key: Vector3i = origin+Vector3i(x,y,z)
					if not buckets.has(key):continue
					for candidate in range(buckets[key].size()):
						if triangle_matches(actual,buckets[key][candidate]):
							buckets[key].remove_at(candidate)
							found=true
							break
		if not found:return false
	for remaining: Array in buckets.values():
		if not remaining.is_empty():return false
	return true

func tree_valid(root: Node3D, baseline: Dictionary) -> bool:
	if root==null or root.get_script()!=null or root.name!="OriginalCockpitAsset" or root.transform!=Transform3D.IDENTITY or root.get_child_count()!=9:
		return false
	var wanted: Dictionary = {"Static":Vector3.ZERO}
	for marker: Dictionary in baseline.markers:
		wanted[marker.name]=v3(marker.translation_m)
	var seen: Dictionary = {}
	for child in root.get_children():
		if child.get_class()!="Node3D" or child.get_script()!=null or not wanted.has(str(child.name)) or seen.has(str(child.name)):
			return false
		seen[str(child.name)]=true
		if child.basis!=Basis.IDENTITY or child.position.distance_to(wanted[str(child.name)])>EPS:
			return false
	var parts: Dictionary = {}
	for expected: Dictionary in baseline.parts:
		parts[expected.name]=expected
	var observed: Dictionary = {}
	for group in root.get_children():
		for child in group.get_children():
			var name: String = str(child.name)
			if child.get_class()!="MeshInstance3D" or child.get_script()!=null or child.get_child_count()!=0 or not parts.has(name) or observed.has(name) or parts[name].parent!=str(group.name):
				return false
			if not part_frame_valid(child):return false
			observed[name]=true
	return observed.size()==74 and seen.size()==9

func aperture_clear(imported: Node3D, baseline: Dictionary, ray: Dictionary) -> bool:
	var eye: Vector3=v3(ray.origin_m)
	var direction: Vector3=v3(ray.direction)
	for part: Dictionary in baseline.parts:
		var node: MeshInstance3D=imported.get_node(str(part.parent)+"/"+str(part.name))
		var arrays: Array=node.mesh.surface_get_arrays(0)
		var vertices: PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
		var indices: PackedInt32Array=arrays[Mesh.ARRAY_INDEX]
		var composed: Transform3D=node.get_parent().transform*node.transform
		for i in range(0,indices.size(),3):
			var hit=Geometry3D.ray_intersects_triangle(eye,direction,composed*vertices[indices[i]],composed*vertices[indices[i+1]],composed*vertices[indices[i+2]])
			if hit!=null and eye.distance_to(hit)<=ray.distance_m:return false
	return true

func run(owner: Node) -> Dictionary:
	host=owner
	var baseline: Dictionary = Fixture.data()
	var imported: Node3D = Adapter.instantiate()
	check(imported!=null,"asset_actual_fixed_resource_admitted")
	if imported==null:return {"checks":checks,"failures":failures,"passed":false}
	check(tree_valid(imported,baseline),"asset_closed84_tree_exact_rest_eye_pivots")
	var material_ids: Dictionary = {}
	var textures: Dictionary = {}
	var decoded_array_bytes: int = 0
	for part: Dictionary in baseline.parts:
		var node: MeshInstance3D = imported.get_node_or_null(str(part.parent)+"/"+str(part.name))
		check(node!=null,"asset_part_"+str(part.name))
		if node==null:continue
		var geometry_ok: bool=geometry(node,part)
		check(geometry_ok,"asset_complete_oriented_geometry_normals_uv_"+str(part.name))
		if geometry_ok:
			var arrays: Array=node.mesh.surface_get_arrays(0)
			decoded_array_bytes += arrays[Mesh.ARRAY_VERTEX].size()*12+arrays[Mesh.ARRAY_NORMAL].size()*12+arrays[Mesh.ARRAY_TEX_UV].size()*8+arrays[Mesh.ARRAY_INDEX].size()*4
			decoded_array_bytes += 0 if arrays[Mesh.ARRAY_TANGENT]==null else arrays[Mesh.ARRAY_TANGENT].size()*4
		var material: StandardMaterial3D = node.material_override
		check(material!=null and material==node.mesh.surface_get_material(0),"asset_shared_surface_override_"+str(part.name))
		if material==null:continue
		if material_ids.has(part.material):
			check(material_ids[part.material]==material.get_instance_id(),"asset_material_sharing_"+str(part.name))
		material_ids[part.material]=material.get_instance_id()
		for expected: Dictionary in baseline.materials:
			if expected.name!=part.material:continue
			var c: Color=material.albedo_color
			check(absf(c.r-expected.original_godot_albedo_rgb[0])<=EPS and absf(c.g-expected.original_godot_albedo_rgb[1])<=EPS and absf(c.b-expected.original_godot_albedo_rgb[2])<=EPS and c.a==1.0 and absf(material.roughness-expected.roughness)<=EPS and absf(material.metallic-expected.metallic)<=EPS,"asset_actual_imported_source_material_"+str(part.name))
		var textured: bool = part.material in ["Cloth","Leather","Dark","Black"]
		for channel in [BaseMaterial3D.TEXTURE_ALBEDO,BaseMaterial3D.TEXTURE_ROUGHNESS]:
			var texture: Texture2D=material.get_texture(channel)
			check((texture!=null)==textured,"asset_texture_subset_"+str(part.name)+"_"+str(channel))
			if texture==null:continue
			var image: Image=texture.get_image()
			check(image!=null and image.get_width()==256 and image.get_height()==256 and image.get_format()==Image.FORMAT_RGBA8 and not image.is_compressed() and image.has_mipmaps(),"asset_actual_uncompressed_rgba8_full_mips_"+str(part.name))
			if image!=null:
				check(image.get_data().size()==349524,"asset_observed_full_mip_texel_bytes_"+str(part.name))
			if textures.has(channel):check(textures[channel]==texture.get_instance_id(),"asset_texture_sharing_"+str(part.name))
			textures[channel]=texture.get_instance_id()
		check(material.texture_repeat and material.texture_filter==BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS,"asset_repeat_linear_mip_sampling_"+str(part.name))
	check(decoded_array_bytes>0 and decoded_array_bytes<=8*1024*1024,"asset_complete_imported_array_budget_including_derived_tangents")
	check(material_ids.size()==7 and textures.size()==2,"asset_seven_shared_materials_two_shared_images")
	for ray: Dictionary in baseline.aperture_rays:
		check(aperture_clear(imported,baseline,ray),"asset_unchanged_open_sight_ray_"+str(ray.name))
	# Negatives operate only on this isolated imported tree and restore it immediately.
	imported.scale=Vector3.ONE*100.0
	check(not tree_valid(imported,baseline),"asset_negative_unit100")
	imported.scale=Vector3.ONE
	var eye: Node3D=imported.get_node("PilotEye")
	var saved_eye: Vector3=eye.position
	eye.position.x+=0.01
	check(not tree_valid(imported,baseline),"asset_negative_changed_eye")
	eye.position=saved_eye
	var extra:=Node3D.new()
	imported.add_child(extra)
	check(not tree_valid(imported,baseline),"asset_negative_extra_node")
	imported.remove_child(extra);extra.free()
	imported.free()
	# Real runtime builder keeps the live panel and copied control API; no flight created.
	var parent:=Node3D.new()
	owner.add_child(parent)
	var builder=Cockpit.new()
	var result: Dictionary=builder.build(parent,null)
	check(result.size()==3 and result.has("root") and result.has("eye") and result.has("panel_focus"),"asset_builder_success_api")
	if not result.has("root"):
		parent.free();return {"checks":checks,"failures":failures,"passed":false}
	check(result.eye==Vector3(-0.27,0.67,-0.92) and result.panel_focus==Vector3(-0.08,0.255,-1.535),"asset_original_eye_focus_authority")
	var panel: MeshInstance3D=result.root.get_node_or_null("LiveReadonlyPanelSurface")
	check(panel!=null and panel.mesh is QuadMesh and panel.mesh.size==Vector2(1.115,0.5575) and panel.position==Vector3(0,0.255,-1.535),"asset_retained_live_panel_size_pose")
	if panel!=null:
		check(panel.material_override.shading_mode==BaseMaterial3D.SHADING_MODE_UNSHADED and panel.cast_shadow==GeometryInstance3D.SHADOW_CASTING_SETTING_OFF,"asset_retained_unlit_shadowfree_panel")
	for fixture: Dictionary in baseline.control_cases:
		var held: Dictionary=fixture.held.duplicate(true)
		var before: Dictionary=held.duplicate(true)
		builder.update_controls(held)
		check(held==before,"asset_unchanged_caller_dictionary_"+str(fixture.name))
		var nodes: Dictionary={"CopiedPilotYoke":builder.yoke,"CopiedLeftPedal":builder.pedals[0],"CopiedRightPedal":builder.pedals[1],"CopiedThrottleHandle":builder.throttle_handle,"CopiedTrimWheel":builder.trim_wheel}
		for name: String in fixture.expected:
			var expected: Dictionary=fixture.expected[name]
			var node: Node3D=nodes[name]
			check(node.name==name and node.position.distance_to(v3(expected.position))<=EPS and basis_matches(node.basis,Basis.from_euler(v3(expected.rotation))),"asset_control_endpoint_mixed_basis_"+str(fixture.name)+"_"+name)
	parent.free()
	return {"schema":"OriginalCockpitActualImportChecks/v1","checks":checks,"failures":failures,"passed":failures.is_empty(),"baseline_sha256":Fixture.BASELINE_SHA256,"scope":"Actual isolated imported geometry/material/control checks only; native authority, pixels and delivery remain separate."}
