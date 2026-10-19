extends Node3D
class_name KawoWorld
# Original MIT. Canonical terrain presentation only; never moves aircraft,
# samples native physics, resamples source heights or creates collision shapes.
const Reader = preload("res://world/terrain/resident_grid_reader.gd")
const Frames = preload("res://simulation/canonical_frames.gd")
const UInt64 = preload("res://simulation/uint64.gd")
const CHUNK_CELLS: int=64
const CHUNK_VERTICES: int=65
const CANDIDATE_KEYS=["session_id","origin_ecef_m","ecef_to_eus","version"]
const SHADER_SOURCE = """shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_disabled;
uniform vec2 ring0[4];
uniform vec2 ring1[4];
uniform bool second_wins=false;
uniform vec3 ground_color=vec3(0.21,0.28,0.13);
uniform vec3 color0=vec3(0.16,0.17,0.17);
uniform vec3 color1=vec3(0.16,0.17,0.17);
uniform vec4 paint_ends0;
uniform vec4 paint_ends1;
uniform vec4 paint_axes0;
uniform vec4 paint_axes1;
uniform vec2 paint_size0;
uniform vec2 paint_size1;
uniform vec4 paint_numbers0;
uniform vec4 paint_numbers1;
uniform ivec4 paint_digits0;
uniform ivec4 paint_digits1;
varying vec2 canonical_xz;
void vertex() { canonical_xz=VERTEX.xz; }
bool in_ring(vec2 p,int which) {
    // Both compiled footprints are clockwise convex rectangles. This affects
    // visual pigment only; CPU/native material predicates remain independent.
    for(int i=0;i<4;i++) {
        vec2 a=which==0?ring0[i]:ring1[i];
        vec2 b=which==0?ring0[(i+1)%4]:ring1[(i+1)%4];
        vec2 d=b-a; vec2 q=p-a;
        if(d.x*q.y-d.y*q.x>0.0) return false;
    }
    return true;
}
// Original 5x7 prototype glyphs. Row0 is the inward/top edge; column0 is
// the arriving pilot's left. These are not an operational marking font.
int glyph_row(int digit,int row) {
    if(digit==1) return row==0?4:row==1?12:row==6?14:4;
    if(digit==2) return row==0?14:row==1?17:row==2?1:row==3?2:row==4?4:row==5?8:31;
    if(digit==3) return row==0?30:row==3?14:row==6?30:1;
    if(digit==4) return row==0?2:row==1?6:row==2?10:row==3?18:row==4?31:2;
    if(digit==6) return row==0?6:row==1?8:row==2?16:row==3?30:row==6?14:17;
    if(digit==9) return row==0?14:row==1?17:row==2?17:row==3?15:row==4?1:row==5?2:12;
    return 0;
}
float ink(float distance_m,float aa) {
    return 1.0-smoothstep(-aa,aa,distance_m);
}
float glyph_occupancy(vec2 p,int digit) {
    if(p.x<0.0 || p.x>=7.5 || p.y<0.0 || p.y>=12.0) return 0.0;
    int col=min(4,int(floor(p.x/1.5)));
    int row=6-min(6,int(floor(p.y*(7.0/12.0))));
    return (glyph_row(digit,row) & (1<<(4-col)))!=0?1.0:0.0;
}
float glyph(vec2 p,int digit,float aa) {
    // Sample the whole occupied glyph, not distances to individual cells.
    // A boundary between two filled cells remains fully occupied, so it
    // cannot acquire an artificial half-coverage internal hairline.
    vec2 offset=vec2(0.5*aa);
    return 0.25*(glyph_occupancy(p+offset,digit)
                +glyph_occupancy(p-offset,digit)
                +glyph_occupancy(p+vec2(offset.x,-offset.y),digit)
                +glyph_occupancy(p+vec2(-offset.x,offset.y),digit));
}
float number_block(vec2 p,vec2 bottom,vec2 forward,vec2 right,ivec2 digits,float aa) {
    vec2 q=vec2(dot(p-bottom,right)+8.5,dot(p-bottom,forward));
    return max(glyph(q,digits.x,aa),glyph(q-vec2(9.5,0.0),digits.y,aa));
}
float runway_paint(vec2 p,vec4 ends,vec4 axes,vec2 size_m,vec4 bottoms,ivec4 digits,float aa) {
    vec2 q=vec2(dot(p-ends.xy,axes.zw),dot(p-ends.xy,axes.xy));
    float edge=ink(abs(abs(q.x)-(size_m.y*0.5-1.0))-0.225,aa);
    float center=0.0;
    if(q.y>=90.0 && q.y<=size_m.x-90.0) {
        // One first-end phase. The next rectangle supplies AA near period50;
        // reciprocal-end dashes must never be OR-ed into this pattern.
        float phase=mod(q.y-90.0,50.0);
        float longitudinal=min(abs(phase-10.0),abs(phase-60.0))-10.0;
        center=ink(max(abs(q.x)-0.225,longitudinal),aa);
    }
    float numbers=max(number_block(p,bottoms.xy,axes.xy,axes.zw,digits.xy,aa),
                      number_block(p,bottoms.zw,-axes.xy,-axes.zw,digits.zw,aa));
    // Fade tiny strokes instead of turning distant/subpixel paint into glare.
    return max(max(edge,center)*min(1.0,0.45/(2.0*aa)),numbers*min(1.0,1.5/(2.0*aa)));
}
void fragment() {
    // This canonical heightfield's authored lighting normals face world-up.
    // Keep two-sided rasterization without letting back-face shading invert
    // that hemisphere. Vertex positions, topology and contact stay unchanged.
    vec3 world_up_view=normalize((VIEW_MATRIX*vec4(0.0,1.0,0.0,0.0)).xyz);
    if(dot(NORMAL,world_up_view)<0.0) NORMAL=-NORMAL;
    bool a=in_ring(canonical_xz,0); bool b=in_ring(canonical_xz,1);
    vec3 pigment=ground_color;
    if(a) pigment=color0;
    if(b && (!a || second_wins)) pigment=color1;
    // Opaque pigment only on the existing winning pavement. No overlay mesh,
    // displacement, alpha material, native normal or physical marking claim.
    float aa=max(0.0001,0.5*max(fwidth(canonical_xz.x),fwidth(canonical_xz.y)));
    float paint=0.0;
    if(b && (!a || second_wins)) paint=runway_paint(canonical_xz,paint_ends1,paint_axes1,paint_size1,paint_numbers1,paint_digits1,aa);
    else if(a) paint=runway_paint(canonical_xz,paint_ends0,paint_axes0,paint_size0,paint_numbers0,paint_digits0,aa);
    pigment=mix(pigment,vec3(0.9),paint);
    float variation=1.0+0.035*sin(canonical_xz.x*0.025)*sin(canonical_xz.y*0.021);
    ALBEDO=pigment*(a||b?1.0:variation);
    ROUGHNESS=1.0;
}
"""

