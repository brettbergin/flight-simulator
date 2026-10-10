extends Control
## Optional original airfield locator. Positions are the same accepted tangent
## frame used by scenery; this is not a chart, GPS instrument or flight assist.

const MAX_TRAIL := 600
const SAMPLE_TICKS := 120
const INK := Color("e8edf3")
const MUTED := Color("98afbb")
const CYAN := Color("79d7e4")
const CircuitGeometry = preload("res://world/synthetic/circuit_geometry.gd")
const U64 = preload("res://simulation/uint64.gd")
const SUMMARY_KEYS = ["session_id","tick","paused","historical","available","error","route_labels","leg_index","leg_count","target_label","target_anchor_eus_m","planar_range_m","bearing_deg","complete","active","aid_visible"]
var extent_m := 8000.0
var _session := ""
var _sample_tick := -SAMPLE_TICKS
var _trail: Array[Vector2] = []
var _position := Vector2.ZERO
var _direction := Vector2.UP
var _valid := false
var _heading_valid := false
var _paused := false
var _retained := false
var _clearance_valid := false
var _clearance_m := 0.0
var _runway := 36
var _landmarks: Array[Dictionary] = []
var _route: Dictionary={}
var _font: Font = ThemeDB.fallback_font
var _wind_cue: Dictionary={}
var _circuit: Dictionary={}
var _manual_summary: Dictionary={}
var _publication_tick: String=""
var _locator_hints: Dictionary={}
var _presentation: Dictionary={}
var _labels: Dictionary={}
var compact_aid_layout: bool=false:
	set(value):
		compact_aid_layout=value
		_refresh_presentation()

func _init() -> void:
	mouse_filter=Control.MOUSE_FILTER_IGNORE
	clip_contents=true
	for id in ["header","status","target","runway","along","height","manual","leg","footer","bindings","no_current"]:
		var label := Label.new()
		label.mouse_filter=Control.MOUSE_FILTER_PASS
		label.clip_text=true
		label.text_overrun_behavior=TextServer.OVERRUN_NO_TRIMMING
		label.add_theme_font_override("font",_font)
		label.visible=false
		add_child(label)
		_labels[id]=label

static func _number(value: Variant) -> bool:
	return typeof(value) in [TYPE_INT,TYPE_FLOAT] and is_finite(float(value))

static func _admit_summary(value: Dictionary) -> Dictionary:
	# This closed copied display admission never authorizes geographic geometry.
	if value.size()!=SUMMARY_KEYS.size(): return {}
	for key in value:
		if not key is String or not SUMMARY_KEYS.has(key): return {}
	for key in ["paused","historical","available","complete","active","aid_visible"]:
		if typeof(value[key])!=TYPE_BOOL: return {}
	if not value.error is String: return {}
	if value.session_id!=null and (not value.session_id is String or value.session_id.is_empty() or value.session_id.length()>128): return {}
	if value.tick!=null and not U64.valid(value.tick): return {}
	if (value.tick==null)!=(value.session_id==null): return {}
	if typeof(value.leg_count)!=TYPE_INT or value.leg_count<0 or value.leg_count>4 or typeof(value.leg_index)!=TYPE_INT: return {}
	if not value.route_labels is Array or value.route_labels.size()!=value.leg_count: return {}
	for label in value.route_labels:
		if not label is String or label.is_empty() or label.length()>32: return {}
	if value.leg_index<0 or (value.leg_count==0 and value.leg_index!=0) or (value.leg_count>0 and value.leg_index>=value.leg_count): return {}
	if value.complete and (value.leg_count==0 or value.leg_index!=value.leg_count-1): return {}
	if value.active!=(value.leg_count>0 and not value.complete): return {}
	if value.available:
		if value.historical or value.session_id==null or not value.error.is_empty(): return {}
		if value.active:
			if not value.target_label is String or value.target_label!=value.route_labels[value.leg_index]: return {}
			var target: Variant=value.target_anchor_eus_m
			if not target is Array or target.size()!=3: return {}
			for scalar in target:
				if not _number(scalar): return {}
			if absf(float(target[0]))>20000.0 or absf(float(target[2]))>20000.0 or float(target[1])!=0.0: return {}
			if not _number(value.planar_range_m) or float(value.planar_range_m)<0.0: return {}
			if value.bearing_deg!=null and (not _number(value.bearing_deg) or float(value.bearing_deg)<0.0 or float(value.bearing_deg)>=360.0): return {}
			return value.duplicate(true)
	# Completed, absent and noncurrent itineraries contain no recalled target.
	for key in ["target_label","target_anchor_eus_m","planar_range_m","bearing_deg"]:
		if value[key]!=null: return {}
	return value.duplicate(true)

