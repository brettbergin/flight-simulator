"""Source-authored structural tests against Root's already frozen byte witnesses.

No Blender/art generator or third-party import. --reference supplies the exact
independent oracle file, not production identities/pins or candidate artwork.
"""
import argparse
import copy
import hashlib
import importlib.util
import json
from pathlib import Path
import struct
import tempfile
import unittest


SOURCE = Path(__file__).absolute().parent
spec = importlib.util.spec_from_file_location('evergreen_structural_checker', SOURCE / 'check_trees.py')
C = importlib.util.module_from_spec(spec)
spec.loader.exec_module(C)
REFERENCE_SHA256 = '1d867f93e07dc4247894dcf135427e80e1080440c51a6f8258ca38aa09afae25'
REFERENCE = None


def frame(json_bytes, binary):
    padded = json_bytes + b' ' * (-len(json_bytes) % 4)
    binary += b'\0' * (-len(binary) % 4)
    return struct.pack('<III', 0x46546C67, 2, 28 + len(padded) + len(binary)) + struct.pack('<II', len(padded), 0x4E4F534A) + padded + struct.pack('<II', len(binary), 0x004E4942) + binary


def repack(document, binary):
    return frame(json.dumps(document, sort_keys=True, separators=(',', ':'), allow_nan=False).encode('utf-8'), bytes(binary))


def baseline():
    row = REFERENCE['fixtures'][0]
    return copy.deepcopy(row['json_document']), bytearray.fromhex(row['bin_hex'])


