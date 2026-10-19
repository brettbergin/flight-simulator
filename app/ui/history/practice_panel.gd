extends Control

signal next_requested(opening: int, epoch: int, before_creation_sequence: Variant)
signal details_requested(opening: int, epoch: int, practice_id: String)
signal prune_requested(opening: int, epoch: int, practice_ids: Array)
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

var _page: Dictionary = {}
var _player_id: String = ""
var _rows: VBoxContainer
var _checks: Array[CheckBox] = []
var _details_buttons: Array[Button] = []
var _next: Button
var _prune: Button
var _confirmation: VBoxContainer
var _confirmation_label: Label
var _confirm: Button
var _keep: Button
var _confirmed_ids: Array = []

func _ready() -> void:
	var body: VBoxContainer = _shell("Practice history")
	_label(body, "Observed simulation intervals — not pilot hours or lesson results.", 14)
	var contents: VBoxContainer = _scroll(body)
	_rows = VBoxContainer.new()
	_rows.add_theme_constant_override("separation", 14)
	contents.add_child(_rows)
	_feedback = _label(contents, "")
	_feedback.add_theme_color_override("font_color", Color("ffcf8c"))
	_confirmation = VBoxContainer.new()
	contents.add_child(_confirmation)
	_confirmation_label = _label(_confirmation, "")
	var choices := HBoxContainer.new()
	_confirmation.add_child(choices)
	_confirm = _button(choices, "Remove these rows")
	_keep = _button(choices, "Cancel removal")
	_confirmation.hide()
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 12)
	body.add_child(actions)
	_prune = _button(actions, "Remove selected…")
	_next = _button(actions, "Next page")
	_cancel = _button(actions, "Cancel")
	_cancel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_fit()
	hide()

func present(opening: int, epoch: int, player_id: String, page: Dictionary) -> bool:
	if not is_node_ready() or not is_inside_tree() or opening <= 0 or epoch < 0 \
		or _generation == 9223372036854775807 or not _valid_id(player_id) \
		or not _keys(page, ["practice", "next_before_creation_sequence"]) or typeof(page["practice"]) != TYPE_ARRAY:
		return false
	var entries: Array = page["practice"]
	if entries.size() > 50 or (page["next_before_creation_sequence"] != null and not _u64(page["next_before_creation_sequence"], true)):
		return false
	var seen: Dictionary = {}
	for entry: Variant in entries:
		if not _valid_practice(entry, true) or entry["player_id"] != player_id or seen.has(entry["id"]): return false
		seen[entry["id"]] = true
	_active = false
	_disconnect_ui()
	_generation += 1
	_opening = opening
	_epoch = epoch
	_player_id = player_id
	_page = page.duplicate(true)
	_busy = false
	_confirmed_ids.clear()
	_confirmation.hide()
	_feedback.text = ""
	_feedback.hide()
	_checks.clear()
	_details_buttons.clear()
	_clear_rows(_rows)
	if entries.is_empty(): _label(_rows, "No practice history on this page.")
	for entry: Dictionary in _page["practice"]:
		var row := VBoxContainer.new()
		_rows.add_child(row)
		_label(row, entry["started_utc"] + " · " + _status_caption(entry["status"]))
		_label(row, _duration(entry["observed_ticks"]) + " observed interval · " + String(entry["source"]["model_identity"]["id"]), 14)
		var actions := HBoxContainer.new()
		row.add_child(actions)
		var check := CheckBox.new()
		check.text = "Select for removal"
		check.set_meta("practice_id", entry["id"])
		check.set_meta("terminal", entry["status"] != "active")
		actions.add_child(check)
		_checks.append(check)
		_connect_ui(check.toggled, _selection_changed.bind(opening, epoch, _generation))
		var details: Button = _button(actions, "Details")
		_details_buttons.append(details)
		_connect_ui(details.pressed, _details.bind(opening, epoch, _generation, entry["id"]))
	_connect_ui(_next.pressed, _next_page.bind(opening, epoch, _generation))
	_connect_ui(_prune.pressed, _ask_remove.bind(opening, epoch, _generation))
	_connect_ui(_confirm.pressed, _remove.bind(opening, epoch, _generation))
	_connect_ui(_keep.pressed, _cancel_remove.bind(opening, epoch, _generation))
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
	_page.clear()
	_confirmed_ids.clear()
	_player_id = ""
	_confirmation.hide()
	hide()

func _selected_ids() -> Array:
	var ids: Array = []
	for check: CheckBox in _checks:
		if check.button_pressed and check.get_meta("terminal"): ids.append(check.get_meta("practice_id"))
	return ids

func _update_actions() -> void:
	var enabled: bool = _active and not _busy and not _confirmation.visible
	for check: CheckBox in _checks: check.disabled = not enabled or not check.get_meta("terminal")
	for item: Button in _details_buttons: item.disabled = not enabled
	_prune.disabled = not enabled or _selected_ids().is_empty()
	_next.disabled = not enabled or _page.get("next_before_creation_sequence") == null
	_confirm.disabled = not _active or _busy or _confirmed_ids.is_empty()
	_keep.disabled = not _active
	_cancel.disabled = not _active

func _selection_changed(_pressed: bool, opening: int, epoch: int, generation: int) -> void:
	if _matches(opening, epoch, generation): _update_actions()

func _details(opening: int, epoch: int, generation: int, practice_id: String) -> void:
	if _matches(opening, epoch, generation) and not _busy and not _confirmation.visible:
		details_requested.emit(opening, epoch, practice_id)

