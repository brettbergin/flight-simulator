# Local players: records, storage policy and UI lifetimes v1

Status: **PROPOSED** normative companion to [ADR026](../../decisions/026-durable-local-players-and-practice-history.md). Normative only after the checked contract PR merges; no consumer or runtime acceptance is implied. This is a bounded child of [LOCAL-PERSISTENCE #34](https://github.com/brettbergin/flight-simulator/issues/34) and [PROFILE-SESSION-UI #74](https://github.com/brettbergin/flight-simulator/issues/74), not parent or phase closure. Original MIT. Design limits are proposed bounds, not measured performance.

## Outcome and unchanged authority

Two named local players and Guest can use the existing original simulator. Named players explicitly save their separate Controls and Audio preferences, restart the executable, deliberately select themselves and find both preferences and a truthful practice history. History includes interrupted attempts and optional links to explicitly saved recorded reviews. Players can export their own bounded data and delete it without deleting another player's data or external recordings.

There is no account/network, achievement, evaluator, official flying time, aircraft procedure, automatic scoring, live-flight restore or automatic recording save. History is not a ReplayHeader, Checkpoint, SessionManifest or resumable flight. The existing fourteen public wire formats, native flight commands, models, numerical budgets, ADR011 recordings and ADR012 interchange remain unchanged. SaveProof17 remains the original fixed120Hz flight-only same-build reconstruction experiment; it does not prove this store, current piston/contact resume, migrations or arbitrary application restoration.

ADR004 already chooses SQLite3.53.4 C API, one asynchronous writer, LocalAppData/FlightSimulator, WAL, transactional receipts and backed-up migrations. This proposal supplies missing internal records, service protocol and UI lifetimes. It is not a choice of a second persistence architecture. New internal `schemas/save/local-players/v1/` fixtures must be explicitly separate from the fourteen wire schema registry entries.

## Proposed limits and scalar rules

| Item | v1 choice |
|---|---|
| Durable players | 8 maximum; Guest is not a database row |
| Display name | 1–40 Unicode scalars, at most160 UTF8 bytes; well-formed Unicode; no NUL/C0/DEL, leading/trailing whitespace or all-whitespace value |
| Identity | newly generated32 lowercase hexadecimal characters; never name, path, Windows SID or native session ID |
| Preferences | one revisioned bundle per player; two preset slots, each null or a complete validated preset for its exact original aircraft profile |
| Input payload | existing accepted decoded64KiB bound; proposed lossless storage encoding at most256KiB per slot |
| Bundle | at most600KiB encoded; only accepted v1/v2 presets plus four Audio options |
| Practice rows | 2,000 total across store; at most8KiB per compact row including at most one external archive link |
| Queries | page at most50 summaries, up to400KiB result; no unbounded UI query |
| Work | at most16 outstanding requests, including undelivered results; request/result at most640KiB each; explicit32MiB total service-owned live-buffer ceiling |
| Store | main database at most256MiB; page limit checked; WAL independently checked at32MiB soft high-water; no claim of hard total filesystem bound during transactions/recovery |
| Export | selected player's data only, at most32MiB; streamed by writer, not returned through the640KiB bridge |
| Diagnostics | fixed code plus bounded1024-scalar message; no SQL parameters, names, device metadata, paths or practice rows in routine logs |
| Busy | SQLite busy wait2,000ms; bounded application retry at most once only for operations proved not begun; no automatic retry of uncertain commit |
| Save scheduling | periodic summary no more often than120 additional observed simulation ticks; no per-render write; native runtime currently120Hz |

All Dictionaries are closed with actual String keys; bool is never int, StringName is never String. Numbers are checked at admission and decode. Unsigned tick/revision/commit sequence values are canonical decimal Strings in0..18446744073709551615, with exact bounded string arithmetic; never absolute float, SQLite INTEGER cast or lexicographic-only sorting. SQLite integer leaves are genuinely bounded signed integers (versions, rate120, bool0/1); binary64 scalar leaves are finite and stored as exactly eight little-endian bytes. Signed zero survives preferences encoding. Strings preserve scalar sequence; no silent Unicode normalization/case folding. Duplicate display names are allowed because opaque IDs are authoritative; chooser also shows a short ID suffix so two identical names are distinguishable.

UTC labels use exactly `YYYY-MM-DDTHH:MM:SSZ`, years2000..9999, valid Gregorian dates, from the platform clock. They are labelled local-computer dates, not authoritative duration or ordering. Backward wall-clock changes do not reject a valid practice or reorder its observation sequence. Exact commit sequence and tick arithmetic determine order. No filesystem path is derived from a display name.

## Closed internal records

The following describe owned service values, not a permissive arbitrary settings map. Every listed version is integer1. Optional fields are present and null, never missing. Existing preset/model/source validators retain their exact duties; no normalization repairs unsupported content.

**Player/v1**, exactly `{type,version,id,name,created_utc,updated_utc,revision}`. `type="LocalPlayer"`; ID/name/time follow above; revision starts"1" and is shared with PlayerPreferences: successful rename OR preference replacement increments both atomically, never on reads. A result also returns the relevant committed revision; rejected stale expected revisions preserve all previous values.

**PlayerPreferences/v1**, exactly `{type,version,player_id,revision,legacy_input,piston_input,audio}`. `type="LocalPlayerPreferences"`; initial revision"1"; both input slots initially null. `legacy_input` is accepted InputPreset/v1 for original-interactive-prototype; `piston_input` is accepted InputPreset/v2 with exact original-piston capability. A malformed/unsupported stored current-schema preset fails whole-store qualification without silently loaded defaults. A semantically valid preset with an absent device remains a valid bundle with an explicit device-unavailable hint and normal runtime release/takeover gates. Audio is the exact ADR020 four-key AudioOptions value. Null slot means use that profile's existing default when explicitly starting it; it is shown as Default, not a secretly saved custom binding. Saving a bundle is one atomic transaction, not independently successful sliders/axes.

For exact durable type/bit preservation, the separate proposed **PreferencesStorage/v1 codec** is frozen in [preferences-codec-v1.json](../../../schemas/save/local-players/v1/preferences-codec-v1.json): existing closed preset structure, integer-only protocol/enumeration leaves normalized by the accepted preset validators, and binary64 tags only at the explicitly enumerated real-valued preset calibration/rate/fixed-axis and Audio gain positions. Continuous preset positions preserve the accepted INT/FLOAT branch exactly; FLOAT values use tags, INT values canonical integer tokens. Only integer enum/index/key/button positions normalize to INT exactly as existing validators. Audio gains remain actual FLOAT. The source-independent numeric-path audit is bound as review input; no silent numeric-type migration is authorized. Tags use ADR012's exact eight-byte little-endian lowercase encoding, but this is NOT an ObservedFlightReview envelope or extension. Unknown/misplaced tags reject. Strings use strict Unicode and duplicate-key checks; reuse reviewed strict scanner/scalar code where compatible, not a new general JSON grammar. Native worker receives/returns owned byte blobs; main-thread adapter validates full restored presets/Audio again. Canonical UTF8 encoded payload and SHA256 are stored together and checked on reads. The exhaustive numeric-path table and design examples are companion contract inputs; independent accepted encode/decode references remain a prerequisite before consumer outputs. Do not store Godot Variant object serialization as an upgrade-stable format, or use NativeWireDecoder for preferences: it intentionally returns float for all native JSON numbers.

**PracticeSource/v1**, exactly `{session_id,model_identity,source_variant,native_source_fingerprint,prepared_world_sha256,named_start,wind_profile,angular_integration_method}`. `model_identity` is the exact three-key source model dictionary; known original combinations match the current adopted facade, including supported starts/wind/method. Source variant and fingerprint come from actual reviewed loaded-source closure; no caller-invented authority from matching dictionary shape. All hashes are64 lowercase hex; method is actual String or null under the accepted identity rule. History preserves this admitted source snapshot after updates; later content missing/uninstalled does not erase a compact old summary. Reader validates the current closed PracticeSource/v1 structure, without requiring its historical fingerprint equal today's binary. There is no unsupported future descriptor/version envelope in v1; malformed or extra fields fail whole-store qualification. It never upgrades that old descriptor into current authority.

**Practice/v1**, exactly `{type,version,id,player_id,source,started_utc,last_observed_utc,first_tick,last_tick,observed_ticks,tick_rate_hz,status,end_reason,revision,creation_sequence,commit_sequence,archive}`. `type="LocalPractice"`; tick_rate_hz integer120; first/last/observed_ticks are canonical unsigned decimal strings, `observed_ticks=last_tick-first_tick` exactly. This is an endpoint-bounded simulation interval, not proof every intervening tick was individually observed. Duration is derived for display from this bounded difference; no wall time, paused time or official pilot-hour counter. No summing rounded displayed durations. `status` is exactly `active`, `manually_ended`, `source_ended`, `interrupted`; `end_reason` is respectively null, `user_end|user_restart|user_quit`, `native_terminal`, or `previous_process_incomplete`. No `passed`, `landed` or `completed_lesson`. `revision` advances only when durable content changes; creation_sequence is the immutable actual begin transaction's sequence, while commit_sequence is the latest changing transaction's sequence. `archive` null or ArchiveLink/v1 below. Native fault details are not free-text flight logs in this compact table.

**ArchiveLink/v1**, exactly `{type,version,absolute_path,payload_sha256,recording_session_id,first_tick,last_tick,linked_utc}`. `type="ExternalRecordedReview"`; path at most4096UTF8 bytes, admitted by current explicit local-file path policy; every identity/tick/hash must match the fully decoded successful Save receipt and the current practice source. First/last are bounds of that recording, not necessarily whole practice duration. This link proves an operation witnessed at association time, not continued existence or authenticity of today's path. Link replacement requires explicit user choice and expected practice revision. Imported/Open historical data is not a new practice; linking an unrelated historical recording to an existing practice rejects. External links are NEVER opened, statted or hashed during routine list/history queries; explicit Open goes through existing ADR012 full validation, with changed/missing contents unavailable. No arbitrary path execution.

## Normative companion allocation

[service protocol](protocol-v1.md) is normative for exact admission/result/error/state/seed/revision/
no_change/cursor/source/export grammar; [preferences codec](../../../schemas/save/local-players/v1/preferences-codec-v1.json) freezes every
numeric path and serialization limit; [schema-v1.sql](../../../schemas/save/local-players/v1/schema-v1.sql) is exact proposed DDL.
These are PROPOSED contract artifacts, not implemented code or schema
acceptance. Application ID is fixed0x46535031 (FSP1), private not registered;
user_version1, new page_size4096 and max_page_count65536. [schema binding](../../../schemas/save/local-players/v1/schema-binding-v1.json)
binds exact LF DDL/codec bytes and fingerprint recipe. Worker/bridge must validate
record blobs fully and equality to duplicated indexed columns. Hash matches alone
never establish semantic validity, native authority or source qualification.

At most one active row globally. Actual flight can continue if storage fails;
new history remains Not saved until old active row is reconciled/ended. Never
fabricate an end to free the slot. FIFO jobs cannot be canceled after admission.
Adapter coalesces only unsent latest qualified observation; no accepted job is
silently lost. Periodic update at least120 additional ticks, terminal boundary
can use same/later actual qualified tick. Worker does not query simulation.
Full expected_source is carried on observe/end/link, and must equal begin source.
Main-thread adapter independently qualifies adopted full Readback before any
begin/progress/end/link. Metadata shape never proves flight origin.

## Root ownership, filesystem and test isolation

Production root resolution is native `SHGetKnownFolderPath(FOLDERID_LocalAppData,0,nullptr,...)`, checked HRESULT and freed returned memory, then fixed child `FlightSimulator/Players`. Database is `players.sqlite3`; ownership file `players.lock`; owned backups and export temporaries have fixed generated names. No install directory, `user://`, `%APPDATA%` expansion, current directory, path supplied by a preset, saved root preference or environment override is accepted. A failed resolver leaves Guest usable and named storage unavailable; no fallback writes elsewhere. This extends ADR004's fixed app root with a private subdirectory; existing explicit archive/preset interchange outside it is unchanged.

Obtain exclusive OS file ownership before SQLite opening; file opened without sharing for the lifetime of service, with process-crash release supplied by the OS. Existence/PID/lease-file text alone is not a lock. Second process refuses named-store writes and does not touch .db/WAL/SHM, migrate or mark active rows interrupted. Guest can run separately. Require a local supported Windows filesystem for v1; network/UNC roots unsupported. Inspect root and owned-file components for reparses, reject observed reparse/file aliases. State stable-parent assumption; do not claim hostile TOCTOU protection from path inspection. Native handle-relative implementation/platform audit must validate actual policy before consumers.

**No tests may open the product store.** Split (a) pure root composition and (b) native Known Folder query from (c) repository opening. Product bridge exposes no test-root/CLI/env override. A separate test-only native executable invokes the SAME repository core with a `TestRootCapability` created only by the harness; that symbol/factory is absent from shipping ClassDB/bridge. The capability binds an absolute existing fresh directory, a random run nonce, sentinel bytes and canonical parent identity selected by Root. Repository validates it before worker/SQLite/path creation. Test adapter has no fallback to Known Folder. Tests fail closed if capability/parent is missing, path equals/is ancestor/descendant of actual product root, reparse, drive root, workspace source root, or lacks exact sentinel. Never use a substring prefix as a containment check.

Root chooses a fresh UUID directory under a declared private proof parent (workspace .local or OS cache, verified absolute physical path) and owns cleanup. Test subprocesses get only its closed capability descriptor; invalid descriptor must cause zero calls to production resolver/open. Cleanup closes/join-observes children, revalidates same root/nonce/final canonical containment, and removes only the run directory. Unknown/changed sentinel/path causes retained evidence and no recursive delete. Export/missing-archive fixtures live under that root too. Injected fault hooks only in test executable, closed phase IDs, no arbitrary callback paths in shipping schema.

Real `SHGetKnownFolderPath` is tested separately as a **read-only query** using no CREATE flag, comparing native-resolved absolute result to native adapter output before appending the pure fixed suffix. This does not create `FlightSimulator`. It cannot prove real profile ACL/storage writes. Offline integration proves writes via injected root using same repository/SQLite/Win32 file/lock core; actual installed live-root journey requires a dedicated disposable Windows user/account or explicitly authorized test account, never owner's existing profile. Setting APPDATA/LOCALAPPDATA is not an assertion that SHGetKnownFolderPath moved. [Microsoft documents that null token resolves the current user and that the caller frees the returned buffer](https://learn.microsoft.com/en-us/windows/win32/api/shlobj_core/nf-shlobj_core-shgetknownfolderpath).

## Exact proposed SQLite/opening/recovery/closing policy

SQLite is pinned3.53.4/sourceID bf7c7f30031888f4e796e429ab3978879485813aaca6f641c7b33e4e09459bcc,
archive1e71ddf93849c6a6ecf58b827c0692073d2dd7ee40196158068f7b29f422e87d.
Actual amalgamation digest is bound as a pinned external dependency in [source bindings](../../../schemas/save/local-players/v1/source-bindings-v1.json). Current CMake target has
SQLITE_THREADSAFE=1, SQLITE_OMIT_LOAD_EXTENSION=1. Future artifact must preserve
these, forbid SQLITE_NO_SYNC, enable extended result codes, and record actual
sqlite3_sourceid/libversion/compile options/VFS. Source inspection is not an
executed durability guarantee. Pinned winSync51877..51960 calls FlushFileBuffers
and returns IOERR_FSYNC; winOpen54207..54227 shows EXCLUSIVE means CreateNew and
default sharing is READ|WRITE. The following adds a real separate ownership and
quiescent-copy policy rather than treating that SQLite flag as a writer lock.

1. Resolve fixed root without CREATE flag on KnownFolder query; inspect ordinary
local NTFS parent/components/handles (other filesystems unsupported in first slice).
Create/open players.lock with CreateFileW READ|WRITE, share0, OPEN_ALWAYS,
noninheritable handle retained until actual writer exit. Existing lockfile bytes
are not ownership proof; sharing failure gives store_locked, zero SQLite opens.
The native service control block retains this OS handle through worker exit;
owner try_join first observes actual thread join, then closes that retained lock
handle exactly once. No Godot Object or SQLite query crosses into main thread.
Only cooperating app instances are excluded for the whole lifetime. External
editors/hostile concurrent pathname changes are UNSUPPORTED, not claimed defeated.

2. Under that lock, enumerate exactly players.sqlite3 plus existing -wal/-shm/
-journal. A missing main with any side file, unknown journal suffix, nonordinary
component, existing zero-byte main, reparse/hardlink alias (linkcount!=1), invalid
SQLite signature/page-size or unambiguously unsupported header refuses original
SQLite opening. Main header applicationID/user_version MAY be stale while a WAL
contains the newest committed page1; with WAL present do not reject a legitimate
store solely for an older/zero main-header value. Resolve logical applicationID/
version/schema ONLY on the preserved qualification COPY through real SQLite.
Without WAL a foreign/newer header refuses original opening. Read
header using ordinary held native handle; do not create/truncate a guessed DB.
Acquire each existing source with GENERIC_READ, FILE_SHARE_READ ONLY,
OPEN_EXISTING, FILE_FLAG_OPEN_REPARSE_POINT|SEQUENTIAL_SCAN, noninheritable.
Failure means snapshot_failed/store_locked, no SQLite call. These handles deny
new write/delete access while held, and conflict with an already open writer.
Enumerate/recheck exact existence roster after all handles acquired. Missing side
files are recorded as missing, never created as placeholders. Stable-parent and
cooperating-no-external-writer assumptions are explicit; existence checks cannot
prevent a malicious creation of a formerly absent side file. No atomic-filesystem
snapshot or adversarial TOCTOU protection is claimed.

3. Before copying require free retention capacity: at most2 retained recovery
sets, EACH main<=256MiB/WAL<=64MiB/SHM<=8MiB/journal<=8MiB and manifest<=1MiB;
total retained<=674MiB. Proposed contract storage ceilings, not performance
measurements. One qualification work copy of that same<=336MiB set may exist;
no more than1 work set. Before copying require available free space>=673MiB for
one complete retained set+manifest and one work set; this is a checked free-space
threshold, NOT an OS reservation or guarantee against later disk-full. Every
actual write/flush must still succeed. If full/oversize/free-space check fails, refuse
recovery/DB opening and retain originals. No automatic pruning. Guest recovery
UI can list/delete an explicitly selected app-owned snapshot via the worker
without opening SQLite; otherwise user may keep it and stay Guest.

4. Create a new recovery-32hex directory ONLY under fixed Players/recovery,
CREATE_NEW files; stream1MiB chunks from held source handles to copies, compute
SHA256/bytes/fileIDs and source times, FlushFileBuffers copies and close; reread
copies/hash every actual source handle and recheck original roster. Any mismatch,
short IO/flush/reparse/identity change leaves an explicitly partial snapshot and
refuses original SQLite opening. Exact snapshot manifest lists role/existence/
relative basename/actualbytes/hash/volume+file IDs, no fabricated missing file.
Write new manifest after copies verified, flush; no overwrite. Successful set is
immutable under app policy, never a claim of a coherent logical backup. Partial
sets count toward2; their bounded manifest/state and known files stay visible.
Unmanifested unknown files are retained/refused, never automatically deleted.
[recovery-copy records](recovery-v1.md) freezes exact intent/manifest/deletion ownership grammar.

5. Close source share-guards ONLY after complete verified set. They MUST be closed
before any normal original SQLite RW open: the deny-WRITE handles themselves
would block it. The guard interval protects the byte-copy phase; the later open
is a DISTINCT SQLite-owned locking phase. The advisory players.lock remains held
through both and excludes only cooperating applications. Make one disposable
qualification work copy from this immutable set; open/recover the COPY with pinned
SQLite, verify header/user_version/applicationID/schema/meta/record hashes/full
semantic records/column equality and integrity_check+foreign_key_check. It may
create/recover COPY side files; never touches raw preserved set or original.
Unknown schema/invalid row/unsupported version refuses originals, keeps copies.
Reject all nonexpected user schema objects; compare exact table/index SQL with
DDL (SQLite-normalized CREATE prefix and missing terminal semicolon only), expected
autoindexes/sql=NULL and table/index metadata. Schema fingerprint stored in meta
must match exact schema.sql SHA, codec fingerprint exact codec JSON SHA; neither
is a substitute for inspecting actual schema/records. Finalize all qualification
statements and check sqlite3_close success on the SAME sole worker before opening
original; a connection is not a joined thread. After successful qualification and stable
original identity/byte recheck, open original with fixed internal URI exclusive=1
(no caller URI), no create for existing DB. Set/query locking_mode=EXCLUSIVE
BEFORE FIRST database/WAL access on both qualification and original connections.
The pinned pagerOpenWal67262..67284 obtains the exclusive lock and passes
exclusiveMode into sqlite3WalOpen; its wal-index uses heap memory in that mode.
Thus no new SHM is expected for this connection. Existing SHM remains a preserved
forensic input; never assume SHM is always present or discard it manually.
Opening failure leaves immutable set. Noncooperating writer in guard/open gap is
unsupported; rechecks/SQLite exclusive sharing detect observed conflicts/drift,
not a proof against every race. No deletion of original WAL/SHM/journal by app.

6. On original qualified connection set/query WAL, synchronous FULL(2),
foreign_keys ON, trusted_schema OFF, locking_mode EXCLUSIVE; defensively disable
extension loading/ATTACH/arbitrary SQL, mmap_size0, SQLite length<=32MiB,
SQL length<=64KiB, variable number<=64, attached databases0, compound SELECT<=16.
New page_size4096 before DDL/WAL; existing must equal4096 (no silent reformat).
max_page_count65536=>256MiB main; busy_timeout2000ms. WAL32MiB is soft pressure,
not hard filesystem ceiling. Checkpoint between jobs; report failure separately
from committed mutation. If pressure cannot clear, refuse growth-producing jobs
storage_full without deleting data. A committed row never becomes failed because
checkpoint later fails. Existing WAL>64MiB refuses preopen snapshot/recovery rather
than copying unbounded bytes. Root can explicitly manage retained snapshots.

7. New store only when main+all side files absent under ownership: create main
with fixed internal CreateNew semantics, never SQLITE_OPEN_CREATE over an
existing unknown file. One real transaction initializes DDL/applicationID/
user_version/meta sequence1/schema fingerprints. Creation failure leaves owned
incomplete files and diagnostic recovery_required; never silently retry/truncate.
Existing start converts active rows ONLY when meta.owner_run_id differs from
the trusted process-lifetime run ID, in one transaction to
interrupted/previous_process_incomplete, preserving original source/lasttick/
creation/archive, incrementing each revision and ONE shared next commitsequence.
Same-process close/reopen preserves the row as active-but-reconciliation-required;
UI must qualify actual original source before showing it as currently flying.
It must retain the real practice/player/source binding across storage reopen;
matching meta run ID alone is insufficient. Without that binding and matching
actual Readback or joined lifecycle, preserve unavailable history unchanged.
The next real begin stamps current run ID in its own transaction, including when
clean open left an older inactive stamp. This bookkeeping never resumes flight.
Precheck all increments before any write. If no active rows, start is read/null.
If recovery commit uncertain, no claim those rows are currently flying; refuse
new writes pending joined-close/reopen and reconcile. No native session started.

8. Graceful shutdown stops new admission, FIFO drains and closes statements,
sqlite3_close success, closes export/snapshot handles and actually joins thread;
only then releases owner lock. Owner bridge must stay alive until join; never
detach/free-live-worker. Outer supervisor timeout is failure and retained evidence.
At10s show slow-save notice, not fake completion. Explicit Quit without latest
save can terminate PROCESS only after ordinary native/audio close/join; DB outcome
remains unknown/last acknowledged, next launch recovery decides. No promise that
an OS FlushFileBuffers blockage can be interrupted or threadjoined in10s.
Lost worker classification/reserved terminal slots are exact [service protocol](protocol-v1.md) rules.

RecoverySummary exact `{id,state,created_utc,bytes,manifest_sha256}` with id32hex,
state complete/partial, observed UTC or null, count actual nonnegative<=cap,
manifestsha actual or null if unavailable. list/delete recovery operate only
known fixed directories under ownership; deletion validates original fileID/nonce/
manifest, no symlink/reparse/unknown file and joined handles. Each selected set
must be confirmed in UI as a copy of ALL players, may contain logically deleted
data; explicit deletion is not player deletion/forensic erase. Partial filesystem
delete reports actual deleted_ids/retained_ids, never commits DB or marks read_only
from file uncertainty alone. Unknown paths cannot be supplied. No recursive
delete against a guessed/computed unverified directory. After capacity cleanup,
close/join and explicit reopen re-runs qualification, never resumes a failed job.

Schema1 has no historical product migrations; foreign/version0 is not a migration
fixture. Future v2 requires separate accepted migration plus real SQLite backup
API destination validation before upgrade. No pretending this raw forensic set
is a logical backup or that v1 has already proven migration rollback.

Primary source support: [Win32 sharing/CreateNew](https://learn.microsoft.com/en-us/windows/win32/api/fileapi/nf-fileapi-createfilew)
supports deny-write guards, not a mult-file atomic snapshot. [FlushFileBuffers](https://learn.microsoft.com/en-us/windows/win32/api/fileapi/nf-fileapi-flushfilebuffers)
is a checked OS operation, not a hardware-failure guarantee. [SQLite WAL](https://www.sqlite.org/wal.html)
requires side-file/recovery care. [transaction state](https://www.sqlite.org/c3ref/txn_state.html)
helps classify observed rollback but cannot recover a lost COMMIT acknowledgement.
[Exclusive WAL mode](https://www.sqlite.org/wal.html#use_of_wal_without_shared_memory)
must precede first WAL access to omit a shared-memory wal-index; setting it later
does not justify that expectation. This is distinct from SQLITE_OPEN_EXCLUSIVE
creation semantics and the Win32 source guards.
This source-informed protocol still needs independent design/source review and
actual isolated Win32/SQLite qualification before consumer acceptance.

## Activation and complete player journey

Startup always selects Guest explicitly, with existing mapper defaults and default Audio; durable last-selected autoactivation is not introduced. Guest can fly offline if storage fails. Guest preferences are application-instance only, no Guest DB row/history/archive autoassociation; switching to Guest resets its preferences to defaults (explicit chooser explanation), leaving named players untouched. Switching back loads that player's committed bundle, not an old unsaved draft.

Create A/B from profile chooser after the accessible End current/Guest flight and joined chooser route below. Real create commit creates identity/default bundle; failure leaves Guest/current player. Select invokes load_player; validate whole owned bundle and input profile capabilities; only after successful result and all current opening tokens match does the coordinator atomically replace active player ID, active saved bundle and Audio. It does not configure a mapper for an imaginary session. A missing device is a visible pending selection/hint; fresh-session configuration later uses current Raw/generation/held/start/takeover gates. Never auto-select matching runtime ID from disk, clear neutral/release gates or restore starter held state. An invalid bundle leaves the previous player and runtime options intact, offers Guest explicitly and storage diagnostics.

Profile switch is allowed only without an active native session. In a current paused session, chooser first offers “End this practice and switch player” with default Cancel. Existing actual native/audio joined close is required; final practice receipt must commit or user explicitly acknowledges latest history was not saved. Only then load/adopt target player. Cancel/stale callback preserves full current native/mapper/recording/player/prefs. DB target load failure after a real joined close keeps old player/preferences and the honestly ended old practice; it cannot resurrect physics or claim old session still current. If no close has happened, failure changes neither. This is explicitly different from trying to preserve a dead session by copying its dictionary.

Save to player is explicit and separate from Apply. In paused Controls, Apply retains current mapper admission semantics and marks unsaved differences; “Save current preferences to player” snapshots complete accepted input slots+Audio, expected bundle revision and actual player/opening guard. It can save only the current supported slot and preserves the other committed slot; null/default allowed. Actual commit acknowledges that snapshot; edits made while it was pending remain unsaved unless equal to committed snapshot. Save never implicitly Apply/reconfigure/run. Import remains draft; v1→v2 migration remains explicit draft; neither overwrites a profile or external guest file without explicit choice. For Guest the action is “Create/select player to save,” not a false persistent save.

**Explicit ADR020 amendment:** for Guest, Audio retains application-instance semantics. For a named player, explicit Save-to-player persists exactly enabled/engine_gain/airflow_gain/show_panel_captions; selection loads it as one atomic accepted AudioOptions value while no native worker. Unsaved Audio edits stay active during the application/session as today, labelled unsaved for that player, and are discarded on switching/relaunch unless explicitly saved. Successful fresh flight resets source/oscillator/lifecycle exactly as ADR020; it does not reset selected player's active Audio options. No live-caption/newwarning/gainmodel change. Current master action still has one Scene authority and can make the bundle dirty; DB result never directly toggles a second master state. **ADR025 unchanged:** camera/FOV/response/distance/look are not PlayerPreferences fields and still reset only after fully successful fresh-session adoption. Player selection cannot silently override a current camera.

After successful native+Scene+recorder adoption (not mere Start request), a trusted main-thread history adapter captures immutable PracticeSource and first actual tick, assigns a practice ID, submits begin. No worker derives practice from render pose or queries facade/native. A rejected/failed initialization creates no new row; old joined-close history remains honest. Until begin commits UI says “Practice history pending”; failure says “Not saved” while flight may continue. Persistence failure must never silently forcepause or submit axes; player can later explicitly retry a whole qualified current summary. Such retry may start history at the actual later first observed tick and must not invent a tick0 row/duration.

Periodic source inputs require the same adopted session/source/frame/context plus qualified current full Readback; malformed/foreign/tick-regressing data preserves last durable row and reports unavailable, not estimated progress. Current readonly/historical review never extends practice. A terminal publication can update last tick only when it is a qualified same-source endpoint; fault without endpoint preserves last qualified tick and marks source_ended after actual lifecycle termination. Pure SQL schema acceptance is not proof of native origin. Observe no more often than120tick growth; pause may leave unchanged ticks, clocks may move back. A paused clean Quit still records manual end at last actual tick, no invented step. Ownship distance, heading, destinations and manually ended itinerary never become a score.

Practice rows remain readable across source/model uninstall because they contain compact historical descriptors; a structurally valid current descriptor with unavailable model/binary shows historical source unavailable and remains readable. No unknown future descriptor fields/version are admitted. Newer STORE schema is different: refuse opening writer entirely. Exact policy for structurally malformed current-schema row is fail qualification/read_only, not silently delete it. Source update cannot silently reclassify prototype history as C172 practice.

## Retention, selected-file export and recovery UI

At2,000 rows new begin fails history_limit without deleting old practice or affecting native flight; UI offers explicit player-scoped selection/prune before starting or later. No automatic oldest-row loss. Only terminal rows can prune; optional limit default is a capacity policy, not a promise of infinite streaming history. Delete named player from no-session chooser requires default Cancel and explicit named scope: preferences+practice rows+links in one transaction, unrelated players preserved. This is logical app deletion, not certified forensic erasure: WAL, free pages, backups and already exported files may retain data. UI must disclose that fact; offer explicit management of app-owned backups separately. Never delete externally linked .fsreview or arbitrary paths from a DB field.

Explicit “Export player summary” writes a new chosen file, no upload. Export includes versioned public-safe player label/preferences/practice summaries/source provenance and no local machine root, archive absolute paths, Windows SID, credentials, host logs/crash dumps. Device GUID/name metadata in presets is clearly included as personal configuration; user sees scope before choosing. Do not call summaries anonymous. Full exact preferences numeric types use the defined storage codec; export is not a new import capability or resumable flight. Encoding caps/errors preserve previous file/DB. Worker uses CreateNew same-directory owned temporary, flush, caller-independent verify and no-replace final move with observed completion; collisions never overwrite. Postmove uncertainty reports possible exported file, never deletion/retry overwrite. This requires its own narrow selected-output implementation/admission contract; ADR012 Files API validates recordings and cannot be reused for arbitrary export bytes without changing its boundary.

Archive association is subsequent DB job after actual successful explicit archive Save+full validation; no cross-resource transaction promise. DB link failure leaves the saved external file valid and accessible; file save failure never creates link. Export/delete of DB records does not change external-file ownership. Explicit historical Open stays read-only, warns unavailable/mismatched hash/session and does not resume or become a new practice. Shared current recording authority and default Cancel discard behaviour remain Root-owned.

Recovery screen: stable failure code, last acknowledged-save status, “Continue as Guest,” read-only valid rows where safely available, explicit export/backup diagnostics and Close. Do not automatically rename/delete corrupt store, scan arbitrary disks, import backups or migrate down. Restore-from-backup is a separate future reviewed operation unless included with its complete tested policy before contract acceptance. OS-diskfull/newer/corrupt/reparse failure never routes to installer data writes. No automatic local telemetry/log/profile uploads.

## Preconsumer fixtures and actual verification allocation

[design-fixtures-v2.json](../../../schemas/save/local-players/v1/design-fixtures-v2.json) freezes logical records/operation outcomes/limits for review, not an executed result. Independent test author must turn these into exact accepted schema+service fixtures before consumers. At minimum: two players+Guest separation, exact four Audio values including -0, full preset float tags and int enums, exact unsigned boundary arithmetic, wall-clock reversal, optimistic revision conflicts, same/lower/new tick, source identity change, old historical descriptor, invalid fields/types/Unicode, quotas, queue result reservation, lost acknowledgement and uncertain reconciliation, expiry/stale opening, retention ownership and export redaction.

Actual native offline tests use the real pinned SQLite build and same repository core via isolated capability; independent child processes kill at before-BEGIN, afterwrites-before-COMMIT, afterCOMMIT-before-receipt, and during recovery. Parent waits exact childexit before reopening; no arbitrary timeoutkill counted as graceful join. Verify first two previous durable values, last one committed value, actual integrity/foreignkeys/uniqueidentity/bundle bits. Lock holder must use explicit ready/release/PIDnonce/observed exit, not sleep/assumed startup speed. Unknown new version bytepreserved, corrupt original snapshot retained, failed rollback uncertain, readonly/diskfull via real bounded disposable filesystem/VFS fault seam explicitly labelled; a synthetic SQLite return code is not a real NTFS diskfull proof. All fail/timeout logs retained.

Actual UI/editor/portable/replacement journey uses isolated-root test build/route clearly labelled, not hidden product root override: A saves two different profile slots/Audio, B saves distinct choices, short actual flights supply genuine adopted source, Guest unsaved; exit allworkers, relaunchsameisolatedstore, selectA/B and verify exact bits/separation/history; crashactivebecomesinterrupted, gracefulmanualendtruth, historicalopennonresume, explicitexport/delete. Check authority snapshots around Save/Cancel/failedactivation, realrelease/starter/generation/takeover preserved. Minimum960focus/text/defaultCancel; exact three-context source/native/persistence/SQLite closure and clean writer/audio/native joins. A separate disposable Windows user tests actual Known Folder+installed path journey. No owner's data path ever needed to produce automated proof.

## Bounded child acceptance and remaining real evidence

The owner-authorized proposal is the two named players+Guest complete vertical journey; ceilings8players,
2000total rows/16outstanding/32MiB service buffers are proposed CONTRACT limits,
not observed performance. Export-only explicit local-data child is in this slice;
import/achievements/assists/full restore and parent34/74/EPICP2 remain open.

1. Independent whole design/DDL/codec/protocol/reference review and checked
contract/source allocation before consumers; all numbers/status remain proposed.
2. Freeze independent bits/types/queue/revision/paging/source/export/retention
references before implementation outputs, then actual SQLite/Win32 isolated
fault/crash/flush/rollback/COMMIT-unknown tests with exact compiled source closure.
3. Actual A/B+Guest full relaunch/history/interrupted/manualended/export/delete
journey in editor/portable/replacement using same core and Root-owned capabilities;
full joins/source bits/player scope, accessible960 keyboard/defaultCancel evidence.
4. Actual KnownFolder query separately read-only; installed root writes only under
dedicated disposable Windows user/account, never APPDATA fiction or owner data.
5. Independent code/source/rights review, recorded SQLite flags/VFS, NTFS guard
recovery set/partial/capacity/pruning and output actor joins before acceptance.
No current database/API implementation or runtime evidence is claimed here.

## Retained context and accessible joined chooser

Ordinary startup currently creates a paused Guest flight. Visible Players button
in ordinary pause menu opens a compact explanatory dialog with default Cancel:
End current Guest/practice and choose player. Keyboard focus/accessibility route
exists at960; no impossible no-session-only entry. Cancel preserves full native,
mapper/recording/player/dirty drafts/camera. Confirm retires modal/input callbacks,
closes native and audio via actual existing joined paths, final qualified history
end must commit or user explicitly acknowledges not saved, then chooser opens.
Creation/load/delete do not construct a new flight. First new flight uses existing
explicit restart/discard confirmations and full successful adoption semantics.

ADR011 recording is NOT arbitrarily clearable. Save its original player/source
ownership alongside retained recording in MAIN-THREAD presentation context;
on switch hide old review panel/imported-review selection and show Previous player
recording retained if reopened. Never reassign it to new player/history. Retained
current recording persists until existing explicit different-session replacement
or confirmed exit; archive Open remains read-only/imported and cannot begin practice.
Switch may retain native closed Readback and recording honestly closed. Target
load failure after real close keeps previous player/options and closed history,
not a live fiction. Before-close failure leaves all authority intact.

Each player chooser/save/history/export/delete/Controls/Audio opening binds owner
playerID, active generation, unique opening token and current revision/source
where applicable. On retire disconnect callbacks and invalidate tokens before
UI hide/free. Request results still drain exactly once; stale callback cannot
activate, re-save, Apply or dirty a new player. In-flight saved snapshot belongs
to original player regardless of switch; changes during save remain dirty unless
bit-equal to acknowledged normalized snapshot. Visible pending/unsaved/saved/status
unknown labels distinguish DB receipts; Guest never receives a fake saved toast.
Unsaved Controls imported/migrated draft remains draft and is retired on confirmed
player switch, never auto-saved/activated. Default Cancel warns about discarding
unsaved player options before closing; explicit Save first retains the same guard.
Successful selected-player deletion adopts Guest defaults only AFTER actual
committed receipt and matching current token; failed/uncertain deletion preserves
selection pending reconciliation. Any retained ADR011 recording keeps its original
deleted-player ownership and is hidden/labeled retained, never reassigned to Guest.
Deletion disclosure includes this in-memory retained review until different-session
replacement/exit, recovery copies and external exports/archives; no forensic erase.

ADR020 amendment is ONLY selected named-player explicit saved four Audio options;
Guest remains instance-transient. ADR025 camera settings remain session-only and
reset ONLY fully successful fresh adoption. Player selection/load/save/failed
restart cannot reset camera or turn DB result into a control command. Retain all
14 wire schemas, SaveProof17 scope, ADR011/012 authority and original physical
budgets. Main-thread adapter uses exact captured expected_source and full current
Readback qualification; new descriptor shape never grants native authority.

## Implementation constraints clarified by source review

### Fresh database: checked exclusive handle handoff

This narrow shared-interface amendment becomes normative only after its checked
contract PR merges. Implementation and actual storage qualification under
[#219](https://github.com/brettbergin/flight-simulator/issues/219) remain pending.
The pinned SQLite `sqlite3_open_v2` API ignores `SQLITE_OPEN_EXCLUSIVE`; it is
not a caller-visible CreateNew guarantee. Keep the pinned default Win32 VFS and
fixed internal `exclusive=1` URI. No shared-open fallback or VFS change is allowed.

For a fully inspected empty root, perform one actual native `CREATE_NEW` of the
fixed main basename. Observe its volume serial/file ID, ordinary nonreparse
single-link identity and zero bytes. Retain its creation handle and immutable
expected identity while players.lock and admitted root/parent/sentinel leases
remain owned. Recheck that SAME handle's identity and zero bytes, then
checked-close it immediately before the SQLite-owned phase. Clear the owned
handle only after actual close succeeds. Failed close leaves it owned and
forbids SQLite opening or successful closed/joined reporting.

Open the already-created fixed basename with READWRITE|URI|NOMUTEX, without
SQLITE_OPEN_CREATE or SQLITE_OPEN_EXCLUSIVE. On actual successful open, obtain
the borrowed MAIN native handle using
`sqlite3_file_control(db, "main", SQLITE_FCNTL_WIN32_GET_HANDLE, &handle)`.
Require successful control, non-null/non-invalid handle and actual read/write
main connection. Verify the SQLite-owned handle against the CREATE_NEW expected
volume/file ID, ordinary/nonreparse/single-link identity, zero length and
normalized canonical final pathname. Recheck admitted root/parent identities
without opening a second main data handle. These checks MUST precede ALL
configuration SQL, application ID/user version, page-size/WAL setup, DDL,
initialization or other database writes. Pinned raw SQLite opening may read the
file header; opening is not claimed to perform no reads, nor are SQLite internal
calls represented by fabricated adapter IO events.

The expected identity comes ONLY from actual CREATE_NEW observation, never from
a caller record/path/test dictionary. MAIN handle is borrowed only within the
sole-worker verification call: FileSystem MUST NOT close, duplicate, cache,
rebind or write through it. Never use WIN32_SET_HANDLE or reinterpret a
FILE_POINTER as HANDLE. SQLite owns its handle; checked sqlite3_close must
succeed before that connection's resources are closed. Existing statement,
worker exit/join and retained lock ownership requirements remain unchanged.

The exact internal FileSystem declarations are virtual/pure, with corresponding
WindowsFileSystem overrides; the existing reserve_new_database(FileIdentity&)
declaration is unchanged:

```cpp
Error release_reserved_database_for_sqlite(const FileIdentity& expected);
Error verify_reserved_database(const FileIdentity& expected,
                               void* borrowed_sqlite_main_handle);
```

The opaque void* is non-owning internal Windows HANDLE input, never a public
DTO/Godot capability. Release requires the currently held creation handle and
players.lock. Verification requires retired creation handle, valid immutable
expected identity and retained lock; its HANDLE/topology checks are bounded and
read-only. Non-Windows stubs return root_unavailable, not a Linux storage route.
Store's private fresh-open path carries the expected identity (or an equally
explicit private split): checked release -> raw SQLite open -> actual MAIN
handle acquisition/verification -> configure -> initialize. Qualification and
existing-original paths do not use these fresh reservation methods and retain
their existing policies. No public Service/AdmissionSource/Registry/Boundary or
ClassDB ABI, persistent payload or arena allocation is added.

Closed failure rules:

- Reserve failure keeps existing mapping and performs no SQLite open. Retain
  every actually owned failed-close handle.
- Release identity/metadata/zero-byte drift returns recovery_required without
  SQLite opening; invalid internal ownership or failed close returns io_error.
  Failed close retains the same handle.
- SQLite open failure keeps actual SQLite error mapping and any returned
  connection for checked close; there is no initialize/configure fallback.
- GET_HANDLE failure/null/invalid or unexpectedly read-only main returns
  io_error. Identity/type/link/final-path/root drift or nonzero freshly reserved
  file returns recovery_required. Neither outcome performs configuration SQL.
- Pre-write handoff failure is failed with value and commit_sequence null,
  never uncertain/committed/ready. Later configuration/initialization uses
  existing errors, commit uncertainty and actual transaction observations.

Preserve the zero/new file or observed replacement on every failure. Never
delete, truncate or overwrite it to make retry pass. Subsequent inspection may
refuse an uninitialized preexisting file as foreign_store. Keep advisory lock
and topology leases throughout; the close/open interval is an observed handoff,
NOT atomic adversarial path protection. Observed drift refuses writes;
noncooperating mutation beyond those observations remains unsupported. Existing
qualification-copy guards, fixed exclusive URI, locking_mode EXCLUSIVE,
WAL/SHM/journal preservation and actual shutdown/join rules remain unchanged.

Implementation is restricted to the existing filesystem.hpp,
windows_filesystem.hpp, store.hpp, store.cpp and windows_filesystem.cpp under
native/persistence/local_players. Keep exact 17 source/15 control/11 normative
path membership, public API and all frozen fixtures/crash19 recipes. Changed
normative/source bytes require fresh contract/component/build identities and
actual source/compiler/SQLite/object/aggregate binding. Source review must
verify actual ABI, unchanged arena charges and operation-site ordering before
execution. Required real isolated cases include new-store success, borrowed
MAIN identity/exclusive sharing, read-only/closed/identity drift before writes,
checked failed-close ownership, ordinary reopen/qualification/recovery and
full authenticated Native/Windows/Bridge/crash qualification. Existing
before_open sites may expose the actual interval for deterministic test
replacement/lock attempts; no new shipping hook is authorized. A callback,
mock or source proof is not an observed Win32/SQLite result. Historical b07
failed/io_error and zero-file observations remain failures; their exact SQLite
extended/Win32 error was not captured and is not invented here.

Direct `poll` actual-INT admission must precede any Godot narrow-parameter
coercion. Export snapshot/spool buffers count toward the same 32 MiB owned-buffer
ceiling alongside reserved requests/results; no unaccounted full export buffer
or unlisted persistent scratch ownership is permitted. Exact implementation and
actual source/NTFS qualification remain consumer evidence.

## Prospective ADR027 closed source-domain amendment

PROPOSED, effective only after checked [ADR027](../../decisions/027-synthetic-taxi-navigation.md) acceptance. Its exact two new Source pairs extend the existing named_start enumeration without changing eight-key DTO, SQL/codec/schema fingerprints. Legacy apron-ready requires calm/null method/original legacy model; piston-cold-apron requires calm/event_aware_coupled_midpoint_v1/jsbsim-1.3.1-event-aware-coupled-midpoint-local-window-v2/original piston model. Existing cold-ground historical variants and all old Source fixtures remain accepted unchanged. Current source adoption still requires the actual reviewed first-party recipe closure and complete native Readback; history uses these closed semantics without equality to today's installed hash. Changed normative inputs require new source/CI/component binding, even though DDL/codec bytes stay exact. No physics resume, profile/source relabel or older-reader universal compatibility claim.
