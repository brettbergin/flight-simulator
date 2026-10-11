extends Control
## Original MIT. ADR018 copied presentation and bounded signal producer only.
const Readings = preload("res://cockpit/instruments/native_readings.gd")
const EngineStatus = preload("res://cockpit/instruments/engine_status.gd")
const BindingHelp = preload("res://ui/first_flight/binding_help.gd")
const FIXTURE_PATH = "res://content/scenarios/first-flight/briefing.json"
const FIXTURE_SHA256 = "d75704a7aa6b50724561202bf817e1b74a0d7693ec2043347300cba8a29492c4"
const CHOICE_IDS = ["cold-familiarization","ready-flight","airborne-orientation"]
const CHOICE_TITLES = {"cold-familiarization":"Engine-off familiarization","ready-flight":"On the runway, engine running","airborne-orientation":"Already airborne"}
signal choice_requested(choice_id: String, source_session: String)
signal controls_requested(source_session: String)
signal back_requested(source_session: String)
var circuit_slot: VBoxContainer
var _readback: Dictionary = {}
var _preset: Dictionary = {}
var _qualified: Dictionary = {}
var _help: Dictionary = {}
var _current_wind: String = ""
var _fixture: Dictionary = {}
var _fixture_error: String = ""
var _step_index: int = 0
var _status: Label
var _actual: Label
var _binding_text: Label
var _step_text: Label
var _previous: Button
var _next: Button
var _back: Button
var _controls: Button
var _choice_buttons: Array[Button] = []
var _tabs: TabContainer
var _shell: Panel
var _summary: Label
var _details_source: Label
var _choice_details: Label
var _limits: Label
var _circuit_hint: Label
var _cards: Array[PanelContainer] = []
var _card_titles: Array[Label] = []
var _card_facts: Array[Label] = []
const _CARD_COPY = {
	"cold-familiarization":{"title":"Engine off","description":"Explore the engine controls.","facts":"Idealized starter supply.\nRecorded flight and engine review available","action":"Choose engine-off flight"},
	"ready-flight":{"title":"Engine running","description":"Begin at the runway with the engine prestarted.","facts":"Startup is skipped.\nLegacy observed review available","action":"Choose prestarted flight"},
	"airborne-orientation":{"title":"Already airborne","description":"Explore the view and flight controls.","facts":"Start, taxi and takeoff are skipped. Read the initialized state.","action":"Choose airborne flight"}
}

static func validate_fixture_bytes(bytes: PackedByteArray) -> Dictionary:
	if bytes.is_empty():
		return {"ok":false,"error":"Briefing unavailable: original fixture missing or empty","value":{}}
	var hash_context: HashingContext = HashingContext.new()
	hash_context.start(HashingContext.HASH_SHA256); hash_context.update(bytes)
	if hash_context.finish().hex_encode() != FIXTURE_SHA256:
		return {"ok":false,"error":"Briefing unavailable: missing or changed original fixture bytes/revision","value":{}}
	var parser: JSON = JSON.new()
	if parser.parse(bytes.get_string_from_utf8()) != OK or not parser.data is Dictionary:
		return {"ok":false,"error":"Briefing unavailable: invalid original fixture","value":{}}
	var value: Dictionary = parser.data
	if value.get("id") != "original-first-flight-briefing" or value.get("revision") != 2:
		return {"ok":false,"error":"Briefing unavailable: unknown fixture identity/revision","value":{}}
	return {"ok":true,"error":"","value":value.duplicate(true)}

static func _fixture_check() -> Dictionary:
	if not FileAccess.file_exists(FIXTURE_PATH):
		return {"ok":false,"error":"Briefing unavailable: original fixture missing","value":{}}
	return validate_fixture_bytes(FileAccess.get_file_as_bytes(FIXTURE_PATH))

static func choice_for(choice_id: String) -> Dictionary:
	if not CHOICE_IDS.has(choice_id): return {}
	var checked: Dictionary = _fixture_check()
	if not checked.ok: return {}
	for choice in checked.value.choices:
		if choice.choice_id == choice_id: return choice.duplicate(true)
	return {}

func _label(parent: Node, text: String, font_size: int = 16) -> Label:
	var label: Label = Label.new()
	label.text=text; label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size",font_size)
	label.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	parent.add_child(label)
	return label

func _button(parent: Node, text: String, hint: String, callback: Callable) -> Button:
	var button: Button = Button.new()
	button.text=text; button.tooltip_text=hint; button.custom_minimum_size.y=36
	button.add_theme_font_size_override("font_size",16)
	button.pressed.connect(callback); parent.add_child(button)
	return button

func _page(title: String) -> VBoxContainer:
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.name=title; scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus=true; _tabs.add_child(scroll)
	var box: VBoxContainer = VBoxContainer.new()
	box.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation",6); scroll.add_child(box)
	return box

