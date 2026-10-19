extends Control

signal delete_requested(opening: int, epoch: int, snapshot_ids: Array)
signal reopen_requested(opening: int, epoch: int)
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

var _summaries: Array = []
var _deletion: Variant = null
var _rows: VBoxContainer
var _checks: Array[CheckBox] = []
var _delete: Button
var _reopen: Button
var _confirmation: VBoxContainer
var _confirmation_label: Label
var _confirm: Button
var _keep: Button
var _confirmed_ids: Array = []

func _ready() -> void:
	var body: VBoxContainer = _shell("Recovery copies")
	_label(body, "Copies may contain data from all players, including deleted records. Removing them does not restore or repair the store.", 14)
	var contents: VBoxContainer = _scroll(body)
	_rows = VBoxContainer.new()
	_rows.add_theme_constant_override("separation", 12)
	contents.add_child(_rows)
	_feedback = _label(contents, "")
	_feedback.add_theme_color_override("font_color", Color("ffcf8c"))
	_confirmation = VBoxContainer.new()
	contents.add_child(_confirmation)
	_confirmation_label = _label(_confirmation, "")
	var choices := HBoxContainer.new()
	_confirmation.add_child(choices)
	_confirm = _button(choices, "Delete these copies")
	_keep = _button(choices, "Cancel deletion")
	_confirmation.hide()
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 12)
	body.add_child(actions)
	_delete = _button(actions, "Delete selected…")
	_reopen = _button(actions, "Reopen storage")
	_cancel = _button(actions, "Cancel")
	_cancel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_fit()
	hide()

func present(opening: int, epoch: int, summaries: Array, deletion: Variant) -> bool:
	if not is_node_ready() or not is_inside_tree() or opening <= 0 or epoch < 0 \
		or _generation == 9223372036854775807 or not _valid_summaries(summaries) or not _valid_deletion(deletion): return false
	_active = false
	_disconnect_ui()
	_generation += 1
	_opening = opening
	_epoch = epoch
	_summaries = summaries.duplicate(true)
	_deletion = deletion.duplicate(true) if deletion != null else null
	_busy = false
	_confirmed_ids.clear()
	_confirmation.hide()
	_checks.clear()
	_clear_rows(_rows)
	if summaries.is_empty(): _label(_rows, "No recovery copies listed.")
	for summary: Dictionary in _summaries:
		var check := CheckBox.new()
		check.text = ("Complete" if summary["state"] == "complete" else "Partial") + " copy · ID …" + String(summary["id"]).right(8)
		check.set_meta("snapshot_id", summary["id"])
		_rows.add_child(check)
		_checks.append(check)
		_connect_ui(check.toggled, _selection_changed.bind(opening, epoch, _generation))
		var created: String = "Creation time unavailable" if summary["created_utc"] == null else summary["created_utc"]
		_label(_rows, created + " · %d bytes" % summary["bytes"], 14)
	if _deletion != null:
		_label(_rows, "%d copies deleted; %d retained." % [_deletion["deleted_ids"].size(), _deletion["retained_ids"].size()])
		for snapshot_id: String in _deletion["retained_ids"]:
			_label(_rows, "Retained ID: " + snapshot_id, 14)
	_feedback.text = ""
	_feedback.hide()
	_connect_ui(_delete.pressed, _ask_delete.bind(opening, epoch, _generation))
	_connect_ui(_confirm.pressed, _delete_copies.bind(opening, epoch, _generation))
	_connect_ui(_keep.pressed, _cancel_delete.bind(opening, epoch, _generation))
	_connect_ui(_reopen.pressed, _reopen_storage.bind(opening, epoch, _generation))
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
	_update_actions()
	_summaries.clear()
	_deletion = null
	_confirmed_ids.clear()
	_confirmation.hide()
	hide()

func _selected_ids() -> Array:
	var ids: Array = []
	for check: CheckBox in _checks:
		if check.button_pressed: ids.append(check.get_meta("snapshot_id"))
	return ids

