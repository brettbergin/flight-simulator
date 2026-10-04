extends Control
## Optional original airfield locator. Positions are the same accepted tangent
## frame used by scenery; this is not a chart, GPS instrument or flight assist.

const MAX_TRAIL := 600
const SAMPLE_TICKS := 120
const INK := Color("e8edf3")
const MUTED := Color("98afbb")
const CYAN := Color("79d7e4")
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
var _font: Font = ThemeDB.fallback_font

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)

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
	queue_redraw()

func toggle_runway() -> void:
	select_runway(18 if _runway==36 else 36)

func set_state(state: Dictionary, local_position: Vector3, aircraft_basis: Basis, info: Dictionary={}) -> void:
	_paused=bool(info.get("paused",false))
	_retained=bool(info.get("blocked",false)) or bool(info.get("stalled",false)) or str(info.get("outcome","completed"))!="completed"
	_valid = not state.is_empty() and state.get("validity", "") == "valid" and local_position.is_finite()
	_clearance_valid=_valid and not _retained and bool(info.get("ground_valid",false)) and is_finite(float(info.get("clearance_m",NAN)))
	_clearance_m=float(info.get("clearance_m",0.0)) if _clearance_valid else 0.0
	if not _valid:
		_heading_valid=false
		queue_redraw()
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
	queue_redraw()

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
	queue_redraw()

func _point(position: Vector2, chart: Rect2) -> Vector2:
	return chart.get_center() + (position - _position) * chart.size.x / extent_m

func _text(at: Vector2, value: String, color: Color = INK, pixels: int = 12) -> void:
	draw_string(_font, at, value, HORIZONTAL_ALIGNMENT_LEFT, -1, pixels, color)

func _polygon(points: PackedVector2Array, chart: Rect2, color: Color) -> void:
	var border := PackedVector2Array([chart.position,Vector2(chart.end.x,chart.position.y),chart.end,Vector2(chart.position.x,chart.end.y)])
	for clipped in Geometry2D.intersect_polygons(points,border):
		draw_colored_polygon(clipped,color)

func _rectangle(bounds: Rect2, chart: Rect2, color: Color) -> void:
	_polygon(PackedVector2Array([_point(bounds.position,chart),_point(Vector2(bounds.end.x,bounds.position.y),chart),_point(bounds.end,chart),_point(Vector2(bounds.position.x,bounds.end.y),chart)]),chart,color)

func _draw() -> void:
	if size.x < 220 or size.y < 220:
		return
	var style := StyleBoxFlat.new()
	style.bg_color=Color(0.025,0.055,0.075,0.96)
	style.border_color=Color("426274")
	style.set_border_width_all(1)
	style.set_corner_radius_all(9)
	draw_style_box(style,Rect2(Vector2.ZERO,size))
	_text(Vector2(14,23),"AIRFIELD LOCATOR",CYAN,14)
	_text(Vector2(size.x-100,23),"T · RWY %02d" % _runway,Color("ffc477"),12)
	_text(Vector2(14,43),"SYNTHETIC · OPTIONAL AID · "+("STOPPED" if _retained else "PAUSED" if _paused else "LIVE" if _valid else "UNAVAILABLE"),MUTED,10)
	var chart := Rect2(12,56,size.x-24,size.y-163)
	draw_rect(chart,Color("162c2b"))
	_rectangle(Rect2(-20000,-20000,40000,40000),chart,Color("223c32"))
	var spacing := extent_m / 4.0
	var first := (_position / spacing).floor() * spacing
	for i in range(-3,4):
		var vertical := _point(Vector2(first.x+i*spacing,_position.y),chart).x
		var horizontal := _point(Vector2(_position.x,first.y+i*spacing),chart).y
		if vertical >= chart.position.x and vertical <= chart.end.x:
			draw_line(Vector2(vertical,chart.position.y),Vector2(vertical,chart.end.y),Color("355146"),1)
		if horizontal >= chart.position.y and horizontal <= chart.end.y:
			draw_line(Vector2(chart.position.x,horizontal),Vector2(chart.end.x,horizontal),Color("355146"),1)
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
	if chart.grow(-7).has_point(end_point):
		draw_circle(end_point,5,Color("ffc477"))
	for landmark in _landmarks:
		var position: Vector3=landmark.position_eus_m
		var at:=_point(Vector2(position.x,position.z),chart)
		if chart.grow(-18).has_point(at):
			draw_circle(at,3.5,Color("d2bf83"))
			var width:=_font.get_string_size(landmark.label,HORIZONTAL_ALIGNMENT_LEFT,-1,10).x
			_text(Vector2(clampf(at.x+7,chart.position.x+4,chart.end.x-width-4),clampf(at.y-5,chart.position.y+12,chart.end.y-5)),landmark.label,Color("d2bf83"),10)
	for i in range(1,_trail.size() if _valid and not _retained else 0):
		var a := _point(_trail[i-1],chart)
		var b := _point(_trail[i],chart)
		if chart.has_point(a) and chart.has_point(b):
			draw_line(a,b,Color(0.47,0.84,0.89,0.6),1.5,true)
	if not chart.grow(-24).has_point(end_point):
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
	var metrics:=_runway_metrics()
	var line:=chart.end.y+19
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
	_text(Vector2(14,size.y-12),"SPAN %.1f km · + / − ZOOM · TAB CLOSE" % (extent_m/1000.0),MUTED,11)
