extends RefCounted
# Original MIT. Copied session-local itinerary; no flight or device mutators.
const Layout = preload("res://world/taxi/taxi_layout.gd")
const Readings = preload("res://cockpit/instruments/native_readings.gd")
const Frames = preload("res://simulation/canonical_frames.gd")
const Closure = preload("res://simulation/session_facade.gd")
const U64 = preload("res://simulation/uint64.gd")
const VIEW_KEYS: Array = ["layout_id","layout_revision","state","session_id","tick","qualified","paused","historical","itinerary_id","itinerary_label","runway","point_index","point_count","target_id","target_label","target_eus_m","points","planar_range_m","anchor_bearing_deg","available","aids_visible","error"]
const ERRORS: Array = ["","invalid_relationship","wrong_thread","not_configured","invalid_readback","source_unqualified","session_mismatch","not_paused","invalid_selection","no_active_itinerary"]
var _owner: int = OS.get_thread_caller_id()
var _layout: Dictionary = {}
var _session: String = ""
var _selected: int = -1
var _index: int = 0
var _ended: bool = false
var _aids: bool = false

func _foreign() -> bool:
	return not Thread.is_main_thread() or OS.get_thread_caller_id()!=_owner

func configure(layout: Variant) -> Dictionary:
	if _foreign(): return {"ok":false,"error":"wrong_thread","value":null}
	if not _session.is_empty(): return {"ok":false,"error":"invalid_relationship","value":null}
	var admitted: Dictionary = Layout.validate(layout)
	if admitted.ok: _layout=admitted.value.duplicate(true)
	return admitted

func retire() -> void:
	if _foreign(): return
	_session=""
	_selected=-1
	_index=0
	_ended=false
	_aids=false

static func _metrics(dx: float, dz: float) -> Dictionary:
	if not is_finite(dx) or not is_finite(dz): return {}
	var largest: float = maxf(absf(dx),absf(dz))
	if largest==0.0: return {"range":0.0,"bearing":null}
	var ratio: float = minf(absf(dx),absf(dz))/largest
	var distance: float = largest*sqrt(1.0+ratio*ratio)
	var bearing: float = fposmod(rad_to_deg(atan2(dx,-dz)),360.0)
	if not is_finite(distance) or distance<=0.0 or not is_finite(bearing): return {}
	return {"range":distance,"bearing":0.0 if bearing==0.0 else bearing}

static func _qualification(readback: Variant) -> Dictionary:
	var result: Dictionary = {"error":"invalid_readback","historical":false,"paused":false,"session_id":null,"tick":null,"position":null}
	var readings: Dictionary = Readings.from_readback(readback)
	if readings.state in ["empty","invalid"]: return result
	result.historical=readings.state=="historical"
	if not readings.state in ["live","paused"]: return result
	if not readback.error.is_empty() or not readback.native_fault.is_empty() or not readback.native_outcome in ["completed","paused"]: return result
	if readback.native_source_fingerprint!=Closure.NATIVE or readback.prepared_world_sha256!=Readings.WORLD:
		result.error="source_unqualified"
		return result
	var prepared: Dictionary = Frames.anchor(0.8,-2.0,0.0)
	var derived: Dictionary = Frames.derive(readback.aircraft,prepared)
	if derived.is_empty() or not Frames.finite_array(derived.anchor_eus_position_m,3): return result
	for key in ["ecef_position_m","anchor_eus_position_m","body_to_anchor_eus"]:
		var actual: Array = readback.canonical[key]
		var expected: Array = derived[key]
		if actual.size()!=expected.size(): return result
		for i in actual.size():
			if absf(float(actual[i])-float(expected[i]))>(1e-12 if key=="body_to_anchor_eus" else 1e-7): return result
	result.error=""
	result.paused=readings.state=="paused"
	result.session_id=readings.session_id
	result.tick=readings.tick
	result.position=readback.canonical.anchor_eus_position_m.duplicate(true)
	return result

func _admission(readback: Variant, require_paused: bool, require_bound: bool = true) -> String:
	if _layout.is_empty(): return "not_configured"
	var qualified: Dictionary = _qualification(readback)
	if not qualified.error.is_empty(): return qualified.error
	if require_bound and (_session.is_empty() or qualified.session_id!=_session): return "session_mismatch"
	if require_paused and not qualified.paused: return "not_paused"
	return ""

