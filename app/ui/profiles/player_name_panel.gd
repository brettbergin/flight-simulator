extends Control

signal name_confirmed(opening: int, epoch: int, name: String)
signal dismissed(opening: int, epoch: int)

var _opening: int = 0
var _epoch: int = 0
var _generation: int = 0
var _active: bool = false
var _busy: bool = false
var _connections: Array[Dictionary] = []
var _card: PanelContainer
var _title: Label
var _name: LineEdit
var _feedback: Label
var _validation: Label
var _confirm: Button
var _cancel: Button

func _ready() -> void:
	var body: VBoxContainer = _shell("Player name")
	_title = body.get_child(0)
	_label(body, "Name", 16)
	_name = LineEdit.new()
	_name.max_length = 40
	_name.placeholder_text = "Player name"
	_name.custom_minimum_size.y = 44
	body.add_child(_name)
	_label(body, "1–40 characters. No leading or trailing spaces. Names may match; player IDs remain distinct.", 14)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(scroll)
	var messages := VBoxContainer.new()
	messages.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(messages)
	_validation = _label(messages, "")
	_feedback = _label(messages, "")
	_feedback.add_theme_color_override("font_color", Color("ffcf8c"))
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 12)
	body.add_child(actions)
	_confirm = _button(actions, "Create player")
	_confirm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_cancel = _button(actions, "Cancel")
	_fit()
	hide()

func present(opening: int, epoch: int, name: String, rename: bool) -> bool:
	if not is_node_ready() or not is_inside_tree() or opening <= 0 or epoch < 0 \
		or _generation == 9223372036854775807 or (not name.is_empty() and not _valid_name(name)) or (rename and name.is_empty()):
		return false
	_active = false
	_disconnect_ui()
	_generation += 1
	_opening = opening
	_epoch = epoch
	_busy = false
	_title.text = "Rename player" if rename else "Create player"
	_confirm.text = "Save name" if rename else "Create player"
	_name.text = name
	_feedback.text = ""
	_feedback.hide()
	_connect_ui(_confirm.pressed, _confirm_name.bind(opening, epoch, _generation))
	_connect_ui(_cancel.pressed, _dismiss.bind(opening, epoch, _generation))
	_connect_ui(_name.text_submitted, _submitted.bind(opening, epoch, _generation))
	_connect_ui(_name.text_changed, _changed.bind(opening, epoch, _generation))
	_active = true
	_update_actions()
	show()
	_fit()
	focus_cancel()
	return true

func set_feedback(opening: int, epoch: int, message: String, busy: bool) -> void:
	if not _matches(opening, epoch, _generation):
		return
	_feedback.text = message.left(1024)
	_feedback.visible = not _feedback.text.is_empty()
	_busy = busy
	_update_actions()

func retire() -> void:
	_active = false
	_disconnect_ui()
	_busy = false
	_update_actions()
	_name.text = ""
	_feedback.text = ""
	hide()

func focus_cancel() -> void:
	if _matches(_opening, _epoch, _generation):
		_cancel.grab_focus()

func _fit() -> void:
	if is_instance_valid(_card):
		_card.custom_minimum_size = Vector2(maxf(320, minf(600, size.x - 32)), maxf(300, minf(360, size.y - 32)))

func _update_actions() -> void:
	var valid: bool = _valid_name(_name.text)
	_confirm.disabled = not _active or _busy or not valid
	_cancel.disabled = not _active
	_validation.text = "" if valid or _name.text.is_empty() else "Use 1–40 characters without edge spaces or control characters."
	_validation.visible = not _validation.text.is_empty()

func _changed(_text: String, opening: int, epoch: int, generation: int) -> void:
	if _matches(opening, epoch, generation):
		_update_actions()

func _submitted(_text: String, opening: int, epoch: int, generation: int) -> void:
	_confirm_name(opening, epoch, generation)

func _confirm_name(opening: int, epoch: int, generation: int) -> void:
	if _matches(opening, epoch, generation) and not _busy and _valid_name(_name.text):
		name_confirmed.emit(opening, epoch, _name.text)

# Internal presentation guards supplement Root's live-widget registry; they do not
# authorize storage operations or establish native request identity.
func _matches(opening: int, epoch: int, generation: int) -> bool:
	return _active and is_inside_tree() and is_visible_in_tree() \
		and opening == _opening and epoch == _epoch and generation == _generation

func _connect_ui(source_signal: Signal, callback: Callable) -> void:
	source_signal.connect(callback)
	_connections.append({"signal": source_signal, "callback": callback})