func _summary_text() -> Dictionary:
	if _manual_summary.is_empty(): return {}
	var view: Dictionary=_manual_summary
	var metrics: String="Range / bearing unavailable"
	if view.planar_range_m!=null:
		metrics=("%.2f km / anchor %03d deg" % [view.planar_range_m/1000.0,int(roundf(view.bearing_deg))%360]) if view.bearing_deg!=null else "%.2f km / bearing unavailable" % (view.planar_range_m/1000.0)
	return {"title":view.target_label if view.target_label!=null else "Manual itinerary ended" if view.complete else "Current guidance unavailable",
		"metrics":metrics,"leg":"Leg %d / %d: %s" % [view.leg_index+1,view.leg_count," -> ".join(view.route_labels)],
		"footer":"RETAINED / NO CURRENT GUIDANCE" if view.historical else "PAUSED / select Next from the route board" if view.paused else "SYNTHETIC ANCHOR BEARING / MANUAL LEGS"}

func _set_binding_hints(value: Variant) -> void:
	_locator_hints.clear()
	for key in ["zoom_in","zoom_out","close"]:
		var fallback: Dictionary={"short":"unbound","full":"Binding unavailable; open Controls"}
		var row: Variant=value.get(key) if value is Dictionary else null
		if row is Dictionary and row.size()==2 and row.has("short") and row.has("full") and row.short is String and row.full is String and not row.short.is_empty() and not row.full.is_empty() and not "\n" in row.short and not "\r" in row.short:
			fallback=row.duplicate(true)
		_locator_hints[key]=fallback

func _hint_parts(text: String) -> Dictionary:
	var alias: String=text
	var extra: String=""
	for count in range(1,4):
		var suffix: String=" +%d alternatives" % count
		var compact_suffix: String=" +%d" % count
		if alias.ends_with(suffix) or alias.ends_with(compact_suffix):
			alias=alias.left(alias.length()-(suffix.length() if alias.ends_with(suffix) else compact_suffix.length()))
			extra=compact_suffix
			break
	var category: String=""
	if alias.begins_with("cfg "):
		category="cfg ";alias=alias.substr(4)
	elif alias.begins_with("CONFIGURED "):
		category="cfg ";alias=alias.substr(11)
	elif alias=="unbound" or alias.begins_with("Unavailable") or alias.begins_with("Binding unavailable"):
		category="unbound";alias=""
	return {"category":category,"alias":alias,"extra":extra,"shortened":false}

func _binding_footer(width: float) -> String:
	var parts: Array=[]
	for key in ["zoom_in","zoom_out","close"]:
		parts.append(_hint_parts(_locator_hints.get(key,{"short":"unbound"}).short))
	var result: String=""
	for iteration in 4096:
		var values: Array=[]
		for item in parts: values.append(item.category+item.alias+("…" if item.shortened else "")+item.extra)
		result="%.1fkm +%s −%s Close:%s" % [extent_m/1000.0,values[0],values[1],values[2]]
		if _font.get_string_size(result,HORIZONTAL_ALIGNMENT_LEFT,-1,10).x<=width: return result
		var longest: int=-1
		var largest: float=0.0
		for i in parts.size():
			var length: float=_font.get_string_size(parts[i].alias,HORIZONTAL_ALIGNMENT_LEFT,-1,10).x
			if not parts[i].alias.is_empty() and length>largest: largest=length;longest=i
		if longest<0: break
		parts[longest].alias=parts[longest].alias.left(parts[longest].alias.length()-1)
		parts[longest].shortened=true
	return result


func set_circuit_reference(view: Dictionary) -> void:
	# The pure geometry leaf owns admission. This draw layer keeps a complete
	# copied view only; it never selects a route, runway, zoom or aircraft state.
	_circuit.clear()
	if CircuitGeometry.valid_view(view) and view.available:
		_circuit=view.duplicate(true)
	queue_redraw()

static func _clip_circuit_segment(a: Vector2, b: Vector2, chart: Rect2) -> Array:
	# Intersect the full parameter interval, including crossings with both
	# endpoints outside. Final draw vectors are presentation precision only.
	if not a.is_finite() or not b.is_finite() or not chart.position.is_finite() or not chart.size.is_finite() or chart.size.x<=0.0 or chart.size.y<=0.0:
		return []
	var low: float=0.0
	var high: float=1.0
	for axis in 2:
		var delta: float=float(b[axis])-float(a[axis])
		if delta==0.0:
			if a[axis]<chart.position[axis] or a[axis]>chart.end[axis]: return []
		else:
			var first: float=(float(chart.position[axis])-float(a[axis]))/delta
			var last: float=(float(chart.end[axis])-float(a[axis]))/delta
			low=maxf(low,minf(first,last))
			high=minf(high,maxf(first,last))
			if low>high: return []
	return [a+(b-a)*low,a+(b-a)*high]

