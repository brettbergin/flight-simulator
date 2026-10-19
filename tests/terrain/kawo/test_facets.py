"""Hand-derived spacing4 planar facets; expected heights use final f32 words."""
from fractions import Fraction
import unittest

from _support import b64, compiler, word64


class FacetTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.c = compiler()

    def intersection(self, heights, columns=2, rows=2, east=-2., south=-2.,
                     minimum=0., maximum=4., valid=None):
        return self.c.facet_intersection((0., 0., 0.), (0., 1., 0.), heights,
                                         columns, rows, east, south, 4,
                                         minimum, maximum, valid)

    def test_saddle_uses_planes_not_bilinear(self):
        heights = [0., 4., 4., 0.]
        cases = ((-2., -2., 0., -1, 1),
                 (-1., -3., 2., -1, 1),
                 (-3., -1., 2., 1, -1))
        for east, south, height, p, q in cases:
            with self.subTest(origin=(east, south)):
                result = self.intersection(heights, east=east, south=south)
                self.assertEqual(result['h'], height)
                self.assertEqual(tuple(result['eus']), (0., height, 0.))
                self.assertEqual((result['p'], result['q']), (Fraction(p), Fraction(q)))

    def test_internal_edge_and_strict_sides(self):
        heights = [0., 0., 4., 0., 0., 4.]
        cases = ((-4., 0., 1), (-4. + 2.**-24, 0., 0),
                 (-4. - 2.**-24, 2.**-24, 1))
        for east, height, p in cases:
            with self.subTest(east=east):
                result = self.intersection(heights, columns=3, east=east)
                self.assertEqual(result['h'], height)
                self.assertEqual((result['p'], result['q']), (Fraction(p), Fraction(0)))

    def test_internal_vertex_higher_row_and_column(self):
        result = self.intersection([0., 0., 4., 0., 0., 4., 4., 4., 8.],
                                   columns=3, rows=3, east=-4., south=-4., maximum=8.)
        self.assertEqual(result['h'], 0.)
        self.assertEqual((result['p'], result['q']), (Fraction(1), Fraction(1)))

    def test_outer_minimum_included_maximum_excluded(self):
        result = self.intersection([10.] * 4, east=0., south=0., minimum=10., maximum=10.)
        self.assertEqual(result['h'], 10.)
        with self.assertRaises(self.c.Refusal):
            self.intersection([10.] * 4, east=-4., south=-4., minimum=10., maximum=10.)

    def test_padding_missing_is_not_physical_support_missing(self):
        nan = float('nan')
        result = self.intersection([nan, 0., 4., nan, 0., 4.], columns=3,
                                   east=-4., valid=[0x36])
        self.assertEqual(result['h'], 0.)
        self.assertEqual(result['p'], Fraction(1))
        with self.assertRaises(self.c.Refusal):
            self.intersection([0., 0., nan, 0., 0., nan], columns=3,
                              east=-4., minimum=0., maximum=0., valid=[0x1b])

    def test_final_rounded_surface_is_authority(self):
        # q=1+2^-24 rounds to f32 1; the independent facet must use1.
        result = self.intersection([1.] * 4, minimum=1., maximum=1.)
        self.assertEqual(result['h'], 1.)
        self.assertNotEqual(result['h'], b64('3ff0000010000000'))

    def test_endpoint_product_then_add(self):
        # Frozen arithmetic-only witness, not a complete realized unit ray.
        result = self.c.endpoint_at((b64('3f50000000000000'), 0., 0.),
                                    (b64('bf50000020000000'), 1., 0.),
                                    b64('3fefffffffe00000'))
        self.assertEqual(word64(result[0]), 'bddff00000000000')


if __name__ == '__main__':
    unittest.main()
