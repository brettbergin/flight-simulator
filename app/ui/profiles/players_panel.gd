extends Control

signal player_chosen(opening: int, epoch: int, player_id: String)
signal guest_chosen(opening: int, epoch: int)
signal create_requested(opening: int, epoch: int)
signal rename_requested(opening: int, epoch: int)
signal history_requested(opening: int, epoch: int)
signal dismissed(opening: int, epoch: int)

var _opening: int = 0
var _epoch: int = 0
var _generation: int = 0
var _active: bool = false
var _busy: bool = false
var _players: Array = []
var _selected: Variant = null
var _storage: Dictionary = {}
var _connections: Array[Dictionary] = []
var _choice_buttons: Array[Button] = []
var _card: PanelContainer
var _current: Label
var _storage_label: Label
var _rows: VBoxContainer
var _feedback: Label
var _guest: Button
var _create: Button
var _rename: Button
var _history: Button
var _cancel: Button

func _ready() -> void:
	var body: VBoxContainer = _shell("Players")
	_current = _label(body, "")
	_storage_label = _label(body, "")
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(scroll)
	var contents := VBoxContainer.new()
	contents.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	contents.add_theme_constant_override("separation", 10)
	scroll.add_child(contents)
	_rows = VBoxContainer.new()
	_rows.add_theme_constant_override("separation", 8)
	contents.add_child(_rows)
	_feedback = _label(contents, "")
	_feedback.add_theme_color_override("font_color", Color("ffcf8c"))
	_guest = _button(body, "Use Guest — reset to defaults")
	_label(body, "Guest does not save preferences or practice history.", 14)
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 8)
	body.add_child(actions)
	_create = _button(actions, "Create player")
	_rename = _button(actions, "Rename current")
	_history = _button(actions, "History")
	_cancel = _button(actions, "Cancel")
	_cancel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_fit()
	hide()

func present(opening: int, epoch: int, players: Array, selected_player_id: Variant, storage: Dictionary) -> bool:
	if not is_node_ready() or not is_inside_tree() or opening <= 0 or epoch < 0 \
		or _generation == 9223372036854775807 or not _valid_players(players) or not _valid_storage(storage):
		return false
	if selected_player_id != null and (typeof(selected_player_id) != TYPE_STRING or not _valid_id(selected_player_id)):
		return false
	var selected_name: String = "Guest"
	var selected_found: bool = selected_player_id == null
	for player: Dictionary in players:
		if player["id"] == selected_player_id:
			selected_found = true
			selected_name = player["name"]
	if not selected_found:
		return false
	_active = false
	_disconnect_ui()
	_generation += 1
	_opening = opening
	_epoch = epoch
	_players = players.duplicate(true)
	_selected = selected_player_id
	_storage = storage.duplicate(true)
	_busy = false
	_current.text = "Current player: " + selected_name
	_storage_label.text = "Storage: " + _storage_caption(_storage["state"])
	_feedback.text = ""
	_feedback.hide()
	_choice_buttons.clear()
	for child: Node in _rows.get_children():
		_rows.remove_child(child)
		child.queue_free()
	if _players.is_empty():
		_label(_rows, "No saved players yet. Create one to keep your preferences.")
	for player: Dictionary in _players:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		_rows.add_child(row)
		var identity := VBoxContainer.new()
		identity.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(identity)
		_label(identity, player["name"])
		var detail: String = "ID …" + String(player["id"]).right(8)
		if player["id"] == _selected:
			detail = "Current · " + detail
		var badge: Label = _label(identity, detail, 14)
		badge.add_theme_color_override("font_color", Color("6fe0d1"))
		var choose: Button = _button(row, "Use player")
		choose.set_meta("player_id", player["id"])
		_choice_buttons.append(choose)
		_connect_ui(choose.pressed, _choose.bind(opening, epoch, _generation, player["id"]))
	_connect_ui(_guest.pressed, _action.bind(opening, epoch, _generation, "guest"))
	_connect_ui(_create.pressed, _action.bind(opening, epoch, _generation, "create"))
	_connect_ui(_rename.pressed, _action.bind(opening, epoch, _generation, "rename"))
	_connect_ui(_history.pressed, _action.bind(opening, epoch, _generation, "history"))
	_connect_ui(_cancel.pressed, _dismiss.bind(opening, epoch, _generation))
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
	_players.clear()
	_storage.clear()
	_selected = null
	hide()

