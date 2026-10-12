# Local players: isolated test capability v1

Original MIT. **PROPOSED, unratified.** This companion allocates a test boundary
for the proposed ADR026 service. It is not implemented protection, a successful
store test, or permission to open the owner's product store. The exact source
and target slots are in [compiled-source-allocation-v1.json](compiled-source-allocation-v1.json).
The service protocol and recovery rules retain their existing meanings.

## Shipping and reusable source boundary

The production Windows extension is `flight_local_players_bridge.dll`, entry
`flight_local_players_init`, registering only `LocalPlayers`. It has precisely
`start`, `start_management`, `submit`, `poll`, `status`, `begin_shutdown` and
`try_join`. It has no test-root, capability, injected root, arbitrary fault,
process-exit or simulated-commit ClassDB method. No CLI/env/config parameter can
change its root. Missing storage/unsupported platform reports unavailable and
keeps Guest usable; it never substitutes another folder or a positive no-op.

Shipping root composition is a pure function of an actual successful native
`SHGetKnownFolderPath(FOLDERID_LocalAppData,0,nullptr,...)` result plus fixed
`FlightSimulator/Players`. Check HRESULT, free the result with CoTaskMemFree;
do not request CREATE from KnownFolder. The actual resolver and directory/store
opening are separate. A read-only resolver check creates no FlightSimulator
folder and is not a test of product writes/ACLs. No Python environment-variable
replacement proves KnownFolder identity.

`include/flight/local_players/store_access.hpp` defines an internal opaque move-only `StoreAccess` token.
Its constructors are private and bind origin, actual opened root identity and
owned platform implementation. Production factory is in `src/windows_filesystem.cpp`; it
never accepts a selected root. Test factories exist only in the separately
compiled `tests/persistence/local_players/test_capability.cpp` and test header.
A narrowly scoped friend declaration permits those compiled test factories to
mint the token. A declaration has no callable implementation in the shipping
link; it is not a ClassDB entry point. No conditional macro alters the reusable
production core object bytes. Repository/service constructors accept the token,
not a public path or a boolean claiming validation. Both production and tests
use the same repository, codec, queue and Windows filesystem/SQLite code.

The test root factory, fault actor, child crash entry and test registration
objects are absent from shipping compile/link target lists. Audit actual source
lists, compile/link commands and map plus shipping ClassDB methods; a stripped
DLL string scan alone is not proof. No factory ABI is installed/exported. Test
source is included as corresponding source for reproducibility, not linked into
or loaded by the shipping player.

## Root-owned test descriptor

Root explicitly creates one fresh unique direct child of a declared private
proof parent, using native Windows APIs and no existing product/profile/cache
store. The child and parent must already exist before capability admission.
Root writes a fresh sentinel, opens/identifies root+parent, and binds a reviewed
exact descriptor. A standalone test executable may receive only this descriptor
and its exact expected SHA256 from Root's fixed supervisor. Values are data,
never command strings. The descriptor has exactly these actual String keys:

| Key | Type/meaning |
|---|---|
| schema | String `LocalPlayersTestRootDescriptor/v1` |
| root | String existing absolute physical Windows root, max4096 UTF8 bytes |
| parent | String existing absolute physical declared proof parent, max4096 bytes |
| nonce | String exactly32 lowercase hex, fresh per run |
| root_volume_serial | canonical U64 String from actual root handle |
| root_file_id | String32 lowercase hex, actual FILE_ID_INFO128 bytes |
| parent_volume_serial | canonical U64 String from actual parent handle |
| parent_file_id | String32 lowercase hex, actual FILE_ID_INFO128 bytes |
| sentinel_sha256 | String64 lowercase hex of exact Root-written sentinel bytes |

