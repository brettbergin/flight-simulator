"""Corrupt observable asset semantics, not exporter metadata, and require rejection."""
import copy
import json
import struct
import unittest

from check_fixture import DEFAULT_FIXTURE, FixtureError, check, decode

def encode(doc, binary):
    payload = json.dumps(doc, separators=(",", ":")).encode()
    payload += b" " * (-len(payload) % 4)
    return (struct.pack("<III", 0x46546C67, 2, 28 + len(payload) + len(binary))
            + struct.pack("<II", len(payload), 0x4E4F534A) + payload
            + struct.pack("<II", len(binary), 0x004E4942) + binary)

class FixtureMutants(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.original = DEFAULT_FIXTURE.read_bytes()
        cls.doc, cls.binary = decode(cls.original)

    def corrupt(self, mutate, diagnostic):
        doc, binary = copy.deepcopy(self.doc), bytearray(self.binary)
        mutate(doc, binary)
        with self.assertRaisesRegex(FixtureError, diagnostic):
            check(encode(doc, binary))

    def test_actual_fixture(self):
        result = check(self.original)
        self.assertTrue(result["passed"])
        self.assertEqual(result["animation_samples"], 31)

    def test_centimeters_mislabeled_as_meters(self):
        def mutate(doc, binary):
            # glTF units are meters; scaling the actual body positions by 100
            # retains a valid GLB whose implied physical dimensions are wrong.
            body = next(n for n in doc["nodes"] if n["name"] == "MeterBody")
            index = doc["meshes"][body["mesh"]]["primitives"][0]["attributes"]["POSITION"]
            acc = doc["accessors"][index]
            view = doc["bufferViews"][acc["bufferView"]]
            start = view.get("byteOffset", 0) + acc.get("byteOffset", 0)
            for i in range(acc["count"]):
                offset = start + i * view.get("byteStride", 12)
                values = struct.unpack_from("<fff", binary, offset)
                struct.pack_into("<fff", binary, offset, *(v * 100 for v in values))
        self.corrupt(mutate, "meter body dimensions")

    def test_lever_attached_to_body_instead_of_pivot(self):
        def mutate(doc, binary):
            pivot = next(n for n in doc["nodes"] if n["name"] == "ControlPivot")
            body = next(n for n in doc["nodes"] if n["name"] == "MeterBody")
            body["children"] = pivot.pop("children")
        self.corrupt(mutate, "lever parent")

    def test_color_space_double_conversion(self):
        def mutate(doc, binary):
            doc["materials"][0]["pbrMetallicRoughness"]["baseColorFactor"] = [0.221, 0.461, 0.798, 1]
        self.corrupt(mutate, "linear PBR color")

    def test_lost_material_binding(self):
        def mutate(doc, binary):
            doc["meshes"][0]["primitives"][0]["material"] = 1
        self.corrupt(mutate, "material bindings")

    def test_animation_rotates_lever_instead_of_pivot(self):
        def mutate(doc, binary):
            lever = next(i for i, n in enumerate(doc["nodes"]) if n["name"] == "PivotLever")
            doc["animations"][0]["channels"][0]["target"]["node"] = lever
        self.corrupt(mutate, "animation pivot binding")

    def test_wrong_mid_animation_with_correct_endpoints(self):
        def mutate(doc, binary):
            sampler = doc["animations"][0]["samplers"][0]
            acc = doc["accessors"][sampler["output"]]
            view = doc["bufferViews"][acc["bufferView"]]
            offset = view.get("byteOffset", 0) + acc.get("byteOffset", 0) + 15 * view.get("byteStride", 16)
            struct.pack_into("<ffff", binary, offset, 0, 0, 0, 1)
        self.corrupt(mutate, "linear animation rotation")

    def test_out_of_bounds_accessor(self):
        def mutate(doc, binary):
            body = next(n for n in doc["nodes"] if n["name"] == "MeterBody")
            index = doc["meshes"][body["mesh"]]["primitives"][0]["attributes"]["POSITION"]
            doc["accessors"][index]["count"] = 10_000_000
        self.corrupt(mutate, "accessor bounds")

    def test_truncated_binary(self):
        with self.assertRaisesRegex(FixtureError, "GLB header"):
            check(self.original[:-4])

if __name__ == "__main__":
    unittest.main()
