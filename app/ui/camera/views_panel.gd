extends Control
# Original MIT. Paused copied draft only; Scene owns eligibility and adoption.
signal apply_requested(settings: Dictionary, source_session: String)
signal cancel_requested(source_session: String)

const Policy = preload("res://camera/view_policy.gd")
const PRESETS = ["cockpit", "forward_horizon", "left_window", "right_window", "panel", "chase", "orbit"]
const PRESET_LABELS = ["Cockpit", "Forward horizon", "Left window", "Right window", "Panel", "Chase", "Orbit"]
var _source_session: String = ""
var _current: Dictionary = {}
var _draft: Dictionary = {}
var _active: bool = false
var _opening_revision: int = 0
var _focus_revision: int = 0
var _preset: OptionButton
var _fov: SpinBox
var _response: OptionButton
var _restore: Button
var _apply: Button
var _cancel: Button
var _current_label: Label
var _error: Label
var _scroll: ScrollContainer

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visibility_changed.connect(_on_visibility_changed)
	var shade := ColorRect.new()
	shade.color = Color(0.01, 0.025, 0.04, 1.0)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(shade)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for edge in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + edge, 24)
	add_child(margin)
	# Keep the current camera summary and default Cancel focus outside the
	# scrolling form. Focusing Cancel must not hide the title or live summary.
	var shell := VBoxContainer.new()
	shell.add_theme_constant_override("separation", 8)
	margin.add_child(shell)
	var heading := _label(shell, "VIEWS · FLIGHT PAUSED", 23)
	heading.name = "ViewsHeading"
	_current_label = _label(shell, "", 16)
	_current_label.name = "CurrentView"
	var hint := _label(shell, "Draft only — the camera stays unchanged until Apply. Choices last for this session.", 16)
	hint.name = "DraftHint"
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.follow_focus = true
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	shell.add_child(_scroll)
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 8)
	_scroll.add_child(box)
	var preset_row := HBoxContainer.new()
	box.add_child(preset_row)
	var preset_label := _label(preset_row, "View preset", 16)
	preset_label.custom_minimum_size.x = 230
	_preset = OptionButton.new()
	_preset.name = "Preset"
	for label in PRESET_LABELS: _preset.add_item(label)
	_control_style(_preset)
	_preset.item_selected.connect(_choose_preset)
	_preset.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	preset_row.add_child(_preset)
	var fov_row := HBoxContainer.new()
	box.add_child(fov_row)
	var fov_label := _label(fov_row, "Field of view · degrees (35–90)", 16)
	fov_label.custom_minimum_size.x = 230
	_fov = SpinBox.new()
	_fov.name = "Fov"
	_fov.min_value = 35.0
	_fov.max_value = 90.0
	# Do not quantize a copied live wheel FOV. Arrows still offer one-degree edits.
	_fov.step = 0.0
	_fov.custom_arrow_step = 1.0
	_fov.custom_minimum_size.x = 130
	_control_style(_fov)
	_fov.value_changed.connect(_choose_fov)
	fov_row.add_child(_fov)
	var response_row := HBoxContainer.new()
	box.add_child(response_row)
	var response_label := _label(response_row, "Chase / Orbit response", 16)
	response_label.custom_minimum_size.x = 230
	_response = OptionButton.new()
	_response.name = "ExternalResponse"
	_response.add_item("Smooth · existing offset follow")
	_response.add_item("Immediate · no offset blending")
	_control_style(_response)
	_response.item_selected.connect(_choose_response)
	_response.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	response_row.add_child(_response)
	_label(box, "Recenter selected view resets free look, keeping this preset and FOV. Forward horizon is aircraft-level, not stabilized; window views may include pillars.", 16)
	_label(box, "Side looks can move gauges out of view; flight aids keep their current positions. Use existing hide controls if needed.", 16)
	_label(box, "Original lookout directions; no calibrated Cessna sight picture. Cancel keeps the current view exactly and leaves the flight paused.", 16)
	_error = _label(box, "", 16)
	_error.name = "Error"
	_error.add_theme_color_override("font_color", Color(1.0, 0.76, 0.48))
	# All three actions remain visible even while a long bounded error scrolls.
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 12)
	shell.add_child(actions)
	_restore = _button(actions, "RestoreDefaults", "Restore draft defaults", _restore_defaults)
	_apply = _button(actions, "Apply", "Apply", _request_apply)
	_cancel = _button(actions, "Cancel", "Cancel", _request_cancel)
	_restore.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_apply.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_cancel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# SpinBox's LineEdit is the keyboard editor, rather than the container.
	var chain: Array[Control] = [_preset, _fov.get_line_edit(), _response, _restore, _apply, _cancel]
	for i in chain.size():
		chain[i].focus_neighbor_top = chain[i].get_path_to(chain[(i + chain.size() - 1) % chain.size()])
		chain[i].focus_neighbor_bottom = chain[i].get_path_to(chain[(i + 1) % chain.size()])
		chain[i].focus_previous = chain[i].focus_neighbor_top
		chain[i].focus_next = chain[i].focus_neighbor_bottom
	_refresh()
	hide()

