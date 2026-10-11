# Local players: closed service protocol v1

Original MIT. **PROPOSED**, normative only after checked [ADR026](../../decisions/026-durable-local-players-and-practice-history.md) acceptance. Every dictionary has exactly the listed actual
String keys, no StringName or coercion. Every array/count/type/Unicode/cap checked
at the DIRECT ClassDB boundary before queue/root/DB mutation, not merely by UI.
The worker receives owned native DTOs and bounded canonical bytes, never Godot
objects, Callable or Variant. It repeats pure record/hash/cross-column validation.

## Object, admission and owner lifetime

`LocalPlayers` is owner-thread constructed. `start()` and `submit(Variant)` return
exact `{accepted:bool,error_code:String,request_id:String|null}`. Accepted means
copied+reserved, never saved. Rejection has false/nonemptycode/null ID and leaves
all prior state/queue/results unchanged. Accepted has true/emptycode/32hex ID.
start is kind=start, no payload; new->opening only once per object. Alternative
`start_management()` has the same Admission shape and kind=start_management,
only from new, owner-thread, no arguments. It resolves/owns the same fixed root
and lock but NEVER opens SQLite. Successful result is read/null sequence with
exact value {management_only:true}; state becomes unavailable with error_code=""
and store_version=null, writer_alive=true. Only recovery list/delete and close
are admitted. Explicit joined close and a NEW ordinary service are required to
try database qualification afterward; no in-place mode switch. No root
resolution/allocation on invalid state/thread. `submit` exact `{kind,payload}`.

`poll(max_results:int=8)->Array|null`: actual INT1..16, null on wrong thread/type/
range, zero drain/mutation; otherwise up to that many owned terminal results FIFO.
`status()->Dictionary|null`: null foreign thread. Owned result exactly
`{state,error_code,pending,undelivered,writer_alive,resolved_root,store_version}`.
states new/opening/ready/closing/closed/read_only/unavailable; counts INT0..16;
pending+undelivered<=16 always; pending includes queued and actual in-flight.
root null or actual qualified absolute String; version null or INT1. No mutable
internal collection escapes. `begin_shutdown()->bool`: false wrong thread;
owner true idempotently closes admission and drains accepted FIFO jobs.
`try_join()->bool`: false wrong thread or still alive; true ONLY actual thread
exit+join, DB/statements closed, all handles released. No detach/kill-as-join.

Reserve a terminal slot and bounded request/result capacity atomically at
admission. At most16 accepted not-yet-polled requests INCLUDING undelivered.
Total owned buffers<=32MiB; max individual request/result640KiB. Admission may
fail out_of_memory/queue_full before side effects. Per-slot fixed-size minimal
failure receipt storage is reserved BEFORE BEGIN or export IO; maximum successful
result space is accounted for. Terminal acknowledgement construction cannot
retroactively turn a possibly committed job into failed. Jobs stay FIFO and
cannot cancel after admission; UI may discard a stale owned result only after
poll, never deny an actual commit. In-process worker exception caught by its
outer owner records remaining accepted slots in order; known unstarted jobs
failed/worker_lost; possibly in-flight DB MUTATION uncertain/commit_unknown,
read-only query failed/worker_lost, export/delete use their observed file-specific
values. If OS
thread is genuinely stuck, no terminal result or joined=true is fabricated;
status remains closing/read_only with reserved slots until observed exit.

## Shared Result and exact operation values

Every Result exactly `{request_id,kind,state,error_code,commit_sequence,value}`.
request_id exact admitted ID. DB states: read/committed/no_change/failed/uncertain.
read/failed/uncertain have commit_sequence=null; committed actual new canonical
U64 sequence; no_change current acknowledged row sequence (player operations
use the player stored latest sequence defined below). First3 error_code="";
failed/uncertain fixed nonempty error. DB failed/uncertain value=null, successful
value exactly table. Export additionally has recovery_required and a closed
ExportFileReceipt even on failed/recovery_required, never DB sequence. Recovery
copy deletion has its own closed deletion value after file actions, no DB sequence
and no fabricated commit. Only these two file kinds have nonnull failure values.

