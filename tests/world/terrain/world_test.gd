extends SceneTree
# Actual-source component evidence only. No facade/native/profile/history exists
# in this isolated runner; it cannot claim their authority/lifecycle acceptance.
const Reader=preload("res://world/terrain/resident_grid_reader.gd")
const World=preload("res://world/terrain/kawo_world.gd")
const Frames=preload("res://simulation/canonical_frames.gd")
const Origin=preload("res://simulation/render_origin.gd")
const U64=preload("res://simulation/uint64.gd")
const ReaderChecks=preload("res://terrain_tests/reader_checks.gd")
var checks: int=0
var failures: Array=[]
var cached_vertices: Array=[]
var source_up: PackedByteArray
var terrain: Node3D
var anchor: Array=[]
var rotation: Array=[]
var committed: int=0
var previous_recovered: Dictionary={}
const SESSION="render-hand-reference-v1"

func check(good: bool,name: String) -> void:
	checks+=1
	if not good and failures.size()<32: failures.append(name)

func _initialize() -> void:
	call_deferred("_run")

func _bytes(path: String,limit: int) -> PackedByteArray:
	var file:=FileAccess.open(path,FileAccess.READ)
	if file==null or file.get_length()>limit: return PackedByteArray()
	return file.get_buffer(file.get_length())

# Independent Dekker product + error-free TwoSum expansion. All operands in this
# frozen workload are bounded normals (or zero), so splitting cannot overflow or
# underflow. The final ascending expansion sum has error far below2^-20m here;
# no consumer/Frames projection supplies the expected answer.
func _grow(existing: Array,value: float) -> Array:
	var out: Array=[]
	var q: float=value
	for e in existing:
		var sum: float=q+e
		var bv: float=sum-q
		var error: float=(q-(sum-bv))+(e-bv)
		if error!=0.0: out.append(error)
		q=sum
	out.append(q)
	return out

func _product(a: float,b: float) -> Array:
	var product: float=a*b
	var ca: float=134217729.0*a
	var cb: float=134217729.0*b
	var ah: float=ca-(ca-a)
	var bh: float=cb-(cb-b)
	var al: float=a-ah
	var bl: float=b-bh
	var error: float=((ah*bh-product)+ah*bl+al*bh)+al*bl
	return [error,product]

func _reference_offset(origin: Array) -> Array:
	var answer: Array=[]
	for row in 3:
		var expansion: Array=[]
		for axis in 3:
			var difference: Array=_grow([anchor[axis]],-origin[axis])
			for term in difference:
				for part in _product(term,rotation[row*3+axis]):
					expansion=_grow(expansion,part)
		var total: float=0.0
		for term in expansion: total+=term
		answer.append(total)
	return answer

func _origin(d: Array) -> Array:
	var out: Array=[]
	for axis in 3:
		var p0: float=rotation[axis]*d[0]
		var p1: float=rotation[3+axis]*d[1]
		var s01: float=p0+p1
		var p2: float=rotation[6+axis]*d[2]
		var delta: float=s01+p2
		out.append(anchor[axis]-delta)
	return out

func _word(value: float) -> int:
	var bytes:=PackedByteArray()
	bytes.resize(4)
	bytes.encode_float(0,value)
	return bytes.decode_u32(0)

func _audit(first: bool) -> void:
	check(terrain.get_child_count()==1536,"all1536 chunks")
	if first: cached_vertices.clear()
	var seen_vertices: int=0
	var seen_indices: int=0
	var word:=PackedByteArray()
	word.resize(4)
	for chunk_row in 32:
		for chunk_col in 48:
			var chunk: MeshInstance3D=terrain.get_child(chunk_row*48+chunk_col)
			check(chunk.transform==Transform3D.IDENTITY and chunk.mesh.get_surface_count()==1,"identity chunk and one surface")
			var arrays: Array=chunk.mesh.surface_get_arrays(0)
			var vertices: PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
			var indices: PackedInt32Array=arrays[Mesh.ARRAY_INDEX]
			check(vertices.size()==4225 and indices.size()==24576,"fixed chunk cardinality")
			var valid: bool=true
			for row in 65:
				for col in 65:
					var r: int=chunk_row*64+row
					var c: int=chunk_col*64+col
					var p: Vector3=vertices[row*65+col]
					word.encode_float(0,p.y)
					if p.x!=float(-6144+4*c) or p.z!=float(-4096+4*r) or word.decode_u32(0)!=source_up.decode_u32(4*(r*3073+c)): valid=false
					seen_vertices+=1
			var cursor: int=0
			for row in 64:
				for col in 64:
					var base: int=65*row+col
					for expected in [base,base+65,base+66,base,base+66,base+1]:
						if indices[cursor]!=expected: valid=false
						cursor+=1
						seen_indices+=1
			check(valid,"every actual mesh word and fixed facet index")
			if first: cached_vertices.append(vertices)
			else: check(vertices==cached_vertices[chunk_row*48+chunk_col],"mesh arrays unchanged after transactions")
	check(seen_vertices==6489600 and seen_indices==37748736,"independent full-grid entry totals")

