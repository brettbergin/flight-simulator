# Local-player storage implementation progress

Status: draft implementation for LOCAL-PLAYERS-STORE #219. This is an engineering storage boundary; the player selection, preference Save, history, relaunch, export and delete screens in #220 are not implemented by this change. Neither the issue nor P3 is accepted by this report.

The implementation consumes the accepted [compiled allocation](../../contracts/local-players/compiled-source-allocation-v1.json), [reservation contract](../../contracts/local-players/reservation-and-export-spool-v1.md) and [test capability](../../contracts/local-players/test-capability-v1.md). It adds a separate Windows storage extension, a pinned SQLite store, an owner/worker service, bounded records/codecs, fixed KnownFolder storage, export/recovery operations and independent native/Godot tests. Simulation state remains separate; practice summaries cannot restore an aircraft or establish official flight hours.

## Measured engineering evidence

On 2026-10-12, the coordinator compiled the isolated b32 source snapshot with the pinned Windows toolchain and retained actual compiler, linker, object/archive, DLL and source witnesses. Independent saved-evidence review verified the shipping/test registration separation and actual SQLite inclusion. The test-only descriptor parser moved its 524,288-byte scratch buffer to checked heap allocation; the measured parser stack frame fell from 525,200 to 936 bytes without changing the executable's 1 MiB stack reserve. The preceding stack-overflow run remains failed.

All five focused CTests passed: codec, store, service, Windows and crash. The crash test exercised nineteen fixed injected process-crash scenarios, twenty actors and thirty-eight prepare/reopen stages. These are process-crash tests, not hardware power-loss qualification.

The store suite reached the complete 2,000-record fixture, forty pages of fifty records, cursor/count/refusal/prune/refill checks, eight-player and ninth-player refusal cases, and complete selected-player export. Its 7,826 actual events remained below the unchanged 16,384-event ceiling. The saved export was independently rehashed: 2,387,415 bytes, SHA256 `c07ca164caffac111c5b7e3724dc00eed439502fe7bfc17523be4fa01cab74fc`. Assertion totals describe looped test execution; they are not independent product features or flight scenarios.

Native receipt SHA256: `33812846ccc9e5c5fb22b7158d49c32dcc0d8817fdfcff3d2062feae46dfb147`. Independent native review SHA256: `aa9b4ffdc2ecfdff29a4890047712c78812aba63e03b148b97659b4cdc96a734`. Private evidence uses disposable test roots and is retained locally; no pilot profile is published. These pins identify the measured snapshot, not an eventual merged commit or proof of a different build.

## Required before acceptance

The same-build Godot boundary campaign completed with exit zero and a passing supervisor receipt, SHA256 `5425812a41e70ba36a7434194ee692b98f5f8cfef3558098112013fb4b428907`. Independent saved-evidence review is pending. Allocation-category/ordinal refusals, shared export-credit lifetimes, remaining fault/counter and size-boundary cases require completion. A source audit also found that pre-IO oversized export classification needs correction to the accepted `storage_full` result.

The root CMake integration changes shared flight build controls. Current-main combined flight/storage qualification, package aggregate identity and the required CI remain outstanding; old flight build hashes cannot substitute. The installed A/B/Guest journey, privacy/relaunch behavior, full resume, hardware/pilot evaluation and broader phase gates remain separate. Keep #219 open until its complete acceptance criteria and reviewed exit evidence hold.
