extends Control
# Original MIT. Optional synthetic geometric aid; no native/device/clock calls.
const Readings = preload("res://cockpit/instruments/native_readings.gd")
const Frames = preload("res://simulation/canonical_frames.gd")
signal route_requested(indices: Array)
signal next_requested()
signal stop_requested()
signal return_requested(runway: int)
signal dismissed()
signal aids_requested(value: bool)
const CYAN := Color("78dce9")
const MUTED := Color("a0b5c4")
var _landmarks: Array[Dictionary] = []
var _route: Array[int] = []
var _leg := 0
var _complete := false
var _session := ""
var _view: Dictionary = _empty()
var _open := false
var _aids_visible := true
var _aids: CheckBox
var _draft: Array[int] = []
var _chooser: PanelContainer
var _card: PanelContainer
var _title: Label
var _metrics: Label
var _state: Label
var _leg_text: Label
var _choices: VBoxContainer
var _draft_text: Label
var _begin: Button
var _next: Button
var _stop: Button
var _choices_signature := ""
var _choice_buttons: Array[Button] = []

static func _empty() -> Dictionary:
	return {"session_id":null,"tick":null,"paused":false,"historical":false,"available":false,"error":"No verified current publication","route_labels":[],"leg_index":0,"leg_count":0,"target_label":null,"target_anchor_eus_m":null,"planar_range_m":null,"bearing_deg":null,"complete":false,"active":false,"aid_visible":true}

func configure(landmarks: Array) -> Dictionary:
	if landmarks.is_empty() or landmarks.size()>16:
		return {"ok":false,"error":"Expected 1-16 original landmarks"}
	var copied: Array[Dictionary] = []
	var labels: Array[String] = []
	for item in landmarks:
		if not item is Dictionary or item.size()!=2 or not item.has("label") or not item.has("position_eus_m"):
			return {"ok":false,"error":"Malformed original landmark"}
		for key in item:
			if not key is String:
				return {"ok":false,"error":"Landmark keys must be Strings"}
		if not item.label is String or item.label.is_empty() or item.label.length()>32 or labels.has(item.label) or not item.position_eus_m is Vector3:
			return {"ok":false,"error":"Invalid or duplicate landmark name/position"}
		var at: Vector3 = item.position_eus_m
		if not at.is_finite() or at.y!=0.0 or absf(at.x)>20000.0 or absf(at.z)>20000.0:
			return {"ok":false,"error":"Landmark must lie on the bounded original presentation plane"}
		copied.append({"label":item.label,"position_eus_m":at})
		labels.append(item.label)
	_landmarks=copied
	_choices_signature=""
	_clear_route()
	_view=_empty()
	_open=false
	_refresh()
	return {"ok":true,"error":""}

func _clear_route() -> void:
	_route.clear()
	_leg=0
	_complete=false
	_draft.clear()

func _result(ok: bool, error: String) -> Dictionary:
	return {"ok":ok,"error":error,"view":_view.duplicate(true)}

func _editable(readback: Dictionary) -> bool:
	observe(readback)
	return _view.available and _view.paused and not _view.historical

func choose(indices: Array, readback: Dictionary) -> Dictionary:
	if not _editable(readback):
		return _result(false,"Choose a route while verified native state is paused")
	if indices.is_empty() or indices.size()>4:
		return _result(false,"Choose 1-4 unique landmarks")
	var chosen: Array[int] = []
	for index in indices:
		if typeof(index)!=TYPE_INT or index<0 or index>=_landmarks.size() or chosen.has(index):
			return _result(false,"Unknown or repeated landmark")
		chosen.append(index)
	_route=chosen
	_leg=0
	_complete=false
	_draft=chosen.duplicate()
	observe(readback)
	_open=false
	_refresh()
	return _result(true,"")

func _target(index: int) -> Dictionary:
	if index<0:
		return {"label":"Runway %02d pavement end"%(36 if index==-1 else 18),"position_eus_m":Vector3(0,0,100 if index==-1 else -1700)}
	return _landmarks[index]

func choose_return(runway: int, readback: Dictionary) -> Dictionary:
	if not _editable(readback):
		return _result(false,"Choose a pavement-end reference while verified native state is paused")
	if runway!=36 and runway!=18:
		return _result(false,"Unknown synthetic runway end")
	_route.assign([-1 if runway==36 else -2])
	_leg=0
	_complete=false
	_draft.clear()
	observe(readback)
	_open=false
	_refresh()
	return _result(true,"")

func next(readback: Dictionary) -> Dictionary:
	if not _editable(readback):
		return _result(false,"Advance a leg while verified native state is paused")
	if _route.is_empty() or _complete:
		return _result(false,"No active route leg")
	if _leg+1>=_route.size():
		_complete=true
	else:
		_leg+=1
	observe(readback)
	return _result(true,"")

func stop(readback: Dictionary) -> Dictionary:
	if not _editable(readback):
		return _result(false,"Stop a route while verified native state is paused")
	_clear_route()
	_open=false
	observe(readback)
	return _result(true,"")