var _initialized: bool=false
var _grid: RefCounted
var _metadata: Dictionary={}
var _geometry: Dictionary={}
var _up: PackedByteArray=PackedByteArray()
var _valid: PackedByteArray=PackedByteArray()
var _anchor: Array=[]
var _rotation: Array=[]
var _session: String=""
var _chunks: Array=[]
var _mesh_ids: Array=[]
var _last_version: String="0"
var _offset: Array=[0.0,0.0,0.0]
var _committed: bool=false
var _prepared: Variant=null
var _prepared_hierarchy: Dictionary={}

static func _failure(error: String="Invalid or incompatible KAWO terrain presentation") -> Dictionary:
	return {"ok":false,"error":error,"root":null}

static func _scalars(value: Variant,count: int) -> bool:
	if not value is Array or value.size()!=count: return false
	for scalar in value:
		if typeof(scalar)!=TYPE_FLOAT or not is_finite(scalar): return false
	return true

static func _same(a: Array,b: Array) -> bool:
	if a.size()!=b.size(): return false
	for i in a.size():
		if not Reader._same_float(a[i],b[i]): return false
	return true

static func _tag(value: Variant) -> Dictionary:
	if not Reader._keys(value,["$binary64_le"]) or not Reader._hex(value["$binary64_le"],16): return {"ok":false,"value":null}
	var bytes: PackedByteArray=value["$binary64_le"].hex_decode()
	var number: float=bytes.decode_double(0)
	return {"ok":is_finite(number),"value":number}

