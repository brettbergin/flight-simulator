"""Strict byte/type budgets, not a substitute for actual seven-file admission."""
import json
import unittest

from _support import compiler, word64


class InputTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.c = compiler()

    def test_json_byte_depth_value_inclusive_edges(self):
        self.assertEqual(self.c.strict_json(b'{}', 2, 1, 1), {})
        self.assertEqual(self.c.strict_json(b'[[0]]', 5, 3, 3), [[0]])
        self.assertEqual(self.c.strict_json(b'[0,1]', 5, 2, 3), [0, 1])
        for raw, limit, depth, values in ((b'{} ', 2, 1, 1),
                                          (b'[[0]]', 5, 2, 3),
                                          (b'[0,1]', 5, 2, 2)):
            with self.subTest(raw=raw, limits=(limit, depth, values)):
                with self.assertRaises(self.c.Refusal):
                    self.c.strict_json(raw, limit, depth, values)

    def test_strict_json_refusals(self):
        cases = (b'\xef\xbb\xbf{}', b'"\xff"', b'{"x":0,"x":1}',
                 b'{"x":0,"\\u0078":1}', b'NaN', b'Infinity', b'-Infinity',
                 b'1e9999', b'{} trailing', b'{"x":1,}', b'[01]', b'/*x*/{}')
        for raw in cases:
            with self.subTest(raw=raw):
                with self.assertRaises(self.c.Refusal):
                    self.c.strict_json(raw)

    def test_named_b64_scalars_preserve_zero_and_low_bit(self):
        for word in ('0000000000000000', '8000000000000000',
                     '0000000000000001', '3ff0000000000001'):
            tag = {'$binary64_le': bytes.fromhex(word)[::-1].hex()}
            self.assertEqual(word64(self.c.decode_b64(tag)), word)
        malformed = (None, 0., {'$binary64_le': '000000000000F03f'},
                     {'$binary64_le': '000000000000f03'},
                     {'$binary64_le': '000000000000f03g'},
                     {'$binary64_le': '000000000000f03f', 'extra': 0},
                     {'$binary64_le': '000000000000f07f'},
                     {'$binary64_le': '000000000000f0ff'},
                     {'$binary64_le': '000000000000f87f'})
        for tag in malformed:
            with self.subTest(tag=tag):
                with self.assertRaises(self.c.Refusal):
                    self.c.decode_b64(tag)

    def test_descriptor_closed_root_before_filesystem_use(self):
        # Each refusal occurs at closed shape/schema, never needs source files.
        roles = ('airport', 'dossier', 'tile55', 'tile55_metadata', 'tile56',
                 'tile56_metadata', 'tool_qualification')
        base = dict(schema='wrong', **dict.fromkeys(roles))
        with self.assertRaises(self.c.Refusal):
            self.c.admit_descriptor(json.dumps(base).encode('ascii'))
        base['schema'] = 'KawoTerrainInputs/v1'
        base['override'] = 4
        with self.assertRaises(self.c.Refusal):
            self.c.admit_descriptor(json.dumps(base).encode('ascii'))
        del base['override']
        del base['tile55']
        with self.assertRaises(self.c.Refusal):
            self.c.admit_descriptor(json.dumps(base).encode('ascii'))

    def test_relative_unc_and_nonpath_rejected(self):
        for path in ('relative/file.tif', '\\\\server\\share\\source.tif', 4, None):
            with self.subTest(path=path):
                with self.assertRaises(self.c.Refusal):
                    self.c.ordinary(path)


if __name__ == '__main__':
    unittest.main()
