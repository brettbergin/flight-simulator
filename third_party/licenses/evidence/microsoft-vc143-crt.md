# Microsoft VC143 release runtime conditional rights evidence

Recorded 2026-10-03 for the [#15 native export proof](../../../docs/evidence/P1/native-export.md). Delivery owns exact selected-build inventories. The reviewed local runtime is staged only in ignored proof payloads; no public release is published by this record.

The owner directly confirmed a Visual Studio Community license on2026-10-03. Record that declared edition as the basis; do not invent an acquisition year/version, account identifier or key. No separate installation or per-file license grant gate is required. Applicable [Community distributable-code terms](https://visualstudio.microsoft.com/license-terms/vs2022-ga-community/) and [VS2022 REDIST list](https://learn.microsoft.com/en-us/visualstudio/releases/2022/redistribution) govern unmodified listed release runtime files with this program. These files retain Microsoft terms, separate from project MIT and JSBSim LGPL.

Primary Community DOCX linked by the Microsoft terms page: https://visualstudio.microsoft.com/wp-content/uploads/2021/11/Visual-Studio-2022-Community-License-EN.docx, reviewed exact SHA256`41a207b10c8ab91d0d2f10a854715f73dca54509581692d2fe179aa3ffcb8540`. Source was read fully, not inferred from a search snippet. Distribution includes application functionality and protective Microsoft-component terms for distributors/end users; no misleading Microsoft endorsement or source relicensing of proprietary runtime. Preserve separate JSBSim modification/replacement/debugging permission. [Microsoft guidance](https://learn.microsoft.com/en-us/cpp/windows/redistributing-visual-cpp-files?view=msvc-170) supports app-local runtime deployment, with servicing responsibility on this project.

## Reviewed local inventory

The register's concrete source-verified/conditional entry covers the five inspected local release files, version 14.40.33810.0. Source is `VC/Redist/MSVC/14.40.33807/x64/Microsoft.VC143.CRT` in the installed VS2022 tree. Each signature verified Valid, architecture is x64, and no debug/tool/System32 binary is in this scope. The actual exported proof loaded these exact files inside its relocated payload. The local inventory does not approve a newer hosted inventory.

| Filename | Version | SHA256 |
|---|---|---|
| msvcp140.dll | 14.40.33810.0 | a4c2229bdc2a2a630acdc095b4d86008e5c3e3bc7773174354f3da4f5beb9cde |
| msvcp140_2.dll | 14.40.33810.0 | 713f17b253d802d283d306ce75647e37d83a546aeb1a881e5d9e529e856c007e |
| msvcp140_atomic_wait.dll | 14.40.33810.0 | aede4ec454a82f146eb4a721e616e2086870107d88aabc6b0bd1eea0a505d935 |
| vcruntime140.dll | 14.40.33810.0 | 02c6aa0e6e624411a9f19b0360a7865ab15908e26024510e5c38a9c08362c35a |
| vcruntime140_1.dll | 14.40.33810.0 | 7dd9aa02e271c68ca6d5f18d651d23a15d7259715af43326578f7dde27f37637 |

## Concrete hosted inventory

The first [PR #91 native run](https://github.com/brettbergin/flight-simulator/actions/runs/37156502551)
at exact head `30d195ac58f7db58ffee0d5ed83284ef0e980824` recorded five unmodified
Microsoft signature-valid x64 release runtime files, version 14.44.35211.0, from
`VC/Redist/MSVC/14.44.35112/x64/Microsoft.VC143.CRT` in the hosted VS2022 tree.
The folder revision differs from the files' version and is retained exactly.
Actual compiler was MSVC 19.44.35229.0/toolset 14.44.35207; this runtime is newer
than that toolset. The portable and replacement runs witnessed these exact bytes
loaded inside the payload. The initial package audit failed closed on its
unreviewed identities, providing the concrete review packet before pin clearance.

| Filename | Bytes | SHA256 |
| --- | --- | --- |
| msvcp140.dll | 557728 | 0f885b509a685d2bbfa652fed26b5fb31d88fbdab0a978c641d1c7b8aa460aa9 |
| msvcp140_2.dll | 280200 | 3ea06f0ee098b4823cb79599df3780e7f23cce52c19aac31d2a0d47efe33a5e9 |
| msvcp140_atomic_wait.dll | 50304 | 640b2aefced484d0368eea5bdd06addd0658a3a70a49256e560d6923b404a479 |
| vcruntime140.dll | 124544 | d5e4d9a3e835fa679450145d6a7d94e36573a509317111904d9b3712c30d9066 |
| vcruntime140_1.dll | 49792 | 1f2d41c4aa5db0bc33ebf7b66d72943a817d7ce6cbe880502a9403823633093f |

The delivery reviewer and integrator independently approved these exact hosted
pins through CI-attested source/signature/byte metadata and actual process/module
witnesses. This is not a local signature re-verification of undownloaded binaries.
Final current-head actual PE/runtime/package audit remains mandatory before merge.
Future new or changed identities remain unapproved automatically; no version
wildcard bypass is used.

Project-authored notice `third_party/licenses/notices/Microsoft-VC143-CRT-Notice.txt` SHA256`5a64868e606d8db5ccff33bea9e299be795258d42ff1bc397341470aed8105e7` retains scope and primary terms references. It is provenance, not Microsoft's full grant. The proof also stages the retained primary DOCX terms and reviewed text extraction, plus protective distribution terms and selected-runtime evidence; a summary notice alone does not establish all release obligations.

## Required selected-build artifact record

Before publication record the actual selected runtime source/edition/version, x64 release-only path allowlist, byte length/SHA256/AuthentiCode result, build toolset/compiler identity, direct/transitive/dynamic imports, governing terms digest and an immutable inventory digest. Register/pin must match those selected files; unchanged bytes are required. Scope only the imports needed by shipped host/bridge/JSBSim/Godot components. Copying every Microsoft DLL because it appears on disk does not constitute reviewed dependency closure.

[Binary compatibility](https://learn.microsoft.com/en-us/cpp/porting/binary-compat-2015-2017?view=msvc-170) requires a runtime at least as recent as the newest toolset used by any shipped component. The local14.40 candidates must not silently be used for hosted14.44 binaries. Select and review a suitable release runtime from the actual build environment, updating the proposed exact version/source/hash entry accordingly. A runtime source change needs inventory review, not a new entitlement interview. Runtime use/replacement tests must run on a clean supported Windows machine without development PATH; debugger/compiler libraries must not become release dependencies.

The REDIST list excludes debug_nonredist; also exclude Microsoft preview/pre-release/beta runtimes, compiler tools and arbitrary OS files. [Dependency guidance](https://learn.microsoft.com/en-us/cpp/windows/determining-which-dlls-to-redistribute?view=msvc-170) identifies Windows10/11 UCRT as an OS component. Do not copy System32 UCRT/API-set/system libraries into the ZIP. Microsoft runtime terms do not restrict this project's choice to brand its own game alpha/beta.

## Accepted audit boundary

The 18-entry register and actual staged proof pass the rights audit with retained notices. Generic component/file checks now call `tools/export/check-runtime.mjs` for Microsoft CRT package entries. This bounded verifier enforces exact reviewed file pins/lengths, version/source revision, x64 PE identities, inspected signatures, staged bytes, immutable inventory digests and compiler/runtime compatibility. It independently reads actual direct/deferred PE imports and requires full non-system closure. Twelve runtime test groups cover exact identity, missing/unreviewed pins/evidence, unsigned source, forbidden origins, changed bytes, digest mutation, wrong architecture, newer compiler, omitted imports and missing staged CRTs. Unknown hosted identities fail before package clearance and require independent inventory review.

The original bridge/proof has a separate MIT ledger entry. The [export evidence](../../../docs/evidence/P1/native-export.md) records actual loading and DLL replacement; this rights record consumes the accepted #13 structure and owner's declaration. It does not qualify an aircraft, complete P1 or authorize a public simulator release.
