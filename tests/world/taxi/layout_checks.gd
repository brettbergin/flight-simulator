extends RefCounted
# Original MIT. Independent immutable geometry references, not output goldens.
const Layout = preload("res://world/taxi/taxi_layout.gd")
const REFERENCE_PATH: String = "res://taxi_tests/reference/expected-v1.json"
const REFERENCE_SHA256: String = "9b9579b18c38ba3c1393af76798fa39b8683229fdf2eff553b1c12e0fd3ae37c"

static func receipt(scope: String) -> Dictionary:
	return {"passed":true,"checks":0,"failures":[],"scope":scope}

static func check(result: Dictionary, condition: bool, label: String) -> void:
	result.checks+=1
	if not condition:
		result.passed=false
		result.failures.append(label)

static func references(result: Dictionary) -> Dictionary:
	var raw: PackedByteArray = FileAccess.get_file_as_bytes(REFERENCE_PATH)
	var context := HashingContext.new()
	var ok: bool = not raw.is_empty() and context.start(HashingContext.HASH_SHA256)==OK and context.update(raw)==OK
	check(result,ok and context.finish().hex_encode()==REFERENCE_SHA256,"immutable_reference_raw_sha256")
	if not ok or not result.passed: return {}
	var value: Variant = JSON.parse_string(raw.get_string_from_utf8())
	check(result,typeof(value)==TYPE_DICTIONARY and value.get("schema")=="SyntheticTaxiContentReference/v1","reference_shape")
	return value if result.passed else {}

static func _fraction(text: String) -> float:
	var parts: PackedStringArray = text.split("/")
	return float(parts[0]) if parts.size()==1 else float(parts[0])/float(parts[1])

