extends SceneTree
# Explicitly synthetic reducer/queue checks only. No LocalPlayers, flight,
# archive writer, actual terminal envelope or durable ACK is claimed here.
const Fixture = preload("res://player_tests/archive_link_fixture.gd")
const Options = preload("res://ui/profiles/player_options.gd")
const PLAYER = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
const PRACTICE = "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
const UTC = "2026-10-19T00:00:00Z"
var checks: int = 0
var failures: Array = []
var signals_seen: Array = []
var exits: Array = []

func check(good: bool, name: String) -> void:
	checks += 1
	if not good: failures.append(name)

func source() -> Dictionary:
	return {"session_id":"synthetic-archive-reducer","model_identity":{"id":"original-interactive-prototype","version":"0.1.0-prototype","backend_model":"original-interactive"},"source_variant":"jsbsim-1.3.1-event-aware-coupled-midpoint-local-window-v2","native_source_fingerprint":"a".repeat(64),"prepared_world_sha256":"b".repeat(64),"named_start":"ground-ready","wind_profile":"calm","angular_integration_method":null}

func archive(last: String = "61", digest: String = "c") -> Dictionary:
	return {"type":"ExternalRecordedReview","version":1,"absolute_path":"C:/synthetic/recording.json","payload_sha256":digest.repeat(64),"recording_session_id":"synthetic-archive-reducer","first_tick":"0","last_tick":last,"linked_utc":UTC}

func row(last: String = "0", revision: String = "1", closed: bool = false, linked: Variant = null) -> Dictionary:
	return {"type":"LocalPractice","version":1,"id":PRACTICE,"player_id":PLAYER,"source":source(),"started_utc":UTC,"last_observed_utc":UTC,"first_tick":"0","last_tick":last,"observed_ticks":last,"tick_rate_hz":120,"status":"manually_ended" if closed else "active","end_reason":"user_end" if closed else null,"revision":revision,"creation_sequence":"1","commit_sequence":revision,"archive":linked}

func setup(last: String = "61") -> Variant:
	var c = Fixture.new()
	# Inert nonnull ownership token ONLY. Production native attach guard is unused.
	c._service = RefCounted.new()
	c._status = {"state":"ready","error_code":"","pending":0,"undelivered":0,"writer_alive":true,"resolved_root":null,"store_version":1}
	c._practice = {"id":PRACTICE,"player_id":PLAYER,"source":source(),"first_tick":"0","last_tick":last,"started_utc":UTC,"utc":UTC,"epoch":0,"row":row(),"closed":false,"resolved":false,"inflight":false,"failed":false,"end":null}
	c._practice_cache[PRACTICE] = row()
	c.archive_link_changed.connect(func(id: String, state: Dictionary): signals_seen.append([id,state.duplicate(true)]))
	c.history_exit_resolved.connect(func(epoch: int, saved: bool): exits.append([epoch,saved]))
	return c

func settle(c: Variant, result_row: Dictionary) -> bool:
	var route: Dictionary = c.take()
	return c._settle_practice({"state":"committed","value":{"practice":result_row}},route,true)

