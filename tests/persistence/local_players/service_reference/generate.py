"""Original MIT. Declarative preconsumer expectations; no service/DB imports.

Only --check is supported. The frozen expected file is never overwritten.
Fixture descriptors are not a production interchange format.
"""
import argparse
import copy
import json
import struct
from pathlib import Path

HERE = Path(__file__).resolve().parent
MAX = "18446744073709551615"
A, B, P, Q = "a" * 32, "b" * 32, "c" * 32, "d" * 32
UTC, LATER = "2026-10-11T12:00:00Z", "2026-10-11T12:01:00Z"


def bound(name, grammar="lowerhex32"):
    return {"$fixture_binding": name, "actual_type": "STRING", "grammar": grammar}


def typed(value):
    if isinstance(value, dict) and "$fixture_binding" in value:
        return value
    if value is None:
        return {"type": "NIL"}
    if isinstance(value, bool):
        return {"type": "BOOL", "value": value}
    if isinstance(value, int):
        return {"type": "INT", "decimal": str(value)}
    if isinstance(value, float):
        return {"type": "FLOAT", "binary64_le": struct.pack("<d", value).hex()}
    if isinstance(value, str):
        return {"type": "STRING", "value": value}
    if isinstance(value, list):
        return {"type": "ARRAY", "items": [typed(v) for v in value]}
    assert isinstance(value, dict)
    return {"type": "DICTIONARY", "entries": [[k, typed(v)] for k, v in value.items()]}


SOURCE = {
    "session_id": "synthetic-service-reference-1",
    "model_identity": {"id": "original-interactive-prototype", "version": "0.1.0-prototype", "backend_model": "original-interactive"},
    "source_variant": "jsbsim-1.3.1-upstream",
    "native_source_fingerprint": "0" * 64,
    "prepared_world_sha256": "1" * 64,
    "named_start": "ground-ready", "wind_profile": "calm", "angular_integration_method": None,
}
SEED = {"legacy_input": None, "piston_input": None, "audio": {
    "enabled": True, "engine_gain": 1.0, "airflow_gain": 1.0, "show_panel_captions": True}}
PLAYER = {"type": "LocalPlayer", "version": 1, "id": A, "name": "Aster", "created_utc": UTC, "updated_utc": UTC, "revision": "1"}
PREFS = {"type": "LocalPlayerPreferences", "version": 1, "player_id": A, "revision": "1", **copy.deepcopy(SEED)}
PRACTICE = {"type": "LocalPractice", "version": 1, "id": P, "player_id": A, "source": copy.deepcopy(SOURCE),
    "started_utc": UTC, "last_observed_utc": UTC, "first_tick": "9007199254740992", "last_tick": "9007199254740992",
    "observed_ticks": "0", "tick_rate_hz": 120, "status": "active", "end_reason": None,
    "revision": "1", "creation_sequence": "4", "commit_sequence": "4", "archive": None}


def result(kind, state, sequence, value, code="", request="request_01"):
    return {"request_id": bound(request), "kind": kind, "state": state, "error_code": code, "commit_sequence": sequence, "value": value}


def failed(kind, code):
    return result(kind, "failed", None, None, code)


def request(kind, payload):
    return {"method": "submit", "arguments": typed([{"kind": kind, "payload": payload}])}


