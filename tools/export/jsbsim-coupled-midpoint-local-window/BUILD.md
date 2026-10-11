# ADR024 local-window library-only corresponding source

The distinct schema3 variant is
`jsbsim-1.3.1-event-aware-coupled-midpoint-local-window-v2`.
Its complete source archive has 293 regular files: 279 vendor paths (275 pristine,
four modified), four pristine before-images and the closed wrapper/recipe/manifest
roster. Upstream remains JSBSim 1.3.1 commit
`3b25f25e49b42d0489c04ac805674fc1450ca579`. The exact replacement recipe
reconstructs directly from verified pristine source. Preserve all historical
pristine, held-power and coupled-midpoint-v1 archives separately.

This variant inherits all four ADR015 preferred-source after-images. Only
FGPropeller.cpp adds ADR024 admission: the whole-endpoint certificate runs first;
a structured uncertifiable result alone permits one strict interior half window.
Both attempts share eight total splits, at most 18 interval evaluations and a
sequential nine-slot work array. The unchanged 64-step solve is reached only after
strict exact remaining-time admission. No source event, stop or donated time is
created at that private boundary. Model bytes, engine/fuel chronology, source law,
public method name and physical/reference budgets are unchanged.

Invoke each source variant in a separate Python interpreter; cross-variant cached
helper modules are rejected. Python 3.12+ standard-library verification/repacking:

```text
python verify.py --root .
python pack.py --root . --output ../source-a.zip
python pack.py --root . --output ../source-b.zip
```

Build a complete materialized archive in a Windows x64 VS2022 Native Tools shell
with the project's pinned CMake/Ninja, using a fresh external directory:

```text
cmake -S . -B ../jsbsim-build -G Ninja -DCMAKE_BUILD_TYPE=RelWithDebInfo -DCMAKE_EXPORT_COMPILE_COMMANDS=ON -DCMAKE_MAKE_PROGRAM=C:/path/to/ninja.exe
cmake --build ../jsbsim-build --target libJSBSim --parallel 6 --verbose
```

Expected outputs are bin/JSBSim.dll and lib/JSBSim.lib. Dynamic release CRT /MD
and matching inherited patched headers are required. The wrapper builds only the
library, disabling docs, language bindings, tests, PkgConfig and system Expat.
Both FGPiston.cpp and FGPropeller.cpp receive /fp:strict in the actual Propulsion
OBJECT target. Inspect their actual compile_commands.json entries and verbose
compiler invocations; reject conflicting /fp:fast, /fp:precise and implicit CL/_CL_
flags. The repository Linux route requires -fno-fast-math -ffp-contract=off
-frounding-math on both units. Record the actual compiler, SDK, tool environment
and output/import hashes; flags or availability alone establish no qualification.

The inherited ADR015 API differs from pristine upstream. This private admission
amendment adds no header/API/layout change relative to coupled-midpoint-v1;
matching source/build and actual compatible-library evidence remain required.
Source verification is an evidence audit, not permission to modify: recipients
may edit preferred source and rebuild without an application DLL-byte allowlist
forbidding ABI-compatible user replacements. A changed source needs its own
qualification before product claims. LGPL debugging/replacement rights remain.

No aircraft XML, binaries or Microsoft redistributables enter this archive.
Retain vendor/COPYING, vendor/README.md, SimGear, GeographicLib and MSIS grants;
LICENSE.first-party.txt covers first-party wrapper work only. Retain exact source,
notices, modification record and rebuild scripts with the corresponding DLL.
Numerical qualification, original physical/default/replay tests, address-resolved
module identity and relocated exported-player replacement are separate gates.
This package establishes no aircraft, pilot, training-credit or phase acceptance.
