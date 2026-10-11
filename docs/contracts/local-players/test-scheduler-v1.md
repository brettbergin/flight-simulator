# Local players: deterministic native test observation and scheduler v1

Original MIT. **PROPOSED, unratified, not executed.** Future #218 companion to
[test-capability-v1.md](test-capability-v1.md), [protocol-v1.md](protocol-v1.md),
[recovery-v1.md](recovery-v1.md) and
[reservation-and-export-spool-v1.md](reservation-and-export-spool-v1.md).
No production ClassDB/root/fault/method/DTO extension or alternate store is added.

## Same compiled production paths

Use the SAME production core objects and actual pinned SQLite/default win32
VFS/Windows adapter. An internal qualification-observer interface is declared
inside already allocated store_access.hpp; StoreAccess privately retains a
nullable observer pointer minted only by the separately linked test factory.
The production Windows factory always supplies null. No public setter, arbitrary
Callable, command/path, environment override or fault method exists. Friend
declaration alone supplies no shipping factory implementation. No test define
changes core object bytes or skips record/source validation.

The interface is fixed native event data plus a continue/fail-allocation decision
at the actual arena allocator; no replacement SQL/Win32 result or fabricated
committed value. A test implementation may block at a declared barrier, record
events, fail a real metered allocation request before it occurs, or coordinate
an actual child death/SQLite interruption/OS fixture. Production null-observer
path neither blocks nor allocates observer records. Observer code/factory/actor
implementations and registration are absent shipping compile/link/exports.
This seam is a proposed allocation-role refinement in existing files, not proof
that future source/ABI/symbol absence already passes.

Place event definitions/private interface in store_access.hpp; calls in
service.cpp/store.cpp/windows_filesystem.cpp/codec.cpp and the shared direct
boundary. Place test controller/closed plans in existing
tests/persistence/local_players/faults/fault_plan.hpp and test_capability.hpp/.cpp;
service.cpp/windows.cpp/native.cpp/crash_actor.cpp/faults/lock_actor.cpp drive
the existing five CTests. No general scheduler library or sixth test target.

## Closed sites, counters and barriers

Retain the15 already allocated phase IDs: before_open, before_begin, row_write,
before_commit, after_commit, rollback, postverify, publish_ack, checkpoint,
export_create, export_write, export_flush, export_move, export_verify_target,
recovery_copy. Each site has an exact edge before/after and scope
service/qualification_copy/original/export/recovery. Freeze actual source line
sites and counters in the reviewed source/proof manifest before any run.

- before_open brackets each actual sqlite3_open_v2, tagged qualification_copy or
  original; management has zero such events, not a synthetic successful open.
- before_begin brackets actual SQLite BEGIN stepping, before_commit brackets
  actual COMMIT stepping; after_commit fires after the actual call returns and
  records its real SQLite result. COMMIT success alone is not postverify.
- row_write brackets each actual mutating sqlite3_step in a job; rollback brackets
  the actual rollback call and records actual return/autocommit/txn-state evidence.
  Neither event supplies an invented status in place of that call.
- postverify brackets the actual full owned row/counter readback; publish_ack
  before is after operation classification and reserved terminal construction,
  after is after the real pending-to-undelivered transition. Never block while
  holding the service/queue/status mutex, and copy event scalars before releasing
  it so owner poll cannot invalidate an event's borrowed data.
- checkpoint brackets the actual separate checkpoint. Export sites bracket the
  actual owned CreateNew/write/FlushFileBuffers/no-replace Move/target reread;
  export_write is per actual bounded write call, not per imagined entire file.
  recovery_copy separately brackets EACH actual bounded data-copy READ and EACH
  actual WRITE with role main/wal/shm/journal and chunk index. A successful chunk
  has four events: before-read, after-read, before-write, after-write. A failed read
  has only its two actual read events and no invented write. The pre-write barrier
  occurs after the real read and before the real write, retaining the actual owned
  IO bytes. File bytes/counts/identities come from real calls, not caller assertions.

Every event has exactly {run_nonce,actor_pid,service_ordinal,request_ordinal,kind,
scope,phase,edge,occurrence,event_sequence,detail}. Nonce lowerhex32; PID actual
positive integer; service/request ordinals positive integers assigned by the
test controller (request0 only for non-job lifecycle events); kind existing
method kind or lifecycle; event_sequence positive canonical U64 String strictly
increasing per actor. occurrence is positive INT per
(service,request,scope,phase,edge), starting1. detail is a closed site-specific
observation declared in the plan, not arbitrary payload/SQL/paths/pilot data.
The detail union is closed as follows; actual source line sites and applicability
must be frozen before outputs. Unknown keys/site/scope/edge reject the plan.