static func _millimetre_ring(value: Variant) -> Array:
	# JSON integer tokens arrive as TYPE_FLOAT in Godot. Only this enumerated
	# serialized integer position accepts exact integral parsed numbers. No
	# session/camera/frame coercion, snapping, B64-tag conversion or ring repair.
	if not value is Array or value.size()!=4: return []
	var result: Array=[]
	for point in value:
		if not point is Array or point.size()!=2: return []
		var owned: Array=[]
		for coordinate in point:
			if typeof(coordinate) not in [TYPE_INT,TYPE_FLOAT]: return []
			if not is_finite(float(coordinate)) or absf(float(coordinate))>8192000.0 or float(coordinate)!=floor(float(coordinate)): return []
			owned.append(int(coordinate))
		result.append(owned)
	return result

static func _geometry_valid(value: Variant,meta: Dictionary,polygons: Array) -> bool:
	if not Reader._keys(value,["schema","source_airport_sha256","ground_payload_sha256","world_anchor","position_frame","bearing_reference","runways"]): return false
	if typeof(value.schema)!=TYPE_STRING or value.schema!="CompiledAirportGeometry/v1" or not Reader._hex(value.source_airport_sha256,64) or value.ground_payload_sha256!=meta.payload_sha256 or value.position_frame!="anchor-eus-metres" or value.bearing_reference!="published-geographic-true-degrees": return false
	if not Reader._keys(value.world_anchor,["latitude_rad","longitude_rad","ellipsoid_height_m"]): return false
	for key in meta.world_anchor:
		var number: Dictionary=_tag(value.world_anchor[key])
		if not number.ok or not Reader._same_float(number.value,meta.world_anchor[key]): return false
	if not value.runways is Array or value.runways.size()!=2 or polygons.size()!=2: return false
	var ids: Array=["kawo.runway.11-29","kawo.runway.16-34"]
	var ends: Array=[["11","29"],["16","34"]]
	for i in 2:
		var runway: Variant=value.runways[i]
		if not Reader._keys(runway,["id","material_polygon_id","published_length_m","width_m","footprint_mm","ends"]) or typeof(runway.id)!=TYPE_STRING or runway.id!=ids[i] or runway.material_polygon_id!=ids[i]: return false
		for key in ["published_length_m","width_m"]:
			var number: Dictionary=_tag(runway[key])
			if not number.ok or number.value<=0.0: return false
		var ring: Array=_millimetre_ring(runway.footprint_mm)
		if ring.is_empty(): return false
		var found: bool=false
		for polygon in polygons:
			if polygon.id==ids[i]:
				if polygon.vertices_mm!=ring: return false
				found=true
		if not found: return false
		# The pigment shader requires convex compiled rings, without repairing them.
		for j in 4:
			if Reader._orientation(ring[j],ring[(j+1)%4],ring[(j+2)%4])>=0: return false
		if not runway.ends is Array or runway.ends.size()!=2: return false
		for j in 2:
			var end: Variant=runway.ends[j]
			if not Reader._keys(end,["designator","eus_m","published_true_bearing_deg"]) or typeof(end.designator)!=TYPE_STRING or end.designator!=ends[i][j] or not end.eus_m is Array or end.eus_m.size()!=3: return false
			for scalar in end.eus_m:
				var number: Dictionary=_tag(scalar)
				if not number.ok or absf(number.value)>8192.0: return false
			var bearing: Dictionary=_tag(end.published_true_bearing_deg)
			if not bearing.ok or bearing.value<0.0 or bearing.value>=360.0: return false
	return true