func focus_cancel() -> void:
	if _matches(_opening, _epoch, _generation):
		_cancel.grab_focus()

func _fit() -> void:
	if is_instance_valid(_card):
		_card.custom_minimum_size = Vector2(maxf(320, minf(720, size.x - 32)), maxf(300, minf(480, size.y - 32)))

func _can_use_storage() -> bool:
	return _active and not _busy and _storage.get("state") == "ready"

func _update_actions() -> void:
	for item: Button in _choice_buttons:
		item.disabled = not _can_use_storage() or item.get_meta("player_id") == _selected
	_guest.disabled = not _active or _busy
	_create.disabled = not _can_use_storage() or _players.size() >= 8
	_rename.disabled = not _can_use_storage() or _selected == null
	_history.disabled = not _can_use_storage() or _selected == null
	_cancel.disabled = not _active

func _choose(opening: int, epoch: int, generation: int, player_id: String) -> void:
	if _matches(opening, epoch, generation) and _can_use_storage() and player_id != _selected:
		player_chosen.emit(opening, epoch, player_id)

func _action(opening: int, epoch: int, generation: int, action: String) -> void:
	if not _matches(opening, epoch, generation) or _busy:
		return
	match action:
		"guest":
			guest_chosen.emit(opening, epoch)
		"create":
			if _can_use_storage() and _players.size() < 8:
				create_requested.emit(opening, epoch)
		"rename":
			if _can_use_storage() and _selected != null:
				rename_requested.emit(opening, epoch)
		"history":
			if _can_use_storage() and _selected != null:
				history_requested.emit(opening, epoch)

func _storage_caption(state: String) -> String:
	match state:
		"ready": return "Ready"
		"new", "opening": return "Opening…"
		"read_only": return "Read only — saved changes need reconciliation"
		"unavailable": return "Unavailable — Guest is available"
		"closing": return "Closing…"
		_: return "Closed — Guest is available"

func _valid_id(value: String) -> bool:
	if value.length() != 32:
		return false
	for code: int in value.to_utf8_buffer():
		if not (code >= 48 and code <= 57) and not (code >= 97 and code <= 102):
			return false
	return true

func _valid_revision(value: Variant) -> bool:
	if typeof(value) != TYPE_STRING or value.is_empty() or value.length() > 20 or value[0] == "0":
		return false
	for code: int in value.to_utf8_buffer():
		if code < 48 or code > 57:
			return false
	return value.length() < 20 or value <= "18446744073709551615"

func _keys(value: Dictionary, expected: Array) -> bool:
	if value.size() != expected.size():
		return false
	for key: Variant in value:
		if typeof(key) != TYPE_STRING or not key in expected:
			return false
	return true

func _valid_players(players: Array) -> bool:
	if players.size() > 8:
		return false
	var ids: Dictionary = {}
	for value: Variant in players:
		if typeof(value) != TYPE_DICTIONARY or not _keys(value, ["id", "name", "revision"]):
			return false
		if typeof(value["id"]) != TYPE_STRING or not _valid_id(value["id"]) or ids.has(value["id"]):
			return false
		if typeof(value["name"]) != TYPE_STRING or not _valid_name(value["name"]) or not _valid_revision(value["revision"]):
			return false
		ids[value["id"]] = true
	return true

func _valid_storage(storage: Dictionary) -> bool:
	if not _keys(storage, ["state", "error_code", "pending", "undelivered", "writer_alive", "resolved_root", "store_version"]):
		return false
	if typeof(storage["state"]) != TYPE_STRING or not storage["state"] in ["new", "opening", "ready", "closing", "closed", "read_only", "unavailable"]:
		return false
	if typeof(storage["error_code"]) != TYPE_STRING or typeof(storage["writer_alive"]) != TYPE_BOOL:
		return false
	for key: String in ["pending", "undelivered"]:
		if typeof(storage[key]) != TYPE_INT or storage[key] < 0 or storage[key] > 16:
			return false
	if storage["pending"] + storage["undelivered"] > 16:
		return false
	if storage["resolved_root"] != null and typeof(storage["resolved_root"]) != TYPE_STRING:
		return false
	return storage["store_version"] == null or (typeof(storage["store_version"]) == TYPE_INT and storage["store_version"] == 1)

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

func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo \
		and event.keycode == KEY_ESCAPE and _matches(_opening, _epoch, _generation):
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