class StructuralChecks(unittest.TestCase):
    def check(self, raw):
        return C._check_glb(raw, 'tall-narrow', 0)

    def refused(self, document, binary):
        with self.assertRaises(C.InvalidGlb):
            self.check(repack(document, binary))

    def test_two_frozen_hand_witnesses_structure_only(self):
        self.assertEqual(len(REFERENCE['fixtures']), 2)
        for row in REFERENCE['fixtures']:
            raw = bytes.fromhex(row['hex'])
            self.assertEqual(hashlib.sha256(raw).hexdigest(), row['sha256'])
            result = self.check(raw)
            self.assertTrue(result['structural_pass'])
            self.assertEqual((result['vertices'], result['triangles'], result['materials']), (72, 36, 3))
            self.assertEqual(result['aabb_min'], [-2.5, 0, -2.5])
            self.assertEqual(result['aabb_max'], [2.5, 25, 2.5])
            self.assertEqual(result['height_width_depth_m'], [25, 5, 5])
            self.assertFalse(result['artwork_accepted'])
            self.assertFalse(result['full_bundle_accepted'])
            self.assertFalse(result['import_accepted'])
            for name, volume in [('Bark', 5.5), ('InnerNeedles', 250), ('OuterNeedles', 110.25)]:
                self.assertEqual(result['geometric_components'][name], [{'triangles': 12, 'closed_oriented_edge_incidence': True, 'signed_volume_m3_when_closed': volume}])

    def test_every_strict_prefix_and_extra_byte(self):
        raw = bytes.fromhex(REFERENCE['fixtures'][0]['hex'])
        for length in range(len(raw)):
            with self.subTest(length=length), self.assertRaises(C.InvalidGlb):
                self.check(raw[:length])
        with self.assertRaises(C.InvalidGlb):
            self.check(raw + b'\0')

    def test_bad_framing_and_json(self):
        original = bytes.fromhex(REFERENCE['fixtures'][0]['hex'])
        for offset, value in [(0, 0), (4, 1), (8, len(original) + 4), (12, 0), (16, 0)]:
            raw = bytearray(original)
            struct.pack_into('<I', raw, offset, value)
            with self.subTest(offset=offset), self.assertRaises(C.InvalidGlb):
                self.check(bytes(raw))
        document, binary = baseline()
        raw_json = json.dumps(document, separators=(',', ':')).encode()
        for invalid in [b'\xef\xbb\xbf' + raw_json, b'{"scene":0,' + raw_json[1:], raw_json + b'\n', raw_json.replace(b'"scene":0', b'"scene":NaN'), b'\xff']:
            with self.subTest(invalid=invalid[:50]), self.assertRaises(C.InvalidGlb):
                self.check(frame(invalid, bytes(binary)))

    def test_closed_json_roster(self):
        for place, key, value in [('top', 'extensionsUsed', []), ('top', 'extras', {}), ('asset', 'extensions', {}),
                                  ('node', 'matrix', [1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1]),
                                  ('buffer', 'uri', 'file:///no-read'), ('view', 'byteStride', 12),
                                  ('accessor', 'sparse', {}), ('primitive', 'targets', []), ('attributes', 'TEXCOORD_0', 0),
                                  ('material', 'alphaCutoff', 0.5), ('pbr', 'baseColorTexture', {})]:
            document, binary = baseline()
            targets = {'top': document, 'asset': document['asset'], 'node': document['nodes'][0],
                       'buffer': document['buffers'][0], 'view': document['bufferViews'][0],
                       'accessor': document['accessors'][0], 'primitive': document['meshes'][0]['primitives'][0],
                       'attributes': document['meshes'][0]['primitives'][0]['attributes'],
                       'material': document['materials'][0], 'pbr': document['materials'][0]['pbrMetallicRoughness']}
            targets[place][key] = value
            with self.subTest(place=place, key=key):
                self.refused(document, binary)

    def test_explicit_defaults_and_optional_extrema(self):
        document, binary = baseline()
        for node in document['nodes']:
            node.update(translation=[0, 0, 0], rotation=[0, 0, 0, 1], scale=[1, 1, 1])
        for accessor in document['accessors']:
            accessor['normalized'] = False
        for mesh in document['meshes']:
            mesh['primitives'][0]['mode'] = 4
        for material in document['materials']:
            material.update(alphaMode='OPAQUE', doubleSided=False)
        for index in (1, 4, 7):
            document['accessors'][index].update(min=[-1, -1, -1], max=[1, 1, 1])
        for index in (2, 5, 8):
            document['accessors'][index].update(min=[0], max=[23])
        self.assertTrue(self.check(repack(document, binary))['structural_pass'])

    def test_consistently_remapped_array_order(self):
        document, binary = baseline()
        for node in document['nodes']:
            if 'children' in node:
                node['children'] = [3 - index for index in node['children']]
            if 'mesh' in node:
                node['mesh'] = 2 - node['mesh']
        document['scenes'][0]['nodes'] = [3]
        for mesh in document['meshes']:
            primitive = mesh['primitives'][0]
            primitive['material'] = 2 - primitive['material']
            primitive['indices'] = 8 - primitive['indices']
            primitive['attributes'] = {key: 8 - index for key, index in primitive['attributes'].items()}
        for accessor in document['accessors']:
            accessor['bufferView'] = 8 - accessor['bufferView']
        for key in ('nodes', 'meshes', 'materials', 'accessors', 'bufferViews'):
            document[key].reverse()
        self.assertTrue(self.check(repack(document, binary))['structural_pass'])

    def test_material_tolerance_and_alpha_domain(self):
        document, binary = baseline()
        pbr = document['materials'][0]['pbrMetallicRoughness']
        pbr['baseColorFactor'][0] = 0.125 + 2 ** -22
        pbr['baseColorFactor'][3] = 1 - 2 ** -22
        self.assertTrue(self.check(repack(document, binary))['structural_pass'])
        for alpha in (1 - 2 ** -19, 0.5, 1 + 2 ** -22, -2 ** -22):
            pbr['baseColorFactor'][3] = alpha
            with self.subTest(alpha=alpha):
                self.refused(document, binary)
        for key, value in [('alphaMode', 'BLEND'), ('alphaMode', 'MASK'), ('doubleSided', True)]:
            document, binary = baseline()
            document['materials'][0][key] = value
            self.refused(document, binary)

    def test_node_identity_and_types(self):
        for location, key, value in [('node', 'translation', [0, 0.0000001, 0]), ('node', 'scale', [1, 1, -1]),
                                    ('node', 'name', 'WrongRoot'), ('scene', 'scene', True), ('accessor', 'count', True),
                                    ('accessor', 'normalized', 0), ('view', 'buffer', False)]:
            document, binary = baseline()
            target = {'node': document['nodes'][0], 'scene': document, 'accessor': document['accessors'][0], 'view': document['bufferViews'][0]}[location]
            target[key] = value
            self.refused(document, binary)

    def test_unreferenced_shared_or_extra_objects(self):
        for key in ('nodes', 'meshes', 'materials', 'accessors', 'bufferViews'):
            document, binary = baseline()
            document[key].append(copy.deepcopy(document[key][0]))
            self.refused(document, binary)
        for fault in ('mesh', 'accessor', 'view', 'material'):
            document, binary = baseline()
            if fault == 'mesh':
                document['nodes'][2]['mesh'] = 0
            elif fault == 'accessor':
                document['meshes'][1]['primitives'][0]['attributes']['POSITION'] = 0
            elif fault == 'view':
                document['accessors'][3]['bufferView'] = 0
            else:
                document['meshes'][0]['primitives'][0]['material'] = 1
            self.refused(document, binary)

    def test_span_alignment_and_count_failures(self):
        for location, key, value in [('view', 'byteOffset', 1), ('view', 'byteOffset', 1944), ('view', 'byteLength', 289),
                                    ('accessor', 'byteOffset', 4), ('accessor', 'count', 15001),
                                    ('accessor', 'componentType', 5123), ('accessor', 'min', [-0.5, 0, -0.25])]:
            document, binary = baseline()
            target = document['bufferViews'][0] if location == 'view' else document['accessors'][0]
            target[key] = value
            self.refused(document, binary)

    def test_actual_word_normal_index_and_winding_faults(self):
        for offset, fmt, values in [(0, '<I', [0x7FC00000]), (288, '<fff', [0, 0, 0]), (288, '<fff', [0.5, 0, 0]),
                                    (288, '<I', [0x7F800000]), (576, '<H', [24]), (578, '<H', [0]), (576, '<HHH', [0, 2, 1])]:
            document, binary = baseline()
            struct.pack_into(fmt, binary, offset, *values)
            with self.subTest(offset=offset, values=values):
                self.refused(document, binary)
        document, binary = baseline()
        binary[48:96] = binary[:48]
        binary[336:384] = binary[288:336]
        self.refused(document, binary)

    def test_negative_zero_is_numeric_zero(self):
        document, binary = baseline()
        struct.pack_into('<I', binary, 4, 0x80000000)    # first positionY0
        struct.pack_into('<I', binary, 292, 0x80000000)  # first normalY0
        self.assertTrue(self.check(repack(document, binary))['structural_pass'])

    def test_geometry_and_metadata_changed_together(self):
        document, binary = baseline()
        # Outer top25→23 remains finite/nondegenerate but tree height23<24.
        for index in range(24):
            offset = 1296 + index * 12 + 4
            if struct.unpack_from('<f', binary, offset)[0] == 25:
                struct.pack_into('<f', binary, offset, 23)
        document['accessors'][6]['max'][1] = 23
        self.refused(document, binary)

    def test_predeclared_zero_alignment_gap_and_bin_padding(self):
        document, binary = baseline()
        # Independent new control: insert exactly4zero bytes after Bark's288
        # position bytes, move every following view+4, preserve all hand vectors.
        binary[288:288] = b'\0' * 4
        document['buffers'][0]['byteLength'] = 1948
        for view in document['bufferViews'][1:]:
            view['byteOffset'] += 4
        self.assertTrue(self.check(repack(document, binary))['structural_pass'])
        binary[289] = 1
        self.refused(document, binary)
        # Separate control: one declared unused zero byte plus three GLB BIN
        # padding bytes; all nine hand spans remain unchanged inside1945bytes.
        document, binary = baseline()
        document['buffers'][0]['byteLength'] = 1945
        binary.extend(b'\0' * 4)
        self.assertTrue(self.check(repack(document, binary))['structural_pass'])
        binary[-1] = 1
        self.refused(document, binary)


