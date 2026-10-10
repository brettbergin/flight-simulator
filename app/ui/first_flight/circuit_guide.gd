extends Control
# Original MIT. Fixed copied schematic, never a chart, flight phase or evaluator.
const Geometry = preload("res://world/synthetic/circuit_geometry.gd")
signal enabled_requested(enabled: bool, source_session: String)
const TITLE: String = "OPTIONAL SYNTHETIC CIRCUIT REFERENCE · not evaluated"
const CAPTION: String = "Fixed schematic · not to map scale"
const CYAN := Color("79d7e4")
const MUTED := Color("a0b5c4")
var _view: Dictionary = Geometry.unavailable("Aid off")
var _compact_unavailable: bool = false
var _title: Label
var _caption: Label
var _reason: Label
var _footer: Label
var _labels: Array[Label] = []
var _font: Font = ThemeDB.fallback_font

func _init() -> void:
	mouse_filter=Control.MOUSE_FILTER_IGNORE
	custom_minimum_size=Vector2(240,200)
	_title=_label(TITLE,12,CYAN)
	_title.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	_caption=_label(CAPTION,11,MUTED)
	_reason=_label("Aid off",12,MUTED)
	_reason.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	_footer=_label("Illustration only · no target altitude",10,MUTED)
	for i in 5: _labels.append(_label("",12,Color("e8edf3")))
	resized.connect(_arrange)
	_arrange()

func _label(text: String, pixels: int, color: Color) -> Label:
	var label := Label.new()
	label.text=text
	label.mouse_filter=Control.MOUSE_FILTER_IGNORE
	label.clip_text=true
	label.add_theme_font_size_override("font_size",pixels)
	label.add_theme_color_override("font_color",color)
	add_child(label)
	return label

func set_state(view: Dictionary, enabled: bool) -> void:
	# Root owns the session-local flag and paused chooser. This live card has no
	# interactive children; its declared signal is the integration request seam.
	_view=Geometry.unavailable("Aid off")
	if enabled:
		_view=view.duplicate(true) if Geometry.valid_view(view) else Geometry.unavailable("Malformed circuit display")
	_arrange()

func set_compact_unavailable(enabled: bool) -> void:
	# Presentation only. Availability and the copied source view remain unchanged.
	_compact_unavailable=enabled
	_arrange()

static func schematic_points(rect: Rect2) -> Array[Vector2]:
	# Fixed authored x[-1400,0], z[-2700,1300], independent of ownship/map extent.
	var result: Array[Vector2] = []
	if not rect.position.is_finite() or not rect.size.is_finite() or rect.size.x<=0.0 or rect.size.y<=0.0: return result
	var scale: float=minf(rect.size.x/1400.0,rect.size.y/4000.0)
	for point in Geometry.POINTS:
		result.append(rect.get_center()+Vector2((point[0]+700.0)*scale,(point[2]+700.0)*scale))
	return result

func schematic_rect() -> Rect2:
	return Rect2(14,76,maxf(1.0,size.x*0.52-26.0),maxf(1.0,size.y-112.0))

func _arrange() -> void:
	if _title==null: return
	var compact: bool=_compact_unavailable and not _view.available
	custom_minimum_size=Vector2(240,84 if compact else 200)
	if size.x<custom_minimum_size.x or size.y<custom_minimum_size.y:
		size=Vector2(maxf(size.x,custom_minimum_size.x),maxf(size.y,custom_minimum_size.y))
	_caption.visible=not compact
	_footer.visible=not compact
	_reason.add_theme_font_size_override("font_size",11 if compact else 12)
	_title.position=Vector2(12,8)
	_title.size=Vector2(maxf(1.0,size.x-24),40)
	_caption.position=Vector2(12,50)
	_caption.size=Vector2(maxf(1.0,size.x-24),16)
	_reason.position=Vector2(8 if compact else 14,50 if compact else 70)
	_reason.size=Vector2(maxf(1.0,size.x-(16 if compact else 28)),maxf(1.0,size.y-(56 if compact else 102)))
	_reason.text=_view.error
	_reason.visible=not _view.available
	_footer.position=Vector2(12,maxf(0.0,size.y-24))
	_footer.size=Vector2(maxf(1.0,size.x-24),16)
	# A 20 px pitch preserves 12 px legend text at the 200 px minimum.
	# Taller panels gain spacing without changing the fixed projection.
	var legend_pitch: float=clampf((size.y-100.0)/5.0,20.0,29.0)
	for i in _labels.size():
		var label: Label=_labels[i]
		label.position=Vector2(size.x*0.52+8,70+i*legend_pitch)
		label.size=Vector2(maxf(1.0,size.x*0.48-20),18)
		label.text="%d  %s" % [i+1,_view.leg_labels[i]] if _view.available else ""
		label.visible=_view.available
	queue_redraw()

func _draw() -> void:
	var style := StyleBoxFlat.new()
	style.bg_color=Color(0.025,0.055,0.075,0.96)
	style.border_color=Color("426274")
	style.set_border_width_all(1)
	style.set_corner_radius_all(8)
	draw_style_box(style,Rect2(Vector2.ZERO,size))
	if not _view.available: return
	var points: Array[Vector2]=schematic_points(schematic_rect())
	for i in 5:
		draw_line(points[i],points[i+1],CYAN,2.0,true)
		# Numbered segment correspondence only, never a current-leg indicator.
		var at: Vector2=(points[i]+points[i+1])*0.5
		draw_circle(at,9,Color("162c2b"))
		draw_string(_font,at+Vector2(-3,4),str(i+1),HORIZONTAL_ALIGNMENT_LEFT,-1,11,CYAN)
