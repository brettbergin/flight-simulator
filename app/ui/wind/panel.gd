extends Control
# Original MIT presentation. Only the scene may adopt a selected start.
signal draft_selected(profile: String)
signal start_requested(named_start: String)
signal dismissed

const IDS: Array[String]=["calm","from-north","from-west","from-east"]
const CHOICES: Array[String]=["Calm","From north · 000° true · 5 m/s","From west · 270° true · 5 m/s","From east · 090° true · 5 m/s"]
var _choice: OptionButton
var _current: Label
var _ground: Button
var _airborne: Button
var _back: Button

static func describe(cue: Dictionary) -> String:
	var state: String=cue.get("state","invalid")
	if state in ["empty","invalid"]:
		return "Wind unavailable"
	var prefix: String="Retained historical wind" if state=="historical" else "Paused wind" if state=="paused" else "Current wind"
	var speed: float=cue.speed_mps
	if speed==0.0 and cue.from_true_rad==null:
		return prefix+" · calm · direction unavailable"
	var strength: String="%.1f kt"%(speed*3600.0/1852.0)
	if speed*3600.0/1852.0<0.05:
		strength=String.num_scientific(speed)+" m/s"
	return "%s · FROM %03d° true · %s"%[prefix,int(round(rad_to_deg(cue.from_true_rad)))%360,strength]

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter=Control.MOUSE_FILTER_STOP
	var shade:=ColorRect.new()
	shade.color=Color(0.01,0.025,0.04,0.96)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(shade)
	var margin:=MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for edge in ["left","right","top","bottom"]:
		margin.add_theme_constant_override("margin_"+edge,24)
	add_child(margin)
	var scroll:=ScrollContainer.new()
	scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED
	margin.add_child(scroll)
	var box:=VBoxContainer.new()
	box.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation",10)
	scroll.add_child(box)
	_label(box,"SYNTHETIC STEADY WIND / NATIVE TRUTH",23)
	_current=_label(box,"Current conditions unavailable",18)
	_label(box,"Choose conditions for the NEXT FRESH START. Selecting a draft leaves this flight unchanged. Resume and ordinary Restart preserve its accepted conditions.",16)
	_choice=OptionButton.new()
	_choice.custom_minimum_size.y=44
	for index in IDS.size(): _choice.add_item(CHOICES[index],index)
	_choice.item_selected.connect(func(index: int):draft_selected.emit(IDS[index]))
	box.add_child(_choice)
	_label(box,"Original synthetic presets · 5 m/s is about 9.7 kt. RWY36: north is a headwind, west from the left, east from the right. RWY18 reverses those interpretations.",16)
	_label(box,"STEADY PRESET / DIRECTION CUE — the windsock shows downstream direction. These presets have no gusts or turbulence.",16)
	_label(box,"Saved reviews do not retain wind setup or resume a flight",17)
	var row:=HBoxContainer.new()
	row.add_theme_constant_override("separation",12)
	box.add_child(row)
	_ground=_button(row,"Apply draft · ground start",func():start_requested.emit("ground-ready"))
	_airborne=_button(row,"Apply draft · airborne start",func():start_requested.emit("airborne-prepared"))
	_back=_button(box,"Back · keep this flight paused",func():dismissed.emit())
	hide()

func _label(parent: Node, text: String, pixels: int) -> Label:
	var label:=Label.new()
	label.text=text
	label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size",pixels)
	parent.add_child(label)
	return label

func _button(parent: Node, text: String, callback: Callable) -> Button:
	var button:=Button.new()
	button.text=text
	button.custom_minimum_size.y=42
	button.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	button.pressed.connect(callback)
	parent.add_child(button)
	return button

func set_context(draft: String, accepted: String, cue: Dictionary, can_start: bool) -> void:
	var index: int=IDS.find(draft)
	_choice.select(index if index>=0 else -1)
	_current.text=describe(cue)+("\nAccepted setup: "+accepted if not accepted.is_empty() else "")
	_ground.disabled=not can_start or index<0
	_airborne.disabled=_ground.disabled

func open(draft: String, accepted: String, cue: Dictionary, can_start: bool) -> void:
	set_context(draft,accepted,cue,can_start)
	show()
	_back.grab_focus()
