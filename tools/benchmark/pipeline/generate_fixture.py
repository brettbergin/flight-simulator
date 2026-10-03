"""Generate original MIT pipeline geometry in the pinned portable Blender.

Run: blender --background --factory-startup --python THIS_FILE -- --output DIR
Outputs: editable .blend, runtime GLB, and a source/hash receipt. No aircraft data.
"""
import argparse
import hashlib
import json
from pathlib import Path
import sys

import bpy

PINNED_BLENDER = "4.5.14 LTS"
if bpy.app.version_string != PINNED_BLENDER:
    raise RuntimeError(f"Expected reviewed Blender {PINNED_BLENDER}, got {bpy.app.version_string}")

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--output", type=Path, required=True)
args = parser.parse_args(sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else [])
out = args.output.resolve()
out.mkdir(parents=True, exist_ok=True)
bpy.ops.object.select_all(action="SELECT")
bpy.ops.object.delete(use_global=False)
scene = bpy.context.scene
scene.unit_settings.system = "METRIC"
scene.unit_settings.scale_length = 1.0
scene.render.fps = 30
scene.frame_start = 0
scene.frame_end = 30
# Process-local authoring setting; do not save user preferences.
bpy.context.preferences.filepaths.save_version = 0

material = bpy.data.materials.new("ProofBlue")
material.use_nodes = True
shader = material.node_tree.nodes.get("Principled BSDF")
shader.inputs["Base Color"].default_value = (0.04, 0.18, 0.6, 1.0)
shader.inputs["Metallic"].default_value = 0.0
shader.inputs["Roughness"].default_value = 0.8
bpy.ops.mesh.primitive_cube_add(size=1, location=(0, 0, 0))
body = bpy.context.object
body.name = "MeterBody"
body.dimensions = (0.6, 1.0, 0.2)
bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
body.data.materials.append(material)
root = bpy.data.objects.new("ControlPivot", None)
scene.collection.objects.link(root)
root.location = (0.2, 0.3, 0.1)
root.rotation_mode = "XYZ"
bpy.ops.mesh.primitive_cube_add(size=1)
control = bpy.context.object
control.name = "PivotLever"
control.dimensions = (0.04, 0.3, 0.04)
bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
control.parent = root
control.location = (0, 0.15, 0)
control.data.materials.append(material)
root.rotation_euler.z = 0.0
root.keyframe_insert(data_path="rotation_euler", frame=0)
root.rotation_euler.z = 0.5
root.keyframe_insert(data_path="rotation_euler", frame=30)
root.animation_data.action.name = "PivotSweep"
for layer in root.animation_data.action.layers:
    for strip in layer.strips:
        for channelbag in strip.channelbags:
            for curve in channelbag.fcurves:
                for keyframe in curve.keyframe_points:
                    keyframe.interpolation = "LINEAR"
scene.frame_set(0)
# Blender +Y forward/+Z up becomes glTF -Z forward/+Y up.
blend_path = out / "pipeline_fixture.blend"
glb_path = out / "pipeline_fixture.glb"
bpy.ops.wm.save_as_mainfile(filepath=str(blend_path))
bpy.ops.export_scene.gltf(
    filepath=str(glb_path), export_format="GLB", export_yup=True,
    export_animations=True, export_frame_range=True, export_force_sampling=True,
    export_materials="EXPORT", export_apply=False, export_cameras=False, export_lights=False,
)

def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

receipt = {
    "kind": "original-pipeline-fixture", "version": 1, "license": "MIT",
    "blender_version": bpy.app.version_string,
    "blender_build_hash": bpy.app.build_hash.decode(),
    "generator_sha256": sha(Path(__file__)),
    "blend_sha256": sha(blend_path), "glb_sha256": sha(glb_path),
    "meters_per_blender_unit": 1.0,
    "blender_axes": "+X right, +Y forward, +Z up",
    "gltf_axes": "+X right, -Z forward, +Y up",
    "body_dimensions_m": [0.6, 1.0, 0.2],
    "body_dimensions_gltf_m": [0.6, 0.2, 1.0],
    "pivot_translation_gltf_m": [0.2, 0.1, -0.3],
    "lever_translation_gltf_m": [0.0, 0.0, -0.15],
    "animation_rotation_gltf_y_rad": [0.0, 0.25, 0.5],
    "animation_interpolation": "linear sampled at 30 Hz",
    "animation_duration_s": 1.0, "materials": ["ProofBlue"],
    "scope": "synthetic units/basis/pivot/PBR/transform animation only; no aircraft dimensions, cockpit fidelity or GPU benchmark",
}
(out / "pipeline_fixture.json").write_bytes((json.dumps(receipt, indent=2) + "\n").encode("utf-8"))
print("PIPELINE_GENERATION " + json.dumps(receipt))
