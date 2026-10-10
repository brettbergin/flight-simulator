extends Control
## Original generic engineering panel. All readings derive from copied native
## state; this is not a simulated sensor suite or a calibrated aircraft panel.

const INK := Color("e8edf3")
const MUTED := Color("94a4b7")
const CYAN := Color("79d7e4")
const AMBER := Color("ffc477")
const GREEN := Color("8be0ac")
const RED := Color("ff8e91")
const FACE := Color("111822")
const LINE := Color("334153")
const MPS_TO_KT := 3600.0 / 1852.0
const M_TO_FT := 1.0 / 0.3048
const MPS_TO_FPM := 60.0 / 0.3048

var _snapshot: Dictionary = {}
var _atmosphere: Dictionary = {}
var _held: Dictionary = {}
var _info: Dictionary = {}
var _readings: Dictionary = {}
var _help_visible := false
var _panel_visible := true
var _cockpit_surface := false
var _font: Font = ThemeDB.fallback_font
var _engine_feedback_bounds := Rect2()

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)
	queue_redraw()

func set_state(snapshot: Dictionary, atmosphere: Dictionary, held: Dictionary, info: Dictionary) -> void:
	_snapshot = snapshot.duplicate(true)
	_atmosphere = atmosphere.duplicate(true)
	_held = held.duplicate(true)
	_info = info.duplicate(true)
	_readings = _derive_readings(_snapshot, _atmosphere)
	queue_redraw()

# Copied presentation bounds only. Scene owns placement; native values/visibility
# and the viewport-based font breakpoint remain unchanged (ADR019).
func set_engine_feedback_bounds(bounds: Rect2) -> bool:
	if bounds != Rect2():
		if not bounds.position.is_finite() or not bounds.size.is_finite() or bounds.size.x<=0.0 or bounds.size.y<=0.0 or bounds.position.x<0.0 or bounds.position.y<0.0 or bounds.end.x>size.x or bounds.end.y>size.y:
			return false
	if bounds==_engine_feedback_bounds:
		return true
	_engine_feedback_bounds=bounds
	queue_redraw()
	return true

func set_help_visible(value: bool) -> void:
	_help_visible = value
	queue_redraw()

func set_panel_visible(value: bool) -> void:
	_panel_visible = value
	queue_redraw()

func set_cockpit_surface(value: bool) -> void:
	_cockpit_surface = value
	queue_redraw()

func _vector(value: Dictionary) -> Vector3:
	return Vector3(float(value.get("x", 0.0)), float(value.get("y", 0.0)), float(value.get("z", 0.0)))

func _derive_readings(state: Dictionary, weather: Dictionary) -> Dictionary:
	if state.is_empty() or state.get("validity", "") != "valid":
		return {"valid": false}
	var raw: Dictionary = state.get("orientation_body_to_ned", {})
	if raw.size() != 4:
		return {"valid": false}
	var w := float(raw.get("w", 0.0))
	var x := float(raw.get("x", 0.0))
	var y := float(raw.get("y", 0.0))
	var z := float(raw.get("z", 0.0))
	var quaternion := Quaternion(x, y, z, w)
	var velocity_ned := quaternion * _vector(state.get("velocity_body_mps", {}))
	var roll_rad := atan2(2.0 * (w * x + y * z), 1.0 - 2.0 * (x * x + y * y))
	var pitch_rad := asin(clampf(2.0 * (w * y - z * x), -1.0, 1.0))
	var heading_rad := atan2(2.0 * (w * z + x * y), 1.0 - 2.0 * (y * y + z * z))
	var air_valid: bool = not weather.is_empty() and weather.get("tick", "") == state.get("tick", "") and weather.get("session_id", "") == state.get("session_id", "")
	var air_ned := velocity_ned
	if air_valid:
		air_ned -= _vector(weather.get("wind_toward_ned_mps", {}))
		air_ned -= _vector(weather.get("turbulence_ned_mps", {}))
	var fuel := NAN
	for system: Dictionary in state.get("systems", []):
		if system.get("id", "") == "fuel.total" and system.get("validity", "") == "valid" and system.get("quantity", "") == "kg":
			fuel = float(system.get("value", NAN))
	var gear_on := 0
	for gear: Dictionary in state.get("contacts", []):
		if gear.get("on_ground", false):
			gear_on += 1
	return {"valid": true, "tas_valid": air_valid, "tas_kt": air_ned.length() * MPS_TO_KT,
		"ground_kt": Vector2(velocity_ned.x,velocity_ned.y).length() * MPS_TO_KT, "roll_deg": rad_to_deg(roll_rad),
		"pitch_deg": rad_to_deg(pitch_rad), "heading_deg": fposmod(rad_to_deg(heading_rad), 360.0),
		"altitude_ft": float(state.get("position", {}).get("ellipsoid_height_m", 0.0)) * M_TO_FT,
		"vsi_fpm": -velocity_ned.z * MPS_TO_FPM,
		"yaw_rate_deg_s": rad_to_deg(float(state.get("angular_rate_body_radps", {}).get("z", 0.0))),
		"fuel_kg": fuel, "ground_contacts": gear_on}

func _draw() -> void:
	if _cockpit_surface:
		# A separate instance fills the physical dashboard's 1024×512 texture.
		# No overlay bar, outside-view gap or interactive help belongs in it.
		draw_set_transform(Vector2.ZERO, 0, Vector2(size.x / 1024.0, size.y / 512.0))
		_draw_cockpit_surface()
		draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)
		return
	if size.x < 640.0 or size.y < 400.0:
		return
	_draw_topbar()
	_draw_control_strip()
	if _info.has("engine_status"):
		_draw_piston_strip()
	if _panel_visible:
		_draw_panel()
	if _help_visible:
		_draw_help()

func _text(at: Vector2, text: String, pixels: float = 14.0, color: Color = INK, centered: bool = false) -> void:
	var font_size := maxi(10, roundi(pixels))
	var origin := at
	if centered:
		origin.x -= _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x * 0.5
	draw_string(_font, origin, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)

func _box(rect: Rect2, fill: Color, border: Color = LINE, radius: int = 9) -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.set_border_width_all(1)
	style.set_corner_radius_all(radius)
	draw_style_box(style, rect)

func _polar(center: Vector2, radius: float, angle: float) -> Vector2:
	return center + Vector2(cos(angle), sin(angle)) * radius

func _line(a: Vector2, b: Vector2, color: Color = INK, width: float = 1.0) -> void:
	draw_line(a, b, color, width, true)