func _copies(row: int,col: int) -> Array:
	var rows: Array=[mini(row/64,31)]
	var cols: Array=[mini(col/64,47)]
	if row>0 and row<2048 and row%64==0: rows.append(row/64-1)
	if col>0 and col<3072 and col%64==0: cols.append(col/64-1)
	var out: Array=[]
	for cr in rows:
		for cc in cols:
			out.append(cached_vertices[cr*48+cc][(row-cr*64)*65+col-cc*64])
	return out

func _sample_model_space(i: int) -> void:
	var actual_offset: Array=terrain._offset.duplicate()
	var addresses: Array=[]
	for row in [0,64,128,1024,2048]:
		for col in [0,64,128,1536,3072]: addresses.append([row,col])
	addresses.append([(37*i)%2049,(101*i)%3073])
	for address in addresses:
		var copies: Array=_copies(address[0],address[1])
		var first: Variant=null
		for canonical in copies:
			var rendered: Vector3=terrain.global_transform*canonical
			if first!=null: check(rendered==first,"CPU duplicate positions equal")
			first=rendered
			var exact: Array=[float(canonical.x)+actual_offset[0],float(canonical.y)+actual_offset[1],float(canonical.z)+actual_offset[2]]
			var square: float=0.0
			var recovered: Array=[]
			for axis in 3:
				var error: float=float(rendered[axis])-exact[axis]
				check(absf(error)<=1.0/256.0,"actual CPU model component budget")
				square+=error*error
				recovered.append(float(rendered[axis])-actual_offset[axis])
			check(square<=1.0/16384.0,"actual CPU model Euclidean budget")
			var key: String=str(address[0])+","+str(address[1])
			if previous_recovered.has(key):
				var pair_square: float=0.0
				for axis in 3:
					var difference: float=recovered[axis]-previous_recovered[key][axis]
					check(absf(difference)<=1.0/128.0,"pair-rebase recovered component budget")
					pair_square+=difference*difference
				check(pair_square<=1.0/4096.0,"pair-rebase recovered Euclidean budget")
			previous_recovered[key]=recovered

func _primitive_controls() -> void:
	for row in [[8192.0+pow(2.0,-11),0x46000000],[-8192.0-pow(2.0,-11),0xc6000000],[8192.0+3.0*pow(2.0,-11),0x46000002],[16384.0-pow(2.0,-11),0x46800000]]:
		check(_word(Vector3(row[0],0,0).x)==row[1],"independent translation RN-even word")
	var p: float=4096.0-pow(2.0,-11)
	var o:=Vector3(8192.0+3.0*pow(2.0,-11),0,0)
	var value: Vector3=Transform3D(Basis.IDENTITY,o)*Vector3(p,0,0)
	check(_word(value.x)==0x46400002,"two separately rounded f32 stages discriminator")
	# Pure canonical-facet witness; no geodetic or admitted-grid claim.
	var tiny_bytes:=PackedByteArray()
	tiny_bytes.resize(8)
	tiny_bytes.encode_u64(0,1)
	var tiny: float=tiny_bytes.decode_double(0)
	check(World._sign([2.0,-2.0])==0 and World._sign([2.0,-2.0,tiny])>0,"exact expansion diagonal includes minsub")
	for sample in [[1.0,3.0,1.0,true],[3.0,1.0,1.0,false],[2.0,2.0,2.0,true],[2.0-pow(2.0,-24),2.0,2.0-pow(2.0,-24),true],[2.0+pow(2.0,-24),2.0,2.0,false]]:
		check(World._facet_height(0.0,0.0,0.0,4.0,sample[0],sample[1],sample[3])==sample[2],"frozen saddle actual triangle, never bilinear")
	var isolated:=World.new()
	check(isolated._cell(4.0,tiny,0.0,3)==0,"exact translated point below internal edge")
	check(isolated._cell(4.0,-tiny,0.0,3)==1,"exact translated point above internal edge")
	check(isolated._cell(8.0,0.0,0.0,3)== -1 and isolated._cell(0.0,0.0,0.0,3)==0,"half-open camera outer bounds")
	check(isolated._cell(8.0,tiny,0.0,3)==1,"exact point just inside outer max")
	isolated.free()
	# Isolated mesh embedding controls from the frozen render reference. These
	# extreme neighboring words are not represented as a physically admitted grid.
	var raw:=PackedByteArray()
	raw.resize(4225*4)
	var expected_words: Array=[0xc47a0000,0x00000000,0x80000000,0x3f800001,0xbf800001,0x457fffff,0x45800000]
	for i in expected_words.size(): raw.encode_u32(i*4,expected_words[i])
	var arrays: Array=World._chunk_arrays(raw.to_float32_array(),{"columns":65,"rows":65,"spacing_m":4,"east_origin_m":-6144.0,"south_origin_m":-4096.0},0,0,World._indices())
	var mesh:=ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays,[],{},0)
	check(mesh.get_surface_count()==1,"isolated actual ArrayMesh control")
	if mesh.get_surface_count()==1:
		var observed: PackedVector3Array=mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		for i in expected_words.size(): check(_word(observed[i].y)==expected_words[i],"mesh original canonical height word")
		check(observed[0].x== -6144.0 and observed[0].z== -4096.0 and observed[4224].x== -5888.0 and observed[4224].z== -3840.0,"isolated canonical corner addresses")

