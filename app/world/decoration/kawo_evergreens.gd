extends "res://simulation/origin_participant.gd"
class_name KawoEvergreens
# Original MIT. Decorative presentation only: no native/physics/storage calls.
const Reader=preload("res://world/terrain/resident_grid_reader.gd")
const Terrain=preload("res://world/terrain/kawo_world.gd")
const FrameOps=preload("res://simulation/canonical_frames.gd")
const PAYLOAD="b2c53308fdc427900d84b541aff51ba66cbb71bc483fcee0ea16d067dbd15cfb"
const GROVES=[[-800,-384,-800,-288],[448,896,-1088,-512],[-1024,-512,64,640],[512,1024,128,768],[-320,-64,480,1056],[448,736,512,1088]]
const ASSETS=[
	{"file":"tall-narrow-lod1.glb","root":"OriginalTallNarrowL1","bytes":70024,"sha256":"35f8cd9714082054e851550281c6996c67159d46b8a2345737a1b63a93e5299d"},
	{"file":"broad-tiered-lod1.glb","root":"OriginalBroadTieredL1","bytes":70060,"sha256":"cc386b8fa59a0e0787430081713d219b9ddfde017fd1fd3c81ed72551db4fdb8"},
	{"file":"irregular-mature-lod1.glb","root":"OriginalIrregularMatureL1","bytes":70060,"sha256":"0e7c33c239b0d3773023e9fd5aec522392f270b06bd6b3591434d27c56378a7e"}]
const PARTS=["Bark","InnerNeedles","OuterNeedles"]
const MATERIALS=["EvergreenBark","EvergreenInner","EvergreenOuter"]
var _source: Dictionary={}
var _placements: Array=[]
var _batches: Array=[]
var _decoration_ready: bool=false

static func _prepare_failure(message: String) -> Dictionary:
	return {"ok":false,"error":message,"root":null}

static func _mask(u: int,v: int) -> bool:
	if u<0 or u>96 or v<0 or v>96: return false
	var x: int=-1536+32*u
	var z: int=-1536+32*v
	for box in GROVES:
		if x>=box[0] and x<=box[1] and z>=box[2] and z<=box[3]: return true
	return false

static func _key(u: int,v: int) -> int:
	return ((u*73856093)^(v*19349663)^0x4b41574f)&0x7fffffff

static func _selection_count(count: int) -> int:
	return 0 if count<96 else mini(192,(count/3)*3)

static func _pavement_box(ring: Array) -> Array:
	var integer_ring: Array=Terrain._millimetre_ring(ring)
	if integer_ring.is_empty(): return []
	var xmin: int=integer_ring[0][0]
	var xmax: int=xmin
	var zmin: int=integer_ring[0][1]
	var zmax: int=zmin
	for point in integer_ring:
		xmin=mini(xmin,point[0]); xmax=maxi(xmax,point[0])
		zmin=mini(zmin,point[1]); zmax=maxi(zmax,point[1])
	return [xmin-112000,xmax+112000,zmin-112000,zmax+112000]

static func _end_box(end: Array,opposite: Array) -> Array:
	if not FrameOps.finite_array(end,2) or not FrameOps.finite_array(opposite,2): return []
	var dx: float=end[0]-opposite[0]
	var dz: float=end[1]-opposite[1]
	var xx: float=dx*dx
	var zz: float=dz*dz
	var length_m: float=sqrt(xx+zz)
	if not is_finite(length_m) or length_m<=0.0: return []
	var ex: float=end[0]+1500.0*(dx/length_m)
	var ez: float=end[1]+1500.0*(dz/length_m)
	if not is_finite(ex) or not is_finite(ez): return []
	return [minf(end[0],ex)-213.0,maxf(end[0],ex)+213.0,minf(end[1],ez)-213.0,maxf(end[1],ez)+213.0]

static func _inside(x: float,z: float,box: Array) -> bool:
	return box.size()==4 and x>=box[0] and x<=box[1] and z>=box[2] and z<=box[3]

