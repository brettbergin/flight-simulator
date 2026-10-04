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
const MPS_TO_KT := 1.9438444924406
const M_TO_FT := 3.2808398950131
const MPS_TO_FPM := 196.85039370079

var _snapshot: Dictionary = {}
var _atmosphere: Dictionary = {}
var _held: Dictionary = {}
var _info: Dictionary = {}
var _readings: Dictionary = {}
var _help_visible := false
var _panel_visible := true
var _font: Font = ThemeDB.fallback_font

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

func set_help_visible(value: bool) -> void:
	_help_visible = value
	queue_redraw()

func set_panel_visible(value: bool) -> void:
	_panel_visible = value
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
		"ground_kt": velocity_ned.length() * MPS_TO_KT, "roll_deg": rad_to_deg(roll_rad),
		"pitch_deg": rad_to_deg(pitch_rad), "heading_deg": fposmod(rad_to_deg(heading_rad), 360.0),
		"altitude_ft": float(state.get("position", {}).get("ellipsoid_height_m", 0.0)) * M_TO_FT,
		"vsi_fpm": -velocity_ned.z * MPS_TO_FPM,
		"yaw_rate_deg_s": rad_to_deg(float(state.get("angular_rate_body_radps", {}).get("z", 0.0))),
		"fuel_kg": fuel, "ground_contacts": gear_on}

func _draw() -> void:
	if size.x < 640.0 or size.y < 400.0:
		return
	_draw_topbar()
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
	_text(Vector2(151, 28), "LAB", 13, MUTED)
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
	if _readings.get("valid", false) == false:
		status = "WAITING FOR STATE"
		status_color = MUTED
	draw_circle(Vector2(318, 23), 3, status_color, true, -1, true)
	_text(Vector2(329, 28), status, 12, status_color)
	var view_name := str(_info.get("view_name", "FLIGHT VIEW")).to_upper()
	_text(Vector2(width * 0.61, 28), view_name, 12, MUTED, true)
	_text(Vector2(width - 225, 28), "P  PAUSE     R  RESET     H  HELP", 11, MUTED)
	if _info.get("blocked",false) or _info.get("stalled",false):
		draw_rect(Rect2(0,46,width,32),Color("492a20"))
		_text(Vector2(18,68),str(_info.get("status","Flight stopped; R starts a fresh attempt")).left(int((width-36)/7.5)),13,AMBER)

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
	_text(Vector2(34, baseline), "THR %03d%%" % roundi(float(_held.get("throttle", 0.0)) * 100), 12, CYAN)
	_text(Vector2(160, baseline), "BRAKES  L %03d  R %03d" % [roundi(float(_held.get("left_brake", 0.0)) * 100), roundi(float(_held.get("right_brake", 0.0)) * 100)], 12, AMBER)
	_text(Vector2(385, baseline), "TRIM %+0.2f" % float(_held.get("trim", 0.0)), 12, INK)
	var fuel := float(_readings.get("fuel_kg", NAN))
	_text(Vector2(530, baseline), "FUEL %.1f kg" % fuel if is_finite(fuel) else "FUEL —", 12, INK)
	_text(Vector2(size.x - 220, baseline), _ground_label(), 12, GREEN if int(_readings.get("ground_contacts", 0)) > 0 else MUTED)

func _draw_instrument(index: int, cell: Rect2) -> void:
	var radius := minf(cell.size.x * 0.43, (cell.size.y - 26.0) * 0.5)
	var center := Vector2(cell.get_center().x, cell.position.y + radius + 4)
	draw_circle(center + Vector2(0, 4), radius + 4, Color(0, 0, 0, 0.45), true, -1, true)
	draw_circle(center, radius + 3, Color("364151"), true, -1, true)
	draw_circle(center, radius + 1, Color("080d14"), true, -1, true)
	draw_circle(center, radius - 2, FACE, true, -1, true)
	draw_arc(center, radius + 2, PI * 1.10, PI * 1.90, 36, Color("657488"), 1, true)
	if not _readings.get("valid", false):
		_text(center + Vector2(0, 6), "—", radius * 0.3, MUTED, true)
	else:
		match index:
			0: _airspeed(center, radius)
			1: _attitude(center, radius)
			2: _altimeter(center, radius)
			3: _turn_rate(center, radius)
			4: _heading(center, radius)
			5: _vertical_speed(center, radius)
	var names := ["TRUE AIRSPEED · kt", "ATTITUDE · TRUTH", "ALTITUDE · ELLIPSOID ft", "BODY YAW RATE · °/s", "HEADING · TRUE", "VERTICAL SPEED · ft/min"]
	_text(Vector2(cell.get_center().x, cell.position.y + radius * 2 + 24), names[index], clampf(radius * 0.12, 10, 13), MUTED, true)

