# ADR026: Durable local players and compact practice history

Date: 2026-10-11. Status: **PROPOSED** shared contract. Normative only after its checked contract PR merges. [Contract #218](https://github.com/brettbergin/flight-simulator/issues/218) owns this decision, [store #219](https://github.com/brettbergin/flight-simulator/issues/219) owns the native implementation, and [journey #220](https://github.com/brettbergin/flight-simulator/issues/220) owns the complete player experience. Consumers remain blocked until complete checked contract acceptance. This bounded child supports [LOCAL-PERSISTENCE #34](https://github.com/brettbergin/flight-simulator/issues/34) and [PROFILE-SESSION-UI #74](https://github.com/brettbergin/flight-simulator/issues/74); it closes neither parent nor a phase gate.

## Decision and allocation

Provide the complete two named players plus Guest journey: explicit saved Controls/Audio, deliberate selection after relaunch, truthful compact practice history, selected-player new-file export and explicit logical deletion. Reuse [ADR004](004-persistence-and-replay.md): pinned native SQLite, one asynchronous writer, real Windows Known Folder LocalAppData and a fixed `FlightSimulator/Players` child. Guest stays available when storage fails. Names never determine paths.

The normative contract is allocated once:

| Location | Authority |
|---|---|
| [Records, storage and UI lifetimes](../contracts/local-players/records-and-lifetimes-v1.md) | Closed player/preferences/practice/source/archive records, limits, native root/open/close policy and complete activation/retained-recording journey |
| [Service protocol](../contracts/local-players/protocol-v1.md) | Exact methods/admission/results/errors, revision/sequence/cursor, worker and same-process reconciliation |
| [Recovery records](../contracts/local-players/recovery-v1.md) | Finite quiescent retained/work copies, identities, management-only deletion and partial failures |
| [Storage definitions](../../schemas/save/local-players/v1/README.md) | Exact SQL/codec/fingerprints, original 72 design recipes and portable source provenance |
| [Independent value references](../../tests/persistence/local_players/reference/README.md) | Frozen original type/bit/canonical-byte/uint64/paging expectations; explicitly unexecuted boundary recipes |
| [Service lifecycle amendment](../contracts/local-players/service-lifecycle-amendment-v1.md) | Closed admission precedence, interrupted observation timestamps, closed polling and actual worker join versus never-created quiescence |
| [Full-record amendment](../contracts/local-players/full-record-reference-amendment-v1.md) | Complete canonical records/export, numeric creation-sequence order, and preferences-layer scanner limits |
| [Reservation and export spool](../contracts/local-players/reservation-and-export-spool-v1.md) | Fixed native arena, request/result delivery ownership and exclusive bounded export spool |
| [Test scheduler](../contracts/local-players/test-scheduler-v1.md) | Shipping-absent actual operation checkpoints, closed fault selectors and actor lifetime evidence |
| [Service](../../tests/persistence/local_players/service_reference/README.md), [full-record](../../tests/persistence/local_players/full_record_reference/README.md) and [reservation](../../tests/persistence/local_players/reservation_reference/README.md) references | Independent complete typed/bit/byte expectations and conditional fault recipes; no runtime observation is implied |
| [Compiled source allocation](../contracts/local-players/compiled-source-allocation-v1.json) and [test capability](../contracts/local-players/test-capability-v1.md) | Closed storage component/build/test/package rosters and shipping-absent isolated test access |

These internal save records do not join the fourteen public wire formats. No native flight API, aircraft definition, numerical budget, model or wire registry changes. Simulation remains sole flight authority; a database descriptor or process run ID cannot establish a current flight. Matching adopted source plus qualified current Readback or actual joined lifecycle is required. A save toast requires the actual committed receipt; lost acknowledgement stays uncertain until explicit read reconciliation. Worker ownership lasts through actual exit/join, never detached or falsely completed on a deadline.

## Explicit lifetime amendment

After this contract is accepted, [ADR020](020-original-audio-cues.md)'s application-only/no-persistence Audio rule has one exception: a named player may explicitly save/load exactly its four existing Audio options with its atomic Controls bundle. Guest remains instance-transient. No gain/cue/authority/caption behavior changes. Unsaved edits remain labelled; a source reset does not reset the selected player's active options.

[ADR025](025-paused-view-presets-and-comfort.md) remains unchanged: Views/FOV/response/look are session-only, absent from PlayerPreferences, and reset only after fully successful fresh-session adoption. Player selection/save or failed restart cannot reset the camera. [ADR011](011-observed-flight-review.md) recordings retain original player/source ownership until their existing confirmed replacement/exit boundary; there is no invented clear or reassignment operation. [ADR012](012-observed-review-interchange.md) remains explicit interchange, not automatic recording persistence.

## Fresh-store exclusive handle handoff amendment

The [fresh database handle handoff](../contracts/local-players/records-and-lifetimes-v1.md#fresh-database-checked-exclusive-handle-handoff)
is a narrow shared-interface prerequisite for [store #219](https://github.com/brettbergin/flight-simulator/issues/219), normative only after its checked contract PR merges.
Keep actual CREATE_NEW identity and fixed exclusive=1 no-CREATE SQLite opening.
Checked-retire the reservation handle, then verify the actual borrowed SQLite
MAIN handle's read/write/identity/zero/topology before configuration or writes;
SQLite retains sole ownership of that handle. Failed closes remain owned and
cannot become successful joins. The close/open interval adds no atomic security
claim. No public DTO/API, source/control/normative membership, old fixture,
database schema or codec changes. New byte identities and full actual isolated
storage qualification remain implementation gates; saved b07 failures are not
acceptance evidence. No parent or phase gate closes with this amendment.

## Gates and limits

The SQL/codec/recipes are proposed design inputs, not observed database output. Freeze independent exact type/bit, revision/queue/source/paging/recovery/export references before consumers. Qualify the actual pinned SQLite/Win32 source and isolated fault/crash/flush/COMMIT-unknown/join behavior, then the A/B/Guest complete relaunch/history/export/delete journey in editor, portable and rebuilt-library contexts. Test roots use the separate native test capability; production exposes no root override. Real Known Folder query is separately read-only; installed writes require a disposable authorized Windows account. Owner data must not be opened by tests.

The [P1 SaveProof17](../evidence/P1/save-proof.md) remains original fixed-rate flight-only same-build reconstruction. This contract provides no current piston/contact/in-flight restore, migration, automatic recording save/import, account, achievement, evaluator, official hours, C172 fidelity or pilot/phase acceptance. Future schema migrations and restore require separately reviewed contracts and evidence.

The complete input allocation contains eleven normative contract inputs and thirteen additional fixed reference files. Historical source-binding snapshots remain immutable provenance; future storage qualification binds all current normative inputs independently. The [contract evidence](../evidence/P3/local-players-contract.md) records the closed-field export bound and separates contract acceptance from actual source/layout review, compilation and runtime qualification under #219. No hash of unwritten consumer code is required to accept this contract.
