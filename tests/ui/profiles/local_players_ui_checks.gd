extends RefCounted
# Original MIT. Synthetic presentation and pure-options checks only.
# No LocalPlayers object is created, no native Status is claimed, and no paths
# selected below are opened. Actual persistence/relaunch proof is separate.
const Options = preload("res://ui/profiles/player_options.gd")
const Players = preload("res://ui/profiles/players_panel.gd")
const NamePanel = preload("res://ui/profiles/player_name_panel.gd")
const History = preload("res://ui/history/practice_panel.gd")
const Details = preload("res://ui/history/practice_details.gd")
const ExportPanel = preload("res://ui/history/player_export_panel.gd")
const Recovery = preload("res://ui/history/recovery_panel.gd")
const Controls = preload("res://ui/controls/controls_panel.gd")
const Audio = preload("res://ui/audio/audio_panel.gd")
const A = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
const B = "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
const UTC = "2026-10-12T12:00:00Z"

var _events: Array = []

func _player() -> Dictionary:
	return {"type":"LocalPlayer", "version":1, "id":A, "name":"Alpha", "created_utc":UTC, "updated_utc":UTC, "revision":"1"}

func _pair() -> Dictionary:
	return {"player":_player(), "preferences":{"type":"LocalPlayerPreferences", "version":1, "player_id":A, "revision":"1", "legacy_input":null, "piston_input":null, "audio":{"enabled":true, "engine_gain":1.0, "airflow_gain":1.0, "show_panel_captions":true}}}

func _status(state: String = "ready") -> Dictionary:
	# This is a labelled fixture passed to a page, never to the controller.
	return {"state":state, "error_code":"", "pending":0, "undelivered":0, "writer_alive":state == "ready", "resolved_root":null, "store_version":1}

func _source() -> Dictionary:
	return {"session_id":"synthetic-ui-fixture", "model_identity":{"id":"original-interactive-prototype", "version":"0.1.0-prototype", "backend_model":"original-interactive"}, "source_variant":"jsbsim-1.3.1-event-aware-coupled-midpoint-local-window-v2", "native_source_fingerprint":"a".repeat(64), "prepared_world_sha256":"b".repeat(64), "named_start":"ground-ready", "wind_profile":"calm", "angular_integration_method":null}

func _practice(summary: bool = false) -> Dictionary:
	return {"type":"LocalPractice", "version":1, "id":B, "player_id":A, "source":_source(), "started_utc":UTC, "last_observed_utc":UTC, "first_tick":"10", "last_tick":"130", "observed_ticks":"120", "tick_rate_hz":120, "status":"manually_ended", "end_reason":"user_end", "revision":"2", "creation_sequence":"1", "commit_sequence":"2", "archive":{"linked":false} if summary else null}

func _signal2(opening: int, epoch: int) -> void:
	_events.append([opening, epoch])

func _signal3(opening: int, epoch: int, value: Variant) -> void:
	_events.append([opening, epoch, value.duplicate(true) if value is Array or value is Dictionary else value])

func _mount(host: Node, script: Script) -> Control:
	var panel: Control = script.new()
	host.add_child(panel)
	return panel

func _release(panel: Control) -> void:
	panel.hide()
	panel.get_parent().remove_child(panel)
	panel.free()

func _escape(panel: Control) -> void:
	var key := InputEventKey.new()
	key.keycode = KEY_ESCAPE
	key.pressed = true
	if panel.get_script() == NamePanel:
		panel._input(key)
	else:
		panel._unhandled_key_input(key)