class BundleReceiptChecks(unittest.TestCase):
    """Six synthetic box witnesses/receipt only; never actual .blend or artwork."""
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.project = Path(self.temporary.name).absolute()
        self.source = self.project / '.local/source'
        (self.source / 'exports').mkdir(parents=True)
        actual_project = SOURCE.parents[3]
        for relative in ('docs/contracts/world/original-evergreens-v1.md', 'third_party/licenses/notices/OriginalEvergreens-MIT.txt'):
            destination = self.project / relative
            destination.parent.mkdir(parents=True, exist_ok=True)
            destination.write_bytes((actual_project / relative).read_bytes())
        generator = self.project / 'assets_source/environment/original-evergreens-v1/generate_trees.py'
        generator.parent.mkdir(parents=True)
        generator.write_bytes(b'# Independent synthetic receipt source, not an executable art generator.\n')
        blend = b'BLENDER-v405SYNTHETIC-HASH-FIXTURE-NOT-EDITABLE-SOURCE'
        (self.source / 'original-evergreens.blend').write_bytes(blend)
        notice = (self.project / 'third_party/licenses/notices/OriginalEvergreens-MIT.txt').read_bytes()
        self.receipt = {'kind': 'OriginalEvergreenSource/v1', 'version': 1, 'license': 'MIT',
                        'scope': 'Original decorative evergreen art; no botanical, geographic or obstacle claim',
                        'contract_sha256': 'eb3aea53ba869b80117eaed952ac1f65ec2e1e3df1fe731524715fd7e3ae40d6',
                        'generator': {'path': 'assets_source/environment/original-evergreens-v1/generate_trees.py', 'sha256': hashlib.sha256(generator.read_bytes()).hexdigest()},
                        'blender': {'version': '4.5.14 LTS', 'build_hash': '62c1db4208e8'},
                        'blend': {'path': 'original-evergreens.blend', 'bytes': len(blend), 'sha256': hashlib.sha256(blend).hexdigest()},
                        'notice': {'path': 'third_party/licenses/notices/OriginalEvergreens-MIT.txt', 'sha256': hashlib.sha256(notice).hexdigest()}, 'exports': []}
        # Independent synthetic dimensions: tall25x5x5, broad19x9.5x9,
        # mature22x8x8; both LODs are the same36-triangle box witness, not art.
        specifications = [('tall-narrow', 'OriginalTallNarrow', (1, 1, 1)),
                          ('broad-tiered', 'OriginalBroadTiered', (1.9, 19 / 25, 1.8)),
                          ('irregular-mature', 'OriginalIrregularMature', (1.6, 22 / 25, 1.6))]
        for name, root, scale in specifications:
            for lod in (0, 1):
                document, binary = baseline()
                document['nodes'][0]['name'] = root + 'L' + str(lod)
                for accessor_index in (0, 3, 6):
                    accessor = document['accessors'][accessor_index]
                    offset = document['bufferViews'][accessor['bufferView']]['byteOffset']
                    vectors = []
                    for index in range(24):
                        old = struct.unpack_from('<fff', binary, offset + index * 12)
                        struct.pack_into('<fff', binary, offset + index * 12, *(value * factor for value, factor in zip(old, scale)))
                        vectors.append(struct.unpack_from('<fff', binary, offset + index * 12))
                    accessor['min'] = [min(row[axis] for row in vectors) for axis in range(3)]
                    accessor['max'] = [max(row[axis] for row in vectors) for axis in range(3)]
                path = 'exports/' + name + '-lod' + str(lod) + '.glb'
                raw = repack(document, binary)
                (self.source / path).write_bytes(raw)
                self.receipt['exports'].append({'id': name, 'lod': lod, 'path': path, 'bytes': len(raw), 'sha256': hashlib.sha256(raw).hexdigest()})
        self.save()

    def tearDown(self):
        self.temporary.cleanup()

    def save(self):
        (self.source / 'evergreen-source-v1.json').write_text(json.dumps(self.receipt), encoding='utf-8')

    def check(self):
        return C._check_bundle(self.source, self.project)

    def test_synthetic_receipt_and_pair_controls_do_not_accept_art(self):
        report = self.check()
        self.assertTrue(report['source_receipt_integrity_pass'])
        self.assertTrue(report['all_six_glb_structure_pass'])
        self.assertTrue(report['lod_pair_bounds_pass'])
        self.assertFalse(report['artwork_accepted'])
        self.assertFalse(report['import_accepted'])
        for index, dimensions in [(0, [25, 5, 5]), (2, [19, 9.5, 9]), (4, [22, 8, 8])]:
            self.assertEqual(report['exports'][index]['height_width_depth_m'], dimensions)

    def test_fixed_pin_receipt_mutations(self):
        original = copy.deepcopy(self.receipt)
        for target, key, value in [('root', 'version', True), ('root', 'self_hash', '0' * 64),
                                   ('root', 'contract_sha256', '0' * 64), ('generator', 'sha256', '0' * 64),
                                   ('notice', 'sha256', '0' * 64), ('blender', 'version', '4.5.15 LTS'),
                                   ('blend', 'bytes', 12), ('blend', 'path', '../escape.blend')]:
            self.receipt = copy.deepcopy(original)
            destination = self.receipt if target == 'root' else self.receipt[target]
            destination[key] = value
            self.save()
            with self.subTest(target=target, key=key), self.assertRaises(C.InvalidGlb):
                self.check()

    def test_export_roster_and_source_hash_faults(self):
        original = copy.deepcopy(self.receipt)
        for key, value in [('path', '../escape.glb'), ('lod', True), ('id', 'other'), ('sha256', '0' * 64), ('bytes', 1), ('extra', False)]:
            self.receipt = copy.deepcopy(original)
            self.receipt['exports'][0][key] = value
            self.save()
            with self.subTest(key=key), self.assertRaises(C.InvalidGlb):
                self.check()
        self.receipt = original
        self.receipt['exports'].reverse()
        self.save()
        with self.assertRaises(C.InvalidGlb):
            self.check()

    def test_unrecorded_files_and_changed_source(self):
        extra = self.source / 'unexpected.txt'
        extra.write_bytes(b'not allowed')
        with self.assertRaises(C.InvalidGlb):
            self.check()
        extra.unlink()
        generator = self.project / 'assets_source/environment/original-evergreens-v1/generate_trees.py'
        generator.write_bytes(b'changed after receipt')
        with self.assertRaises(C.InvalidGlb):
            self.check()

    def test_source_receipt_duplicate_bom_and_bounds(self):
        path = self.source / 'evergreen-source-v1.json'
        original = path.read_bytes()
        for raw in (b'\xef\xbb\xbf' + original, b'{"version":1,' + original[1:], b' ' * 65537):
            path.write_bytes(raw)
            with self.subTest(raw=raw[:30]), self.assertRaises(C.InvalidGlb):
                self.check()
        path.write_bytes(original)

    def test_pair_bound_margin_predeclared_before_art(self):
        row = self.receipt['exports'][3]  # broad-tiered LOD1
        original_raw = (self.source / row['path']).read_bytes()
        json_length = struct.unpack_from('<I', original_raw, 12)[0]
        original_document = json.loads(original_raw[20:20 + json_length])
        bin_length = struct.unpack_from('<I', original_raw, 20 + json_length)[0]
        original_binary = original_raw[28 + json_length:28 + json_length + bin_length]
        for delta, accepted in [(0.015625, True), (0.03125, False)]:
            document, binary = copy.deepcopy(original_document), bytearray(original_binary)
            # Only the known+X extremum4.75 moves; all actual matching positions
            # and accessor maxima change together. Both trees stay inside class.
            for accessor_index in (0, 3, 6):
                accessor = document['accessors'][accessor_index]
                view = document['bufferViews'][accessor['bufferView']]
                changed = False
                for index in range(accessor['count']):
                    offset = view['byteOffset'] + index * 12
                    if struct.unpack_from('<f', binary, offset)[0] == 4.75:
                        struct.pack_into('<f', binary, offset, 4.75 + delta)
                        changed = True
                if changed:
                    accessor['max'][0] = 4.75 + delta
            raw = repack(document, binary)
            (self.source / row['path']).write_bytes(raw)
            row.update(bytes=len(raw), sha256=hashlib.sha256(raw).hexdigest())
            self.save()
            if accepted:
                self.assertTrue(self.check()['lod_pair_bounds_pass'])
            else:
                with self.assertRaises(C.InvalidGlb):
                    self.check()


def main():
    global REFERENCE
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--reference', required=True)
    args, remaining = parser.parse_known_args()
    path = Path(args.reference)
    if path.stat().st_size > 1024 * 1024:
        raise ValueError('independent reference byte bound')
    raw = path.read_bytes()
    if hashlib.sha256(raw).hexdigest() != REFERENCE_SHA256:
        raise ValueError('independent Root-frozen reference SHA mismatch')
    REFERENCE = json.loads(raw)
    unittest.main(argv=[str(Path(__file__)), *remaining], verbosity=2)


if __name__ == '__main__':
    main()
