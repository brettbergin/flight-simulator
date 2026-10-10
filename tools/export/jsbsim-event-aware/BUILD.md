# Proposed ADR014 library-only source variant

This separate schema2 recipe contains the complete modified preferred source,
277 unchanged upstream files and the two explicitly reviewed FGPropeller files.
Upstream remains JSBSim1.3.1 at commit
3b25f25e49b42d0489c04ac805674fc1450ca579; the variant is
jsbsim-1.3.1-event-aware-constant-power-v1. Before-images plus vendor after-images
are the byte-replacement patch. No textual patch interpreter is used.

The two FGPropeller modifications were authored by flight-simulator project
contributors on 2026-10-09. Exact before/after bytes, upstream acquisition
and the materializer are bound by patches/event-aware-constant-power-v1/recipe.json.
Source reconstruction and strict compiler flags require verification before
numerical use. This source package establishes no numerical, aircraft or pilot acceptance.

The exact291-member manifest and unchanged upstream inventory cover source and
build controls; the external archive SHA256 covers the manifest. Verify/repack
using Python3.12+ stdlib. Verification reconstructs all279 pristine files from
the277 unchanged files and two before-images, then rematerializes the entire
modified source in a disposable directory. No repository/cache/network needed.

```
python verify.py --root .
python pack.py --root . --output ../source-a.zip
python pack.py --root . --output ../source-b.zip
```

Build the directly editable vendor source using Windows x64, VS2022 MSVC,
CMake3.31.8 and Ninja1.13.1, from an x64 Native Tools prompt. Use a fresh external
build directory, dynamic release CRT(/MD) and compatible toolset for every C++
ABI consumer. Record compiler, SDK, environment version variables, flags and
actual output/import hashes. Python/source verification is an evidence audit,
not a compilation permission check: recipients may edit vendor source and
rebuild directly; deliberate edits no longer identify the reviewed variant.

```
cmake -S . -B ../jsbsim-build -G Ninja -DCMAKE_BUILD_TYPE=RelWithDebInfo -DCMAKE_MAKE_PROGRAM=C:/path/to/ninja.exe
cmake --build ../jsbsim-build --target libJSBSim --parallel 6
```

Expected outputs are bin/JSBSim.dll and lib/JSBSim.lib. The wrapper disables
docs/Python/Julia/Matlab, tests/PkgConfig and system Expat; only libJSBSim is
qualified. Upstream install/CPack/dist and models are outside this selection.
This schema2 wrapper applies `/fp:strict` specifically to FGPropeller.cpp in the
libJSBSim target's directory scope. Inspect the actual Ninja compile command
before a numerical build; do not accept inherited `/fp:fast` or implicit FMA
contraction. The future repository Linux route must likewise select
`-fno-fast-math -ffp-contract=off` for this source and prove the actual flags.
Record actual configure/build commands and results separately; source verification does not establish compilation success.
No aircraft XML, binaries or Microsoft redistributables enter this archive.
Keep original grants/notices in vendor/COPYING, vendor/README.md, SimGear,
GeographicLib and MSIS; first-party MIT does not replace the vendor LGPL grant.

The new API changes C++ ABI; build matching patched headers and all consumers.
Do not relabel an old DLL. Source closure, exact numerical qualification and
actual loaded-module observations are distinct. A separate fresh rebuild and
Unicode relocated exported-player replacement must keep every other payload
byte unchanged and retain missing-library/close+join checks. No runtime binary
hash allowlist may prevent an ABI-compatible user-modified library; relevant
LGPL modification/debugging reverse-engineering rights remain available.
No aircraft, pilot, hardware, training-credit or phase qualification is implied.