func _options(host: Node) -> void:
	var positive := PackedByteArray([0,0,0,0,0,0,0,0])
	var negative := PackedByteArray([0,0,0,0,0,0,0,128])
	var plus: float = positive.decode_double(0)
	var minus: float = negative.decode_double(0)
	host.check(not Options.exact_equal(plus, minus), "player_options_binary64_signed_zero_distinct")
	host.check(not Options.exact_equal(1, 1.0) and not Options.exact_equal(false, 0), "player_options_scalar_types_distinct")
	host.check(not Options.exact_equal({"x":[1.0,minus]}, {"x":[1.0,plus]}), "player_options_nested_binary64_distinct")
	host.check(Options.exact_equal({"b":[true,null,"1"],"a":1.0}, {"a":1.0,"b":[true,null,"1"]}), "player_options_dictionary_order_not_content")
	var seed: Dictionary = Options.default_seed()
	host.check(seed.legacy_input == null and seed.piston_input == null and typeof(seed.audio.engine_gain) == TYPE_FLOAT, "player_options_guest_null_slots_and_float_defaults")
	seed.audio.engine_gain = minus
	var admitted: Dictionary = Options.validate_seed(seed)
	host.check(admitted.ok and Options.exact_equal(admitted.value.audio.engine_gain, minus), "player_options_validator_preserves_signed_zero")
	seed.audio.engine_gain = 0.5
	host.check(Options.exact_equal(admitted.value.audio.engine_gain, minus), "player_options_validation_owns_recursive_copy")
	for malformed in [{}, {"legacy_input":null,"piston_input":null,"audio":null}, {"legacy_input":null,"piston_input":null,"audio":{"enabled":true,"engine_gain":1,"airflow_gain":1.0,"show_panel_captions":true}}]:
		host.check(not Options.validate_seed(malformed).ok, "player_options_rejects_invalid_shape_and_scalar_types")
	var pair: Dictionary = _pair()
	host.check(Options.validate_pair(pair).ok, "player_options_accepts_independent_fixture_pair")
	for field in ["player_id", "revision"]:
		var wrong: Dictionary = pair.duplicate(true)
		wrong.preferences[field] = B if field == "player_id" else "2"
		host.check(not Options.validate_pair(wrong).ok, "player_options_pair_rejects_" + field + "_mismatch")
	host.check(Options.next_u64("999") == "1000" and Options.next_u64("18446744073709551615") == null, "player_options_u64_increment_exact_no_signed_wrap")
	host.check(Options.utc_valid("2024-02-29T23:59:59Z") and not Options.utc_valid("2025-02-29T23:59:59Z"), "player_options_utc_leap_day")
	host.check(Options.name_valid("Pilot 🛩") and not Options.name_valid(" Alpha") and not Options.name_valid("Alpha\u00a0"), "player_options_names_unicode_and_edge_whitespace")
	host.check(Options.practice_valid(_practice()) and Options.practice_valid(_practice(true), true), "player_options_practice_independent_fixture_shape")
	var inconsistent: Dictionary = _practice()
	inconsistent.observed_ticks = "121"
	host.check(not Options.practice_valid(inconsistent), "player_options_practice_interval_mismatch_rejected")

func _players(host: Node) -> void:
	var panel: Control = _mount(host, Players)
	panel.player_chosen.connect(_signal3)
	panel.guest_chosen.connect(_signal2)
	panel.dismissed.connect(_signal2)
	var rows: Array = [{"id":A,"name":"Alpha","revision":"1"}, {"id":B,"name":"Bravo","revision":"1"}]
	host.check(not panel.present(0,0,rows,A,_status()), "players_rejects_nonpositive_opening")
	host.check(panel.present(1,0,rows,A,_status()), "players_presents_synthetic_ready_list")
	host.check(panel.get_viewport().gui_get_focus_owner() == panel._cancel, "players_initial_cancel_focus")
	rows[0].name = "Changed outside"
	host.check(panel._current.text == "Current player: Alpha" and panel._players[0].name == "Alpha", "players_copies_list_selected_name")
	_events.clear()
	panel._choice_buttons[1].pressed.emit()
	host.check(_events == [[1,0,B]] and panel._current.text == "Current player: Alpha", "players_choice_intent_does_not_claim_selection")
	var prior_callback: Callable = panel._choice_buttons[1].pressed.get_connections()[0].callable
	panel.set_feedback(99,0,"stale",true)
	host.check(panel._feedback.text.is_empty() and not panel._busy, "players_stale_feedback_ignored")
	panel.set_feedback(1,0,"x".repeat(1200),true)
	host.check(panel._feedback.text.length() == 1024 and panel._choice_buttons[1].disabled and not panel._cancel.disabled, "players_busy_feedback_bounded_cancel_usable")
	_events.clear()
	panel._choice_buttons[1].pressed.emit()
	panel._cancel.pressed.emit()
	host.check(_events == [[1,0]], "players_busy_blocks_choice_preserves_cancel")
	panel.retire()
	_events.clear()
	prior_callback.call()
	host.check(_events.is_empty(), "players_retired_callback_has_no_effect")
	host.check(panel.present(2,1,[{"id":A,"name":"Alpha","revision":"1"}],null,_status("unavailable")), "players_unavailable_still_presents_guest")
	panel._guest.pressed.emit()
	host.check(_events == [[2,1]] and panel._create.disabled, "players_unavailable_guest_intent_without_storage_create")
	panel.hide()
	_events.clear()
	panel._guest.pressed.emit()
	host.check(_events.is_empty(), "players_hidden_retires_handlers")
	_release(panel)

