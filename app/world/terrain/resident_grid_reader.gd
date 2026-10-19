extends RefCounted
# Original MIT. Closed byte reader; successful decoding is presentation data,
# never native admission. All geometry uses the retained original IEEE words.
const MAX_BYTES: int = 276946836
const MAX_OWNED: int = 536870912
const LIMBS: int = 24 # 360 bits; Float32-unit squared differences need <328.
const BASE: int = 32768
const MASK: int = 32767
const MAGIC = [70,71,82,68,76,69,49,0]

class DecodedGrid extends RefCounted:
	var _admitted: bool = false
	var _meta: Dictionary = {}
	var _up: PackedByteArray = PackedByteArray()
	var _valid: PackedByteArray = PackedByteArray()
	var _materials: Array = []
	var _polygons: Array = []
	func metadata() -> Dictionary:
		return _meta.duplicate(true) if _admitted else {}
	func copy_up_words() -> PackedByteArray:
		return _up.duplicate() if _admitted else PackedByteArray()
	func copy_valid_words() -> PackedByteArray:
		return _valid.duplicate() if _admitted else PackedByteArray()
	func copy_materials() -> Array:
		return _materials.duplicate(true) if _admitted else []
	func copy_polygons() -> Array:
		return _polygons.duplicate(true) if _admitted else []

class Cursor extends RefCounted:
	var bytes: PackedByteArray
	var position: int = 104
	var ok: bool = true
	func need(count: int) -> bool:
		if count < 0 or count > bytes.size()-position:
			ok=false
		return ok
	func u8() -> int:
		if not need(1): return 0
		var value: int=bytes[position]
		position+=1
		return value
	func u32() -> int:
		if not need(4): return 0
		var value: int=bytes.decode_u32(position)
		position+=4
		return value
	func i32() -> int:
		var value: int=u32()
		return value-4294967296 if value>=2147483648 else value
	func f64() -> float:
		if not need(8): return NAN
		var value: float=bytes.decode_double(position)
		position+=8
		return value
	func identifier() -> String:
		var count: int=u8()
		if count<1 or count>128 or not need(count):
			ok=false
			return ""
		var start: int=position
		position+=count
		for i in range(start,position):
			if bytes[i]>127:
				ok=false
		return bytes.slice(start,position).get_string_from_ascii()

static func _failure() -> Dictionary:
	return {"ok":false,"error":"Invalid or incompatible resident terrain bytes","grid":null}

static func _keys(value: Variant, names: Array) -> bool:
	if not value is Dictionary or value.size()!=names.size(): return false
	for name in names:
		if not value.has(name): return false
	return true

static func _float(value: Variant) -> bool:
	return typeof(value)==TYPE_FLOAT and is_finite(value)

static func _same_float(a: Variant,b: Variant) -> bool:
	if not _float(a) or not _float(b): return false
	var words:=PackedByteArray()
	words.resize(16)
	words.encode_double(0,a)
	words.encode_double(8,b)
	return words.slice(0,8)==words.slice(8,16)

static func _nonnegative_key(value: float) -> int:
	var bytes:=PackedByteArray()
	bytes.resize(8)
	bytes.encode_double(0,value)
	var word: int=bytes.decode_u64(0)
	if (word&0x7fffffffffffffff)==0: return 0 # Both signed zeros admitted.
	return -1 if word<0 else word

static func _origin_lattice(value: float) -> bool:
	var bytes:=PackedByteArray()
	bytes.resize(8)
	bytes.encode_double(0,value)
	var magnitude: int=bytes.decode_u64(0)&0x7fffffffffffffff
	if magnitude==0: return true
	var exponent: int=(magnitude>>52)&2047
	if exponent<991: return false # Nonzero magnitude smaller than2^-32.
	if exponent>=1043: return true
	var significand: int=(magnitude&0xfffffffffffff)|0x10000000000000
	return (significand&((1<<(1043-exponent))-1))==0

static func _hash(bytes: PackedByteArray) -> String:
	var hash:=HashingContext.new()
	if hash.start(HashingContext.HASH_SHA256)!=OK or hash.update(bytes)!=OK: return ""
	return hash.finish().hex_encode()