func _view(readback: Variant, error: String = "") -> Variant:
	if _layout.is_empty(): return null
	var observation: Dictionary = _qualification(readback)
	var reason: String = error if not error.is_empty() else observation.error
	if reason.is_empty() and (_session.is_empty() or observation.session_id!=_session): reason="session_mismatch"
	var qualified: bool = reason.is_empty()
	# Action refusal (invalid selection/not paused) does not invalidate genuine
	# same-session source truth. Its diagnostic still shows honest current state.
	if error in ["invalid_selection","no_active_itinerary","not_paused"]:
		qualified=observation.error.is_empty() and observation.session_id==_session and not _session.is_empty()
	var row: Dictionary = {} if _selected<0 else _layout.itineraries[_selected]
	var state: String = "empty" if row.is_empty() else ("manual-ended" if _ended else "active")
	var view: Dictionary = {"layout_id":_layout.id,"layout_revision":_layout.revision,"state":state,
		"session_id":observation.session_id if qualified else null,"tick":observation.tick if qualified else null,
		"qualified":qualified,"paused":observation.paused if qualified else false,"historical":observation.historical,
		"itinerary_id":null if row.is_empty() else row.id,"itinerary_label":null if row.is_empty() else row.label,
		"runway":null if row.is_empty() else row.runway,"point_index":_index,"point_count":0 if row.is_empty() else row.points.size(),
		"target_id":null,"target_label":null,"target_eus_m":null,"points":[],"planar_range_m":null,
		"anchor_bearing_deg":null,"available":false,"aids_visible":_aids,"error":reason}
	if not qualified or state!="active": return view
	var target: Dictionary = row.points[_index]
	var metrics: Dictionary = _metrics(float(target.point_eus_m[0])-float(observation.position[0]),float(target.point_eus_m[2])-float(observation.position[2]))
	if metrics.is_empty():
		view.qualified=false
		view.session_id=null
		view.tick=null
		view.paused=false
		view.error="invalid_readback"
		return view
	view.target_id=target.id
	view.target_label=target.label
	view.target_eus_m=target.point_eus_m.duplicate(true)
	view.points=row.points.duplicate(true)
	view.planar_range_m=metrics.range
	view.anchor_bearing_deg=metrics.bearing
	view.available=true
	return view

func _reply(error: String, readback: Variant) -> Dictionary:
	return {"ok":error.is_empty(),"error":error,"view":_view(readback,error)}

func fresh_session(readback: Variant) -> Dictionary:
	if _foreign(): return {"ok":false,"error":"wrong_thread","view":null}
	var error: String = _admission(readback,false,false)
	if not error.is_empty(): return _reply(error,readback)
	_session=readback.session_id
	_selected=-1
	_index=0
	_ended=false
	_aids=false
	return _reply("",readback)

func choose(itinerary_id: Variant, readback: Variant) -> Dictionary:
	if _foreign(): return {"ok":false,"error":"wrong_thread","view":null}
	var error: String = _admission(readback,true)
	if not error.is_empty(): return _reply(error,readback)
	var found: int = -1
	if typeof(itinerary_id)==TYPE_STRING:
		for i in _layout.itineraries.size():
			if _layout.itineraries[i].id==itinerary_id: found=i
	if found<0: return _reply("invalid_selection",readback)
	_selected=found
	_index=0
	_ended=false
	_aids=true
	return _reply("",readback)

func next(readback: Variant) -> Dictionary:
	if _foreign(): return {"ok":false,"error":"wrong_thread","view":null}
	var error: String = _admission(readback,true)
	if not error.is_empty(): return _reply(error,readback)
	if _selected<0 or _ended: return _reply("no_active_itinerary",readback)
	if _index==_layout.itineraries[_selected].points.size()-1: _ended=true
	else: _index+=1
	return _reply("",readback)

func stop(readback: Variant) -> Dictionary:
	if _foreign(): return {"ok":false,"error":"wrong_thread","view":null}
	var error: String = _admission(readback,true)
	if not error.is_empty(): return _reply(error,readback)
	_selected=-1
	_index=0
	_ended=false
	return _reply("",readback)

func set_aids_visible(value: Variant, readback: Variant) -> Dictionary:
	if _foreign(): return {"ok":false,"error":"wrong_thread","view":null}
	var error: String = _admission(readback,true)
	if not error.is_empty(): return _reply(error,readback)
	if typeof(value)!=TYPE_BOOL: return _reply("invalid_selection",readback)
	_aids=value
	return _reply("",readback)