func _name_panel(host: Node) -> void:
	var panel: Control = _mount(host, NamePanel)
	panel.name_confirmed.connect(_signal3)
	panel.dismissed.connect(_signal2)
	host.check(panel.present(3,1,"",false), "player_name_empty_create_presents")
	host.check(panel._confirm.disabled and panel.get_viewport().gui_get_focus_owner() == panel._cancel, "player_name_empty_blocks_submit_default_cancel")
	_events.clear()
	panel._name.text = " Alpha"
	panel._name.text_changed.emit(panel._name.text)
	panel._name.text_submitted.emit(panel._name.text)
	host.check(_events.is_empty() and panel._confirm.disabled, "player_name_invalid_enter_no_intent")
	panel._name.text = "Alpha"
	panel._name.text_changed.emit(panel._name.text)
	panel._name.text_submitted.emit(panel._name.text)
	host.check(_events == [[3,1,"Alpha"]], "player_name_enter_emits_owned_valid_name")
	panel.set_feedback(3,1,"Saving…",true)
	_events.clear()
	panel._confirm.pressed.emit()
	_escape(panel)
	host.check(_events == [[3,1]] and not panel._cancel.disabled, "player_name_busy_escape_remains_cancel")
	panel.retire()
	_events.clear()
	panel._name.text_submitted.emit("Other")
	host.check(_events.is_empty() and panel._name.text.is_empty(), "player_name_retirement_clears_private_draft_handlers")
	_release(panel)

func _history(host: Node) -> void:
	var panel: Control = _mount(host, History)
	panel.prune_requested.connect(_signal3)
	panel.next_requested.connect(_signal3)
	panel.dismissed.connect(_signal2)
	var page: Dictionary = {"practice":[_practice(true)],"next_before_creation_sequence":"1"}
	host.check(panel.present(4,1,A,page), "practice_list_presents_synthetic_interval")
	host.check(panel._duration("18446744073709551615") == "153722867280912930.125 s", "practice_list_u64_duration_without_signed_or_float_loss")
	_events.clear()
	panel._checks[0].button_pressed = true
	panel._prune.pressed.emit()
	host.check(_events.is_empty() and panel._confirmation.visible and panel.get_viewport().gui_get_focus_owner() == panel._keep, "practice_remove_requires_confirmation_default_keep")
	_escape(panel)
	host.check(not panel._confirmation.visible and _events.is_empty(), "practice_escape_cancels_removal_only")
	panel._prune.pressed.emit()
	panel._confirm.pressed.emit()
	host.check(_events == [[4,1,[B]]], "practice_remove_emits_explicit_selected_ids_only")
	panel.set_feedback(4,1,"Removing…",true)
	_events.clear()
	panel._confirm.pressed.emit()
	panel._cancel.pressed.emit()
	host.check(_events == [[4,1]], "practice_busy_blocks_remove_preserves_dismiss")
	panel.retire()
	_events.clear()
	panel._next.pressed.emit()
	host.check(_events.is_empty(), "practice_retired_page_no_next")
	_release(panel)
	var details: Control = _mount(host, Details)
	details.archive_open_requested.connect(_signal3)
	host.check(details.present(5,1,_practice()) and details._open.disabled, "practice_details_unlinked_does_not_offer_open")
	_release(details)

