# Original render fixture rights and provenance

Reviewed 2026-10-03 for issue #18. Ledger IDs `original-pipeline-fixture` (version `1`) and `original-render-proof` (version `0.1.0-prototype`) cover original project-authored proof content under the repository [MIT license](../../../LICENSE). The retained [full notice](../notices/FirstParty-RenderProof-MIT.txt) has SHA-256 `ca8c1205d820d40917b54d548b97dde200bc24bc6c3166358e8bc6cc27eb0e9e`. The owner authorized original project implementation and accepted the pipeline contribution for integration; its first authoring commit is `1f680a5891664c4d3ae8208b00af7cee919080d4`, integrated by the renderer owner as `64b2a829bd9ddd4f6b47bee469ef87154d4f7b5d`.

## Fixed Blender-to-GLB fixture

The [exact 14-file inventory](original-render-pipeline.inventory.json) identifies the fixed contribution, including the editable source, runtime GLB, generation receipt, original generator, independent semantic/corruption checks, actual Godot import check, instructions and attributes. Inventory SHA-256 is `b5da02707fe101a9c9f9dcda90bda07dd61c4cec9eef126255ece347975f8e34`. Each current source file was compared byte-for-byte with that immutable contribution before its hash was recorded. This file list covers the pipeline slice only; it does not include changing procedural renderer scripts.

| Fixed asset | Bytes | SHA-256 |
|---|---:|---|
| `assets_source/proof/pipeline_fixture.blend` | 458945 | `847908a2cc2b851a77f0b492fa4d44de72fc8ac856535bc95043d059ab2eaa6f` |
| `app/proof/pipeline/pipeline_fixture.glb` | 4664 | `6af12b425789a4d0cb344c67e73410c1ea8c031a4a20bd2b98b96939e81c82a8` |

The [original generator](../../../tools/benchmark/pipeline/generate_fixture.py) constructs two cuboids, an explicitly translated empty pivot, a blue PBR material and a one-second sampled rotation from original literals. It starts with Blender's factory scene cleared; it does not acquire another model, photograph, texture, typeface, aircraft drawing, POH, airport layout or geographic dataset. The [source receipt](../../../assets_source/proof/pipeline_fixture.json) binds the generator, source and GLB hashes to Blender 4.5.14 LTS/build `62c1db4208e8`; [authoring software rights](blender-authoring.md) remain separate. The fixed source hash identifies this generation, not a promise of byte-identical future `.blend` serialization.

## Original procedural geometry and panel

The renderer owner's `app/proof/render/render.gd`, `panel.gd`, `frame.gd`, `render.tscn` and `.gitattributes` contain project-authored code/scene definitions. The reviewed scope consists of mathematical terrain tiles, synthetic runway markings, box buildings, cone trees, opaque cloud proxies, panel drawing and private presentation-frame expressions. The panel labels/readings are fixed synthetic examples. These expressions generate prototype visual-load content using Godot primitives; they do not reproduce a Cessna cockpit, manufacturer calibration or an actual airfield. The imported fixed pipeline GLB keeps its separate immutable identity above.

The renderer scripts are still being implemented. This record declares the original-content rights scope and does **not** approve an exact frozen renderer code inventory. The renderer owner must bind its final source revision, scripts, recipe and exported content to the benchmark/package manifest after the shutdown fix and freeze. The fixed 14-file asset inventory must not be treated as a digest for that later renderer package. The existing offline rights auditor checks notice/register integrity; this supplemental source inventory is independently checked evidence, not a new automatic release gate implemented by this change.

The panel uses `ThemeDB.fallback_font`; no external font file is acquired or granted by this original-content record. That built-in resource stays within the existing Godot runtime ledger and complete [Godot COPYRIGHT inventory](../notices/Godot-COPYRIGHT.txt), including its separate bundled font terms. The unselected external art/font/model `visual-content` exclusion remains unchanged. Engine classes, bundled fonts, native libraries and authoring tools retain their own rights; neither generated output nor these MIT records relicense those components.

## Package and acceptance limits

Any package containing these original assets/code must retain the full MIT notice and source attribution and declare actual staged hashes under the applicable component ID. This contribution does not authorize future third-party art packs, licensed aircraft documentation, real-world scenery, recordings or fonts. Changed fixed pipeline assets require refreshed inventory and review; a future borrowed input needs its own artifact-specific rights evidence. Renderer measurements, readability, aircraft fidelity, pilot evaluation and the P1 gate are separate acceptance work.