func _update_actions() -> void:
	var enabled: bool = _active and not _busy and not _confirmation.visible
	for check: CheckBox in _checks: check.disabled = not enabled
	_delete.disabled = not enabled or _selected_ids().is_empty()
	_reopen.disabled = not enabled
	_confirm.disabled = not _active or _busy or _confirmed_ids.is_empty()
	_keep.disabled = not _active
	_cancel.disabled = not _active

func _selection_changed(_pressed: bool, opening: int, epoch: int, generation: int) -> void:
	if _matches(opening, epoch, generation): _update_actions()

func _ask_delete(opening: int, epoch: int, generation: int) -> void:
	if not _matches(opening, epoch, generation) or _busy or _confirmation.visible: return
	_confirmed_ids = _selected_ids().duplicate()
	if _confirmed_ids.is_empty(): return
	_confirmation_label.text = "Delete %d selected recovery copies and any associated work copy? These copies can contain all-player data. External exports and recordings remain. This is not forensic erasure." % _confirmed_ids.size()
	_confirmation.show()
	_update_actions()
	_keep.grab_focus()

func _cancel_delete(opening: int, epoch: int, generation: int) -> void:
	if not _matches(opening, epoch, generation): return
	_confirmed_ids.clear()
	_confirmation.hide()
	_update_actions()
	focus_cancel()

func _delete_copies(opening: int, epoch: int, generation: int) -> void:
	if _matches(opening, epoch, generation) and not _busy and _confirmation.visible and not _confirmed_ids.is_empty():
		delete_requested.emit(opening, epoch, _confirmed_ids.duplicate())

func _reopen_storage(opening: int, epoch: int, generation: int) -> void:
	if _matches(opening, epoch, generation) and not _busy and not _confirmation.visible:
		reopen_requested.emit(opening, epoch)

func _valid_summaries(summaries: Array) -> bool:
	if summaries.size() > 2: return false
	var seen: Dictionary = {}
	for summary: Variant in summaries:
		if typeof(summary) != TYPE_DICTIONARY or not _keys(summary, ["id", "state", "created_utc", "bytes", "manifest_sha256"]): return false
		if not _text(summary["id"], 32) or not _valid_id(summary["id"]) or seen.has(summary["id"]): return false
		seen[summary["id"]] = true
		if not _text(summary["state"], 16) or not summary["state"] in ["complete", "partial"]: return false
		if typeof(summary["bytes"]) != TYPE_INT or summary["bytes"] < 0 or summary["bytes"] > 353370112: return false
		if summary["created_utc"] != null and not _text(summary["created_utc"], 32): return false
		if summary["manifest_sha256"] != null and not _text(summary["manifest_sha256"], 64): return false
		if summary["state"] == "complete" and (summary["created_utc"] == null or summary["manifest_sha256"] == null): return false
	return true

func _valid_deletion(deletion: Variant) -> bool:
	if deletion == null: return true
	if typeof(deletion) != TYPE_DICTIONARY or not _keys(deletion, ["deleted_ids", "retained_ids"]): return false
	var seen: Dictionary = {}
	for key: String in ["deleted_ids", "retained_ids"]:
		if typeof(deletion[key]) != TYPE_ARRAY or deletion[key].size() > 2: return false
		for snapshot_id: Variant in deletion[key]:
			if not _text(snapshot_id, 32) or not _valid_id(snapshot_id) or seen.has(snapshot_id): return false
			seen[snapshot_id] = true
	return seen.size() <= 2

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
		if _confirmation.visible:
			_cancel_delete(_opening, _epoch, _generation)
		else:
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

func _text(value: Variant, cap: int = 256) -> bool:
	return typeof(value) == TYPE_STRING and value.length() <= cap

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

func _clear_rows(rows: Control) -> void:
	for child: Node in rows.get_children():
		rows.remove_child(child)
		child.queue_free()
