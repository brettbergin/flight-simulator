"""Original MIT. Pure proposed integer/conditional reference generator.
No production/SQLite/native/Godot/previous consumer output imported.
Only --check is supported; existing reference bytes are never overwritten.
"""
from pathlib import Path
import argparse
import hashlib
import json

PAGE, ARENA, FIXED, MAX_R, T, D, E = 4096, 33554432, 2097152, 655360, 655360, 655360, 18874368
slot_small, slot_max = PAGE + T + D, MAX_R + T + D

def capacity(case_id, sizes, export_credit, incoming_r=None, incoming_export=False):
    assert len(sizes) <= 16 and all(0 <= r <= MAX_R and r % PAGE == 0 for r in sizes)
    used = FIXED + sum(r + T + D for r in sizes) + (E if export_credit else 0)
    assert used <= ARENA
    row = {"id": case_id, "request_charges": sizes, "shared_export_credit": export_credit,
           "expected_reserved_bytes": used, "expected_free_bytes": ARENA - used}
    if incoming_r is not None:
        assert PAGE <= incoming_r <= MAX_R and incoming_r % PAGE == 0
        need = incoming_r + T + D + (E if incoming_export and not export_credit else 0)
        error = "queue_full" if len(sizes) == 16 else ("out_of_memory" if need > ARENA - used else "")
        row["incoming"] = {"request_charge": incoming_r, "export": incoming_export}
        row["expected_admission"] = {"accepted": not error, "error_code": error,
                                     "additional_reservation_bytes": 0 if error else need}
        row["premise"] = "Owner/ready/type/caps/codec lease already valid; actual capacity test still future."
    return row