static func _color(id: String) -> Color:
	if id=="original.asphalt": return Color(0.16,0.17,0.17)
	if id in ["original.grass","original.terrain-prototype"]: return Color(0.21,0.28,0.13)
	return Color(0.34,0.29,0.20)

static func _paint_upload_finite(values: Array) -> bool:
	# Shader uniforms use Float32 even though geometry calculations use binary64.
	# Test the actual narrowing, without clamping or adding a new airport extent.
	for value in values:
		if typeof(value)!=TYPE_FLOAT or not is_finite(value): return false
	var narrowed:=PackedFloat32Array(values)
	for value in narrowed:
		if not is_finite(value): return false
	return true

static func _paint_frame(a: Array,b: Array,width_m: float,designators: Array,id: String) -> Dictionary:
	# Original-art feasibility, not operational dimensions or a new source API.
	if not _scalars(a,3) or not _scalars(b,3) or not is_finite(width_m) or width_m<19.45: return {}
	var expected: Array=[]
	if id=="kawo.runway.11-29": expected=["11","29"]
	elif id=="kawo.runway.16-34": expected=["16","34"]
	if expected.is_empty() or designators.size()!=2: return {}
	for i in 2:
		if typeof(designators[i])!=TYPE_STRING or designators[i]!=expected[i]: return {}
	var dx: float=b[0]-a[0]
	var dz: float=b[2]-a[2]
	var length_m: float=sqrt(dx*dx+dz*dz)
	if not is_finite(length_m) or length_m<=180.0: return {}
	var forward: Array=[dx/length_m,dz/length_m]
	var right: Array=[-forward[1],forward[0]]
	var bottoms: Array=[[a[0]+60.0*forward[0],a[2]+60.0*forward[1]],[b[0]-60.0*forward[0],b[2]-60.0*forward[1]]]
	if not _paint_upload_finite([a[0],a[2],b[0],b[2],length_m,width_m]+forward+right+bottoms[0]+bottoms[1]): return {}
	var digits: Array=[]
	for label in designators:
		digits.append(label.unicode_at(0)-48)
		digits.append(label.unicode_at(1)-48)
	return {"id":id,"ends":[[a[0],a[2]],[b[0],b[2]]],"forward":forward,"right":right,"length_m":length_m,"width_m":width_m,"number_bottoms":bottoms,"digits":digits}

static func _paint_layout(runways: Array,polygons: Array) -> Array:
	# Called after the unchanged full geometry admission. Associate through ID,
	# never through coincidental polygon storage order or published bearing.
	if runways.size()!=2 or polygons.size()!=2: return []
	var frames: Array=[]
	for polygon in polygons:
		var matched: Array=[]
		for runway in runways:
			if runway.id==polygon.id: matched.append(runway)
		if matched.size()!=1: return []
		var runway: Dictionary=matched[0]
		var width: Dictionary=_tag(runway.width_m)
		if not width.ok: return []
		var ends: Array=[]
		var names: Array=[]
		for end in runway.ends:
			var position: Array=[]
			for raw in end.eus_m:
				var scalar: Dictionary=_tag(raw)
				if not scalar.ok: return []
				position.append(scalar.value)
			ends.append(position)
			names.append(end.designator)
		if ends.size()!=2: return []
		var frame: Dictionary=_paint_frame(ends[0],ends[1],width.value,names,runway.id)
		if frame.is_empty(): return []
		frames.append(frame)
	if frames[0].id==frames[1].id: return []
	return frames

