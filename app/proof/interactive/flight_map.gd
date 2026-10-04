extends Control
## Optional original airfield locator. Positions are the same accepted tangent
## frame used by scenery; this is not a chart, GPS instrument or flight assist.

const MAX_TRAIL := 600
const SAMPLE_TICKS := 120
const INK := Color("e8edf3")
const MUTED := Color("98afbb")
const CYAN := Color("79d7e4")
var extent_m := 4000.0
var _session := ""
var _sample_tick := -SAMPLE_TICKS
var _trail: Array[Vector2] = []
var _position := Vector2.ZERO
var _direction := Vector2.UP
var _valid := false
var _heading_valid := false
var _font: Font = ThemeDB.fallback_font

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)

func set_state(state: Dictionary, local_position: Vector3, aircraft_basis: Basis) -> void:
	_valid = not state.is_empty() and state.get("validity", "") == "valid"
	if not _valid:
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
	if tick - _sample_tick >= SAMPLE_TICKS:
		_trail.append(_position)
		if _trail.size() > MAX_TRAIL:
			_trail.pop_front()
		_sample_tick = tick
	queue_redraw()

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
	_text(Vector2(14,23),"AIRFIELD MAP",CYAN,14)
	_text(Vector2(14,43),"SYNTHETIC · TANGENT FRAME",MUTED,10)
	var chart := Rect2(12,56,size.x-24,size.y-102)
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
	for i in range(1,_trail.size()):
		var a := _point(_trail[i-1],chart)
		var b := _point(_trail[i],chart)
		if chart.has_point(a) and chart.has_point(b):
			draw_line(a,b,Color(0.47,0.84,0.89,0.6),1.5,true)
	var runway := _point(Vector2(0,-800),chart)
	if chart.grow(-24).has_point(runway):
		_text(runway+Vector2(8,-4),"36 / 18",INK,11)
	else:
		var offset := runway-chart.get_center()
		var scale := minf((chart.size.x*0.5-15)/maxf(absf(offset.x),0.001),(chart.size.y*0.5-15)/maxf(absf(offset.y),0.001))
		var at := chart.get_center()+offset*minf(scale,1.0)
		var direction := offset.normalized()
		var across := Vector2(-direction.y,direction.x)
		draw_colored_polygon(PackedVector2Array([at+direction*8,at-direction*5+across*5,at-direction*5-across*5]),Color("ffc477"))
	if _valid:
		var at := chart.get_center()
		var across := Vector2(-_direction.y,_direction.x)
		if _heading_valid:
			draw_colored_polygon(PackedVector2Array([at+_direction*11,at-_direction*7+across*7,at-_direction*4,at-_direction*7-across*7]),CYAN)
		else:
			draw_circle(at,5,CYAN)
			_text(at+Vector2(10,4),"HEADING —",MUTED,10)
	else:
		_text(chart.get_center()-Vector2(65,0),"STATE UNAVAILABLE",Color("ffc477"),12)
	_text(Vector2(chart.end.x-18,chart.position.y+18),"N",INK,12)
	draw_line(Vector2(chart.end.x-14,chart.position.y+33),Vector2(chart.end.x-14,chart.position.y+22),INK,1.5)
	_text(Vector2(14,size.y-28),"SPAN %.1f km   + / − ZOOM" % (extent_m/1000.0),MUTED,11)
	_text(Vector2(14,size.y-11),"RWY %.2f km · TAB CLOSE" % (_position.distance_to(Vector2(0,-800))/1000.0),INK,11)