CONDITIONAL = [{'id': 'S01_full_copy_two_chunks', 'input': {'actual_calls': [{'io_kind': 'read', 'chunk_index': 0}, {'io_kind': 'write', 'chunk_index': 0}, {'io_kind': 'read', 'chunk_index': 1}, {'io_kind': 'write', 'chunk_index': 1}]}, 'premises': ['Each actual read/write completed one full65536-byte call', 'Root-bound source sites/actor/nonce/handles and plan validated'], 'expected': {'occurrences': [1, 2, 3, 4], 'edges_each': ['before', 'after'], 'actual_event_count': 8}}, {'id': 'S02_partial_write_retry_no_parity', 'input': {'actual_calls': [{'io_kind': 'read', 'chunk_index': 0, 'completed_bytes': 65536}, {'io_kind': 'write', 'chunk_index': 0, 'completed_bytes': 32768}, {'io_kind': 'write', 'chunk_index': 0, 'completed_bytes': 32768}, {'io_kind': 'read', 'chunk_index': 1, 'completed_bytes': 65536}]}, 'premises': ['Fixture actually induces this permitted bounded partial-call sequence', 'Source writer records EACH actual call and advances only observed completed bytes'], 'expected': {'occurrences': [1, 2, 3, 4], 'io_kinds': ['read', 'write', 'write', 'read'], 'edges_each': ['before', 'after'], 'actual_event_count': 8, 'odd_even_rule_allowed': False}}, {'id': 'S03_actual_failed_read_no_write', 'input': {'actual_calls': [{'io_kind': 'read', 'chunk_index': 0, 'succeeded': False}]}, 'premises': ['Real selected read failed; actual Win32 result retained, not a fabricated return'], 'expected': {'occurrences': [1], 'edges_each': ['before', 'after'], 'actual_event_count': 2, 'write_calls': 0}}, {'id': 'S04_unknown_selector_key', 'input': {'selector': {'service_ordinal': 1, 'request_ordinal': 1, 'kind': 'start', 'scope': 'qualification_copy', 'phase': 'recovery_copy', 'edge': 'before', 'occurrence': 1, 'extra': True}, 'action': 'hold'}, 'premises': ['Only stated violation; trusted supervisor validates closed plan before launching actor'], 'expected': {'plan_admitted': False, 'actor_launches': 0, 'worker_or_IO_calls': 0}}, {'id': 'S05_duplicate_selector', 'input': {'repeat_identical_action_count': 2, 'selector': {'service_ordinal': 1, 'request_ordinal': 1, 'kind': 'start', 'scope': 'qualification_copy', 'phase': 'recovery_copy', 'edge': 'before', 'occurrence': 1}, 'action': 'hold'}, 'premises': ['Each selector may match once; duplicate plan rejected before launch'], 'expected': {'plan_admitted': False, 'actor_launches': 0}}, {'id': 'S06_exact_plan_record_bound', 'input': {'checked_max_actual_events': 524288}, 'premises': ['All actual call/partial retry/SQL/allocator/lifecycle overhead included, valid finite plan otherwise'], 'expected': {'capacity_preflight_admitted': True, 'overflow_may_drop_events': False}}, {'id': 'S07_plan_bound_plus_one', 'input': {'checked_max_actual_events': 524289}, 'premises': ['Same finite-capacity preflight; no runtime output observed'], 'expected': {'capacity_preflight_admitted': False, 'actor_launches': 0}}, {'id': 'S08_terminal_reservation_failure', 'input': {'allocation_selector': {'service_ordinal': 1, 'request_ordinal': 1, 'category': 'terminal', 'ordinal': 1}, 'action': 'fail_allocation'}, 'premises': ['Exact first terminal reservation selected BEFORE admission and effects', 'Real arena fail-before-claim hook, not revocation of accepted memory'], 'expected': {'accepted': False, 'error_code': 'out_of_memory', 'request_id': None, 'slot_count_delta': 0, 'BEGIN_calls': 0, 'export_IO_calls': 0}}, {'id': 'S09_codec_lease_busy', 'input': {'codec_lease': 'owned_by_worker', 'outstanding_before': 3}, 'premises': ['Otherwise valid owner/ready/type/caps request', 'No queue saturation; nonblocking admission cannot borrow codec workspace'], 'expected': {'accepted': False, 'error_code': 'out_of_memory', 'request_id': None, 'outstanding_after': 3, 'wait_on_worker_or_IO': False}}, {'id': 'S10_foreign_nonce_ready', 'input': {'ready_nonce_matches': False, 'ready_pid_matches': True, 'process_alive': True}, 'premises': ['Actual actor/received frame observations, not assumed from marker existence'], 'expected': {'readiness_qualified': False, 'held_lock_proof': False, 'failure_retained': True}}, {'id': 'S11_expired_holder', 'input': {'closed_reason': 'lease_expired', 'handles_closed': True, 'actual_exit_observed': True}, 'premises': ['Correct actual nonce/PID and parsed frame; lease expiry is real failure'], 'expected': {'normal_disposal_passed': False, 'failure_retained': True, 'cleanup_does_not_erase_failure': True}}, {'id': 'S12_closed_frame_without_exit', 'input': {'closed_reason': 'released', 'handles_closed': True, 'actual_exit_observed': False}, 'premises': ['Correct actual nonce/PID; claimed CLOSED alone is not process retirement'], 'expected': {'normal_disposal_passed': False, 'actual_join_or_exit_proven': False}}, {'id': 'S13_real_held_lock_readiness', 'input': {'ready_nonce_matches': True, 'ready_pid_matches': True, 'actual_executable_matches': True, 'actual_capability_matches': True, 'actual_handle_identity_matches': True, 'holder_alive_during_competing_call': True, 'actual_competing_access_rejected': True, 'closed_before_held_assertion': False}, 'premises': ['Every true input must come from Root-bound ACTUAL NTFS/process/handle operations', 'A JSON dict with these values is not runtime evidence'], 'expected': {'held_lock_proof': True, 'normal_disposal_still_requires_released_and_actual_exit': True}}]