static func _material(polygons: Array,materials: Array,default_index: int,paint: Array) -> ShaderMaterial:
	var shader:=Shader.new()
	shader.code=SHADER_SOURCE
	var material:=ShaderMaterial.new()
	material.shader=shader
	for i in 2:
		var ring:=PackedVector2Array()
		for point in polygons[i].vertices_mm:
			ring.append(Vector2(float(point[0])/1000.0,float(point[1])/1000.0))
		material.set_shader_parameter("ring"+str(i),ring)
		material.set_shader_parameter("color"+str(i),_color(materials[polygons[i].material_index].id))
		var frame: Dictionary=paint[i]
		material.set_shader_parameter("paint_ends"+str(i),Vector4(frame.ends[0][0],frame.ends[0][1],frame.ends[1][0],frame.ends[1][1]))
		material.set_shader_parameter("paint_axes"+str(i),Vector4(frame.forward[0],frame.forward[1],frame.right[0],frame.right[1]))
		material.set_shader_parameter("paint_size"+str(i),Vector2(frame.length_m,frame.width_m))
		material.set_shader_parameter("paint_numbers"+str(i),Vector4(frame.number_bottoms[0][0],frame.number_bottoms[0][1],frame.number_bottoms[1][0],frame.number_bottoms[1][1]))
		material.set_shader_parameter("paint_digits"+str(i),Vector4i(frame.digits[0],frame.digits[1],frame.digits[2],frame.digits[3]))
	material.set_shader_parameter("ground_color",_color(materials[default_index].id))
	material.set_shader_parameter("second_wins",polygons[1].priority>polygons[0].priority or (polygons[1].priority==polygons[0].priority and polygons[1].id<polygons[0].id))
	return material

static func _indices() -> PackedInt32Array:
	var indices:=PackedInt32Array()
	indices.resize(24576)
	var cursor: int=0
	for row in 64:
		for col in 64:
			var n: int=row*65+col
			for index in [n,n+65,n+66,n,n+66,n+1]:
				indices[cursor]=index
				cursor+=1
	return indices

static func _chunk_arrays(values: PackedFloat32Array,meta: Dictionary,chunk_column: int,chunk_row: int,indices: PackedInt32Array) -> Array:
	var vertices:=PackedVector3Array()
	var normals:=PackedVector3Array()
	vertices.resize(4225)
	normals.resize(4225)
	for row in 65:
		var r: int=chunk_row*64+row
		for col in 65:
			var c: int=chunk_column*64+col
			var n: int=r*meta.columns+c
			var x: float=meta.east_origin_m+float(c*meta.spacing_m)
			var z: float=meta.south_origin_m+float(r*meta.spacing_m)
			vertices[row*65+col]=Vector3(x,values[n],z)
			# Lighting only: same global neighboring source addresses on all copies.
			# Canonical coordinates/indices are untouched and no native normal claimed.
			var left: int=maxi(c-1,0)
			var right: int=mini(c+1,meta.columns-1)
			var north: int=maxi(r-1,0)
			var south: int=mini(r+1,meta.rows-1)
			var dx: float=(float(values[r*meta.columns+right])-float(values[r*meta.columns+left]))/float((right-left)*meta.spacing_m)
			var dz: float=(float(values[south*meta.columns+c])-float(values[north*meta.columns+c]))/float((south-north)*meta.spacing_m)
			normals[row*65+col]=Vector3(-dx,1.0,-dz).normalized()
	var arrays: Array=[]
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX]=vertices
	arrays[Mesh.ARRAY_NORMAL]=normals
	arrays[Mesh.ARRAY_INDEX]=indices
	return arrays

