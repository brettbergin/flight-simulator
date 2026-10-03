# P1 native export evidence

Date: 2026-10-03. [NATIVE-EXPORT #15](https://github.com/brettbergin/flight-simulator/issues/15)
consumes accepted #11–14 foundations. This record describes a bounded export
proof; it does not accept P1, qualify an aircraft or publish a simulator release.
Reproduction and downstream API limits are in [tools/export](../../../tools/export/README.md).

## Observed owner-machine proof

The Windows x64 reference machine ran Godot 4.7.2, pinned matching release
templates, godot-cpp 4.5 standard precision, JSBSim 1.3.1, CMake 3.31.8, Ninja
1.13.1, Python 3.12.5 and MSVC 19.40.33813.0/toolset 14.40.33807. Native components
use the dynamic release CRT (`/MD`). The exported application ran without Node,
Python, compiler or development PATH. No global installation was changed.

| Evidence | Observed result |
| --- | --- |
| Actual editor and exported scene | Registered `FlightProofSession`; submitted pilot axes with exact uint64 sequence `9007199254740993`; recorded full v1 initial/final aircraft, atmosphere, applied command and observed event; reached tick 121. |
| Fixed tick/lifecycle | Pause at tick 121 held physics; closed calls rejected; repeated close, destructor and extension termination joined the worker. |
| Wire rejection | Numeric sequence, unknown field, unsupported authority/version, nonfinite axes, oversized step batch and duplicate open rejected; malformed initializer closed cleanly. |
| Portable environment | Empty PATH, isolated profile/TEMP, working directory outside package, spaces and Unicode relocation passed. Actual JSBSim and all three CRT modules resolved inside the portable payload. |
| Missing library control | Quarantined root and `bin/` JSBSim DLLs in a disposable export; startup failed visibly with no positive proof marker. |
| Source closure | 286 archive entries: 279 byte-identical upstream library files plus seven original wrapper/build/inventory files; no upstream aircraft/engine/system XML; repeated generation had identical bytes. |
| Fresh source rebuild | 108 MSVC build steps completed. Source/header/compile/import receipts retained; vendor hashes unchanged. |
| Actual DLL replacement | Only JSBSim DLL copies changed. Actual loaded replacement path/hash matched the rebuilt library. Commands, snapshots and events preserved finite-state/unit semantics within frozen `1e-9` absolute / `1e-12` relative tolerance; strings/integer-wire fields exact. |
| Package audit | Six declared component identities, required notices/primary Microsoft terms, source/replacement/module evidence and reviewed selected CRT pins passed the combined rights/integrity audit. Eight meaningful runtime rejection test groups passed. |

Observed baseline JSBSim DLL SHA256:
`7963d908c74a039e0e8d0664090fad33b777c60e38e9e6e9bb5d85d5da6f7948`.
Independently rebuilt replacement SHA256:
`45625ee1eff952fe41d48613c8ecd8ce065cb70d6bdb4bc9f297dad01eccbd49`.
Different debug paths/build options may produce different binary hashes; application
startup does not enforce one JSBSim binary hash. The witness ties this experiment
to the actual loaded module rather than merely a DLL present in a directory.

Reviewed corresponding-source archive SHA256:
`73f478b7e411517a72bff961ba73b33d69168945bcf3e813e4b107644e58e4e6`,
3,766,829 bytes. Acquisition commit is
`3b25f25e49b42d0489c04ac805674fc1450ca579`; acquisition ZIP digest remains distinct.
The source inventory/build wrapper preserves LGPL library replacement/debugging
permission and original component attribution. Microsoft components retain their
separate distributable-code terms, not the project's MIT license.

The selected local CRT is version 14.40.33810.0 from release redist revision
14.40.33807. The reviewed-runtime inventory digest is
`eea106b997c65c9c40a294f9ebf36d6d3444f53dc484ad1b4fc0ed979ac8b51d`;
the compiler-bound selected-build digest is
`8dbfb218b13a95cb401e19aa0019e43fd6f9f0e239c416af04df64a9858c2c13`.
Exact file hashes and governing terms are in the
[CRT register evidence](../../../third_party/licenses/evidence/microsoft-vc143-crt.md).
These local identities do not authorize older-runtime use with hosted 14.44 builds.

## Automation and remaining limits

Native CI exercises the real typed bridge in both pinned Godot editors. Windows
additionally runs release export, portable negatives, fresh source rebuild,
replacement and package audit. Unknown hosted CRT identities fail packaging
until independently reviewed/pinned; the evidence artifact preserves their
concrete source/version/signature/hash information. No simulator binaries or
source archives are published by this CI job.

Raw proof/build/import logs remain in ignored `.local/export-proof/` and native
CI evidence artifacts. Paths in raw local logs are not committed; this record
contains portable identities and results. CI run/head identifiers are added in
the issue completion record after final independent review.

Immediate cold editor first-discovery shutdown crashed the pinned engine.
Bounded paced import (`--quit-after 120 --frame-delay 100`, 120-second watchdog)
passed without an engine patch. Native lifetime markers and separate normal,
destructor and malformed-input runs remain required; the workaround is not a
claim about a fully developed application's shutdown behavior.

The proof has a minimal visible status label and headless assertions. It does not
provide flight controls, a cockpit, scenery, renderer performance, persistence,
ground operations or calibrated C172S aerodynamics. #18 owns representative visual
proof; #20 owns the production asynchronous simulation/frame loop; #61 owns final
Windows release packaging. Pilot/instructor evaluation and later phase gates remain open.
