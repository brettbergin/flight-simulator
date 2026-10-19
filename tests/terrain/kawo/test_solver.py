"""Frozen scalar/control-flow maps; no claim these are real CRS/DEM fields."""
from array import array
import unittest

from _support import b64, compiler


class ScalarMap:
    def __init__(self, target):
        self.target = target
        self.calls = []

    def evaluate(self, ys):
        values = tuple(ys)
        self.calls.append(values)
        return {'h': array('d', values), 'H': array('d', (self.target(y) for y in values)),
                'N': array('d', [0.] * len(values)), 'c': array('d', [1.] * len(values))}


class SolverTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.c = compiler()

    def run_map(self, source):
        return self.c.solve_block(source, array('d', [0.]), array('d', [0.]))

    def test_stable_target_still_eight_plus_two_maps(self):
        source = ScalarMap(lambda _: 77.25)
        result = self.run_map(source)
        self.assertEqual(source.calls, [(0.,)] + [(77.25,)] * 9)
        self.assertEqual(list(result['words']), [0x429a8000])
        self.assertEqual(list(result['heights']), [77.25])
        self.assertEqual((result['max_pre'], result['max_delta'], result['max_post']), (0., 0., 0.))

    def test_inclusive_residual_and_last_delta(self):
        e = 2.**-12
        source = ScalarMap(lambda y: y + e)
        result = self.run_map(source)
        self.assertEqual(source.calls, [(i * e,) for i in range(8)] + [(8 * e,)] * 2)
        self.assertEqual(list(result['words']), [0x3b000000])
        self.assertEqual((result['max_pre'], result['max_delta'], result['max_post']), (e, e, e))

    def test_last_delta_refusal_separate_from_pre_residual(self):
        source = ScalarMap(lambda y: 1./16 + y/2)
        with self.assertRaises(self.c.Refusal):
            self.run_map(source)
        self.assertEqual(source.calls[:8], [(0.,), (1./16,), (3./32,), (7./64,),
                                           (15./128,), (31./256,), (63./512,), (127./1024,)])

    def test_pre_refusal_separate_from_inclusive_last_delta(self):
        source = ScalarMap(lambda y: 2.**-19 + 2*y)
        with self.assertRaises(self.c.Refusal):
            self.run_map(source)
        self.assertEqual(source.calls[:8], [(i / 2.**19,) for i in (0, 1, 3, 7, 15, 31, 63, 127)])

    def test_no_adaptive_extra_iterations(self):
        source = ScalarMap(lambda y: 1. + y/2)
        with self.assertRaises(self.c.Refusal):
            self.run_map(source)
        self.assertLessEqual(len(source.calls), 9)
        self.assertEqual(source.calls[:8], [(0.,), (1.,), (1.5,), (1.75,), (1.875,),
                                           (1.9375,), (1.96875,), (1.984375,)])

    def test_fresh_post_round_map_and_inclusive_bound(self):
        q = b64('3ff0000010000000')
        for rounded_target, passes in ((1. + 2.**-10, True), (1. + 2.**-9, False),
                                        (b64('3ff0040000000001'), False)):
            def table(y):
                if y == 0. or y == q:
                    return q
                if y == 1.:
                    return rounded_target
                raise AssertionError('unlisted synthetic map operand')
            with self.subTest(post_target=rounded_target):
                source = ScalarMap(table)
                if passes:
                    result = self.run_map(source)
                    self.assertEqual(list(result['words']), [0x3f800000])
                    self.assertEqual(result['max_post'], 2.**-10)
                else:
                    with self.assertRaises(self.c.Refusal):
                        self.run_map(source)
                self.assertEqual(source.calls, [(0.,)] + [(q,)] * 8 + [(1.,)])

    def test_nonfinite_at_fresh_post_is_not_cached_success(self):
        q = b64('3ff0000010000000')
        source = ScalarMap(lambda y: float('nan') if y == 1. else q)
        with self.assertRaises(self.c.Refusal):
            self.run_map(source)
        self.assertEqual(source.calls[-1], (1.,))

    def test_final_f32_range_inclusive_and_next_words(self):
        for target in (-1000., 4096.):
            with self.subTest(target=target):
                self.assertEqual(list(self.run_map(ScalarMap(lambda _, t=target: t))['heights']), [target])
        for target in (-1000.00006103515625, 4096.00048828125):
            with self.subTest(target=target):
                with self.assertRaises(self.c.Refusal):
                    self.run_map(ScalarMap(lambda _, t=target: t))

    def test_scalar_cone_equality_and_outward_neighbor(self):
        c = b64('3feffff583a53b8e')
        self.assertEqual(self.c.scalar_update(0., 0., 0., 0., c), 0.)
        with self.assertRaises(self.c.Refusal):
            self.c.scalar_update(0., 0., 0., 0., b64('3feffff583a53b8d'))


if __name__ == '__main__':
    unittest.main()
