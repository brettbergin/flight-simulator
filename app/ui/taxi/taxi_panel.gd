extends Control
# Original MIT. Paused display/draft/signals only; Scene owns all admission.
signal route_requested(itinerary_id: String, source_session: String)
signal next_requested(source_session: String)
signal stop_requested(source_session: String)
signal aids_requested(value: bool, source_session: String)
signal dismissed(source_session: String)
const Layout = preload("res://world/taxi/taxi_layout.gd")
const Navigation = preload("res://world/taxi/taxi_navigation.gd")
var _owner: int = OS.get_thread_caller_id()
var _layout: Dictionary = {}
var _view: Dictionary = {}
var _draft: Dictionary = {}
var _session: String = ""
var _active: bool = false
var _guidance: bool = false
var _revision: int = 0
var _picker: OptionButton
var _begin: Button
var _next: Button
var _stop: Button
var _aids: CheckBox
var _back: Button
var _summary: Label
var _error: Label

func _foreign() -> bool:
	return not Thread.is_main_thread() or OS.get_thread_caller_id()!=_owner

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter=Control.MOUSE_FILTER_STOP
	visibility_changed.connect(_visibility_changed)
	var shade := ColorRect.new()
	shade.color=Color(0.01,0.025,0.04,1.0)
	shade.mouse_filter=Control.MOUSE_FILTER_IGNORE
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(shade)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for edge in ["left","right","top","bottom"]: margin.add_theme_constant_override("margin_"+edge,20)
	add_child(margin)
	var shell := VBoxContainer.new()
	shell.add_theme_constant_override("separation",10)
	margin.add_child(shell)
	_label(shell,"TaxiHeading","SYNTHETIC TAXI - FLIGHT PAUSED",23)
	_summary=_label(shell,"TaxiSummary","No current taxi guidance",17)
	_label(shell,"TaxiHint","Manual references only. Begin restarts at point 1; Next never moves the aircraft or grants runway clearance. Back leaves the flight paused.",16)
	# Fixed heading/summary/hint/footer avoid the default-focus scrolling defect
	# found on Views. The short form alone scrolls on smaller windows.
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical=Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus=true
	shell.add_child(scroll)
	var form := VBoxContainer.new()
	form.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	form.add_theme_constant_override("separation",10)
	scroll.add_child(form)
	_label(form,"ItineraryLabel","Choose an itinerary; no position or arrival is inferred.",16)
	_picker=OptionButton.new()
	_picker.name="Itinerary"
	_style(_picker)
	_picker.item_selected.connect(_select)
	form.add_child(_picker)
	_begin=_button(form,"BeginItinerary","Begin itinerary",_request_begin)
	var progress := HBoxContainer.new()
	progress.add_theme_constant_override("separation",12)
	form.add_child(progress)
	_next=_button(progress,"NextPoint","Next reference",_request_next)
	_stop=_button(progress,"StopItinerary","Stop itinerary",_request_stop)
	_next.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	_stop.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	_aids=CheckBox.new()
	_aids.name="ShowAids"
	_aids.text="Show optional map and world taxi aids"
	_style(_aids)
	_aids.toggled.connect(_request_aids)
	form.add_child(_aids)
	_error=_label(form,"TaxiError","",16)
	_error.add_theme_color_override("font_color",Color(1.0,0.76,0.48))
	_back=_button(shell,"Back","Back",_request_back)
	_refresh()
	hide()

func open(layout: Variant, view: Variant, source_session: Variant) -> bool:
	if _foreign(): return false
	var admitted: Dictionary = Layout.validate(layout)
	if not admitted.ok or typeof(source_session)!=TYPE_STRING or source_session.is_empty() or not Navigation._valid_view(view): return false
	if not view.qualified or not view.paused or view.session_id!=source_session or not _matches_layout(view,admitted.value): return false
	if not is_inside_tree() or not is_node_ready(): return false
	_revision+=1
	_layout=admitted.value.duplicate(true)
	_view=view.duplicate(true)
	_session=source_session
	_draft={"itinerary_id":view.itinerary_id}
	_active=true
	_guidance=true
	_picker.clear()
	for itinerary in _layout.itineraries: _picker.add_item(itinerary.label)
	if _draft.itinerary_id!=null:
		for i in _layout.itineraries.size():
			if _layout.itineraries[i].id==_draft.itinerary_id: _picker.select(i)
	else: _picker.select(0)
	_refresh()
	show()
	focus_back()
	return true

func present(view: Variant) -> bool:
	if _foreign() or not _can_request(): return false
	if not Navigation._valid_view(view) or not _matches_layout(view,_layout) or (view.qualified and (view.session_id!=_session or not view.paused)):
		_guidance=false
		_refresh()
		return false
	_view=view.duplicate(true)
	_guidance=view.qualified and view.paused and view.session_id==_session
	_refresh()
	return true

