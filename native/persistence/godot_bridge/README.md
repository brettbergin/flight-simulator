# Separate local-player storage extension

Original MIT. Windows x64 production registers only `LocalPlayers` through
`flight_local_players_init`. The reusable storage core, fixed KnownFolder
adapter and static pinned SQLite are separate from the flight extension and
JSBSim. Registration opens no root, database or worker. Instance shutdown and
the SCENE terminator join active workers before extension teardown.

The production target has no test registration, capability factory or injected
root. Test wrappers have their own explicit target/resource and reuse the same
core/boundary. The shipping resource has no Linux library entry; Linux codec
qualification is separate from Windows storage qualification.

Build identity is reconstructed from the accepted closed source/control/input
rosters and actual configure/compiler/dependency provenance. A single configure
freezes the cache. The Root runner then generates the independently expected
identity resource and the three-definition header before compilation. Only
`storage_identity.cpp` force-includes that generated header. It is a generated
output, excluded from fingerprint inputs; missing output cannot produce a
valid library. Actual compile/link/object/archive/map and ClassDB observations
are separate mandatory qualification evidence.

This directory's source allocation is defined by
[ADR026](../../../docs/decisions/026-durable-local-players-and-practice-history.md)
and the [compiled allocation](../../../docs/contracts/local-players/compiled-source-allocation-v1.json).
Source presence or compilation alone establishes neither durable saves nor the
two-player/Guest relaunch journey.

The pinned CMake 3.31.8 Ninja rule places the Python link witness inside
`vs_link_dll`, preserving manifest handling and capturing the direct linker
arguments after manifest flags are appended. Storage uses `/INCREMENTAL:NO` so
one final link owns its fresh outputs. Root independently admits the exact plan,
tool hashes, receipt parent and generated command before each qualified build.

Configure declares the plan-digest file path before prerequisite archives
exist. After prerequisite compilation, Root admits the actual archive and
exclusively emits the exact link plan plus the closed
`LocalPlayersInvocationPlanDigest/v1` object (`schema`, `plan_path`,
`plan_sha256`). The launcher binds both files before execution and checks their
stability afterward. Their bytes are postcompile witnesses and are excluded
from compiled identity inputs. The qualifier implements this CLI and checks
actual global, directory and target launcher properties together with the
final generated rule.

Root compile witnesses use one independently frozen plan index for nine
invocations: SQLite C, five core C++, one Windows C++ and two production bridge
C++ sources. All four targets use a target-local exact-argv launcher. Compiler
PDB paths remain in argv but are shared target outputs checked only after the
target joins; objects are the unique fresh per-invocation outputs. The generated
compile-policy JSON exports configuration flag tokens and ordered target/source
arrays. Compile database file/directory/output metadata may identify object
locations; its command string never supplies expected arguments.

[Backend qualification](../../../docs/evidence/P3/local-players-store.md) and
[implementation progress](../../../docs/evidence/P3/local-players-storage-progress.md)
records measured source/build snapshots and outstanding gates. For #219, fresh
current-source native/ClassDB and root-free production API checks, exact
source/SQLite/VFS/compiler/CRT/rights identity, affected flight/shared-control
qualification and required CI precede checked store acceptance. Old snapshots
do not qualify changed source or a later integration. #220 then implements the
UI and delivery: the accepted twelve-role package aggregate, both-extension
corresponding source, actual editor/portable/rebuilt-replacement PCK and module
receipts, storage rebuild/replacement, relaunch and installed-user journey remain
mandatory there. No combined shipping-package result is claimed by this backend
report. Broader phase gates, aircraft fidelity and pilot acceptance remain separate.