static func _environment() -> bool:
	# Observe, never change the caller FP environment. Variable operands prevent
	# compile-time folding of the RN-even / no-DAZ/no-FTZ witness arithmetic.
	var bytes:=PackedByteArray()
	bytes.resize(24)
	bytes.encode_u64(0,1)
	var tiny: float=bytes.decode_double(0)
	bytes.encode_double(8,tiny+tiny)
	if bytes.decode_u64(8)!=2: return false
	bytes.encode_double(0,1.0)
	bytes.encode_u64(8,0x3ca0000000000000) # Exact2^-53; never reparse a decimal.
	var one: float=bytes.decode_double(0)
	var half: float=bytes.decode_double(8)
	bytes.encode_double(16,one+half)
	if bytes.decode_u64(16)!=0x3ff0000000000000: return false
	bytes.encode_double(16,one+3.0*half)
	return bytes.decode_u64(16)==0x3ff0000000000002

static func _hex(value: Variant,count: int) -> bool:
	if typeof(value)!=TYPE_STRING or value.length()!=count: return false
	for i in count:
		var c: int=value.unicode_at(i)
		if not ((c>=48 and c<=57) or (c>=97 and c<=102)): return false
	return true

static func _id(value: String) -> bool:
	if value.length()<1 or value.length()>128: return false
	var last_separator: bool=false
	for i in value.length():
		var c: int=value.unicode_at(i)
		var letter: bool=c>=97 and c<=122
		var digit: bool=c>=48 and c<=57
		var separator: bool=c==46 or c==95 or c==45
		if i==0 and not letter: return false
		if not letter and not digit and not separator: return false
		if separator and (last_separator or i==value.length()-1): return false
		last_separator=separator
	return true

static func _valid(mask: PackedByteArray,index: int) -> bool:
	return (mask[index>>3] & (1<<(index&7)))!=0

static func _height(bytes: PackedByteArray,index: int) -> float:
	var word: int=bytes.decode_u32(index*4)
	if (word&0x7f800000)==0:
		if (word&0x7fffffff)==0: return bytes.decode_float(index*4)
		# Never convert a hardware f32 subnormal through a DAZ-sensitive promotion.
		var unit:=PackedByteArray()
		unit.resize(8)
		unit.encode_u64(0,0x36a0000000000000) # Exact2^-149, not decimal reparsing.
		var value: float=float(word&0x7fffff)*unit.decode_double(0)
		return -value if (word&0x80000000)!=0 else value
	return bytes.decode_float(index*4)

# Exact nonnegative integer arithmetic in units 2^-149. The fixed 360-bit
# workspace exceeds the admitted height-range square bound, including carries.
static func _zero() -> PackedInt64Array:
	var a:=PackedInt64Array()
	a.resize(LIMBS)
	return a

static func _power(bit: int) -> PackedInt64Array:
	var a: PackedInt64Array=_zero()
	a[bit/15]=1<<(bit%15)
	return a

static func _compare(a: PackedInt64Array,b: PackedInt64Array) -> int:
	for i in range(LIMBS-1,-1,-1):
		if a[i]!=b[i]: return -1 if a[i]<b[i] else 1
	return 0

static func _add(a: PackedInt64Array,b: PackedInt64Array) -> PackedInt64Array:
	var out: PackedInt64Array=_zero()
	var carry: int=0
	for i in LIMBS:
		var value: int=a[i]+b[i]+carry
		out[i]=value&MASK
		carry=value>>15
	assert(carry==0)
	return out

static func _subtract(a: PackedInt64Array,b: PackedInt64Array) -> PackedInt64Array:
	var out: PackedInt64Array=_zero()
	var borrow: int=0
	for i in LIMBS:
		var value: int=a[i]-b[i]-borrow
		borrow=1 if value<0 else 0
		out[i]=value+BASE if value<0 else value
	assert(borrow==0)
	return out

