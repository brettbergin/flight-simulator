# Local players: service lifecycle and admission amendment v1

Original MIT. **PROPOSED, unratified, no consumer/runtime evidence.** Future
companion to [ADR026](../../decisions/026-durable-local-players-and-practice-history.md),
[service protocol](protocol-v1.md) and [records/lifetimes](records-and-lifetimes-v1.md).
This path needs explicit #218 contract allocation and independent review. Nothing
here is effective before the checked contract amendment merges. It changes no
public method roster, DTO key, wire schema, preference codec or flight authority.

This is an explicit semantic amendment to the proposed `try_join` wording and
an exact clarification of interruption timestamps, closed-state ownership and
admission errors. It is not a claim these rules were already implemented or
proved by the original 114 references, 72 recipes or proposed 66 service cases.
All those historical inputs remain byte-for-byte unchanged; future independent
fixtures must be separately named and bind the accepted amended contract.

## Startup interruption preserves real observation time

When a different actual trusted process opens a qualified store with its sole
active practice, the one recovery transaction changes only the fields already
required by the protocol: status becomes `interrupted`, end_reason becomes
`previous_process_incomplete`, row revision and latest commit sequence advance,
global commit sequence advances once, and meta.owner_run_id becomes the new
trusted process run ID. **Preserve last_observed_utc exactly.** Also preserve
started_utc, first/last tick, observed_ticks, immutable source/creation sequence
and archive. Interruption discovery is not a new flight observation, endpoint
or duration. No new Practice field is added for recovery time.

Existing recovery-copy intent/manifest UTC values continue to label those
separate file operations; they never replace a practice observation UTC.
Same-process reopen retains the existing active row pending actual retained
binding plus qualified same-source Readback or actual joined terminal evidence.
No run ID, database row, UTC label or shutdown boolean establishes native flight.
All increment/qualification/uncertainty and no-active read/null rules remain.

## Shutdown and try_join: exact safe-quiescence contract

`begin_shutdown()` remains owner-thread, returns true idempotently, stops new
admission, and preserves/drains all already accepted jobs FIFO. Foreign thread
returns false without change. It does not cancel jobs, invent receipts, stop
native flight or close another service. A shutdown request alone is not closed.

`try_join()` keeps its existing boolean result and owner-thread restriction but
now means **proof of safe service quiescence** under these disjoint conditions:

1. If this instance **ever created a worker**, true requires that exact worker's
   actual exit and actual join, every statement/SQLite connection/export and
   snapshot handle closed, accepted jobs classified into their reserved terminal
   receipts, and the retained owner lock released only after the join. A currently
   alive worker always returns false. A timeout, detach, process kill, dictionary
   copy, worker exit flag alone or elapsed ten seconds cannot satisfy this branch.
   If close/handle release cannot be proved, do not publish closed/true.
2. If this instance **never created a worker**, an owner `begin_shutdown()` followed
   by `try_join()` may return true once there are no in-flight jobs, all accepted
   jobs (if any) have their honest reserved terminal results, and no service-owned
   statement/connection/file/lock handle remains. These calls perform no root
   resolution, store opening or cleanup IO to manufacture closure. No thread
   existed, so this is quiescent closure, **not an observed thread join**. Before
   shutdown was requested a new never-worker instance returns false unchanged.

No private flag can change an ever-created worker into the never-worker branch.
Owner `try_join()` on an already closed object returns true idempotently with
unchanged status/results. Foreign thread returns false, including after closure.
For an exited worker, `try_join()` can close admission and complete the actual
join even if the owner had not separately called begin_shutdown; it cannot
join a live worker or bypass accepted-result/handle ownership prerequisites.

Test-only evidence must distinguish `worker_created=false, quiescent=true` from
`worker_created=true, actual_exit=true, actual_joined=true`; these are test
observations, not new production DTO fields. Accepted startup failure before
worker creation cannot be turned into a fake worker/join. Its terminal error
must still reflect the actually observed failure and existing closed code set;
an admission rejection remains a rejection and does not become an accepted job.

Destroying an instance that is already safely closed may release its undrained
owned terminal results. It cannot retract a committed operation, turn an
uncertain result into failed or fabricate delivery. Already polled copies remain
owned independently of that object. Owner may also destroy a never-worker,
never-accepted new object with no owned handles; there is no thread to join.
An ever-created live/unjoined worker must never be detached/freed through object
destruction. Its control block and reserved result ownership remain alive until
the actual shutdown/join rule is satisfied. An unresponsive worker is a retained
failure, not permission to report joined. Process-exit limitations remain as in
the original records/lifetimes policy.

