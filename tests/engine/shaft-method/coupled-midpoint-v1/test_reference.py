"""Focused prospective mathematical self-checks. Not executed at source freeze."""
import unittest
from fractions import Fraction as Q

from exact import (IV, RF, add, mul, quotient, derivative, evaluate, isolate,
                   multiplicity, sturm, open_count, sign_on, binary64_bits,
                   from_bits, rn, simpson, verified_time, bernstein, binary64_floor_bits, floor_cell)
from generate import fixed_step, midpoint_polynomial, B_polynomial


class PolynomialChecks(unittest.TestCase):
    def test_euclidean_and_repeated_roots(self):
        p = mul(mul((-1, 1), (-1, 1)), (2, 1))
        roots = isolate(p)
        self.assertEqual(len(roots), 2)
        self.assertEqual([multiplicity(p, r) for r in roots], [1, 2])
        self.assertEqual(quotient(p, (-1, 1)), mul((-1, 1), (2, 1)))

    def test_sturm_open_endpoint_count(self):
        p = mul((-1, 1), (0, 1))
        self.assertEqual(open_count(p, sturm(p), Q(0), Q(1)), 0)
        self.assertEqual(open_count(p, sturm(p), Q(-1), Q(1)), 1)
        self.assertEqual(open_count(p, sturm(p), Q(-1), Q(2)), 2)

    def test_no_spurious_rest_root(self):
        p = midpoint_polynomial(Q(1), Q(0), Q(1, 8), (0, 2, 0, 0))
        self.assertNotEqual(evaluate(p, 0), 0)
        self.assertEqual(evaluate(p, Q(1, 4)), 0)

    def test_sign_certificate_is_not_endpoint_sampling(self):
        p = (Q(1, 8), Q(-1), Q(1))
        self.assertFalse(sign_on(p, Q(0), Q(1), 1))

    def test_effective_degree_and_hold(self):
        self.assertEqual(isolate((2,)), [])
        self.assertEqual(isolate(()), [])
        self.assertEqual(fixed_step(1, 1, Q(1, 8), (0, 0, 0, 0))["status"], "hold")

    def test_torque_and_loss_limits(self):
        self.assertEqual(fixed_step(1, 1, Q(1, 8), (0, -2, 0, 0))["final"], IV.point(Q(3, 4)))
        p = midpoint_polynomial(Q(2), Q(3), Q(1, 4), (-2, 0, 0, 0))
        self.assertEqual(evaluate(p, 0), Q(-17, 2))

    def test_finite_stop_vs_drag_equilibrium(self):
        self.assertEqual(fixed_step(1, 1, Q(1, 2), (0, -2, 0, 0))["status"], "stop")
        self.assertEqual(fixed_step(1, 2, 2, (0, 0, -1, 0))["status"], "reject")
        self.assertEqual(fixed_step(1, 2, 2, (0, 0, 0, -1))["status"], "reject")

    def test_multiple_root_branch_is_rejected(self):
        result = fixed_step(1, Q(1, 4), Q(21, 500), (-1, 2, 0, 0))
        self.assertEqual(result["status"], "reject")
        self.assertIn("monotone", result["reason"])

    def test_B_identity(self):
        w0, x, c = Q(3), Q(2), (Q(-1), Q(4), Q(-2), Q(-1))
        m = (w0+x)/2
        T = c[0]/m+c[1]+c[2]*m+c[3]*m*m
        Tp = -c[0]/(m*m)+c[2]+2*c[3]*m
        self.assertEqual(evaluate(B_polynomial(w0, c), x), m*m*(T-(x-w0)*Tp/2))


class RoundingChecks(unittest.TestCase):
    def test_floor_is_distinct_from_nearest(self):
        q = Q(1)+Q(3, 2**54)
        self.assertEqual(binary64_floor_bits(q), 0x3ff0000000000000)
        self.assertEqual(binary64_bits(q), 0x3ff0000000000001)
        self.assertEqual(binary64_floor_bits(-q), 0xbff0000000000001)
        root = IV(Q(1)-Q(1, 2**80), Q(1)+Q(1, 2**80))
        self.assertEqual(floor_cell(root, (-1, 1))["bits"], "3ff0000000000000")

    def test_nearest_even_and_subnormal(self):
        self.assertEqual(binary64_bits(Q(1)+Q(1, 2**53)), 0x3ff0000000000000)
        self.assertEqual(binary64_bits(Q(1)+Q(3, 2**53)), 0x3ff0000000000002)
        self.assertEqual(binary64_bits(Q(1, 2**1075)), 0)
        self.assertEqual(binary64_bits(Q(3, 2**1075)), 2)
        self.assertEqual(binary64_bits(Q(0), True), 0x8000000000000000)

    def test_boundary_and_sign_roundtrip(self):
        for bits in (0, 1, 0x000fffffffffffff, 0x0010000000000000,
                     0x3ff0000000000000, 0x400921fb54442d18, 0x7fefffffffffffff,
                     0xbff0000000000000):
            self.assertEqual(binary64_bits(from_bits(bits)), bits)
        self.assertEqual(rn(Q("3.14159265358979323846")), from_bits(0x400921fb54442d18))


class QuadratureChecks(unittest.TestCase):
    def test_symbolic_derivative(self):
        g = RF((1,), (1, 1))
        self.assertEqual(g.derivative().value(Q(1)), Q(-1, 4))

    def test_polynomial_integral_enclosure(self):
        g = RF((0, 0, 1), (1,))
        out = verified_time(g, Q(0), Q(1), Q(1, 2**40))
        self.assertTrue(out.lo <= Q(1, 3) <= out.hi)
        self.assertTrue((-out).intersects(verified_time(g, Q(1), Q(0), Q(1, 2**40))))

    def test_zero_denominator_fails(self):
        with self.assertRaises(ArithmeticError):
            RF((1,), (0, 1)).bounds(Q(-1), Q(1))

    def test_bernstein_encloses_interior_extremum(self):
        enclosure = bernstein((0, 1, -1), Q(0), Q(1))
        self.assertTrue(enclosure.lo <= Q(1, 4) <= enclosure.hi)


if __name__ == "__main__":
    unittest.main()