func _draw_topbar() -> void:
	var width := size.x
	draw_rect(Rect2(0, 0, width, 46), Color("0d1522"))
	_line(Vector2(0, 45), Vector2(width, 45), LINE)
	draw_circle(Vector2(23, 23), 5, CYAN, true, -1, true)
	_text(Vector2(38, 28), "FLIGHT SIM", 17)
	_text(Vector2(151, 28), "NATIVE", 11, MUTED)
	_box(Rect2(202, 12, 90, 23), Color("253022"), Color("4c5740"), 5)
	_text(Vector2(247, 28), "PROTOTYPE", 10, AMBER, true)
	var status := "PAUSED" if _info.get("paused", false) else "LIVE"
	var status_color := AMBER if _info.get("paused", false) else GREEN
	var outcome := str(_info.get("outcome", ""))
	if outcome in ["discarded", "coverage_blocked", "error"]:
		status = "STOPPED" if outcome == "discarded" else "GROUND UNAVAILABLE"
		status_color = RED
	if _info.get("blocked",false) or _info.get("stalled",false):
		status="RESTART REQUIRED"
		status_color=RED
	if _info.get("retained",false):
		status="RETAINED"
		status_color=RED
	if _readings.get("valid", false) == false and not _info.get("blocked",false) and not _info.get("stalled",false):
		status = "WAITING FOR STATE"
		status_color = MUTED
	draw_circle(Vector2(318, 23), 3, status_color, true, -1, true)
	_text(Vector2(329, 28), status, 12, status_color)
	var view_name := str(_info.get("view_name", "FLIGHT VIEW")).to_upper()
	_text(Vector2(width * 0.61, 28), view_name, 12, MUTED, true)
	_text(Vector2(width - 225, 28), "P  PAUSE     R  RESET     H  HELP", 11, MUTED)
	if not _info.get("blocked",false) and not _info.get("stalled",false):
		var input_label: String=str(_info.get("input_label","PAD" if str(_info.get("input_name","")).begins_with("Gamepad") else "KEYBOARD"))
		var status_right: float=329.0+_font.get_string_size(status,HORIZONTAL_ALIGNMENT_LEFT,-1,12).x
		var input_width: float=_font.get_string_size(input_label,HORIZONTAL_ALIGNMENT_LEFT,-1,10).x
		_text(Vector2(maxf(width*0.43,status_right+18.0+input_width*0.5),28),input_label,10,MUTED,true)
	if _info.get("blocked",false) or _info.get("stalled",false):
		draw_rect(Rect2(0,46,width,32),Color("492a20"))
		_text(Vector2(18,68),str(_info.get("status","Flight stopped; R starts a fresh attempt")).left(int((width-36)/7.5)),13,AMBER)

func _control_strip_values() -> Dictionary:
	return {"valid":_readings.get("valid",false) and not _held.is_empty(),
		"ground_valid":_readings.get("valid",false) and _readings.get("channel_valid",{}).get("ground_speed",true),
		"ground_kt":float(_readings.get("ground_kt",NAN)),
		"throttle_percent":roundi(float(_held.get("throttle",0.0))*100),
		"left_percent":roundi(float(_held.get("left_brake",0.0))*100),
		"right_percent":roundi(float(_held.get("right_brake",0.0))*100)}

func _draw_control_strip() -> void:
	# Remains visible when the full overlay is hidden in cockpit/panel view.
	# Numbers are native-held controls/current copied motion, never pending intent.
	var retained: bool=_info.get("retained",false) or _info.get("blocked",false) or _info.get("stalled",false) or str(_info.get("outcome","")) in ["discarded","error","coverage_blocked"]
	var top: float=84.0 if retained else 51.0
	var values:=_control_strip_values()
	_box(Rect2(10,top,size.x-20,34),Color(0.035,0.064,0.095,0.95),Color("425162"),6)
	var baseline:=top+23.0
	var valid: bool=values.valid
	_text(Vector2(23,baseline),"GS "+_native_number(float(values.ground_kt),1)+" kt" if values.ground_valid and is_finite(values.ground_kt) else "GS — kt",16,INK)
	_text(Vector2(174,baseline),"THR %03d%%" % int(values.throttle_percent) if valid else "THR —",16,CYAN)
	_text(Vector2(319,baseline),"BRAKES L %03d%%  R %03d%%" % [int(values.left_percent),int(values.right_percent)] if valid else "BRAKES L —  R —",15,AMBER)
	var scope: String="RETAINED" if retained else "PAUSED" if _info.get("paused",false) else "NATIVE HELD"
	_text(Vector2(574,baseline),scope,11,RED if retained else AMBER if _info.get("paused",false) else MUTED)
	_text(Vector2(size.x-258,baseline),"X IDLE   HOLD SPACE   B TOGGLE",11,MUTED)

func _draw_panel() -> void:
	var compact := size.y < 900.0
	var panel_height := minf(size.y * 0.34, 455.0)
	var top := size.y - panel_height
	_box(Rect2(12, top, size.x - 24, panel_height + 9), Color("111b29"), Color("3b4b60"), 14)
	_line(Vector2(28, top + 1), Vector2(size.x - 28, top + 1), Color("526378"))
	if compact:
		_draw_compact_panel(top, panel_height)
	else:
		_draw_classic_panel(top, panel_height)

func _engine_channel(id: String) -> Variant:
	var source: Variant=_info.get("engine_status")
	if not source is Dictionary or source.get("native_truth")!=true or source.get("state") not in ["live","paused","historical"]:
		return null
	var channels: Variant=source.get("readings")
	if not channels is Dictionary:
		return null
	var channel: Variant=channels.get(id)
	if not channel is Dictionary or channel.get("valid")!=true or channel.get("error")!="":
		return null
	var value: Variant=channel.get("value")
	if channel.get("unit")=="bool":
		return value if typeof(value)==TYPE_BOOL else null
	return value if typeof(value)==TYPE_FLOAT and is_finite(value) else null

func _engine_number(id: String, factor: float=1.0, decimals: int=0) -> String:
	var value: Variant=_engine_channel(id)
	return _native_number(float(value)*factor,decimals) if typeof(value)==TYPE_FLOAT else "—"

func _engine_switch(id: String) -> String:
	var value: Variant=_engine_channel(id)
	return ("ON" if value else "OFF") if typeof(value)==TYPE_BOOL else "—"

func _engine_phase() -> String:
	var running: Variant=_engine_channel("engine.running")
	var starter: Variant=_engine_channel("engine.starter")
	var shaft: Variant=_engine_channel("propeller.angular_speed")
	if typeof(running)!=TYPE_BOOL or typeof(starter)!=TYPE_BOOL or typeof(shaft)!=TYPE_FLOAT:
		return "UNAVAILABLE"
	if running: return "RUNNING"
	if starter: return "CRANKING"
	return "STOPPED" if shaft==0.0 else "COASTING" if shaft>0.0 else "UNAVAILABLE"