static func prepare(grid: Variant,compiled_geometry: Variant,session_id: Variant,anchor_ecef: Variant,rotation: Variant) -> Dictionary:
	if not Thread.is_main_thread() or not Reader._environment() or not grid is Reader.DecodedGrid or not grid._admitted or typeof(session_id)!=TYPE_STRING or not _scalars(anchor_ecef,3) or not _scalars(rotation,9) or not Frames.rigid(rotation): return _failure()
	var meta: Dictionary=grid.metadata()
	if meta.columns!=3073 or meta.rows!=2049 or meta.spacing_m!=4 or meta.east_origin_m!= -6144.0 or meta.south_origin_m!= -4096.0: return _failure()
	var expected: Dictionary=Frames.anchor(meta.world_anchor.latitude_rad,meta.world_anchor.longitude_rad,meta.world_anchor.ellipsoid_height_m)
	if expected.is_empty() or not _same(expected.ecef,anchor_ecef) or not _same(expected.rotation,rotation): return _failure()
	var polygons: Array=grid.copy_polygons()
	if not _geometry_valid(compiled_geometry,meta,polygons): return _failure()
	var paint: Array=_paint_layout(compiled_geometry.runways,polygons)
	if paint.size()!=2: return _failure("Invalid original prototype runway paint layout")
	var valid: PackedByteArray=grid.copy_valid_words()
	var count: int=meta.columns*meta.rows
	for i in count/8:
		if valid[i]!=255: return _failure("KAWO presentation requires the complete compiled grid")
	if count%8!=0 and valid[count/8]!=(1<<(count%8))-1: return _failure("KAWO presentation requires the complete compiled grid")
	var up: PackedByteArray=grid.copy_up_words()
	var values: PackedFloat32Array=up.to_float32_array()
	var indices: PackedInt32Array=_indices()
	var root:=KawoWorld.new()
	root.name="KawoPrototypeTerrain"
	root.visible=false
	root._grid=grid
	root._metadata=meta
	root._geometry=compiled_geometry.duplicate(true)
	for runway in root._geometry.runways:
		runway.footprint_mm=_millimetre_ring(runway.footprint_mm)
	root._up=up
	root._valid=valid
	root._anchor=anchor_ecef.duplicate(true)
	root._rotation=rotation.duplicate(true)
	var material: ShaderMaterial=_material(polygons,grid.copy_materials(),meta.default_material_index,paint)
	for row in 32:
		for col in 48:
			var mesh:=ArrayMesh.new()
			mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,_chunk_arrays(values,meta,col,row,indices),[],{},0)
			if mesh.get_surface_count()!=1:
				root.free()
				return _failure("Unable to prepare canonical terrain mesh")
			mesh.surface_set_material(0,material)
			var chunk:=MeshInstance3D.new()
			chunk.name="Terrain_%02d_%02d"%[row,col]
			chunk.mesh=mesh
			chunk.visibility_range_begin=0.0
			chunk.visibility_range_end=0.0
			root.add_child(chunk)
			root._chunks.append(chunk)
			root._mesh_ids.append(mesh.get_instance_id())
	root._initialized=true
	if not session_id.is_empty():
		var bound: Dictionary=root.bind_session(session_id)
		if not bound.ok:
			root.free()
			return _failure()
	return {"ok":true,"error":"","root":root}

func bind_session(value: Variant) -> Dictionary:
	if not Thread.is_main_thread() or not _initialized or is_queued_for_deletion() or typeof(value)!=TYPE_STRING or value.is_empty() or not _session.is_empty() or get_parent()!=null or is_inside_tree() or _prepared!=null or _committed: return {"ok":false,"error":"Invalid or repeated provisional world binding"}
	_session=value
	return {"ok":true,"error":""}

func source_binding() -> Dictionary:
	return {"session_id":_session,"payload_sha256":_metadata.get("payload_sha256",""),"world_anchor":_metadata.get("world_anchor",{}).duplicate(true),"anchor_ecef_m":_anchor.duplicate(true),"ecef_to_eus":_rotation.duplicate(true)}