func _serialized_geometry_controls() -> void:
	# Literal accepted receipt footprint, independently transcribed numbers. The
	# parser representation is observed, not assumed to preserve integer type.
	var parsed: Variant=JSON.parse_string('{"footprint_mm":[[-719239,-112253],[-733057,-94042],[116281,550408],[130099,532197]]}')
	var expected: Array=[[-719239,-112253],[-733057,-94042],[116281,550408],[130099,532197]]
	var ring: Array=World._millimetre_ring(parsed.footprint_mm)
	check(ring==expected,"serialized receipt integer tokens retain exact millimetres")
	for point in ring:
		check(typeof(point[0])==TYPE_INT and typeof(point[1])==TYPE_INT,"owned ring coordinates normalized to integer representation")
	for bad in [0.5,true,"1",NAN,INF,8192001.0]:
		var crossed: Array=expected.duplicate(true)
		crossed[0][0]=bad
		check(World._millimetre_ring(crossed).is_empty(),"fraction/type/nonfinite/range footprint refused")
	var boundary: Array=[[-8192000.0,-8192000.0],[-8192000.0,8192000.0],[8192000.0,8192000.0],[8192000.0,-8192000.0]]
	check(World._millimetre_ring(boundary)==[[-8192000,-8192000],[-8192000,8192000],[8192000,8192000],[8192000,-8192000]],"exact inclusive millimetre bounds")

