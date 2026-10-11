extends RefCounted
# Original MIT. Synthetic closed cue views; actual headless Control layout/events.
const AudioPanel = preload("res://ui/audio/audio_panel.gd")
var _checks: int = 0
var _failures: Array[String] = []
var _requests: Array = []
var _dismissals: int = 0

func check(value: bool, label: String) -> void:
	_checks += 1
	if not value: _failures.append(label)

static func cues() -> Dictionary:
	return {"session_id": "synthetic-panel-session", "tick": "18446744073709551615", "profile_id": "original-piston-prop-v1", "state": "paused", "engine_mode": "running", "shaft_radps": 100.0, "legacy_throttle": null, "tas_mps": 40.0, "starved": false, "error": ""}

static func options() -> Dictionary:
	return {"enabled": true, "engine_gain": 1.0, "airflow_gain": 1.0, "show_panel_captions": true}

func _settle(host: Node) -> void:
	for i in 4: await host.get_tree().process_frame

func _snapshot(panel: Control) -> PackedByteArray:
	return var_to_bytes([panel._cues, panel._options, panel._qualifier.text, panel._details.text, panel._details.visible, panel._master.button_pressed, panel._engine.value, panel._airflow.value, panel._captions.button_pressed])

func _reject(panel: Control, cue: Variant, opts: Variant, name: String) -> void:
	var before := _snapshot(panel)
	var count: int = _requests.size()
	check(not panel.set_context(cue, opts) and _snapshot(panel) == before and _requests.size() == count, "atomic_context_reject_" + name)