func _export(host: Node) -> void:
	var panel: Control = _mount(host, ExportPanel)
	panel.export_requested.connect(_signal3)
	host.check(panel.present(6,1,_player(),null) and panel._export.disabled, "player_export_requires_explicit_folder")
	# Synthetic path signal only: no FileDialog or file I/O is executed here.
	panel._folder_selected("C:/synthetic-ui-fixture",6,1,panel._generation)
	_events.clear()
	panel._export.pressed.emit()
	host.check(_events == [[6,1,"C:/synthetic-ui-fixture/player-aaaaaaaa.json"]], "player_export_emits_new_target_intent_only")
	for bad in ["../escape.json","CON:","trailing.","bad/name.json"]:
		host.check(not panel._valid_filename(bad), "player_export_rejects_unsafe_filename")
	panel.set_feedback(6,1,"Export pending",true)
	_events.clear()
	panel._export.pressed.emit()
	host.check(_events.is_empty() and not panel._cancel.disabled and not panel._receipt_label.visible, "player_export_pending_never_claims_receipt")
	panel.retire()
	panel._folder_selected("C:/stale",6,1,panel._generation)
	host.check(panel._folder.is_empty(), "player_export_retired_dialog_cannot_restore_target")
	_release(panel)

func _recovery(host: Node) -> void:
	var panel: Control = _mount(host, Recovery)
	panel.delete_requested.connect(_signal3)
	var copies: Array = [{"id":B,"state":"partial","created_utc":null,"bytes":0,"manifest_sha256":null}]
	host.check(panel.present(7,1,copies,null), "recovery_partial_summary_presents")
	copies[0].id = A
	_events.clear()
	panel._checks[0].button_pressed = true
	panel._delete.pressed.emit()
	host.check(_events.is_empty() and panel.get_viewport().gui_get_focus_owner() == panel._keep, "recovery_delete_requires_confirmation_default_keep")
	panel._confirm.pressed.emit()
	host.check(_events == [[7,1,[B]]], "recovery_delete_uses_owned_known_snapshot_id")
	panel.retire()
	_events.clear()
	panel._confirm.pressed.emit()
	host.check(_events.is_empty(), "recovery_retired_confirmation_no_intent")
	_release(panel)

func _save_panels(host: Node) -> void:
	for script: Script in [Controls, Audio]:
		var panel: Control = _mount(host, script)
		panel.show()
		panel.save_player_requested.connect(_signal2)
		panel.set_player_save_state(8,1,_player(),true,false,false)
		host.check(not panel._player_save_button.disabled, "player_save_dirty_snapshot_enabled")
		var old_callback: Callable = panel._player_save_callback
		_events.clear()
		panel._player_save_button.pressed.emit()
		host.check(_events == [[8,1]], "player_save_emits_only_opening_epoch")
		panel.set_player_save_state(8,1,_player(),true,true,false)
		_events.clear()
		panel._player_save_button.pressed.emit()
		host.check(panel._player_save_button.disabled and _events.is_empty(), "player_save_pending_no_second_submit")
		panel.set_player_save_state(8,1,_player(),true,false,true)
		host.check(panel._player_save_button.disabled and panel._player_save_label.text.contains("unknown"), "player_save_unknown_is_not_saved")
		panel.set_player_save_state(8,1,_player(),false,false,false)
		host.check(panel._player_save_button.disabled, "player_save_clean_no_redundant_submit")
		panel.hide()
		panel.show()
		panel.set_player_save_state(8,1,_player(),true,false,false)
		_events.clear()
		old_callback.call()
		host.check(_events.is_empty() and panel._player_save_button.disabled, "player_save_hidden_token_cannot_be_reactivated")
		panel.set_player_save_state(9,2,null,false,false,false)
		panel._player_save_button.pressed.emit()
		host.check(_events == [[9,2]] and panel._player_save_button.text.contains("Create"), "player_save_guest_requests_chooser_without_claiming_save")
		panel.set_player_save_state(8,1,_player(),true,false,false)
		host.check(panel._player_save_player == null and panel._player_save_opening == 9, "player_save_old_context_cannot_replace_guest")
		_release(panel)

func run(host: Node) -> Dictionary:
	_options(host)
	_players(host)
	_name_panel(host)
	_history(host)
	_export(host)
	_recovery(host)
	_save_panels(host)
	return {"scope":"synthetic_presentation_and_pure_options", "native_persistence_exercised":false}
