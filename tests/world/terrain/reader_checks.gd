extends RefCounted
# Literal independent codec fixtures, accepted expected-v1.json (not a writer).
const Reader=preload("res://world/terrain/resident_grid_reader.gd")
const GOLDEN="464752444c4531000100000004030201c3000000000000000300000002000000060000000100000001000000010000000300000000000000020200000000000000000000000000000000000000000000000000000000594000000000000000c000000000000000c0000000000000803f0000c07f000000000000803f0000c07f1b00000000000000056772617373000000000000e03f000000000000d03f0370616400000000070300000018fcffff18fcffff18fcffffe8030000e803000018fcffff"
const ZERO="464752444c4531000100000004030201920000000000000002000000020000000400000001000000010000000000000000000000000000000200000000000000000000000000008000000000000000800000000000000080000000000000008000000000000000c0000000800000000000000080000000000f00000000000000017a00000000000000800000000000000000"
var checks: int=0
var failures: Array=[]

func check(good: bool,name: String) -> void:
	checks+=1
	if not good: failures.append(name)

func entry(bytes: PackedByteArray) -> Dictionary:
	# Synthetic checked-registry shape. No real source/pack authority claimed.
	var files: Array=[]
	var digest: String="e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855" if bytes.is_empty() else Reader._hash(bytes)
	for pair in [["ground.fgrd","resident-ground-grid-v1"],["airport.json","airport-source-record"],["dossier.json","airport-source-dossier"],["compile-receipt.json","terrain-compile-receipt-v1"],["start-ready34.json","world-start-recipe-v1"],["NOTICE.txt","source-notice"]]:
		files.append({"path":pair[0],"role":pair[1],"bytes":bytes.size() if files.is_empty() else 1,"sha256":digest if files.is_empty() else "0".repeat(64)})
	var anchor: Dictionary={"latitude_rad":0.0,"longitude_rad":0.0,"ellipsoid_height_m":100.0}
	if bytes.size()>=104:
		anchor={"latitude_rad":bytes.decode_double(64),"longitude_rad":bytes.decode_double(72),"ellipsoid_height_m":bytes.decode_double(80)}
	return {"files":files,"world_anchor":anchor}

func admitted(bytes: PackedByteArray) -> bool:
	return Reader.decode(bytes,entry(bytes)).ok

func _four(heights: Array,spacing: int=4) -> PackedByteArray:
	# Fixed tiny fixture mutation only. No arbitrary Definition/production encoder.
	var bytes: PackedByteArray=ZERO.hex_decode()
	bytes[56]=spacing
	bytes.encode_double(64,0.0)
	bytes.encode_double(72,0.0)
	bytes.encode_double(80,100.0)
	bytes.encode_double(88,0.0)
	bytes.encode_double(96,0.0)
	for i in 4: bytes.encode_u32(104+i*4,heights[i])
	return bytes

func _span(negative_minimum: bool) -> PackedByteArray:
	# Independent frozen exact-admission witness, same fixed 4362-byte layout.
	var bytes:=PackedByteArray()
	bytes.resize(4362)
	for i in 8: bytes[i]=[70,71,82,68,76,69,49,0][i]
	for row in [[8,1],[12,0x01020304],[16,4362],[24,513],[28,2],[32,1026],[36,17],[40,1],[44,0],[48,0],[52,0]]:
		bytes.encode_u32(row[0],row[1])
	bytes[56]=4
	bytes[57]=0
	bytes.encode_double(80,100.0)
	bytes.encode_double(88,-1024.0)
	for row in 2:
		for col in 513:
			var offset: int=104+4*(row*513+col)
			if col==512: bytes.encode_u32(offset,0x44ffff00)
			elif col==0 and negative_minimum: bytes.encode_u32(offset,0x80000001)
			else: bytes.encode_float(offset,float(4*col))
	for i in 128: bytes[4208+i]=255
	bytes[4336]=3
	bytes[4344]=1
	bytes[4345]=122 # z; static and dynamic +0 in remaining16 bytes
	return bytes

