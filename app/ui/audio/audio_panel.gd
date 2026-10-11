extends Control
# Original MIT. Copied paused presentation; Scene alone accepts settings/lifecycle.
signal options_requested(options: Dictionary, source_session: String)
signal dismissed

const Options = preload("res://audio/audio_options.gd")
const U64 = preload("res://simulation/uint64.gd")
const CUE_KEYS = ["session_id", "tick", "profile_id", "state", "engine_mode", "shaft_radps", "legacy_throttle", "tas_mps", "starved", "error"]
var _cues: Dictionary = {}
var _options: Dictionary = {}
var _master: CheckBox
var _engine: HSlider
var _airflow: HSlider
var _captions: CheckBox
var _engine_percent: Label
var _airflow_percent: Label
var _qualifier: Label
var _details: Label
var _back: Button
var _scroll: ScrollContainer
var _focus_revision: int = 0

static func _number(value: Variant) -> bool:
	return typeof(value) == TYPE_FLOAT and is_finite(value) and value >= 0.0

static func _valid_cues(value: Variant) -> bool:
	if not value is Dictionary or value.size() != CUE_KEYS.size(): return false
	for key in value:
		if typeof(key) != TYPE_STRING or key not in CUE_KEYS: return false
	for key in CUE_KEYS:
		if not value.has(key): return false
	if not value.state is String or not value.engine_mode is String or not value.error is String or value.error.length() > 1024: return false
	if value.state == "unavailable":
		if value.engine_mode != "unavailable" or value.error.is_empty(): return false
		for key in ["session_id", "tick", "profile_id", "shaft_radps", "legacy_throttle", "tas_mps", "starved"]:
			if value[key] != null: return false
		return true
	if not value.state in ["live", "paused", "historical"] or not value.session_id is String or value.session_id.is_empty() or not U64.valid(value.tick): return false
	if not value.profile_id is String or not value.profile_id in ["original-interactive-prototype", "original-piston-prop-v1"]: return false
	if value.tas_mps != null and not _number(value.tas_mps): return false
	var complete: bool = value.tas_mps != null
	if value.profile_id == "original-interactive-prototype":
		if value.engine_mode != "legacy" or value.shaft_radps != null or value.starved != null or not _number(value.legacy_throttle) or value.legacy_throttle > 1.0: return false
	else:
		if value.legacy_throttle != null or (value.starved != null and not value.starved is bool): return false
		if value.engine_mode == "unavailable":
			if value.shaft_radps != null: return false
			complete = false
		elif value.engine_mode in ["running", "rotating", "stopped"]:
			if not _number(value.shaft_radps): return false
			if (value.engine_mode == "stopped") != (value.shaft_radps == 0.0): return false
		else: return false
		complete = complete and value.starved != null
	return value.error.is_empty() == complete

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visibility_changed.connect(func():
		if not is_visible_in_tree(): _focus_revision += 1)
	var shade := ColorRect.new()
	shade.color = Color(0.01, 0.025, 0.04, 1.0)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(shade)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for edge in ["left", "right", "top", "bottom"]: margin.add_theme_constant_override("margin_" + edge, 24)
	add_child(margin)
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.follow_focus = true
	margin.add_child(_scroll)
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 10)
	_scroll.add_child(box)
	_label(box, "ORIGINAL SYNTHESIS / AUDIO", 23)
	_label(box, "Engineering cues for the two original synthetic profiles. No measured engine load, installed warnings or C172 acoustic claim. Settings last only for this application instance.", 16)
	_master = _check_box(box, "Master audio", func(value: bool): _request("enabled", value))
	var engine_row := _gain(box, "Engine gain")
	_engine = engine_row.slider
	_engine_percent = engine_row.percent
	_engine.value_changed.connect(func(value: float): _request("engine_gain", value))
	var airflow_row := _gain(box, "Airflow gain")
	_airflow = airflow_row.slider
	_airflow_percent = airflow_row.percent
	_airflow.value_changed.connect(func(value: float): _request("airflow_gain", value))
	_captions = _check_box(box, "Show source captions in this paused panel", func(value: bool): _request("show_panel_captions", value))
	_qualifier = _label(box, "Audio source unavailable", 16)
	_details = _label(box, "", 16)
	_label(box, "Paused summary is not live audio accessibility. Live captions and critical-warning accessibility remain separate work. No preview tone; Back keeps the flight paused.", 16)
	_back = Button.new()
	_back.name = "Back"
	_back.text = "Back · keep this flight paused"
	_back.custom_minimum_size.y = 44
	_back.pressed.connect(func(): dismissed.emit())
	box.add_child(_back)
	var chain: Array[Control] = [_master, _engine, _airflow, _captions, _back]
	for i in chain.size():
		chain[i].focus_neighbor_top = chain[i].get_path_to(chain[(i + chain.size() - 1) % chain.size()])
		chain[i].focus_neighbor_bottom = chain[i].get_path_to(chain[(i + 1) % chain.size()])
		chain[i].focus_next = chain[i].focus_neighbor_bottom
		chain[i].focus_previous = chain[i].focus_neighbor_top
	_refresh()
	hide()

func _label(parent: Node, text: String, pixels: int) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", pixels)
	parent.add_child(label)
	return label