func _wrap_engine_feedback(value: String, width: float, pixels: int) -> Array[String]:
	var lines: Array[String]=[]
	var line: String=""
	for word in value.split(" ",false):
		var candidate: String=word if line.is_empty() else line+" "+word
		if not line.is_empty() and _font.get_string_size(candidate,HORIZONTAL_ALIGNMENT_LEFT,-1,pixels).x>width:
			lines.append(line)
			line=word
		else:
			line=candidate
	if not line.is_empty(): lines.append(line)
	return lines

func _engine_feedback_layout() -> Dictionary:
	var retained: bool=_info.get("retained",false) or _info.get("blocked",false) or _info.get("stalled",false)
	var top: float=size.y-60.0 if str(_info.get("view_name","")).to_upper()=="PANEL" else 123.0 if retained else 90.0
	var bounds: Rect2=_engine_feedback_bounds if _engine_feedback_bounds!=Rect2() else Rect2(10,top,size.x-20,54)
	var scope: String="RETAINED" if retained else "ENGINE"
	# These are the original complete source rows/formatters. Wrapping changes
	# presentation only; unfit rows remain explicit failures, never ellipsized.
	var first: String="%s %s · %s RPM · MIX %s%% · FUEL %s kg · NATIVE RUN %s" % [scope,_engine_phase(),_engine_number("propeller.angular_speed",60.0/TAU),_engine_number("engine.mixture",100.0),_engine_number("fuel.total",1.0,1),_engine_switch("engine.running")]
	var second: String="IGN L %s / R %s · START %s · FEED %s · STARVED %s · IDEALIZED STARTER SUPPLY" % [_engine_switch("engine.ignition_left"),_engine_switch("engine.ignition_right"),_engine_switch("engine.starter"),_engine_switch("fuel.feed"),_engine_switch("engine.starved")]
	var pixels: int=12 if size.x<1100.0 else 14
	var line_height: float=_font.get_height(pixels)
	var row_height: float=(bounds.size.y-12.0)*0.5
	var rows: Array=[]
	var fits: bool=bounds.size.x>24.0 and row_height>0.0 and Rect2(Vector2.ZERO,size).encloses(bounds)
	for text in [first,second]:
		var lines: Array[String]=_wrap_engine_feedback(text,maxf(1.0,bounds.size.x-24.0),pixels)
		for line in lines:
			fits=fits and _font.get_string_size(line,HORIZONTAL_ALIGNMENT_LEFT,-1,pixels).x<=bounds.size.x-24.0
		fits=fits and lines.size()*line_height<=row_height
		rows.append(lines)
	return {"bounds":bounds,"texts":[first,second],"rows":rows,"pixels":pixels,"line_height":line_height,"row_height":row_height,"fits":fits,"retained":retained}

func _draw_piston_strip() -> void:
	var layout: Dictionary=_engine_feedback_layout()
	var bounds: Rect2=layout.bounds
	_box(bounds,Color("14222d"),Color("425162") if layout.fits else RED,6)
	# Render every complete row, even for an unfit caller rectangle: the red
	# boundary makes that composition failure visible instead of hiding truth.
	for row in 2:
		for line in layout.rows[row].size():
			var baseline: float=bounds.position.y+6.0+row*layout.row_height+_font.get_ascent(layout.pixels)+line*layout.line_height
			_text(Vector2(bounds.position.x+12.0,baseline),layout.rows[row][line],layout.pixels,(AMBER if layout.retained else CYAN) if row==0 else MUTED)

func _draw_classic_panel(top: float, height: float) -> void:
	var slot := (height - 44.0) * 0.5
	var grid_width := slot * 3.0
	var left := (size.x - grid_width) * 0.5
	_text(Vector2(35, top + 28), "NATIVE FLIGHT STATE", 12, MUTED)
	_text(Vector2(size.x * 0.5, top + 25), "FLIGHT INSTRUMENTS", 11, MUTED, true)
	for index in range(6):
		var col := index % 3
		var row := index / 3
		var cell := Rect2(left + col * slot, top + 34 + row * slot, slot, slot)
		_draw_instrument(index, cell)
	var side_width := minf(left - 58.0, 300.0)
	if side_width > 160.0:
		_draw_engine(Rect2(maxf(34, left - side_width - 28), top + 62, side_width, height - 83))
		_draw_controls(Rect2(left + grid_width + 28, top + 62, side_width, height - 83))

func _draw_compact_panel(top: float, height: float) -> void:
	var usable := size.x - 56.0
	var slot_width := usable / 6.0
	var dial_height := height - 61.0
	for index in range(6):
		_draw_instrument(index, Rect2(28 + index * slot_width, top + 10, slot_width, dial_height))
	var baseline := size.y - 23.0
	_text(Vector2(usable * 0.02, baseline), "THR %03d%%" % roundi(float(_held.get("throttle", 0.0)) * 100), 12, CYAN)
	_text(Vector2(usable * 0.17, baseline), "BRAKES L %03d  R %03d" % [roundi(float(_held.get("left_brake", 0.0)) * 100), roundi(float(_held.get("right_brake", 0.0)) * 100)], 12, AMBER)
	_text(Vector2(usable * 0.43, baseline), "TRIM %+0.2f" % float(_held.get("trim", 0.0)), 12, INK)
	var fuel := float(_readings.get("fuel_kg", NAN))
	_text(Vector2(usable * 0.59, baseline), "FUEL "+_native_number(fuel,1)+" kg" if is_finite(fuel) else "FUEL —", 12, INK)
	_text(Vector2(usable * 0.78, baseline), _ground_label(), 12, GREEN if int(_readings.get("ground_contacts", 0)) > 0 else MUTED)