func run() -> Dictionary:
	var fp_words:=PackedByteArray()
	fp_words.resize(16)
	fp_words.encode_u64(0,0x3ca0000000000000)
	var exact_half: float=fp_words.decode_double(0)
	fp_words.encode_double(8,exact_half)
	check(fp_words.decode_u64(8)==0x3ca0000000000000,"exact2^-53 raw witness survives carrier")
	fp_words.encode_double(8,1.0+3.0*exact_half)
	check(fp_words.decode_u64(8)==0x3ff0000000000002,"exact RNE upper-even half tie")
	check(Reader._environment(),"actual supported nearest-even/subnormal environment witness")
	var raw_subnormal:=PackedByteArray()
	raw_subnormal.resize(8)
	raw_subnormal.encode_u32(0,1)
	raw_subnormal.encode_u32(4,0x80000001)
	fp_words.encode_double(0,Reader._height(raw_subnormal,0))
	fp_words.encode_double(8,Reader._height(raw_subnormal,1))
	check(fp_words.hex_encode()=="000000000000a036000000000000a0b6","exact positive/negative f32 minsub promotion words")
	var golden: PackedByteArray=GOLDEN.hex_decode()
	var zero: PackedByteArray=ZERO.hex_decode()
	check(golden.size()==195 and Reader._hash(golden)=="7abb9551cf82cea00dc382c01bd3d675f91a1306cb9b09b0b039c1bf5fb5aa17","literal golden identity")
	check(zero.size()==146 and Reader._hash(zero)=="df832af1c57d060299135d16b7bfedd59e66a4611a8337f9cac2693f24a155e3","literal signed-zero identity")
	var decoded: Dictionary=Reader.decode(golden,entry(golden))
	check(decoded.ok,"golden complete admission")
	check(admitted(zero),"signed-zero admission")
	if decoded.ok:
		var grid: RefCounted=decoded.grid
		check(grid.metadata().columns==3 and grid.metadata().rows==2,"decoded dimensions")
		check(grid.copy_up_words()==golden.slice(104,128) and grid.copy_valid_words()==golden.slice(128,136),"all original height/mask bytes")
		check(grid.copy_materials()==[{"id":"grass","static_friction":0.5,"dynamic_friction":0.25}],"exact original material tuple")
		check(grid.copy_polygons()==[{"id":"pad","material_index":0,"priority":7,"vertices_mm":[[-1000,-1000],[-1000,1000],[1000,-1000]]}],"exact ordered ring tuple")
		var copy: Dictionary=grid.metadata()
		copy.columns=99
		copy.world_anchor.latitude_rad=1.0
		var words: PackedByteArray=grid.copy_up_words()
		words[0]=255
		var materials: Array=grid.copy_materials()
		materials[0].id="changed"
		var polygons: Array=grid.copy_polygons()
		polygons[0].vertices_mm[0][0]=0
		check(grid.metadata().columns==3 and grid.metadata().world_anchor.latitude_rad==0.0 and grid.copy_up_words()[0]==0 and grid.copy_materials()[0].id=="grass" and grid.copy_polygons()[0].vertices_mm[0][0]== -1000,"deep copied views")
	for source in [golden,zero]:
		for cut in source.size(): check(not admitted(source.slice(0,cut)),"every truncated prefix rejected")
		var extra: PackedByteArray=source.duplicate()
		extra.append(0)
		check(not admitted(extra),"appended byte rejected")
	for patch in [[0,0],[8,2],[12,0],[20,1],[24,1],[32,5],[36,2],[40,0],[44,129],[48,4],[52,1],[56,3],[57,3],[58,1],[60,1],[136,0],[137,65]]:
		var changed: PackedByteArray=golden.duplicate()
		changed[patch[0]]=patch[1]
		check(not admitted(changed),"closed structural mutation "+str(patch[0]))
	for patch in [[104,0x7f800000],[112,0],[128,0x8000001b]]:
		var changed: PackedByteArray=golden.duplicate()
		changed.encode_u32(patch[0],patch[1])
		check(not admitted(changed),"nonfinite/sentinel/padding mutation")
	var wrong: Dictionary=entry(golden)
	wrong.files[0].sha256="0".repeat(64)
	check(not Reader.decode(golden,wrong).ok,"digest mismatch")
	wrong=entry(golden)
	wrong.world_anchor.latitude_rad=0
	check(not Reader.decode(golden,wrong).ok,"int anchor never coerced")
	check(not Reader.decode([],entry(golden)).ok,"wrong bytes Variant rejected")
	check(not Reader.decode(golden,[]).ok,"wrong entry Variant rejected")
	check(admitted(_four([0,0x42800000,0,0x42800000])),"exact maximum gradient16 accepted at4m")
	check(not admitted(_four([0x80000001,0x42800000,0,0x42800000])),"negative minsub exact gradient witness rejected")
	check(not admitted(_four([0,0x42800001,0,0x42800001])),"next Float32 gradient above16 rejected")
	check(admitted(_four([0,0x41000001,0,0x41000001])),"former2 cap is no longer applied")
	check(admitted(_span(false)),"exact2048 bracket span accepted")
	check(not admitted(_span(true)),"2048 plus minsub bracket span rejected")
	var nonlattice: PackedByteArray=zero.duplicate()
	nonlattice.encode_double(88,0.1)
	check(not admitted(nonlattice),"non-lattice origin rejected")
	var friction: PackedByteArray=zero.duplicate()
	friction.encode_u64(138,1)
	check(not admitted(friction),"positive double minsub dynamic exceeds static zero")
	var priority: PackedByteArray=golden.duplicate()
	priority[166]=255
	check(admitted(priority),"full uint8 priority255 is admitted")
	var no_cell: PackedByteArray=_four([0x7fc00000,0x7fc00000,0x7fc00000,0x7fc00000])
	no_cell[120]=0
	check(not admitted(no_cell),"all invalid has no usable cell")
	check(Reader._ring([[-2,-2],[-2,2],[2,2],[2,-2]]),"clockwise convex ring")
	check(Reader._ring([[-2,-2],[-2,2],[0,2],[0,0],[2,0],[2,-2]]),"clockwise concave ring")
	check(Reader._ring([[-2,-2],[-2,0],[-2,2],[2,2],[2,-2]]),"forward adjacent collinear edges admitted")
	check(not Reader._ring([[-2,-2],[-2,2],[-2,0],[2,2],[2,-2]]),"adjacent reverse overlap refused")
	check(not Reader._ring([[-2,-2],[2,2],[-2,2],[2,-2]]),"self-intersection refused")
	check(not Reader._ring([[-2,-2],[-2,2],[2,2],[-2,-2],[2,-2]]),"duplicate ring point refused")
	return {"checks":checks,"failures":failures.duplicate(),"scope":"synthetic codec, exact admission and copied views only"}
