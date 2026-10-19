extends RefCounted
# Original MIT. CPU geometry-to-uniform checks against independently frozen
# synthetic controls. Shader pigment samples remain actual GPU observations.
const World=preload("res://world/terrain/kawo_world.gd")
const CONTROL_SHA="150f64031548bbbe38930c842315dacb89513dd857184ae79e8cad6467c78a18"
var checks: int=0
var failures: Array=[]
var _mode: String=""
var _material_active: bool=false
var _groups: Dictionary={"geometry":{"checks":0,"failures":[]},"material":{"checks":0,"failures":[]}}

func check(good: bool,name: String) -> void:
	checks+=1
	var group: Dictionary=_groups.material if _material_active else _groups.geometry
	group.checks+=1
	if not good and group.failures.size()<32: group.failures.append(name)
	if not good and failures.size()<32: failures.append(name)

func _tag(value: float) -> Dictionary:
	var bytes:=PackedByteArray()
	bytes.resize(8)
	bytes.encode_double(0,value)
	return {"$binary64_le":bytes.hex_encode()}

func _runway(fixture: Dictionary) -> Dictionary:
	var ends: Array=[]
	for i in 2:
		var p: Array=fixture.physical_ends_xz_m[i]
		ends.append({"designator":fixture.designators[i],"eus_m":[_tag(float(p[0])),_tag(0.0),_tag(float(p[1]))],"published_true_bearing_deg":_tag(0.0)})
	# Deliberately independent published length: layout must use actual endpoints.
	return {"id":fixture.id,"material_polygon_id":fixture.id,"published_length_m":_tag(7.0),"width_m":_tag(float(fixture.width_m)),"footprint_mm":fixture.footprint_mm.duplicate(true),"ends":ends}

func _frame(fixture: Dictionary) -> Dictionary:
	var a: Array=fixture.physical_ends_xz_m[0]
	var b: Array=fixture.physical_ends_xz_m[1]
	return World._paint_frame([float(a[0]),0.0,float(a[1])],[float(b[0]),0.0,float(b[1])],float(fixture.width_m),fixture.designators,fixture.id)

func _near(actual: Array,expected: Array,name: String,tolerance: float=1.0e-9) -> void:
	check(actual.size()==expected.size(),name+"_size")
	if actual.size()!=expected.size(): return
	for i in actual.size(): check(absf(float(actual[i])-float(expected[i]))<=tolerance,name+"_"+str(i))

func _point(origin: Array,forward: Array,right: Array,q: float,lateral: float) -> Array:
	return [origin[0]+q*forward[0]+lateral*right[0],origin[1]+q*forward[1]+lateral*right[1]]

func _fixture(fixtures: Dictionary,name: String) -> Dictionary:
	if name=="crossing.vertical": return fixtures.crossing.vertical
	return fixtures[name]