func paused_then_observed() -> void:
	var c = setup()
	check(Options.practice_valid(row()) and Options.archive_valid(archive(),source()),"synthetic_shapes_valid")
	check(c.archive_saved(PRACTICE,archive("62")).state == "failed" and c._archive_links.is_empty(),"future_endpoint_refused_before_queue")
	var owned: Dictionary = archive()
	check(c.archive_saved(PRACTICE,owned).state == "pending_endpoint","paused61_retains_until_endpoint_ack")
	owned.payload_sha256 = "d".repeat(64)
	c._drive_practice()
	c._drive_archive_links()
	check(c.captured.is_empty() and c._practice.row.last_tick == "0","no_forced_sub120_observation_or_link")
	check(c.archive_saved(PRACTICE,archive("61","e")).state == "failed","second_file_cannot_replace_unresolved_intent")
	check(c.archive_link_state(PRACTICE).payload_sha256 == "c".repeat(64),"owned_digest_survives_caller_and_second_file")
	c._practice.last_tick = "120"
	c._drive_practice()
	check(c.captured.size() == 1 and c.captured[0].route.kind == "observe_practice" and c.captured[0].payload.last_tick == "120","ordinary_observe120_first")
	c._drive_archive_links()
	check(c.captured.size() == 1,"pending_observation_blocks_link")
	check(settle(c,row("120","2")),"synthetic_observe_ack_accepted")
	# Selection/epoch changes cannot relabel the retained source/player intent.
	c._selected = null
	c._epoch = 9
	c._drive_archive_links()
	var request: Dictionary = c.captured.back()
	check(c.captured.size() == 2 and request.route.kind == "link_archive" and request.payload.expected_revision == "2","link_uses_newest_ack_revision")
	check(request.payload.player_id == PLAYER and Options.exact_equal(request.payload.expected_source,source()) and request.payload.archive.last_tick == "61","original_owner_source_window_retained")
	check(c.archive_link_state(PRACTICE).state == "inflight","admission_is_not_saved_ack")
	c._drive_archive_links()
	check(c.captured.size() == 2,"inflight_link_not_replayed")
	check(settle(c,row("120","3",false,archive())),"synthetic_exact_link_ack_accepted")
	check(c.archive_link_state(PRACTICE).state == "saved" and c._practice_cache[PRACTICE].archive.payload_sha256 == "c".repeat(64),"saved_only_after_matching_row_ack")
	var copied: Dictionary = c.archive_link_state(PRACTICE)
	copied.state = "failed"
	check(c.archive_link_state(PRACTICE).state == "saved","state_getter_is_copied")

func already_inflight() -> void:
	var c = setup("180")
	c._drive_practice()
	check(c.captured.size() == 1 and c.captured[0].payload.last_tick == "180","ordinary_pending_observe_fixture")
	check(c.archive_saved(PRACTICE,archive()).state == "pending_endpoint","save_during_existing_request_retained")
	check(settle(c,row("180","2")),"existing_observation_ack_reduced")
	c._drive_archive_links()
	check(c.captured.size() == 2 and c.captured[1].route.kind == "link_archive","retained_link_drains_after_existing_request")

func closed_case(failure: String = "") -> void:
	var c = setup()
	var before: int = exits.size()
	c.archive_saved(PRACTICE,archive())
	# Inject an explicitly synthetic already-qualified closed lifecycle endpoint.
	# This does NOT exercise flight_closed, native close or actual join.
	c._practice.closed = true
	c._practice.end = {"status":"manually_ended","end_reason":"user_end"}
	c._history_barrier_epoch = 0
	c._drive_practice()
	check(c.captured.size() == 1 and c.captured[0].route.kind == "end_practice" and c.captured[0].payload.last_tick == "61","close_can_ack_actual61_without_forced_observe")
	check(settle(c,row("61","2",true)),"synthetic_end_ack_accepted")
	check(exits.size() == before and c.history_exit_pending(),"end_ack_keeps_pending_link_barrier")
	c._drive_archive_links()
	check(c.captured.size() == 2 and c.captured[1].payload.expected_revision == "2","closed_row_revision_used_for_link")
	if failure.is_empty():
		check(settle(c,row("61","3",true,archive())),"closed_link_ack_reduced")
		check(exits.size() == before + 1 and exits.back() == [0,true] and not c.history_exit_pending(),"barrier_releases_only_after_link_ack")
	else:
		var route: Dictionary = c.take()
		check(c._settle_practice({"state":failure,"error_code":"commit_unknown" if failure == "uncertain" else "io_error"},route,false),"synthetic_failed_terminal_reduced")
		var expected: String = "unknown" if failure == "uncertain" else "failed"
		check(c.archive_link_state(PRACTICE).state == expected and c.history_state().failed and c.history_exit_pending(),"failed_link_retains_explicit_history_barrier")
		c._drive_archive_links()
		c.archive_saved(PRACTICE,archive())
		check(c.captured.size() == 2 and exits.size() == before,"failure_and_same_save_never_auto_replay")
		c.acknowledge_history_not_saved(1,0)
		check(exits.size() == before + 1 and exits.back() == [0,false] and not c.history_exit_pending(),"explicit_closed_not_saved_resolves_barrier")

