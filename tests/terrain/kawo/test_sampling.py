"""Sparse literal samples are synthetic indexables, never fabricated TIFFs."""
import unittest

from _support import compiler, f32


class SparseSamples:
    """Only declared scalar addresses exist; records every access, no big array."""
    def __init__(self, entries):
        self.entries = dict(entries)
        self.accesses = []

    def __len__(self):
        return 10012 * 10012

    def __getitem__(self, index):
        self.accesses.append(index)
        if index not in self.entries:
            raise AssertionError('undeclared synthetic source address: ' + str(index))
        return self.entries[index]


class SamplingTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.c = compiler()

    def plane(self, tile, records):
        values = SparseSamples({r * 10012 + col: value for (r, col), value in records.items()})
        return self.c.SourcePlane(values, 0xff7fffff if tile == 55 else 0xc97423f0,
                                  origin_easting=549994 if tile == 55 else 559994), values

    def test_pixel_centers_and_north_row(self):
        p, values = self.plane(55, {(1, 1): 10., (1, 2): 20.,
                                    (0, 1): 10., (0, 2): 20., (1, 0): 0., (0, 0): 0.})
        self.assertEqual(self.c.sample_mosaic({55: p}, 549995.5, 5340004.5), 10.)
        self.assertEqual(values.accesses, [10013, 10014, 1, 2])
        self.assertEqual(self.c.sample_mosaic({55: p}, 549995.25, 5340004.5), 7.5)
        p, _ = self.plane(55, {(1, 1): 10., (1, 2): 10., (0, 1): 30., (0, 2): 30.})
        self.assertEqual(self.c.sample_mosaic({55: p}, 549995.5, 5340005.25), 25.)

    def test_zero_weight_neighbor_required(self):
        p, values = self.plane(55, {(1, 1): 10., (1, 2): 20.,
                                    (0, 1): 10., (0, 2): f32('ff7fffff')})
        with self.assertRaises(self.c.Refusal):
            self.c.sample_mosaic({55: p}, 549995.5, 5340004.5)
        self.assertIn(2, values.accesses)
        p, _ = self.plane(55, {(0, 0): 1., (0, 1): 2.})
        with self.assertRaises(self.c.Refusal):
            self.c.sample_mosaic({55: p}, 549994.5, 5340005.5)

    def seam(self, bad_tile=None):
        west = {(5005, 10005): 0., (5005, 10006): 2000.,
                (5004, 10005): 8., (5004, 10006): 4000.}
        east = {(5005, 5): 1000., (5005, 6): 4.,
                (5004, 5): 3000., (5004, 6): 20.}
        if bad_tile == 55:
            west[5005, 10005] = f32('ff7fffff')
        if bad_tile == 56:
            east[5005, 6] = f32('c97423f0')
        p55, v55 = self.plane(55, west)
        p56, v56 = self.plane(56, east)
        return {55: p55, 56: p56}, v55, v56

    def test_disagreeing_overlap_owner_before_bilinear(self):
        planes, west, east = self.seam()
        self.assertEqual(self.c.sample_mosaic(planes, 559999.75, 5335001.25), 8.5)
        self.assertEqual(west.accesses, [5005 * 10012 + 10005, 5004 * 10012 + 10005])
        self.assertEqual(east.accesses, [5005 * 10012 + 6, 5004 * 10012 + 6])

    def test_owner_missing_has_no_other_copy_retry(self):
        for tile in (55, 56):
            with self.subTest(tile=tile):
                planes, _, _ = self.seam(tile)
                with self.assertRaises(self.c.Refusal):
                    self.c.sample_mosaic(planes, 559999.75, 5335001.25)

    def test_each_tile_own_sentinel_only_and_finite_classification(self):
        for tile, i, col in ((55, 559999, 10005), (56, 560000, 6)):
            own, other = ('ff7fffff', 'c97423f0') if tile == 55 else ('c97423f0', 'ff7fffff')
            for raw in (other, '00000000', '80000000', 'c0200000', '00000001'):
                with self.subTest(tile=tile, raw=raw):
                    p, _ = self.plane(tile, {(5005, col): f32(raw)})
                    self.assertEqual(self.c.lattice_sample({tile: p}, i, 5335000), f32(raw))
            for raw in (own, '7fc00000', '7f800000', 'ff800000'):
                with self.subTest(tile=tile, raw=raw):
                    p, _ = self.plane(tile, {(5005, col): f32(raw)})
                    with self.assertRaises(self.c.Refusal):
                        self.c.lattice_sample({tile: p}, i, 5335000)


if __name__ == '__main__':
    unittest.main()