static func _exclusions(geometry: Dictionary) -> Dictionary:
	var pavement: Array=[]
	var corridors: Array=[]
	for runway in geometry.runways:
		var ring: Array=_pavement_box(runway.footprint_mm)
		if ring.is_empty(): return {}
		pavement.append(ring)
		var ends: Array=[]
		for item in runway.ends:
			var point: Array=[]
			for index in [0,2]:
				var number: Dictionary=Terrain._tag(item.eus_m[index])
				if not number.ok: return {}
				point.append(number.value)
			ends.append(point)
		for j in 2:
			var box: Array=_end_box(ends[j],ends[1-j])
			if box.is_empty(): return {}
			corridors.append(box)
	return {"pavement":pavement,"corridors":corridors}

static func _excluded(x: float,z: float,exclusions: Dictionary) -> bool:
	for box in exclusions.pavement:
		# Candidate metre coordinates and millimetre boxes are exact integers.
		if _inside(x*1000.0,z*1000.0,box): return true
	for box in exclusions.corridors:
		if _inside(x,z,box): return true
	return false

static func _site(up: PackedByteArray,valid: PackedByteArray,columns: int,rows: int,col: int,row: int) -> Dictionary:
	if columns<7 or rows<7 or up.size()!=columns*rows*4 or valid.size()<(columns*rows+7)/8 or col<3 or row<3 or col>=columns-3 or row>=rows-3: return {}
	var minimum: float=INF
	var maximum: float=-INF
	for r in range(row-3,row+4):
		for c in range(col-3,col+4):
			var index: int=r*columns+c
			if not Reader._valid(valid,index): return {}
			var height: float=Reader._height(up,index)
			if not is_finite(height): return {}
			minimum=minf(minimum,height)
			maximum=maxf(maximum,height)
	if maximum-minimum>2.0: return {}
	var address: int=row*columns+col
	return {"height":Reader._height(up,address),"word":up.decode_u32(address*4)}

static func _ordered(a: Dictionary,b: Dictionary) -> bool:
	if a.key!=b.key: return a.key<b.key
	if a.v!=b.v: return a.v<b.v
	return a.u<b.u

static func _candidates(up: PackedByteArray,valid: PackedByteArray,meta: Dictionary,exclusions: Dictionary) -> Array:
	var result: Array=[]
	for v in 97:
		for u in 97:
			if not _mask(u,v): continue
			var x: int=-1536+32*u
			var z: int=-1536+32*v
			if _excluded(float(x),float(z),exclusions): continue
			var col: int=(x+6144)/4
			var row: int=(z+4096)/4
			var site: Dictionary=_site(up,valid,meta.columns,meta.rows,col,row)
			if site.is_empty(): continue
			result.append({"u":u,"v":v,"key":_key(u,v),"column":col,"row":row,"east_m":x,"south_m":z,"up_word":site.word,"up_m":site.height})
	result.sort_custom(_ordered)
	return result

