extends SceneTree
# Original MIT. Synthetic hand controls plus optional actual-source component.
# No flight/native/storage is created. Actual game/visual evidence stays separate.
const Decor=preload("res://world/decoration/kawo_evergreens.gd")
const Reader=preload("res://world/terrain/resident_grid_reader.gd")
const Worlds=preload("res://world/world_admission.gd")
const Frames=preload("res://simulation/canonical_frames.gd")
const Origin=preload("res://simulation/render_origin.gd")
var checks: int=0
var failures: Array=[]
var actual_result: Dictionary={}

func check(good: bool,name: String) -> void:
	checks+=1
	if not good and failures.size()<32: failures.append(name)

func _initialize() -> void:
	call_deferred("_run")

func _hand() -> void:
	var raw: PackedByteArray=FileAccess.get_file_as_bytes("res://decoration_tests/controls-v1.json")
	check(Reader._hash(raw)=="84bb8ae7328cdedb4224cabcd090b6277c8f26d7bcb17fb8dcc1cf4b8ecbf3ee","frozen hand controls bytes")
	if not failures.is_empty(): return
	var controls: Dictionary=JSON.parse_string(raw.get_string_from_utf8())
	for item in controls.mask:
		check(Decor._mask(int(item.u),int(item.v))==item.inside,"hand grove membership")
	check(not Decor._mask(-1,0) and not Decor._mask(97,0),"bounded grove lattice")
	for item in controls.keys:
		check(Decor._key(int(item.u),int(item.v))==String(item.key_hex).hex_to_int(),"hand hexadecimal XOR")
	for item in controls.addresses:
		check((int(item.east)+6144)/4==int(item.column) and (int(item.south)+4096)/4==int(item.row),"hand canonical vertex address")
	var box: Array=Decor._pavement_box(controls.pavement.ring_mm)
	check(box==[-113000,113000,-113000,113000],"hand exact pavement envelope")
	for item in controls.pavement.points:
		check(Decor._inside(float(item.x)*1000.0,float(item.z)*1000.0,box)==item.excluded,"hand inclusive pavement boundary")
	var corridor: Array=Decor._end_box(controls.corridor.end,controls.corridor.opposite)
	check(corridor==[-213.0,213.0,-213.0,1713.0],"hand outward corridor envelope")
	for item in controls.corridor.points:
		check(Decor._inside(float(item.x),float(item.z),corridor)==item.excluded,"hand inclusive end boundary")
	check(Decor._end_box([0.0,0.0],[0.0,0.0]).is_empty(),"zero length corridor refused")
	check(Decor._end_box([NAN,0.0],[0.0,1.0]).is_empty(),"nonfinite corridor refused")
	for item in controls.counts:
		check(Decor._selection_count(int(item.suitable))==int(item.selected),"hand minimum and balanced cap")
	for item in controls.sites:
		var up:=PackedByteArray()
		up.resize(49*4)
		for i in 49: up.encode_u32(i*4,String(item.other_word).hex_to_int())
		up.encode_u32(24*4,String(item.center_word).hex_to_int())
		var valid:=PackedByteArray([255,255,255,255,255,255,1])
		if item.get("missing_neighbor",false): valid[0]=254
		var site: Dictionary=Decor._site(up,valid,7,7,3,3)
		check((not site.is_empty())==item.valid,"hand fixed local span/validity "+item.name)
		if item.valid: check(site.word==String(item.center_word).hex_to_int(),"hand exact foot word "+item.name)
		check(Decor._site(up,valid,7,7,2,3).is_empty(),"edge neighborhood refused")
	var ordered: Array=[{"key":2,"v":0,"u":0},{"key":1,"v":2,"u":0},{"key":1,"v":1,"u":3},{"key":1,"v":1,"u":2}]
	ordered.sort_custom(Decor._ordered)
	check(ordered==[{"key":1,"v":1,"u":2},{"key":1,"v":1,"u":3},{"key":1,"v":2,"u":0},{"key":2,"v":0,"u":0}],"hand hash/row/column tie order")
	check(not Decor.prepare(null,{},"",[],[]).ok,"no decoder admission is forged")
	var invalid: Node3D=Decor.new()
	check(not invalid.bind_session("fake").ok,"unprepared binding refused")
	invalid.free()