The sentinel is the ordinary file `.local-players-test-root.json` directly in
root, bounded1024 bytes. Its exact UTF8 LF content is independently bound by the
descriptor, with `{"schema":"LocalPlayersTestRootSentinel/v1","nonce":"<32hex>"}`
in that fixed member order and one final LF. No absolute path is put in its name.
The test harness's trusted prerequisite separately resolves actual product root
read-only and identifies workspace source root, drive root and selected proof
parent. These exclusions come from native observations/Root's declared source
context, never an arbitrary caller-provided forbidden-path array. No store is
opened by that prerequisite. Descriptor rejection must cause zero calls to the
shipping resolver, worker creation, root creation or SQLite open. The independent
read-only prerequisite is recorded separately, not disguised as a repository
fallback during rejection.

The capability factory validates exact descriptor shape/types, byte cap,
canonical strings and SHA before any store access; ordinary ancestors, root,
parent and sentinel via native handles; same actual volume/file IDs; exact
sentinel bytes/hash+nonce; and actual parent-child containment. No junction,
symlink/reparse, UNC/network volume, unsupported non-NTFS target or ambiguous
alias is accepted. Root is strictly within the declared parent and not that
parent. The root basename is exactly `local-players-test-<nonce>`. Reject root
that equals, contains or is contained by the actual product root; reject drive
root, workspace source root or their ancestors. A separately declared private
`.local` descendant is permitted, not the workspace source root itself. Compare
canonical component boundaries and actual file identities; neither string-prefix
checks nor case folding alone establish safe containment.

Observed path checks assume stable parent identity during the operation. Recheck
handles/identities at opening and cleanup. This does not claim adversarial
all-path atomic security against external rename/reparse races. Unknown or
changed identity refuses access and retains evidence; no fallback creates a
replacement root or follows a link.

## Test wrapper, fault surface and process lifecycle

The separate test extension `flight_local_players_test_bridge.dll` has its own
registration in `tests/persistence/local_players/test_bridge.cpp` and resource
`tests/persistence/local_players/local_players_test.gdextension`; it registers
only `LocalPlayersTest`. It links the SAME production core and Windows adapter
and SAME direct `LocalPlayersBoundary` admission implementation, with a test-origin
token supplied by the test factory. Its `LocalPlayersTest` wrapper extends
RefCounted and forwards to that same boundary; it does not derive from an
unregistered Godot `LocalPlayers` base or provide a second validator. It does
not register production `LocalPlayers` or load the
production storage resource in the isolated-root journey. Flight's independent
extension/resources remain separately bound.

`LocalPlayersTest.configure_test_root(descriptor)->bool` is test-only, owner
thread, state new, once only. It validates the Root-bound capability before
ordinary seven-method service use. Invalid/foreign/missing descriptor returns
false, preserves existing state and cannot call KnownFolder/open a store.
Starting a test wrapper without a valid configured token fails before any IO;
there is no production-provider fallback. Exact expected descriptor digest is
supplied by the fixed test supervisor/prepared fixture, not another untrusted
field of this dictionary. Test wrapper and production wrapper share direct
closed record validation/conversion; test registration must not weaken public
admission or add a mutable Godot object to worker DTOs.

Injected fault phase IDs are closed test-only enums: before_open, before_begin,
row_write, before_commit, after_commit, rollback, postverify, publish_ack,
checkpoint, export_create, export_write, export_flush, export_move,
export_verify_target and recovery_copy. Actual faults must use the same native
operation sites and expose observed phase/outcome; they cannot return fabricated
committed results or turn a Python recipe into SQLite evidence. Unexpected
phase IDs reject. Precise per-operation schedules/counters and test result
shapes are independently frozen with actual drivers before their qualification;
this allocation does not fabricate those unwritten outputs. Hard process death uses the closed `tests/persistence/local_players/crash_actor.cpp`
standalone `local_players_crash_actor` target; share locks use
`tests/persistence/local_players/faults/lock_actor.cpp` and
`local_players_lock_actor`. Both share the exact test capability and production
core/Windows adapter; nonce-bound READY/release/exit and each executable hash are
validated independently. These actors belong only to test executables, never
the shipping ClassDB or an owner game process. No arbitrary Callable/filename
or shell command is a fault parameter.

