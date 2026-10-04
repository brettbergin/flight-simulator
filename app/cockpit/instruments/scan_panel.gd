extends "res://interactive/flight_panel.gd"
# Original MIT. ADR009 view-only native-truth scan; no flight authority.
signal focus_selected(instrument: String)
signal dismissed()
const U64 = preload("res://simulation/uint64.gd")
const CHANNEL_UNITS: Dictionary = {"tas":"m/s","ground_speed":"m/s","pitch":"rad","bank":"rad","heading_true":"rad","ellipsoid_height":"m","vertical_speed":"m/s","body_yaw_rate":"rad/s","fuel_total":"kg"}
const INSTRUMENTS: Array = ["tas","attitude","ellipsoid_height","heading_true","body_yaw_rate","vertical_speed"]
var _reading_set: Dictionary = {}
var _scan_info: Dictionary = {}
var _focus: Variant = null
var _display_available: Dictionary = {}
var _scan_error: String = "No verified readings"

func _ready() -> void:
	super._ready()
	_update_mouse()

static func _closed(value: Variant, keys: Array) -> bool:
	if not value is Dictionary or value.size()!=keys.size():
		return false
	for key in value:
		if not key is String or not keys.has(key):
			return false
	return true

static func _bounded(value: Variant, limit: int) -> bool:
	return value is String and value.length()<=limit

static func _session(value: Variant) -> bool:
	if not value is String or value.is_empty() or value.length()>128 or value.unicode_at(0)<97 or value.unicode_at(0)>122:
		return false
	var separator: bool = false
	for i in value.length():
		var code: int = value.unicode_at(i)
		if (code>=97 and code<=122) or (code>=48 and code<=57):
			separator=false
		elif code in [46,45,95] and not separator:
			separator=true
		else:
			return false
	return not separator

static func _validate_set(value: Dictionary, info: Dictionary) -> String:
	if not _closed(value,["session_id","tick","state","native_truth","readings","error"]) or not _closed(info,["view_name","paused","historical","status"]):
		return "Malformed exact scan value"
	if not _bounded(info.view_name,128) or not _bounded(info.status,1024) or typeof(info.paused)!=TYPE_BOOL or typeof(info.historical)!=TYPE_BOOL:
		return "Malformed scan labels or flags"
	if not value.state is String or not ["empty","live","paused","historical","invalid"].has(value.state) or typeof(value.native_truth)!=TYPE_BOOL or not value.native_truth or not _bounded(value.error,1024):
		return "Malformed native-truth ReadingSet"
	if info.historical!=(value.state=="historical") or (value.state=="live" and info.paused) or (value.state=="paused" and not info.paused):
		return "Contradictory scan/current-state flags"
	if not _closed(value.readings,CHANNEL_UNITS.keys()):
		return "Expected exactly nine native channels"
	var unavailable: bool = value.state in ["empty","invalid"]
	if unavailable:
		if value.session_id!=null or value.tick!=null or value.error.is_empty():
			return "Unavailable set must clear identity and explain invalidity"
	elif not _session(value.session_id) or not U64.valid(value.tick) or not value.error.is_empty():
		return "Malformed canonical reading identity"
	for id in CHANNEL_UNITS:
		var channel: Variant = value.readings[id]
		if not _closed(channel,["value","unit","valid","error"]) or not channel.unit is String or channel.unit!=CHANNEL_UNITS[id] or typeof(channel.valid)!=TYPE_BOOL or not _bounded(channel.error,1024):
			return "Malformed native channel: %s" % id
		if channel.valid:
			if unavailable or typeof(channel.value)!=TYPE_FLOAT or not is_finite(channel.value) or not channel.error.is_empty():
				return "Malformed available native channel: %s" % id
		elif channel.value!=null or channel.error.is_empty():
			return "Unavailable channel needs null value and reason: %s" % id
	return ""