func _draw_instrument(index: int, cell: Rect2) -> void:
	var radius := minf(cell.size.x * 0.43, (cell.size.y - 26.0) * 0.5)
	var center := Vector2(cell.get_center().x, cell.position.y + radius + 4)
	draw_circle(center + Vector2(0, 4), radius + 4, Color(0, 0, 0, 0.45), true, -1, true)
	draw_circle(center, radius + 3, Color("252b30") if _cockpit_surface else Color("364151"), true, -1, true)
	draw_circle(center, radius + 1, Color("080d14"), true, -1, true)
	draw_circle(center, radius - 2, Color("0f151b") if _cockpit_surface else FACE, true, -1, true)
	draw_arc(center, radius + 2, PI * 1.10, PI * 1.90, 36, Color("56606a") if _cockpit_surface else Color("657488"), 1, true)
	if not _instrument_available(index):
		_text(center + Vector2(0, 6), "—", radius * 0.3, MUTED, true)
	elif absf(float(_readings.get(["tas_kt","pitch_deg","altitude_ft","heading_deg","yaw_rate_deg_s","vsi_fpm"][index],0.0)))>999999.0:
		# Keep the verified value visible without overflowing integer formatters.
		var numeric: String=_native_number(float(_readings[["tas_kt","pitch_deg","altitude_ft","heading_deg","yaw_rate_deg_s","vsi_fpm"][index]]),0)
		_text(center+Vector2(0,7),_bounded_text(numeric,radius*1.6,maxi(10,roundi(radius*0.17))),radius*0.17,INK,true)
		_text(center+Vector2(0,radius*0.42),"NUMERIC VIEW",radius*0.11,MUTED,true)
	else:
		match index:
			0: _airspeed(center, radius)
			1: _attitude(center, radius)
			2: _altimeter(center, radius)
			3: _heading(center, radius)
			4: _turn_rate(center, radius)
			5: _vertical_speed(center, radius)
	var titles := ["TRUE AIRSPEED", "ATTITUDE", "ELLIPSOID ALT", "TRUE HEADING", "BODY YAW RATE", "VERTICAL SPEED"]
	var units := ["kt · derived", "native truth", "ft · WGS84", "degrees", "°/s · body r", "ft/min · kinematic"]
	var label_y := cell.position.y + radius * 2 + 20
	if _cockpit_surface:
		var caption: Dictionary = _physical_dial_caption(index,titles[index],units[index])
		_text(Vector2(cell.get_center().x,caption.baseline),caption.text,caption.pixels,INK,true)
	else:
		_text(Vector2(cell.get_center().x, label_y), titles[index], clampf(radius * 0.14, 10, 15), INK, true)
		_text(Vector2(cell.get_center().x, label_y + 13), units[index], clampf(radius * 0.115, 10, 12), MUTED, true)

func _physical_dial_caption(index: int, title: String, unit: String) -> Dictionary:
	# Full qualifier in one line between projected rings; never ellipsize it.
	# Frozen eye/front depth + actual12px ascent13/descent4 bound these baselines.
	return {"text":title+" · "+unit,"baseline":262.7 if index<3 else 485.0,"pixels":12}

func _dial_label(center: Vector2, radius: float, at: Vector2, value: String, pixels: float, color: Color = INK) -> void:
	# Reserve the readout's footprint, including text ascenders and margins.
	# Keep every graduation; only omit labels obscured by the digital window.
	var relative := at - center
	if relative.y > radius * 0.20 and relative.y < radius * 0.76 and absf(relative.x) < radius * 0.68:
		return
	_text(at, value, maxf(pixels,13.0) if _cockpit_surface else pixels, color, true)

func _scale(center: Vector2, radius: float, limit: float, step: float, major: float) -> void:
	var value := 0.0
	while value <= limit + 0.01:
		var angle := deg_to_rad(135.0 + value / limit * 270.0)
		var big := absf(fposmod(value, major)) < 0.01
		_line(_polar(center, radius * (0.76 if big else 0.84), angle), _polar(center, radius * 0.91, angle), INK if big else MUTED, (2.0 if big else 1.15) if _cockpit_surface else (1.3 if big else 1.0))
		if big:
			_dial_label(center, radius, _polar(center, radius * 0.61, angle) + Vector2(0, radius * 0.055), str(roundi(value)), radius * 0.13)
		value += step

func _needle(center: Vector2, radius: float, angle: float, color: Color = AMBER, length: float = 0.75) -> void:
	var direction := Vector2(cos(angle), sin(angle))
	var normal := Vector2(-direction.y, direction.x)
	draw_colored_polygon(PackedVector2Array([center - direction * radius * 0.16 + normal * 2, center + direction * radius * length, center - direction * radius * 0.16 - normal * 2]), color)
	draw_circle(center, maxf(3.0, radius * 0.055), Color("cad2dc"), true, -1, true)
	draw_circle(center, maxf(1.5, radius * 0.025), FACE, true, -1, true)

func _digital(center: Vector2, radius: float, value: String, subtitle: String = "") -> void:
	var rect := Rect2(center.x - radius * 0.49, center.y + radius * 0.29, radius * 0.98, radius * 0.30)
	_box(rect, Color("080e17"), LINE, 3)
	_text(Vector2(center.x, rect.position.y + radius * 0.23), value, maxf(13, radius * 0.23), INK, true)
	if not subtitle.is_empty():
		if radius >= 82:
			_text(center + Vector2(0, radius * 0.75), subtitle, radius * 0.105, MUTED, true)

func _airspeed(center: Vector2, radius: float) -> void:
	_scale(center, radius, 160, 10, 40)
	_text(center + Vector2(0, -radius * 0.26), "TAS", radius * 0.15, MUTED, true)
	if not _readings.get("tas_valid", false):
		_digital(center, radius, "—", "NO WEATHER")
		return
	var speed := float(_readings.tas_kt)
	_needle(center, radius, deg_to_rad(135.0 + clampf(speed / 160.0, 0, 1) * 270.0))
	_digital(center, radius, "%03d" % roundi(speed))

func _attitude_point(center: Vector2, offset: Vector2, bank: float, pitch_shift: float) -> Vector2:
	return center + Vector2(offset.x, offset.y + pitch_shift).rotated(bank)