The supervisor starts every child with the same bounded capability, separate
isolated profile and controlled arguments; preserves raw stdout/stderr/exit;
checks actual worker/process exit+join. A timeout/process kill is not a successful
service join or committed acknowledgement. Uncertain jobs retain the protocol's
commit_unknown/read_only/reconciliation meanings. No synthetic row/source IDs
or database rows establish a flight: actual journey source comes only from an
adopted qualified native session, with explicit authority snapshots and lifecycle.

## Cleanup and required evidence

After observed child exits and worker/SQLite/OS handles close, Root revalidates
nonce, sentinel, parent/root identity and exact canonical containment, then may
remove only that run child. Changed/missing sentinel, unknown file ownership,
remaining actor/handle, or changed identity means retain it and report the
location; no recursive delete against a computed unchecked path. Tests never
clean product root or external archive/export paths outside this run child.
No profile/player/history/crash dump is uploaded by default.

Required future evidence separates (1) source/target and shipping-symbol/API
absence; (2) pure descriptor negatives, with no IO/worker/resolver side effects;
(3) actual NTFS identities/reparse/locks/CREATE_NEW/flush/no-replace and recovery
under valid capability; (4) same production repository/codec/worker objects and
exact pinned SQLite/CRT; (5) actual editor/portable/rebuilt test extension journey
and joined shutdown; and (6) separately authorized disposable-account production
KnownFolder journey. Linux pure codec/core tests do not satisfy Win32/service/
product gates. Guest, native flight authority, Audio amendment, session-only Views,
existing Facade/298/WireCodec/camera receipts and numerical references stay intact.

## Fixed qualification target allocation

The five Windows CTests are exactly `local_players_codec`, `local_players_store`,
`local_players_service`, `local_players_windows` and `local_players_crash`.
`codec.cpp` drives exact values; public `native.cpp` drives distinct fixed store
and crash suites; `service.cpp` and `windows.cpp` retain their published roles.
The allocation closes each executable and actual CTest command. Root's already
allocated qualifier creates per-test capabilities only after explicit native
execution authorization, observes actual child exit and preserves failures.
The real crash and lock actors above cannot be replaced by return-code mocks
or sleep-based lock assumptions. They are absent shipping source/link lists.
Linux executes only the pure codec/reference test and records the four Windows
gates unavailable; it cannot fabricate Win32/store qualification.

SQLite's distinct **C** compiler ID/version/executable digest, flags, configuration
flags, exact target definitions/options/include provenance and C /MD runtime are
bound independently of CXX. After compilation, actual SQLite C command, object
and static archive roster plus storage link map verify inclusion in the tested
DLL. These post-build witnesses are excluded from compiled hash inputs to avoid
an identity cycle. No actual compiled witness/hash is allocated by this draft.

## Normative companions and independent fixed reference inputs

This proposed successor appends four normative contract inputs, in order, without
changing the original seven-input prefix:

- [service-lifecycle-amendment-v1.md](service-lifecycle-amendment-v1.md)
- [full-record-reference-amendment-v1.md](full-record-reference-amendment-v1.md)
- [reservation-and-export-spool-v1.md](reservation-and-export-spool-v1.md)
- [test-scheduler-v1.md](test-scheduler-v1.md)

The allocation also closes these13 independent qualification/source-package inputs:

- [tests/persistence/local_players/service_reference/expected-v1.json](../../../tests/persistence/local_players/service_reference/expected-v1.json)
- [tests/persistence/local_players/service_reference/generate.py](../../../tests/persistence/local_players/service_reference/generate.py)
- [tests/persistence/local_players/service_reference/source-binding-v1.json](../../../tests/persistence/local_players/service_reference/source-binding-v1.json)
- [tests/persistence/local_players/service_reference/README.md](../../../tests/persistence/local_players/service_reference/README.md)
- [tests/persistence/local_players/full_record_reference/expected-v1.json](../../../tests/persistence/local_players/full_record_reference/expected-v1.json)
- [tests/persistence/local_players/full_record_reference/generate.py](../../../tests/persistence/local_players/full_record_reference/generate.py)
- [tests/persistence/local_players/full_record_reference/source-binding-v1.json](../../../tests/persistence/local_players/full_record_reference/source-binding-v1.json)
- [tests/persistence/local_players/full_record_reference/README.md](../../../tests/persistence/local_players/full_record_reference/README.md)
- [tests/persistence/local_players/full_record_reference/player-summary-v1.json](../../../tests/persistence/local_players/full_record_reference/player-summary-v1.json)
- [tests/persistence/local_players/reservation_reference/expected-v1.json](../../../tests/persistence/local_players/reservation_reference/expected-v1.json)
- [tests/persistence/local_players/reservation_reference/generate.py](../../../tests/persistence/local_players/reservation_reference/generate.py)
- [tests/persistence/local_players/reservation_reference/source-binding-v1.json](../../../tests/persistence/local_players/reservation_reference/source-binding-v1.json)
- [tests/persistence/local_players/reservation_reference/README.md](../../../tests/persistence/local_players/reservation_reference/README.md)