static func _multiply(a: PackedInt64Array,b: PackedInt64Array) -> PackedInt64Array:
	var out: PackedInt64Array=_zero()
	for i in LIMBS:
		var carry: int=0
		for j in range(LIMBS-i):
			var value: int=out[i+j]+a[i]*b[j]+carry
			out[i+j]=value&MASK
			carry=value>>15
		assert(carry==0)
	return out

static func _units(word: int) -> PackedInt64Array:
	var exponent: int=(word>>23)&255
	var significand: int=word&0x7fffff
	if exponent!=0: significand|=0x800000
	var shift: int=0 if exponent==0 else exponent-1
	var out: PackedInt64Array=_zero()
	for bit in 24:
		if (significand&(1<<bit))!=0:
			out[(shift+bit)/15]|=1<<((shift+bit)%15)
	return out

static func _difference(a: int,b: int) -> PackedInt64Array:
	var left: PackedInt64Array=_units(a)
	var right: PackedInt64Array=_units(b)
	if ((a^b)&0x80000000)!=0: return _add(left,right)
	return _subtract(left,right) if _compare(left,right)>=0 else _subtract(right,left)

static func _gradient(dx: float,dz: float,spacing: int,raw: PackedByteArray,ia: int,ib: int,ic: int,id: int) -> bool:
	var squared: float=dx*dx+dz*dz
	var limit: float=float(256*spacing*spacing)
	# |heights|<=4096, differences<=8192: two binary64 subtractions,
	# two squares and their addition have absolute error <1e-6, even when
	# tiny f32 terms disappear. This is ONLY a certified filter; the band
	# always falls through to the unchanged exact mathematical predicate.
	if squared<limit-0.000001: return true
	if squared>limit+0.000001: return false
	var x: PackedInt64Array=_difference(raw.decode_u32(ia*4),raw.decode_u32(ib*4))
	var z: PackedInt64Array=_difference(raw.decode_u32(ic*4),raw.decode_u32(id*4))
	return _compare(_add(_multiply(x,x),_multiply(z,z)),_power(308 if spacing==2 else 310))<=0

static func _orientation(a: Array,b: Array,p: Array) -> int:
	return (b[0]-a[0])*(p[1]-a[1])-(b[1]-a[1])*(p[0]-a[0])

static func _on(a: Array,b: Array,p: Array) -> bool:
	return _orientation(a,b,p)==0 and p[0]>=mini(a[0],b[0]) and p[0]<=maxi(a[0],b[0]) and p[1]>=mini(a[1],b[1]) and p[1]<=maxi(a[1],b[1])

static func _crosses(a: Array,b: Array,c: Array,d: Array) -> bool:
	var x: int=_orientation(a,b,c)
	var y: int=_orientation(a,b,d)
	var z: int=_orientation(c,d,a)
	var w: int=_orientation(c,d,b)
	if (x==0 and _on(a,b,c)) or (y==0 and _on(a,b,d)) or (z==0 and _on(c,d,a)) or (w==0 and _on(c,d,b)): return true
	return ((x<0 and y>0) or (x>0 and y<0)) and ((z<0 and w>0) or (z>0 and w<0))

static func _ring(points: Array) -> bool:
	var count: int=points.size()
	if count<3 or count>4096: return false
	var seen: Dictionary={}
	var area: int=0
	for i in count:
		var a: Array=points[i]
		var b: Array=points[(i+1)%count]
		if abs(a[0])>8192000 or abs(a[1])>8192000: return false
		var key: String=str(a[0])+","+str(a[1])
		if seen.has(key): return false
		seen[key]=true
		area+=a[0]*b[1]-a[1]*b[0]
	if area>=0: return false
	# Products and sum fit signed64: <=4096*2*(8192000^2)<2^59.
	for i in count:
		var a: Array=points[i]
		var b: Array=points[(i+1)%count]
		var next: Array=points[(i+2)%count]
		if _orientation(a,b,next)==0 and (_on(a,b,next) or _on(b,next,a)): return false
		for j in range(i+1,count):
			if j==i+1 or (i==0 and j+1==count): continue
			if _crosses(a,b,points[j],points[(j+1)%count]): return false
	return true