func _reject(error: String) -> void:
	_reading_set={}
	_scan_info={}
	_readings={"valid":false}
	_display_available={}
	_scan_error=error
	_focus=null
	tooltip_text=error
	_update_mouse()
	queue_redraw()

func set_readings(value: Dictionary, info: Dictionary) -> void:
	var error: String = _validate_set(value,info)
	if not error.is_empty():
		_reject(error)
		return
	var old_session: Variant = _reading_set.get("session_id")
	_reading_set=value.duplicate(true)
	_scan_info=info.duplicate(true)
	_scan_error=value.error
	if old_session!=value.session_id or value.state in ["empty","invalid"]:
		_focus=null
	_prepare_display()
	tooltip_text=value.error if not value.error.is_empty() else info.status
	_update_mouse()
	queue_redraw()

# The inherited raw-snapshot entry point cannot bypass this leaf's ReadingSet seam.
func set_state(_state: Dictionary, _weather: Dictionary, _controls: Dictionary, _context: Dictionary) -> void:
	_reject("Scan accepts only validated NativeReadings ReadingSet values")

func _prepare_display() -> void:
	# Strict SI-to-display conversion is shared with every native-truth dial.
	_readings=display_readings(_reading_set)
	_display_available=_readings.get("channel_valid",{}).duplicate(true)

func _can_focus() -> bool:
	return _reading_set.get("state")=="paused" and _scan_info.get("paused")==true and _scan_info.get("historical")==false

func _update_mouse() -> void:
	mouse_filter=Control.MOUSE_FILTER_PASS if _can_focus() else Control.MOUSE_FILTER_IGNORE

func focus(instrument: String) -> bool:
	if not _can_focus() or not INSTRUMENTS.has(instrument):
		return false
	var changed: bool = _focus!=instrument
	_focus=instrument
	queue_redraw()
	if changed:
		focus_selected.emit(instrument)
	return true

func clear_focus() -> void:
	if not _can_focus():
		return
	var changed: bool = _focus!=null
	_focus=null
	queue_redraw()
	if changed:
		dismissed.emit()

func focused() -> Variant:
	return _focus

func _scan_layout() -> Dictionary:
	var focused_view: bool = _focus!=null
	var panel: Rect2
	var cells: Array = []
	if focused_view:
		# Retained controls occupy y84..118; leave their fault/held strip readable.
		var top_margin: float = 128.0 if _reading_set.get("state")=="historical" else 96.0
		var width: float = minf(480.0,minf(size.x*0.46,size.y-top_margin-110.0))
		panel=Rect2(size.x-width-18.0,maxf(top_margin,(size.y-width-102.0)*0.5),width,width+102.0)
		cells.append(Rect2(panel.position+Vector2(12,64),Vector2(width-24,width-12)))
	else:
		var cell: float = maxf(80.0,minf((minf(960.0,size.x-40.0)-32.0)/3.0,(size.y-142.0)/2.0))
		var dimensions: Vector2 = Vector2(cell*3.0+32.0,cell*2.0+104.0)
		panel=Rect2((size-dimensions)*0.5,dimensions)
		for index in 6:
			cells.append(Rect2(panel.position+Vector2(16+(index%3)*cell,62+(index/3)*cell),Vector2(cell,cell)))
	return {"panel":panel,"cells":cells,"back":Rect2(panel.position+Vector2(panel.size.x-98,14),Vector2(82,30))}

func _gui_input(event: InputEvent) -> void:
	if not _can_focus() or not event is InputEventMouseButton or not event.pressed or event.button_index!=MOUSE_BUTTON_LEFT:
		return
	var layout: Dictionary = _scan_layout()
	if layout.back.has_point(event.position) or (_focus!=null and not layout.panel.has_point(event.position)):
		var had_focus: bool = _focus!=null
		clear_focus()
		if not had_focus:
			dismissed.emit()
	elif _focus==null:
		for index in 6:
			if layout.cells[index].has_point(event.position):
				focus(INSTRUMENTS[index])
				break
	# Never accepts a keyboard event, clears Raw/mapper edges or sends flight intent.

