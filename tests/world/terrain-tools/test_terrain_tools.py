"""Independent small synthetic refusal/bit fixtures; no native/package import.

Run after source review with a verified interpreter, e.g. Python -I -B -S thisfile.
No production pin override or successful real-environment claim is made here.
"""
import base64
import copy
import hashlib
import importlib.util
import io
import json
from pathlib import Path
import stat
import struct
import sys
import tempfile
import unittest
import zipfile


SOURCE = Path(__file__).absolute().parents[3] / 'tools/ingest/terrain'


def load(name, filename):
    spec = importlib.util.spec_from_file_location(name, SOURCE / filename)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


T = load('terrain_tools_under_test', 'terrain_tools.py')
D = load('terrain_decode_under_test', 'terrain_decode.py')


def zip_bytes(entries):
    buffer = io.BytesIO()
    with zipfile.ZipFile(buffer, 'w', compression=zipfile.ZIP_STORED) as archive:
        for name, raw in entries:
            archive.writestr(name, raw)
    buffer.seek(0)
    return buffer


def fixed_codes(codes, widths):
    # Literal code words specified by each test, not an LZW encoder. Expected
    # decoded bytes are separate hand values and never production-derived.
    bits = ''.join(format(code, '0' + str(width) + 'b') for code, width in zip(codes, widths))
    bits += '0' * (-len(bits) % 8)
    return int(bits, 2).to_bytes(len(bits) // 8, 'big')


LITERAL_FLOAT_BYTES = b'\x00\x00\x80\x3f\x00\x00\x20\xc0'  # +1.0, -2.5 LE IEEE32
LITERAL_FLOAT_LZW = fixed_codes([256, 0, 0, 128, 63, 0, 0, 32, 192, 257], [9] * 10)


def fixed_tiff():
    # One primary 2x1 strip, twelve closed TIFF tags, no predictor. The hand
    # byte offset is 8 +2 +(12*12) +4 =158; it is not obtained from the reader.
    tags = [(256, 3, 1, 2), (257, 3, 1, 1), (258, 3, 1, 32), (259, 3, 1, 5),
            (262, 3, 1, 1), (273, 4, 1, 158), (277, 3, 1, 1), (278, 4, 1, 1),
            (279, 4, 1, len(LITERAL_FLOAT_LZW)), (284, 3, 1, 1), (317, 3, 1, 1), (339, 3, 1, 3)]
    return b'II\x2a\x00\x08\x00\x00\x00' + struct.pack('<H', 12) + b''.join(struct.pack('<HHII', *tag) for tag in tags) + b'\x00' * 4 + LITERAL_FLOAT_LZW


class StrictLockTests(unittest.TestCase):
    def test_exact_fixed_lock_and_distinct_types(self):
        T.exact(T.strict_json(json.dumps(T.EXPECTED_LOCK).encode()), T.EXPECTED_LOCK)
        for path, value in [(('schema_version',), True), (('runtime_dependency',), 0), (('host', 'upstream_interpreter_archive'), {}),
                            (('policy', 'only_best'), 1), (('grid', 'bytes'), 16742155.0)]:
            changed = copy.deepcopy(T.EXPECTED_LOCK)
            cursor = changed
            for part in path[:-1]:
                cursor = cursor[part]
            cursor[path[-1]] = value
            with self.subTest(path=path), self.assertRaises(T.Refusal):
                T.exact(changed, T.EXPECTED_LOCK)

    def test_unknown_missing_and_reordered_wheels(self):
        for mutation in ('unknown', 'missing', 'reordered', 'url', 'hash'):
            changed = copy.deepcopy(T.EXPECTED_LOCK)
            if mutation == 'unknown':
                changed['host']['allow_override'] = False
            elif mutation == 'missing':
                del changed['grid']['readme']
            elif mutation == 'reordered':
                changed['wheels'].reverse()
            elif mutation == 'url':
                changed['wheels'][0]['url'] += '?mirror=other'
            else:
                changed['wheels'][0]['sha256'] = '0' * 64
            with self.subTest(mutation=mutation), self.assertRaises(T.Refusal):
                T.exact(changed, T.EXPECTED_LOCK)

    def test_strict_bytes(self):
        for raw in (b'\xef\xbb\xbf{}', b'{"a":1,"a":2}', b'{"a":NaN}', b'{"a":Infinity}', b'{"a":-Infinity}', b'\xff', b' ' * 65537):
            with self.subTest(raw=raw[:40]), self.assertRaises((T.Refusal, UnicodeError, ValueError)):
                T.strict_json(raw)


class MemberTests(unittest.TestCase):
    def test_paths(self):
        self.assertEqual(T.member_name('package/file.cp312-win_amd64.pyd'), 'package/file.cp312-win_amd64.pyd')
        for name in ('', '../bad', 'a/../b', './bad', '/bad', 'C:/bad', 'a\\b', 'a//b', 'a/', 'a:stream', 'con.txt', 'A/LPT1', 'a.', 'a ', 'a/\x00b', 'a?/b', 'é/file'):
            with self.subTest(name=name), self.assertRaises(T.Refusal):
                T.member_name(name)

    def test_zip_roster_and_duplicates(self):
        with zipfile.ZipFile(zip_bytes([('pkg/a', b'hello'), ('pkg/b', b'world')])) as archive:
            files, directories = T.wheel_roster(archive)
            self.assertEqual(set(files), {'pkg/a', 'pkg/b'})
            self.assertEqual(directories, [])
        cases = [ [('a', b'1'), ('A', b'2')], [('a', b'1'), ('a/b', b'2')], [('a/../b', b'1')],
                 [('pkg/payload.pth', b'code')], [('pkg.data/a', b'code')], [('pkg/a.exe', b'MZ')]]
        for entries in cases:
            with self.subTest(entries=entries), zipfile.ZipFile(zip_bytes(entries)) as archive, self.assertRaises(T.Refusal):
                T.wheel_roster(archive)

    def test_safe_explicit_directory_entries_are_not_record_files(self):
        info = zipfile.ZipInfo('pkg/')
        info.create_system = 3
        info.external_attr = (stat.S_IFDIR | 0o777) << 16
        with zipfile.ZipFile(zip_bytes([(info, b''), ('pkg/a', b'abc'), ('empty/', b'')])) as archive:
            files, directories = T.wheel_roster(archive)
            self.assertEqual(set(files), {'pkg/a'})
            self.assertEqual(directories, ['empty', 'pkg'])
            # Directory headers never enter RECORD's exact regular-file roster.
            sha = base64.urlsafe_b64encode(hashlib.sha256(b'abc').digest()).decode().rstrip('=')
            self.assertEqual(T.record_rows(('pkg/a,sha256=' + sha + ',3\n').encode(), files, 'unused-self-record')['pkg/a']['bytes'], 3)

    def test_explicit_directory_faults(self):
        cases = [[('pkg/', b'payload')], [('pkg//', b'')], [('../pkg/', b'')],
                 [('pkg/', b''), ('pkg/', b'')], [('pkg/', b''), ('PKG/', b'')],
                 [('pkg', b'file'), ('pkg/', b'')], [('pkg/', b''), ('pkg', b'file')],
                 [('pkg', b'file'), ('pkg/a/', b'')], [('pkg/', b''), ('PKG/a', b'file')],
                 [('pkg/a', b'file'), ('PKG/b', b'file')], [('pkg.data/', b'')]]
        for entries in cases:
            with self.subTest(entries=entries), zipfile.ZipFile(zip_bytes(entries)) as archive, self.assertRaises(T.Refusal):
                T.wheel_roster(archive)
        for name, kind in [('pkg/', stat.S_IFREG), ('pkg', stat.S_IFDIR), ('pkg/', stat.S_IFLNK)]:
            info = zipfile.ZipInfo(name)
            info.create_system = 3
            info.external_attr = (kind | 0o777) << 16
            with self.subTest(name=name, kind=kind), zipfile.ZipFile(zip_bytes([(info, b'')])) as archive, self.assertRaises(T.Refusal):
                T.wheel_roster(archive)

    def test_symlink_zip_member(self):
        info = zipfile.ZipInfo('pkg/link')
        info.create_system = 3
        info.external_attr = (stat.S_IFLNK | 0o777) << 16
        with zipfile.ZipFile(zip_bytes([(info, b'target')])) as archive, self.assertRaises(T.Refusal):
            T.wheel_roster(archive)

    def test_expansion_limits(self):
        with zipfile.ZipFile(zip_bytes([('a', b'x')])) as archive:
            archive.getinfo('a').file_size = T.MAX_WHEEL_MEMBER + 1
            with self.assertRaises(T.Refusal):
                T.wheel_roster(archive)

    def test_record_closed_roster_and_sha(self):
        sha = base64.urlsafe_b64encode(hashlib.sha256(b'abc').digest()).decode().rstrip('=')
        raw = ('pkg/a,sha256=' + sha + ',3\npkg.dist-info/RECORD,,\n').encode()
        names = {'pkg/a': None, 'pkg.dist-info/RECORD': None}
        actual = T.record_rows(raw, names, 'pkg.dist-info/RECORD')
        self.assertEqual(actual['pkg/a'], {'bytes': 3, 'sha256': 'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad'})
        for bad in (raw + b'unknown,,\n', raw + raw, raw.replace(b',3\n', b',03\n'), raw.replace(b'sha256=', b'md5='), raw.replace(b'RECORD,,', b'RECORD,sha256=bad,1'), b'pkg/a,,\n'):
            with self.subTest(bad=bad), self.assertRaises(T.Refusal):
                T.record_rows(bad, names, 'pkg.dist-info/RECORD')


class ManifestTests(unittest.TestCase):
    def test_complete_manifest_includes_empty_directories(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / 'empty').mkdir()
            (root / 'data').mkdir()
            (root / 'data/a').write_bytes(b'abc')
            expected = {'files': [{'path': 'data/a', 'bytes': 3, 'sha256': 'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad'}], 'directories': ['data', 'empty']}
            self.assertEqual(T.tree(root), expected)
            (root / 'new').write_bytes(b'extra')
            with self.assertRaises(T.Refusal):
                T.exact(T.tree(root), expected)
            (root / 'new').unlink()
            (root / 'data/a').write_bytes(b'bad')
            with self.assertRaises(T.Refusal):
                T.exact(T.tree(root), expected)

    def test_new_file_only_and_lexical_parent_normalization(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            value = root / 'receipt.json'
            T.write_json(value, {'passed': False})
            with self.assertRaises(FileExistsError):
                T.write_json(value, {'passed': True})
            self.assertEqual(T.plain(root / 'unused/../receipt.json'), value)

    def test_directory_closure(self):
        self.assertEqual(T.directory_closure([{'path': 'environment/Lib/pkg/a.py'}, {'path': 'proj-data/proj.db'}], ['empty']),
                         ['empty', 'environment', 'environment/Lib', 'environment/Lib/pkg', 'proj-data'])


class IndependentLzwTests(unittest.TestCase):
    def test_float32_literals(self):
        self.assertEqual(D.lzw_tiff(LITERAL_FLOAT_LZW, 8), LITERAL_FLOAT_BYTES)
        self.assertEqual(struct.unpack('<ff', LITERAL_FLOAT_BYTES), (1.0, -2.5))

    def test_kwkwk_and_clear(self):
        self.assertEqual(D.lzw_tiff(fixed_codes([256, 65, 258, 257], [9] * 4), 3), b'AAA')
        self.assertEqual(D.lzw_tiff(fixed_codes([256, 65, 256, 66, 257], [9] * 5), 2), b'AB')

    def test_tiff_early_change_width(self):
        # 254 literal codes allocate dictionary indices258..510. Next-free511
        # changes the following code width to10 before an ordinary 512 boundary.
        encoded = fixed_codes([256] + [0] * 255 + [257], [9] * 255 + [10, 10])
        self.assertEqual(D.lzw_tiff(encoded, 255), b'\0' * 255)
        late_change = fixed_codes([256] + [0] * 255 + [257], [9] * 256 + [10])
        with self.assertRaises(D.DecodeRefusal):
            D.lzw_tiff(late_change, 255)

    def test_all_widths_full_dictionary_and_reset(self):
        # After254,766,1790 literals the next-free codes are511,1023,2047.
        # Remaining literal words use12bits, including a clear after saturation.
        codes = [256] + [0] * 5000 + [256, 42, 257]
        widths = [9] * 255 + [10] * 512 + [11] * 1024 + [12] * (5000 - 1790 + 1) + [9, 9]
        self.assertEqual(len(codes), len(widths))
        self.assertEqual(D.lzw_tiff(fixed_codes(codes, widths), 5001), b'\0' * 5000 + b'*')

    def test_malformed_or_unbounded(self):
        cases = [(fixed_codes([65, 257], [9, 9]), 1), (fixed_codes([256, 300, 257], [9] * 3), 1),
                 (fixed_codes([256, 65], [9, 9]), 1), (fixed_codes([256, 65, 66, 257], [9] * 4), 1), (b'', 1)]
        for encoded, length in cases:
            with self.subTest(encoded=encoded), self.assertRaises(D.DecodeRefusal):
                D.lzw_tiff(encoded, length)

    def test_fixed_tiff_strip_and_rejections(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'fixture.tif'
            raw = fixed_tiff()
            path.write_bytes(raw)
            reader = D.TiffBlocks(path)
            try:
                self.assertEqual(reader.block(0), (0, 0, 2, 1, LITERAL_FLOAT_BYTES))
            finally:
                reader.close()
            # Fixed tag field locations derive from the literal twelve-tag list.
            for offset, replacement in [(2, b'\x2b\x00'), (10 + 10 * 12 + 8, b'\x03\x00\x00\x00'), (10 + 5 * 12 + 8, b'\xff\xff\xff\xff')]:
                changed = bytearray(raw)
                changed[offset:offset + len(replacement)] = replacement
                path.write_bytes(changed)
                try:
                    with self.assertRaises(D.DecodeRefusal):
                        reader = D.TiffBlocks(path)
                        try:
                            reader.block(0)
                        finally:
                            reader.close()
                finally:
                    path.write_bytes(raw)

    def test_invalid_sample_classification_not_8bit(self):
        # Literal IEEE binary32: +1, -2.5, -999999, +inf, quietNaN.
        raw = bytes.fromhex('0000803f000020c0f02374c90000807f0000c07f')
        self.assertEqual(D.float_counts(raw), {'samples': 5, 'nodata': 1, 'nonfinite': 2, 'minimum_valid': -2.5, 'maximum_valid': 1.0})

    def test_tiled_padding_is_distinct_from_logical_raster(self):
        pixels = LITERAL_FLOAT_BYTES + b'\0' * 8
        compressed = fixed_codes([256, *pixels, 257], [9] * 18)
        # Literal13tagIFD data starts at8+2+13*12+4=170. Logical1x1
        # raster occupies only the firstFloat32 of a padded2x2 source tile.
        tags = [(256, 3, 1, 1), (257, 3, 1, 1), (258, 3, 1, 32), (259, 3, 1, 5), (262, 3, 1, 1),
                (277, 3, 1, 1), (284, 3, 1, 1), (317, 3, 1, 1), (322, 3, 1, 2), (323, 3, 1, 2),
                (324, 4, 1, 170), (325, 4, 1, len(compressed)), (339, 3, 1, 3)]
        raw = b'II\x2a\x00\x08\x00\x00\x00' + struct.pack('<H', 13) + b''.join(struct.pack('<HHII', *tag) for tag in tags) + b'\0' * 4 + compressed
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'tile.tif'
            path.write_bytes(raw)
            reader = D.TiffBlocks(path)
            try:
                x, y, width, rows, result = reader.block(0)
                self.assertEqual((x, y, width, rows), (0, 0, 2, 2))
                self.assertEqual(result, pixels)
                self.assertEqual((reader.width, reader.height), (1, 1))
                self.assertEqual(result[:4], b'\x00\x00\x80\x3f')
            finally:
                reader.close()


if __name__ == '__main__':
    unittest.main(verbosity=2)