func open(settings: Variant, source_session: Variant) -> bool:
	# Validate everything before touching an already-open draft or its focus work.
	var admitted: Dictionary = Policy.validate(settings)
	if not admitted.ok or typeof(source_session) != TYPE_STRING or source_session.is_empty(): return false
	if not is_inside_tree() or not is_node_ready(): return false
	_opening_revision += 1
	_focus_revision += 1
	_current = admitted.value.duplicate(true)
	_draft = admitted.value.duplicate(true)
	_source_session = source_session
	_active = true
	_error.text = ""
	_refresh()
	show()
	focus_cancel()
	return true

func retire() -> void:
	_opening_revision += 1
	_focus_revision += 1
	_active = false
	_source_session = ""
	_current.clear()
	_draft.clear()
	if is_instance_valid(_error): _error.text = ""
	_refresh()
	hide()

func draft() -> Variant:
	return _draft.duplicate(true) if _can_request() else null

func set_error(message: Variant) -> bool:
	if not _can_request() or typeof(message) != TYPE_STRING or message.length() > 1024: return false
	_error.text = message
	_error.visible = not message.is_empty()
	return true

func get_cancel_button() -> Button:
	return _cancel

func focus_cancel() -> void:
	if not _can_request(): return
	_cancel.grab_focus()
	_focus_revision += 1
	_settle_cancel_scroll(_opening_revision, _focus_revision)

func _can_request() -> bool:
	return _active and is_inside_tree() and is_visible_in_tree() and not _source_session.is_empty() and not _draft.is_empty()

func _choose_preset(index: int) -> void:
	if not _can_request() or index < 0 or index >= PRESETS.size(): return
	var preset: String = PRESETS[index]
	if preset != _draft.preset:
		_draft.preset = preset
		_draft.fov_deg = Policy.describe(preset).default_fov_deg
	_clear_error_and_refresh()

func _choose_fov(value: float) -> void:
	if not _can_request(): return
	var candidate: Dictionary = _draft.duplicate(true)
	candidate.fov_deg = value
	if Policy.validate(candidate).ok: _draft = candidate
	_clear_error_and_refresh()

func _choose_response(index: int) -> void:
	if not _can_request() or index not in [0, 1]: return
	_draft.external_response = "smooth" if index == 0 else "immediate"
	_clear_error_and_refresh()

func _restore_defaults() -> void:
	if not _can_request(): return
	_draft = Policy.defaults()
	_clear_error_and_refresh()

func _request_apply() -> void:
	if not _can_request(): return
	var admitted: Dictionary = Policy.validate(_draft)
	if not admitted.ok:
		set_error(admitted.error)
		return
	# Scene rechecks its own opening token and adopted session. Emission never
	# adopts settings or changes visibility; failed adoption can retain the page.
	apply_requested.emit(admitted.value.duplicate(true), _source_session)

func _request_cancel() -> void:
	if _can_request(): cancel_requested.emit(_source_session)

func _on_visibility_changed() -> void:
	if not is_visible_in_tree():
		_opening_revision += 1
		_focus_revision += 1
		_active = false
		_source_session = ""
		_current.clear()
		_draft.clear()

func _clear_error_and_refresh() -> void:
	_error.text = ""
	_refresh()

func _refresh() -> void:
	if not is_instance_valid(_preset): return
	var enabled: bool = _active and not _draft.is_empty()
	_preset.disabled = not enabled
	_fov.editable = enabled
	_response.disabled = not enabled
	_restore.disabled = not enabled
	_apply.disabled = not enabled
	_cancel.disabled = not enabled
	_error.visible = not _error.text.is_empty()
	if not enabled:
		_current_label.text = "No current Views draft"
		return
	_current_label.text = "Current view: %s · FOV %s° · %s response" % [PRESET_LABELS[PRESETS.find(_current.preset)], str(_current.fov_deg), _current.external_response]
	_preset.select(PRESETS.find(_draft.preset))
	_fov.set_value_no_signal(_draft.fov_deg)
	_response.select(0 if _draft.external_response == "smooth" else 1)

func _settle_cancel_scroll(opening: int, revision: int) -> void:
	# Layout and wrapping settle after show. A retired/replaced opening cannot
	# steal focus or scroll a later page, even for the same session identity.
	for frame in 3:
		if not _can_request() or opening != _opening_revision or revision != _focus_revision: return
		await get_tree().process_frame
	if not _can_request() or opening != _opening_revision or revision != _focus_revision: return
	# Cancel is a fixed footer sibling, not a child of the ScrollContainer.
	# Start the compact form at its first row without touching camera settings.
	if get_viewport().gui_get_focus_owner() == _cancel: _scroll.scroll_vertical = 0

func _control_style(control: Control) -> void:
	control.custom_minimum_size.y = 44
	control.add_theme_font_size_override("font_size", 16)

func _label(parent: Node, text: String, pixels: int) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", pixels)
	parent.add_child(label)
	return label

func _button(parent: Node, node_name: String, text: String, callback: Callable) -> Button:
	var button := Button.new()
	button.name = node_name
	button.text = text
	_control_style(button)
	button.pressed.connect(callback)
	parent.add_child(button)
	return button