| Sites | Exact detail keys and types |
|---|---|
| before_open | {sqlite_result:INT|null}; before=null, after=actual sqlite3_open_v2 return; scope fixes original/qualification_copy |
| before_begin,row_write,before_commit,after_commit,rollback,checkpoint | {sqlite_result:INT|null,autocommit:BOOL,txn_state:INT}; before result=null, after actual return, state from the actual connection; txn_state0..2 |
| postverify | {sqlite_result:INT|null,autocommit:BOOL,txn_state:INT,verified_rows:INT}; result=null before, observed real result after; verified_rows0..2017 counts only fully validated meta/player/preferences/practice rows |
| publish_ack | {pending:INT,undelivered:INT}; copied actual counts0..16, sum<=16, before/after actual transition |
| export_create,export_write,export_flush,export_move,export_verify_target | {win32_error:INT|null,requested_bytes:INT|null,completed_bytes:INT|null,owned_handle:BOOL,installed:BOOL|null,volume_serial:String|null,file_id:String|null,chunk_index:INT,role:String}; fields below |
| recovery_copy | The same exact file-detail fields plus io_kind:String exactly read or write; each call has its own before/after occurrence |

SQLite return is actual signed32-bit result/extended code; before/after connection
state is observed, not guessed from intended action. after_commit is the one
edge=after notification immediately following the actual COMMIT return, carrying
that result; it never re-executes COMMIT. Other listed SQL sites bracket their
actual operation. postverify's count bound derives1 meta+8 Player+8 Preferences+
2000 Practice, not a claimed minimum or a replacement for full validation.

For file details, absent/not-applicable byte/error/identity observations are null,
not synthetic zero. Error is actual DWORD0..4294967295 only after an attempted
operation; success records0 only from actual success. requested/completed are
actual counts0..65536 for bounded calls; a full verify reports its real bounded
chunks instead of an unbounded count. volume_serial is canonical U64 and file_id
lowerhex32 from an actual owned handle, both null until established. chunk_index
is actual INT0..524288; role is exactly target/temp/main/wal/shm/journal. installed
uses the existing file receipt's false/true/unknown observation rule. owned_handle
is actual liveness, never a READY assertion alone. The source manifest must
resolve EVERY actual ReadFile or WriteFile call to its next checked monotone
occurrence in the existing (service,request,scope,phase,edge) counter. Before/after
of the SAME call share its occurrence; actual io_kind and chunk_index are bound
by the frozen source/plan. Read1/write2/read3/write4 is ONLY the illustration for
two successful full-chunk read/write pairs, never an odd/even rule. Each permitted
partial read/write retry gets its OWN next occurrence before the following call;
all such calls count toward the prelaunch checked maximum actual-call bound.
A failed read ends that chunk without any write event. Counters never report a
synthetic write, merge calls or force full-chunk parity onto partial-call loops.

Test-only arena allocation events are separate from the15 IO/SQL phase IDs:
category control/request/terminal/delivery/workspace/export_spool, service and
request ordinal, ordinal positive INT per category, requested/rounded bytes,
reserved/live page counts. Injection selects exactly one category+ordinal and
causes that actual allocation to fail before claiming pages. It cannot revoke a
previous reservation, corrupt accepted bytes or simulate a post-COMMIT failure.
Pre-reserved minimal receipts remain independently witnessed and not allocated
by the fault. Export shared-credit acquisition/release and actual page lifetime
must be observable, not derived merely from an Admission return value.

Plans are finite, at most32 actions, no wildcards or regex/code. IO/SQL selectors
have exactly {service_ordinal,request_ordinal,kind,scope,phase,edge,occurrence};
allocation selectors instead have exactly {service_ordinal,request_ordinal,
category,ordinal}. Each action is exactly {selector,action}, where action is
hold, fail_allocation, request_sqlite_interrupt or await_parent_process_termination.
hold receives one external nonce-bound release command, not an extra wildcard
plan action. fail_allocation admits only allocation selectors; other actions only
applicable IO/SQL selectors. Each selector may match only once; unmatched,
duplicate, out-of-order or unexpected site execution fails the test, retaining
raw events. Successor test record capacity is bounded524288 fixed records per
actor and is test-harness ownership, never a hidden shipping buffer; overflow is
test failure. This explicitly renews the v1 event-count design, not any service,
physics, reference, runtime-performance or watchdog criterion. One maximum336MiB
recovery set needs5376 64KiB chunks and exactly5376*4=21504 actual bracket
records. Sixteen such operations need344064 records, leaving180224 for ALL other
actual events. The literal arithmetic is frozen in the private examples.
The independently frozen actual plan must checked-precount ALL SQL/IO/allocation/
lifecycle events, require at most524288 records (including overhead), and reject
before launch otherwise. The per-plan bound includes smaller chunks/partial-call
loops when the fixture can produce them;5376 is only the declared full-chunk
recipe, not a universal upper bound on actual calls. Unexpected extra events or
record overflow FAIL and retain evidence; no drop/aggregate/skip-on-overflow.
This finite test allocation is not a production arena or promise every plan fits.
Counters are checked before increment; overflow is failure, not wrap/skip.

Hold uses native signalled events/condition variables and explicit controller
release, never a sleep. Controller must observe ARRIVED with matching selector,
PID/nonce and source-bound actual operation before issuing RELEASE for exactly
that action. Worker cannot hold the queue mutex across the wait. Later owner
submit/status/poll calls can establish real pending/undelivered counts while
the worker is held; no mocked status qualifies capacity/FIFO tests.