func _draw_circuit(chart: Rect2) -> void:
	if _circuit.is_empty() or not _valid or _retained or _runway!=36 or _circuit.session_id!=_session:
		return
	var points: Array=_circuit.points_anchor_eus_m
	var color:=Color("f0cf8c")
	for i in 5:
		var a: Vector2=_point(Vector2(points[i][0],points[i][2]),chart)
		var b: Vector2=_point(Vector2(points[i+1][0],points[i+1][2]),chart)
		# Inset the stroke half-width so antialiasing cannot bleed into captions.
		var segment: Array=_clip_circuit_segment(a,b,chart.grow(-1.5))
		if segment.size()==2: draw_line(segment[0],segment[1],color,1.5,true)
		var text: String=_circuit.leg_labels[i]
		var at: Vector2=(a+b)*0.5+Vector2(5,-5)
		var width: float=_font.get_string_size(text,HORIZONTAL_ALIGNMENT_LEFT,-1,10).x
		if chart.grow(-5).encloses(Rect2(at-Vector2(0,11),Vector2(width,14))):
			_text(at,text,color,10)

func set_wind_cue(value: Dictionary) -> void:
	_wind_cue=value.duplicate(true)
	queue_redraw()

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(_refresh_presentation)
	_refresh_presentation()

func set_landmarks(values: Array) -> void:
	# Private original-scene metadata, copied once. Not a persisted chart schema.
	_landmarks.clear()
	for value in values.slice(0,16):
		if typeof(value)!=TYPE_DICTIONARY or typeof(value.get("position_eus_m"))!=TYPE_VECTOR3:
			continue
		var position: Vector3=value.position_eus_m
		if not position.is_finite() or str(value.get("label","")).is_empty():
			continue
		_landmarks.append({"label":str(value.label).left(32),"position_eus_m":position})
	queue_redraw()

func select_runway(value: int) -> void:
	_runway=18 if value==18 else 36
	_refresh_presentation()

func set_route(view: Dictionary) -> void:
	_set_geographic_route(view)
	_manual_summary=_admit_summary(view)
	_refresh_presentation()

func _set_geographic_route(view: Dictionary) -> void:
	# Private copied presentation only. The board owns selection/progress, and
	# the original native pose remains the map's authoritative position source.
	_route.clear()
	if view.get("available")!=true or view.get("active")!=true:
		queue_redraw()
		return
	var target: Variant=view.get("target_anchor_eus_m")
	var label: Variant=view.get("target_label")
	if not target is Array or target.size()!=3 or not label is String or label.is_empty() or label.length()>32:
		queue_redraw()
		return
	for scalar in target:
		if not (scalar is float or scalar is int) or not is_finite(float(scalar)):
			queue_redraw()
			return
	if absf(float(target[0]))>20000.0 or absf(float(target[2]))>20000.0 or float(target[1])!=0.0:
		queue_redraw()
		return
	_route={"target":Vector2(target[0],target[2]),"label":label,
		"leg_number":int(view.get("leg_index",0))+1,"leg_count":int(view.get("leg_count",1))}
	queue_redraw()

func toggle_runway() -> void:
	select_runway(18 if _runway==36 else 36)

func set_state(state: Dictionary, local_position: Vector3, aircraft_basis: Basis, info: Dictionary={}) -> void:
	_set_binding_hints(info.get("locator_binding_hints"))
	_publication_tick=str(state.get("tick",""))
	_paused=bool(info.get("paused",false))
	_retained=bool(info.get("historical",false)) or bool(info.get("blocked",false)) or bool(info.get("stalled",false)) or str(info.get("outcome","completed")) not in ["completed","paused"]
	_valid = not state.is_empty() and state.get("validity", "") == "valid" and local_position.is_finite()
	_clearance_valid=_valid and not _retained and bool(info.get("ground_valid",false)) and is_finite(float(info.get("clearance_m",NAN)))
	_clearance_m=float(info.get("clearance_m",0.0)) if _clearance_valid else 0.0
	if not _valid:
		_heading_valid=false
		_refresh_presentation()
		return
	var session := str(state.get("session_id", ""))
	var tick := int(str(state.get("tick", "0")))
	if session != _session or tick < _sample_tick:
		_session = session
		_sample_tick = -SAMPLE_TICKS
		_trail.clear()
	_position = Vector2(local_position.x, local_position.z)
	var nose := -aircraft_basis.z
	var horizontal := Vector2(nose.x,nose.z)
	_heading_valid = horizontal.length_squared() >= 0.000001
	if not _heading_valid:
		_direction = Vector2.UP
	else:
		_direction = horizontal.normalized()
	if not _retained and tick - _sample_tick >= SAMPLE_TICKS:
		_trail.append(_position)
		if _trail.size() > MAX_TRAIL:
			_trail.pop_front()
		_sample_tick = tick
	_refresh_presentation()

