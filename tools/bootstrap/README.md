# Reproducible native build bootstrap

P1 toolchain proof for Windows x64/MSVC 2022 and Linux x64/GCC 13+. This compiles a real C++20 dependency probe, replaceable JSBSim shared library, SQLite, and a trimmed standard-precision godot-cpp binding probe. It is not a flight model, cockpit, export, or aircraft-validation result.

Use Python 3.12 or later and installed MSVC 2022 C++ Build Tools on Windows. The current PC has Python 3.12.5 and MSVC 19.40.33813.0; CI requests Python 3.12.5 explicitly. The bootstrap's supported Python baseline is separate from the planned Python 3.13 family for future GIS/data tooling. Nothing installs globally or creates a vendor account.

From the repository root:

~~~powershell
./tools/bootstrap/build.ps1 -Python python
# If Python is not on PATH, supply its actual executable path.
# Optional official editor and matching templates, downloaded locally:
./tools/bootstrap/build.ps1 -Python python -WithGodot -WithExportTemplates
# Repeat using only checksum-verified cache:
./tools/bootstrap/build.ps1 -Python python -Offline
python tools/bootstrap/test_bootstrap.py
./tools/bootstrap/verify-godot.ps1 # after -WithGodot build
~~~

Linux requires GCC 13+, Python 3.12+, and PowerShell (available on the GitHub Ubuntu runner). The same build script uses the pinned Linux CMake/Ninja artifacts. CI sets CC=gcc-13 and CXX=g++-13.

The authoritative lock is [dependencies.lock.json](../../third_party/dependencies.lock.json). GitHub release binary SHA-256 values were verified against the official release API digests. Source archives are fixed to exact commits or the official SQLite version and have SHA-256 values measured from those downloaded bytes. Extraction rejects traversal, special members, and excessive expanded sizes. Receipts include a full extracted-tree fingerprint; corrupted downloads and changed sources fail before build.

CMake 3.31.8 and Ninja 1.13.1 are downloaded under ignored .local/toolchain. Source caches live in .local/deps and downloads in .local/download-cache. Build/test output lives in .local/build/native-release. Compiler environments affect the process only; all native Windows targets use the dynamic CRT (/MD for RelWithDebInfo, /MDd for Debug). Compiler patch and tool versions enter the build manifest. Hosted runner compilers/OS images can change, so identical binaries across different compiler/image versions are not promised.

The build verifies that the smoke executable actually links JSBSim.dll/libJSBSim.so. It tests the library interface, C++20 span, SQLite's pinned runtime version, transaction commit and rollback, and unchanged source/tool fingerprints after compilation. Project code treats warnings as errors; upstream headers are marked external. CTest rejects an empty test run. The accepted contract module/tests are incorporated after their separate PR lands. Clean build evidence is attached to [toolchain PR #84](https://github.com/brettbergin/flight-simulator/pull/84); its initial Windows/Linux runs used MSVC 19.44.35229.0 and GCC 13.3.0 and passed native tests, dynamic-library checks, source receipts and real editor loading.

The official godot-cpp repository has no 4.7 tag/branch at verification time. Its godot-4.5-stable tag is pinned at e83fd0904c13356ed1d4c3d09f8bb9132bdc6b77, targeting the 4.5 single-precision API on the pinned Godot 4.7.2 engine. Godot documents forward compatibility across these later 4.x minor versions. The headless probe actually loads this native library in the pinned editor and requires a positive native initializer sentinel after RefCounted construction/destruction, plus the script load marker and no ERROR/FATAL messages. Exported simulator operation, command/step/snapshot and clean portable-package loading remain NATIVE-EXPORT evidence gates; this probe does not establish those. The tiny binding profile lists base classes required by upstream source; production may extend that reviewed profile.

Upstream JSBSim model/engine XML is never automatically installed or packaged. The source cache contains upstream references for building, whose individual licenses differ from the library. Release packaging must use the reviewed license register, corresponding-source/replacement obligations, and original/authorized aircraft packages. Native CI uploads manifests and test logs, not a simulator distribution.

Official references: [Godot release assets](https://github.com/godotengine/godot-builds/releases/tag/4.7.2-stable), [GDExtension compatibility](https://docs.godotengine.org/en/stable/tutorials/scripting/cpp/gdextension_cpp_example.html), [godot-cpp pin](https://github.com/godotengine/godot-cpp/tree/e83fd0904c13356ed1d4c3d09f8bb9132bdc6b77), [JSBSim pin](https://github.com/JSBSim-Team/jsbsim/tree/3b25f25e49b42d0489c04ac805674fc1450ca579), [SQLite source ID](https://sqlite.org/changes.html), [CMake assets](https://github.com/Kitware/CMake/releases/tag/v3.31.8), [Ninja assets](https://github.com/ninja-build/ninja/releases/tag/v1.13.1).