func run(mode: String) -> Dictionary:
	if mode not in ["geometry","material"]:
		check(false,"explicit_geometry_or_material_mode_required")
		return _finish(false)
	_mode=mode
	if _mode=="material" and DisplayServer.get_name()=="headless":
		check(false,"material_mode_requires_real_renderer")
		return _finish(false)
	var path: String="res://runway_paint_tests/controls-v1.json"
	check(FileAccess.get_sha256(path)==CONTROL_SHA,"frozen_independent_controls")
	var controls: Variant=JSON.parse_string(FileAccess.get_file_as_string(path))
	if not controls is Dictionary or not controls.has("fixtures") or not controls.has("cases"):
		check(false,"read_controls")
		return _finish(false)
	var fixtures: Dictionary=controls.fixtures
	for entry in controls.cases:
		if entry.id.ends_with("frame") or entry.id=="translated-three-four-five-frames":
			var frame: Dictionary=_frame(_fixture(fixtures,entry.fixture))
			check(not frame.is_empty(),entry.id+"_admitted")
			if frame.is_empty(): continue
			for i in 2:
				var sign_value: float=1.0 if i==0 else -1.0
				_near([frame.length_m],[entry.expected[i].length_m],entry.id+"_length")
				_near([sign_value*frame.forward[0],sign_value*frame.forward[1]],entry.expected[i].inward_xz,entry.id+"_forward"+str(i))
				_near([sign_value*frame.right[0],sign_value*frame.right[1]],entry.expected[i].right_xz,entry.id+"_right"+str(i))
		elif entry.id in ["axis-numbers-face-each-inward-pilot","rotated-number-orientation-and-centering","other-two-identifiers-face-their-inward-pilots"]:
			var frame: Dictionary=_frame(_fixture(fixtures,entry.fixture))
			check(not frame.is_empty(),entry.id+"_admitted")
			if frame.is_empty(): continue
			for i in 2:
				var sign_value: float=1.0 if i==0 else -1.0
				var forward: Array=[sign_value*frame.forward[0],sign_value*frame.forward[1]]
				var right: Array=[sign_value*frame.right[0],sign_value*frame.right[1]]
				var expected: Dictionary=entry.expected[i]
				_near(frame.number_bottoms[i],expected.bottom_center_xz_m,entry.id+"_bottom"+str(i))
				_near(_point(frame.number_bottoms[i],forward,right,12.0,0.0),expected.top_center_xz_m,entry.id+"_top"+str(i))
				_near(_point(frame.number_bottoms[i],forward,right,6.0,-4.75),expected.first_digit_center_xz_m,entry.id+"_first"+str(i))
				_near(_point(frame.number_bottoms[i],forward,right,6.0,4.75),expected.second_digit_center_xz_m,entry.id+"_second"+str(i))
		elif entry.has("expected_layout_admissible"):
			_dimension(entry,entry.expected_layout_admissible)
		elif entry.id=="invalid-layout-dimensions-refuse-before-adoption":
			for sample in entry.samples: _dimension(sample,false)
	var horizontal: Dictionary=_runway(fixtures.crossing.horizontal)
	var vertical: Dictionary=_runway(fixtures.crossing.vertical)
	var runways: Array=[horizontal,vertical]
	var original: Array=runways.duplicate(true)
	for reversed_order in [false,true]:
		var polygons: Array=[]
		for runway in ([vertical,horizontal] if reversed_order else runways):
			polygons.append({"id":runway.id,"vertices_mm":runway.footprint_mm,"material_index":0,"priority":20 if runway.id==vertical.id else 10})
		var paint: Array=World._paint_layout(runways,polygons)
		check(paint.size()==2,"id_mapped_layout")
		if paint.size()!=2: continue
		for i in 2:
			check(paint[i].id==polygons[i].id,"polygon_slot_keeps_id")
			check(paint[i].digits==([1,1,2,9] if polygons[i].id==horizontal.id else [1,6,3,4]),"exact_physical_end_identifiers")
		if _mode=="material": _material(polygons,paint)
	check(runways==original,"geometry_and_tags_unchanged")
	check(World._paint_layout([horizontal,horizontal],[{"id":horizontal.id},{"id":vertical.id}]).is_empty(),"duplicate_or_missing_runway_refused")
	check(World._paint_frame([0.0,0.0,0.0],[0.0,0.0,1000.0],24.0,["16","34"],horizontal.id).is_empty(),"crossed_identifier_refused")
	check(World._paint_frame([0.0,0.0,0.0],[0.0,0.0,1000.0],INF,["11","29"],horizontal.id).is_empty(),"nonfinite_width_refused")
	# API-invalid controls are separate from the immutable20 independent cases.
	check(World._paint_frame([0.0,0.0,0.0],[0.0,0.0,1000.0],1.0e40,["11","29"],horizontal.id).is_empty(),"finite_width_float32_overflow_refused")
	check(World._paint_frame([1.0e40,0.0,0.0],[1.0e40,0.0,1000.0],24.0,["11","29"],horizontal.id).is_empty(),"finite_endpoint_float32_overflow_refused")
	check(World._paint_frame([0.0,0.0,0.0],[0.0,0.0,1.0e40],24.0,["11","29"],horizontal.id).is_empty(),"finite_length_float32_overflow_refused")
	check(not World._paint_frame([1.0e20,0.0,0.0],[1.0e20,0.0,1000.0],24.0,["11","29"],horizontal.id).is_empty(),"finite_upload_not_arbitrarily_clamped")
	return _finish(_groups.material.checks>0)

func _dimension(sample: Dictionary,expected: bool) -> void:
	var a: Array=sample.physical_ends_xz_m[0]
	var b: Array=sample.physical_ends_xz_m[1]
	var frame: Dictionary=World._paint_frame([float(a[0]),0.0,float(a[1])],[float(b[0]),0.0,float(b[1])],float(sample.width_m),["11","29"],"kawo.runway.11-29")
	check((not frame.is_empty())==expected,"visual_feasibility_guard")

func _material(polygons: Array,paint: Array) -> void:
	_material_active=true
	var material: ShaderMaterial=World._material(polygons,[{"id":"original.asphalt"},{"id":"original.grass"}],1,paint)
	check(material!=null and material.shader!=null,"actual_production_material")
	if material==null:
		_material_active=false
		return
	for i in 2:
		var f: Dictionary=paint[i]
		check(material.get_shader_parameter("paint_ends"+str(i))==Vector4(f.ends[0][0],f.ends[0][1],f.ends[1][0],f.ends[1][1]),"actual_end_uniform")
		check(material.get_shader_parameter("paint_axes"+str(i))==Vector4(f.forward[0],f.forward[1],f.right[0],f.right[1]),"actual_axis_uniform")
		check(material.get_shader_parameter("paint_size"+str(i))==Vector2(f.length_m,f.width_m),"actual_dimensions_uniform")
		check(material.get_shader_parameter("paint_numbers"+str(i))==Vector4(f.number_bottoms[0][0],f.number_bottoms[0][1],f.number_bottoms[1][0],f.number_bottoms[1][1]),"actual_number_uniform")
		check(material.get_shader_parameter("paint_digits"+str(i))==Vector4i(f.digits[0],f.digits[1],f.digits[2],f.digits[3]),"actual_identifier_uniform")
	var expected: bool=polygons[1].priority>polygons[0].priority or (polygons[1].priority==polygons[0].priority and polygons[1].id<polygons[0].id)
	check(material.get_shader_parameter("second_wins")==expected,"existing_priority_uniform")
	_material_active=false

func _finish(material_readback: bool) -> Dictionary:
	return {"mode":_mode,"checks":checks,"failures":failures,"groups":_groups,"material_readback_exercised":material_readback,"shader_pixel_cases_exercised":false,"native_flight_exercised":false,"scope":"Frozen synthetic frame/box/feasibility and ID-to-uniform controls; white/gap/glyph/AA/crossing pixels require actual GPU observations"}
