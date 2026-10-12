# Local-player frontend integration v1 (proposed contract)

Proposed contract requiring checked PR acceptance before parallel consumers;
this document does not implement or accept the #220 journey. Checked #219 backend
acceptance and Root's qualified integrated Scene selection remain prerequisites.
The [qualified backend](../../evidence/P3/local-players-store.md) and
[PR239](https://github.com/brettbergin/flight-simulator/pull/239) provide the
backend source/qualification anchors; component evidence is not #220 readiness.
No native method, durable DTO, schema, allocator, fault hook or root override changes.

## Ownership and minimum first slice

| Owner | Paths | Responsibility |
| --- | --- | --- |
| Controller | `app/persistence/local_players_controller.gd`, `app/ui/profiles/player_options.gd` | Main-thread storage lifetime, guarded routing, exact bundle comparison, committed selection and practice binding. |
| Players pages | `app/ui/profiles/players_panel.gd`, `player_name_panel.gd` | Chooser/name presentation and typed intents; no storage, Scene or mapper calls. |
| Later history pages | `app/ui/history/{practice_panel,practice_details,player_export_panel,recovery_panel}.gd` | Owned query/result presentation, explicit destructive confirmations and new-file selection. |
| Root | `app/simulation/flight_scene.gd`, existing Controls/Audio panels, `app/proof/interactive/preview.gd`, source/build/package/CI/docs | Current Scene integration, flight/audio lifetime, options adoption and Save affordances. |
| Independent tests | `tests/ui/profiles/{panel_checks,controller_checks,scene_checks,journey_checks,visual_checks}.gd` and README | Real isolated service integration, full authority/bit/layout cases. Pure presentation fixtures remain labelled synthetic. |

Implement first: joined chooser from paused Guest; create/select A/B/Guest;
atomic named bundle adoption without creating a flight; explicit Save of applied
current-slot Controls and current Audio; dirty/pending/unknown presentation;
deliberate A/B selection after a second launch. Guest has no row, Save or history.
History/export/delete/recovery interfaces below are frozen so their authors can
proceed later, but empty/stub pages cannot count as the complete journey.

## Guard and lifetime rules shared by all modules

`opening: int` is a positive owner-issued monotonically increasing presentation
token. `epoch: int` is the current selected-player generation. Neither is a
native request ID, durable revision, session or authorization proof. Refuse new
openings before signed-int exhaustion; never wrap/reuse. RootScene exclusively owns the registry binding each actual widget and Callable
to its opening, player ID, epoch, applicable revision and source. Root is the SOLE
page-signal forwarding guard: before invoking any controller intent it verifies
that exact live widget/connection and all bound context still match. Pages never
connect directly to controller intent methods. Retire/disconnect the Root registry
entry before hide/free. An integer supplied by a page alone cannot authorize an
operation. Controller separately owns native request/result associations; those
associations do not establish callback caller identity. Every method/signal below
is main-thread-only.

Controller owns one actual service at a time and at most16 native accepted IDs
including undelivered results. It retains ID→kind/player/revision/snapshot/opening
association until the one full terminal result is polled. Do not discard accepted
jobs when retiring a page. Poll once in the controller, never in pages/Scene.
Admission failures have no pending commit; resource contention may legitimately
return `out_of_memory`. Do not promise every pair of immediate submissions succeeds.
Schedule application intents after the worker is idle when needed; never spin or
automatically replay a rejected/uncertain mutation. Actual native Admission,
Status and Result dictionaries retain their accepted closed shapes unchanged.

## Controller signatures to freeze

The following are INTERNAL GDScript signatures, not new ClassDB methods. `void`
intent methods do not imply native acceptance; status/result signals carry truth.

```gdscript
func attach_service(service: RefCounted) -> bool
func start_storage() -> void
func open_players(opening: int, epoch: int) -> void
func retire_opening(opening: int) -> void
func choose_player(opening: int, epoch: int, player_id: String) -> void
func choose_guest(opening: int, epoch: int) -> void
func create_player(opening: int, epoch: int, name: String) -> void
func rename_player(opening: int, epoch: int, name: String) -> void
func finish_selection(opening: int, epoch: int, adopted: bool) -> void
func current_options_changed(seed: Dictionary) -> void
func save_snapshot(opening: int, epoch: int, seed: Dictionary, utc: String) -> void
func acknowledge_history_not_saved(opening: int, epoch: int) -> void
func begin_close() -> void
func pump() -> void

signal storage_changed(status: Dictionary)
signal players_changed(opening: int, epoch: int, players: Array)
signal selection_candidate(opening: int, epoch: int, pair: Variant)
signal selection_changed(epoch: int, pair: Variant)
signal options_changed(epoch: int, committed_preferences: Variant,
    dirty: bool, pending: bool, unknown: bool)
signal operation_finished(opening: int, epoch: int, result: Dictionary)
signal intent_refused(opening: int, epoch: int, kind: String,
    reason: String, admission: Variant)
signal history_exit_resolved(epoch: int, saved: bool)
signal storage_closed()
```

`intent_refused` separates pre-effect refusal from actual terminal Results.
Its closed `reason` is `native_rejected`, `local_busy` or `local_guard`.
For `native_rejected`, `admission` is the exact owned rejected native Admission;
present its existing `error_code`. For either local reason, `admission=null`:
`local_busy` means another pending controller operation prevents this intent,
and `local_guard` means the current controller context does not permit it.
Root applies the same live-widget/opening/epoch guard before presenting feedback;
stale openings receive no presentation update. A refusal creates no synthetic
Result, accepted request ID, pending Save or native Status mutation.
`operation_finished` remains actual terminal Results only, and
`storage_changed` remains actual native Status only.

Root attaches only its freshly constructed production `LocalPlayers`. Independent
isolated integration may attach the actual compiled `LocalPlayersTest` after its
existing capability/context setup; shipping contains no such class/factory.
Attach once, before start, and verify this exact native class identity. Do not
accept a duck-typed mock as real persistence evidence, or expose factory/root/
test-mode arguments to pages, CLI, preferences or shipping APIs. A new service
object may be attached only after the previous instance was actually joined,
all accepted results drained and its binding explicitly retired.

`pair` is the accepted exact `{player,preferences}` value, or null for Guest;
never a new durable record format. Selection candidate is an owned, whole validated
bundle from a matching `load_player`/create result. Root synchronously validates
and adopts it at a no-flight boundary, then calls `finish_selection`. Controller
changes selection and increments epoch ONLY after matching `adopted=true`.
Failed load/adoption leaves the old identity/options intact. Stale commits update
their old-player ledger but never activate or dirty the current selection.
Create must not silently select before its real commit and Root adoption.

`save_snapshot` is called by Root, not directly by a page: seed is the existing
exact `{legacy_input,piston_input,audio}`. Controller supplies selected player ID
and current acknowledged expected revision to `save_preferences`. One Save at
a time per current bundle; pending retains its immutable seed/revision. A real
`committed`/`no_change` result establishes the returned paired revision and
committed seed. Compare today's active seed against that seed to determine dirty;
edits made while pending are not overwritten. Revision conflict offers an explicit
reload/reconciliation choice. `uncertain` retains seed and selection, says status
unknown, disables DB writes and requires joined new-object reconciliation; never
auto-retry or label saved. Guest Save opens create/select, not a fake success.

Exact comparison in `player_options.gd` must retain actual INT/FLOAT branches and
compare FLOAT binary64 bytes, including signed zero, recursively within accepted
records. Ordinary Variant equality, JSON decimal stringify or epsilon comparison
cannot establish clean state. Use accepted preset/Audio validators before adopting.
No alternate persisted codec or permissive normalization is introduced.

## Page signatures and signals

Every page supports `set_feedback(opening:int, epoch:int, message:String, busy:bool) -> void`.
Root first guards its actual live widget/Callable registry; the page additionally
ignores mismatched or retired tokens. Feedback owns copied text bounded to 1024
characters and clears on a fresh `present`. Busy disables submitting actions,
while Cancel/dismiss remains usable. Dismissal never cancels accepted native work.
This method changes presentation only, never native Status, selection, revision,
saved-state truth or retry behavior.

Every page supports `retire() -> void`, disabling intents before disconnect/hide,
and `focus_cancel() -> void`. `present` owns deep copies; it never sets selection.

| Page | Input method | Intent signals |
| --- | --- | --- |
| players_panel | `present(opening:int, epoch:int, players:Array, selected_player_id:Variant, storage:Dictionary) -> bool` | `player_chosen(opening:int, epoch:int, player_id:String)`, `guest_chosen(opening:int, epoch:int)`, `create_requested(opening:int, epoch:int)`, `rename_requested(opening:int, epoch:int)`, `history_requested(opening:int, epoch:int)`, `dismissed(opening:int, epoch:int)` |
| player_name_panel | `present(opening:int, epoch:int, name:String, rename:bool) -> bool` | `name_confirmed(opening:int, epoch:int, name:String)`, `dismissed(opening:int, epoch:int)` |
| practice_panel | `present(opening:int, epoch:int, player_id:String, page:Dictionary) -> bool` | `next_requested(opening:int, epoch:int, before_creation_sequence:Variant)`, `details_requested(opening:int, epoch:int, practice_id:String)`, `prune_requested(opening:int, epoch:int, practice_ids:Array)`, `dismissed(opening:int, epoch:int)` |
| practice_details | `present(opening:int, epoch:int, practice:Dictionary) -> bool` | `archive_open_requested(opening:int, epoch:int, practice_id:String)`, `dismissed(opening:int, epoch:int)` |
| player_export_panel | `present(opening:int, epoch:int, player:Dictionary, receipt:Variant) -> bool` | `export_requested(opening:int, epoch:int, target_absolute_path:String)`, `dismissed(opening:int, epoch:int)` |
| recovery_panel | `present(opening:int, epoch:int, summaries:Array, deletion:Variant) -> bool` | `delete_requested(opening:int, epoch:int, snapshot_ids:Array)`, `reopen_requested(opening:int, epoch:int)`, `dismissed(opening:int, epoch:int)` |

Later controller entry points mirror these exact intents: `request_history(opening,
epoch,before_creation_sequence:Variant)`, `request_details(opening,epoch,practice_id:String)`,
`request_prune(opening,epoch,practice_ids:Array)`, `request_export(opening,epoch,
target_absolute_path:String)`, `request_delete_player(opening,epoch)`,
`request_recovery(opening,epoch)`, `request_delete_recovery(opening,epoch,snapshot_ids:Array)`
and `request_reopen(opening,epoch)`, all `-> void`. IDs/expected revisions come from
the controller's selected owned records after Root's callback guard, never a
page-controlled revision or Source. Native request routing is separate from the
Root-owned widget/Callable registry.
History uses existing null/U64 cursor, limit50 and exact result page; no unbounded
summary list. `operation_finished` delivers full immutable native results to the
registered route, including file outcomes/retained IDs; page closure drains without
redelivery. Raw status paths are shown only in requested storage details, not logs.

Controls/Audio retain their existing signals unchanged. Root adds the same
`save_player_requested(opening:int, epoch:int)` intent and
`set_player_save_state(opening:int, epoch:int, player:Variant, dirty:bool,
pending:bool, unknown:bool) -> void` presentation method to both panels.
Controls Apply remains its existing `applied(preset)` path. Label Save explicitly
as applied Controls/current Audio; unapplied import/calibration drafts remain drafts.
This avoids silently applying a draft or implying it was saved. A pending Save
does not block further draft edits or rewrite them on ACK.

## RootScene seams on the qualified integrated source

Proposed new Root-owned signatures:

```gdscript
func open_players() -> bool
func cancel_players_exit(opening: int, epoch: int) -> void
func confirm_players_exit(opening: int, epoch: int) -> void  # may await audio retirement
func adopt_player_bundle(opening: int, epoch: int, pair: Variant) -> bool
func capture_current_player_seed() -> Dictionary
func request_player_save(opening: int, epoch: int) -> void
func retire_players_ui() -> void
```

Entry uses a current paused/full Readback, no native advance, and all existing
Views/Taxi/Audio/Controls/review/archive/wind/first-flight/pointer modal guards.
Default Cancel only retires the confirmation and restores focus; it does NOT call
close, shutdown, Apply, clear a recording, change camera or mutate player drafts.
Do not reuse `confirm_discard`'s restart/otherwise-quit branch for player switching.
Confirm first retires competing openings, then calls actual `close_session()`.
Its false result stops adoption; a copied closed-looking dictionary is not join.
Capture the owned final `result.readback` INSIDE `close_session`, after the actual
`facade.close()` returns successful observed join and BEFORE `facade=null`.
A pre-close Readback copy is not final-endpoint or join evidence. Only this matching
successful close result may be forwarded to history finalization. Await `sound.shutdown()`
and require playback retirement; that is not an audio OS-thread join. Complete the
matching practice end receipt, or explicit user acknowledgment that history was
not saved, before exposing active chooser actions. Closing storage is separate.

`adopt_player_bundle` requires facade null/real joined flight boundary, no pending
archive operation and matching current candidate. Prevalidate both input slots
and all four Audio values before mutation; then copy selection options atomically.
Do NOT configure a mapper or call restart/resume during adoption. Preserve camera,
recording source and current release/takeover/starter gates. Missing devices remain
a later fresh-session selection/release hint, not automatic runtime-ID reconnection.
Guest explicitly resets options to defaults without creating a native flight.

Map legacy slot to `Facade.LEGACY_PROFILE.id`, piston slot to
`Facade.PISTON_PROFILE.id`; these are model IDs, never player IDs. Current selected
mode's accepted Apply changes only that slot. Save MUST preserve the other
committed slot, even if Scene `profile_presets` holds an old unsaved mode cache.
For an untouched loaded null slot, display mapper defaults but retain null in
the save seed until an explicit accepted Apply changes that slot; merely loading
defaults must not manufacture dirty state. Audio remains the accepted four-key
`AudioOptions.validate` value. No camera/UI/runtime device IDs enter seed.

Current `close_session` retires Views/Taxi/Audio and records the joined endpoint;
`restart` validates admission, joins old flight, constructs/qualifies native,
configures mapper, begins recorder and only then publishes full adoption and resets
camera. Hook history begin after that successful adoption boundary, not at Start.
`observe_flight` is the existing complete Readback observation seam; add history
observation without changing recorder/physics. Current `apply_controls` and
`set_audio_options` remain the authority paths, with successful changes notifying
the controller's exact active-seed comparison. Recreate a retired sound instance
through existing construction/attachment before a later flight; do not revive
the closed renderer or pretend `set_options` revives it.

## Practice and archive routing, without native/schema additions

Root-only controller calls to freeze: `flight_adopted(source:Dictionary,
readback:Dictionary,utc:String) -> void`, `flight_observed(readback:Dictionary,
utc:String) -> void`, `flight_closed(readback:Dictionary,end_reason:String,
utc:String) -> void`, `archive_saved(practice_id:String,archive:Dictionary) -> void`.
Pages cannot call these. They carry existing accepted records and qualified
Readback, not a new flight event schema or opaque bool claiming a join.

Root constructs exact eight-key PracticeSource after fully successful restart:
Readback supplies session/model/native fingerprint/world hash/named start;
accepted loaded `NativeIdentity.SOURCE_VARIANT` supplies variant;
`current_wind_profile` is retained ONLY after actual Facade.start validated the
native reply against the requested wind; method is the exact Facade.PISTON_METHOD
or null that `_method_matches` validated at that same adoption. Recorder metadata
alone lacks wind/method/variant and cannot substitute. Do not infer Source from
pose, DB owner run ID or a historical filename. Controller independently validates
the admitted combination and binds it immutably to the selected player/practice.

Generate caller player/practice IDs once; do not substitute the private native
run ID. Begin after adoption, then schedule observations at >=120 added qualified
ticks, coalescing only unsent observations. Drain begin/observe ACKs before end
and use acknowledged row revision/full expected_source. Close uses the actual
qualified endpoint; manual reasons `user_end|user_restart|user_quit`, terminal
reason `native_terminal`, never invented landing/success. A failed begin leaves
flight usable and says not saved; no forced pause/axes. Unknown end cannot be
automatically replayed. Same-process reopen requires the retained actual binding
and matching qualified source/lifecycle; a fresh process permits the existing
interrupted-row recovery, never an invented resume.

ADR011 retained recording keeps its original player/source presentation context
through switching/deletion. Imported ADR012 review is read-only and starts no
practice. Scene `finish_archive_operation` must produce a successful selected-file
receipt and qualified matching source before optional `link_archive`; a link
failure never deletes/relabels the external file. Player/history deletion never
clears external archives. Matching committed player deletion may adopt Guest;
uncertainty preserves selection until reconciliation. Recovery management means
real storage join, NEW management-only service, exact partition/retry presentation,
real join, NEW ordinary service; no restore/import or arbitrary path cleanup.

## Existing anchors and acceptance limits

Current Scene anchors: close272, restart314–438, full adoption529, pause565,
Views1321/Taxi1413, Audio1510/1532/1549/1557, Controls1583/1671,
observe2452, review boundary2460, archive save2567, confirmation2700, exit2732.
Facade: method333 and validated native start reply377; recorder begin57/observe80;
sound shutdown181; storage protocol11–49/66–85, records254–276 and lifecycle
safe-closure amendment. Backend source/identity anchors are recorded in the
[qualified backend evidence](../../evidence/P3/local-players-store.md) and
[PR239](https://github.com/brettbergin/flight-simulator/pull/239). Read the actual
[`flight_scene.gd`](../../../app/simulation/flight_scene.gd),
[internal controller signatures](#controller-signatures-to-freeze)
and accepted [storage protocol](protocol-v1.md), [records](records-and-lifetimes-v1.md)
and [lifecycle amendment](service-lifecycle-amendment-v1.md) before integrating.
Line numbers above are navigation aids, not immutable authority.

First-slice independent proof must include A/B exact bits/types across two actual
launches, Guest/default/null handling, Apply distinct from Save, edits during Save,
stale page/old-player commit routing, unknown/load-after-close failure, and complete
before/after native/mapper/recording/camera authority for Cancel/Save/navigation.
Later full #220 still requires histories, archive context, export/collision/delete/
recovery, 960x540/1080p/1440p keyboard/focus layouts, editor/portable/rebuilt
journeys and separately authorized disposable-user KnownFolder installation.
No new runner stages/receipt schema are asserted here; Root freezes only needed
delivery interfaces before those consumers. This proposal closes no issue, parent,
phase, aircraft/pilot gate, physical durability or engine OOM claim.