|kind|exact payload|successful value|legal success states|
|---|---|---|---|
|start|no payload / start() only|{store_version:1,interrupted_rows:int0..1,created:bool}|read,committed|
|start_management|no payload / start_management() only|{management_only:true}|read|
|list_players|{}|{players:Array[{id,name,revision}]}<=8|read|
|create_player|{id,name,utc}|{player,preferences}|committed,no_change|
|load_player|{player_id}|{player,preferences}|read|
|rename_player|{player_id,expected_revision,name,utc}|{player,preferences}|committed,no_change|
|save_preferences|{player_id,expected_revision,seed,utc}|{player,preferences}|committed,no_change|
|begin_practice|{seed}|{practice}|committed,no_change|
|observe_practice|{practice_id,player_id,expected_revision,expected_source,last_tick,utc}|{practice}|committed,no_change|
|end_practice|{practice_id,player_id,expected_revision,expected_source,last_tick,utc,status,end_reason}|{practice}|committed,no_change|
|link_archive|{practice_id,player_id,expected_revision,expected_source,archive}|{practice}|committed,no_change|
|list_practice|{player_id,before_creation_sequence,limit}|{practice:Array[PracticeSummary],next_before_creation_sequence:String|null}|read|
|load_practice|{player_id,practice_id}|{practice}|read|
|prune_practice|{player_id,practice_ids}|{deleted_ids:Array[String]}|committed|
|delete_player|{player_id,expected_revision}|{deleted_player_id:String}|committed|
|export_player|{player_id,expected_revision,target_absolute_path}|ExportFileReceipt|read|
|list_recovery|{}|{snapshots:Array[RecoverySummary]}<=2|read|
|delete_recovery|{snapshot_ids:Array[String]}1..2|{deleted_ids:Array[String],retained_ids:Array[String]}|read|

Player/Preferences share ONE revision: both start"1"; successful rename OR
preference change increments both atomically. Rename returns updated preferences
revision although options stay bit-identical. Save seed exact
`{legacy_input,piston_input,audio}`; there is NO embedded ID/revision to disagree
with expected_revision. Worker assigns ID/revision/version/type and timestamps.
Each player also has a DB latest commit_sequence (not an added Player/v1 field).
Creation stores it; rename/save update it; current no_change result returns it.

BeginPracticeSeed exact `{id,player_id,source,started_utc,first_tick}`. No caller
revision/status/last_tick/counters/sequence/archive accepted. Repository supplies
active/null, last_tick=first_tick, observed_ticks="0", last_observed_utc=started_utc,
revision="1", creation_sequence=commit_sequence=next global sequence, archive=null,
type/version/tick_rate_hz exactly current Practice/v1. Duplicate ID returns
no_change ONLY if initial seed tuple exactly matches immutable existing seed;
return current existing Practice, without resetting progressed/terminal fields.
Different tuple=>identity_conflict. A source fingerprint/session pair already
owned by another ID/player=>identity_conflict, even if same source shape.

Expected revision is always compared BEFORE ordinary equality/no_change tests.
Stale exact preference retry=>revision_conflict, not a silent success. Explicit
load/reconcile then retry current revision can return no_change. Create duplicate
ID no_change only same name+creation UTC+initial default bundle and still initial
revision; otherwise identity_conflict. Initial Audio is exactly enabled=true,
engine_gain=FLOAT1.0,airflow_gain=FLOAT1.0,show_panel_captions=true, both preset
slots null. No guessed current device/preset is captured on creation.
Rename same name/save same normalized bits
return no_change preserving timestamps/revision/counters. Observe equal tick
no_change preserving UTC. End same terminal/status/reason/tick returns no_change
only current expected revision/source. Terminal different value=>invalid_transition.
Link exact existing archive no_change; replacement otherwise increments only
Practice revision/commit sequence, never its immutable creation sequence.
No implicit retry ledger across process death; reconciled reads are required.

delete_recovery reports read only if ALL requested sets were removed and
retained_ids empty. After partial filesystem effects it reports failed with
snapshot_failed and this same closed actual deleted/retained value, disjoint
arrays whose union is EXACT requested IDs. Failure before any validated file
action has null value. File deletion uncertainty alone never sets DB read_only;
retained means not proved completely deleted, never guessed absent.

expected_source is a complete exact PracticeSource/v1, compared to immutable
source BEFORE tick/state mutation even on a potential no_change. Native worker
does not query flight. Observe/end/link require original player ID and source;
wrong ID=>not_found or source_mismatch without revealing another player's row.
Observe/end new tick cannot regress; exact subtraction produces observed_ticks.
Only active rows advance. User end statuses limited to manually_ended reasons
user_end/user_restart/user_quit, or source_ended/native_terminal. Interrupted is
startup-only, never accepted from a UI end job. Adapter requires real matching
joined lifecycle for terminal status; valid shape alone is not native evidence.
observe_practice requires active even at equal tick; equal-tick no_change applies
only while active. End retry alone can acknowledge identical terminal content.
link_archive permits active or terminal owned rows with fully matching saved
recording source/receipt and explicit replacement choice; never changes ticks.