func _attitude(center: Vector2, radius: float) -> void:
	var bank := -deg_to_rad(float(_readings.roll_deg))
	var pitch := float(_readings.pitch_deg)
	var disk := radius * 0.88
	var shift := clampf(pitch, -85, 85) * disk / 35.0
	var horizon_a := Vector2.ZERO
	var horizon_b := Vector2.ZERO
	var show_horizon := false
	# Clip sky/earth by constructing each half of the same circular face.
	var sky := PackedVector2Array()
	var earth := PackedVector2Array()
	for index in range(97):
		var angle := TAU * index / 96.0
		var point := Vector2(cos(angle), sin(angle)) * disk
		var local := point.rotated(-bank)
		if local.y <= shift:
			sky.append(center + point)
		if local.y >= shift:
			earth.append(center + point)
	if absf(shift) < disk:
		var edge := sqrt(disk * disk - shift * shift)
		horizon_a = Vector2(-edge, shift).rotated(bank) + center
		horizon_b = Vector2(edge, shift).rotated(bank) + center
		show_horizon = true
		# Ordered convex polygon clipping keeps every point inside the bezel.
		sky = _clip_disk(center, disk, bank, shift, true)
		earth = _clip_disk(center, disk, bank, shift, false)
	if sky.size() >= 3:
		draw_colored_polygon(sky, Color("396480"))
	if earth.size() >= 3:
		draw_colored_polygon(earth, Color("76533d"))
	if show_horizon:
		_line(horizon_a, horizon_b, Color("ebf2f4"), 1.2)
	for degrees in [-20, -10, 0, 10, 20]:
		var vertical := shift - float(degrees) * disk / 35.0
		if absf(vertical) >= disk * 0.80:
			continue
		var half_width := disk * (0.35 if degrees == 0 else 0.23)
		var a := center + Vector2(-half_width, vertical).rotated(bank)
		var b := center + Vector2(half_width, vertical).rotated(bank)
		_line(a, b, Color("eef4f6"), 1.3)
		if degrees != 0:
			_text(center + Vector2(half_width + 7, vertical + 4).rotated(bank), str(absi(degrees)), radius * 0.105, INK)
	for degrees in [-60, -45, -30, -20, -10, 0, 10, 20, 30, 45, 60]:
		var angle := deg_to_rad(float(degrees) - 90)
		_line(_polar(center, radius * 0.91, angle), _polar(center, radius * (0.99 if absi(degrees) % 30 == 0 else 0.96), angle), INK, 1.2)
	var pointer := _polar(center, radius * 0.80, -PI * 0.5 + bank)
	draw_colored_polygon(PackedVector2Array([pointer, pointer + Vector2(-4, -7).rotated(bank), pointer + Vector2(4, -7).rotated(bank)]), AMBER)
	_line(center + Vector2(-radius * 0.50, 0), center + Vector2(-radius * 0.15, 0), AMBER, 3)
	_line(center + Vector2(radius * 0.15, 0), center + Vector2(radius * 0.50, 0), AMBER, 3)
	_line(center + Vector2(-radius * 0.15, 0), center + Vector2(-radius * 0.15, radius * 0.08), AMBER, 3)
	_line(center + Vector2(radius * 0.15, 0), center + Vector2(radius * 0.15, radius * 0.08), AMBER, 3)
	draw_circle(center, 2, AMBER, true, -1, true)

func _clip_disk(center: Vector2, radius: float, bank: float, shift: float, sky: bool) -> PackedVector2Array:
	var points := PackedVector2Array()
	var previous := Vector2(radius, 0)
	var previous_side := previous.rotated(-bank).y - shift
	for index in range(1, 98):
		var current := Vector2(cos(TAU * index / 97.0), sin(TAU * index / 97.0)) * radius
		var side := current.rotated(-bank).y - shift
		var before := previous_side <= 0 if sky else previous_side >= 0
		var inside := side <= 0 if sky else side >= 0
		if before != inside:
			points.append(center + previous.lerp(current, previous_side / (previous_side - side)))
		if inside:
			points.append(center + current)
		previous = current
		previous_side = side
	return points

func _altimeter(center: Vector2, radius: float) -> void:
	for digit in range(10):
		var angle := -PI * 0.5 + digit * TAU / 10.0
		_line(_polar(center, radius * 0.79, angle), _polar(center, radius * 0.91, angle), INK, 1.4)
		_dial_label(center, radius, _polar(center, radius * 0.65, angle) + Vector2(0, radius * 0.055), str(digit), radius * 0.15)
		for minor in range(1, 5):
			var tick_angle := angle + minor * TAU / 50.0
			_line(_polar(center, radius * 0.87, tick_angle), _polar(center, radius * 0.91, tick_angle), MUTED)
	var altitude := float(_readings.altitude_ft)
	_needle(center, radius, -PI * 0.5 + altitude / 10000.0 * TAU, CYAN, 0.47)
	_needle(center, radius, -PI * 0.5 + altitude / 1000.0 * TAU, INK, 0.77)
	_text(center + Vector2(0, -radius * 0.28), "ELLIPSOID", radius * 0.115, MUTED, true)
	_digital(center, radius, "%05d" % roundi(altitude))

func _heading(center: Vector2, radius: float) -> void:
	var heading := float(_readings.heading_deg)
	for degrees in range(0, 360, 10):
		var angle := deg_to_rad(float(degrees) - heading - 90)
		var major := degrees % 30 == 0
		_line(_polar(center, radius * (0.78 if major else 0.86), angle), _polar(center, radius * 0.92, angle), INK if major else MUTED)
		if major:
			var label := str(degrees / 10)
			if degrees % 90 == 0:
				label = ["N", "E", "S", "W"][degrees / 90]
			_dial_label(center, radius, _polar(center, radius * 0.63, angle) + Vector2(0, radius * 0.06), label, radius * 0.16, CYAN if degrees == 0 else INK)
	draw_colored_polygon(PackedVector2Array([center + Vector2(0, -radius * 0.74), center + Vector2(-4, -radius * 0.98), center + Vector2(4, -radius * 0.98)]), AMBER)
	_line(center + Vector2(-radius * 0.18, 0), center + Vector2(radius * 0.18, 0), AMBER, 2)
	_line(center + Vector2(0, -radius * 0.22), center + Vector2(0, radius * 0.13), AMBER, 2)
	_digital(center, radius, "%03d°" % (roundi(heading) % 360))

func _vertical_speed(center: Vector2, radius: float) -> void:
	for step in range(-4, 5):
		var angle := PI + float(step) / 4.0 * PI * 0.78
		_line(_polar(center, radius * 0.80, angle), _polar(center, radius * 0.91, angle), INK, 1.3)
		_dial_label(center, radius, _polar(center, radius * 0.62, angle) + Vector2(0, radius * 0.055), str(absi(step) * 5), radius * 0.13)
	var rate := float(_readings.vsi_fpm)
	_needle(center, radius, PI + clampf(rate / 2000.0, -1, 1) * PI * 0.78)
	_text(center + Vector2(radius * 0.25, -radius * 0.12), "+", radius * 0.15, MUTED, true)
	_text(center + Vector2(radius * 0.25, radius * 0.18), "−", radius * 0.15, MUTED, true)
	if radius >= 82:
		_text(center + Vector2(0, -radius * 0.30), "×100", radius * 0.11, MUTED, true)
	_digital(center, radius, "%+05d" % roundi(rate))

