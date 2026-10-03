# Synthetic Blender to Godot pipeline check

Issue [#18](https://github.com/brettbergin/flight-simulator/issues/18), asset-pipeline slice only. These tools author and verify a small original MIT fixture. They do not modify physics or establish aircraft dimensions, instrument readability or renderer performance. The asset source and provenance are described in [assets_source/proof](../../../assets_source/proof/README.md).

Use the already reviewed portable Blender **4.5.14 LTS**, build `62c1db4208e8`, and the pinned **Godot 4.7.2 stable editor** from the repository bootstrap cache. The generator rejects another Blender version. The standalone importer runner checks the supplied Godot version and records its executable hash plus the in-engine version/hash; it does not acquire tools or replace the central dependency lock. Obtain and verify tools through the coordinator's approved bootstrap/pin record first.

From the repository root:

~~~powershell
# Substitute the actual portable Blender path; no global installation is needed.
& $BlenderExe --background --factory-startup --python tools/benchmark/pipeline/generate_fixture.py -- --output .local/pipeline-generation
python tools/benchmark/pipeline/check_fixture.py .local/pipeline-generation/pipeline_fixture.glb
# After reviewing changed assets, update only the three owned files:
Copy-Item -LiteralPath .local/pipeline-generation/pipeline_fixture.blend -Destination assets_source/proof/pipeline_fixture.blend
Copy-Item -LiteralPath .local/pipeline-generation/pipeline_fixture.json -Destination assets_source/proof/pipeline_fixture.json
Copy-Item -LiteralPath .local/pipeline-generation/pipeline_fixture.glb -Destination app/proof/pipeline/pipeline_fixture.glb
python -m unittest discover -s tools/benchmark/pipeline -p test_fixture.py -v
python tools/benchmark/pipeline/check_fixture.py
python tools/benchmark/pipeline/verify_pipeline.py --godot $GodotExe
~~~

Python tooling uses only the standard library; `bpy` comes from the specified Blender process. Prefer a fresh generation folder to retain earlier receipts. Generator text is normalized to LF because its actual-byte hash is part of the source receipt. Blender's editable `.blend` serialization can differ across saves, so rebuilding means deterministic authored semantics and independently checked GLB values, not an unsupported promise of identical source-file bytes. The exporter samples authored LINEAR curves at 30 Hz.

The independent checker decodes actual GLB JSON and binary accessors without importing Blender. It checks meter dimensions, transformed axes, applied object scale, pivot translation and parent, linear PBR factors/material bindings, animation binding, all sample times and rotation quaternions. Its 1e-6 absolute numeric allowance is for these small exported float32 design values; it is not an aviation validation tolerance. Nine test groups include valid bytes plus corrupted units, parent, color conversion, material binding, animation target/middle sample, accessor bounds and truncation.

`verify_pipeline.py` stages a separate ignored Godot project, performs an actual editor import, then runs the checked scene. It rejects nonzero exits, engine/script errors, missing success markers, incompatible versions, changed sources and mismatched source-receipt hashes. It requires a fresh evidence directory, retains import/runtime/version logs, and writes `receipt.json` only after success. The default output is a unique `.local/pipeline-proof/run-...` directory. An explicit `--output` must also be inside this repository's `.local` and empty; failed runs cannot reuse a prior successful receipt.

The actual imported resource test checks dimensions, identity/rest transforms, hierarchy, shared material, glTF linear factors converted to Godot's sRGB material color, and evaluated parent/lever transforms at 0, 0.5 and 1 seconds. The script is a self-terminating import test scene, not a component to attach to the interactive renderer benchmark. Use the GLB resource itself in the benchmark.

The isolated project requests GL Compatibility and runs headlessly. That verifies resource import and scene transforms; it is not Forward+ appearance or an RTX 3090 GPU benchmark. The renderer owner supplies separate visible Forward+ material/animation captures, authoritative tool pin/rights records, timing and project acceptance evidence. Textures, normals, glass, skinning, final cockpit illumination and aircraft/instrument behavior are outside this tiny fixture's scope. These checks use editor assertions and should run in the specified editor, not a release export that strips assertions.