func run(host: Node) -> Dictionary:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(960, 540)
	viewport.gui_disable_input = false
	host.add_child(viewport)
	var panel = AudioPanel.new()
	# Admission before _ready must be safe and later displayed.
	check(panel.set_context(cues(), options()), "context_before_ready")
	viewport.add_child(panel)
	panel.show()
	panel.options_requested.connect(func(value: Dictionary, session: String): _requests.append({"options": value.duplicate(true), "session": session}))
	panel.dismissed.connect(func(): _dismissals += 1)
	await _settle(host)
	check(panel.size == Vector2(960, 540), "minimum_960_full_viewport")
	check(panel.get_child(0) is ColorRect and panel.get_child(0).color.a == 1.0, "opaque_modal")
	check(panel._scroll.get_global_rect() == Rect2(24, 24, 912, 492), "wind_pattern_24px_scroll_margins")
	check(panel._scroll.horizontal_scroll_mode == ScrollContainer.SCROLL_MODE_DISABLED and panel._scroll.follow_focus, "vertical_scroll_follows_keyboard_focus")
	check(panel._qualifier.text.contains("PAUSED — no audio playing") and panel._details.text.contains("RUNNING") and panel._details.text.contains("100.0 rad/s") and panel._details.text.contains("40.0 m/s"), "paused_actual_engineering_facts_not_live_audio")
	check(panel._qualifier.text.contains("18446744073709551615"), "full_decimal_tick_not_float_rounded")
	check(panel._engine_percent.text == "100%" and panel._airflow_percent.text == "100%", "gain_percentages")
	var source: Dictionary = cues()
	var opts: Dictionary = options()
	check(panel.set_context(source, opts), "valid_context")
	source.session_id = "caller-mutated"
	opts.engine_gain = 0.0
	check(panel._cues.session_id == "synthetic-panel-session" and panel._options.engine_gain == 1.0, "context_inputs_copied")
	var before := _snapshot(panel)
	check(panel.set_context(cues(), options()) and _snapshot(panel) == before, "identical_context_idempotent")
	for key in cues():
		var bad: Dictionary = cues(); bad.erase(key)
		_reject(panel, bad, options(), "cue_missing_" + key)
	var extra: Dictionary = cues(); extra["unexpected"] = false
	_reject(panel, extra, options(), "cue_extra")
	for bad in [null, [], "paused", true, 1]: _reject(panel, bad, options(), "cue_not_dict_" + str(bad))
	var cases: Array = [
		["session_id", null], ["session_id", ""], ["tick", "01"], ["tick", "18446744073709551616"], ["tick", 1.0],
		["profile_id", "C172"], ["profile_id", 1], ["state", "ready"], ["state", false], ["engine_mode", "cranking"],
		["shaft_radps", -1.0], ["shaft_radps", 100], ["shaft_radps", true], ["shaft_radps", NAN], ["shaft_radps", INF],
		["shaft_radps", 0.0], ["legacy_throttle", 0.5], ["tas_mps", -1.0], ["tas_mps", 1], ["tas_mps", NAN], ["tas_mps", INF],
		["starved", 0], ["starved", "false"], ["error", false], ["error", "x".repeat(1025)], ["error", "spurious error"]]
	for item in cases:
		var bad: Dictionary = cues(); bad[item[0]] = item[1]
		_reject(panel, bad, options(), "cue_type_semantics_" + str(item))
	for key in options():
		var bad: Dictionary = options(); bad.erase(key)
		_reject(panel, cues(), bad, "option_missing_" + key)
	extra = options(); extra["unexpected"] = 0
	_reject(panel, cues(), extra, "option_extra")
	for bad in [null, [], false, "options"]: _reject(panel, cues(), bad, "options_not_dict_" + str(bad))
	for item in [["enabled", 1], ["show_panel_captions", 0], ["engine_gain", 1], ["airflow_gain", true], ["engine_gain", -0.01], ["airflow_gain", 1.01], ["engine_gain", NAN], ["airflow_gain", INF]]:
		var bad: Dictionary = options(); bad[item[0]] = item[1]
		_reject(panel, cues(), bad, "option_type_range_" + str(item))
	# Native widgets emit requests but cannot optimistically commit them.
	panel._master.button_pressed = false
	check(_requests.size() == 1 and _requests[-1].session == cues().session_id and not _requests[-1].options.enabled and panel._master.button_pressed and panel._options == options(), "master_single_copied_request_restore_until_scene_ack")
	var accepted: Dictionary = _requests[-1].options.duplicate(true)
	_requests[-1].options.engine_gain = 0.0
	check(panel._options == options(), "emitted_request_is_owned")
	check(panel.set_context(cues(), accepted) and not panel._master.button_pressed and panel._details.visible and panel._qualifier.text.contains("PAUSED"), "scene_ack_master_mute_does_not_hide_captions")
	panel._engine.value = 0.25
	check(_requests[-1].options.engine_gain == 0.25 and _requests[-1].options.airflow_gain == 1.0 and panel._engine.value == 1.0, "engine_gain_request_independent_restore")
	accepted = _requests[-1].options.duplicate(true); panel.set_context(cues(), accepted)
	check(panel._engine_percent.text == "25%" and panel._airflow_percent.text == "100%", "accepted_percentages_independent")
	panel._airflow.value = 0.0
	check(_requests[-1].options.airflow_gain == 0.0 and _requests[-1].options.engine_gain == 0.25, "airflow_endpoint_request")
	accepted = _requests[-1].options.duplicate(true); panel.set_context(cues(), accepted)
	panel._captions.button_pressed = false
	check(not _requests[-1].options.show_panel_captions and panel._details.visible, "caption_request_waits_for_scene")
	accepted = _requests[-1].options.duplicate(true); panel.set_context(cues(), accepted)
	check(not panel._details.visible and panel._qualifier.visible and panel._qualifier.text.contains("Original engineering profile"), "mandatory_qualification_stays_without_optional_details")
	# Valid partial source is not whole-source invalidity and never invents alarms.
	for missing in ["tas_mps", "starved", "shaft_radps"]:
		var partial: Dictionary = cues(); partial[missing] = null; partial.error = "Actual " + missing + " unavailable"
		if missing == "shaft_radps": partial.engine_mode = "unavailable"
		check(panel.set_context(partial, options()), "qualified_partial_" + missing)
		check(panel._qualifier.text.contains(partial.error) and panel._qualifier.text.contains("PAUSED"), "partial_full_reason_" + missing)
	check(panel._details.text.contains("Engine unavailable") and panel._details.text.contains("40.0 m/s"), "engine_missing_does_not_hide_airflow")
	for mode in ["rotating", "stopped"]:
		var value: Dictionary = cues(); value.engine_mode = mode
		if mode == "stopped": value.shaft_radps = 0.0
		check(panel.set_context(value, options()) and panel._details.text.contains(mode.to_upper()), "actual_mode_" + mode)
		if mode == "rotating": check(panel._details.text.contains("cranking or coasting not distinguished"), "no_cranking_inference")
	var legacy: Dictionary = cues()
	legacy.profile_id = "original-interactive-prototype"; legacy.engine_mode = "legacy"; legacy.shaft_radps = null; legacy.legacy_throttle = 0.75; legacy.starved = null
	check(panel.set_context(legacy, options()) and panel._details.text.contains("Synthetic throttle cue — not measured RPM"), "honest_legacy_qualifier")
	var unavailable: Dictionary = {"session_id": null, "tick": null, "profile_id": null, "state": "unavailable", "engine_mode": "unavailable", "shaft_radps": null, "legacy_throttle": null, "tas_mps": null, "starved": null, "error": "Actual source unavailable"}
	for state in ["live", "historical", "unavailable"]:
		var value: Dictionary = unavailable.duplicate(true) if state == "unavailable" else cues()
		value.state = state
		check(panel.set_context(value, options()), "display_valid_nonpaused_" + state)
		var count: int = _requests.size()
		panel._request("enabled", false)
		check(_requests.size() == count and panel._master.disabled and not panel._engine.editable and panel._captions.disabled, "nonpaused_cannot_request_" + state)
		check(not panel._qualifier.text.contains("PAUSED"), "nonpaused_never_relabelled_paused_" + state)
	check(not panel._qualifier.text.contains(cues().session_id) and not panel._details.text.contains("100.0"), "explicit_unavailable_clears_old_identity_values")
	panel.set_context(cues(), options()); panel.hide()
	var count: int = _requests.size(); panel._request("enabled", false)
	check(_requests.size() == count, "hidden_panel_cannot_request")
	panel.show()
	# Real headless container/font/scroll/focus bounds, not claimed GPU pixels.
	var long_cues: Dictionary = cues()
	long_cues.tas_mps = null
	long_cues.error = "Source error: " + "bounded complete diagnostic ".repeat(35)
	check(long_cues.error.length() <= 1024 and panel.set_context(long_cues, options()), "long_error_admitted_complete")
	await _settle(host)
	check(panel._qualifier.text.ends_with(long_cues.error) and panel._qualifier.autowrap_mode == TextServer.AUTOWRAP_WORD_SMART, "full_reason_wrapped_not_ellipsized")
	check(panel._scroll.get_v_scroll_bar().max_value > panel._scroll.size.y, "long_context_actually_requires_scroll")
	var labels: Array[Label] = []
	_collect_labels(panel, labels)
	for label in labels:
		if not label.visible: continue
		var font: Font = label.get_theme_font("font")
		var pixels: int = label.get_theme_font_size("font_size")
		check(pixels >= 16 and label.size.x <= 912.0 and label.size.x > 0.0, "readable_label_width_font_" + label.text.left(22))
		check(label.size.y + 0.01 >= label.get_line_count() * font.get_height(pixels), "actual_all_wrapped_lines_have_height_" + label.text.left(22))
	for control in [panel._master, panel._engine, panel._airflow, panel._captions, panel._back]:
		check(control.size.y >= 44.0 and control.focus_mode == Control.FOCUS_ALL and not control.focus_next.is_empty(), "actual_hit_focus_" + str(control.get_class()))
	viewport.notify_mouse_entered()
	panel._master.grab_focus()
	await _settle(host)
	check(panel._scroll.get_global_rect().encloses(panel._master.get_global_rect()), "focus_scroll_brings_master_inside_view")
	var native_before := _snapshot(panel)
	var native_count: int = _requests.size()
	var master_motion := InputEventMouseMotion.new()
	master_motion.position = panel._master.get_global_rect().get_center()
	viewport.push_input(master_motion, true)
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = master_motion.position; event.button_index = MOUSE_BUTTON_LEFT; event.pressed = pressed
		viewport.push_input(event, true)
	await _settle(host)
	check(_requests.size() == native_count + 1 and not _requests[-1].options.enabled and _requests[-1].session == cues().session_id, "actual_master_mouse_hit_one_source_bound_request")
	check(_snapshot(panel) == native_before, "actual_master_hit_not_optimistically_committed")
	panel._engine.grab_focus()
	await _settle(host)
	native_count = _requests.size()
	for pressed in [true, false]:
		var key := InputEventKey.new()
		key.keycode = KEY_LEFT; key.physical_keycode = KEY_LEFT; key.pressed = pressed
		viewport.push_input(key, true)
	await _settle(host)
	check(_requests.size() == native_count + 1 and _requests[-1].options.engine_gain < 1.0 and _requests[-1].options.airflow_gain == 1.0, "actual_gain_keyboard_request_independent")
	check(_snapshot(panel) == native_before, "actual_gain_key_not_optimistically_committed")
	count = _requests.size()
	panel.focus_back()
	await _settle(host)
	check(viewport.gui_get_focus_owner() == panel.get_back_button(), "back_actual_keyboard_focus")
	check(panel._scroll.get_global_rect().encloses(panel._back.get_global_rect()), "focus_scroll_brings_back_fully_inside_view")
	var truth := _snapshot(panel)
	var motion := InputEventMouseMotion.new()
	motion.position = panel._back.get_global_rect().get_center()
	viewport.push_input(motion, true)
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = motion.position; event.button_index = MOUSE_BUTTON_LEFT; event.pressed = pressed
		viewport.push_input(event, true)
	await _settle(host)
	check(_dismissals == 1 and _requests.size() == count, "actual_back_hit_only_dismisses_no_options_resume")
	check(_snapshot(panel) == truth, "back_preserves_all_admitted_source_and_settings")
	viewport.notify_mouse_exited()
	viewport.queue_free()
	await host.get_tree().process_frame
	await _fresh_open_regression(host)
	return {"passed": _failures.is_empty(), "checks": _checks, "failures": _failures.duplicate(), "scope": "Synthetic copied cue/options, actual 960x540 headless GUI container/font/focus/hit/scroll checks; no native/GPU/audio-device or Scene lifecycle qualification"}