func _turn_rate(center: Vector2, radius: float) -> void:
	var rate := float(_readings.yaw_rate_deg_s)
	_text(center + Vector2(-radius * 0.52, -radius * 0.33), "L", radius * 0.18, MUTED, true)
	_text(center + Vector2(radius * 0.52, -radius * 0.33), "R", radius * 0.18, MUTED, true)
	for step in range(-2, 3):
		var xx := float(step) * radius * 0.29
		_line(center + Vector2(xx, -radius * 0.13), center + Vector2(xx, radius * 0.05), MUTED, 1.3)
	var indicated := clampf(rate / 6.0, -1, 1) * radius * 0.57
	draw_colored_polygon(PackedVector2Array([center + Vector2(indicated, -radius * 0.23), center + Vector2(indicated - 4, -radius * 0.40), center + Vector2(indicated + 4, -radius * 0.40)]), AMBER)
	_text(center + Vector2(0, radius * 0.14), "BODY r", radius * 0.14, MUTED, true)
	_digital(center, radius, "%+04.1f" % rate)

func _bar(at: Vector2, width: float, value: float, color: Color) -> void:
	_box(Rect2(at, Vector2(width, 7)), Color("070d16"), Color("263447"), 3)
	draw_rect(Rect2(at + Vector2(1, 1), Vector2((width - 2) * clampf(value, 0, 1), 5)), color)

func _ground_label() -> String:
	if not _info.get("ground_valid", false) or not _readings.get("contacts_valid",true):
		return "GROUND UNAVAILABLE"
	var count := int(_readings.get("ground_contacts", 0))
	return "GEAR CLEAR · 0/3" if count == 0 else "CONTACT  %d / 3" % count

func _draw_engine(rect: Rect2) -> void:
	if _info.has("engine_status"):
		_text(rect.position,"PISTON & FIXED PROP",13,MUTED)
		_text(rect.position+Vector2(0,44),_engine_number("propeller.angular_speed",60.0/TAU),35,CYAN)
		_text(rect.position+Vector2(115,43),"RPM",12,MUTED)
		_text(rect.position+Vector2(0,76),_engine_phase(),14,GREEN if _engine_channel("engine.running")==true else AMBER)
		_text(rect.position+Vector2(0,107),"MIXTURE  "+_engine_number("engine.mixture",100.0)+"%",14)
		_text(rect.position+Vector2(0,138),"FUEL  "+_engine_number("fuel.total",1.0,1)+" kg",14)
		_text(rect.position+Vector2(0,172),"IGN L "+_engine_switch("engine.ignition_left")+" / R "+_engine_switch("engine.ignition_right"),12)
		_text(rect.position+Vector2(0,200),"STARTER  "+_engine_switch("engine.starter"),12,AMBER)
		_text(rect.position+Vector2(0,228),"FEED "+_engine_switch("fuel.feed")+" · STARVED "+_engine_switch("engine.starved"),12)
		_text(rect.position+Vector2(0,254),"IDEALIZED STARTER SUPPLY",10,MUTED)
		_text(rect.position+Vector2(0,278),"NATIVE TRUTH · NOT SENSORS",10,MUTED)
		return
	_text(rect.position + Vector2(0, 0), "POWER & FUEL", 13, MUTED)
	var throttle := float(_held.get("throttle", 0.0))
	_text(rect.position + Vector2(0, 44), "%03d" % roundi(throttle * 100), 35, CYAN)
	_text(rect.position + Vector2(80, 43), "% THROTTLE", 12, MUTED)
	_bar(rect.position + Vector2(0, 61), rect.size.x, throttle, CYAN)
	var fuel := float(_readings.get("fuel_kg", NAN))
	_text(rect.position + Vector2(0, 106), _bounded_text(_native_number(fuel,1),92.0,28) if is_finite(fuel) else "—", 28)
	_text(rect.position + Vector2(100, 105), "kg FUEL", 12, MUTED)
	if is_finite(fuel):
		_bar(rect.position + Vector2(0, 120), rect.size.x, fuel / 100.0, GREEN)
	_text(rect.position + Vector2(0, 155), "ORIGINAL SYNTHETIC ENGINE", 10, MUTED)
	_line(rect.position + Vector2(0, 171), rect.position + Vector2(rect.size.x, 171), LINE)
	_text(rect.position + Vector2(0, 196), _ground_label(), 15, GREEN if int(_readings.get("ground_contacts", 0)) > 0 else CYAN)
	var clearance := float(_info.get("clearance_m", 0.0))
	_text(rect.position + Vector2(0, 222), "CG CLEARANCE  %.1f m" % clearance if _info.get("ground_valid", false) else "CG CLEARANCE  —", 12, MUTED)
	_text(rect.position + Vector2(0, 253), "GS "+_native_number(float(_readings.ground_kt),0)+" kt" if _readings.get("channel_valid",{}).get("ground_speed",true) and is_finite(float(_readings.get("ground_kt",NAN))) else "GS — kt", 12, INK)
	_text(rect.position + Vector2(0, 278), "NATIVE TRUTH · NOT SENSORS", 10, MUTED)

func _draw_controls(rect: Rect2) -> void:
	_text(rect.position, "HELD PILOT CONTROLS", 13, MUTED)
	for index in range(2):
		var label := "LEFT BRAKE" if index == 0 else "RIGHT BRAKE"
		var value := float(_held.get("left_brake" if index == 0 else "right_brake", 0.0))
		var y := 35 + index * 49
		_text(rect.position + Vector2(0, y), label, 11, MUTED)
		_text(rect.position + Vector2(rect.size.x - 43, y), "%03d%%" % roundi(value * 100), 12, AMBER)
		_bar(rect.position + Vector2(0, y + 11), rect.size.x, value, AMBER)
	var hold := "HOLD ON · B RELEASES" if _info.get("brake_hold", false) else "HOLD OFF · SPACE BRAKES"
	_text(rect.position + Vector2(0, 141), hold, 11, AMBER if _info.get("brake_hold", false) else MUTED)
	_text(rect.position + Vector2(0, 181), "TRIM", 11, MUTED)
	var trim := float(_held.get("trim", 0.0))
	_text(rect.position + Vector2(rect.size.x - 60, 181), "%+0.2f" % trim, 15)
	_line(rect.position + Vector2(0, 200), rect.position + Vector2(rect.size.x, 200), LINE, 3)
	var trim_x := (clampf(trim, -1, 1) + 1) * 0.5 * rect.size.x
	draw_circle(rect.position + Vector2(trim_x, 200), 4, CYAN, true, -1, true)
	_text(rect.position + Vector2(0, 224), "NOSE DOWN", 9, MUTED)
	_text(rect.position + Vector2(rect.size.x - 64, 224), "NOSE UP", 9, MUTED)
	_text(rect.position + Vector2(0, 254), str(_info.get("input_name", "KEYBOARD")).to_upper(), 11, MUTED)
	_text(rect.position + Vector2(0, 279), "H  CONTROLS & DISPLAY GUIDE", 10, MUTED)

