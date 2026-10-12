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

The proposed pinned CMake 3.31.8 Ninja rule places the Python link witness inside `vs_link_dll`, preserving its manifest handling and capturing the direct linker arguments after manifest flags are appended. Storage uses `/INCREMENTAL:NO` so one final link owns its fresh outputs. Root must independently admit the exact plan, tool hashes, receipt parent and generated command before build. This source proposal has not been configured or executed. No compiler command, archive/map closure or runtime result is established.

The configure declares a future plan-digest file path, not a digest of an archive that does not exist yet. After prerequisite compilation, Root admits the actual archive and exclusively emits the exact link plan plus closed `LocalPlayersInvocationPlanDigest/v1` object (`schema`, `plan_path`, `plan_sha256`). The launcher binds both files before execution and checks their stability afterward. Their bytes are postcompile witnesses and never compiled identity inputs. The qualifier successor must implement this declared CLI before execution; the earlier witness subset does not yet support it. Actual global, directory and target launcher properties are checked, with a final generated-rule check still required.

Root compile witnesses use one independently frozen plan index for nine invocations: SQLite C, five core C++, one Windows C++ and two production bridge C++ sources. All four targets use a target-local exact-argv launcher. Compiler PDB paths remain in argv but are shared target outputs checked only after the target joins; objects are the unique fresh per-invocation outputs. The generated compile-policy JSON exports configuration flag tokens and ordered target/source arrays; compile database file/directory/output metadata may identify object locations, while its command string never supplies expected arguments. Actual generation/plan parity, complete runner and native qualification remain required.