SQLite interruption must be an actual test-only sqlite3_interrupt/progress
interruption on the real selected connection/statement, with actual SQLite return
and transaction state recorded. It cannot promise a specific IOERR/disk-full
return or represent a real rollback failure. Real process-death, rollback/flush/
disk-capacity and sharing cases need their separate actual OS/SQLite fixture and
phase outcomes. A logical injected refusal is labelled injected, never native
filesystem proof. Unsupported fault outcomes are missing gates, not passing mocks.

## Real lock/crash actors and supervised lifecycle

Actors are the already allocated separately hashed native crash_actor and
faults/lock_actor executables under the exact Root TestRootCapability. No shipping
resource loads them. Parent owns process handles/nonce-bound pipes; arguments
are fixed data (capability descriptor digest, nonce and closed plan), not commands.
Use bounded length-framed UTF8 records:4-byte little-endian length1..4096, then
exact bytes; strict closed keys/types/Unicode/duplicates and full frame admission.
Partial/excess/foreign/PID-mismatch/EOF record is failure, never readiness.

Actor READY exactly {type:"READY",nonce,pid,role,capability_sha256,plan_sha256}.
Role lock_holder/crash_actor. Parent compares PID to actual spawned process and
requires observed liveness, expected executable hash and actual adopted test
capability. A lock holder sends READY ONLY after actual share0 ownership handle
and root/nonce/file-identity qualification. Its separate HELD observation exactly
{type:"HELD",nonce,pid,action_ordinal,volume_serial,file_id,held:true} contains
canonical U64 volume_serial and lowerhex32 file_id from the live handle. Parent
compares these to its qualified selected fixture identity before real competing-access rejection
while holder remains alive. A text marker/existence/READY without held operation
cannot prove a lock.

Parent RELEASE exactly {type:"RELEASE",nonce,pid,action_ordinal}; actor validates
same actual parent channel and current held action. CLOSED exactly
{type:"CLOSED",nonce,pid,reason,handles_closed}; reason released/lease_expired/
parent_eof/actor_error, handles_closed actual bool. Only released with actual
closure plus observed process exit can satisfy normal disposal. Parent retries
incomplete frames until complete/actual exit (with final read)/deadline; never
accept a partial/foreign acknowledgement. Any CLOSED before the held assertion
disqualifies that holder. Parent retains actual stdout/stderr/terminal code and
observes retirement independently of CLOSED.

Proposed test lifecycle watchdogs: startup45s, held lease120s, release/handle-close10s,
then observed-exit10s. These are supervisor failure bounds, not service/SQLite/
physics performance criteria or guarantees that blocked OS calls can be stopped.
No timeout is a passed assertion. Expiry/early exit/parent EOF remains failure
even if a later cleanup succeeds. Known helper lease/reason/liveness observations
are checked throughout the competing operation; slow startup cannot consume an
unobserved held lease and then be reported as a successful lock proof.

Crash plan requires parent ARRIVED at the exact source-bound before-BEGIN,
before-COMMIT, after-actual-COMMIT-before-ACK or recovery site, then actual child
process termination and observed exit before reopening. Intentional death is
expected process-death evidence, never graceful service join. Reopen is another
real process so trusted owner_run_id differs; same-process reopen is separate.
After COMMIT-before-ACK, actual durable read may reconcile the committed state;
it cannot rewrite the lost receipt as committed or automatically repeat the job.

## Independently frozen tests before consumer observations

Prepare exact source-bound plans and typed expected states for:16 held pending;
mixed/unpolled capacity; reserve failure before acceptance/noBEGIN; success and
minimal-failure reservation despite caught exception; poll-copy overlap and
copy independence; two sequential large exports sharing E with other queued
jobs; insufficient shared credit rejected before admission; poll-freed explicit
retry; oversized actual encoded export rejected before target IO; actual rollback,
COMMIT/postverify/ACK and killed-child reconciliation; management zero SQLite;
partial-copy/partial-delete and observed file ownership; never-worker quiescence
versus ever-worker actual join; foreign thread; changed nonce/PID/EOF/expiry/
early-exit actor negatives. No numerical/timing budget is fitted to output.

The32MiB arithmetic/typed declarative examples are not real allocator/fault/SQLite
tests. #218 freezes the finite scheduler/event/actor grammar, design capacity,
independent fixtures and exact allocated source/test roles before implementation.
It does not wait for unwritten consumer hashes. #219 then authors actual sites,
record layouts/counters and controlled plans within that contract, independently
source-reviewed BEFORE compilation/execution. Actual compiled same-core objects,
capabilities, actor exes and five CTest commands are bound after build and before
Root execution, not invented as design acceptance. Actual service/DB/Win32/ClassDB and installed-user/three-context
journeys remain separate gates. Original114/72/66 and all flight evidence stay
immutable; no parents/phase/pilot acceptance follows.