func _runway_metrics() -> Dictionary:
	if not _valid or _retained:
		return {}
	# Physical paving end, not an operational threshold. Existing painted cues
	# are displaced from these ends and are not regulatory marking geometry.
	var end:=Vector2(0,100 if _runway==36 else -1700)
	var inbound:=Vector2.UP if _runway==36 else Vector2.DOWN
	var right:=Vector2(-inbound.y,inbound.x)
	var relative:=_position-end
	var to_end:=end-_position
	var range_m:=to_end.length()
	return {"end":end,"inbound":inbound,"range_m":range_m,"bearing_valid":range_m>0.01,
		"bearing_deg":fposmod(rad_to_deg(atan2(to_end.x,-to_end.y)),360.0) if range_m>0.01 else 0.0,
		"along_m":relative.dot(inbound),"cross_m":relative.dot(right),"clearance_valid":_clearance_valid,"clearance_m":_clearance_m}

func zoom(factor: float) -> void:
	extent_m = clampf(extent_m * factor, 1000.0, 32000.0)
	_refresh_presentation()

func _point(position: Vector2, chart: Rect2) -> Vector2:
	return chart.get_center() + (position - _position) * chart.size.x / extent_m

static func _inset_contains(chart: Rect2, point: Vector2, margin: float) -> bool:
	# A small routed chart can have no interior at this margin. Treat that
	# interior as empty, rather than querying a negative-size Godot rectangle.
	if not chart.position.is_finite() or not chart.size.is_finite() or not point.is_finite() or not is_finite(margin) or margin<0.0:
		return false
	if chart.size.x<=2.0*margin or chart.size.y<=2.0*margin:
		return false
	return chart.grow(-margin).has_point(point)

func _text(at: Vector2, value: String, color: Color = INK, pixels: int = 12) -> void:
	draw_string(_font, at, value, HORIZONTAL_ALIGNMENT_LEFT, -1, pixels, color)

func _polygon(points: PackedVector2Array, chart: Rect2, color: Color) -> void:
	var border := PackedVector2Array([chart.position,Vector2(chart.end.x,chart.position.y),chart.end,Vector2(chart.position.x,chart.end.y)])
	for clipped in Geometry2D.intersect_polygons(points,border):
		draw_colored_polygon(clipped,color)

func _rectangle(bounds: Rect2, chart: Rect2, color: Color) -> void:
	_polygon(PackedVector2Array([_point(bounds.position,chart),_point(Vector2(bounds.end.x,bounds.position.y),chart),_point(bounds.end,chart),_point(Vector2(bounds.position.x,bounds.end.y),chart)]),chart,color)

func _route_metrics() -> Dictionary:
	if _route.is_empty() or not _valid or _retained: return {}
	var delta: Vector2=_route.target-_position
	return {"range_m":delta.length(),"bearing_valid":delta.length()>0.01,
		"bearing_deg":fposmod(rad_to_deg(atan2(delta.x,-delta.y)),360.0) if delta.length()>0.01 else 0.0}


func _shortened(text: String, width: float, pixels: int=10) -> String:
	if _font.get_string_size(text,HORIZONTAL_ALIGNMENT_LEFT,-1,pixels).x<=width: return text
	var result: String=text
	while not result.is_empty() and _font.get_string_size(result+"…",HORIZONTAL_ALIGNMENT_LEFT,-1,pixels).x>width:
		result=result.left(result.length()-1)
	return result+"…"

func _row(id: String, text: String, rect: Rect2, pixels: int=10, wrap: bool=false, color: Color=MUTED) -> Dictionary:
	return {"id":id,"text":text,"rect":rect,"pixels":pixels,"wrap":wrap,"color":color}

