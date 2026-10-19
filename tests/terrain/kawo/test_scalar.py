"""Literal arithmetic controls; none is an admitted source/geographic product."""
import unittest

from _support import b64, compiler, word64


class ScalarTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.c = compiler()

    def test_height_sign_and_separate_bilinear_primitives(self):
        # Frozen hand-oracles8d542: synthetic H100+N(-22.75)=77.25.
        self.assertEqual(self.c.scalar_update(0.0, 0.0, 100.0, -22.75, 1.0), 77.25)
        # Fused product/add gives a different B64 word; final f32 can hide it.
        h = self.c.bilinear(1.0, -2.0**-23, 1.0, -2.0**-23,
                            b64('3fefffffffe00000'), 0.0)
        self.assertEqual(word64(h), 'be7ff00000000000')

    def test_dot_primitive_order(self):
        self.assertEqual(word64(self.c.dot3((2.0**53, 1.0, -2.0**53),
                                           (1.0, 1.0, 1.0))), '0000000000000000')

    def test_target_line_anchor_addition_order(self):
        # Frozen solver design a7ed. Synthetic operands, not a full frame.
        basis = {'east': (2.0**-33, 0.0, 0.0),
                 'up': (1.0, 0.0, 0.0), 'south': (0.0, 0.0, 0.0)}
        result = self.c.target_ecef(4.0, -3.0 * 2.0**-31, 0.0,
                                    (6378137.0, 0.0, 0.0), basis)
        self.assertEqual(word64(result[0]), '415854a63ffffffe')

    def test_f32_rne_literal_words(self):
        cases = (
            ('3ff0000010000000', 0x3f800000),
            ('3ff000000fffffff', 0x3f800000),
            ('3ff0000010000001', 0x3f800001),
            ('3ff0000030000000', 0x3f800002),
            ('bff0000010000000', 0xbf800000),
            ('bff0000030000000', 0xbf800002),
            ('3690000000000000', 0x00000000),
            ('b690000000000000', 0x80000000),
            ('36a8000000000000', 0x00000002),
        )
        for source_word, expected in cases:
            with self.subTest(word=source_word):
                promoted, actual = self.c.f32_round(b64(source_word))
                self.assertEqual(actual, expected)
                # Signed zero must survive promotion, not just integer word output.
                if expected in (0, 0x80000000):
                    self.assertEqual(word64(promoted),
                                     '8000000000000000' if expected else '0000000000000000')

    def test_exact_millimeter_controls(self):
        cases = (
            ('3fb0000000000000', 63), ('3fafffffffffffff', 62),
            ('3fb0000000000001', 63), ('bfb0000000000000', -63),
            ('bfafffffffffffff', -62), ('bfb0000000000001', -63),
            ('0000000000000000', 0), ('8000000000000000', 0),
            ('3f726e978d4fdf3b', 4), ('bf726e978d4fdf3b', -4),
        )
        for source_word, expected in cases:
            with self.subTest(word=source_word):
                self.assertEqual(self.c.round_mm(b64(source_word)), expected)

    def test_exact_gradient_subnormal_witness(self):
        # Frozen246 exact-admission reference: tiny excess is invisible to B64
        # subtraction/norm squaring but is mathematically above16.
        # At fixed4m use height64, independently scaling frozen2m/32 control.
        self.assertTrue(self.c.gradient_admitted(0, 0x42800000, 0, 0x42800000))
        self.assertFalse(self.c.gradient_admitted(0x80000001, 0x42800000,
                                                 0, 0x42800000))
        self.assertFalse(self.c.gradient_admitted(0, 0x42800001,
                                                 0, 0x42800001))
        self.assertEqual(self.c.f32_units(0x80000001), -1)

    def test_footprint_literal_corner_order(self):
        self.assertEqual([list(p) for p in self.c.footprint(
            (0.0, 10.0, 0.0), (4.0, 10.0, 0.0), 0.125)],
            [[0, -63], [0, 63], [4000, 63], [4000, -63]])
        for first, second, width in (((0., 0., 0.), (0., 0., 0.), 1.),
                                     ((0., 0., 0.), (4., 0., 0.), 0.)):
            with self.subTest(first=first, width=width):
                with self.assertRaises(self.c.Refusal):
                    self.c.footprint(first, second, width)


if __name__ == '__main__':
    unittest.main()