func _check_box(parent: Node, text: String, callback: Callable) -> CheckBox:
	var button := CheckBox.new()
	button.text = text
	button.custom_minimum_size.y = 44
	button.add_theme_font_size_override("font_size", 16)
	button.toggled.connect(callback)
	parent.add_child(button)
	return button

func _gain(parent: Node, title: String) -> Dictionary:
	var row := HBoxContainer.new()
	parent.add_child(row)
	var label := _label(row, title, 16)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var percent := _label(row, "100%", 16)
	percent.custom_minimum_size.x = 60
	percent.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	var slider := HSlider.new()
	slider.min_value = 0.0
	slider.max_value = 1.0
	slider.step = 0.01
	slider.custom_minimum_size.y = 44
	slider.focus_mode = Control.FOCUS_ALL
	parent.add_child(slider)
	return {"slider": slider, "percent": percent}

func set_context(cues: Variant, options: Variant) -> bool:
	if not _valid_cues(cues): return false
	var admitted: Dictionary = Options.validate(options)
	if not admitted.ok: return false
	# Ordinary paused publications repeat every frame. Idempotent updates must
	# not continually restart the pending initial-layout scroll.
	if _cues == cues and _options == admitted.value: return true
	_cues = cues.duplicate(true)
	_options = admitted.value.duplicate(true)
	if is_node_ready():
		_refresh()
		if is_visible_in_tree() and get_viewport().gui_get_focus_owner() == _back: _queue_back_scroll()
	return true

func _can_request() -> bool:
	return not _cues.is_empty() and _cues.state == "paused" and not _options.is_empty()

func _request(key: String, value: Variant) -> void:
	var eligible: bool = _can_request() and is_visible_in_tree()
	var request: Dictionary = _options.duplicate(true)
	if eligible: request[key] = value
	# Controls may update themselves before emitting. Restore admitted settings;
	# only Scene's subsequent set_context acknowledges an accepted request.
	_refresh()
	if eligible and Options.validate(request).ok: options_requested.emit(request.duplicate(true), _cues.session_id)

func _refresh() -> void:
	if not is_instance_valid(_master): return
	var enabled: bool = _can_request()
	_master.disabled = not enabled
	_captions.disabled = not enabled
	_engine.editable = enabled
	_airflow.editable = enabled
	if not _options.is_empty():
		_master.set_pressed_no_signal(_options.enabled)
		_captions.set_pressed_no_signal(_options.show_panel_captions)
		_engine.set_value_no_signal(_options.engine_gain)
		_airflow.set_value_no_signal(_options.airflow_gain)
		_engine_percent.text = "%d%%" % roundi(_options.engine_gain * 100.0)
		_airflow_percent.text = "%d%%" % roundi(_options.airflow_gain * 100.0)
	_details.visible = not _options.is_empty() and _options.show_panel_captions
	if _cues.is_empty():
		_qualifier.text = "Audio source unavailable — no audio playing"
		_details.text = ""
		return
	var state: String = {"paused": "PAUSED — no audio playing", "live": "LIVE source — Audio options require pause", "historical": "RETAINED HISTORICAL — no audio playing", "unavailable": "UNAVAILABLE — no audio playing"}[_cues.state]
	_qualifier.text = state
	if _cues.state != "unavailable":
		_qualifier.text += "\nOriginal engineering profile: %s\nSession: %s · tick %s" % [_cues.profile_id, _cues.session_id, _cues.tick]
	if not _cues.error.is_empty(): _qualifier.text += "\nSource qualification: " + _cues.error
	var engine: String = "Engine unavailable"
	if _cues.engine_mode == "legacy": engine = "Synthetic throttle cue — not measured RPM: " + str(_cues.legacy_throttle)
	elif _cues.engine_mode == "rotating": engine = "ROTATING — cranking or coasting not distinguished · shaft %s rad/s" % str(_cues.shaft_radps)
	elif _cues.engine_mode in ["running", "stopped"]: engine = "%s · actual shaft %s rad/s" % [_cues.engine_mode.to_upper(), str(_cues.shaft_radps)]
	var air: String = "Airflow TAS unavailable" if _cues.tas_mps == null else "Wind-relative TAS: %s m/s" % str(_cues.tas_mps)
	var starvation: String = ""
	if _cues.profile_id == "original-piston-prop-v1": starvation = "\nActual starvation indication: " + ("unavailable" if _cues.starved == null else str(_cues.starved)) + " (information only; no warning sound)"
	_details.text = engine + "\n" + air + starvation

func get_back_button() -> Button:
	return _back

func focus_back() -> void:
	if not is_instance_valid(_back) or not is_visible_in_tree(): return
	_back.grab_focus()
	_queue_back_scroll()

func _queue_back_scroll() -> void:
	_focus_revision += 1
	_settle_back_scroll(_focus_revision)

func _settle_back_scroll(revision: int) -> void:
	# Newly shown/wrapped context changes nested container minima after focus.
	# Wait for layout, then scroll only if this opening still owns Back focus.
	for frame in 3:
		if not is_inside_tree() or not is_visible_in_tree() or revision != _focus_revision: return
		await get_tree().process_frame
	if not is_inside_tree() or not is_visible_in_tree() or revision != _focus_revision: return
	if get_viewport().gui_get_focus_owner() == _back: _scroll.ensure_control_visible(_back)