func _presentation_rows() -> Dictionary:
	var rows: Array=[]
	var current: bool=_valid and not _retained
	if not compact_aid_layout or size.x<250.0 or size.y<(220.0 if current else 188.0): return {"rows":rows,"chart":Rect2(),"current":current}
	var width: float=size.x-24.0
	var status: String="STOPPED" if _retained else "PAUSED" if _paused and _valid else "LIVE" if _valid else "UNAVAILABLE"
	var manual: Dictionary=_summary_text() if _manual_summary.get("aid_visible",false) else {}
	var selected: bool=not manual.is_empty() and _manual_summary.leg_count>0
	var header: String="SYNTHETIC LOCATOR · "+status
	if selected: header+=" · %d/%d" % [_manual_summary.leg_index+1,_manual_summary.leg_count]
	var header_pixels: int=11 if _font.get_string_size(header,HORIZONTAL_ALIGNMENT_LEFT,-1,11).x<=width else 10
	rows.append(_row("header",header,Rect2(12,17-_font.get_ascent(header_pixels),width,_font.get_height(header_pixels)),header_pixels,false,CYAN))
	var binding_line: String=_binding_footer(width)
	if current:
		var secondary: String="SYNTHETIC AID · "+status+" · RWY %02d" % _runway
		if selected:
			var prefix: String="Itinerary (tooltip): "
			secondary=prefix+_shortened(" -> ".join(_manual_summary.route_labels),width-_font.get_string_size(prefix,HORIZONTAL_ALIGNMENT_LEFT,-1,10).x)
		rows.append(_row("status",secondary,Rect2(12,22,width,14)))
		var target: String=manual.title if selected else _route.get("label","No manual itinerary")
		rows.append(_row("target",target,Rect2(12,38,width,31),10,true,Color("c9b8ff")))
		var metrics: Dictionary=_runway_metrics()
		var bearing: String="%03d°T" % (int(roundf(metrics.bearing_deg))%360) if metrics.get("bearing_valid",false) else "—"
		rows.append(_row("runway","RWY %02d · %.2f km · %s" % [_runway,metrics.get("range_m",0.0)/1000.0,bearing],Rect2(12,124,width,14),10,false,CYAN))
		rows.append(_row("along","%s %.0fm · %s %.0fm" % ["BEFORE" if metrics.get("along_m",0.0)<0 else "PAST",absf(metrics.get("along_m",0.0)),"RIGHT" if metrics.get("cross_m",0.0)>0.01 else "LEFT" if metrics.get("cross_m",0.0)< -0.01 else "AXIS",absf(metrics.get("cross_m",0.0))],Rect2(12,139,width,14),10,false,INK))
		rows.append(_row("height","CG H %s · NOT MSL / WHEELS" % ("%.0fft" % (metrics.get("clearance_m",0.0)*3.280839895) if metrics.get("clearance_valid",false) else "—"),Rect2(12,154,width,14)))
		rows.append(_row("manual",manual.metrics if selected else "Range / bearing unavailable",Rect2(12,169,width,14)))
		var qualification: String=manual.footer if selected else "SYNTHETIC / OPTIONAL MAP AID"
		rows.append(_row("footer",qualification+"\n"+binding_line,Rect2(12,185,width,31),10,true))
		return {"rows":rows,"chart":Rect2(12,69,width,54),"current":true}
	rows.append(_row("status","SYNTHETIC AID · "+status,Rect2(12,22,width,14)))
	rows.append(_row("runway","RWY %02d · SPAN %.1f km" % [_runway,extent_m/1000.0],Rect2(12,38,width,14),10,false,CYAN))
	rows.append(_row("no_current","NO CURRENT GEOGRAPHIC GUIDANCE",Rect2(12,54,width,14)))
	if selected:
		rows.append(_row("target",manual.title,Rect2(12,70,width,14),10,false,Color("c9b8ff")))
		rows.append(_row("manual",manual.metrics,Rect2(12,86,width,14)))
		var prefix: String="Leg %d/%d · itinerary(tooltip): " % [_manual_summary.leg_index+1,_manual_summary.leg_count]
		rows.append(_row("leg",prefix+_shortened(" -> ".join(_manual_summary.route_labels),width-_font.get_string_size(prefix,HORIZONTAL_ALIGNMENT_LEFT,-1,10).x),Rect2(12,102,width,14)))
		rows.append(_row("footer",manual.footer,Rect2(12,121,width,31),10,true))
	else:
		rows.append(_row("footer","SYNTHETIC / OPTIONAL MAP AID",Rect2(12,121,width,31)))
	rows.append(_row("bindings",binding_line,Rect2(12,165,width,14)))
	return {"rows":rows,"chart":Rect2(),"current":false}

func _refresh_presentation() -> void:
	if _labels.is_empty(): return
	_presentation=_presentation_rows()
	for label in _labels.values(): label.visible=false
	for row in _presentation.rows:
		var label: Label=_labels[row.id]
		label.text=row.text
		label.add_theme_font_size_override("font_size",row.pixels)
		label.add_theme_color_override("font_color",row.color)
		label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART if row.wrap else TextServer.AUTOWRAP_OFF
		label.position=row.rect.position
		label.size=row.rect.size
		label.visible=true
	var hints: PackedStringArray=["cfg = CONFIGURED; device availability unverified. +N means additional configured alternatives. Open Controls for complete bindings."]
	for pair in [["zoom_in","+ Zoom in"],["zoom_out","− Zoom out"],["close","Close"]]:
		hints.append(pair[1]+": "+_locator_hints.get(pair[0],{"full":"Binding unavailable; open Controls"}).full)
	var manual: Dictionary=_summary_text()
	if not manual.is_empty():
		for key in ["title","metrics","leg","footer"]: hints.append(manual[key])
		if not _manual_summary.error.is_empty(): hints.append(_manual_summary.error)
	tooltip_text="\n".join(hints)
	for label in _labels.values(): label.tooltip_text=tooltip_text
	queue_redraw()

