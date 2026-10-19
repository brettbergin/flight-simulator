extends Control

signal export_requested(opening: int, epoch: int, target_absolute_path: String)
signal dismissed(opening: int, epoch: int)

var _opening: int = 0
var _epoch: int = 0
var _generation: int = 0
var _active: bool = false
var _busy: bool = false
var _connections: Array[Dictionary] = []
var _card: PanelContainer
var _feedback: Label
var _cancel: Button

var _player: Dictionary = {}
var _receipt: Variant = null
var _folder: String = ""
var _heading: Label
var _scope: Label
var _folder_label: Label
var _receipt_label: Label
var _filename: LineEdit
var _choose: Button
var _export: Button
var _dialog: FileDialog

func _ready() -> void:
	var body: VBoxContainer = _shell("Export player summary")
	_heading = _label(body, "")
	var contents: VBoxContainer = _scroll(body)
	_scope = _label(contents, "Includes this player's name, preferences (including device names and GUIDs), practice summaries and source information. No upload. This is not a flight or backup import.", 14)
	_choose = _button(contents, "Choose export folder…")
	_folder_label = _label(contents, "No folder selected", 14)
	_label(contents, "New file name", 14)
	_filename = LineEdit.new()
	_filename.max_length = 120
	_filename.custom_minimum_size.y = 44
	contents.add_child(_filename)
	_label(contents, "Choose a new file. Existing files are never replaced. Local storage and linked archive paths are excluded.", 14)
	_receipt_label = _label(contents, "")
	_feedback = _label(contents, "")
	_feedback.add_theme_color_override("font_color", Color("ffcf8c"))
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 12)
	body.add_child(actions)
	_export = _button(actions, "Export to new file")
	_cancel = _button(actions, "Cancel")
	_cancel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# Directory selection + a separate filename avoids an overwrite-confirmation
	# dialog. The native selected-output boundary still admits the final path.
	_dialog = FileDialog.new()
	_dialog.title = "Choose export folder"
	_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_dialog.file_mode = FileDialog.FILE_MODE_OPEN_DIR
	add_child(_dialog)
	_fit()
	hide()

func present(opening: int, epoch: int, player: Dictionary, receipt: Variant) -> bool:
	if not is_node_ready() or not is_inside_tree() or opening <= 0 or epoch < 0 \
		or _generation == 9223372036854775807 or not _valid_player(player) or not _valid_receipt(receipt, player["id"]): return false
	_active = false
	_dialog.hide()
	_disconnect_ui()
	_generation += 1
	_opening = opening
	_epoch = epoch
	_player = player.duplicate(true)
	_receipt = receipt.duplicate(true) if receipt != null else null
	_busy = false
	_folder = ""
	_heading.text = "Player: " + _player["name"]
	_folder_label.text = "No folder selected"
	_filename.text = "player-" + String(_player["id"]).right(8) + ".json"
	_feedback.text = ""
	_feedback.hide()
	_receipt_label.text = _receipt_text()
	_receipt_label.visible = not _receipt_label.text.is_empty()
	_connect_ui(_choose.pressed, _choose_folder.bind(opening, epoch, _generation))
	_connect_ui(_dialog.dir_selected, _folder_selected.bind(opening, epoch, _generation))
	_connect_ui(_filename.text_changed, _filename_changed.bind(opening, epoch, _generation))
	_connect_ui(_export.pressed, _export_file.bind(opening, epoch, _generation))
	_connect_ui(_cancel.pressed, _dismiss.bind(opening, epoch, _generation))
	_active = true
	_update_actions()
	show()
	_fit()
	focus_cancel()
	return true

func retire() -> void:
	_active = false
	_disconnect_ui()
	_dialog.hide()
	_update_actions()
	_player.clear()
	_receipt = null
	_folder = ""
	hide()

func _update_actions() -> void:
	var enabled: bool = _active and not _busy
	_choose.disabled = not enabled
	_filename.editable = enabled
	_export.disabled = not enabled or _target().is_empty()
	_cancel.disabled = not _active
	if _busy: _dialog.hide()

func _choose_folder(opening: int, epoch: int, generation: int) -> void:
	if _matches(opening, epoch, generation) and not _busy:
		_dialog.popup_centered_ratio(0.75)

func _folder_selected(path: String, opening: int, epoch: int, generation: int) -> void:
	if not _matches(opening, epoch, generation) or _busy or not path.is_absolute_path() or path.to_utf8_buffer().size() > 4096: return
	_folder = path
	_folder_label.text = path
	_update_actions()

func _filename_changed(_text_value: String, opening: int, epoch: int, generation: int) -> void:
	if _matches(opening, epoch, generation): _update_actions()

func _target() -> String:
	if _folder.is_empty() or not _folder.is_absolute_path() or not _valid_filename(_filename.text): return ""
	var path: String = _folder.path_join(_filename.text)
	return path if path.to_utf8_buffer().size() <= 4096 else ""

func _valid_filename(value: String) -> bool:
	if value.is_empty() or value.length() > 120 or value.ends_with(" ") or value.ends_with("."): return false
	for index: int in value.length():
		var code: int = value.unicode_at(index)
		if code < 32 or code == 127 or (code >= 0xd800 and code <= 0xdfff) or code > 0x10ffff or code in [34, 42, 47, 58, 60, 62, 63, 92, 124]: return false
	return true