func observe(readback: Variant) -> Variant:
	if _foreign(): return null
	return _view(readback)

static func _valid_view(value: Variant) -> bool:
	# Private defensive display boundary; no new public DTO/helper contract.
	if not Layout._keys(value,VIEW_KEYS): return false
	if typeof(value.layout_id)!=TYPE_STRING or value.layout_id!="original-taxi-navigation" or typeof(value.layout_revision)!=TYPE_INT or value.layout_revision!=1: return false
	for key in ["state","error"]:
		if typeof(value[key])!=TYPE_STRING: return false
	if not value.state in ["empty","active","manual-ended"] or not ERRORS.has(value.error): return false
	for key in ["qualified","paused","historical","available","aids_visible"]:
		if typeof(value[key])!=TYPE_BOOL: return false
	for key in ["point_index","point_count"]:
		if typeof(value[key])!=TYPE_INT or value[key]<0: return false
	if value.point_count>8 or typeof(value.points)!=TYPE_ARRAY: return false
	if value.runway!=null and (typeof(value.runway)!=TYPE_INT or not value.runway in [36,18]): return false
	for key in ["itinerary_id","itinerary_label","target_id","target_label"]:
		if value[key]!=null and not (_id(value[key]) if key.ends_with("_id") else _label(value[key])): return false
	if value.state=="empty":
		if value.itinerary_id!=null or value.itinerary_label!=null or value.runway!=null or value.point_count!=0 or value.point_index!=0: return false
	else:
		if value.itinerary_id==null or value.itinerary_label==null or value.point_count<1 or value.point_index>=value.point_count: return false
		if value.state=="manual-ended" and value.point_index!=value.point_count-1: return false
	if value.qualified:
		if not value.error in ["","invalid_selection","no_active_itinerary","not_paused"]: return false
		if value.error=="not_paused" and value.paused: return false
		if typeof(value.session_id)!=TYPE_STRING or value.session_id.is_empty() or value.session_id.length()>128 or not U64.valid(value.tick) or value.historical: return false
	else:
		if value.session_id!=null or value.tick!=null or value.paused or value.available or value.error.is_empty(): return false
	if not value.available:
		return value.target_id==null and value.target_label==null and value.target_eus_m==null and value.points.is_empty() and value.planar_range_m==null and value.anchor_bearing_deg==null and not (value.qualified and value.state=="active")
	if not value.qualified or value.state!="active" or value.target_id==null or value.target_label==null or value.points.size()!=value.point_count: return false
	if not _float_point(value.target_eus_m) or typeof(value.planar_range_m)!=TYPE_FLOAT or not is_finite(value.planar_range_m) or value.planar_range_m<0.0: return false
	if value.anchor_bearing_deg!=null and (typeof(value.anchor_bearing_deg)!=TYPE_FLOAT or not is_finite(value.anchor_bearing_deg) or value.anchor_bearing_deg<0.0 or value.anchor_bearing_deg>=360.0): return false
	if (value.planar_range_m==0.0)!=(value.anchor_bearing_deg==null): return false
	var seen: Dictionary = {}
	for point in value.points:
		if not Layout._keys(point,["id","label","point_eus_m"]) or not _id(point.id) or not _label(point.label) or seen.has(point.id.to_lower()) or not _float_point(point.point_eus_m): return false
		seen[point.id.to_lower()]=true
	var target: Dictionary = value.points[value.point_index]
	return value.target_id==target.id and value.target_label==target.label and value.target_eus_m==target.point_eus_m

static func _float_point(value: Variant) -> bool:
	if typeof(value)!=TYPE_ARRAY or value.size()!=3: return false
	for number in value:
		if typeof(number)!=TYPE_FLOAT or not is_finite(number) or absf(number)>2000.0: return false
	return value[1]==0.0

static func _id(value: Variant) -> bool:
	if typeof(value)!=TYPE_STRING or value.is_empty() or value.length()>48: return false
	for i in value.length():
		var cp: int = value.unicode_at(i)
		if not ((cp>=97 and cp<=122) or (cp>=48 and cp<=57) or cp==45): return false
	return true

static func _label(value: Variant) -> bool:
	if typeof(value)!=TYPE_STRING or value.is_empty() or value.length()>80: return false
	for i in value.length():
		var cp: int = value.unicode_at(i)
		if cp<32 or cp>126: return false
	return true