func _run() -> void:
	_serialized_geometry_controls()
	var args: PackedStringArray=OS.get_cmdline_user_args()
	if args.size()!=2:
		printerr("world_test requires absolute fixed payload and compile-receipt paths")
		quit(1)
		return
	var payload: PackedByteArray=_bytes(args[0],276946836)
	var receipt: PackedByteArray=_bytes(args[1],4194304)
	check(Reader._hash(payload)=="b2c53308fdc427900d84b541aff51ba66cbb71bc483fcee0ea16d067dbd15cfb","actual fixed payload identity")
	check(Reader._hash(receipt)=="cb1e0b28384aeb1c11173d991b5790a8a16e64953c2c479be6b07136c5f489f0","actual fixed receipt identity")
	if not failures.is_empty(): _finish(); return
	var document: Variant=JSON.parse_string(receipt.get_string_from_utf8())
	var decoded: Dictionary=Reader.decode(payload,ReaderChecks.new().entry(payload))
	check(decoded.ok,"actual complete reader")
	if not decoded.ok: _finish(); return
	var grid: RefCounted=decoded.grid
	var meta: Dictionary=grid.metadata()
	source_up=grid.copy_up_words()
	var frame: Dictionary=Frames.anchor(meta.world_anchor.latitude_rad,meta.world_anchor.longitude_rad,meta.world_anchor.ellipsoid_height_m)
	anchor=frame.ecef
	rotation=frame.rotation
	check(World._geometry_valid(document.airport_geometry,meta,grid.copy_polygons()),"actual serialized geometry matches exact decoded polygons")
	var prepared: Dictionary=World.prepare(grid,document.airport_geometry,"",anchor,rotation)
	check(prepared.ok,"complete unbound world preparation")
	if not prepared.ok: _finish(); return
	terrain=prepared.root
	check(terrain.get_parent()==null and terrain.source_binding().session_id=="","provisional root unattached and unbound")
	check(not terrain.bind_session(42).ok and not terrain.camera_height(0.0,0.0).ok,"wrong-type binding/unbound camera refuse")
	check(terrain.bind_session(SESSION).ok and not terrain.bind_session(SESSION).ok,"bind exactly once")
	get_root().add_child(terrain)
	await process_frame
	var registry:=Origin.new(SESSION,anchor,rotation)
	check(registry.register_participant("world",terrain,["world"]).ok,"actual world protocol registration")
	check(registry.register_participant("absent",null,["ownship","cockpit","camera","light","spatial_audio","local_particles"]).ok,"explicit component-only absent categories")
	_primitive_controls()
	check(registry.rebase(anchor.duplicate()).ok,"first actual anchor adoption")
	# Separate initial adoption from the frozen10000-attempt schedule/version.
	registry.unregister_participant("world")
	terrain.free()
	prepared=World.prepare(grid,document.airport_geometry,SESSION,anchor,rotation)
	check(prepared.ok,"fresh world for frozen sequence")
	if not prepared.ok: _finish(); return
	terrain=prepared.root
	get_root().add_child(terrain)
	await process_frame
	registry=Origin.new(SESSION,anchor,rotation)
	check(registry.register_participant("world",terrain,["world"]).ok and registry.register_participant("absent",null,["ownship","cockpit","camera","light","spatial_audio","local_particles"]).ok,"fresh complete component registry")
	_audit(true)
	for i in 10000:
		var k: int=i%16
		var before: Transform3D=terrain.transform
		var state: Dictionary=registry.read_origin()
		var ux: int=(73*i+19)%2049-1024
		var uy: int=(151*i+7)%1025-512
		var uz: int=(199*i+31)%2047-1023
		var d: Array=[float(8*(ux if ux!=0 else 1)),float(4*(uy if uy!=0 else 1)),float(8*(uz if uz!=0 else 1))]
		var origin: Array=anchor.duplicate() if k==0 or k==15 else _origin(d)
		if k==12:
			origin[0]=NAN
			check(not registry.rebase(origin).ok,"nonfinite registry refusal")
		elif k==13:
			check(not registry.rebase(_origin([20000.0,0.0,0.0])).ok,"guard prepare refusal")
		elif k==14:
			var next: String=U64.increment(str(committed)).value
			var plan: Dictionary=terrain.prepare_origin({"session_id":SESSION,"version":next,"origin_ecef_m":origin,"ecef_to_eus":rotation})
			check(plan.ok and terrain.transform==before,"direct prepare leaves scene unchanged")
			plan.version=str(committed)
			check(not terrain.commit_origin(plan).ok,"mutated stale direct plan refused")
		else:
			var expected: Array=_reference_offset(origin)
			check(registry.rebase(origin).ok,"scheduled complete registry rebase")
			committed+=1
			for axis in 3: check(absf(terrain._offset[axis]-expected[axis])<=pow(2.0,-20),"independent fixed-frame projection budget")
			_sample_model_space(i)
			if k==0 or k==15: check(terrain.position==Vector3.ZERO,"exact anchor return without drift")
		if k>=12 and k<=14:
			check(terrain.transform==before and registry.read_origin().committed==state.committed,"refused transaction preserves committed state")
		if not failures.is_empty(): break
	check(committed==8125 and registry.read_origin().committed.version=="8125","frozen10000 sequence committed count")
	check(terrain.camera_height(0.0,0.0).ok and not terrain.camera_height(6144.0,0.0).ok and not terrain.camera_height(0,0.0).ok,"camera interior/outermax/strict Variant")
	check(terrain.camera_height(0.0,0.0).height_m==float(source_up.decode_float(4*(1024*3073+1536))),"camera at actual original source vertex")
	var binding: Dictionary=terrain.source_binding()
	binding.anchor_ecef_m[0]=0.0
	check(terrain.source_binding().anchor_ecef_m==anchor,"source binding deep copied")
	_audit(false)
	terrain.free()
	_finish()

func _finish() -> void:
	print(JSON.stringify({"checks":checks,"failures":failures,"commits":committed,"scope":"actual fixed source meshes and isolated presentation transactions; no native/game/authority or GPU pixel claim"}))
	quit(0 if failures.is_empty() else 1)