func _surface(color: String, border: String) -> StyleBoxFlat:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color=Color(color); style.border_color=Color(border)
	style.set_border_width_all(1); style.set_corner_radius_all(8)
	return style

func _layout_shell() -> void:
	if not is_instance_valid(_shell): return
	_shell.size=Vector2(minf(1120.0,maxf(0.0,size.x-32.0)),minf(720.0,maxf(0.0,size.y-32.0)))
	_shell.position=(size-_shell.size)*0.5

func _ready() -> void:
	mouse_filter=Control.MOUSE_FILTER_STOP
	var background: Panel = Panel.new()
	var backdrop_style: StyleBoxFlat = _surface("0a111a","0a111a")
	backdrop_style.set_corner_radius_all(0); background.add_theme_stylebox_override("panel",backdrop_style)
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); add_child(background)
	# A plain Panel keeps child minimum sizes from enlarging the bounded shell.
	_shell=Panel.new(); _shell.name="SetupSurface"; add_child(_shell)
	_shell.add_theme_stylebox_override("panel",_surface("101c29","38516a"))
	resized.connect(_layout_shell); _layout_shell()
	var margin: MarginContainer = MarginContainer.new(); _shell.add_child(margin)
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left","top","right","bottom"]: margin.add_theme_constant_override("margin_"+side,16)
	var layout: VBoxContainer = VBoxContainer.new()
	layout.add_theme_constant_override("separation",6); margin.add_child(layout)
	var header: HBoxContainer = HBoxContainer.new(); header.custom_minimum_size.y=36
	header.add_theme_constant_override("separation",12); layout.add_child(header)
	var title: Label = _label(header,"First flight",24)
	# This fixed short heading must keep its natural width in the horizontal header.
	title.autowrap_mode=TextServer.AUTOWRAP_OFF
	title.size_flags_horizontal=Control.SIZE_SHRINK_BEGIN; title.vertical_alignment=VERTICAL_ALIGNMENT_CENTER
	_status=_label(header,"No current flight | Back returns paused",14)
	_status.horizontal_alignment=HORIZONTAL_ALIGNMENT_RIGHT; _status.vertical_alignment=VERTICAL_ALIGNMENT_CENTER
	_tabs=TabContainer.new(); _tabs.size_flags_vertical=Control.SIZE_EXPAND_FILL
	_tabs.add_theme_font_size_override("font_size",16); layout.add_child(_tabs)
	_tabs.get_tab_bar().focus_mode=Control.FOCUS_ALL
	var overview: VBoxContainer = _page("Start & state")
	overview.add_theme_constant_override("separation",4)
	_summary=_label(overview,"Current flight unavailable",14); _summary.custom_minimum_size.y=42
	var choices: HBoxContainer = HBoxContainer.new(); choices.name="StartingPoints"
	choices.add_theme_constant_override("separation",12); overview.add_child(choices)
	for id in CHOICE_IDS:
		var copy: Dictionary = _CARD_COPY[id]
		var card: PanelContainer = PanelContainer.new(); card.name=id
		card.size_flags_horizontal=Control.SIZE_EXPAND_FILL; card.custom_minimum_size.y=184
		card.add_theme_stylebox_override("panel",_surface("17293a","3d5973")); choices.add_child(card)
		_cards.append(card)
		var inset: MarginContainer = MarginContainer.new(); card.add_child(inset)
		for side in ["left","top","right","bottom"]: inset.add_theme_constant_override("margin_"+side,10)
		var body: VBoxContainer = VBoxContainer.new(); body.add_theme_constant_override("separation",4); inset.add_child(body)
		_card_titles.append(_label(body,copy.title,20))
		_label(body,copy.description,14)
		var facts: Label = _label(body,"Starting-point facts unavailable",13)
		facts.size_flags_vertical=Control.SIZE_EXPAND_FILL; _card_facts.append(facts)
		var button: Button = _button(body,copy.action,"Request this exact original start; remain paused after successful adoption.",_request_choice.bind(id))
		button.size_flags_horizontal=Control.SIZE_EXPAND_FILL; _choice_buttons.append(button)
	circuit_slot=VBoxContainer.new(); circuit_slot.name="CircuitOptions"; overview.add_child(circuit_slot)
	_circuit_hint=_label(overview,"Not evaluated | ready-flight / ground-ready / calm / runway36 only.\nCircuit aid choice is session-local and is not stored in saved flight reviews.",12)
	var controls_page: VBoxContainer = _page("Control help")
	_label(controls_page,BindingHelp.AVAILABILITY)
	_binding_text=_label(controls_page,"")
	var steps: VBoxContainer = _page("Software steps")
	_label(steps,"Manual software orientation only | not a checklist, aircraft phase, score or completion record.")
	_step_text=_label(steps,"")
	var step_buttons: HBoxContainer = HBoxContainer.new(); steps.add_child(step_buttons)
	_previous=_button(step_buttons,"Previous step","Change only the manual software step.",_change_step.bind(-1))
	_next=_button(step_buttons,"Next step","Change only the manual software step.",_change_step.bind(1))
	var details: VBoxContainer = _page("Details")
	_details_source=_label(details,"")
	_actual=_label(details,"")
	_choice_details=_label(details,"")
	_limits=_label(layout,"Original prototype models | synthetic airfield | no aircraft-specific checklist or training credit.\nNew choices stay paused. Return to the menu and choose Resume to continue.",13)
	_limits.custom_minimum_size.y=32
	var footer: HBoxContainer = HBoxContainer.new(); layout.add_child(footer)
	_back=_button(footer,"Back to paused menu","Return still paused. Use the ordinary menu's explicit Resume to continue.",_request_back)
	var spacer: Control = Control.new(); spacer.size_flags_horizontal=Control.SIZE_EXPAND_FILL; footer.add_child(spacer)
	_controls=_button(footer,"Controls","Open paused Controls to inspect assignments and observed status.",_request_controls)
	for i in _choice_buttons.size():
		if i>0: _choice_buttons[i].focus_neighbor_left=_choice_buttons[i-1].get_path()
		if i+1<_choice_buttons.size(): _choice_buttons[i].focus_neighbor_right=_choice_buttons[i+1].get_path()
		_choice_buttons[i].focus_neighbor_bottom=(_back if i<2 else _controls).get_path()
	_back.focus_neighbor_top=_choice_buttons[0].get_path(); _controls.focus_neighbor_top=_choice_buttons[2].get_path()
	_refresh()

