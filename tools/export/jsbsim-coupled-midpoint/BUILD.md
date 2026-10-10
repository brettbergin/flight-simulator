# ADR015 library-only corresponding source

The separate schema3 variant is jsbsim-1.3.1-event-aware-coupled-midpoint-v1.
Its 293 regular files contain 279 vendor paths (275 pristine and four modified),
four pristine before-images, and the closed wrapper/manifest/recipe roster.
Upstream is JSBSim 1.3.1, commit 3b25f25e49b42d0489c04ac805674fc1450ca579.
The exact replacement recipe reconstructs directly from verified pristine
source. Preserve schema1 and schema2 archives independently.

Invoke each variant in a separate Python interpreter; cached helper modules
from another variant are rejected. Verify/repack using Python 3.12+ standard library:

```
python verify.py --root .
python pack.py --root . --output ../source-a.zip
python pack.py --root . --output ../source-b.zip
```

Build in a Windows x64 VS2022 Native Tools prompt with CMake 3.31.8,
Ninja 1.13.1 and a fresh external directory. Dynamic release CRT (/MD) and
matching patched headers are required for ABI consumers.

```
cmake -S . -B ../jsbsim-build -G Ninja -DCMAKE_BUILD_TYPE=RelWithDebInfo -DCMAKE_EXPORT_COMPILE_COMMANDS=ON -DCMAKE_MAKE_PROGRAM=C:/path/to/ninja.exe
cmake --build ../jsbsim-build --target libJSBSim --parallel 6 --verbose
```

Expected outputs: bin/JSBSim.dll and lib/JSBSim.lib. The wrapper qualifies only
libJSBSim and disables docs, language bindings, tests, PkgConfig and system
Expat. Source verification is an evidence audit, not a permission mechanism;
recipients may edit preferred source and rebuild. Such edits identify a new
source variant and require corresponding qualification before product claims.

Both FGPiston.cpp and FGPropeller.cpp receive /fp:strict in the actual Propulsion
OBJECT target directory. Before numerical execution, inspect exactly one
compile_commands.json entry for each unit plus both actual verbose compiler
invocations. Reject conflicting /fp:fast or /fp:precise and implicit CL/_CL_
flags; record compiler, SDK, tool environment and all output/import hashes.
The repository Linux route requires -fno-fast-math -ffp-contract=off
-frounding-math on both units with actual-command verification. No contraction
or unrelated final-DLL flag substitutes for the two source-unit checks.

No aircraft XML, binaries or Microsoft redistributables enter this archive.
Retain vendor/COPYING, vendor/README.md, SimGear, GeographicLib and MSIS grants;
LICENSE.first-party.txt applies only to the first-party wrapper work.

The new API changes C++ ABI: rebuild all consumers with matching patched headers.
Actual address-resolved module identity, numerical references, original coupled
tests and relocated exported-player replacement remain separate. An exported
replacement must preserve every other payload byte and missing-library/close+join
checks. No runtime hash allowlist may block an ABI-compatible user-modified DLL;
relevant LGPL modification/debugging rights remain available. This source
package establishes no numerical, runtime, aircraft, pilot, training-credit or
phase acceptance.