func _hierarchy() -> Dictionary:
	if not _initialized or is_queued_for_deletion() or not is_inside_tree() or top_level or basis!=Basis.IDENTITY or not transform.is_finite() or position!=Vector3(_offset[0],_offset[1],_offset[2]) or get_child_count()!=1536: return {}
	var parents: Array=[]
	var parent: Node=get_parent()
	while parent!=null:
		if not is_instance_valid(parent) or parent.is_queued_for_deletion(): return {}
		if parent is Node3D:
			if parent.top_level or parent.transform!=Transform3D.IDENTITY: return {}
		parents.append(parent.get_instance_id())
		parent=parent.get_parent()
	for i in _chunks.size():
		var chunk: Variant=_chunks[i]
		if not is_instance_valid(chunk) or chunk.is_queued_for_deletion() or get_child(i)!=chunk or not chunk is MeshInstance3D or chunk.top_level or chunk.transform!=Transform3D.IDENTITY or chunk.mesh==null or chunk.mesh.get_instance_id()!=_mesh_ids[i] or chunk.mesh.get_surface_count()!=1: return {}
	return {"parents":parents,"root_id":get_instance_id(),"offset":_offset.duplicate(true)}

func _origin_failure(value: Variant,error: String) -> Dictionary:
	var version: String=value.get("version","0") if value is Dictionary and typeof(value.get("version"))==TYPE_STRING else "0"
	return {"ok":false,"error":error,"session_id":_session,"version":version,"data":null}

func prepare_origin(candidate: Variant) -> Dictionary:
	if not Thread.is_main_thread(): return _origin_failure(candidate,"Terrain origin requires main thread")
	_prepared=null
	_prepared_hierarchy={}
	if not Thread.is_main_thread() or not Reader._environment() or _session.is_empty() or not Reader._keys(candidate,CANDIDATE_KEYS) or typeof(candidate.session_id)!=TYPE_STRING or candidate.session_id!=_session or not _scalars(candidate.origin_ecef_m,3) or not _scalars(candidate.ecef_to_eus,9) or not _same(candidate.ecef_to_eus,_rotation) or not UInt64.valid(candidate.version) or UInt64.compare(candidate.version,_last_version)<=0: return _origin_failure(candidate,"Malformed, unbound or stale terrain origin")
	var hierarchy: Dictionary=_hierarchy()
	if hierarchy.is_empty(): return _origin_failure(candidate,"Terrain hierarchy changed or retired")
	# Same fixed canonical frame and explicitly stored binary64 dot grouping.
	var offset: Array=[]
	var d0: float=_anchor[0]-candidate.origin_ecef_m[0]
	var d1: float=_anchor[1]-candidate.origin_ecef_m[1]
	var d2: float=_anchor[2]-candidate.origin_ecef_m[2]
	for row in 3:
		var t0: float=d0*_rotation[row*3]
		var t1: float=d1*_rotation[row*3+1]
		var s01: float=t0+t1
		var t2: float=d2*_rotation[row*3+2]
		var result: float=s01+t2
		if not is_finite(result) or absf(result)>16384.0: return _origin_failure(candidate,"Terrain presentation offset outside fixed domain")
		offset.append(result)
	_prepared_hierarchy=hierarchy
	_prepared={"ok":true,"error":"","session_id":_session,"version":candidate.version,"data":{"offset_eus_m":offset,"origin_ecef_m":candidate.origin_ecef_m.duplicate(true)}}
	return _prepared.duplicate(true)

func commit_origin(plan: Variant) -> Dictionary:
	if not Thread.is_main_thread() or not Reader._environment(): return {"ok":false,"error":"Unsupported terrain commit thread or floating environment"}
	var prepared: Variant=_prepared
	_prepared=null
	if not Thread.is_main_thread() or prepared==null or not plan is Dictionary or plan!=prepared or _session.is_empty() or _hierarchy()!=_prepared_hierarchy:
		_prepared_hierarchy={}
		return {"ok":false,"error":"Stale, mutated or retired terrain origin plan"}
	_prepared_hierarchy={}
	_offset=prepared.data.offset_eus_m.duplicate(true)
	position=Vector3(_offset[0],_offset[1],_offset[2])
	_last_version=prepared.version
	_committed=true
	return {"ok":true,"error":""}

