# Durable local-player contract and independent references

Date: 2026-10-11. Issue [#218](https://github.com/brettbergin/flight-simulator/issues/218). Status: complete proposed contract input set; source checks, protected CI and checked merge remain acceptance gates. This document records contract design evidence, not storage/runtime qualification.

## Reviewable outcome

[ADR026](../../decisions/026-durable-local-players-and-practice-history.md) defines two named local players and Guest, deliberate Controls/Audio Save, source-bound practice history, selected-player new-file export and logical deletion. The original records, protocol, recovery policy, exact SQL and lossless preference codec are supplemented by four explicitly allocated normative companions: [lifecycle](../../contracts/local-players/service-lifecycle-amendment-v1.md), [full records](../../contracts/local-players/full-record-reference-amendment-v1.md), [reservation/spool](../../contracts/local-players/reservation-and-export-spool-v1.md), and [test scheduler](../../contracts/local-players/test-scheduler-v1.md). Eleven normative inputs are bound by the [compiled allocation](../../contracts/local-players/compiled-source-allocation-v1.json); thirteen additional fixed files bind the three new reference packets separately. The seventeen storage source roles, fifteen controls, separate storage GDExtension and five future CTests retain their exact allocation. Actual code/compiler/binary hashes bind after source review and before compilation/execution; hashes of unwritten code are not contract prerequisites.

The bounded roadmap amendment permits only #218/#219/#220 to advance on the accepted original-profile contracts. Store and journey consumers remain blocked until complete checked #218 acceptance. Simulation retains flight authority, all fourteen wire formats remain unchanged, ADR020 has only the named-player explicit-save exception for its four existing Audio options, and ADR025 Views remains session-only. The canonical plan preserves the two previously published #215 ownership additions alongside this contract's seventeen additions.

## Independent references and precise scope

| Packet | Frozen scope | Expected bytes SHA-256 |
|---|---|---|
| [Original value references](../../../tests/persistence/local_players/reference/README.md) | 114 type/bit/canonical/U64/paging cases and explicitly unexecuted boundary recipes | `1ffaa82ae54a18dc5c9ec3d6c49760ed3b2d6c27abf77783572c6a9b3902d962` |
| [Service references](../../../tests/persistence/local_players/service_reference/README.md) | 66 typed cases: 42 declarative and 24 conditional observations | `61078c6aea80de7d15b2d0fe8a94a796a24086ea270f64e98fa9074aa8aa7860` |
| [Complete record references](../../../tests/persistence/local_players/full_record_reference/README.md) | 110 complete type/bit/record/cross-column/canonical-export cases | `164aad9b74de33b04a6a69734116eab899dceaf696135137b9963f679968b722` |
| [Reservation references](../../../tests/persistence/local_players/reservation_reference/README.md) | 16 arithmetic cases and 13 conditional allocator/scheduler/actor recipes | `2bbe1ced7a5d30ae1a469eb5da1675779028fceaf9779fb309d78e356b22cd86` |

Historical PROPOSED/UNRATIFIED fields and source-binding files identify immutable authored snapshots. Ratification through checked contract adoption does not rewrite those snapshots, import consumer output, or turn a logical recipe into an executed test. The original 72 design recipes remain unchanged and unexecuted. Conditional service/file/fault values are premises for actual tests, never fabricated Win32, SQLite, worker or crash observations.

The complete small export is 7641 exact bytes, SHA-256 `1bb1781e8484ceafc6ce2e3ae421112d71004bdbaae713127c7a31d50f28f2b0`. Every selected player's practice row belongs to one coherent export snapshot in numeric creation-sequence descending order, including empty arrays. The 30000-value/depth12 scans apply separately to each PreferencesStorage envelope and decoded preference payload before tag restoration; they do not cap the aggregate history export. No frozen fixture or existing limit was changed to fit that clarification.

Lifecycle rules distinguish safe quiescence when no worker ever existed from actual exit/join after worker creation; retained terminal receipts remain pollable under the closed-state contract. Startup interruption preserves the last actual flight observation timestamp. Reservation rules retain the 32MiB native arena, 16-outstanding ceiling, full delivery-overlap charges and exclusive 18MiB export spool. The scheduler retains distinct actual recovery read/write before/after sites, including partial-call occurrences, within a checked 524288-event test-only capacity; v1's insufficient proposed capacity remains historical private failed evidence, not an adopted contract.

## Closed-field export size proof

Independent source review and separate integer/escaping calculations established these conservative upper bounds under the exact current closed records and canonical codec:

| Complete canonical value | Upper bytes | Reason |
|---|---:|---|
| Player | 352 | Seven closed fields; name at most40 Unicode scalars/160 UTF8 bytes, no C0/DEL, at most4 canonical bytes per allowed scalar |
| PracticeSource | 658 | Closed ASCII session/source identifiers, two supported model triples, four variant IDs and fixed hash/enum fields |
| PracticeSummary | 1215 | All17 practice fields, bounded U64/UTC/IDs/source and exactly `{linked:BOOL}` archive summary |
| PlayerPreferences payload | 524601 | Two canonical tagged slots at most262144 bytes each plus313 fixed/Audio bytes; binary64 tags are35 bytes |

The complete inner payload is at most `40 + 352 + 524601 + 2000*1215 + 1999 = 2956992` bytes, below the existing18MiB spool. Compact canonical inner JSON contains no literal C0 bytes, so outer String escaping expands each byte by at most2; fixed outer fields cost145 bytes. Thus the outer export is at most `145 + 2*2956992 = 5914129` bytes, below the unchanged32MiB cap. These direct bounds count canonical slot lengths and closed fields; arbitrary stored blob lengths alone would not prove them because noncanonical short escapes can grow on canonical re-encoding. Independent field maxima deliberately relax cross-field compatibility and are conservative bounds, not claims of a valid maximum-size store fixture.

A qualified valid current-v1 store cannot exceed the32MiB export cap under these premises. Defensive over-cap tests must explicitly target an invalid snapshot or low-level counting/writer boundary; they cannot fabricate a valid-store overflow by inserting unbounded records. Actual #219 source must enforce these exact canonical/field/slot premises, count/hash output before file effects, and qualify complete/near-cap witnesses. Different escaping, additional fields or embedding the PreferencesStorage envelope would invalidate this proof.

## Verification and remaining gates

Root read-only checks reproduced all110 full-record cases and the16 arithmetic/13 conditional reservation cases without changing any expected bytes. Independent reviews approved the complete records, lifecycle, final scheduler, reservations, exact input allocation, ownership-only plan and closed-field export bound. Actual combined-tree source checks passed: documentation validates131 planned issues,147 requirements and187 Markdown files; all fourteen wire schemas reproduce unchanged, all eleven contract regressions pass, and the unchanged renderer verifies nine phase briefs. The extracted Foundation CI step checked thirty exact raw LF pins and reproduced all four reference packets with the pinned Python runtime. Rights inventory/dependency checks pass for25 entries; the separate rights regression suite passed72 checks. These are source checks only. Protected checks on the final published head and reviewed merge remain acceptance gates.

Under #219, author and independently source-review the actual layout, canonical encoder, allocator/ownership, SQLite/VFS/Win32 operation sites, source/control identity and compiler/SQLite closure before compile/execution. Then qualify the real native storage service, all five CTests at their actual platform scope, failure/COMMIT-unknown/crash/recovery/lock/join behavior and shipping absence of test capabilities using authorized disposable roots/users. Under #220, qualify the complete A/B/Guest preference/history/relaunch/export/delete journey in editor, portable and rebuilt-library contexts. No production database IO, queue/thread, native storage build, Windows capability, installed-user or UI result is reported here.

SaveProof17 remains historical flight-only reconstruction, not current piston/contact restore. #34/#74/#36, aircraft applicability/fidelity, hardware/pilot and P2/P3 gates remain open. No official flight hours or training credit are awarded.


## Proposed remaining-row qualification amendment

The proposed [capability amendment](../../contracts/local-players/test-capability-v1.md#proposed-fixed-remaining-row-qualification-amendment), [scheduler terms](../../contracts/local-players/test-scheduler-v1.md#proposed-finite-remaining-row-qualification-campaign) and [compiled allocation](../../contracts/local-players/compiled-source-allocation-v1.json) define a second fixed child of the existing store CTest. Fifteen exact loadable reference cases require actual failed Store qualification; two exact primary-key collisions are setup applicability outcomes, never passing Store corruption tests. Frozen reference bytes and expected outcomes remain unchanged.

Each child retains a hard 16,384-event ceiling and 600-second supervisor deadline; the combined store limits are 32,768 events and an explicit 1,200-second CTest timeout. Other CTest deadlines and the 14,400-second overall Native limit remain unchanged. The conditional source pre-count is 9,900 records for the new child, subject to complete implementation/setup reconciliation before execution and hard overflow failure. These are proposed limits and source arithmetic, not observed runtime results.

Checked contract merge and adoption must precede consumers. Fresh compiled source/control/contract identities and actual qualification remain [#219](https://github.com/brettbergin/flight-simulator/issues/219) gates; actual player UI/relaunch/installed-account evidence remains [#220](https://github.com/brettbergin/flight-simulator/issues/220). This amendment adds no storage consumer, new fault hook, first-error SQLite witness or parent/phase acceptance.

The generated requirements mapping and existing #219 ownership remain unchanged:
PRD-027, PRD-028, PRD-029, UX-001, UX-002, UX-016, UX-017, UX-018, UX-019, UX-020,
UX-022, SAFE-028 and SAFE-029. This amendment supplies qualification planning for
those existing requirements and does not mark them accepted.


## Proposed bounded logical fault evidence

The separate proposed [capability amendment](../../contracts/local-players/test-capability-v1.md#proposed-bounded-logical-fault-evidence-amendment), [scheduler](../../contracts/local-players/test-scheduler-v1.md#proposed-bounded-logical-fault-qualification) and [allocation](../../contracts/local-players/compiled-source-allocation-v1.json) define two already-permitted real SQLite API interruption cases and one newly permitted, explicitly synthetic export-flush stage refusal. The latter retains real writes/temp ownership and tests error propagation, without attempting or fabricating a FlushFileBuffers return. Exact closed provenance, whole-state reconciliation, actual ACK/join/credits and an ordinary unarmed real-flush retry are mandatory.

This is source-only proposed design, not executed fault or storage acceptance. Checked merge/adoption precedes consumers; the checked fixed-row definitions remain unchanged. The conditional SQL-case estimate is 3,095 added to 11,970, or 15,065 records before any flush additions. Consumer source must independently freeze the flush contribution and complete total within the unchanged 16,384 first-child gate before output. The remaining-row child, combined limits, all five CTests and original nineteen crash recipes remain intact.

After fresh qualification these cases may satisfy bounded #219 logical error propagation. Physical rollback IO failure, observed FlushFileBuffers(false), disk-full/device failure and power-loss durability remain permanent exclusions, never passing mocks or implied fault observations. Native allocator/copy/worker-loss and normal poll-transfer evidence remain distinct; catastrophic engine/OS OOM is not certified. This proposal does not accept #219, installed #220 journeys, parents, aircraft or phase gates.

Bounded atomic-delivery evidence requires reviewed pre-ACK guards, actual complete two-result caller copies surviving another poll, and native whole-batch abandon/repeek/ACK tests. Actual recoverable engine output-construction-failure execution remains unqualified; no unreachable-state proof or engine allocator failure result is claimed. Public atomic transfer semantics stay unchanged, without inventing a new allocator fault framework or extending the accepted catastrophic-OOM exclusion.