func prune_ack_case() -> void:
	var c = setup()
	c._status.pending = 1 # Synthetic accepted prune holds the ordinary writer.
	check(c.archive_saved(PRACTICE,archive()).state == "pending_endpoint","prune_queued_intent_retained_before_ack")
	c._practice = {} # Original practice now belongs to the retained old context.
	var route: Dictionary = {"kind":"prune_practice","player_id":PLAYER,"context":{"ids":[PRACTICE]}}
	check(not c._settle_extra({"value":{"deleted_ids":[]}},route,true) and c.archive_link_state(PRACTICE).state == "pending_endpoint" and c._practice_cache.has(PRACTICE),"malformed_prune_ack_cannot_fail_intent")
	check(c._settle_extra({"value":null},route,false) and c.archive_link_state(PRACTICE).state == "pending_endpoint","failed_prune_does_not_establish_deletion")
	check(c._settle_extra({"value":{"deleted_ids":[PRACTICE]}},route,true),"synthetic_prune_ack_reduced")
	var state: Dictionary = c.archive_link_state(PRACTICE)
	check(state.state == "failed" and not state.error.is_empty() and state.payload_sha256 == "c".repeat(64) and not c._practice_cache.has(PRACTICE),"unsent_pruned_intent_explicit_failed_original_digest")
	check(c._archive_links[PRACTICE].player_id == PLAYER and Options.exact_equal(c._archive_links[PRACTICE].source,source()),"prune_does_not_rebind_original_context")
	c._status.pending = 0
	c._drive_archive_links()
	check(c.captured.is_empty() and c.history_state().failed and c.history_exit_pending(),"pruned_intent_no_submission_or_silent_resolution")
	var before: int = exits.size()
	c._history_barrier_epoch = 0
	c.acknowledge_history_not_saved(1,0)
	check(exits.size() == before + 1 and exits.back() == [0,false] and not c.history_exit_pending(),"pruned_intent_explicit_not_saved_escape")

func prune_preserves_admitted_link() -> void:
	var c = setup("120")
	c._practice_cache[PRACTICE] = row("120","2")
	check(c.archive_saved(PRACTICE,archive()).state == "inflight" and c.captured.size() == 1,"prune_admitted_link_fixture")
	var route: Dictionary = {"kind":"prune_practice","player_id":PLAYER,"context":{"ids":[PRACTICE]}}
	check(c._settle_extra({"value":{"deleted_ids":[PRACTICE]}},route,true) and c.archive_link_state(PRACTICE).state == "inflight" and c._requests.size() == 1,"prune_ack_preserves_accepted_route_to_drain")
	var link: Dictionary = c.take()
	check(c._settle_practice({"state":"failed","error_code":"not_found"},link,false) and c.archive_link_state(PRACTICE).state == "failed" and c._requests.is_empty(),"accepted_link_uses_own_terminal_reduction")
	c._drive_archive_links()
	check(c.captured.size() == 1,"pruned_admitted_link_never_replayed")

func _initialize() -> void:
	paused_then_observed()
	already_inflight()
	closed_case()
	closed_case("failed")
	closed_case("uncertain")
	prune_ack_case()
	prune_preserves_admitted_link()
	check(not signals_seen.is_empty() and signals_seen[0][1].payload_sha256 == "c".repeat(64),"state_signals_include_original_digest")
	print(JSON.stringify({"kind":"synthetic-archive-link-reducer","checks":checks,"failures":failures,"actual_persistence_exercised":false,"actual_flight_exercised":false}))
	quit(0 if failures.is_empty() else 1)