# Error-free binary64 expansions preserve exact cell/diagonal ownership even
# when subtracting a common translation would round a tiny offset onto an edge.
# This is presentation geometry, not a geodetic/native SurfaceProvider query.
static func _expansion(terms: Array) -> Array:
	var result: Array=[]
	for term in terms:
		var q: float=term
		var next: Array=[]
		for component in result:
			var sum: float=q+component
			var virtual: float=sum-q
			var error: float=(q-(sum-virtual))+(component-virtual)
			if error!=0.0: next.append(error)
			q=sum
		if q!=0.0 or next.is_empty(): next.append(q)
		result=next
	return result

static func _sign(terms: Array) -> int:
	var exact: Array=_expansion(terms)
	var top: float=exact[-1]
	return -1 if top<0.0 else (1 if top>0.0 else 0)

func _cell(render: float,offset: float,origin: float,count: int) -> int:
	var low: int=0
	var high: int=count-1
	if _sign([render,-offset,-origin])<0 or _sign([render,-offset,-(origin+float((count-1)*4))])>=0: return -1
	while low+1<high:
		var middle: int=(low+high)/2
		if _sign([render,-offset,-(origin+float(middle*4))])>=0: low=middle
		else: high=middle
	return low

static func _facet_height(y00: float,y10: float,y01: float,y11: float,x: float,z: float,triangle_zero: bool) -> float:
	if triangle_zero: return y00+(x*(y11-y01)+z*(y01-y00))/4.0
	return y00+(x*(y10-y00)+z*(y11-y10))/4.0

func camera_height(render_east_m: Variant,render_south_m: Variant) -> Dictionary:
	var failure: Dictionary={"ok":false,"error":"Terrain camera query unavailable or outside canonical geometry","height_m":null}
	if not Thread.is_main_thread() or not Reader._environment() or not _committed or _session.is_empty() or typeof(render_east_m)!=TYPE_FLOAT or typeof(render_south_m)!=TYPE_FLOAT or not is_finite(render_east_m) or not is_finite(render_south_m) or absf(render_east_m)>32768.0 or absf(render_south_m)>32768.0 or _hierarchy().is_empty(): return failure
	var col: int=_cell(render_east_m,_offset[0],_metadata.east_origin_m,_metadata.columns)
	var row: int=_cell(render_south_m,_offset[2],_metadata.south_origin_m,_metadata.rows)
	if col<0 or row<0: return failure
	var i: int=row*_metadata.columns+col
	for n in [i,i+1,i+_metadata.columns,i+_metadata.columns+1]:
		if not Reader._valid(_valid,n): return failure
	var x0: float=_metadata.east_origin_m+float(col*4)
	var z0: float=_metadata.south_origin_m+float(row*4)
	var east: Array=_expansion([render_east_m,-_offset[0],-x0])
	var south: Array=_expansion([render_south_m,-_offset[2],-z0])
	var x: float=0.0
	var z: float=0.0
	for term in east: x+=term
	for term in south: z+=term
	var y00: float=Reader._height(_up,i)
	var y10: float=Reader._height(_up,i+1)
	var y01: float=Reader._height(_up,i+_metadata.columns)
	var y11: float=Reader._height(_up,i+_metadata.columns+1)
	var triangle_zero: bool=_sign([render_south_m,-_offset[2],-z0,-render_east_m,_offset[0],x0])>=0
	var height: float=_facet_height(y00,y10,y01,y11,x,z,triangle_zero)
	var rendered: float=height+_offset[1]
	if not is_finite(rendered): return failure
	return {"ok":true,"error":"","height_m":rendered}
