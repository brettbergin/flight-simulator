# ADR-004: Local progress with versioned recording and conditional resume

Date: 2026-10-03. Status: accepted for planning; exact in-flight resume is a proof gate.

## Context

Two local players need separate controls, accessibility preferences, achievements, and skill evidence. Progress must survive crashes/upgrades and a GitHub ZIP installation. A realistic flight contains state hidden behind visible location/airspeed, so a visual snapshot alone is insufficient for correct continuation.

## Decision

Use SQLite 3.53.4 through its native C API for profiles, settings, progress, achievements, session metadata, and save pointers. Use immutable versioned files for accepted commands/events and sampled physical/observed playback state. One asynchronous writer owns database/files. Native persistence resolves Windows Known Folder `FOLDERID_LocalAppData`, appends `FlightSimulator`, and shares that resolved project root with the client; all durable data resides at `%LOCALAPPDATA%/FlightSimulator/`. Do not assume Godot's default `user://` directory is LocalAppData. Portable install content is read-only and independent of this data root. Commit saves transactionally and show success only after a committed receipt.

Use WAL with validated backups, pre-migration backup, foreign keys, and idempotent progress events. SQLite is suited to embedded application storage and publishes public-domain code. Backup must use the API or tested checkpoint/closed-copy logic rather than copying only a live database while ignoring the WAL. [Appropriate uses](https://www.sqlite.org/whentouse.html), [copyright](https://www.sqlite.org/copyright.html), [WAL](https://www.sqlite.org/wal.html), [backup API](https://www.sqlite.org/backup.html).

Recorded playback reads historical snapshots and events without re-integrating physics. Re-simulation uses matching build/compiler/FDM/content hashes and complete accepted inputs/environment/events/seeds. Preserve compatibility categories in the replay header; cross-version physics reproduction is not assumed. Summary/progress data remains readable after aircraft/content updates.

P1 first tests full solver-state restoration, including integrator histories, engine/gear transients, filters, systems, RNG, scenario, and ATC. If no complete safe restore exists, reconstruct from initial conditions and the accepted log in the identical runtime, with visible progress. If neither restore nor reconstruction proves equivalence and acceptable time, initial resume is limited to reviewed ground/scenario restart checkpoints while in-flight recordings and progress remain preserved. A blocking issue tracks exact resume; do not advertise partial state restoration as seamless continuation.

## Alternatives

JSON-only mutable profile files require custom transactional/migration logic. A cloud database adds account/network/cost dependencies without serving the initial household use. Writing every simulation tick into relational tables complicates recording throughput. Saving just transform and airspeed loses engine, integration, sensor, and procedural state.

## Consequences and gates

Replay/readers need explicit schema versions and size limits. Updating physics may prevent re-simulation of earlier sessions, but not viewing recorded summaries/playback. Rewinding/resuming branches the attempt and retains assistance provenance. Test interrupted writes, disk-full behavior, migration rollback, replay corruption, ten-minute deterministic reconstruction, and 60-second resumed-versus-uninterrupted divergence before enabling exact in-flight saves. Bound storage and give players export/pruning controls.