static func run() -> Dictionary:
	var result: Dictionary = receipt("Actual pure TaxiLayout admission and immutable six-rectangle/24leg/face/parking references; no flight or native proof")
	var reference: Dictionary = references(result)
	var admitted: Dictionary = Layout.load()
	check(result,admitted.ok and admitted.error=="" and admitted.value!=null,"fixed_content_load")
	if not admitted.ok or reference.is_empty(): return result
	var layout: Dictionary = admitted.value
	check(result,typeof(layout.revision)==TYPE_INT and layout.revision==1,"revision_normalized_int")
	var rectangles: Array = layout.pavement.duplicate(true)
	for link in layout.links: rectangles.append(link)
	check(result,rectangles.size()==6,"union_contains_all_three_connectors")
	for i in reference.rectangles.size():
		var actual: Dictionary = rectangles[i]
		var expected: Dictionary = reference.rectangles[i]
		check(result,actual.id==expected.id,"rectangle_identity_"+expected.id)
		for axis in 2:
			check(result,actual.center_xz_m[axis]-actual.half_extent_xz_m[axis]==_fraction(expected.minimum_xz_m[axis]) and actual.center_xz_m[axis]+actual.half_extent_xz_m[axis]==_fraction(expected.maximum_xz_m[axis]),"rectangle_exact_bounds_"+expected.id+str(axis))
	for row in reference.route_segments:
		var found: Dictionary = {}
		for itinerary in layout.itineraries:
			if itinerary.id==row.itinerary: found=itinerary
		check(result,not found.is_empty(),"route_roster_"+row.itinerary)
		if found.is_empty(): continue
		var index: int = int(row.segment)
		var a: Array = found.points[index].point_eus_m
		var b: Array = found.points[index+1].point_eus_m
		check(result,[a[0],a[2]]==row.from_xz_m and [b[0],b[2]]==row.to_xz_m,"independent_leg_"+row.itinerary+str(index))
		check(result,Layout._segment_on_pavement(a,b,rectangles)==row.inside_six_rectangle_union,"full_interval_containment_"+row.itinerary+str(index))
	for row in reference.segment_counterexamples:
		check(result,Layout._segment_on_pavement([row.p[0],0.0,row.p[1]],[row.q[0],0.0,row.q[1]],rectangles)==row.inside,"containment_counterexample_"+row.id)
	# Endpoints inside different paved pieces must not imply a paved chord.
	check(result,not Layout._segment_on_pavement([0.0,0.0,-400.0],[82.0,0.0,-400.0],rectangles),"unpaved_gap_despite_paved_endpoints")
	for i in reference.parking.size():
		var actual: Dictionary = layout.parking[i]
		var expected: Dictionary = reference.parking[i]
		check(result,actual.id==expected.id and actual.stripe_center_eus_m==expected.stripe_center_eus_m and actual.stand_point_eus_m==expected.stand_point_eus_m and actual.cap_z_m==expected.cap_z_m,"paint_and_distinct_CG_stand_"+expected.id)
	check(result,layout.parking[0].stand_point_eus_m==[108.0,0.0,18.0] and layout.parking[0].stripe_center_eus_m==[108.0,0.0,34.0],"PARK1_not_stripe_center")
	for row in reference.junction_faces:
		var site: Dictionary = {}
		for sign_row in layout.signs:
			if sign_row.id==row.site: site=sign_row
		check(result,not site.is_empty(),"junction_site_exists_"+row.site)
		if site.is_empty(): continue
		var matched: bool = false
		for face in site.faces:
			if face.normal_xz!=row.normal_xz: continue
			var labels: Array = []
			for panel in face.panels:
				labels.append(panel.label)
				if panel.role=="direction":
					var dot: float = panel.direction_xz[0]*face.normal_xz[1]-panel.direction_xz[1]*face.normal_xz[0]
					check(result,("right" if dot>0.0 else "left")==row.arrow_screen,"independent_screen_arrow_"+row.site+str(row.normal_xz))
			matched=labels==row.panel_labels_left_to_right
		check(result,matched,"both_junction_faces_"+row.site+str(row.normal_xz))
	for link in layout.links:
		check(result,link.bar_styles==["dashed","dashed","solid","solid"],"east_solid_west_dashed_"+link.id)
	var variants: Array = [1,1.0,true,"1",1.5]
	for i in variants.size():
		var changed: Dictionary = layout.duplicate(true)
		changed.revision=variants[i]
		check(result,Layout.validate(changed).ok==reference.revision_admission_recipes[i].accepted,"strict_revision_branch_"+str(i))
	var bad: Dictionary = layout.duplicate(true)
	bad.world.prepared_sha256="0".repeat(64)
	check(result,Layout.validate(bad).error=="unsupported_world","wrong_world_rejects")
	bad=layout.duplicate(true)
	bad.itineraries[0].points[0].extra=true
	check(result,not Layout.validate(bad).ok,"nested_unknown_key_rejects")
	bad=layout.duplicate(true)
	bad.links[1].id=bad.links[0].id
	check(result,not Layout.validate(bad).ok,"duplicate_link_id_rejects")
	bad=layout.duplicate(true)
	bad.signs[0].faces[0].panels[1].direction_xz=[1.0,0.0]
	check(result,not Layout.validate(bad).ok,"wrong_direction_rejects")
	bad=layout.duplicate(true)
	bad.starts[0].requested_cg_eus_m[2]=34.0
	check(result,not Layout.validate(bad).ok,"old_paint_center_not_new_spawn")
	bad=layout.duplicate(true)
	bad.itineraries[1].points[0].point_eus_m[0]=NAN
	check(result,not Layout.validate(bad).ok,"nonfinite_rejects")
	var before: Dictionary = layout.duplicate(true)
	var copy: Dictionary = Layout.validate(layout).value
	copy.parking[0].label="caller mutation"
	check(result,layout==before,"normalized_result_has_owned_children")
	bad=layout.duplicate(true)
	bad.erase("frame")
	bad[StringName("frame")]=layout.frame
	check(result,not Layout.validate(bad).ok,"StringName_key_rejects")
	return result