func draft() -> Variant:
	if _foreign(): return null
	return _draft.duplicate(true) if _can_request() else null

func retire() -> void:
	if _foreign(): return
	_clear()
	_refresh()
	hide()

func get_back_button() -> Button:
	return null if _foreign() else _back

func focus_back() -> void:
	if _foreign() or not _can_request(): return
	_back.grab_focus()
	# Back is a fixed footer. Container settling does not scroll/focus another
	# child, and no queued callback can steal focus from a subsequent opening.

static func _matches_layout(view: Dictionary, layout: Dictionary) -> bool:
	if view.layout_id!=layout.id or view.layout_revision!=layout.revision: return false
	if view.itinerary_id==null: return view.state=="empty"
	for row in layout.itineraries:
		if row.id==view.itinerary_id:
			if view.itinerary_label!=row.label or view.runway!=row.runway or view.point_count!=row.points.size(): return false
			return not view.available or view.points==row.points
	return false

func _can_request() -> bool:
	return not _foreign() and _active and is_inside_tree() and is_visible_in_tree() and not _session.is_empty() and not _draft.is_empty()

func _can_mutate() -> bool:
	return _can_request() and _guidance

func _select(index: int) -> void:
	if not _can_mutate() or index<0 or index>=_layout.itineraries.size(): return
	_draft.itinerary_id=_layout.itineraries[index].id

func _request_begin() -> void:
	if not _can_mutate(): return
	# The initial null draft means no itinerary has been explicitly selected;
	# pressing Begin explicitly chooses the visible first row.
	var index: int = _picker.selected
	if index<0 or index>=_layout.itineraries.size(): return
	_draft.itinerary_id=_layout.itineraries[index].id
	route_requested.emit(_draft.itinerary_id,_session)

func _request_next() -> void:
	if _can_mutate() and _view.state=="active": next_requested.emit(_session)

func _request_stop() -> void:
	if _can_mutate() and _view.state=="active": stop_requested.emit(_session)

func _request_aids(value: bool) -> void:
	if _can_mutate(): aids_requested.emit(value,_session)

func _request_back() -> void:
	if _can_request(): dismissed.emit(_session)

func _clear() -> void:
	_revision+=1
	_active=false
	_guidance=false
	_session=""
	_layout.clear()
	_view.clear()
	_draft.clear()

func _visibility_changed() -> void:
	if not is_visible_in_tree(): _clear()

func _refresh() -> void:
	if not is_instance_valid(_picker): return
	var enabled: bool = _active and _guidance
	_picker.disabled=not enabled
	_begin.disabled=not enabled
	_next.disabled=not enabled or _view.get("state","")!="active"
	_stop.disabled=_next.disabled
	_aids.disabled=not enabled
	_back.disabled=not _active
	_aids.set_pressed_no_signal(_view.get("aids_visible",false) if _active else false)
	_error.text=_view.get("error","") if enabled else ("Guidance unavailable; close and reopen at a qualified paused boundary." if _active else "")
	_error.visible=not _error.text.is_empty()
	if not enabled:
		_summary.text="No current taxi guidance"
	elif _view.state=="manual-ended":
		_summary.text="%s - manual itinerary ended" % _view.itinerary_label
	elif _view.state=="empty":
		_summary.text="No itinerary selected. Choose a reference route explicitly."
	else:
		var bearing: String = "no direction (coincident)" if _view.anchor_bearing_deg==null else "anchor bearing %.1f degrees" % _view.anchor_bearing_deg
		_summary.text="%s - point %d/%d: %s\n%.1f m planar range; %s" % [_view.itinerary_label,_view.point_index+1,_view.point_count,_view.target_label,_view.planar_range_m,bearing]
	# Rebuild only focus links, never controls, selection or current focus.
	var chain: Array[Control] = []
	for control in [_picker,_begin,_next,_stop,_aids,_back]:
		if not control.disabled: chain.append(control)
	for i in chain.size():
		chain[i].focus_previous=chain[i].get_path_to(chain[(i+chain.size()-1)%chain.size()])
		chain[i].focus_next=chain[i].get_path_to(chain[(i+1)%chain.size()])
		chain[i].focus_neighbor_top=chain[i].focus_previous
		chain[i].focus_neighbor_bottom=chain[i].focus_next

func _style(control: Control) -> void:
	control.custom_minimum_size.y=42
	control.add_theme_font_size_override("font_size",16)
	control.focus_mode=Control.FOCUS_ALL

func _label(parent: Node, node_name: String, text: String, pixels: int) -> Label:
	var label := Label.new()
	label.name=node_name
	label.text=text
	label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size",pixels)
	parent.add_child(label)
	return label

func _button(parent: Node, node_name: String, text: String, callback: Callable) -> Button:
	var button := Button.new()
	button.name=node_name
	button.text=text
	_style(button)
	button.pressed.connect(callback)
	parent.add_child(button)
	return button