The exact17 added path/size/raw-SHA256 bindings are in the allocation. Missing,
duplicate or changed inputs fail; existing114/72/66 and110 expected math/type/byte
fixtures remain immutable. Historical source-binding metadata retains authoring
provenance; the fresh proof manifest separately binds actual adopted contracts.
Read-only generator checks are mandatory. No extra CTest, actor, compiled source,
build control, shipping method or fault hook is allocated:17 storage source slots,
15 controls and the five fixed CTests retain their original order and definitions.

The lifecycle companion fixes admission/quiescence/retained-result semantics and
preserves actual observed flight UTC. A never-created worker needs no fictitious
join; every ever-created worker still needs actual exit/join and closed resources.
The full-record companion freezes complete numeric-creation-desc export history
and exact scanner accounting. PreferencesStorage envelope and decoded payload
are scanned separately, each30000 values/depth12 before tag restoration; that is
not an aggregate-export value cap. All closed rows,2000-summary count and32MiB
outer-byte limits still apply. Reference fixtures are independent byte/type and
conditional state expectations, never storage or crash observations.

Reservation/scheduler companions specify the32MiB native-owned arena excluding
caller Variants/SQLite/OS, one shared18MiB inner-export spool, and real four-event
recovery IO pairs with independently counted partial calls. Sixteen is a request
count ceiling, not a promise16 exports fit. The conditional17044688-byte inner
spool premise still needs a complete canonical-encoder/maximum-record-size
argument; one2000-row expansion is not that theorem. All actual events must fit
the checked524288-record test plan, with overflow/unexpected events failing.
Test observer/factory/actors remain absent shipping objects; actual allocator,
SQL/OS faults, process exit and joins must be witnessed, not supplied by recipes.

Issue218 accepts concrete design, roles, representations/ceilings and independently
reviewed fixtures. Issue219 then authors actual layouts, terminal/failure paths,
source sites and hashes within that contract, independently reviewed after
authoring and BEFORE compilation/execution. Unwritten source hashes are not a
circular prerequisite for contract authoring. Actual compiled source/link closure,
five CTests, service/SQLite/NTFS/ClassDB and installed-player journeys remain
separate gates. This proposed publication alone neither closes218 nor unlocks
219/220, accepts runtime storage, or changes native flight authority.


## Proposed fixed remaining-row qualification amendment

This public contract amendment is proposed pending checked merge and adoption.
It allocates source-only test evidence; consumers wait for that acceptance.
This publication contains no consumer implementation or execution evidence. The previous five CTest names and commands, eight compiled
test output roles, 19 crash recipes/20 actors/38 stages and all 17 production
source paths remain unchanged. The first-error SQLite witness proposal is separate.

`local_players_store` has exactly two sequential children of the SAME reviewed
`local_players_store_native` executable: original store child, then remaining-row
child. No concurrent child, replacement of the first child, new executable/CTest,
actor, production method or factory is allocated. Both retain context role
`store`, CLI `--suite store`, the existing NativeAuth `children.store` pin and
actual parent/PID/start/exit/Job retirement/input lease requirements.