Native service has one trusted process-lifetime32hex run ID, generated once by
native process initialization, shared across its service objects/reopens, never
accepted from request/CLI/environment/Godot caller. It is private meta.owner_run_id,
never exported or substituted for actual native session/source. begin_practice
stamps this run ID in its SAME transaction. Reopen in SAME process preserves
active rows pending source/receipt reconciliation. DIFFERENT process with active
rows converts them interrupted in one recovery transaction and stamps current run
ID. Clean open with no active rows need not update the stamp, so remains read.
No native session is invented or closed by comparing this bookkeeping value.
It is the last active-practice owner stamp, not the current SQLite/file-lock
holder, and can remain older when no active practice exists.
Same-process reconciliation requires the coordinator's ACTUAL retained active
binding (practice ID, player ID and full immutable PracticeSource), plus a newly
qualified Readback from that exact still-owned session, or the actual joined
terminal lifecycle evidence for that binding. The database/run ID cannot create
this binding, select a replacement source or prove a new flight. Missing binding,
foreign/unavailable source or uncertain close leaves the stored row unavailable
and unchanged; no observe/end is synthesized from DB contents. Explicit ordinary
application shutdown/relaunch can subsequently apply previous-process recovery.

Cursor null or canonicalU64; limit actual INT1..50. Order creation_sequence by
length DESC then BINARY digits DESC. Strict < cursor by this SAME ordering.
next_before_creation_sequence is last returned row's creation sequence ONLY
when more owned rows exist in that read snapshot, else null. No mutable commit
cursor. Pages use fresh read snapshots, so insertions newer than cursor do not
reappear and deletions can shorten a later page. Summary exact Practice fields
except archive replaced by `{linked:bool}`, no absolute path. Practice full load
checks ownership; external files are not touched by query. Prune accepts1..50
unique IDs, every row must exist/owned/terminal; all-or-nothing, unknown=>not_found.

Every changing transaction prechecks ALL needed U64 increments and quotas before
SQL writes; begin also checks sole-active and creation uniqueness. Reserve one
global sequence for a changing transaction; startup interruption changes the
sole active row if any, with that new sequence and next row revision. Creation
sequences remain unique. Counter exhaustion leaves DB unchanged; reads/export
remain possible. Initial store creation consumes sequence"1"; existing clean
open is read/null; interruption recovery consumes one next sequence only if
rows actually changed. No dummy export COMMIT. Success committed requires actual
COMMIT and postcommit owned row/counter readback; checkpoint errors are separate.

Qualification cross-checks meta singleton1, exactly one preferences row per
player, equal player/preferences revisions, counts<=8/2000 and sole active row.
Every current row's creation<=latest commit<=meta sequence and positive revision;
all comparisons are canonical U64 length+digits. Player latest sequence<=meta.
Preference/Player record IDs/revisions and every indexed practice field equal
fully decoded blobs. Referential, hash and SQLite constraints complement, never
replace, full closed semantic validation. Update ACK establishes the next expected
revision; terminal requests wait for outstanding begin/observe receipts before
submission. A conflicting/uncertain ACK requires explicit read reconciliation,
not guessing a revision or automatically replaying a potentially committed end.

## Error and state grammar

Admission errors exactly wrong_thread,invalid_state,invalid_request,invalid_type,
invalid_record,payload_limit,queue_full,out_of_memory. No SQL/root IO on malformed
input. Accepted terminal DB errors exactly not_found,identity_conflict,
revision_conflict,source_mismatch,tick_regression,invalid_transition,player_limit,
history_limit,active_practice,counter_exhausted,store_locked,root_unavailable,
unsupported_version,foreign_store,corrupt_store,recovery_required,recovery_limit,
snapshot_failed,storage_full,busy,io_error,worker_lost,commit_unknown,verification_failed.
All mutation kinds may fail semantic/capacity/storage checks with null value.
Only possibly begun MUTATIONS/start creation or recovery can be uncertain;
read-only query failure is failed/io_error unless it uncovers an already unknown
DB state. uncertain error exactly commit_unknown or verification_failed; service
enters read_only and refuses new DB writes until joined close/reopen/reconciliation.
No misleading rollback claim from sqlite3_txn_state alone. In a caught failure
BEFORE BEGIN=>failed; after BEGIN with observed successful ROLLBACK, autocommit=1
and txn_state NONE=>failed; COMMIT-success-but-postverify/receipt-loss or failed
rollback/unknown COMMIT=>uncertain even if autocommit1. Preserve extended SQLite
code internally with phase, not names/values/SQL in logs.