func _disconnect_ui() -> void:
	for binding: Dictionary in _connections:
		var source_signal: Signal = binding["signal"]
		var callback: Callable = binding["callback"]
		if source_signal.is_connected(callback):
			source_signal.disconnect(callback)
	_connections.clear()

func _visibility_changed() -> void:
	if _active and not is_visible_in_tree():
		retire()

# LineEdit consumes Escape while editing. Retire this page before that GUI
# focus release so one ordinary Escape remains the explicit Cancel action.
func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo \
		and (event.keycode == KEY_ESCAPE or event.physical_keycode == KEY_ESCAPE) and _matches(_opening, _epoch, _generation):
		get_viewport().set_input_as_handled()
		dismissed.emit(_opening, _epoch)

func _dismiss(opening: int, epoch: int, generation: int) -> void:
	if _matches(opening, epoch, generation):
		dismissed.emit(opening, epoch)

func _label(parent: Node, text: String, pixels: int = 16) -> Label:
	var item := Label.new()
	item.text = text
	item.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	item.add_theme_font_size_override("font_size", pixels)
	parent.add_child(item)
	return item

func _button(parent: Node, caption: String) -> Button:
	var item := Button.new()
	item.text = caption
	item.custom_minimum_size.y = 42
	item.focus_mode = Control.FOCUS_ALL
	item.add_theme_font_size_override("font_size", 16)
	parent.add_child(item)
	return item

func _style() -> void:
	var page_theme := Theme.new()
	page_theme.default_font_size = 16
	page_theme.set_color("font_color", "Label", Color("edf3f7"))
	page_theme.set_color("font_color", "Button", Color("edf3f7"))
	page_theme.set_color("font_disabled_color", "Button", Color("93a6b6"))
	page_theme.set_color("font_color", "LineEdit", Color("edf3f7"))
	page_theme.set_color("caret_color", "LineEdit", Color("5ee0ce"))
	for state: String in ["normal", "hover", "pressed", "disabled"]:
		var box := StyleBoxFlat.new()
		box.bg_color = Color("263b50") if state != "hover" else Color("345269")
		if state == "pressed":
			box.bg_color = Color("225b60")
		if state == "disabled":
			box.bg_color = Color("223140")
		box.set_corner_radius_all(5)
		box.content_margin_left = 12
		box.content_margin_right = 12
		box.content_margin_top = 8
		box.content_margin_bottom = 8
		page_theme.set_stylebox(state, "Button", box)
	var focus := StyleBoxFlat.new()
	focus.bg_color = Color(0, 0, 0, 0)
	focus.border_color = Color("5ee0ce")
	focus.set_border_width_all(3)
	focus.set_corner_radius_all(5)
	page_theme.set_stylebox("focus", "Button", focus)
	page_theme.set_stylebox("focus", "LineEdit", focus)
	var field := StyleBoxFlat.new()
	field.bg_color = Color("132435")
	field.content_margin_left = 12
	field.content_margin_right = 12
	field.content_margin_top = 10
	field.content_margin_bottom = 10
	page_theme.set_stylebox("normal", "LineEdit", field)
	theme = page_theme

func _shell(title: String) -> VBoxContainer:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_style()
	var shade := ColorRect.new()
	shade.color = Color(0.02, 0.04, 0.07, 0.9)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(shade)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	_card = PanelContainer.new()
	var card_style := StyleBoxFlat.new()
	card_style.bg_color = Color("172a3c")
	card_style.set_corner_radius_all(10)
	card_style.content_margin_left = 20
	card_style.content_margin_right = 20
	card_style.content_margin_top = 18
	card_style.content_margin_bottom = 18
	_card.add_theme_stylebox_override("panel", card_style)
	center.add_child(_card)
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 10)
	_card.add_child(body)
	_label(body, title, 24)
	resized.connect(_fit)
	visibility_changed.connect(_visibility_changed)
	return body

func _valid_name(value: String) -> bool:
	if value.length() < 1 or value.length() > 40 or value.to_utf8_buffer().size() > 160:
		return false
	for index: int in value.length():
		var code: int = value.unicode_at(index)
		if code < 32 or code == 127 or (code >= 0xd800 and code <= 0xdfff) or code > 0x10ffff:
			return false
	return not _name_space(value.unicode_at(0)) and not _name_space(value.unicode_at(value.length() - 1))

func _name_space(code: int) -> bool:
	return code == 32 or code == 0x85 or code == 0xa0 or code == 0x1680 \
		or (code >= 0x2000 and code <= 0x200a) or code in [0x2028, 0x2029, 0x202f, 0x205f, 0x3000]
