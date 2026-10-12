extends RefCounted
# Original MIT. Prospective matrix. Coordinator drives existing actual view/scan
# paths; this fixture never requests native ticks, intent, recording or a session.
const SIZES: Array[Vector2i] = [Vector2i(960,540),Vector2i(1920,1080),Vector2i(2560,1440)]
const CONTEXTS: Array[String] = ["editor","portable","rebuilt_library"]

static func matrix() -> Array[Dictionary]:
	var rows: Array[Dictionary]=[]
	for size: Vector2i in SIZES:
		for preset: String in ["cockpit","forward_horizon","left_window","right_window","panel","outside"]:
			rows.append({"id":str(size.x)+"x"+str(size.y)+"/default/"+preset,"size":[size.x,size.y],"kind":"default","preset":preset,"fov":null,"display":"current","scan":null})
		for selection in range(6):
			rows.append({"id":str(size.x)+"x"+str(size.y)+"/scan/"+str(selection),"size":[size.x,size.y],"kind":"scan","preset":null,"fov":null,"display":"current","scan":selection})
		for preset: String in ["cockpit","panel"]:
			for fov: int in [35,90]:
				rows.append({"id":str(size.x)+"x"+str(size.y)+"/fov/"+preset+"/"+str(fov),"size":[size.x,size.y],"kind":"fov","preset":preset,"fov":fov,"display":"current","scan":null})
			for display: String in ["joined_retained","explicitly_invalid"]:
				rows.append({"id":str(size.x)+"x"+str(size.y)+"/"+display+"/"+preset,"size":[size.x,size.y],"kind":"display","preset":preset,"fov":null,"display":display,"scan":null})
	return rows

static func admit_receipt(receipt: Dictionary) -> Dictionary:
	var failures: Array[String]=[]
	var required: Array[String]=["schema","context","captures","source_identity","renderer","driver","reference_hardware","authority_snapshots_equal","saved_view_restored","native_joined","audio_joined","independent_pixel_review"]
	if receipt.size()!=required.size():failures.append("closed_receipt")
	for key: String in required:
		if not receipt.has(key):failures.append("missing_"+key)
	if not failures.is_empty():return {"passed":false,"failures":failures}
	if receipt.schema!="OriginalCockpitAssetVisualObservations/v1" or receipt.context not in CONTEXTS:failures.append("context_schema")
	for key: String in ["authority_snapshots_equal","saved_view_restored","native_joined","audio_joined"]:
		if typeof(receipt[key])!=TYPE_BOOL or receipt[key]!=true:failures.append(key)
	for key: String in ["source_identity","renderer","driver","reference_hardware"]:
		if typeof(receipt[key])!=TYPE_DICTIONARY or receipt[key].is_empty():failures.append("observed_"+key)
	if typeof(receipt.captures)!=TYPE_ARRAY or receipt.captures.size()!=60:
		failures.append("exact60_actual_captures")
	else:
		var expected: Array[Dictionary]=matrix()
		for i in range(60):
			var capture=receipt.captures[i]
			if typeof(capture)!=TYPE_DICTIONARY or capture.size()!=5 or not capture.has_all(["fixture","image","actual_dimensions","qualified_publication","joined_before_synthetic"]):
				failures.append("closed_capture_"+str(i));continue
			if capture.fixture!=expected[i] or capture.actual_dimensions!=expected[i].size or typeof(capture.qualified_publication)!=TYPE_BOOL or not capture.qualified_publication:
				failures.append("actual_fixture_source_dimensions_"+str(i))
			if typeof(capture.joined_before_synthetic)!=TYPE_BOOL or (expected[i].display!="current" and not capture.joined_before_synthetic):failures.append("synthetic_only_after_join_"+str(i))
			if typeof(capture.image)!=TYPE_DICTIONARY or capture.image.size()!=3 or not capture.image.has_all(["path","bytes","sha256"]) or typeof(capture.image.path)!=TYPE_STRING or capture.image.path.is_empty() or typeof(capture.image.bytes)!=TYPE_INT or capture.image.bytes<=0 or typeof(capture.image.sha256)!=TYPE_STRING or capture.image.sha256.length()!=64:
				failures.append("actual_image_pin_"+str(i))
	# Only an independent reviewer can supply actual image-by-image disposition.
	var review=receipt.independent_pixel_review
	if typeof(review)!=TYPE_DICTIONARY or not review.has_all(["approved","capture_ids","observations","scope"]) or typeof(review.approved)!=TYPE_BOOL or not review.approved or review.capture_ids.size()!=60 or review.observations.size()!=60:
		failures.append("independent_every_original_image_review_required")
	else:
		var ids: Array=[]
		for row: Dictionary in matrix():ids.append(row.id)
		if review.capture_ids!=ids:failures.append("review_exact60_ids")
	return {"schema":"OriginalCockpitVisualReceiptAdmission/v1","passed":failures.is_empty(),"failures":failures,"scope":"Receipt structure only; coordinator independently verifies raw images, source/renderer identity, snapshots, joins and reviewer authority. Dimensions or booleans alone never establish readability."}