func _physical_engine_rows() -> Dictionary:
	# Presentation-only formatting; the existing copied EngineStatus remains owner.
	return {"rpm":_engine_number("propeller.angular_speed",60.0/TAU),"mixture":_engine_number("engine.mixture",100.0)+"%"}

func _draw_cockpit_surface() -> void:
	draw_rect(Rect2(0, 0, 1024, 512), Color("161c24"))
	_box(Rect2(7, 7, 1010, 498), Color("1b2532"), Color("495361"), 14)
	_text(Vector2(27, 31), "FLIGHT INSTRUMENTS", 15, MUTED)
	_text(Vector2(705, 31), "NATIVE TRUTH · PROTOTYPE", 12, AMBER)
	_line(Vector2(26, 43), Vector2(994, 43), LINE)
	# Classic scan: TAS / attitude / altitude, heading / body yaw / VSI.
	for index in range(6):
		_draw_instrument(index, Rect2(24 + (index % 3) * 221, 50 + (index / 3) * 219, 213, 219))
	_line(Vector2(709, 61), Vector2(709, 480), LINE)
	var x := 738.0
	var width := 244.0
	_text(Vector2(x, 81), "THROTTLE", 13, MUTED)
	_text(Vector2(x + 163, 82), "%03d%%" % roundi(float(_held.get("throttle", 0.0)) * 100), 19, CYAN)
	_bar(Vector2(x, 95), width, float(_held.get("throttle", 0.0)), CYAN)
	var fuel := float(_readings.get("fuel_kg", NAN))
	_text(Vector2(x, 137), "FUEL", 13, MUTED)
	_text(Vector2(x + 125, 138), _bounded_text(_native_number(fuel,1)+" kg",119.0,19) if is_finite(fuel) else "— kg", 19)
	if is_finite(fuel):
		_bar(Vector2(x, 151), width, fuel / 100.0, GREEN)
	if _info.has("engine_status"):
		# Two bounded native rows, below the fuel bar and above the divider.
		var engine_rows: Dictionary = _physical_engine_rows()
		_text(Vector2(x,176),"RPM",13,MUTED)
		_text(Vector2(x+96,176),_bounded_text(engine_rows.rpm,148.0,16),16,CYAN)
		_text(Vector2(x,193),"MIXTURE",12,MUTED)
		_text(Vector2(x+136,193),_bounded_text(engine_rows.mixture,108.0,14),14,INK)
	else:
		_text(Vector2(x, 181), "ORIGINAL SYNTHETIC ENGINE", 11, MUTED)
	_line(Vector2(x, 199), Vector2(x + width, 199), LINE)
	for index in range(2):
		var y := 229 + index * 52
		var name := "LEFT BRAKE" if index == 0 else "RIGHT BRAKE"
		var value := float(_held.get("left_brake" if index == 0 else "right_brake", 0.0))
		_text(Vector2(x, y), name, 13, MUTED)
		_text(Vector2(x + 164, y), "%03d%%" % roundi(value * 100), 16, AMBER)
		_bar(Vector2(x, y + 12), width, value, AMBER)
	var trim := float(_held.get("trim", 0.0))
	_text(Vector2(x, 341), "TRIM", 13, MUTED)
	_text(Vector2(x + 169, 341), "%+0.2f" % trim, 18)
	_line(Vector2(x, 359), Vector2(x + width, 359), LINE, 3)
	draw_circle(Vector2(x + (clampf(trim, -1, 1) + 1) * width * 0.5, 359), 5, CYAN, true, -1, true)
	_text(Vector2(x, 381), "NOSE DOWN", 10, MUTED)
	_text(Vector2(x + width - 61, 381), "NOSE UP", 10, MUTED)
	_line(Vector2(x, 400), Vector2(x + width, 400), LINE)
	_text(Vector2(x, 430), _ground_label(), 15, GREEN if int(_readings.get("ground_contacts", 0)) > 0 else CYAN)
	var clearance := float(_info.get("clearance_m", 0.0))
	_text(Vector2(x, 456), "CG clearance %.1f m" % clearance if _info.get("ground_valid", false) else "CG clearance —", 13, MUTED)
	if _info.get("retained",false) or _info.get("blocked", false) or _info.get("stalled", false) or str(_info.get("outcome", "")) in ["discarded","error","coverage_blocked"]:
		_text(Vector2(x, 484), "RETAINED STATE · STOPPED", 12, RED)
	elif _info.get("paused", false):
		_text(Vector2(x, 484), "PAUSED", 14, AMBER)
	else:
		_text(Vector2(x, 484), "ORIGINAL ENGINEERING MODEL", 10, MUTED)

func _draw_help() -> void:
	var width := minf(760, size.x - 60)
	var height := minf(458, size.y - 105)
	var rect := Rect2((size.x - width) * 0.5, maxf(64, (size.y - height) * 0.30), width, height)
	_box(rect, Color("101c2c"), Color("526e86"), 12)
	_text(rect.position + Vector2(24, 34), "FLIGHT CONTROLS", 21)
	_text(rect.position + Vector2(width - 110, 32), "H  CLOSE", 12, CYAN)
	var rows := ["↑ / ↓  Pitch    ← / →  Roll    A / D  Yaw & steering",
		"W / S or Page Up / Down  Throttle    X  Idle    [ / ]  Trim",
		"B  Toggle brake hold    Hold Space  Both brakes    Q / E  Left / right",
		"1  Cockpit    2  Chase    3  External    4  Panel    C  Cycle views",
		"Hold right mouse  Look    Scroll  Zoom    Home  Reset look",
		"P / Escape  Pause menu    R  Fresh start    G / F  Ground / air",
		"V  Overlay    F11  Fullscreen    M  Audio    J  Select controller",
		"Tab  Map    + / −  Zoom    T  Runway 36 / 18"]
	var row_height := minf(30, (height - 170) / rows.size())
	for index in range(rows.size()):
		_text(rect.position + Vector2(24, 73 + index * row_height), rows[index], 14)
	var footer := height - 106
	_line(rect.position + Vector2(24, footer), rect.position + Vector2(width - 24, footer), LINE)
	_text(rect.position + Vector2(24, footer + 26), "Original piston prototype · deliberate cold engine controls" if _info.has("engine_status") else "Original engineering aircraft · engine already running", 13, AMBER)
	_text(rect.position + Vector2(24, footer + 51), "Derived TAS · WGS84 ellipsoid feet · true heading · body yaw rate", 12, MUTED)
	_text(rect.position + Vector2(24, footer + 74), "Native truth, not IAS / magnetic / turn-slip sensors or Cessna calibration.", 12, MUTED)
	_text(rect.position + Vector2(24, footer + 96), "Display scales are not operating limits. The panel cannot modify physics.", 12, MUTED)