## Exact closed status, retained diagnostics and result drainage

After successful safe closure `status()` returns the same seven keys:

| Key | Exact closed meaning |
|---|---|
| state | actual String `closed` |
| error_code | final service diagnostic String retained under the rule below; empty only if there was none |
| pending | actual INT0; no queued/in-flight job remains |
| undelivered | actual INT equal to remaining reserved terminal receipts, 0..16 |
| writer_alive | actual BOOLfalse |
| resolved_root | last actually qualified resolved root String from this instance, or null if none; retained diagnostic only |
| store_version | actual INT1 only if this instance actually qualified store version1, otherwise null |

Root/version retention does not retain a lock/connection, promise the path still
exists, qualify a current database snapshot, or authorize reopening. No path IO
is performed to refresh closed status. Management-only start retains version
null; never-started closure retains root/version null and empty error. A fresh
failed start retains only actually established root/version information, never
defaults. Values are independently owned copies.

There is no new `last_error` key. Existing `error_code` is the final **service**
diagnostic, not the last semantic/admission failure returned for an individual
job. Admission failures, poll errors, not_found/revision_conflict/no_change and
successful reads do not overwrite it. Actual startup/qualification failure and
service-wide uncertainty/worker/close failure retain their existing fixed code.
Closing/joining/polling do not clear it. If multiple service-wide failures are
actually observed during FIFO drain, retain the last service-wide diagnostic
published before closure; worker uncertainty is not erased by a later success.
The `commit_unknown` or `verification_failed` uncertainty latch outranks later
ordinary errors until explicit joined close/new-object reconciliation. If both
uncertainty codes are observed, the later actually published uncertainty code
is retained. It describes uncertainty, never a guessed committed sequence.
File export/deletion uncertainty alone does not create this DB uncertainty latch;
its closed file result remains the operation's diagnostic. A worker failure or
actual handle-close failure is separate and cannot be hidden by this distinction.

In closed state owner `poll` is permitted. It still requires actual INT1..16
before any Godot coercion; it returns the first up-to-limit terminal receipts in
original accepted FIFO order, removes exactly those internal receipts and frees
their reservation. Other status fields and the database remain unchanged.
After drainage it returns an empty Array, never null for a valid owner poll.
Wrong thread/type/range returns null and drains nothing. Closed `status`, poll
and repeated shutdown/join do not create any worker or touch the store.
Changing a returned nested receipt cannot alter other returned copies, retained
results, status or durable rows. Poll is delivery, not COMMIT or read reconciliation.

After closure `start`, `start_management` and every `submit` reject with exact
`{accepted:false,error_code:"invalid_state",request_id:null}` for owner calls.
Foreign calls still return wrong_thread first. No restart, reopen, new request
ID, reservation or reused native/storage source is permitted on this instance.
Explicit new ordinary or management service means a NEW object with its own
admission/qualification; it does not revive the closed object.

## Exact admission code ownership

These are proposed deterministic classifications at the direct production
boundary; the test wrapper uses the same boundary. No coercion, UI prevalidation
or permissive fallback may replace them. Existing accepted preset normalizations
remain exact: an INT-or-FLOAT enum accepted by that validator is not rejected
merely because this table distinguishes strict-INT service fields.

| Single violation, other prerequisites valid | Admission error_code |
|---|---|
| Any admission method on a foreign thread | wrong_thread |
| start/start_management outside new; submit in new/opening/closing/closed; known kind prohibited by current ready/read_only/management/unavailable mode | invalid_state |
| submit argument is not actual Dictionary; any Dictionary key is not actual String; kind is not actual String; required payload is not actual Dictionary | invalid_type |
| Outer submit keys missing/extra; kind unknown, or start/start_management supplied as submit kinds | invalid_request |
| Payload/nested record missing/extra key; duplicate unique-ID array element; below-minimum collection length | invalid_record |
| Field has an actual type disallowed by its existing exact field rule: e.g. numeric player_id, StringName source, FLOAT/BOOL list limit, INT Audio gain | invalid_type |
| Correctly typed field violates its domain/cross-field rule: noncanonical/out-of-range U64, bad ID/hash/date, prohibited enum/model/start/wind/method combination, nonfinite/out-of-range gain, control/name Unicode rule, calibrated sibling incompatibility | invalid_record |
| Above an existing declared maximum byte/scalar/array/depth/value/encoded-size cap, including request/result/preset-specific caps at admission | payload_limit |
| Otherwise valid request but16 requests/results remain outstanding | queue_full |
| Otherwise valid request with a free slot but atomic owned request/maximum-result/minimum-failure reservation cannot be obtained | out_of_memory |

