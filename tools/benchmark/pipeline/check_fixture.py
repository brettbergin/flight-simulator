"""Check actual GLB bytes against the authored SI design, independently of Blender.

This intentionally accepts only the tiny proof fixture's GLB subset. It is not a
general glTF validator, an aircraft model validator, or a renderer benchmark.
"""
import argparse
import hashlib
import json
import math
from pathlib import Path
import struct

ROOT = Path(__file__).resolve().parents[3]
DEFAULT_FIXTURE = ROOT / "app/proof/pipeline/pipeline_fixture.glb"

class FixtureError(ValueError):
    pass

def require(condition, message):
    if not condition:
        raise FixtureError(message)

def decode(blob):
    require(len(blob) >= 28, "truncated GLB")
    magic, version, size = struct.unpack_from("<III", blob)
    require((magic, version, size) == (0x46546C67, 2, len(blob)), "GLB header")
    json_size, json_kind = struct.unpack_from("<II", blob, 12)
    require(json_kind == 0x4E4F534A and json_size % 4 == 0, "JSON chunk header")
    offset = 20 + json_size
    require(offset + 8 <= len(blob), "truncated JSON chunk")
    doc = json.loads(blob[20:offset])
    binary_size, binary_kind = struct.unpack_from("<II", blob, offset)
    require(binary_kind == 0x004E4942 and binary_size % 4 == 0, "BIN chunk header")
    binary = blob[offset + 8:]
    require(len(binary) == binary_size, "BIN chunk length")
    require(doc["asset"]["version"] == "2.0", "glTF version")
    require(len(doc["buffers"]) == 1 and "uri" not in doc["buffers"][0], "embedded single buffer")
    require(0 <= len(binary) - doc["buffers"][0]["byteLength"] <= 3, "buffer padding")
    return doc, binary

def read(doc, binary, index):
    accessor = doc["accessors"][index]
    require(accessor["componentType"] == 5126 and "sparse" not in accessor, "float accessor")
    require(not accessor.get("normalized", False), "unnormalized float accessor")
    width = {"SCALAR": 1, "VEC3": 3, "VEC4": 4}[accessor["type"]]
    view = doc["bufferViews"][accessor["bufferView"]]
    require(view["buffer"] == 0, "accessor buffer")
    start = view.get("byteOffset", 0) + accessor.get("byteOffset", 0)
    stride = view.get("byteStride", width * 4)
    end = start + (accessor["count"] - 1) * stride + width * 4
    require(accessor["count"] > 0 and stride >= width * 4 and start >= view.get("byteOffset", 0), "accessor range")
    require(end <= view.get("byteOffset", 0) + view["byteLength"] <= len(binary), "accessor bounds")
    values = [struct.unpack_from("<" + "f" * width, binary, start + i * stride) for i in range(accessor["count"])]
    require(all(math.isfinite(value) for sample in values for value in sample), "finite accessor")
    return values

def near(actual, expected, label):
    require(len(actual) == len(expected), label + " length")
    require(all(math.isfinite(a) and abs(a - e) <= 1e-6 for a, e in zip(actual, expected)), label)

def check(blob):
    doc, binary = decode(blob)
    nodes = {node["name"]: (index, node) for index, node in enumerate(doc["nodes"])}
    require(len(nodes) == len(doc["nodes"]) == 3 and set(nodes) == {"MeterBody", "ControlPivot", "PivotLever"}, "named nodes")
    require(len(doc["scenes"]) == 1 and doc.get("scene", 0) == 0, "single scene")
    require(set(doc["scenes"][0]["nodes"]) == {nodes["MeterBody"][0], nodes["ControlPivot"][0]}, "scene roots")
    for name, (_, node) in nodes.items():
        require("matrix" not in node, name + " matrix")
        near(node.get("scale", [1, 1, 1]), [1, 1, 1], name + " applied scale")
        near(node.get("rotation", [0, 0, 0, 1]), [0, 0, 0, 1], name + " rest rotation")
    require(len(doc["meshes"]) == 2 and all(len(mesh["primitives"]) == 1 for mesh in doc["meshes"]), "two single-primitive meshes")
    dimensions_by_name = {}
    for name, expected in [("MeterBody", [0.6, 0.2, 1.0]), ("PivotLever", [0.04, 0.04, 0.3])]:
        node = nodes[name][1]
        positions = read(doc, binary, doc["meshes"][node["mesh"]]["primitives"][0]["attributes"]["POSITION"])
        bounds = [(min(p[axis] for p in positions), max(p[axis] for p in positions)) for axis in range(3)]
        dimensions = [high - low for low, high in bounds]
        near(dimensions, expected, "meter body dimensions / glTF basis" if name == "MeterBody" else "meter lever dimensions / glTF basis")
        near([low + high for low, high in bounds], [0, 0, 0], name + " centered mesh")
        dimensions_by_name[name] = dimensions
    body = nodes["MeterBody"][1]
    near(body.get("translation", [0, 0, 0]), [0, 0, 0], "body translation")
    near(nodes["ControlPivot"][1]["translation"], [0.2, 0.1, -0.3], "pivot SI translation")
    near(nodes["PivotLever"][1]["translation"], [0, 0, -0.15], "lever SI translation")
    require(nodes["ControlPivot"][1].get("children") == [nodes["PivotLever"][0]], "lever parent / pivot")
    require(not body.get("children") and not nodes["PivotLever"][1].get("children"), "unexpected children")
    material = doc["materials"][0]
    require(len(doc["materials"]) == 1 and material["name"] == "ProofBlue", "named material")
    pbr = material["pbrMetallicRoughness"]
    near(pbr["baseColorFactor"], [0.04, 0.18, 0.6, 1], "linear PBR color")
    near([pbr["metallicFactor"], pbr["roughnessFactor"]], [0, 0.8], "PBR factors")
    require(all(primitive["material"] == 0 for mesh in doc["meshes"] for primitive in mesh["primitives"]), "material bindings")
    require(len(doc["animations"]) == 1, "single animation")
    animation = doc["animations"][0]
    require(animation["name"] == "PivotSweep" and len(animation["channels"]) == 1, "named rotation track")
    channel = animation["channels"][0]
    require(channel["target"] == {"node": nodes["ControlPivot"][0], "path": "rotation"}, "animation pivot binding")
    sampler = animation["samplers"][channel["sampler"]]
    require(sampler.get("interpolation", "LINEAR") == "LINEAR", "animation interpolation")
    times = [t[0] for t in read(doc, binary, sampler["input"])]
    rotations = read(doc, binary, sampler["output"])
    require(len(times) == len(rotations) == 31, "30 Hz animation samples")
    for index, (time, quaternion) in enumerate(zip(times, rotations)):
        near([time], [index / 30], "animation time")
        angle = 0.5 * index / 30
        near(quaternion, [0, math.sin(angle / 2), 0, math.cos(angle / 2)], "linear animation rotation")
        require(abs(sum(v * v for v in quaternion) - 1) < 1e-6, "unit animation quaternion")
    return {"passed": True, "glb_sha256": hashlib.sha256(blob).hexdigest(), "body_dimensions_gltf_m": dimensions_by_name["MeterBody"],
            "lever_dimensions_gltf_m": dimensions_by_name["PivotLever"],
            "animation_samples": len(times), "duration_s": times[-1], "rotation_samples_rad": [0, 0.25, 0.5],
            "scope": "actual GLB bytes / SI dimensions / basis / parent / PBR / sampled rotation only"}

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("fixture", nargs="?", type=Path, default=DEFAULT_FIXTURE)
    args = parser.parse_args()
    print(json.dumps(check(args.fixture.read_bytes()), indent=2))