def build():
    cases = []

    def add(cid, group, before, stimulus, expected, preserved, evidence="declarative", requires=None):
        cases.append({"id": cid, "group": group, "before": before, "stimulus": stimulus,
            "expected": expected, "preserved": preserved, "evidence_class": evidence,
            "future_actual_evidence_required": requires or []})

    unchanged = ["all owned records/bytes/bits", "queue and undelivered results", "state and counters", "no resolver/worker/SQLite/file call"]
    for label, descriptor in [
        ("FLOAT8", typed(8.0)), ("BOOLtrue", typed(True)), ("STRING8", typed("8")),
        ("StringName8", {"type": "STRING_NAME", "value": "8"}),
        ("INT0", typed(0)), ("INT17", typed(17)), ("INTnegative", typed(-1))]:
        add("poll_reject_" + label, "admission", {"state": "ready", "undelivered_ids": ["r1", "r2"]},
            {"method": "poll", "arguments": {"type": "ARRAY", "items": [descriptor]}, "caller": "owner"},
            {"return": typed(None)}, unchanged)

    for method in ["start", "start_management", "submit", "status", "poll", "begin_shutdown", "try_join"]:
        args = [] if method not in ("poll", "submit") else ([8] if method == "poll" else [{"kind": "list_players", "payload": {}}])
        ret = {"accepted": False, "error_code": "wrong_thread", "request_id": None} if method in ("start", "start_management", "submit") else (False if method in ("begin_shutdown", "try_join") else None)
        add("foreign_thread_" + method, "admission", {"state": "new" if method.startswith("start") else "ready"},
            {"method": method, "arguments": typed(args), "caller": "foreign"}, {"return": typed(ret)}, unchanged,
            requires=["call actual direct ClassDB boundary from actual foreign thread, observe no side effects"])

    reject = typed({"accepted": False, "error_code": "queue_full", "request_id": None})
    for pending, undelivered in [(16, 0), (1, 15), (0, 16)]:
        add(f"queue_full_{pending}_{undelivered}", "queue", {"state": "ready", "pending": pending, "undelivered": undelivered, "other_admission_checks": "all valid; memory available"},
            request("list_players", {}), {"return": reject, "outstanding": 16}, unchanged,
            requires=["fixed test scheduler must establish actual counts without racing a real worker"])
    add("queue_completion_does_not_free_slot", "queue", {"pending": 1, "undelivered": 15},
        {"observed_event": "pending request finishes; nobody polls"}, {"pending": 0, "undelivered": 16, "outstanding": 16, "next_valid_submit": reject},
        ["accepted ID/result order", "reserved capacity remains owned"], "conditional_observation", ["actual worker completion and status/readiness observation"])
    add("poll_frees_exactly_two_slots", "queue", {"pending": 0, "undelivered": 16, "fifo_ids": [f"r{i:02}" for i in range(16)]},
        {"method": "poll", "arguments": typed([2]), "caller": "owner"},
        {"returned_ids": ["r00", "r01"], "remaining_ids": [f"r{i:02}" for i in range(2, 16)], "pending": 0, "undelivered": 14, "new_admission_slots": 2},
        ["returned owned values do not alias remaining/internal values", "database unchanged"])
    add("reservation_failure_prevents_acceptance", "queue", {"state": "ready", "pending": 0, "undelivered": 0, "request_valid": True},
        {**request("create_player", {"id": B, "name": "Birch", "utc": UTC}), "test_observation": "atomic request+maximum-success+minimal-failure reservation cannot be obtained"},
        {"return": typed({"accepted": False, "error_code": "out_of_memory", "request_id": None}), "reserved_slots": 0}, unchanged,
        "conditional_observation", ["test-only allocator fault at admission before any root/BEGIN/export IO; shipping API has no fault argument"])
    add("worker_exception_retains_reserved_fifo", "queue", {"accepted_ids": ["r0", "r1", "r2"], "r0": "possibly begun DB mutation", "r1": "unstarted list_players", "r2": "unstarted rename_player"},
        {"observed_event": "outer worker catches exception; all three reserved receipts remain representable"},
        {"terminal_order": ["r0", "r1", "r2"], "states": ["uncertain", "failed", "failed"], "codes": ["commit_unknown", "worker_lost", "worker_lost"], "commit_sequences": [None, None, None], "values": [None, None, None], "write_admission": "refused"},
        ["no accepted slot silently removed", "actual DB outcome of r0 remains unknown"], "conditional_observation",
        ["actual caught worker exception + reserved storage; thread exit separately witnessed"])

    paired = {"player": copy.deepcopy(PLAYER), "preferences": copy.deepcopy(PREFS)}
    add("create_assigns_default_types", "revision", {"global_sequence": "1", "players": []}, request("create_player", {"id": A, "name": "Aster", "utc": UTC}),
        {"terminal": typed(result("create_player", "committed", "2", paired)), "global_sequence": "2", "player_latest_sequence": "2"},
        ["other players", "no mapper/device capture"], "conditional_observation", ["actual successful COMMIT and postverify required for committed result"])
    renamed = copy.deepcopy(paired)
    renamed["player"].update(name="Aster II", updated_utc=LATER, revision="2")
    renamed["preferences"]["revision"] = "2"
    add("rename_updates_shared_revision", "revision", {"paired": typed(paired), "global_sequence": "2", "player_latest_sequence": "2"},
        request("rename_player", {"player_id": A, "expected_revision": "1", "name": "Aster II", "utc": LATER}),
        {"terminal": typed(result("rename_player", "committed", "3", renamed)), "global_sequence": "3", "player_latest_sequence": "3"},
        ["preferences options exact types/bits", "created_utc"], "conditional_observation", ["actual COMMIT/postverify"])
    for stale in [True, False]:
        add("rename_identical_" + ("stale" if stale else "current"), "revision", {"paired": typed(renamed), "global_sequence": "3", "player_latest_sequence": "3"},
            request("rename_player", {"player_id": A, "expected_revision": "1" if stale else "2", "name": "Aster II", "utc": "2025-01-01T00:00:00Z"}),
            {"terminal": typed(failed("rename_player", "revision_conflict") if stale else result("rename_player", "no_change", "3", renamed))},
            ["all DB fields including timestamps, both revisions and sequence"])
    for stale in [True, False]:
        add("save_identical_" + ("stale" if stale else "current"), "revision", {"paired": typed(renamed), "global_sequence": "3", "player_latest_sequence": "3"},
            request("save_preferences", {"player_id": A, "expected_revision": "1" if stale else "2", "seed": SEED, "utc": LATER}),
            {"terminal": typed(failed("save_preferences", "revision_conflict") if stale else result("save_preferences", "no_change", "3", renamed))},
            ["all DB fields, canonical preference bytes and signed zero bits"])
    zero_seed = copy.deepcopy(SEED)
    zero_seed["audio"]["engine_gain"] = -0.0
    changed = copy.deepcopy(renamed)
    changed["player"].update(revision="3", updated_utc="2026-10-11T12:02:00Z")
    changed["preferences"].update(revision="3", **zero_seed)
    add("save_negative_zero_preserved", "revision", {"paired": typed(renamed), "global_sequence": "3"},
        request("save_preferences", {"player_id": A, "expected_revision": "2", "seed": zero_seed, "utc": "2026-10-11T12:02:00Z"}),
        {"terminal": typed(result("save_preferences", "committed", "4", changed)), "global_sequence": "4"},
        ["other player", "both null input slots", "no Apply or native control call"], "conditional_observation", ["actual COMMIT/postverify; exact restored FLOAT negative zero"])
    maxpair = copy.deepcopy(paired)
    maxpair["player"]["revision"] = maxpair["preferences"]["revision"] = MAX
    for change in [False, True]:
        add("max_revision_" + ("change" if change else "no_change"), "revision", {"paired": typed(maxpair), "global_sequence": MAX, "player_latest_sequence": MAX},
            request("rename_player", {"player_id": A, "expected_revision": MAX, "name": "Changed" if change else "Aster", "utc": LATER}),
            {"terminal": typed(failed("rename_player", "counter_exhausted") if change else result("rename_player", "no_change", MAX, maxpair))},
            ["all rows and counters", "no transient write before increment check"])

    advanced = copy.deepcopy(PRACTICE)
    advanced.update(last_tick="9007199254741112", observed_ticks="120", last_observed_utc=LATER, revision="2", commit_sequence="5")
    base_request = {"practice_id": P, "player_id": A, "expected_revision": "2", "expected_source": SOURCE, "last_tick": advanced["last_tick"], "utc": UTC}
    add("observe_fullrange_tick_difference", "practice", {"practice": typed(PRACTICE), "global_sequence": "4"},
        request("observe_practice", {**base_request, "expected_revision": "1", "utc": LATER}),
        {"terminal": typed(result("observe_practice", "committed", "5", {"practice": advanced})), "global_sequence": "5"},
        ["creation_sequence=4", "source exact", "first_tick exact String"], "conditional_observation", ["actual same-source qualified observation and COMMIT/postverify"])
    for cid, updates, expected in [
        ("equal_active", {}, result("observe_practice", "no_change", "5", {"practice": advanced})),
        ("lower", {"last_tick": "9007199254741111"}, failed("observe_practice", "tick_regression")),
        ("stale_equal", {"expected_revision": "1"}, failed("observe_practice", "revision_conflict"))]:
        add("observe_" + cid, "practice", {"practice": typed(advanced), "global_sequence": "5"}, request("observe_practice", {**base_request, **updates}),
            {"terminal": typed(expected)}, ["all stored fields, revision and counters, including UTC on equal tick"])
    for key in ["session_id", "native_source_fingerprint", "wind_profile"]:
        foreign = copy.deepcopy(SOURCE)
        foreign[key] = {"session_id": "synthetic-other-session", "native_source_fingerprint": "2" * 64, "wind_profile": "from-west"}[key]
        add("source_mismatch_" + key, "practice", {"practice": typed(advanced), "global_sequence": "5"}, request("observe_practice", {**base_request, "expected_source": foreign}),
            {"terminal": typed(failed("observe_practice", "source_mismatch"))}, ["entire practice/sequence; equal tick cannot bypass source comparison"])
    ended = copy.deepcopy(advanced)
    ended.update(status="manually_ended", end_reason="user_end", revision="3", commit_sequence="6", last_observed_utc="2026-10-11T12:02:00Z")
    endpayload = {**base_request, "status": "manually_ended", "end_reason": "user_end", "utc": "2026-10-11T12:02:00Z"}
    end_foreign = copy.deepcopy(SOURCE)
    end_foreign["session_id"] = "synthetic-other-session"
    add("end_source_mismatch_same_tick", "practice", {"practice": typed(advanced), "global_sequence": "5"},
        request("end_practice", {**endpayload, "expected_source": end_foreign}),
        {"terminal": typed(failed("end_practice", "source_mismatch"))}, ["all fields and sequence; joined foreign lifecycle cannot end this row"])
    add("manual_end_same_tick", "practice", {"practice": typed(advanced), "global_sequence": "5"}, request("end_practice", endpayload),
        {"terminal": typed(result("end_practice", "committed", "6", {"practice": ended})), "global_sequence": "6"},
        ["observed_ticks=120", "source/first/last/creation", "no extra simulation tick"], "conditional_observation", ["actual joined terminal lifecycle for exact binding + COMMIT/postverify"])
    for cid, kind, updates, expected in [
        ("terminal_observe_equal", "observe_practice", {}, failed("observe_practice", "invalid_transition")),
        ("terminal_end_retry", "end_practice", {}, result("end_practice", "no_change", "6", {"practice": ended})),
        ("terminal_end_stale", "end_practice", {"expected_revision": "2"}, failed("end_practice", "revision_conflict")),
        ("terminal_end_changed", "end_practice", {"end_reason": "user_quit"}, failed("end_practice", "invalid_transition"))]:
        payload = {**(base_request if kind == "observe_practice" else endpayload), "expected_revision": "3", **updates}
        add(cid, "practice", {"practice": typed(ended), "global_sequence": "6"}, request(kind, payload), {"terminal": typed(expected)}, ["all durable fields/counters"])
    beginseed = {"id": P, "player_id": A, "source": SOURCE, "started_utc": UTC, "first_tick": PRACTICE["first_tick"]}
    add("duplicate_begin_after_end_returns_current", "practice", {"practice": typed(ended), "global_sequence": "6"}, request("begin_practice", {"seed": beginseed}),
        {"terminal": typed(result("begin_practice", "no_change", "6", {"practice": ended}))}, ["terminal state, progressed tick/revision and immutable creation", "no reset/second active row"])
    maxpractice = copy.deepcopy(advanced)
    maxpractice.update(first_tick="18446744073709551495", last_tick=MAX, observed_ticks="120")
    add("max_tick_equal_is_not_overflow", "practice", {"practice": typed(maxpractice), "global_sequence": "5"},
        request("observe_practice", {**base_request, "last_tick": MAX}),
        {"terminal": typed(result("observe_practice", "no_change", "5", {"practice": maxpractice}))}, ["all fields; no unnecessary tick+1 computation"])

    rows = [{"id": str(i) * 32, "player_id": A, "creation_sequence": c, "commit_sequence": m} for i, c, m in [(1, "9007199254740993", MAX), (2, "9007199254740992", "9007199254740992"), (3, "99", "99"), (4, "9", "9")]]
    for cid, cursor, limit, ids, nextcursor in [
        ("first", None, 2, [rows[0]["id"], rows[1]["id"]], "9007199254740992"),
        ("second", "9007199254740992", 1, [rows[2]["id"]], "99"),
        ("last", "99", 2, [rows[3]["id"]], None), ("zero", "0", 2, [], None)]:
        add("page_" + cid, "paging", {"owned_index_projection": rows, "all_full_rows": "prequalified closed terminal Practice/v1; archive summary is linked bool only"},
            request("list_practice", {"player_id": A, "before_creation_sequence": cursor, "limit": limit}),
            {"result_state": "read", "commit_sequence": None, "ordered_ids": ids, "next_before_creation_sequence": typed(nextcursor)},
            ["all rows/counters", "no external archive IO"], requires=["actual read snapshot + exact full summary comparison; index projections alone cannot qualify records"])
    add("page_fresh_snapshot_insert_delete", "paging", {"previous_cursor": "9007199254740992", "previous_rows": rows, "intervening_change": {"delete": rows[2]["id"], "insert": {"id": Q, "creation_sequence": MAX}}},
        request("list_practice", {"player_id": A, "before_creation_sequence": "9007199254740992", "limit": 2}),
        {"ordered_ids": [rows[3]["id"]], "next_before_creation_sequence": typed(None)}, ["newer inserted row never appears behind cursor", "latest commits do not reorder"],
        requires=["actual independent transactions/snapshots; no concurrent SQL proof from Python"])

    add("commit_unknown_then_load_then_equal_retry", "uncertainty", {"paired_before": typed(paired), "global_sequence_before": "2", "request": "rename to Aster II expected revision1"},
        {"observed_event": "actual COMMIT success; acknowledgement/postverify lost"},
        {"first_terminal": typed(result("rename_player", "uncertain", None, None, "commit_unknown")), "service_state": "read_only",
         "reconciliation_sequence": ["actual joined close; new service; qualify exact same owned store", "actual load_player returns renamed revision2 and latest sequence3", "explicit retry expected_revision2 identical name returns no_change sequence3"],
         "reconciled_value": typed(renamed), "retry_terminal": typed(result("rename_player", "no_change", "3", renamed, request="request_retry"))},
        ["no automatic replay", "uncertain receipt never falsely claims committed sequence", "read result alone does not manufacture native source"], "conditional_observation",
        ["actual COMMIT/lost acknowledgement injection, joined worker, reopen/load; separate measured outcomes"])
    for cid, observation, state, code in [
        ("before_begin", "IO failure classified io_error known before BEGIN", "failed", "io_error"),
        ("rollback_observed", "IO failure classified io_error after BEGIN, ROLLBACK observed success AND autocommit1 AND txn_state NONE", "failed", "io_error"),
        ("rollback_unknown", "possibly begun mutation; rollback failure/COMMIT outcome unknown even if autocommit1", "uncertain", "commit_unknown")]:
        add(cid, "uncertainty", {"global_sequence": "2", "paired": typed(paired)}, {"observed_event": observation},
            {"terminal": typed(result("rename_player", state, None, None, code)), "new_write_admission": "refused until joined reopen/reconcile" if state == "uncertain" else "not disabled by this known rolled-back failure"},
            ["never infer rollback from txn_state alone"], "conditional_observation", ["actual phase/extended SQLite code/rollback observations; generic logical event is not injected failure evidence"])
    add("same_process_reopen_missing_binding", "recovery", {"active_practice": typed(advanced), "same_owner_run_id": True, "retained_actual_binding": False},
        {"event": "ordinary storage reopen"}, {"practice": typed(advanced), "current_flight_claim": False, "adapter_observe_end_submissions": 0},
        ["row/source/ticks/revision/sequences", "no synthesized joined evidence or interruption"], "conditional_observation", ["actual process lifetime token and unavailable binding"])
    interrupted = copy.deepcopy(advanced)
    interrupted.update(status="interrupted", end_reason="previous_process_incomplete", revision="3", commit_sequence="6")
    add("different_process_recovery_projection", "recovery", {"active_practice": typed(advanced), "global_sequence": "5", "owner_run_id": "old trusted process"},
        {"event": "actual new trusted process, qualified same store, successful recovery transaction"},
        {"practice_projection": typed({k: v for k, v in interrupted.items() if k != "last_observed_utc"}), "global_sequence": "6", "owner_run_id": "actual new process run ID"},
        ["source/first_tick/last_tick/observed_ticks/creation/archive", "last_observed_utc policy requires explicit clarification before a complete expected Practice"],
        "conditional_observation", ["real exited prior process and different native run ID; actual single recovery COMMIT/postverify"])

    for phase, installed, outcome, state, code, temp, verified in [
        ("read", False, "not_saved", "failed", "revision_conflict", False, False),
        ("write", False, "not_saved", "failed", "file_write_failed", True, False),
        ("move", None, "recovery_required", "recovery_required", "file_recovery_required", True, True),
        ("verify_target", True, "recovery_required", "recovery_required", "file_recovery_required", False, True),
        ("done", True, "saved", "read", "", False, True)]:
        snapshot = phase != "read"
        filevalue = {"operation_id": bound("request_01"), "outcome": outcome, "phase": phase,
            "target_absolute_path": bound("selected_target", "Root-bound outside protected root; actual absolute Windows String"),
            "temporary_absolute_path": bound("observed_owned_temporary", "observed absolute same-directory CreateNew path") if temp else None,
            "installed": installed, "bytes": 1234 if verified else None, "sha256": bound("verified_export_sha256", "lowerhex64 exact owned read") if verified else None,
            "player_id": A if snapshot else None, "preferences_revision": "2" if snapshot else None, "practice_count": 1 if snapshot else None}
        add("export_" + phase, "export", {"database": "qualified ready selected A revision2; for read mismatch actual revision differs", "protected_root": "Root-bound isolated capability"},
            {"request": request("export_player", {"player_id": A, "expected_revision": "2", "target_absolute_path": bound("selected_target", "Root-bound absolute Windows String")}),
             "conditional_observations": {"phase": phase, "actual_verified_length_if_any": 1234 if verified else None, "actual_complete_hash_if_any": "binding only", "move": "unknown" if installed is None else ("observed success" if installed else "not attempted"),
                "temporary_still_observed": temp, "target_verification": "full successful" if phase == "done" else "not established"}},
            {"terminal": typed(result("export_player", state, None, filevalue, code)), "database_write_disabled_by_file_outcome_alone": False},
            ["DB rows/revision/commit sequence", "no overwrite or automatic retry/delete"], "conditional_observation",
            ["actual read snapshot/spool, buffer ledger, NTFS ownership/CreateNew/flush/Move/verification and actor exit as applicable; 1234 is authored conditional data, not observed bytes"])
    add("recovery_delete_partial_partition", "recovery", {"management_only": True, "sqlite_connections": 0, "requested_ids": [A, B]},
        {"observed_event": "all owned files for A proved removed; B not proved fully removed"},
        {"terminal": typed(result("delete_recovery", "failed", None, {"deleted_ids": [A], "retained_ids": [B]}, "snapshot_failed")), "database_uncertainty": False},
        ["no external or unknown path deletion", "requested IDs exact disjoint union"], "conditional_observation", ["actual identity/roster checks and file deletions"])
    add("management_start_no_sqlite", "recovery", {"state": "new"}, {"method": "start_management", "arguments": typed([]), "observed_event": "actual successful root resolution/owner lock/worker setup"},
        {"terminal": typed(result("start_management", "read", None, {"management_only": True})), "status_projection": typed({"state": "unavailable", "error_code": "", "store_version": None, "writer_alive": True}), "sqlite_open_calls": 0},
        ["ordinary DB start requires joined close + NEW object; no in-place switch"], "conditional_observation", ["actual no-SQLite instrumentation + worker/lock observations"])

    for cid, observed, returned in [("worker_alive", "actual worker still alive; shutdown requested", False), ("worker_exited_not_yet_joined", "actual worker exit; all statements/DB/export/snapshot handles already closed; try_join now actually joins and closes retained owner lock exactly once", True)]:
        add("try_join_" + cid, "lifetime", {"state": "closing", "reserved_unpolled_slots": 2}, {"method": "try_join", "arguments": typed([]), "observed_event": observed},
            {"return": typed(returned), "joined_claim_allowed": returned}, ["join does not mean receipt polled; closed-state poll policy still requires clarification", "no detach/timeout kill counted as join"],
            "conditional_observation", ["actual thread/process wait and handle ownership ledger; time elapsed is insufficient"])
    add("shutdown_drains_fifo_before_join", "lifetime", {"state": "ready", "accepted_order": ["r0", "r1"], "pending": 2},
        {"method": "begin_shutdown", "arguments": typed([]), "caller": "owner"},
        {"return": typed(True), "new_submit": typed({"accepted": False, "error_code": "invalid_state", "request_id": None}), "accepted_jobs_canceled": 0, "terminal_order": ["r0", "r1"], "join_requires_actual_exit": True},
        ["reserved result ownership", "no forced service success at10s"], "conditional_observation", ["actual FIFO drain, statements/connection close, actual exit/join and lock release order"])

    ids = [c["id"] for c in cases]
    assert len(ids) == len(set(ids))
    assert 9007199254741112 - 9007199254740992 == 120
    assert int(MAX) - 18446744073709551495 == 120
    assert 16 * 2 * 640 * 1024 == 20971520
    return {"schema": "ProposedLocalPlayersServiceReferences/v1", "status": "PROPOSED_UNRATIFIED_NOT_EXECUTED",
        "license": "Original MIT", "case_count": len(cases),
        "typed_descriptor_policy": "Each value uses explicit NIL/BOOL/INT(decimal String)/FLOAT(8 LE bytes)/STRING/STRING_NAME/ARRAY/DICTIONARY descriptors; dictionary entry keys are actual Strings. $fixture_binding is a test-only observed value constraint, not a production type, source authority, or a caller-chosen service request ID.",
        "authority": "All records/source IDs/hashes/paths are synthetic mathematical or symbolic inputs. SOURCE zero fingerprint is NEVER qualified current flight. Declarative before-states require independently observed real setup when used for runtime tests.",
        "comparison": "Exact typed/bit values and all named preserved state; projections explicitly incomplete. No epsilon, timing pass, consumer output, DB emulator or fixture status counts as actual evidence.",
        "cases": cases}


def expected_bytes():
    return (json.dumps(build(), ensure_ascii=True, indent=2, allow_nan=False) + "\n").encode("utf-8")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--check", action="store_true", required=True)
    parser.parse_args()
    actual = (HERE / "expected-v1.json").read_bytes()
    assert actual == expected_bytes(), "frozen declarative bytes differ; no file was changed"
    print(f"READ-ONLY declarative regeneration PASS: {len(build()['cases'])} proposed cases; zero consumer/DB/runtime observations")