func _scale(center: Vector2, radius: float, limit: float, step: float, major: float) -> void:
	var value := 0.0
	while value <= limit + 0.01:
		var angle := deg_to_rad(135.0 + value / limit * 270.0)
		var big := absf(fposmod(value, major)) < 0.01
		_line(_polar(center, radius * (0.76 if big else 0.84), angle), _polar(center, radius * 0.91, angle), INK if big else MUTED, 1.3 if big else 1.0)
		if big:
			_text(_polar(center, radius * 0.61, angle) + Vector2(0, radius * 0.055), str(roundi(value)), radius * 0.13, INK, true)
		value += step

func _needle(center: Vector2, radius: float, angle: float, color: Color = AMBER, length: float = 0.75) -> void:
	var direction := Vector2(cos(angle), sin(angle))
	var normal := Vector2(-direction.y, direction.x)
	draw_colored_polygon(PackedVector2Array([center - direction * radius * 0.16 + normal * 2, center + direction * radius * length, center - direction * radius * 0.16 - normal * 2]), color)
	draw_circle(center, maxf(3.0, radius * 0.055), Color("cad2dc"), true, -1, true)
	draw_circle(center, maxf(1.5, radius * 0.025), FACE, true, -1, true)

func _digital(center: Vector2, radius: float, value: String, subtitle: String = "") -> void:
	var rect := Rect2(center.x - radius * 0.42, center.y + radius * 0.30, radius * 0.84, radius * 0.27)
	_box(rect, Color("080e17"), LINE, 3)
	_text(Vector2(center.x, rect.position.y + radius * 0.20), value, radius * 0.19, INK, true)
	if not subtitle.is_empty():
		_text(center + Vector2(0, radius * 0.73), subtitle, radius * 0.11, MUTED, true)

func _airspeed(center: Vector2, radius: float) -> void:
	_scale(center, radius, 160, 10, 40)
	_text(center + Vector2(0, -radius * 0.26), "TAS", radius * 0.15, MUTED, true)
	if not _readings.get("tas_valid", false):
		_digital(center, radius, "—", "NO WEATHER")
		return
	var speed := float(_readings.tas_kt)
	_needle(center, radius, deg_to_rad(135.0 + clampf(speed / 160.0, 0, 1) * 270.0))
	_digital(center, radius, "%03d" % roundi(speed), "DERIVED")

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
	_text(center + Vector2(0, radius * 0.66), "P %+04.1f°   B %+04.1f°" % [pitch, float(_readings.roll_deg)], radius * 0.105, INK, true)

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
		_text(_polar(center, radius * 0.65, angle) + Vector2(0, radius * 0.055), str(digit), radius * 0.15, INK, true)
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
			_text(_polar(center, radius * 0.63, angle) + Vector2(0, radius * 0.06), label, radius * 0.16, CYAN if degrees == 0 else INK, true)
	draw_colored_polygon(PackedVector2Array([center + Vector2(0, -radius * 0.74), center + Vector2(-4, -radius * 0.98), center + Vector2(4, -radius * 0.98)]), AMBER)
	_line(center + Vector2(-radius * 0.18, 0), center + Vector2(radius * 0.18, 0), AMBER, 2)
	_line(center + Vector2(0, -radius * 0.22), center + Vector2(0, radius * 0.13), AMBER, 2)
	_digital(center, radius, "%03d°" % (roundi(heading) % 360))

func _vertical_speed(center: Vector2, radius: float) -> void:
	for step in range(-4, 5):
		var angle := PI + float(step) / 4.0 * PI * 0.78
		_line(_polar(center, radius * 0.80, angle), _polar(center, radius * 0.91, angle), INK, 1.3)
		_text(_polar(center, radius * 0.62, angle) + Vector2(0, radius * 0.055), str(absi(step) * 5), radius * 0.13, INK, true)
	var rate := float(_readings.vsi_fpm)
	_needle(center, radius, PI + clampf(rate / 2000.0, -1, 1) * PI * 0.78)
	_text(center + Vector2(radius * 0.24, -radius * 0.15), "UP", radius * 0.12, MUTED, true)
	_text(center + Vector2(radius * 0.24, radius * 0.17), "DN", radius * 0.12, MUTED, true)
	_text(center + Vector2(0, -radius * 0.38), "×100 ft/min", radius * 0.10, MUTED, true)
	_digital(center, radius, "%+05d" % roundi(rate), "KINEMATIC")