func _row_fits(row: Dictionary) -> bool:
	var label: Label=_labels[row.id]
	if not label.visible or label.text!=row.text or label.get_theme_font_size("font_size")!=row.pixels or not Rect2(Vector2.ZERO,size).encloses(label.get_rect()): return false
	var font: Font=label.get_theme_font("font")
	var count: int=label.get_line_count()
	var height: float=count*label.get_line_height()+maxi(0,count-1)*label.get_theme_constant("line_spacing")
	if count<1 or height>row.rect.size.y or label.get_rect()!=row.rect: return false
	if not row.wrap and font.get_string_size(label.text,HORIZONTAL_ALIGNMENT_LEFT,-1,row.pixels).x>row.rect.size.x: return false
	return true

func renders_manual_summary() -> bool:
	# Pure actual-layout accessor; no admission, redraw or source-state mutation.
	if not is_visible_in_tree() or not compact_aid_layout or _manual_summary.is_empty() or not _manual_summary.aid_visible or _manual_summary.leg_count==0: return false
	if _manual_summary.session_id!=null and (_manual_summary.session_id!=_session or _manual_summary.tick!=_publication_tick): return false
	if _manual_summary.historical and not _retained: return false
	if _manual_summary.available and (not _valid or _retained or _manual_summary.paused!=_paused): return false
	if _presentation.rows.is_empty(): return false
	for row in _presentation.rows:
		if not _row_fits(row): return false
	return true

func _draw() -> void:
	if not compact_aid_layout:
		_draw_ordinary()
		return
	if _presentation.rows.is_empty(): return
	var style := StyleBoxFlat.new()
	style.bg_color=Color(0.025,0.055,0.075,0.96)
	style.border_color=Color("426274")
	style.set_border_width_all(1)
	style.set_corner_radius_all(9)
	draw_style_box(style,Rect2(Vector2.ZERO,size))
	if _presentation.current: _draw_chart(_presentation.chart)

