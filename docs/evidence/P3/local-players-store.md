# Local-player storage backend

Status: checked backend accepted through [PR239](https://github.com/brettbergin/flight-simulator/pull/239), merged 2026-10-12 as `783e8fc1576b0a5758a967ccdc5333c7ba1636e8`. All twelve CI checks passed on final head `f2da3aaa44b604b5a3e41083603c8e411dce9aa8`; the merged tree is identical. #219 is closed. Player-selection UI, the combined #220 delivery journey and P3 acceptance remain separate.

## Backend handoff

The separate Windows storage extension implements the accepted [durable-player contract](local-players-contract.md), [compiled allocation](../../contracts/local-players/compiled-source-allocation-v1.json), [records/lifetimes](../../contracts/local-players/records-and-lifetimes-v1.md), [protocol](../../contracts/local-players/protocol-v1.md) and [test capability](../../contracts/local-players/test-capability-v1.md). It uses pinned static SQLite and one owned worker/connection. Storage does not restore flight state, command the aircraft or establish official flight hours.

The six #219 backend criteria are covered by independently reviewed compiled source and successful source-bound suites:

| Criterion | Evidence and scope |
| --- | --- |
| SQLite/service boundary | Real SQLite C API; bounded owned requests/results; owner-thread ClassDB validation; worker/core separation; FIFO transfer, terminal reservation and joined shutdown. |
| Windows ownership/recovery | Fixed production KnownFolder adapter and cooperating-instance lock; real disposable-root Windows guards, exclusive-WAL ordering, copies, recovery sets and ownership-bounded management. The actual installed-user journey is #220. |
| Exact durable records | DDL/meta/schema/codec identity; full legacy/v2 Controls and Audio type/bit round trips; optimistic/U64 boundaries, immutable cursors, full 2,000-record paging/export/prune/refill and source-bound summaries. |
| Commit/error semantics | Actual SQLite interruption around transactions and post-COMMIT verification; uncertain/read-only/refusal/reconciliation assertions; no lost accepted work or fabricated join. These are source-bound successful assertions, not a separate per-assertion SQL trace. |
| Export/delete | Read-snapshot export, CreateNew/no-replace move/verification and retention/retry checks; actual sharing32 and range-lock33 refusals. The selected pre-flush refusal is explicitly synthetic; no unattempted Win32 result is reported. |
| Independent qualification | Five native CTests, nineteen process-crash recipes/twenty actors/thirty-eight stages, original-file proofs, complete fixed remaining-row child, actual ClassDB numeric-family parity and shipping/test separation. Frozen references and resource/event ceilings are unchanged. |

The remaining-row child covers fifteen loadable DN/SQLN cases and two duplicate-primary-key setup applicability cases. The latter observe SQLite constraint rejection rather than pretend to load an impossible Store. Its 2,700 events and the first Store child's 11,300 events remain below the unchanged 16,384 per-child and 32,768 combined ceilings. The 41,231,073 combined Store assertions are looped checks, not independent features or flights. The full selected-player export remains 2,387,415 bytes, SHA256 `c07ca164caffac111c5b7e3724dc00eed439502fe7bfc17523be4fa01cab74fc`.

## Measured Build44

Accepted base: `61c4461beb139b63e7aeccf481aa46c163a820d9`, with forty reviewed storage overlays and the closed 17 component/15 control/11 normative memberships. The independently audited raw source inventory contains 938 files and 242 directories. The measured compile review passed 34,904 passive checks over 34 compiler/linker invocations, seventeen stages and fourteen AMD64 artifacts. It binds SQLite/VFS/compiler flags, source, objects, archives, resources, DLLs and CRT; compile success alone is not execution.

| Saved evidence | SHA256 |
| --- | --- |
| Compile review | `ab5bffaf245a7a3dd378356cac32d4502acf9d932785c77c0fb9315cf9bd55a8` |
| Actual compile terminal | `141c6e458139be3df24c779339adf0aa211042d077b1861feb89041f8c853be0` |
| Source assembly | `afd9cbbff89416e5891cfd790589ee14cc99ac3aa0c91dabe2a3e58657ce21b7` |
| Test manifest | `8e26fd0d709361ff04d9689b21f36b74063153e2033be0261e090a95c7934502` |
| Build receipt | `69a1b3b28a14adbd728eb28592dad1669f2593fddd96d42c36c52cca4357ec6f` |
| Native receipt | `82bf04412a0f50889f8bd76efaa4662ea674f58fb8a34f8ca5ef61d6f306a9e2` |
| Native independent review | `7ca1db7e4b687355efee54262ad02eb4cec6f321ad5c56fcb08d13c0e69d6495` |
| Bridge receipt | `9e31988474fedc5c74ab8f7470a5d2762357bd9efc424c85d500a1f58867530f` |
| Bridge independent review | `06c66bf09526c3839855a0829782436d2e8a52d3d627144de5aa7f8f828433d3` |
| Root-free shipping probe | `e73ed81e276630143b071ada424e986260a0a5f7ca73c59fb3e7c16871c6c556` |

Native independent review passed 5,927 checks over 734 saved raw files, including all five CTests, nineteen crash recipes, twenty actors, thirty-eight stages, 1,362 actor events and 166 reservations. Actual Bridge execution passed 1,209 checks with zero failures; independent saved-evidence review passed 325 checks over 113 raw files. It binds complete preference normalization/type/bit and SQL save/load tests plus the poll-transfer cases. The shipping probe observed exactly `begin_shutdown`, `poll`, `start`, `start_management`, `status`, `submit`, `try_join`, with the test class absent. It created no storage object and called no start method. Processes were observed closed and joined; this registration probe is not an installed-user write journey.

Selected source pins: native driver `2268934298b9fa9bccd8132367db742776a8b2ce9c25332ae271ed96b049f8e7`, qualifier `b7d1f21bbc069476ca3bf5a2106669cc64b98cc473faf0975f4d2049787fe4c3`, ClassDB test `a0ad2595ae893b05619375bde6ef2f6a683bad99492987751975c15f5dba811d`. Production component/control/contract digests are `4ebe5e00b00489966649ca342adfce622cbfcf61da23b540b65a1a53da2928d4`, `2d15109df3013bb03b68ac5b18696d1f5dcbf5d7609a12324a7237349c082a6a`, `7dc11f0aeb927fd643bc1a43a97450f5908ac01c5f29b3ab2d8df2a789af3b2f`.

## Retained failures and limits

Build41 stopped before compilation on stale public-runner producer pins. Build42 compiled but failed an impossible physical read of a live exclusive SQLite database; two test-only snapshots were removed, retaining complete typed/SQL and export proofs. Build43 Native passed, but Bridge failed the test's assumption that two immediate submissions must both be admitted. The accepted nonblocking worker reservation can refuse the second while busy; the actual error code was not recorded. Build44 changes only that test's first-terminal-ready barrier before the second submit, retaining the original two-result FIFO/acknowledgement/type/bit checks. No production admission, sharing policy, reference or threshold was relaxed. Earlier failures and passive-reader corrections remain in [implementation progress](local-players-storage-progress.md) and retained local evidence.

Actual physical rollback failure, an observed OS flush failure, disk-full, hardware power loss, catastrophic engine/OS OOM and arbitrary partial-I/O behavior are not claimed. The synthetic flush case records `operation_attempted=false` and a null Win32 error; it proves the declared logical refusal/retention/retry path. Its logical typed/SQL before/after proofs do not claim a live physical original-four snapshot. Process-crash coverage is not hardware power-loss qualification. No owner profile is published or opened by the root-free probe.

Issue #219 hands off checked backend source after required affected-flight/shared-control CI. #220 must still deliver the accepted twelve-role `LocalPlayersPackageAggregate/v1`, both-extension corresponding source/SQLite/CRT/notices closure, actual editor/portable/rebuilt-replacement PCK/module and storage-replacement evidence, A/B/Guest screens, relaunch and disposable installed-user KnownFolder journey. These mandatory exits are not inferred from separate component receipts. Parent #34/#74/#36, broad P2/P3, aircraft fidelity and pilot evaluation remain open. Final exact-head CI and checked backend merge are recorded in [PR239](https://github.com/brettbergin/flight-simulator/pull/239).