static func _inspect_asset(instance: Node3D,asset: Dictionary) -> Dictionary:
	if instance.get_class()!="Node3D" or String(instance.name)!=String(asset.file).trim_suffix(".glb") or instance.transform!=Transform3D.IDENTITY or instance.get_script()!=null or instance.get_child_count()!=1: return {"ok":false}
	var authored: Node=instance.get_child(0)
	if not authored is Node3D or authored.get_class()!="Node3D" or String(authored.name)!=asset.root or authored.transform!=Transform3D.IDENTITY or authored.get_script()!=null or authored.get_child_count()!=3: return {"ok":false}
	var meshes: Array=[]
	var triangles: int=0
	var vertices: int=0
	for index in 3:
		var child: Node=authored.get_node_or_null(NodePath(PARTS[index]))
		if not child is MeshInstance3D or child.get_child_count()!=0 or child.transform!=Transform3D.IDENTITY or child.get_script()!=null or child.material_override!=null or child.cast_shadow!=GeometryInstance3D.SHADOW_CASTING_SETTING_ON: return {"ok":false}
		var mesh: ArrayMesh=child.mesh as ArrayMesh
		if mesh==null or mesh.get_surface_count()!=1 or mesh.surface_get_primitive_type(0)!=Mesh.PRIMITIVE_TRIANGLES: return {"ok":false}
		var surface: Dictionary=RenderingServer.mesh_get_surface(mesh.get_rid(),0)
		if surface.has("lods") and (not surface.lods is Array or not surface.lods.is_empty()): return {"ok":false}
		var arrays: Array=mesh.surface_get_arrays(0)
		var positions: PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array=arrays[Mesh.ARRAY_NORMAL]
		var indices: PackedInt32Array=arrays[Mesh.ARRAY_INDEX]
		if positions.is_empty() or positions.size()!=normals.size() or indices.is_empty() or indices.size()%3!=0: return {"ok":false}
		for j in positions.size():
			var point: Vector3=positions[j]
			if not point.is_finite() or absf(point.x)>8.0 or absf(point.z)>8.0 or point.y< -0.00001 or point.y>26.00001 or not normals[j].is_finite(): return {"ok":false}
		for j in indices:
			if j<0 or j>=positions.size(): return {"ok":false}
		var material: StandardMaterial3D=mesh.surface_get_material(0) as StandardMaterial3D
		if material==null or material.resource_name!=MATERIALS[index] or material.transparency!=BaseMaterial3D.TRANSPARENCY_DISABLED or material.cull_mode!=BaseMaterial3D.CULL_BACK or material.metallic!=0.0 or material.emission_enabled: return {"ok":false}
		if material.albedo_texture!=null or material.normal_texture!=null or material.metallic_texture!=null or material.roughness_texture!=null or material.emission_texture!=null: return {"ok":false}
		triangles+=indices.size()/3
		vertices+=positions.size()
		meshes.append(mesh)
	return {"ok":triangles==864 and vertices==2592,"meshes":meshes}