Ready allows DB jobs and list_recovery; delete_recovery requires management-only
start with NO live SQLite connection. read_only allows validated reads/export only if a qualified
consistent snapshot can actually be established; corrupt/newer never gets guessed
row reads. unavailable permits list_recovery when root+lock acquired and
delete_recovery ONLY for management-only start with no SQLite connection; all
other jobs refuse. closing/new/opening/closed refuse submit.
Delete recovery never changes readiness; close/reopen is explicit after freeing
capacity. Each code maps to stable player-facing text; bounded diagnostics never
include names/config/ticks/path/SQL automatically. Path visible only in requested
storage/export recovery details. Unknown code/state/value shape is rejection.

## ExportFileReceipt and independent file uncertainty

Exact value `{operation_id,outcome,phase,target_absolute_path,temporary_absolute_path,
installed,bytes,sha256,player_id,preferences_revision,practice_count}`.
operation_id=request ID; player/revision actual read snapshot; count INT0..2000.
player_id/preferences_revision/practice_count are null until a consistent,
revision-matched selected-player snapshot is actually established; then exact
ID/canonical revision/count. A not_found/revision_conflict read error does not
invent these values. Target remains the exact admitted selected output path.
phase exactly read,encode,create,write,flush,verify_temp,move,verify_target,done.
outcome exactly saved,not_saved,recovery_required. installed false before Move,
true after observed successful Move, null if attempted Move result is unknown.
Target is the admitted explicit selected path only; temporary null until actual
owned CreateNew succeeds, then exact observed path. bytes/sha null until actual
complete owned file read verifies intended bytes/hash, then actual values.
No arbitrary or invented recovery path. Success state=read/error=""/sequence=null,
saved/done/installed=true/temp=null and target byte verification required.
Known before Move failure state=failed/nonemptyfilecode/not_saved; retain actual
owned temp path if still observed. Attempted Move error or postmove lost/invalid
verification=>state=recovery_required/error=file_recovery_required, no DB write
disable by this alone. Known moved target stays in receipt; never delete/retry
overwrite. DB snapshot read error failed/value ExportFileReceipt phase read,
installed=false/bytes/sha/temp null; unknown DB state separately marks read_only.
Filecodes exactly target_exists,path_rejected,file_create_failed,file_write_failed,
file_flush_failed,file_verify_failed,file_recovery_required. Known DB read failures
use not_found/revision_conflict/busy/io_error/corrupt_store as applicable, with
phase read and this same closed observed export value; never a null recovery value.

Encode a consistent selected-player read snapshot into public-safe UTF8 envelope
`{format:"LocalPlayerSummary",version:1,payload_json,payload_sha256}`. Payload
exact `{player,preferences,practice}` using same lossless numeric tags, PracticeSummary
without archive paths. No local root/Windows SID/logs/crashdump/hidden profile.
Export size<=32MiB, streamed by sole writer; read transaction released AFTER
stable bounded owned export snapshot spool is complete and BEFORE target IO.
Only explicit new selected output; no import/autosave/overwrite.
Target must be outside the entire protected Players root, including recovery,
DB/lock and side files; reject observed aliases/reparses and use the current
selected-file stable-parent/no-overwrite policy. Tests use a sibling exports
directory within Root's disposable run parent, never the protected store root.
CreateNew owned
same-directory .fsplayers-32hex.tmp, write/FlushFileBuffers, full verify, no-replace
same-volume MoveFileExW flags0, then full target verify+observed actor exit if a
helper is used. Stable-parent/nonadversarial-path assumption and collision
guarantee stated separately; no cross-resource DB/file atomicity or universal
rename power-loss guarantee. Exact output writer/helper closure must receive
independent source audit before implementation execution.


## Exact type/domain and per-kind terminal failure matrix