func _instrument_available(index: int) -> bool:
	if index==1:
		return _display_available.get("pitch",false) and _display_available.get("bank",false)
	return _display_available.get(INSTRUMENTS[index],false)

func _draw_gauge(index: int, cell: Rect2) -> void:
	var all_valid: bool = _readings.get("valid",false)
	_readings.valid=all_valid and _instrument_available(index)
	# Reuse only the original dial artwork; unavailable channels never enter it.
	var display_keys: Array = ["tas_kt","pitch_deg","altitude_ft","heading_deg","yaw_rate_deg_s","vsi_fpm"]
	var large_value: bool = _readings.valid and absf(float(_readings.get(display_keys[index],0.0)))>999999.0
	if large_value:
		_readings.valid=false # Avoid integer formatter overflow; show exact numeric scope.
	super._draw_instrument(index,cell)
	var radius: float = minf(cell.size.x*0.43,(cell.size.y-26.0)*0.5)
	var center: Vector2 = Vector2(cell.get_center().x,cell.position.y+radius+4)
	if large_value:
		draw_circle(center,radius-2,FACE,true,-1,true)
		var numeric_pixels: int = maxi(10,roundi(radius*0.17))
		var numeric_text: String = _fit(str(float(_readings[display_keys[index]])),radius*1.6,numeric_pixels)
		_text(center+Vector2(0,7),numeric_text,numeric_pixels,INK,true)
		_text(center+Vector2(0,radius*0.42),"NUMERIC VIEW",radius*0.11,MUTED,true)
	elif not _readings.valid:
		_text(center+Vector2(0,radius*0.36),"UNAVAILABLE",radius*0.12,MUTED,true)
	_readings.valid=all_valid

func _fit(value: String, width: float, pixels: int) -> String:
	var result: String = value
	while result.length()>0 and _font.get_string_size(result,HORIZONTAL_ALIGNMENT_LEFT,-1,pixels).x>width:
		result=result.substr(0,result.length()-1)
	return result if result==value else result+"…"

func _draw() -> void:
	if not visible or size.x<640.0 or size.y<400.0:
		return
	# Live unselected scan adds nothing to the outside view; host controls visibility.
	if _focus==null and _reading_set.get("state")=="live":
		return
	var layout: Dictionary = _scan_layout()
	var panel: Rect2 = layout.panel
	_box(panel,Color(0.04,0.07,0.11,0.98),LINE,14)
	_text(panel.position+Vector2(16,25),"NATIVE TRUTH / PROTOTYPE",12,CYAN)
	var state: String = str(_reading_set.get("state","invalid"))
	var label: String = "RETAINED" if state=="historical" else "PAUSED · VIEW ONLY" if state=="paused" else "LIVE · VIEW ONLY" if state=="live" else "UNAVAILABLE"
	_text(panel.position+Vector2(16,46),label,14,RED if state=="historical" or state in ["empty","invalid"] else AMBER if state=="paused" else GREEN)
	var context: String = str(_scan_info.get("view_name",""))+" / "+str(_scan_info.get("status",""))
	_text(panel.position+Vector2(16,61),_fit(context,panel.size.x-32,10),10,MUTED)
	if _can_focus():
		_box(layout.back,Color("263346"),LINE,6)
		_text(layout.back.get_center()+Vector2(0,5),"BACK",12,INK,true)
	if _focus!=null:
		_draw_gauge(INSTRUMENTS.find(_focus),layout.cells[0])
	else:
		for index in 6:
			_draw_gauge(index,layout.cells[index])
	var footer: String = "Select a dial · Back returns to flight" if _can_focus() and _focus==null else "Back or click outside · ordinary scan" if _can_focus() else "Pause to select or dismiss · Escape keeps pause/menu"
	if state in ["empty","invalid"]:
		footer=_scan_error
	_text(Vector2(panel.position.x+16,panel.end.y-17),_fit(footer,panel.size.x-32,12),12,MUTED)