The original child keeps its existing `LocalPlayersNativeTestPlan/v1`, eight
case IDs, first-Service ordinal prefix and 16,384-event gate. The second child
has a distinct fresh physical capability root/parent/nonce/sentinel and retained
context/descriptor/plan hashes, not another counter in the original process.
Root's qualifier derives only the additional fixed case namespace
`store-remaining-rows`, before launching it; it is not caller-selectable.

The second plan has exactly the existing six String keys `schema`, `nonce`,
`first_service_ordinal`, `maximum_actual_events`, `suite`, `cases`.
`schema="LocalPlayersRemainingRowsTestPlan/v1"` is the sole new discriminator;
`suite="store"`, `maximum_actual_events` is INT 16384 and `first_service_ordinal`
is a positive INT <= INT64_MAX-30. No FLOAT coercion, other suite/role/schema or
extra key is admitted. `cases` is exactly this 17-String ordered list, with no
omission, substitution, reorder, duplicate, wildcard or arbitrary SQL:

1. `DN_column_prefs_revision`
2. `DN_column_practice_status`
3. `DN_column_source_session`
4. `DN_column_source_fingerprint`
5. `DN_column_creation`
6. `DN_column_commit`
7. `DN_column_practice_revision`
8. `DN_column_practice_owner`
9. `DN_meta_behind`
10. `DN_missing_preferences`
11. `DN_semantic_corruption_rehashed`
12. `SQLN_not_strict`
13. `SQLN_fk_missing_cascade`
14. `SQLN_active_index_not_unique`
15. `SQLN_mutable_cursor_index`
16. `DN_column_player_id`
17. `DN_column_prefs_owner`

The first 15 IDs are distinct failed Store-start qualification cases. The final
two are exact-schema SETUP applicability cases, not passing Store corruption
tests. Keep the full frozen 110-case reference bytes/expected outcomes unchanged.

The additional child uses 31 sequential Service lifetimes: genuine empty-store
initialization at offset 0, then failed-start/management-cleanup pairs at offsets
1/2 through 29/30 in listed loadable order. These 31 Service lifetimes use ONE capability/root, not 31 roots:
one capability encloses all 31 lifetimes. Every worker joins; no ownership overlap.
The original store child and crash/service ordinal guards do not shift.

Each process independently fails on any event beyond 16,384. The store CTest
rollup is the sum of both actual counts and fails above 32,768; no counter reset,
unmetered observer, truncated event buffer or success after either child failure.
Each child has a 600-second supervisor deadline. The store CTest TIMEOUT changes
explicitly from 600 to 1,200 seconds, measured from its start and including preparation/cleanup;
this is a finite bound, not an extra 1,200 seconds after a child deadline. The other four
CTest timeouts stay 120/900/900/7200 seconds; overall Native remains 14,400 seconds. Root supervisor
must stop launching if the combined deadline is exhausted and preserve failures.
NativeAuth exact keys/children/limits grammar stays unchanged: its existing
`native_case_seconds.store=600` remains the per-child bound, not the CTest bound.

The existing qualifier source must explicitly admit the new namespace and
successor plan, retain two invocations/capabilities/results in order, and validate
actual exact output/reference dispositions. No source-only plan or successful
setup constraint substitutes for actual Store failure. Required future consumer
changes are confined to already allocated `tests/persistence/local_players/native.cpp`,
`tools/local-players/qualify.py` and `tests/persistence/local_players/CMakeLists.txt`
(the existing 15-control slot for the store timeout). Actual source/control/contract
identities must be freshly reconstructed and qualified. No consumer implementation
or new source slot accompanies this contract proposal.


### Closed second-child receipt and store rollup

The original store child's stdout remains its exact existing text record. The
second child writes one compact JSON value and one final LF, with no other stdout.
Its schema is `LocalPlayersRemainingRowsReceipt/v1` and its exact keys are
`schema`, `pid`, `nonce`, `descriptor_sha256`, `plan_sha256`, `checks`,
`actual_events`, `joined`, `cases`. PID is the actual positive Windows process
ID, nonce is the bound 32-lowercase-hex capability nonce, both hashes are the
actual 64-lowercase-hex retained inputs, checks is a positive INT <= INT64_MAX,
actual_events is a positive INT <= 16384 and joined is BOOL true only after
all ever-created workers actually joined. A successful exit without this full
receipt, or a receipt with an unjoined worker, is failure.