func _next_page(opening: int, epoch: int, generation: int) -> void:
	if _matches(opening, epoch, generation) and not _busy and not _confirmation.visible and _page["next_before_creation_sequence"] != null:
		next_requested.emit(opening, epoch, _page["next_before_creation_sequence"])

func _ask_remove(opening: int, epoch: int, generation: int) -> void:
	if not _matches(opening, epoch, generation) or _busy or _confirmation.visible: return
	_confirmed_ids = _selected_ids().duplicate()
	if _confirmed_ids.is_empty(): return
	_confirmation_label.text = "Remove %d selected history rows for this player? External recordings and exports remain. This cannot be undone here." % _confirmed_ids.size()
	_confirmation.show()
	_update_actions()
	_keep.grab_focus()

func _cancel_remove(opening: int, epoch: int, generation: int) -> void:
	if not _matches(opening, epoch, generation): return
	_confirmed_ids.clear()
	_confirmation.hide()
	_update_actions()
	focus_cancel()

func _remove(opening: int, epoch: int, generation: int) -> void:
	if _matches(opening, epoch, generation) and not _busy and _confirmation.visible and not _confirmed_ids.is_empty():
		prune_requested.emit(opening, epoch, _confirmed_ids.duplicate())

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
			_cancel_remove(_opening, _epoch, _generation)
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

func _valid_practice(value: Variant, summary: bool) -> bool:
	if typeof(value) != TYPE_DICTIONARY or not _keys(value, ["type", "version", "id", "player_id", "source", "started_utc", "last_observed_utc", "first_tick", "last_tick", "observed_ticks", "tick_rate_hz", "status", "end_reason", "revision", "creation_sequence", "commit_sequence", "archive"]):
		return false
	if value["type"] != "LocalPractice" or typeof(value["version"]) != TYPE_INT or value["version"] != 1 \
		or not _text(value["id"], 32) or not _valid_id(value["id"]) or not _text(value["player_id"], 32) or not _valid_id(value["player_id"]):
		return false
	if typeof(value["tick_rate_hz"]) != TYPE_INT or value["tick_rate_hz"] != 120:
		return false
	for key: String in ["first_tick", "last_tick", "observed_ticks"]:
		if not _u64(value[key]):
			return false
	for key: String in ["revision", "creation_sequence", "commit_sequence"]:
		if not _u64(value[key], true):
			return false
	if not _text(value["started_utc"], 32) or not _text(value["last_observed_utc"], 32) or not _text(value["status"], 24):
		return false
	match value["status"]:
		"active":
			if value["end_reason"] != null: return false
		"manually_ended":
			if not value["end_reason"] in ["user_end", "user_restart", "user_quit"]: return false
		"source_ended":
			if value["end_reason"] != "native_terminal": return false
		"interrupted":
			if value["end_reason"] != "previous_process_incomplete": return false
		_: return false
	var source: Variant = value["source"]
	if typeof(source) != TYPE_DICTIONARY or not _keys(source, ["session_id", "model_identity", "source_variant", "native_source_fingerprint", "prepared_world_sha256", "named_start", "wind_profile", "angular_integration_method"]):
		return false
	for key: String in ["session_id", "source_variant", "native_source_fingerprint", "prepared_world_sha256", "named_start", "wind_profile"]:
		if not _text(source[key], 128): return false
	if source["angular_integration_method"] != null and not _text(source["angular_integration_method"], 64):
		return false
	var model: Variant = source["model_identity"]
	if typeof(model) != TYPE_DICTIONARY or not _keys(model, ["id", "version", "backend_model"]):
		return false
	for key: String in ["id", "version", "backend_model"]:
		if not _text(model[key], 128): return false
	var archive: Variant = value["archive"]
	if summary:
		return typeof(archive) == TYPE_DICTIONARY and _keys(archive, ["linked"]) and typeof(archive["linked"]) == TYPE_BOOL
	if archive == null: return true
	if typeof(archive) != TYPE_DICTIONARY or not _keys(archive, ["type", "version", "absolute_path", "payload_sha256", "recording_session_id", "first_tick", "last_tick", "linked_utc"]):
		return false
	return archive["type"] == "ExternalRecordedReview" and typeof(archive["version"]) == TYPE_INT and archive["version"] == 1 \
		and _text(archive["absolute_path"], 4096) and _text(archive["payload_sha256"], 64) \
		and _text(archive["recording_session_id"], 128) and _text(archive["linked_utc"], 32) \
		and _u64(archive["first_tick"]) and _u64(archive["last_tick"])

func _duration(ticks: String) -> String:
	# Decimal long division avoids converting a U64 interval to signed int/float.
	var seconds: String = ""
	var remainder: int = 0
	for index: int in ticks.length():
		remainder = remainder * 10 + ticks.unicode_at(index) - 48
		var digit: int = floori(float(remainder) / 120.0)
		if not seconds.is_empty() or digit != 0:
			seconds += str(digit)
		remainder -= digit * 120
	if seconds.is_empty(): seconds = "0"
	var milliseconds: int = floori(float(remainder * 1000) / 120.0)
	return "%s.%03d s" % [seconds, milliseconds]

func _status_caption(status: String) -> String:
	match status:
		"active": return "Active history row"
		"manually_ended": return "Ended by player"
		"source_ended": return "Simulation ended"
		_: return "Interrupted"

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