def build():
    rows = [
        capacity("L01_empty_ready_after_start_polled", [], False),
        capacity("L02_sixteen_maximum", [MAX_R] * 16, False, PAGE),
        capacity("L03_fifteen_maximum_accept_last", [MAX_R] * 15, False, MAX_R),
        capacity("L04_sixteen_small_count_precedes_space", [PAGE] * 16, False, PAGE),
        capacity("L05_fifteen_small_first_export_refused", [PAGE] * 15, False, PAGE, True),
        capacity("L06_first_large_export", [], False, MAX_R, True),
        capacity("L07_six_large_shared_exports", [MAX_R] * 6, True, MAX_R, True),
        capacity("L08_nine_small_shared_exports", [PAGE] * 9, True, PAGE, True),
        capacity("L09_five_large_export_pending_accept_sixth", [MAX_R] * 5, True, MAX_R, True),
        capacity("L10_export_credit_released_six_undelivered", [0] * 6, False, MAX_R),
    ]
    rows.extend([
        {"id": "L11_page_rounding_header_included", "input": {"capacity_with_header": [128, 4096, 4097, 655360, 655361]},
         "expected": {"page_charge": [4096, 4096, 8192, 655360, None], "last_error": "payload_limit"},
         "premise": "Native owned request total, not bare wire payload; all earlier validations pass."},
        {"id": "L12_two_exports_hold_shared_credit", "input": {"pending_exports": 2, "active_exports": 1},
         "expected": {"shared_credit_bytes": E, "second_spool_allowed": False,
                      "after_first_terminal_credit_bytes": E, "after_last_terminal_and_no_borrower_credit_bytes": 0},
         "premise": "Sole writer FIFO and both exports already admitted; results retain their own T/D."},
        {"id": "L13_poll_overlap", "input": {"request_charge": MAX_R},
         "expected": {"initial_R_T_D": slot_max, "after_last_request_borrower_T_D": T + D,
                      "during_poll_T_D": T + D, "after_successful_transfer_native_slot_bytes": 0},
         "premise": "No export credit; caller-owned output remains independent and outside native arena."},
        {"id": "L14_spool_conservative_integer_bound", "input": {"players": 1, "practice_rows": 2000},
         "expected": {"inner_upper_bytes": 17044688, "spool_capacity": E, "margin_bytes": 1829680},
         "premise": "Each stated canonical SQL/codec bound and summary encoding premise must be independently proven; not actual encoded output."},
        {"id": "L15_outer_stream_cap", "input": {"counted_outer_bytes": [33554432, 33554433]},
         "expected": [{"encoding_cap_admitted": True}, {"terminal_state": "failed", "error_code": "storage_full", "phase": "encode", "installed": False, "target_IO_calls": 0}],
         "premise": "Hypothetical exact stream counts before any target IO; no saved/hash/path observation inferred."},
        {"id": "L16_actor_record_bound", "input": {"recovery_set_bytes": 352321536, "chunk_bytes": 65536, "operations": 16},
         "expected": {"chunks_per_operation": 5376, "bracket_records": 172032, "record_capacity": 262144,
                      "remaining_for_independently_counted_other_events": 90112},
         "premise": "Exact math only; actual plan must also bound all SQL/IO/events or refuse launch."},
    ])
    rows[-1]['input']['events_per_full_read_write_chunk'] = 4
    rows[-1]['expected'].update(bracket_records=16*(352321536//65536)*4, record_capacity=524288,
        remaining_for_independently_counted_other_events=524288-16*(352321536//65536)*4)
    rows[-1]['premise'] = 'Declared full64KiB successful read+write chunk has four actual events. Checked actual plan also bounds ALL other events and partial-call/chunk multiplicity before launch; overflow fails, never silently drops.'
    assert 16*slot_max+FIXED == ARENA
    assert 8192+614400+2000*(8192+16)+2000+4096 == 17044688
    assert rows[-1]['expected']['bracket_records'] == 344064
    return {'schema':'IndependentLocalPlayersReservationReferences/v1',
        'status':'PROPOSED_PRECONSUMER_UNRATIFIED','license':'Original MIT',
        'arithmetic_case_count':16,'conditional_case_count':len(CONDITIONAL),
        'arithmetic_cases':rows,'conditional_runtime_recipes':CONDITIONAL,
        'authority':'Conditional premises must be ACTUALLY witnessed; no dict/recipe supplies IO/PID/native/SQLite/worker authority.'}

def encoded():
    return (json.dumps(build(),indent=2,ensure_ascii=True)+'\n').encode('utf8')

def main():
    parser=argparse.ArgumentParser()
    parser.add_argument('--check',action='store_true',required=True)
    parser.parse_args()
    actual=Path(__file__).with_name('expected-v1.json').read_bytes()
    expected=encoded()
    if actual!=expected: raise SystemExit('Changed independent reservation references')
    print(json.dumps({'mode':'read_only_check','arithmetic_cases':16,'conditional_recipes':len(CONDITIONAL),
        'expected_sha256':hashlib.sha256(actual).hexdigest()}))
if __name__=='__main__':main()