`cases` is exactly 17 ordered closed records, one per plan ID. Each has exactly
`id`, `disposition`, `reference_input_sha256`, `reference_expected_sha256`,
`checks`, `actual_events`, `sqlite_result`, `error`. Hashes are independently
reproduced from that frozen row's entire `input` and `expected` values, not from
consumer output. Use the existing full-record reference `canonical` encoding:
ASCII dictionary keys sorted lexically; array order retained; lowercase JSON
literals and base-10 INT; compact separators; quotes/backslashes escaped; every
C0 scalar encoded as lowercase `\u00xx`; other Unicode emitted as UTF-8;
no whitespace, BOM or final LF. Hash the exact encoded UTF-8 bytes with SHA256.
No FLOAT re-encoding is needed or permitted for these frozen tagged values.

Each case checks is a positive INT <= INT64_MAX. For the first 15 records,
disposition is exactly `failed_store_qualification`, actual_events is the positive
whole observer delta for that failed-start AND its joined management cleanup,
and error is the actual failed terminal's String: `corrupt_store` for the first
11, `foreign_store` for the next 4. sqlite_result is the INT or NULL actually
observed in the qualification-copy postverify-after record; NULL is allowed only
when that actual record has no SQLite result. Do not synthesize an API error from
the semantic rejection, or substitute a label for witnessed terminal/worker truth.

For the final two records, disposition is exactly
`setup_constraint_inapplicable_to_loadable_store`, actual_events is INT 0,
sqlite_result is the actual extended primary-key result INT 1555 and error is
NULL. Require actual exact-schema mutation refusal and whole-state rollback proof;
this is a setup outcome, not a Store test pass. The native receipt preserves its
real result, while the qualifier independently verifies every reference hash,
ID, ordered disposition, exact counts/types and allowed error/null combination.

The sum of all case actual_events plus the separately accounted fresh
initialization observer delta equals receipt actual_events. Context/admission and
initialization assertions may add checks beyond the sum of per-case checks;
the top checks must be at least that sum. Setup operations outside the Service
observer stream are labelled separately, not added as fake observer events.

The existing `LocalPlayersCTestCase/v1` top-level keys remain unchanged. For store,
`root_capabilities`, `invocations` and `driver_results` each contain exactly two
records in original-child/remaining-row-child order; actors is exactly empty.
The original observed_result shape stays unchanged; the second observed_result
is the complete admitted JSON receipt above, cross-bound to its actual child PID,
context, descriptor/plan hashes, terminal exit 0 and joined Job/process evidence.
Neither a printed passed label nor missing raw stdout can qualify a result.

Store coverage has exactly `fixed_cases`, `remaining_row_cases`, `checks`,
`actual_events`, `child_checks`, `child_actual_events`. fixed_cases remains the
original ordered eight IDs; remaining_row_cases is the exact ordered 17-ID list.
child_checks and child_actual_events are exact two-INT arrays in child order;
checks/actual_events are their checked sums. Each child_events is positive and
<= 16384; their sum is <= 32768. Arithmetic overflow, drift from either admitted
observed_result, missing/extra keys or rows, reused capability identity, a timeout,
failed join or any failed child rejects the entire store CTest and retains records.


## Proposed bounded logical fault evidence amendment