static func _load_assets() -> Dictionary:
	var resources: Array=[]
	for asset in ASSETS:
		var path: String="res://environment/original-evergreens-v1/"+asset.file
		var file: FileAccess=FileAccess.open(path,FileAccess.READ)
		if file==null: return {"ok":false,"error":"Decorative evergreen source unavailable"}
		var bytes: int=file.get_length()
		file.close()
		if bytes!=asset.bytes or FileAccess.get_sha256(path)!=asset.sha256: return {"ok":false,"error":"Decorative evergreen source pin differs"}
		var packed: PackedScene=ResourceLoader.load(path,"PackedScene",ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
		if packed==null: return {"ok":false,"error":"Decorative evergreen import unavailable"}
		var instance: Node=packed.instantiate()
		if not instance is Node3D:
			if instance!=null: instance.free()
			return {"ok":false,"error":"Unexpected decorative evergreen import root"}
		var inspected: Dictionary=_inspect_asset(instance,asset)
		instance.free()
		if not inspected.ok: return {"ok":false,"error":"Unexpected decorative evergreen imported geometry"}
		resources.append(inspected.meshes)
	return {"ok":true,"error":"","meshes":resources}

static func prepare(grid: Variant,geometry: Variant,session_id: Variant,anchor_ecef: Variant,rotation: Variant) -> Dictionary:
	if not Thread.is_main_thread() or not Reader._environment() or not grid is Reader.DecodedGrid or not grid._admitted or typeof(session_id)!=TYPE_STRING or not Terrain._scalars(anchor_ecef,3) or not Terrain._scalars(rotation,9) or not FrameOps.rigid(rotation): return _prepare_failure("Invalid decorative evergreen preparation")
	var meta: Dictionary=grid.metadata()
	if meta.payload_sha256!=PAYLOAD or meta.columns!=3073 or meta.rows!=2049 or meta.spacing_m!=4 or meta.east_origin_m!= -6144.0 or meta.south_origin_m!= -4096.0: return _prepare_failure("Decorative evergreens require the fixed KAWO surface")
	var frame: Dictionary=FrameOps.anchor(meta.world_anchor.latitude_rad,meta.world_anchor.longitude_rad,meta.world_anchor.ellipsoid_height_m)
	if frame.is_empty() or not Terrain._same(frame.ecef,anchor_ecef) or not Terrain._same(frame.rotation,rotation) or not Terrain._geometry_valid(geometry,meta,grid.copy_polygons()): return _prepare_failure("Decorative evergreen source/frame differs")
	var exclusions: Dictionary=_exclusions(geometry)
	if exclusions.is_empty(): return _prepare_failure("Decorative evergreen exclusions unavailable")
	var up: PackedByteArray=grid.copy_up_words()
	var valid: PackedByteArray=grid.copy_valid_words()
	var candidates: Array=_candidates(up,valid,meta,exclusions)
	var selected: int=_selection_count(candidates.size())
	if selected==0: return _prepare_failure("Insufficient admitted decorative grove sites")
	var imported: Dictionary=_load_assets()
	if not imported.ok: return _prepare_failure(imported.error)
	var root:=KawoEvergreens.new()
	root.name="KawoDecorativeEvergreens"
	root.visible=false
	root._source={"session_id":"","payload_sha256":PAYLOAD,"world_anchor":meta.world_anchor.duplicate(true),"anchor_ecef_m":anchor_ecef.duplicate(true),"ecef_to_eus":rotation.duplicate(true)}
	var transforms: Array=[[],[],[]]
	for index in selected:
		var candidate: Dictionary=candidates[index].duplicate(true)
		var design: int=index%3
		var yaw_index: int=candidate.key&15
		var yaw: float=float(yaw_index)*(PI/8.0)
		var placement:=Transform3D(Basis(Vector3.UP,yaw),Vector3(float(candidate.east_m),candidate.up_m,float(candidate.south_m)))
		transforms[design].append(placement)
		candidate["design"]=design
		candidate["yaw_index"]=yaw_index
		root._placements.append(candidate)
	for design in 3:
		for part in 3:
			var mesh: ArrayMesh=imported.meshes[design][part]
			var multimesh:=MultiMesh.new()
			multimesh.transform_format=MultiMesh.TRANSFORM_3D
			multimesh.use_colors=false
			multimesh.use_custom_data=false
			multimesh.mesh=mesh
			multimesh.instance_count=transforms[design].size()
			var bounds:=AABB()
			for index in transforms[design].size():
				var placement: Transform3D=transforms[design][index]
				multimesh.set_instance_transform(index,placement)
				var box: AABB=placement*mesh.get_aabb()
				bounds=box if index==0 else bounds.merge(box)
			# Original visual culling guard, much larger than model-space roundoff.
			multimesh.custom_aabb=bounds.grow(1.0)
			var batch:=MultiMeshInstance3D.new()
			batch.name="Evergreens_%d_%s"%[design,PARTS[part]]
			batch.multimesh=multimesh
			batch.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_ON
			root.add_child(batch)
			root._batches.append(batch)
	root._decoration_ready=true
	if not session_id.is_empty() and not root.bind_session(session_id).ok:
		root.free()
		return _prepare_failure("Decorative evergreen session binding failed")
	return {"ok":true,"error":"","root":root}

func bind_session(value: Variant) -> Dictionary:
	if not Thread.is_main_thread() or not _decoration_ready or typeof(value)!=TYPE_STRING or value.is_empty() or not _source.session_id.is_empty() or get_parent()!=null or is_inside_tree() or is_queued_for_deletion(): return {"ok":false,"error":"Invalid or repeated decorative session binding"}
	if not configure(value,_source.anchor_ecef_m,_source.ecef_to_eus,[0.0,0.0,0.0],Basis.IDENTITY): return {"ok":false,"error":"Decorative origin binding failed"}
	_source.session_id=value
	return {"ok":true,"error":""}

func source_binding() -> Dictionary:
	return _source.duplicate(true)

func placement_observation() -> Dictionary:
	return {"scope":"Original decorative vegetation; not surveyed obstacles or native authority","payload_sha256":PAYLOAD,"count":_placements.size(),"batch_count":_batches.size(),"placements":_placements.duplicate(true),"assets":ASSETS.duplicate(true)}
