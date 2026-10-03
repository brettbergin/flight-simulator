# JSBSim 1.3.1 library-only corresponding source

This is the corresponding source for the original synthetic native integration
proof. It does not establish aircraft fidelity or a qualified training device. No aircraft, engine, system
or other model XML is included. Runtime models are separately licensed content.

The vendor directory contains 279 byte-identical files from JSBSim commit
3b25f25e49b42d0489c04ac805674fc1450ca579. Acquisition ZIP SHA256 is
df57467a831cfa3ee3cadcb98d8291ce56bb11976e35dd9e93c94201ff1420d5.
That acquisition digest is different from the digest of this filtered archive.
upstream-file-inventory.json records the source selection and hashes. All src
files are retained except the unused nested MSIS test and its CMakeLists.txt.
Root CMakeLists.txt, COPYING, README.md and AUTHORS are retained unmodified.
Original grants and attribution remain in vendor/COPYING, vendor/README.md,
vendor/src/simgear/xml/COPYING, vendor/src/GeographicLib/LICENSE.txt,
vendor/src/models/atmosphere/MSIS/DOCUMENTATION and SimGear headers.
The original first-party wrapper and verification/packing scripts are MIT under
LICENSE.first-party.txt; that license does not replace the vendor library grant.

## Clean supported build

Use Windows x64, VS 2022 MSVC x64 release toolchain, CMake 3.31.8 and Ninja 1.13.1.
Our measured local toolchain is MSVC 19.40.33813.0 (toolset 14.40.33807).
Open the x64 Native Tools developer prompt or initialize vcvars64.bat in the
current process. Supply installed CMake/Ninja executable paths when they are not
on PATH. No full JSBSim acquisition or Python/Node dependency is required to build.
Choose a fresh build directory OUTSIDE the extracted source directory.

```powershell
python verify.py --root .
cmake -S . -B ../jsbsim-build -G Ninja -DCMAKE_BUILD_TYPE=RelWithDebInfo -DCMAKE_MAKE_PROGRAM=C:/path/to/ninja.exe
cmake --build ../jsbsim-build --target libJSBSim --parallel 6
python verify.py --root .
dumpbin /dependents ../jsbsim-build/bin/JSBSim.dll
```

Expected outputs: bin/JSBSim.dll and lib/JSBSim.lib in the build directory.
The DLL uses dynamic MSVC release CRT (/MD). The application and all its C++ ABI
dependencies must use a compatible MSVC toolset, x64 architecture and dynamic
release CRT. The selected runtime must be at least as new as the newest toolset
in any shipped component. Windows 10/11 UCRT is OS-managed; do not copy System32
DLLs. Debug CRT files are not a release payload. CRT redistribution is a separate
Microsoft license obligation; library source delivery alone does not cover it.

The wrapper fixes BUILD_SHARED_LIBS=ON, SKBUILD=ON, SYSTEM_EXPAT=OFF and disables
documentation, Python, Julia, Matlab and tests/PkgConfig discovery. Build only
libJSBSim. This filtered tree does not support arbitrary upstream packaging,
tests or language bindings. Do not call upstream install/CPack/dist: those are
outside this selection. The vendor library uses C++17 as selected by upstream;
the simulator host is C++20. Version text may include GITHUB_RUN_NUMBER/GITHUB_SHA,
TRAVIS or APPVEYOR metadata; record those environment values with build evidence.
Windows SDK and compiler dependencies are permitted external build inputs.
Record exact compiler patch, SDK, options, command logs and resulting DLL hash.
Unmodified upstream warnings must be reported, not hidden with source patches.

## Verify and repack

verify.py checks all source and wrapper bytes against the exact manifest and
rejects undeclared files. Source must remain unchanged before/after a build.
manifest.json intentionally does not hash itself. Archive SHA256 is external
evidence and covers its complete bytes. pack.py writes ZIP_STORED entries sorted
by the explicit ordinal POSIX relative-path string (independent of host Path ordering),
with fixed 1980-01-01 timestamps, Unix regular-file mode 0644, no directory entries
or path prefix and no host absolute metadata. The Python stdlib recipe does not
depend on compression library versions. Repack the unchanged extraction twice:

```powershell
python pack.py --root . --output ../source-a.zip
python pack.py --root . --output ../source-b.zip
Get-FileHash ../source-a.zip, ../source-b.zip -Algorithm SHA256
```

Do not place build outputs in the source tree. Source changes require new
provenance, modification notices, manifest, reviewed archive digest and delivery
policy before distribution. Compatible user DLL replacement must not be blocked
by a mandatory allowlist of one binary hash. No vendor source is modified here.

## Exported-application replacement procedure

Use a disposable relocated export, ordinary user privileges and no developer PATH.
Record unchanged application/bridge/model payload hashes and baseline process
module path/hash/version, then exercise accepted original-model initialization,
commands and fixed-step snapshots. After process shutdown, remove only JSBSim.dll
from that disposable copy: startup must fail visibly with no fallback library.
Replace it with the independently rebuilt DLL from this archive. Relaunch through
the same export, record the actual loaded replacement path/hash/version, and
repeat finite-state/unit/configuration and deterministic boundary assertions.
The application/bridge/model must stay unchanged. Explicit close must join the
simulation worker before extension unload. Retain positive and negative logs,
source/build evidence, imports and runtime paths. A rebuilt DLL need not be
bit-identical across absolute debug paths/tool versions. This procedure must be exercised for the exact delivered package; consult its
staged replacement evidence for measured results. Users may replace the library
with an ABI-compatible modified build and reverse engineer the required portions
of the application to debug those modifications under the LGPL. No fixed DLL hash
allowlist is enforced by the application.