func observe(readback: Variant) -> Dictionary:
	var validated: Dictionary = Readings.from_readback(readback)
	var current: bool = validated.state in ["paused","live"]
	var valid_source: bool = validated.state in ["paused","live","historical"]
	if valid_source and validated.session_id!=_session:
		_session=validated.session_id
		_clear_route()
		_open=false
	_view=_empty()
	if valid_source:
		_view.session_id=validated.session_id
		_view.tick=validated.tick
		_view.paused=validated.state=="paused"
		_view.historical=validated.state=="historical"
		_view.error="Retained state; current guidance unavailable" if _view.historical else ""
	else:
		_view.error=validated.error
		_view.historical=validated.state=="empty" or (readback is Dictionary and readback.get("historical")==true)
		_open=false
	_view.aid_visible=_aids_visible
	_view.complete=_complete
	_view.leg_index=_leg
	_view.leg_count=_route.size()
	for index in _route:
		_view.route_labels.append(_target(index).label)
	_view.active=not _route.is_empty() and not _complete
	if current:
		var a: Dictionary=readback.world_anchor
		var prepared: Dictionary=Frames.anchor(a.latitude_rad,a.longitude_rad,a.ellipsoid_height_m)
		var derived: Dictionary=Frames.derive(readback.aircraft,prepared)
		if derived.is_empty():
			current=false
			_view.error="Canonical geometry unavailable"
		else:
			for axis in 3:
				if absf(derived.anchor_eus_position_m[axis]-readback.canonical.anchor_eus_position_m[axis])>1e-7:
					current=false
					_view.error="Canonical anchor position differs from native publication"
			if current and _view.active:
				var target: Vector3=_target(_route[_leg]).position_eus_m
				var point: Array=readback.canonical.anchor_eus_position_m
				var dx: float=float(target.x)-float(point[0])
				var dz: float=float(target.z)-float(point[2])
				var squared: float=dx*dx+dz*dz
				if not is_finite(squared):
					current=false
					_view.error="Geometric arithmetic overflow"
				else:
					_view.target_label=_target(_route[_leg]).label
					_view.target_anchor_eus_m=[float(target.x),float(target.y),float(target.z)]
					_view.planar_range_m=sqrt(squared)
					_view.bearing_deg=fposmod(rad_to_deg(atan2(dx,-dz)),360.0) if squared>0.0001 else null
	_view.available=current
	if not current:
		_view.target_label=null
		_view.target_anchor_eus_m=null
		_view.planar_range_m=null
		_view.bearing_deg=null
		_open=false
	_refresh()
	return _view.duplicate(true)

func set_aids_visible(value: bool) -> void:
	_aids_visible=value
	_view.aid_visible=value
	if _aids!=null:
		_aids.set_pressed_no_signal(value)
	_refresh()

func set_open(value: bool) -> void:
	_open=value and _view.available and _view.paused
	if _open:
		_draft.clear()
		for index in _route:
			if index>=0:
				_draft.append(index)
	_refresh()

func _ready() -> void:
	mouse_filter=Control.MOUSE_FILTER_IGNORE
	resized.connect(_layout)
	_build()
	_refresh()

func _label(text: String, pixels: int, color: Color=MUTED) -> Label:
	var label:=Label.new()
	label.text=text
	label.add_theme_color_override("font_color",color)
	label.add_theme_font_size_override("font_size",pixels)
	label.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS
	label.mouse_filter=Control.MOUSE_FILTER_IGNORE
	return label

func _button(text: String, callable: Callable) -> Button:
	var button:=Button.new()
	button.text=text
	button.custom_minimum_size.y=28
	button.pressed.connect(callable)
	button.focus_mode=Control.FOCUS_ALL
	return button

func _surface() -> PanelContainer:
	var panel:=PanelContainer.new()
	var style:=StyleBoxFlat.new()
	style.bg_color=Color(0.025,0.047,0.065,0.98)
	style.border_color=Color("426679")
	style.set_border_width_all(1)
	style.set_corner_radius_all(10)
	style.content_margin_left=16
	style.content_margin_right=16
	style.content_margin_top=12
	style.content_margin_bottom=12
	panel.add_theme_stylebox_override("panel",style)
	add_child(panel)
	return panel