func _draw_ordinary() -> void:
	if size.x < 220 or size.y < 220:
		return
	var style := StyleBoxFlat.new()
	style.bg_color=Color(0.025,0.055,0.075,0.96)
	style.border_color=Color("426274")
	style.set_border_width_all(1)
	style.set_corner_radius_all(9)
	draw_style_box(style,Rect2(Vector2.ZERO,size))
	var compact: bool=compact_aid_layout and (size.x<330.0 or size.y<330.0)
	var status: String="STOPPED" if _retained else "PAUSED" if _paused else "LIVE" if _valid else "UNAVAILABLE"
	_text(Vector2(14,21 if compact else 23),"AIRFIELD LOCATOR",CYAN,12 if compact else 14)
	if compact:
		_text(Vector2(14,37),"SYNTHETIC AID · "+status+" · RWY %02d" % _runway,MUTED,10)
	else:
		_text(Vector2(size.x-100,23),"RWY %02d" % _runway,Color("ffc477"),12)
		_text(Vector2(14,43),"SYNTHETIC · OPTIONAL AID · "+status,MUTED,10)
	var route_shown: bool=not _route.is_empty() and _valid and not _retained
	var extra: float=20.0 if route_shown else 0.0
	if route_shown:
		var route_title: String="MANUAL %d/%d: " % [_route.leg_number,_route.leg_count] if compact_aid_layout else "MANUAL LEG: "
		_text(Vector2(14,53 if compact else 62),route_title+_route.label,Color("c9b8ff"),10 if compact else 11)
	var chart := Rect2(12,(42 if compact else 56)+extra,size.x-24,size.y-(128 if compact else 183 if compact_aid_layout and route_shown else 163)-extra)
	_draw_chart(chart)
	var metrics:=_runway_metrics()
	var line:=chart.end.y+19
	if compact:
		line=chart.end.y+15
		if metrics.is_empty():
			_text(Vector2(14,line),"RWY %02d · CURRENT STATE UNAVAILABLE" % _runway,MUTED,10)
		else:
			var bearing: String="%03d°T" % (int(roundf(metrics.bearing_deg))%360) if metrics.bearing_valid else "—"
			_text(Vector2(14,line),"RWY %02d · %.2f km · %s" % [_runway,metrics.range_m/1000.0,bearing],CYAN,10)
			_text(Vector2(14,line+15),"%s %.0fm · %s %.0fm" % ["BEFORE" if metrics.along_m<0 else "PAST",absf(metrics.along_m),"RIGHT" if metrics.cross_m>0.01 else "LEFT" if metrics.cross_m< -0.01 else "AXIS",absf(metrics.cross_m)],INK,10)
			_text(Vector2(14,line+30),"CG H %s · NOT MSL / WHEELS" % ("%.0fft" % (metrics.clearance_m*3.280839895) if metrics.clearance_valid else "—"),MUTED,10)
		if route_shown:
			var route_metrics: Dictionary=_route_metrics()
			_text(Vector2(14,line+45),"LEG %.2f km · %s · ANCHOR" % [route_metrics.range_m/1000.0,"%03d°" % (int(roundf(route_metrics.bearing_deg))%360) if route_metrics.bearing_valid else "—"],Color("c9b8ff"),10)
		_text(Vector2(14,size.y-12),_binding_footer(size.x-28),MUTED,10)
		return
	_text(Vector2(14,line),"RWY %02d END · GEOMETRY / NATIVE TRUTH" % _runway,CYAN,11)
	if metrics.is_empty():
		_text(Vector2(14,line+18),"RANGE —   BEARING —   AXIS —",MUTED,12)
		_text(Vector2(14,line+36),"PLANE CG HEIGHT — · CURRENT STATE UNAVAILABLE",MUTED,10)
	else:
		var bearing: String="%03d°T" % (int(roundf(metrics.bearing_deg))%360) if metrics.bearing_valid else "—"
		_text(Vector2(14,line+18),"RANGE %.2f km · BEARING %s" % [metrics.range_m/1000.0,bearing],INK,12)
		var along: String="BEFORE END" if metrics.along_m<0 else "PAST END"
		var side: String="RIGHT" if metrics.cross_m>0.01 else "LEFT" if metrics.cross_m< -0.01 else "ON AXIS"
		_text(Vector2(14,line+36),"%s %.0f m · %s %.0f m" % [along,absf(metrics.along_m),side,absf(metrics.cross_m)],INK,11)
		_text(Vector2(14,line+53),"PLANE CG H %s · NOT MSL / WHEEL CLEARANCE" % ("%.0f ft" % (metrics.clearance_m*3.280839895) if metrics.clearance_valid else "—"),MUTED,10)
	if compact_aid_layout and route_shown:
		var route_metrics: Dictionary=_route_metrics()
		_text(Vector2(14,line+71),"MANUAL LEG %.2f km · ANCHOR %s" % [route_metrics.range_m/1000.0,"%03d°" % (int(roundf(route_metrics.bearing_deg))%360) if route_metrics.bearing_valid else "—"],Color("c9b8ff"),11)
	_text(Vector2(14,size.y-12),_binding_footer(size.x-28),MUTED,11)