func _export_file(opening: int, epoch: int, generation: int) -> void:
	if not _matches(opening, epoch, generation) or _busy: return
	var path: String = _target()
	if not path.is_empty(): export_requested.emit(opening, epoch, path)

func _receipt_text() -> String:
	if _receipt == null: return ""
	match _receipt["outcome"]:
		"saved":
			return "Export saved and verified: " + _receipt["target_absolute_path"]
		"recovery_required":
			return "Export needs attention. A file may have been installed; do not overwrite or retry automatically.\nTarget: " + _receipt["target_absolute_path"] + _temporary_text()
		_:
			return "Export not saved.\nTarget: " + _receipt["target_absolute_path"] + _temporary_text()

func _temporary_text() -> String:
	return "" if _receipt["temporary_absolute_path"] == null else "\nRetained temporary file: " + _receipt["temporary_absolute_path"]

func _valid_receipt(receipt: Variant, player_id: String) -> bool:
	if receipt == null: return true
	if typeof(receipt) != TYPE_DICTIONARY or not _keys(receipt, ["operation_id", "outcome", "phase", "target_absolute_path", "temporary_absolute_path", "installed", "bytes", "sha256", "player_id", "preferences_revision", "practice_count"]): return false
	if not _text(receipt["operation_id"], 32) or not _valid_id(receipt["operation_id"]) or not _text(receipt["outcome"], 24) or not receipt["outcome"] in ["saved", "not_saved", "recovery_required"]: return false
	if not _text(receipt["phase"], 24) or not receipt["phase"] in ["read", "encode", "create", "write", "flush", "verify_temp", "move", "verify_target", "done"]: return false
	if not _text(receipt["target_absolute_path"], 4096) or not String(receipt["target_absolute_path"]).is_absolute_path(): return false
	if receipt["temporary_absolute_path"] != null and (not _text(receipt["temporary_absolute_path"], 4096) or not String(receipt["temporary_absolute_path"]).is_absolute_path()): return false
	if receipt["installed"] != null and typeof(receipt["installed"]) != TYPE_BOOL: return false
	if receipt["player_id"] == null:
		if receipt["preferences_revision"] != null or receipt["practice_count"] != null: return false
	elif typeof(receipt["player_id"]) != TYPE_STRING or receipt["player_id"] != player_id or not _u64(receipt["preferences_revision"], true) \
		or typeof(receipt["practice_count"]) != TYPE_INT or receipt["practice_count"] < 0 or receipt["practice_count"] > 2000: return false
	if receipt["bytes"] == null:
		if receipt["sha256"] != null: return false
	elif typeof(receipt["bytes"]) != TYPE_INT or receipt["bytes"] < 0 or receipt["bytes"] > 33554432 or not _text(receipt["sha256"], 64): return false
	if receipt["outcome"] == "saved":
		return receipt["phase"] == "done" and typeof(receipt["installed"]) == TYPE_BOOL and receipt["installed"] \
			and receipt["temporary_absolute_path"] == null and receipt["player_id"] != null and receipt["bytes"] != null
	return true

func set_feedback(opening: int, epoch: int, message: String, busy: bool) -> void:
	if not _matches(opening, epoch, _generation): return
	_feedback.text = message.left(1024)
	_feedback.visible = not _feedback.text.is_empty()
	_busy = busy
	_update_actions()

func focus_cancel() -> void:
	if _matches(_opening, _epoch, _generation): _cancel.grab_focus()

func _fit() -> void:
	if is_instance_valid(_card):
		_card.custom_minimum_size = Vector2(maxf(320, minf(720, size.x - 32)), maxf(300, minf(480, size.y - 32)))
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
func _keys(value: Dictionary, expected: Array) -> bool:
	if value.size() != expected.size():
		return false
	for key: Variant in value:
		if typeof(key) != TYPE_STRING or not key in expected:
			return false
	return true

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


func _u64(value: Variant, nonzero: bool = false) -> bool:
	if typeof(value) != TYPE_STRING or value.is_empty() or value.length() > 20:
		return false
	if value == "0":
		return not nonzero
	return _valid_revision(value)

func _text(value: Variant, cap: int = 256) -> bool:
	return typeof(value) == TYPE_STRING and value.length() <= cap

func _valid_player(player: Dictionary) -> bool:
	return _keys(player, ["type", "version", "id", "name", "created_utc", "updated_utc", "revision"]) \
		and player["type"] == "LocalPlayer" and typeof(player["version"]) == TYPE_INT and player["version"] == 1 \
		and _text(player["id"], 32) and _valid_id(player["id"]) and _text(player["name"], 40) \
		and _valid_name(player["name"]) and _text(player["created_utc"], 32) and _text(player["updated_utc"], 32) \
		and _u64(player["revision"], true)

func _scroll(body: VBoxContainer) -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(scroll)
	var contents := VBoxContainer.new()
	contents.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	contents.add_theme_constant_override("separation", 10)
	scroll.add_child(contents)
	return contents