static func decode(input: Variant,checked_entry: Variant) -> Dictionary:
	if not input is PackedByteArray or not checked_entry is Dictionary or input.size()<104 or input.size()>MAX_BYTES: return _failure()
	var files: Variant=checked_entry.get("files")
	var anchor: Variant=checked_entry.get("world_anchor")
	if not files is Array or files.size()!=6 or not _keys(anchor,["latitude_rad","longitude_rad","ellipsoid_height_m"]): return _failure()
	var selected: Variant=null
	for file in files:
		if not _keys(file,["path","sha256","bytes","role"]): return _failure()
		if file.get("path")=="ground.fgrd" or file.get("role")=="resident-ground-grid-v1":
			if selected!=null or typeof(file.path)!=TYPE_STRING or file.path!="ground.fgrd" or typeof(file.role)!=TYPE_STRING or file.role!="resident-ground-grid-v1": return _failure()
			selected=file
	if selected==null or typeof(selected.bytes)!=TYPE_INT or selected.bytes!=input.size() or not _hex(selected.sha256,64): return _failure()
	# Owned duplicate establishes stable parsing; returned buffers never alias input.
	var bytes: PackedByteArray=input.duplicate()
	if _hash(bytes)!=selected.sha256: return _failure()
	for i in 8:
		if bytes[i]!=MAGIC[i]: return _failure()
	if bytes.decode_u32(8)!=1 or bytes.decode_u32(12)!=0x01020304 or bytes.decode_u32(16)!=bytes.size() or bytes.decode_u32(20)!=0 or bytes.decode_u16(58)!=0 or bytes.decode_u32(60)!=0: return _failure()
	var columns: int=bytes.decode_u32(24)
	var rows: int=bytes.decode_u32(28)
	var n: int=bytes.decode_u32(32)
	var words: int=bytes.decode_u32(36)
	var material_count: int=bytes.decode_u32(40)
	var polygon_count: int=bytes.decode_u32(44)
	var vertex_count: int=bytes.decode_u32(48)
	var default_material: int=bytes.decode_u32(52)
	var spacing: int=bytes[56]
	if columns<2 or columns>8193 or rows<2 or rows>8193 or n!=columns*rows or words!=(n+63)/64 or material_count<1 or material_count>32 or polygon_count>128 or vertex_count>4096 or default_material>=material_count or (spacing!=2 and spacing!=4) or bytes[57]>2: return _failure()
	# Bounded counts make all following signed64 arithmetic nonoverflowing.
	if 104+4*n+8*words+18*material_count+11*polygon_count+8*vertex_count>bytes.size(): return _failure()
	var decoded_anchor: Dictionary={"latitude_rad":bytes.decode_double(64),"longitude_rad":bytes.decode_double(72),"ellipsoid_height_m":bytes.decode_double(80)}
	for key in decoded_anchor:
		if not _same_float(decoded_anchor[key],anchor.get(key)): return _failure()
	if absf(decoded_anchor.latitude_rad)>PI/2.0 or absf(decoded_anchor.longitude_rad)>PI or decoded_anchor.ellipsoid_height_m< -500.0 or decoded_anchor.ellipsoid_height_m>10000.0: return _failure()
	var east: float=bytes.decode_double(88)
	var south: float=bytes.decode_double(96)
	for pair in [[east,columns],[south,rows]]:
		var origin: float=pair[0]
		var end: float=origin+float((pair[1]-1)*spacing)
		if not is_finite(origin) or absf(origin)>8192.0 or not is_finite(end) or absf(end)>8192.0 or end<=origin or not _origin_lattice(origin): return _failure()
	var cursor:=Cursor.new()
	cursor.bytes=bytes
	cursor.position=104+4*n+8*words
	var materials: Array=[]
	var polygons: Array=[]
	var material_ids: Dictionary={}
	var polygon_ids: Dictionary={}
	for i in material_count:
		var id: String=cursor.identifier()
		var static_friction: float=cursor.f64()
		var dynamic_friction: float=cursor.f64()
		if not cursor.ok or not _id(id) or material_ids.has(id) or not is_finite(static_friction) or not is_finite(dynamic_friction): return _failure()
		var static_key: int=_nonnegative_key(static_friction)
		var dynamic_key: int=_nonnegative_key(dynamic_friction)
		if dynamic_key<0 or static_key<dynamic_key or static_key>0x4014000000000000: return _failure()
		material_ids[id]=true
		materials.append({"id":id,"static_friction":static_friction,"dynamic_friction":dynamic_friction})
	var actual_vertices: int=0
	for i in polygon_count:
		var id: String=cursor.identifier()
		var material: int=cursor.u32()
		var priority: int=cursor.u8()
		var count: int=cursor.u32()
		if not cursor.ok or not _id(id) or polygon_ids.has(id) or material>=material_count or count<3 or count>4096-actual_vertices or not cursor.need(count*8): return _failure()
		actual_vertices+=count
		polygon_ids[id]=true
		var points: Array=[]
		for j in count: points.append([cursor.i32(),cursor.i32()])
		if not _ring(points): return _failure()
		polygons.append({"id":id,"material_index":material,"priority":priority,"vertices_mm":points})
	if not cursor.ok or actual_vertices!=vertex_count or cursor.position!=bytes.size(): return _failure()
	# Native decoded vectors reserve exact counts. Even a conservative 1MiB control
	# allowance +512B/record +256B/ID leaves the format maximum below the core cap;
	# Godot allocations/RSS are separate observations, not a false native capacity.
	if 1048576+4*n+8*words+768*(material_count+polygon_count)+8*vertex_count>MAX_OWNED: return _failure()
	var up: PackedByteArray=bytes.slice(104,104+4*n)
	var valid: PackedByteArray=bytes.slice(104+4*n,104+4*n+8*words)
	if n%64!=0:
		for bit in range(n%64,64):
			if (valid[(words-1)*8+(bit>>3)]&(1<<(bit&7)))!=0: return _failure()
	var low: float=INF
	var high: float=-INF
	var low_word: int=0
	var high_word: int=0
	for i in n:
		var word: int=up.decode_u32(4*i)
		if not _valid(valid,i):
			if word!=0x7fc00000: return _failure()
			continue
		if (word&0x7f800000)==0x7f800000: return _failure()
		var height: float=_height(up,i)
		if height< -1000.0 or height>4096.0: return _failure()
		if height<low: low=height; low_word=word
		if height>high: high=height; high_word=word
	if not is_finite(low): return _failure()
	var span: float=high-low+0.03125
	if span>2048.000000001: return _failure()
	if span>=2047.999999999 and _compare(_add(_difference(high_word,low_word),_power(144)),_power(160))>0: return _failure()
	var usable: bool=false
	# One bounded temporary avoids tens of millions of per-corner method calls.
	# Even DAZ-sensitive promotion can lose only f32-subnormal terms (<2^-126),
	# far below the certified filter band. Borderline cases always use raw words.
	var values: PackedFloat32Array=up.to_float32_array()
	for row in range(rows-1):
		for col in range(columns-1):
			var i: int=row*columns+col
			if not _valid(valid,i) or not _valid(valid,i+1) or not _valid(valid,i+columns) or not _valid(valid,i+columns+1): continue
			usable=true
			var a: float=values[i]
			var b: float=values[i+1]
			var c: float=values[i+columns]
			var d: float=values[i+columns+1]
			if not _gradient(d-c,c-a,spacing,up,i+columns+1,i+columns,i+columns,i) or not _gradient(b-a,d-b,spacing,up,i+1,i,i+columns+1,i+1): return _failure()
	if not usable: return _failure()
	var result:=DecodedGrid.new()
	result._meta={"payload_version":1,"payload_sha256":selected.sha256,"payload_bytes":bytes.size(),"columns":columns,"rows":rows,"spacing_m":spacing,"missing_reason":bytes[57],"east_origin_m":east,"south_origin_m":south,"world_anchor":decoded_anchor,"default_material_index":default_material}
	result._up=up
	result._valid=valid
	result._materials=materials
	result._polygons=polygons
	result._admitted=true
	return {"ok":true,"error":"","grid":result}