All IDs32lowerhex; expected_revision canonical NONZERO U64; tick/cursors canonical
U64 (zero allowed). UTC follows the exact Gregorian rule in [records and lifetimes](records-and-lifetimes-v1.md). actual
INT means never bool/FLOAT; count limits apply before array iteration/allocation.
Name/source/archive/seed are exactly the closed records in [records and lifetimes](records-and-lifetimes-v1.md); no aliases.
Each resulting Player/Preferences/Practice version is INT1, rate INT120. All other
record numeric counters are canonical decimal String, no absolute float cast.

PracticeSource.model_identity has exactly id/version/backend_model actual Strings,
the two original model triples bound in current InputPreset/Facade. session_id is
the existing canonical Wire identifier grammar (ASCII lowercase leading letter,
lowercase letters/digits/single ._- separators, no trailing separator),1..128.
source_variant is one of ADR016's four closed source IDs; hashes64lowerhex;
named_start one of ground-ready/airborne-prepared/piston-cold-ground, wind_profile
one of calm/from-north/from-west/from-east. Method null for original-interactive;
event_aware_constant_power_v1 for piston with jsbsim-1.3.1-event-aware-constant-power-v1;
event_aware_coupled_midpoint_v1 for piston with the ADR016 coupled-midpoint-v1 or
coupled-midpoint-local-window-v2 source variant. Upstream has no adopted piston
history in this slice. Original-interactive admits either legacy named start and
any of those winds under all four source variants; piston requires cold+calm. Source
tuple semantic start/wind/model/method compatibility is exactly the adopted
accepted facade closure, never a shape-only grant. Historical stored source uses
these SAME closed v1 rules, with no equality to today's installed binary/hash.

The following fixed semantic codes are allowed per kind. All DB-access kinds
add busy/storage_full/io_error/corrupt_store/worker_lost; storage_full for a read
means actual bounded work/snapshot allocation failure, never row mutation. Only
mutation kinds add commit_unknown/verification_failed as uncertain. Invalid
request shapes/caps/thread reject at admission, not here. No free-text code.

|kind|additional allowed failure codes|
|---|---|
|start|store_locked,root_unavailable,foreign_store,unsupported_version,recovery_required,recovery_limit,snapshot_failed,counter_exhausted|
|start_management|store_locked,root_unavailable,recovery_limit,snapshot_failed,io_error,worker_lost; no SQLite access|
|list_players|none|
|create_player|identity_conflict,player_limit,counter_exhausted|
|load_player|not_found|
|rename_player,save_preferences|not_found,revision_conflict,counter_exhausted|
|begin_practice|not_found,identity_conflict,active_practice,history_limit,counter_exhausted|
|observe_practice,end_practice|not_found,revision_conflict,source_mismatch,tick_regression,invalid_transition,counter_exhausted|
|link_archive|not_found,revision_conflict,source_mismatch,invalid_transition,counter_exhausted|
|list_practice,load_practice|not_found|
|prune_practice|not_found,active_practice,counter_exhausted|
|delete_player|not_found,revision_conflict,active_practice,counter_exhausted|
|export_player|not_found,revision_conflict,all fixed filecodes; no uncertain DB mutation state|
|list_recovery,delete_recovery|root_unavailable,snapshot_failed,recovery_limit,io_error; no SQLite access|

Result value on failed/uncertain is null except export ALWAYS observed closed file
receipt and delete_recovery AFTER validated file actions the actual deletion value.
Unknown worker death during export returns recovery_required with only already
observed paths/fields; no invented target absence, no DB write disable by itself.
Unknown worker death during delete returns failed/snapshot_failed with retained
every ID not proved removed; no fake DB COMMIT. Reserved minimal receipts cover
these kind-specific observed fields. Full raw OS errors stay bounded/private only.

## Prospective ADR027 closed source-domain amendment

PROPOSED, effective only after checked [ADR027](../../decisions/027-synthetic-taxi-navigation.md) acceptance. Its exact two new Source pairs extend the existing named_start enumeration without changing eight-key DTO, SQL/codec/schema fingerprints. Legacy apron-ready requires calm/null method/original legacy model; piston-cold-apron requires calm/event_aware_coupled_midpoint_v1/jsbsim-1.3.1-event-aware-coupled-midpoint-local-window-v2/original piston model. Existing cold-ground historical variants and all old Source fixtures remain accepted unchanged. Current source adoption still requires the actual reviewed first-party recipe closure and complete native Readback; history uses these closed semantics without equality to today's installed hash. Changed normative inputs require new source/CI/component binding, even though DDL/codec bytes stay exact. No physics resume, profile/source relabel or older-reader universal compatibility claim.