func set_state(readback: Dictionary, preset: Dictionary, current_wind: String) -> void:
	_readback=readback.duplicate(true); _preset=preset.duplicate(true); _current_wind=current_wind
	_qualified=Readings.from_readback(_readback).duplicate(true)
	_help=BindingHelp.view(_preset)
	var checked: Dictionary = _fixture_check()
	_fixture=checked.value.duplicate(true); _fixture_error=checked.error
	_refresh()

func _source_session() -> String:
	if _qualified.get("state") in ["live","paused"]: return str(_qualified.session_id)
	return ""

func _refresh() -> void:
	if not is_instance_valid(_status): return
	var state: String = _qualified.get("state","empty")
	var status_name: String = {"paused":"Paused","live":"Running","historical":"Historical / view-only","empty":"No current flight","invalid":"State unavailable"}.get(state,"State unavailable")
	_status.text=status_name+" | Back returns paused"
	_details_source.text="Source state: %s | session %s | tick %s" % [state,str(_qualified.get("session_id")) if _qualified.get("session_id")!=null else "unavailable",str(_qualified.get("tick")) if _qualified.get("tick")!=null else "unavailable"]
	if not _fixture_error.is_empty():
		_status.text="Starting points unavailable | Back returns paused"
		_details_source.text+="\n"+_fixture_error
	elif state in ["invalid","empty"]: _details_source.text+="\n"+str(_qualified.get("error","No qualified Readback"))
	_status.tooltip_text=_details_source.text
	if state in ["live","paused","historical"]:
		var start_name: String={"piston-cold-ground":"Ground, engine off","ground-ready":"Ground, engine already running","airborne-prepared":"Prepared airborne start"}.get(_readback.named_start,_readback.named_start)
		var wind: Dictionary=_readback.atmosphere.wind_toward_ned_mps
		_actual.text="Current aircraft state (%s)\nModel: %s · %s\nStart: %s | Wind preset: %s\nActual wind NED: north %.1f / east %.1f / down %.1f m/s" % [state,_readback.model_identity.id,_readback.model_identity.version,start_name,_current_wind,wind.x,wind.y,wind.z]
		var speed: Dictionary=_qualified.readings.tas
		var height: Dictionary=_qualified.readings.ellipsoid_height
		_actual.text += "\nTrue airspeed: %s | Ellipsoid height: %s (WGS84, not MSL)" % [("%.1f kt" % (speed.value*3600.0/1852.0)) if speed.valid else "unavailable",("%.1f ft" % (height.value/0.3048)) if height.valid else "unavailable"]
		_actual.text += "\nNative-held controls: throttle %.0f%% / mixture %.0f%% / brakes L %.0f%% R %.0f%%" % [_readback.held_axes.throttle*100.0,_readback.held_axes.mixture*100.0,_readback.held_axes.left_brake*100.0,_readback.held_axes.right_brake*100.0]
		if state=="historical": _actual.text += "\nHistorical readings are view-only; they cannot start or control a current flight."
		if _readback.model_identity == Readings.PISTON_PROFILE:
			var engine: Dictionary = EngineStatus.from_readback(_readback)
			var running: Dictionary = engine.readings["engine.running"]
			_actual.text += "\nNative engine.running: "+(str(running.value) if running.valid else "unavailable")
		if _readback.named_start != "ground-ready" or _readback.model_identity.id != "original-interactive-prototype":
			_actual.text += "\nCircuit reference unavailable for this start"
	else: _actual.text="Actual start unavailable: "+str(_qualified.get("error","No qualified Readback"))
	# Compact text uses the qualified publication, never a requested choice or draft.
	_summary.text=status_name+" | Actual flight facts unavailable. Open Details."
	if not _fixture_error.is_empty(): _summary.text+="\n"+_fixture_error
	elif state in ["invalid","empty"]: _summary.text+="\n"+str(_qualified.get("error","No qualified Readback"))
	if state in ["live","paused","historical"]:
		var adopted_start: String = {"piston-cold-ground":"Engine-off start","ground-ready":"Prestarted runway start","airborne-prepared":"Prepared airborne start"}.get(_readback.named_start,_readback.named_start)
		var tas: Dictionary = _qualified.readings.tas
		var tas_text: String = ("%.1f kt TAS" % (tas.value*3600.0/1852.0)) if tas.valid else "TAS unavailable"
		var engine_text: String = "Engine status unavailable"
		if _readback.model_identity==Readings.PISTON_PROFILE:
			var engine_view: Dictionary = EngineStatus.from_readback(_readback)
			var actual_running: Dictionary = engine_view.readings["engine.running"]
			if actual_running.valid: engine_text="Engine running" if actual_running.value else "Engine off"
		_summary.text="%s | %s | %s\nStart: %s | Adopted wind: %s" % [status_name,tas_text,engine_text,adopted_start,_current_wind if not _current_wind.is_empty() else "unavailable"]
		if state=="historical": _summary.text+=" | Historical facts, not a current flight"
	var warning_lines: PackedStringArray = ["Starting-point facts (copied original content):"]
	for i in CHOICE_IDS.size():
		var admitted: Dictionary = {}
		for choice in _fixture.get("choices",[]):
			if choice.choice_id==CHOICE_IDS[i]: admitted=choice; break
		_card_facts[i].text=_CARD_COPY[CHOICE_IDS[i]].facts if not admitted.is_empty() and _fixture_error.is_empty() else "Starting-point facts unavailable. Open Details."
		if not admitted.is_empty(): warning_lines.append(CHOICE_TITLES[CHOICE_IDS[i]]+"\n"+" | ".join(admitted.required_truth))
	_choice_details.text="\n\n".join(warning_lines) if _fixture_error.is_empty() else _fixture_error
	var lines: PackedStringArray = [_help.get("reserved",BindingHelp.view({}).reserved)]
	if not _help.get("available",false): lines.append("Binding help unavailable: "+str(_help.get("error","No validated preset")))
	for group in ["actions","axes","systems"]:
		lines.append("\n"+group.to_upper())
		for row in _help.get(group,[]): lines.append(row.id+": "+row.text)
	_binding_text.text="\n".join(lines)
	for button in _choice_buttons: button.disabled=not _fixture_error.is_empty() or state in ["live","invalid"]
	var step_count: int = _fixture.get("steps",[]).size()
	_step_index=clampi(_step_index,0,maxi(0,step_count-1))
	_step_text.text="Software steps unavailable: "+_fixture_error
	if step_count > 0:
		var step: Dictionary = _fixture.steps[_step_index]
		_step_text.text="Manual step %s of %s: %s\n\n%s" % [_step_index+1,step_count,step.title,step.text]
	_previous.disabled=_step_index<=0; _next.disabled=_step_index>=step_count-1

func _change_step(delta: int) -> void:
	_step_index=clampi(_step_index+delta,0,maxi(0,_fixture.get("steps",[]).size()-1)); _refresh()

func _request_choice(choice_id: String) -> void:
	# Revalidate exact bytes at use; never emit a stale/changed fixture mapping.
	var checked: Dictionary = _fixture_check()
	if not checked.ok:
		_fixture={}; _fixture_error=checked.error; _refresh(); return
	if not is_visible_in_tree() or _qualified.get("state") in ["live","invalid"] or choice_for(choice_id).is_empty(): return
	choice_requested.emit(choice_id,_source_session())

func _request_controls() -> void:
	if is_visible_in_tree(): controls_requested.emit(_source_session())

func _request_back() -> void:
	if is_visible_in_tree(): back_requested.emit(_source_session())

func focus_back() -> void:
	if is_instance_valid(_back): _back.grab_focus()
