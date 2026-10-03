# Dependency and content rights

`register.json` is the machine-readable rights inventory for issue #13. It distinguishes reviewed source rights from a releasable package. Its sixteen records cover runtime libraries, bindings, persistence, aircraft models, aircraft publications, geographic products, visual assets and audio assets. An excluded record is useful evidence of a source gate, not permission to distribute that material.

Run these checks from the repository root with Node 20 or later:

```powershell
node tools/license-audit/audit.mjs
node tools/license-audit/test.mjs
node tools/license-audit/audit.mjs --dependency-lock third_party/dependencies.lock.json
```

The dependency-lock check is available once issue #12 lands. No network request, account, downloaded publication or vendor SDK is required by these checks. Notice bytes are pinned by SHA-256 and stored with LF line endings. Original upstream notice contents are retained; trailing blank lines and line endings are normalized. SQLite's notice is project-authored provenance because the SQLite core has a public-domain dedication.

## Current decisions

| Material | Decision | Release evidence still needed |
| --- | --- | --- |
| Godot 4.7.2 standard engine/templates | Conditional; MIT plus complete upstream third-party COPYRIGHT inventory | Pinned executable/template identity, complete staged notices, reviewed package file list |
| godot-cpp godot-4.5-stable | Permitted with MIT notice; exact commit matches toolchain | Binding file/build inventory and notice; engine/API runtime compatibility is issue #15, not a rights conclusion |
| JSBSim 1.3.1 C++ library | Conditional; dynamic library, LGPL and bundled MIT notices | Library-only corresponding source, reviewed bundle digest, reproducible build instructions, DLL replacement test, debugging/modification permission |
| SQLite 3.53.4 core amalgamation | Public-domain dedication; retain provenance by project policy | Pinned core identity and package file inventory; don't extend this decision to every upstream script/extension |
| JSBSim c172x and associated model inputs | Excluded | Variant mismatch and additional source-header restriction unresolved; author an original prototype fixture |
| C172S POH/AFM, limits, checklists and tables | Excluded, configuration/source gate open | Applicable serial/configuration, legal access, document revisions/supplements, permitted extraction and redistribution evidence |
| FAA/USGS/NOAA/airport products and third-party art/audio | Excluded until actual artifacts are selected | Product/file-specific rights, source/effective metadata, exact hashes, attribution and derivative inventories |

The project may build and test the library locally while package obligations are unfinished. This register does not grant aircraft fidelity or authorize a GitHub binary release. A provider's general policy or a library's root license does not clear every file hosted by that provider/repository.

## JSBSim source and replacement obligations

The [scoped source review](evidence/jsbsim-scope.md) records the complete component grants and compiled target, including the historical wording in SimGear magnetic code. Use the library's explicit component grants and retain all relevant notices. The selected later-version path is LGPL 2.1 for the C++ library with compatible MIT components; the aircraft XML is independently reviewed and excluded.

`source.archive_sha256` identifies the upstream acquisition ZIP from issue #12. It contains material outside the cleared library scope. **It is not a distributable corresponding-source approval.** `library_policy.source_archive_sha256` is deliberately null until issue #15 creates a reproducible library-only bundle and reviews its file inventory, dependency closure and build reproducibility. The release auditor rejects null; do not fill it with the upstream ZIP digest.

The source bundle must preserve the complete source necessary to build the shipped DLL and its upstream notices, including Expat/GeographicLib and SimGear code; retain necessary headers, CMake/build inputs, generator inputs and documented tool versions. Remove aircraft/engine/system XML, unrelated test fixtures, Python/MATLAB/Unreal interfaces and other unrelated inputs. Prove a clean build from that bundle, without undeclared upstream files. If the upstream CMake install step copies model data, change the project staging step so it does not package that data. Do not silently rewrite library algorithms to avoid a license review.

Package the DLL as a replaceable shared library, and test replacing it with an independently built compatible version. Ship source build/replacement instructions and the license notices. Product terms must permit reverse engineering for debugging modifications to the LGPL library. Dynamic linking alone does not satisfy source delivery when we ship the DLL. The initial auditor permits only unmodified upstream library releases; patches require an updated reviewed source digest and dated modification notices before extending the policy. An application may retain its own license; this work does not choose or change the project's license.

## Adding material

Add a specific record for an actual dependency/asset pack, not a generic clearance for everything a future contributor might create. Record the publisher URL, exact revision/applicability, artifact digest, rights URL, reviewer role, disposition and notices. Keep denied/unresolved material excluded with a concrete blocker. Original assets also need their authorship/contributor rights, project license and exact file/pack identity recorded. Keep restricted manuals outside public repository and release assets.

Use `tools/license-audit/README.md` for the executable release-manifest contract. A human reviewer must verify rights statements, source-bundle completeness and replacement evidence; the auditor validates the declared inventory and file integrity, not the truth of an assertion or every archive member's legal status. Build-only tool downloads in the dependency lock are not cleared for redistribution. Any tool or new runtime file actually packaged needs its own rights record.