The reference to result size means the predicted required maximum reservation
for this request, not a consumer-produced result inspected after COMMIT. The
actual accounting/prediction remains a separate prerequisite below.

No SQL-dependent error becomes an admission rejection: shape-valid but stale
revision, existing row ownership/source mismatch, counter exhaustion, global
player/history/active quota and target existence remain the protocol's accepted
terminal errors once admitted. A syntactically valid old historical fingerprint
is not an invalid scalar simply because it differs from today's loaded source.
Trusted adapter/native origin qualification remains separate from shape checks.
Arity/unknown-method failures reported by Godot's invocation mechanism are not
new Admission DTOs; do not invent results for calls outside the seven-method API.

## Recommended deterministic multiple-violation order

This order is part of the proposed amendment, not an inference from earlier
prose. Single-violation fixtures above are fixed; multi-violation fixtures must
bind the checked accepted order before consumer outputs.

1. Owner thread, then coarse object-state admission (start only new; submit never
   new/opening/closing/closed). Neither reads hostile payload or resolves root.
2. Outer argument actual Dictionary, constant-time outer size exactly2 (otherwise
   invalid_request before enumerating keys), then key types, exact outer key set,
   kind type, kind recognized as a submit kind, payload actual Dictionary, in
   that order. Only two keys can reach the outer key scan.
3. Known-kind service mode eligibility. This can reject a write in read_only
   without inspecting its nested fields. It cannot use database row contents.
4. Applicable bounded payload cap/type preflight before deep record work. Inspect
   container/encoded-length maxima before allocating/iterating children. For
   multiple problems inside a bounded preflight use actual String keys in ASCII
   lexical order and arrays by index, stop at the first encountered violation.
   A cap exceeded at a container rejects payload_limit without traversing the
   excessive children. Unsupported actual Variant types encountered during this
   preflight reject invalid_type. Do not perform unbounded work to find a
   supposedly higher-priority later violation.
5. Exact per-kind payload/nested keys, then field type/domain/cross-field checks
   using the same lexical/index order; type precedes domain for that field.
   Missing/extra keys are invalid_record before existing field values. Existing
   closed preset/Audio validators and numeric normalization remain authoritative;
   their acceptance is not rewritten by a second JSON/record grammar.
6. Outstanding-count capacity (queue_full), then atomic reservation/copy failure
   (out_of_memory). Acceptance/ID/state publication happens only after both pass.

Keys here are contract ASCII names. Arbitrary actual String keys are checked as
keys, never normalized or compared as StringName. Unknown key spellings/Unicode
are rejected by the exact key set, not accepted by sort order. On any rejection
all state, prior results, reservations, IDs and durable values are unchanged.
Temporary bounded validation allocation is not root/worker/queue/DB mutation.
This ordering does not promise that OS resource availability is deterministic;
it fixes which already-established violation wins within a call. If a necessary
bounded temporary validation allocation itself fails before later checks can be
performed, return out_of_memory at that point without side effects; do not claim
the uninspected suffix was valid. Such a resource-failure premise is recorded
separately from multi-invalid-field fixtures with successful validation storage.

## Separate source-layout-aware design gates

This companion does **not** resolve buffer layout or invent a test scheduler.
Before store consumers/output, independently review a concrete owned-memory
ledger: request DTO and bytes, fixed minimal failure slots, maximum successful
result reservation, allocation overhead, export snapshot spool/streaming and
all concurrent16-slot ownership within32MiB, plus exact rejection/failure phase
before BEGIN or selected-output IO. Individual640KiB and export32MiB limits are
caps, not a promise every maximum payload fits alongside every other reservation.
No checkpoint or late allocation can retroactively turn a possible COMMIT into
failed. No unaccounted export buffer or new performance allowance is authorized.

Independently freeze the controlled test-only scheduler/allocator/fault sites,
operation counters, nonce/PID ready/release/exit records and actual source/target
closure. Production ClassDB exposes no fault/root/scheduler extension. Logical
conditions in fixtures do not prove actual SQLite rollback/COMMIT, Win32 locks,
bytes, current native source or worker join. Existing isolated capability,
actual five Windows CTests, separate Linux limits, three-context journey and
disposable-account KnownFolder gates remain; no parent/phase acceptance follows.

Export retention of previously verified observations is already separately
clarified by the reviewed publication work. This companion adds no new export
receipt fields, target permissions, writer path or file success claim.
