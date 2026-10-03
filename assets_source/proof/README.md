# Original synthetic pipeline asset

`pipeline_fixture.blend` is editable original geometry created by this project's generator. It contains two cuboids, a named translated parent pivot, one blue PBR material and a one-second linear transform animation. It uses the repository's [MIT license](../../LICENSE). No external aircraft artwork, dimensions, procedures, textures or geographic data are included.

The Blender source uses meters, +X right, +Y forward and +Z up. The glTF runtime asset uses meters, +X right, -Z forward and +Y up. The body is 0.6 x 1.0 x 0.2 meters in Blender and 0.6 x 0.2 x 1.0 meters in glTF. The translated pivot and rotating lever make loss of hierarchy visible and measurable; none of these dimensions describe a Cessna.

The source receipt `pipeline_fixture.json` records Blender 4.5.14 LTS/build hash, generator/source/GLB hashes, units, basis and intended animation. It records one concrete generation, not a guarantee that Blender's editable file serialization is byte-identical across paths or runs. Independent checks compare the exported physical geometry and all 31 rotation samples, while the actual Godot importer checks resources, color conversion and evaluated transforms. Regeneration instructions and limitations are in the [pipeline tooling guide](../../tools/benchmark/pipeline/README.md).

The runtime GLB is [app/proof/pipeline/pipeline_fixture.glb](../../app/proof/pipeline/pipeline_fixture.glb). This small asset establishes an authoring/import pipeline slice. It does not establish cockpit fidelity, aircraft realism, final material appearance, GPU performance or the P1 review gate.