func _turn_rate(center: Vector2, radius: float) -> void:
	var rate := float(_readings.yaw_rate_deg_s)
	_text(center + Vector2(-radius * 0.52, -radius * 0.33), "L", radius * 0.18, MUTED, true)
	_text(center + Vector2(radius * 0.52, -radius * 0.33), "R", radius * 0.18, MUTED, true)
	for step in range(-2, 3):
		var xx := float(step) * radius * 0.29
		_line(center + Vector2(xx, -radius * 0.13), center + Vector2(xx, radius * 0.05), MUTED, 1.3)
	var indicated := clampf(rate / 6.0, -1, 1) * radius * 0.57
	draw_colored_polygon(PackedVector2Array([center + Vector2(indicated, -radius * 0.23), center + Vector2(indicated - 4, -radius * 0.40), center + Vector2(indicated + 4, -radius * 0.40)]), AMBER)
	_text(center + Vector2(0, radius * 0.23), "BODY r", radius * 0.14, MUTED, true)
	_digital(center, radius, "%+04.1f" % rate)

func _bar(at: Vector2, width: float, value: float, color: Color) -> void:
	_box(Rect2(at, Vector2(width, 7)), Color("070d16"), Color("263447"), 3)
	draw_rect(Rect2(at + Vector2(1, 1), Vector2((width - 2) * clampf(value, 0, 1), 5)), color)

func _ground_label() -> String:
	if not _info.get("ground_valid", false):
		return "GROUND UNAVAILABLE"
	var count := int(_readings.get("ground_contacts", 0))
	return "AIRBORNE" if count == 0 else "CONTACT  %d / 3" % count

func _draw_engine(rect: Rect2) -> void:
	_text(rect.position + Vector2(0, 0), "POWER & FUEL", 13, MUTED)
	var throttle := float(_held.get("throttle", 0.0))
	_text(rect.position + Vector2(0, 44), "%03d" % roundi(throttle * 100), 35, CYAN)
	_text(rect.position + Vector2(80, 43), "% THROTTLE", 12, MUTED)
	_bar(rect.position + Vector2(0, 61), rect.size.x, throttle, CYAN)
	var fuel := float(_readings.get("fuel_kg", NAN))
	_text(rect.position + Vector2(0, 106), "%.1f" % fuel if is_finite(fuel) else "—", 28)
	_text(rect.position + Vector2(100, 105), "kg FUEL", 12, MUTED)
	if is_finite(fuel):
		_bar(rect.position + Vector2(0, 120), rect.size.x, fuel / 100.0, GREEN)
	_text(rect.position + Vector2(0, 155), "RUNNING ENGINE · SYNTHETIC", 10, MUTED)
	_line(rect.position + Vector2(0, 171), rect.position + Vector2(rect.size.x, 171), LINE)
	_text(rect.position + Vector2(0, 196), _ground_label(), 15, GREEN if int(_readings.get("ground_contacts", 0)) > 0 else CYAN)
	var clearance := float(_info.get("clearance_m", 0.0))
	_text(rect.position + Vector2(0, 222), "CG CLEARANCE  %.1f m" % clearance if _info.get("ground_valid", false) else "CG CLEARANCE  —", 12, MUTED)
	_text(rect.position + Vector2(0, 253), "GS  %.0f kt" % float(_readings.get("ground_kt", 0.0)), 12, INK)
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

func _draw_help() -> void:
	var width := minf(650, size.x - 80)
	var height := 335.0
	var rect := Rect2((size.x - width) * 0.5, maxf(62, (size.y - height) * 0.35), width, height)
	_box(rect, Color("101c2c"), Color("526e86"), 12)
	_text(rect.position + Vector2(24, 34), "FLIGHT CONTROLS", 21)
	_text(rect.position + Vector2(width - 110, 32), "H  CLOSE", 12, CYAN)
	var rows := ["↑ / ↓   Pitch        ← / →   Roll", "A / D   Yaw & nose steering", "Page Up / Down   Throttle       [ / ]   Trim", "B / Space   Hold / wheel brakes       Q / E   Left / right", "P   Pause / resume       R   Fresh start       C   View"]
	for index in range(rows.size()):
		_text(rect.position + Vector2(24, 73 + index * 28), rows[index], 15)
	_line(rect.position + Vector2(24, 215), rect.position + Vector2(width - 24, 215), LINE)
	_text(rect.position + Vector2(24, 241), "Original engineering aircraft · engine already running", 13, AMBER)
	_text(rect.position + Vector2(24, 268), "TAS is derived air-relative speed. Altitude uses the WGS84 ellipsoid.", 12, MUTED)
	_text(rect.position + Vector2(24, 291), "Native truth display: no IAS, magnetic compass, turn/slip sensor or Cessna calibration.", 12, MUTED)
	_text(rect.position + Vector2(24, 314), "Display ranges are scales, not operating limits. This overlay cannot modify physics.", 12, MUTED)
