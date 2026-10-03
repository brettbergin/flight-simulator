# Microsoft VC143 release runtime conditional rights evidence

Recorded 2026-10-03 for the [#15 native export proof](../../../docs/evidence/P1/native-export.md). Delivery owns exact selected-build inventories. The reviewed local runtime is staged only in ignored proof payloads; no public release is published by this record.

The owner directly confirmed a Visual Studio Community license on2026-10-03. Record that declared edition as the basis; do not invent an acquisition year/version, account identifier or key. No separate installation or per-file license grant gate is required. Applicable [Community distributable-code terms](https://visualstudio.microsoft.com/license-terms/vs2022-ga-community/) and [VS2022 REDIST list](https://learn.microsoft.com/en-us/visualstudio/releases/2022/redistribution) govern unmodified listed release runtime files with this program. These files retain Microsoft terms, separate from project MIT and JSBSim LGPL.

Primary Community DOCX linked by the Microsoft terms page: https://visualstudio.microsoft.com/wp-content/uploads/2021/11/Visual-Studio-2022-Community-License-EN.docx, reviewed exact SHA256`41a207b10c8ab91d0d2f10a854715f73dca54509581692d2fe179aa3ffcb8540`. Source was read fully, not inferred from a search snippet. Distribution includes application functionality and protective Microsoft-component terms for distributors/end users; no misleading Microsoft endorsement or source relicensing of proprietary runtime. Preserve separate JSBSim modification/replacement/debugging permission. [Microsoft guidance](https://learn.microsoft.com/en-us/cpp/windows/redistributing-visual-cpp-files?view=msvc-170) supports app-local runtime deployment, with servicing responsibility on this project.

## Reviewed local inventory

The register's concrete source-verified/conditional entry covers the three inspected local release files, version 14.40.33810.0. Source is `VC/Redist/MSVC/14.40.33807/x64/Microsoft.VC143.CRT` in the installed VS2022 tree. Each signature verified Valid, architecture is x64, and no debug/tool/System32 binary is in this scope. The actual exported proof loaded these exact files inside its relocated payload. The local inventory does not approve a newer hosted inventory.

| Filename | Version | SHA256 |
|---|---|---|
| msvcp140.dll | 14.40.33810.0 | a4c2229bdc2a2a630acdc095b4d86008e5c3e3bc7773174354f3da4f5beb9cde |
| vcruntime140.dll | 14.40.33810.0 | 02c6aa0e6e624411a9f19b0360a7865ab15908e26024510e5c38a9c08362c35a |
| vcruntime140_1.dll | 14.40.33810.0 | 7dd9aa02e271c68ca6d5f18d651d23a15d7259715af43326578f7dde27f37637 |

Project-authored notice `third_party/licenses/notices/Microsoft-VC143-CRT-Notice.txt` SHA256`5a64868e606d8db5ccff33bea9e299be795258d42ff1bc397341470aed8105e7` retains scope and primary terms references. It is provenance, not Microsoft's full grant. The proof also stages the retained primary DOCX terms and reviewed text extraction, plus protective distribution terms and selected-runtime evidence; a summary notice alone does not establish all release obligations.

## Required selected-build artifact record

Before publication record the actual selected runtime source/edition/version, x64 release-only path allowlist, byte length/SHA256/AuthentiCode result, build toolset/compiler identity, direct/transitive/dynamic imports, governing terms digest and an immutable inventory digest. Register/pin must match those selected files; unchanged bytes are required. Scope only the imports needed by shipped host/bridge/JSBSim/Godot components. Copying every Microsoft DLL because it appears on disk does not constitute reviewed dependency closure.

[Binary compatibility](https://learn.microsoft.com/en-us/cpp/porting/binary-compat-2015-2017?view=msvc-170) requires a runtime at least as recent as the newest toolset used by any shipped component. The local14.40 candidates must not silently be used for hosted14.44 binaries. Select and review a suitable release runtime from the actual build environment, updating the proposed exact version/source/hash entry accordingly. A runtime source change needs inventory review, not a new entitlement interview. Runtime use/replacement tests must run on a clean supported Windows machine without development PATH; debugger/compiler libraries must not become release dependencies.

The REDIST list excludes debug_nonredist; also exclude Microsoft preview/pre-release/beta runtimes, compiler tools and arbitrary OS files. [Dependency guidance](https://learn.microsoft.com/en-us/cpp/windows/determining-which-dlls-to-redistribute?view=msvc-170) identifies Windows10/11 UCRT as an OS component. Do not copy System32 UCRT/API-set/system libraries into the ZIP. Microsoft runtime terms do not restrict this project's choice to brand its own game alpha/beta.

## Accepted audit boundary

The 18-entry register and actual staged proof pass the rights audit with retained notices. Generic component/file checks now call `tools/export/check-runtime.mjs` for Microsoft CRT package entries. This bounded verifier enforces exact reviewed file pins, version/source revision, x64 PE identities, inspected signatures, staged bytes, immutable inventory digests and compiler/runtime compatibility. Eight runtime test groups cover positive exact identity and missing/unreviewed pins/evidence, unsigned source, forbidden origins, changed bytes, digest mutation and newer compiler than runtime. Unknown hosted identities fail before package clearance and require independent inventory review.

The original bridge/proof has a separate MIT ledger entry. The [export evidence](../../../docs/evidence/P1/native-export.md) records actual loading and DLL replacement; this rights record consumes the accepted #13 structure and owner's declaration. It does not qualify an aircraft, complete P1 or authorize a public simulator release.