This separate proposed amendment requires checked merge and adoption before
consumers. It preserves the checked remaining-row definitions without changing
their fixed IDs/receipts/limits. See the exact finite cases
and permanent physical-failure exclusions in
[the scheduler](test-scheduler-v1.md#proposed-bounded-logical-fault-qualification).
No consumer or execution result is published by this amendment.

Only the existing first local_players_store child gains the two already-permitted
actual selected SQLite interruption cases and one newly permitted, source-fixed
synthetic export-flush stage refusal. This is one narrow exception to the prior
no-result-substitution seam: it bypasses ONLY the selected export flush operation
and takes the existing file_flush_failed stage path, explicitly as synthetic.
It does not supply a fabricated BOOL/DWORD or actual-OS-return claim. No new
production DTO/error/receipt/API, VFS, environment switch, generic action,
ClassDB method, actor, target or source path is allocated. The one-shot native
observer method `take_export_flush_refusal_request() noexcept -> bool`, with
default false, is consumed only under an admitted isolated capability and
exact selected source-bound native context. A null production observer always
takes the existing actual FlushFileBuffers path. Existing test-only observer
implementations/factories remain absent shipping compile/link/registration.

The original eight first-child case IDs, original Service prefix0..15, descriptor,
six-key NativeTestPlan, executable/role/store CLI and existing aggregate stdout
receipt remain. Append six Service offsets16..21 for the two SQL cases; the
synthetic flush case reuses the existing first Service. Second-child17 IDs,
31 lifetimes/offsets0..30, exact second receipt and two-child store rollup remain
byte-semantically unchanged. Original first-child checks include all three new
cases; no separately added observer record is hidden outside its16,384 ceiling.

Only the synthetic flush case adds reporting: the first child emits exactly one
closed JSON provenance line before its existing final summary. It has exactly
ten keys: `schema`, `pid`, `nonce`, `descriptor_sha256`, `plan_sha256`,
`selector`, `consumed_once`, `operation_attempted`, `classification`,
`win32_error`. Schema is `LocalPlayersSyntheticExportFlushEvidence/v1`; pid is
the actual observed positive child PID, nonce and input digests match the same
Root capability/context. Selector has exactly seven keys
`service_ordinal`, `request_ordinal`, `kind`, `scope`, `phase`, `edge`,
`occurrence`, with the positive numeric ordinals and closed enums fixed by
source/plan before compilation as the scheduler requires. consumed_once is
actual BOOLtrue, operation_attempted is BOOLfalse, classification is exactly
`synthetic_export_flush_refusal` and win32_error is null. Missing/extra/duplicate
fields, multiple evidence lines or different stdout/PID/input bindings fail.
The two already-permitted actual SQLite cases retain their source-bound actual
result/state/reconciliation assertions and existing aggregate evidence; no new
SQL return schema or redundant count rollup is introduced.

The synthetic terminal is failed/file_flush_failed. Its exact selected stage's
before/after observations have null error because no OS flush was attempted,
with actual temp ownership and existing fields otherwise unchanged. No other
ordinary after-event rule is relaxed. Full actual writes/temp retention, no
verify/move, unchanged DB, ready state, credit/ACK/join and actual unarmed retry
must be source-bound assertions and checked saved witnesses, not inferred from
this provenance line alone. Refusal is consumed once only on its worker.

Before execution, source review freezes the complete auxiliary receipt parser,
ordinary event grammar exception at this exact selector only, all phase/SQL/
ownership/reconciliation predicates, exact selector numbers and total conditional
event pre-count. Root authorizes the fresh same-source native stage after measured
build review; all raw failures remain. No future success/hash is invented here.

Bounded acceptance is actual API-non-success handling plus labelled synthetic
export-flush error propagation through real previously written/retained effects.
Physical rollback IO failure, observed FlushFileBuffers(false), disk-full/device
faults and power-loss durability remain permanently unclaimed. Catastrophic
engine/OS OOM stays excluded by the reservation contract; native T/D ownership
and normal poll transfer remain distinct existing tests. Installed #220 player
journeys and broad persistence/phase/pilot acceptance remain separate.

For the unchanged atomic delivery requirement, bounded #219 evidence requires
source-reviewed pre-ACK guard ordering, actual two-result complete FIFO caller-copy
transfer surviving a later poll, and existing native whole-batch abandon/repeek/
ACK ownership tests. Actual recoverable Godot output-construction-failure execution
remains unqualified; these tests do not certify it or prove the state unreachable.
No new engine allocator fault fixture is required by this bounded disposition.
Public behavior still forbids removing any terminal before successful whole-batch
caller construction. Only the already accepted catastrophic engine/OS OOM exclusion
applies; native T/D refusal cannot masquerade as an observed engine failure.