func _build() -> void:
	_card=_surface()
	_card.mouse_filter=Control.MOUSE_FILTER_IGNORE
	var card_box:=VBoxContainer.new()
	card_box.mouse_filter=Control.MOUSE_FILTER_IGNORE
	_card.add_child(card_box)
	card_box.add_child(_label("SYNTHETIC LANDMARKS / OPTIONAL AID",11,CYAN))
	_title=_label("Choose a local flying goal",20,Color("edf4f8"))
	card_box.add_child(_title)
	_metrics=_label("",16,Color("edf4f8"))
	card_box.add_child(_metrics)
	_leg_text=_label("",12)
	card_box.add_child(_leg_text)
	_state=_label("",11)
	card_box.add_child(_state)
	_chooser=_surface()
	var box:=VBoxContainer.new()
	box.add_theme_constant_override("separation",5)
	_chooser.add_child(box)
	box.add_child(_label("LOCAL LANDMARK PRACTICE",21,Color("edf4f8")))
	box.add_child(_label("SYNTHETIC / OPTIONAL MAP AID / MANUAL LEGS",11,CYAN))
	var presets:=HBoxContainer.new()
	box.add_child(presets)
	for recipe in [{"label":"Farm & orchard","names":["East Farm","North Water Tank","North Orchard"]},{"label":"Pond & bridge","names":["West Pond","River Bridge"]},{"label":"Village & farm","names":["South Village","East Farm"]}]:
		var names: Array=recipe.names.duplicate()
		presets.add_child(_button(recipe.label,func(): _draft_names(names)))
	_choices=VBoxContainer.new()
	_choices.add_theme_constant_override("separation",4)
	box.add_child(_choices)
	_draft_text=_label("Choose up to four landmarks below",12,Color("edf4f8"))
	box.add_child(_draft_text)
	var row:=HBoxContainer.new()
	box.add_child(row)
	_begin=_button("Use selected route",func(): route_requested.emit(_draft.duplicate()))
	_next=_button("Next leg (manual)",func(): next_requested.emit())
	_stop=_button("Stop route",func(): stop_requested.emit())
	row.add_child(_begin)
	row.add_child(_next)
	row.add_child(_stop)
	var returns:=HBoxContainer.new()
	box.add_child(returns)
	returns.add_child(_button("Return: runway 36 end",func(): return_requested.emit(36)))
	returns.add_child(_button("Return: runway 18 end",func(): return_requested.emit(18)))
	_aids=CheckBox.new()
	_aids.text="Show aids"
	_aids.set_pressed_no_signal(_aids_visible)
	_aids.toggled.connect(func(value: bool): aids_requested.emit(value))
	returns.add_child(_aids)
	box.add_child(_button("Back to paused menu",func(): _open=false; _refresh(); dismissed.emit()))
	box.add_child(_label("Resume from the menu. No arrival scoring, altitude or speed targets.",11))
	_layout()

func _draft_names(names: Array) -> void:
	if not _view.paused or not _view.available:
		return
	_draft.clear()
	for name in names:
		for index in _landmarks.size():
			if _landmarks[index].label==name:
				_draft.append(index)
	_refresh_choices()

func _toggle(index: int) -> void:
	if not _view.paused or not _view.available:
		return
	if _draft.has(index):
		_draft.erase(index)
	elif _draft.size()<4:
		_draft.append(index)
	_refresh_choices()

func _refresh_choices() -> void:
	if _choices==null:
		return
	var signature: String=JSON.stringify([_landmarks,_draft,_view.paused,_view.available,_view.active,_route.is_empty()])
	if signature==_choices_signature:
		return
	_choices_signature=signature
	if _choice_buttons.size()!=_landmarks.size():
		for child in _choices.get_children():
			_choices.remove_child(child)
			child.queue_free()
		_choice_buttons.clear()
		for index in _landmarks.size():
			var button: Button=_button("",func(): _toggle(index))
			_choice_buttons.append(button)
			_choices.add_child(button)
	for index in _landmarks.size():
		var number: int=_draft.find(index)+1
		_choice_buttons[index].text=(str(number)+". " if number>0 else "+ ")+_landmarks[index].label
	var names: Array[String]=[]
	for index in _draft:
		names.append(_landmarks[index].label)
	_draft_text.text=" -> ".join(names) if not names.is_empty() else "Choose up to four landmarks"
	_begin.disabled=_draft.is_empty() or not _view.paused or not _view.available
	_next.disabled=not _view.active or not _view.paused or not _view.available
	_stop.disabled=_route.is_empty() or not _view.paused or not _view.available

func _refresh() -> void:
	if _card==null:
		return
	_chooser.visible=_open
	_card.visible=not _route.is_empty() and not _open and _aids_visible
	_title.text=_view.target_label if _view.target_label!=null else "Manual itinerary ended" if _complete else "Current guidance unavailable"
	_metrics.text=("%.2f km / anchor %03d deg"%[_view.planar_range_m/1000.0,int(roundf(_view.bearing_deg))%360] if _view.bearing_deg!=null else "%.2f km / bearing unavailable"%(_view.planar_range_m/1000.0)) if _view.planar_range_m!=null else "Range / bearing unavailable"
	_leg_text.text="Leg %d / %d: %s"%[_leg+1,_route.size()," -> ".join(_view.route_labels)]
	_state.text="RETAINED / NO CURRENT GUIDANCE" if _view.historical else "PAUSED / select Next from the route board" if _view.paused else "SYNTHETIC ANCHOR BEARING / MANUAL LEGS"
	_refresh_choices()
	_layout()

func _layout() -> void:
	if _card==null:
		return
	_card.position=Vector2(14,110)
	_card.size=Vector2(minf(380,size.x-28),0)
	_chooser.size=Vector2(minf(580,size.x-28),0)
	_chooser.position=Vector2((size.x-_chooser.size.x)*0.5,maxf(14,(size.y-_chooser.get_combined_minimum_size().y)*0.5))