func _actual(mode: String) -> void:
	var relation: Dictionary=Worlds.selection("kawo-prototype-v1","original-interactive-prototype","ground-ready","calm")
	check(relation.ok,"actual fixed registry")
	if not relation.ok: return
	var path: String="res://worlds/kawo-prototype-v1/"
	var payload: PackedByteArray=FileAccess.get_file_as_bytes(path+"ground.fgrd")
	var receipt_raw: PackedByteArray=FileAccess.get_file_as_bytes(path+"compile-receipt.json")
	check(Reader._hash(receipt_raw)=="cb1e0b28384aeb1c11173d991b5790a8a16e64953c2c479be6b07136c5f489f0","actual fixed geometry receipt")
	var decoded: Dictionary=Reader.decode(payload,relation.entry)
	check(decoded.ok,"actual admitted grid")
	if not decoded.ok or not failures.is_empty(): return
	var receipt: Dictionary=JSON.parse_string(receipt_raw.get_string_from_utf8())
	var meta: Dictionary=decoded.grid.metadata()
	var frame: Dictionary=Frames.anchor(meta.world_anchor.latitude_rad,meta.world_anchor.longitude_rad,meta.world_anchor.ellipsoid_height_m)
	if mode in ["missing-asset","changed-asset"]:
		# Root creates a separate disposable project, never mutates the good copy.
		var first: String="res://environment/original-evergreens-v1/tall-narrow-lod1.glb"
		var missing: bool=not FileAccess.file_exists(first)
		check(missing if mode=="missing-asset" else (not missing and FileAccess.get_sha256(first)!="35f8cd9714082054e851550281c6996c67159d46b8a2345737a1b63a93e5299d"),"explicit owned source fault required")
		var refused: Dictionary=Decor.prepare(decoded.grid,receipt.airport_geometry,"",frame.ecef,frame.rotation)
		check(not refused.ok and refused.root==null,"actual source fault leaves no partial decoration")
		if refused.ok and is_instance_valid(refused.root): refused.root.free()
		actual_result={"mode":mode,"expected_refusal":not refused.ok}
		return
	var built: Dictionary=Decor.prepare(decoded.grid,receipt.airport_geometry,"",frame.ecef,frame.rotation)
	check(built.ok,"actual decorative preparation")
	if not built.ok:
		actual_result={"preparation_error":built.error}
		return
	var trees: Node3D=built.root
	var repeat: Dictionary=Decor.prepare(decoded.grid,receipt.airport_geometry,"",frame.ecef,frame.rotation)
	check(repeat.ok,"actual deterministic repeat preparation")
	if repeat.ok:
		check(repeat.root.placement_observation()==trees.placement_observation(),"actual identical copied placement facts")
		repeat.root.free()
	check(not trees.visible and trees.get_parent()==null and trees.get_child_count()==9,"hidden unparented nine batches")
	check(trees.bind_session("test.decoration-component").ok,"actual provisional session bind")
	check(not trees.bind_session("other").ok,"actual repeated bind refused")
	root.add_child(trees)
	var observed: Dictionary=trees.placement_observation()
	check(observed.count>=96 and observed.count<=192 and observed.count%3==0,"actual bounded balanced trees")
	var up: PackedByteArray=decoded.grid.copy_up_words()
	var valid: PackedByteArray=decoded.grid.copy_valid_words()
	var exclusions: Dictionary=Decor._exclusions(receipt.airport_geometry)
	var counts: Array=[0,0,0]
	var previous: Dictionary={}
	var seen: Dictionary={}
	var transforms: Array=[[],[],[]]
	for row in observed.placements:
		var key: String=str(row.column)+":"+str(row.row)
		check(not seen.has(key),"no duplicate actual tree")
		seen[key]=true
		check(Decor._mask(row.u,row.v) and row.key==Decor._key(row.u,row.v),"actual deterministic grove/key")
		check(previous.is_empty() or Decor._ordered(previous,row),"actual stable selected order")
		previous=row
		check(row.east_m== -1536+32*row.u and row.south_m== -1536+32*row.v and row.column==(row.east_m+6144)/4 and row.row==(row.south_m+4096)/4,"actual exact vertex address")
		var index: int=row.row*meta.columns+row.column
		check(row.up_word==up.decode_u32(index*4),"actual retained original foot word")
		check(Reader._same_float(row.up_m,Reader._height(up,index)),"actual canonical foot scalar")
		check(not Decor._site(up,valid,meta.columns,meta.rows,row.column,row.row).is_empty() and not Decor._excluded(float(row.east_m),float(row.south_m),exclusions),"actual source suitability and exclusions")
		check(row.design==((seen.size()-1)%3) and row.yaw_index==(row.key&15),"actual balanced design/yaw")
		counts[row.design]+=1
		transforms[row.design].append(Transform3D(Basis(Vector3.UP,float(row.yaw_index)*(PI/8.0)),Vector3(float(row.east_m),row.up_m,float(row.south_m))))
	check(counts[0]==counts[1] and counts[1]==counts[2],"actual exact per-design balance")
	var batch_index: int=0
	for design in 3:
		for part in 3:
			var batch: Node=trees.get_child(batch_index)
			batch_index+=1
			check(batch is MultiMeshInstance3D and batch.transform==Transform3D.IDENTITY and batch.get_child_count()==0,"actual batch has no extra transform/physics subtree")
			if not batch is MultiMeshInstance3D: continue
			check(batch.multimesh.instance_count==counts[design] and batch.multimesh.mesh.get_surface_count()==1,"actual per-material batch counts")
			for index in counts[design]:
				var transform: Transform3D=batch.multimesh.get_instance_transform(index)
				check(transform==transforms[design][index],"actual canonical instance transform")
				var bounds: AABB=transform*batch.multimesh.mesh.get_aabb()
				check(batch.multimesh.custom_aabb.encloses(bounds),"actual bounded culling envelope")
	var origin: RefCounted=Origin.new("test.decoration-component",frame.ecef,frame.rotation)
	check(origin.register_participant("absent",null,["ownship","cockpit","camera","world","light","spatial_audio","local_particles"]).ok,"isolated absent category declaration")
	check(origin.register_participant("kawo-decoration",trees,[]).ok,"existing category-free sibling registration")
	check(origin.rebase(frame.ecef).ok,"actual common anchor adoption")
	var before: Dictionary=trees.placement_observation()
	var moved: Array=[float(frame.ecef[0])+500.0,float(frame.ecef[1])-300.0,float(frame.ecef[2])+100.0]
	check(origin.rebase(moved).ok,"actual oblique presentation rebase")
	var expected_offset: Array=Frames.project(frame.ecef,moved,frame.rotation)
	for axis in 3:
		check(absf(float(trees.position[axis])-expected_offset[axis])<=1.0/128.0,"actual common root numerical budget")
	check(origin.rebase(frame.ecef).ok and trees.position==Vector3.ZERO,"actual return to anchor")
	check(trees.placement_observation()==before,"origin never rewrites canonical instances/source")
	var binding: Dictionary=trees.source_binding()
	binding.world_anchor.latitude_rad=0.0
	check(trees.source_binding().world_anchor==meta.world_anchor,"copied source binding")
	actual_result=observed
	origin.unregister_participant("kawo-decoration")
	root.remove_child(trees)
	trees.free()

func _run() -> void:
	_hand()
	var args: PackedStringArray=OS.get_cmdline_user_args()
	if args.size()>1 or (args.size()==1 and args[0] not in ["actual","missing-asset","changed-asset"]):
		check(false,"usage decoration_checks.gd [actual|missing-asset|changed-asset]")
	elif args.size()==1 and failures.is_empty(): _actual(args[0])
	var result: Dictionary={"scope":"Synthetic hand controls"+(" and actual isolated presentation component" if args.size()==1 else ""),"checks":checks,"failures":failures,"native_flight_exercised":false,"actual":actual_result}
	print("KAWO_DECORATION_RESULT="+JSON.stringify(result))
	if args.size()==1:
		var file: FileAccess=FileAccess.open("res://decoration-component-receipt.json",FileAccess.WRITE)
		if file==null: check(false,"isolated result receipt")
		else:
			file.store_string(JSON.stringify(result))
			file.close()
	quit(0 if failures.is_empty() else 1)
