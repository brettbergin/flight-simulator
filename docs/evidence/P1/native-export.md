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
| Portable environment | Empty PATH, isolated profile/TEMP, working directory outside package, spaces and Unicode relocation passed. Actual JSBSim and all five required CRT modules resolved inside the portable payload. |
| Missing library control | Quarantined root and `bin/` JSBSim DLLs in a disposable export; startup failed visibly with no positive proof marker. |
| CRT isolation controls | Removed each of five required CRT files from both payload locations in separate copies. Every run failed; installed system-runtime fallbacks were rejected by actual loaded-module path checks. |
| Dependency closure | Independently parsed every staged PE binary's direct and deferred import tables, compared against the selected compiler's dependency report and enforced complete non-system staging. Windows OS/API-set/UCRT dependencies remain system-managed. |
| Source closure | 286 archive entries: 279 byte-identical upstream library files plus seven original wrapper/build/inventory files; no upstream aircraft/engine/system XML; repeated generation had identical bytes. |
| Fresh source rebuild | 108 MSVC build steps completed. Source/header/compile/import receipts retained; vendor hashes unchanged. |
| Actual DLL replacement | Only JSBSim DLL copies changed. Actual loaded replacement path/hash matched the rebuilt library. Commands, snapshots and events preserved finite-state/unit semantics within frozen `1e-9` absolute / `1e-12` relative tolerance; strings/integer-wire fields exact. |
| Package audit | Six declared component identities, 42 component file declarations, required notices/primary Microsoft terms, source/replacement/module/import evidence and reviewed selected CRT pins passed the combined rights/integrity audit. Twelve meaningful runtime rejection test groups passed. |

Observed baseline JSBSim DLL SHA256:
`7963d908c74a039e0e8d0664090fad33b777c60e38e9e6e9bb5d85d5da6f7948`.
Independently rebuilt replacement SHA256:
`793a57e7a4cd6093fa2242775dab1da3e0a6b57f3be329b888f48153b02808d7`.
Different debug paths/build options may produce different binary hashes; application
startup does not enforce one JSBSim binary hash. The witness ties this experiment
to the actual loaded module rather than merely a DLL present in a directory.

Reviewed corresponding-source archive SHA256:
`f6ea1c2771de5594f0047e27b2facb605dc958c7c8e0008dd43e73df88bf6a62`,
3,766,826 bytes. Acquisition commit is
`3b25f25e49b42d0489c04ac805674fc1450ca579`; acquisition ZIP digest remains distinct.
The source inventory/build wrapper preserves LGPL library replacement/debugging
permission and original component attribution. Microsoft components retain their
separate distributable-code terms, not the project's MIT license.

The selected local CRT is version 14.40.33810.0 from release redist revision
14.40.33807. The reviewed-runtime inventory digest is
`22586d40a79d34f6005fae5abf63e4d941b9e9b6fbb02d2fc608eb0461f4c87a`;
the compiler-bound selected-build digest is
`0c604c481e7c05d6f70824f893d794e7bbc1e6590e1835494bac5d7dde4fadc2`.
Exact file hashes and governing terms are in the
[CRT register evidence](../../../third_party/licenses/evidence/microsoft-vc143-crt.md).
These local identities do not authorize older-runtime use with hosted 14.44 builds.

Independent review found the initial three-file experiment had omitted direct
imports `MSVCP140_2.dll` and `MSVCP140_ATOMIC_WAIT.dll`; Windows supplied installed
copies despite empty PATH. That experiment is superseded. The corrected proof
stages and witnesses all five files, rejects modules outside the payload and
passes each missing-file control. The source ZIP changed only three first-party
EOF whitespace bytes plus their manifest digests; vendor/compiled inputs remained
unchanged and the new exact archive received independent closure review.

The independent source rebuild retains the unmodified upstream MSVC C4715
warning in `FGTable::GetValue` in its build log. No vendor warning/source patch is
hidden by this proof; first-party native targets compile with warnings as errors.

## Automation and remaining limits

Native CI exercises the real typed bridge in both pinned Godot editors. Windows
additionally runs release export, portable negatives, fresh source rebuild,
replacement and package audit. Unknown hosted CRT identities fail packaging
until independently reviewed/pinned; the evidence artifact preserves their
concrete source/version/signature/hash information. No simulator binaries or
source archives are published by this CI job.

The first [native CI run](https://github.com/brettbergin/flight-simulator/actions/runs/37156502551)
at head `30d195ac58f7db58ffee0d5ed83284ef0e980824` completed the actual Windows
editor/export, five missing-runtime controls, source rebuild and DLL replacement,
then intentionally failed package clearance on unknown hosted CRT pins. The
concrete 14.44.35211.0 inventory received two independent metadata/process-witness
reviews and is now separately pinned; future changes remain rejected. Its actual
release folder is 14.44.35112 and compiler toolset 14.44.35207.
Linux initially failed editor loading because the staging recipe omitted the
upstream `libJSBSim.so.1` runtime filename. The corrected recipe stages identical
dereferenced library bytes under both link and SONAME filenames; no dependency
or engine/library source pin changes. Final current-head CI remains required.

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