func _collect_labels(node: Node, labels: Array[Label]) -> void:
	if node is Label: labels.append(node)
	for child in node.get_children(): _collect_labels(child, labels)

func _fresh_open_regression(host: Node) -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(960, 540)
	viewport.gui_disable_input = false
	host.add_child(viewport)
	var panel = AudioPanel.new()
	viewport.add_child(panel)
	# Match Scene's same-frame context/show/focus order on a fresh hidden page.
	check(not panel.visible and panel.set_context(cues(), options()), "fresh_hidden_context")
	panel.show()
	panel.focus_back()
	for frame in 4:
		panel.set_context(cues(), options())
		await host.get_tree().process_frame
	check(viewport.gui_get_focus_owner() == panel._back and panel._scroll.get_global_rect().encloses(panel._back.get_global_rect()), "fresh_show_focus_back_layout_scroll_visible")
	var before := _snapshot(panel)
	var dismissed: Array = []
	panel.dismissed.connect(func(): dismissed.append(true))
	viewport.notify_mouse_entered()
	var motion := InputEventMouseMotion.new()
	motion.position = panel._back.get_global_rect().get_center()
	viewport.push_input(motion, true)
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = motion.position; event.button_index = MOUSE_BUTTON_LEFT; event.pressed = pressed
		viewport.push_input(event, true)
	check(dismissed == [true] and _snapshot(panel) == before, "fresh_show_scrolled_back_actual_hit_no_context_mutation")
	var changed: Dictionary = cues()
	changed.tas_mps = null
	changed.error = "A newly expanded complete source diagnostic. ".repeat(22)
	check(panel.set_context(changed, options()), "focused_back_source_update")
	await _settle(host)
	check(panel._qualifier.text.ends_with(changed.error) and panel._scroll.get_global_rect().encloses(panel._back.get_global_rect()), "source_update_scrolls_focused_back_after_wrap")
	# Retire before deferred work finishes; a menu button now owns focus.
	panel.focus_back()
	panel.hide()
	var menu_button := Button.new()
	menu_button.text = "Menu Audio"
	viewport.add_child(menu_button)
	menu_button.grab_focus()
	await _settle(host)
	check(viewport.gui_get_focus_owner() == menu_button, "retired_hidden_deferred_scroll_never_steals_focus")
	panel.show()
	panel.focus_back()
	panel._master.grab_focus()
	await _settle(host)
	check(viewport.gui_get_focus_owner() == panel._master, "user_navigation_beats_pending_back_scroll")
	panel.hide()
	menu_button.grab_focus()
	panel.focus_back()
	await _settle(host)
	check(viewport.gui_get_focus_owner() == menu_button, "hidden_focus_back_is_inert")
	viewport.notify_mouse_exited()
	viewport.queue_free()
	await host.get_tree().process_frame