func _native_number(value: float, decimals: int) -> String:
	if not is_finite(value):
		return "—"
	if absf(value)>999999.0:
		var exponent: int=int(floor(log(absf(value))/log(10.0)))
		var mantissa: float=value/pow(10.0,exponent)
		return "%.2fe%d" % [mantissa,exponent]
	return ("%.1f" if decimals==1 else "%.0f") % value

func _bounded_text(value: String, width: float, pixels: int) -> String:
	if _font.get_string_size(value,HORIZONTAL_ALIGNMENT_LEFT,-1,pixels).x<=width:
		return value
	var fitted: String=value
	while not fitted.is_empty() and _font.get_string_size(fitted+"…",HORIZONTAL_ALIGNMENT_LEFT,-1,pixels).x>width:
		fitted=fitted.left(fitted.length()-1)
	return fitted+"…"

# Original MIT shared drawing boundary. NativeReadings remains the
# authoritative SI producer; display conversion does not change flight.
static func _reading_keys(value: Variant, keys: Array) -> bool:
	if not value is Dictionary or value.size()!=keys.size():
		return false
	for key in value:
		if not key is String or not keys.has(key):
			return false
	return true

static func _reading_identity(value: Dictionary) -> bool:
	var session: Variant=value.session_id
	var tick: Variant=value.tick
	if not session is String or session.is_empty() or session.length()>128 or not session[0]>="a" or not session[0]<="z":
		return false
	var separator: bool=false
	for index in session.length():
		var code: int=session.unicode_at(index)
		if (code>=97 and code<=122) or (code>=48 and code<=57):
			separator=false
		elif code in [46,45,95] and not separator:
			separator=true
		else:
			return false
	if separator or not tick is String or tick.is_empty() or tick.length()>20 or (tick.length()>1 and tick[0]=="0"):
		return false
	for index in tick.length():
		if tick.unicode_at(index)<48 or tick.unicode_at(index)>57:
			return false
	return tick.length()<20 or tick<="18446744073709551615"

static func display_readings(value: Dictionary) -> Dictionary:
	var unavailable: Dictionary={"valid":false,"tas_valid":false,"channel_valid":{}}
	if not _reading_keys(value,["session_id","tick","state","native_truth","readings","error"]) or typeof(value.native_truth)!=TYPE_BOOL or not value.native_truth or not value.state is String or not value.state in ["live","paused","historical"] or not value.error is String or not value.error.is_empty() or not _reading_identity(value):
		return unavailable
	var units: Dictionary={"tas":"m/s","ground_speed":"m/s","pitch":"rad","bank":"rad","heading_true":"rad","ellipsoid_height":"m","vertical_speed":"m/s","body_yaw_rate":"rad/s","fuel_total":"kg"}
	var fields: Dictionary={"tas":"tas_kt","ground_speed":"ground_kt","pitch":"pitch_deg","bank":"roll_deg","heading_true":"heading_deg","ellipsoid_height":"altitude_ft","vertical_speed":"vsi_fpm","body_yaw_rate":"yaw_rate_deg_s","fuel_total":"fuel_kg"}
	if not _reading_keys(value.readings,units.keys()):
		return unavailable
	var result: Dictionary={"valid":true,"tas_valid":false,"channel_valid":{}}
	for id in units:
		var channel: Variant=value.readings.get(id)
		if not _reading_keys(channel,["value","unit","valid","error"]) or typeof(channel.valid)!=TYPE_BOOL or not channel.unit is String or channel.unit!=units[id] or not channel.error is String or channel.error.length()>1024:
			return unavailable
		result.channel_valid[id]=false
		if not channel.valid:
			if channel.get("value")!=null or channel.error.is_empty():
				return unavailable
			continue
		if typeof(channel.get("value"))!=TYPE_FLOAT or not is_finite(channel.value) or not channel.error.is_empty():
			return unavailable
		var converted: float=channel.value
		if id in ["tas","ground_speed"]:
			converted*=MPS_TO_KT
		elif id=="ellipsoid_height":
			converted*=M_TO_FT
		elif id=="vertical_speed":
			converted*=MPS_TO_FPM
		elif id in ["pitch","bank","heading_true","body_yaw_rate"]:
			converted=rad_to_deg(converted)
		if is_finite(converted):
			result[fields[id]]=converted
			result.channel_valid[id]=true
	result.tas_valid=result.channel_valid.tas
	return result

func set_native_readings(value: Dictionary, state: Dictionary, held: Dictionary, info: Dictionary) -> void:
	_snapshot=state.duplicate(true)
	_atmosphere={}
	_held=held.duplicate(true)
	_info=info.duplicate(true)
	_readings=display_readings(value)
	if _readings.valid and (state.get("session_id")!=value.session_id or state.get("tick")!=value.tick):
		_readings={"valid":false,"tas_valid":false,"channel_valid":{}}
		_info.status="Reading publication and contact state disagree"
	_info.retained=value.get("state")=="historical"
	if value.get("state") in ["live","paused"]:
		_info.paused=value.state=="paused"
	var contacts: int=0
	var contacts_valid: bool=_readings.valid and state.get("contacts") is Array
	if contacts_valid:
		for contact in _snapshot.contacts:
			if not contact is Dictionary or typeof(contact.get("on_ground"))!=TYPE_BOOL:
				contacts_valid=false
			elif contact.on_ground:
				contacts+=1
	_readings.ground_contacts=contacts
	_readings.contacts_valid=contacts_valid
	if not contacts_valid:
		_info.ground_valid=false
	queue_redraw()

func _instrument_available(index: int) -> bool:
	if not _readings.get("valid",false):
		return false
	# Historical proof keeps its original derivation. Ordinary flight always
	# supplies the shared validated channel map instead of missing-value zeros.
	if not _readings.has("channel_valid"):
		return true
	var channels: Dictionary=_readings.channel_valid
	if index==1:
		return channels.get("pitch",false) and channels.get("bank",false)
	return channels.get(["tas","","ellipsoid_height","heading_true","body_yaw_rate","vertical_speed"][index],false)
