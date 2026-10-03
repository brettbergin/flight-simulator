extends Node2D
# Authored visual load fixture. All readings are fixed synthetic examples.
const CREAM := Color(0.92,0.94,0.89)
var font: Font = ThemeDB.fallback_font

func centered(text: String, point: Vector2, size: int, color: Color = CREAM) -> void:
	draw_string(font, point-Vector2(font.get_string_size(text,HORIZONTAL_ALIGNMENT_LEFT,-1,size).x/2,0), text,HORIZONTAL_ALIGNMENT_LEFT,-1,size,color)

func gauge(center: Vector2, title: String, units: String, value: String, needle: float, horizon: bool = false) -> void:
	draw_circle(center,70,Color(0.025,0.03,0.04))
	draw_arc(center,69,0,TAU,100,Color(0.65,0.68,0.7),3,true)
	if horizon:
		draw_style_box(style(Color(0.14,0.37,0.6)),Rect2(center-Vector2(47,44),Vector2(94,44)))
		draw_style_box(style(Color(0.38,0.23,0.09)),Rect2(center-Vector2(47,0),Vector2(94,44)))
		draw_line(center-Vector2(45,0),center+Vector2(45,0),CREAM,2,true)
		draw_line(center-Vector2(32,2),center-Vector2(8,2),Color.YELLOW,3,true)
		draw_line(center+Vector2(8,-2),center+Vector2(32,-2),Color.YELLOW,3,true)
	else:
		for tick in 40:
			var angle: float = tick*TAU/40.0-PI/2
			var direction := Vector2(cos(angle),sin(angle))
			draw_line(center+direction*(53 if tick%5==0 else 59),center+direction*64,CREAM,2,true)
		for tick in 8:
			var angle: float = tick*TAU/8.0-PI/2
			centered(str(tick*20),center+Vector2(cos(angle),sin(angle))*43+Vector2(0,5),16)
		var direction := Vector2(cos(needle),sin(needle))
		draw_line(center-direction*9,center+direction*51,CREAM,4,true)
		draw_circle(center,5,CREAM)
	centered(title,center+Vector2(0,-81),18)
	centered(units,center+Vector2(0,82),14)
	centered(value,center+Vector2(0,100),20)

func style(color: Color) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color=color
	return box

func _draw() -> void:
	draw_rect(Rect2(0,0,1024,448),Color(0.075,0.085,0.10))
	centered("SYNTHETIC PANEL / RENDER PROOF",Vector2(512,25),22,Color(1,0.72,0.25))
	var titles := ["AIRSPEED","ATTITUDE","ALTITUDE","TURN","HEADING","VERTICAL SPEED"]
	var units := ["KNOTS","DEGREES","FEET","RATE","DEGREES","FT / MIN"]
	var values := ["95","LEVEL","2500","STANDARD","090","+500"]
	for index in 6:
		gauge(Vector2(100+165*(index%3),135+205*(index/3)),titles[index],units[index],values[index],-1.2+index*.47,index==1)
	draw_rect(Rect2(550,65,450,290),Color(0.025,0.028,0.032))
	var rows := ["RPM   2400","OIL TEMP   180 F","OIL PRESS   65 PSI","FUEL   L 18 / R 18 GAL","COM1   122.800","NAV1   110.500"]
	for index in rows.size():
		draw_string(font,Vector2(572,100+43*index),rows[index],HORIZONTAL_ALIGNMENT_LEFT,-1,26,Color(0.68,1,0.64))
	centered("FIXED EXAMPLE VALUES / NO FLIGHT MODEL",Vector2(772,394),18,Color(1,0.72,0.25))