func _draw_chart(chart: Rect2) -> void:
	if not chart.position.is_finite() or not chart.size.is_finite() or chart.size.x<48 or chart.size.y<34: return
	var route_shown: bool=not _route.is_empty() and _valid and not _retained
	draw_rect(chart,Color("162c2b"))
	_rectangle(Rect2(-20000,-20000,40000,40000),chart,Color("223c32"))
	var spacing := extent_m / 4.0
	var first := (_position / spacing).floor() * spacing
	for i in range(-3,4):
		var vertical := _point(Vector2(first.x+i*spacing,_position.y),chart).x
		var horizontal := _point(Vector2(_position.x,first.y+i*spacing),chart).y
		if vertical >= chart.position.x+0.5 and vertical <= chart.end.x-0.5:
			draw_line(Vector2(vertical,chart.position.y+0.5),Vector2(vertical,chart.end.y-0.5),Color("355146"),1)
		if horizontal >= chart.position.y+0.5 and horizontal <= chart.end.y-0.5:
			draw_line(Vector2(chart.position.x+0.5,horizontal),Vector2(chart.end.x-0.5,horizontal),Color("355146"),1)
	# Exact original visual runway/apron/taxiway bounds in the accepted frame.
	_rectangle(Rect2(-20,-1700,40,1800),chart,Color("d9e0da"))
	_rectangle(Rect2(74.5,-1720,15,1840),chart,Color("98a38f"))
	_rectangle(Rect2(67,-70,130,190),chart,Color("899586"))
	for z in [30.0,-800.0,-1630.0]:
		_rectangle(Rect2(16.5,z-7.5,65,15),chart,Color("98a38f"))
	var end:=Vector2(0,100 if _runway==36 else -1700)
	var inbound:=Vector2.UP if _runway==36 else Vector2.DOWN
	# Only an optional geometric reference, no glidepath/flight-director command.
	for i in range(12):
		_rectangle(Rect2(end-inbound*(i*160+160)-Vector2(1.5,0),Vector2(3,70)),chart,Color(1.0,0.77,0.47,0.65))
	var end_point:=_point(end,chart)
	if _inset_contains(chart,end_point,7.0):
		draw_circle(end_point,5,Color("ffc477"))
	for landmark in _landmarks:
		var position: Vector3=landmark.position_eus_m
		var at:=_point(Vector2(position.x,position.z),chart)
		if _inset_contains(chart,at,18.0):
			draw_circle(at,3.5,Color("d2bf83"))
			var width:=_font.get_string_size(landmark.label,HORIZONTAL_ALIGNMENT_LEFT,-1,10).x
			if width<=chart.size.x-8:
				_text(Vector2(clampf(at.x+7,chart.position.x+4,chart.end.x-width-4),clampf(at.y-5,chart.position.y+12,chart.end.y-5)),landmark.label,Color("d2bf83"),10)
	if route_shown:
		var target_at: Vector2=_point(_route.target,chart)
		var offset: Vector2=target_at-chart.get_center()
		var clip_scale: float=minf((chart.size.x*0.5-12)/maxf(absf(offset.x),0.001),(chart.size.y*0.5-12)/maxf(absf(offset.y),0.001))
		var visible_target: Vector2=chart.get_center()+offset*minf(clip_scale,1.0)
		draw_line(chart.get_center(),visible_target,Color("c9b8ff"),1.5,true)
		draw_arc(visible_target,7,0,TAU,24,Color("c9b8ff"),2.0,true)
	_draw_circuit(chart)
	for i in range(1,_trail.size() if _valid and not _retained else 0):
		var a := _point(_trail[i-1],chart)
		var b := _point(_trail[i],chart)
		var segment: Array=_clip_circuit_segment(a,b,chart.grow(-0.75))
		if segment.size()==2:
			draw_line(segment[0],segment[1],Color(0.47,0.84,0.89,0.6),1.5,true)
	if not _inset_contains(chart,end_point,24.0):
		var offset := end_point-chart.get_center()
		var scale := minf((chart.size.x*0.5-15)/maxf(absf(offset.x),0.001),(chart.size.y*0.5-15)/maxf(absf(offset.y),0.001))
		var at := chart.get_center()+offset*minf(scale,1.0)
		var direction := offset.normalized()
		var across := Vector2(-direction.y,direction.x)
		draw_colored_polygon(PackedVector2Array([at+direction*8,at-direction*5+across*5,at-direction*5-across*5]),Color("ffc477"))
	if _valid and not _retained:
		var at := chart.get_center()
		var across := Vector2(-_direction.y,_direction.x)
		if _heading_valid:
			draw_colored_polygon(PackedVector2Array([at+_direction*11,at-_direction*7+across*7,at-_direction*4,at-_direction*7-across*7]),CYAN)
		else:
			draw_circle(at,5,CYAN)
			_text(at+Vector2(10,4),"HEADING —",MUTED,10)
	else:
		_text(chart.get_center()-Vector2(78,0),"LAST STATE · STOPPED" if _valid and _retained else "STATE UNAVAILABLE",Color("ffc477"),12)
	_text(Vector2(chart.end.x-18,chart.position.y+18),"N",INK,12)
	draw_line(Vector2(chart.end.x-14,chart.position.y+33),Vector2(chart.end.x-14,chart.position.y+22),INK,1.5)
	if _wind_cue.get("state") in ["live","paused"] and _wind_cue.get("speed_mps",0.0)>0.0:
		var flow: Array=_wind_cue.wind_toward_airfield_eus_mps
		# Scale first; tiny actual binary64 winds must not underflow to calm.
		var largest: float=maxf(absf(flow[0]),absf(flow[2]))
		var direction: Vector2=Vector2(flow[0]/largest,flow[2]/largest).normalized()
		var at: Vector2=chart.position+Vector2(30,26) if compact_aid_layout else chart.position+Vector2(36,38)
		var end_wind: Vector2=at+direction*20.0
		var across:=Vector2(-direction.y,direction.x)
		draw_line(at-direction*16.0,end_wind,CYAN,2.0,true)
		draw_colored_polygon(PackedVector2Array([end_wind,end_wind-direction*8.0+across*4.0,end_wind-direction*8.0-across*4.0]),CYAN)
		_text(at+Vector2(24,4) if compact_aid_layout else at+Vector2(-20,35),"WIND TO",CYAN,10)
