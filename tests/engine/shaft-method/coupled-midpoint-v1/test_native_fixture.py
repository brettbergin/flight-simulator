"""Prospective independent arithmetic checks; not run at source freeze."""
import unittest
import json
import sys
from fractions import Fraction as Q
from exact import IV, from_bits, MAX_BITS
from generate import (FP, Model, fixed_step, canonical, encode,
                      dyadic_refinement_state, MAX_SERIALIZED_DIGITS)
from native_fixture import scalar_type, selected_bits


class NativeRealizationChecks(unittest.TestCase):
    def test_refinement_seam_preserves_containment_and_dyadic_capacity(self):
        state = IV(Q(1, 3), Q(2, 3))
        for _ in range(32):
            # Rational updates deliberately introduce fresh non-dyadic factors.
            raw = IV((state.lo+1)/3, (state.hi+2)/3)
            state = dyadic_refinement_state(raw)
            self.assertLessEqual(state.lo, raw.lo)
            self.assertGreaterEqual(state.hi, raw.hi)
            for x in (state.lo, state.hi):
                d = x.denominator
                self.assertEqual(d & (d-1), 0)
                self.assertLessEqual(d.bit_length(), 385)
            self.assertLessEqual(state.width-raw.width, Q(2, 2**384))

    def test_serialization_keeps_a_finite_sufficient_decimal_guard(self):
        previous = sys.get_int_max_str_digits()
        try:
            sys.set_int_max_str_digits(4300)
            large = 1 << 20000  # Admitted bits; exceeds the default decimal cap.
            data = canonical({"integer": large, "rational": Q(large, 3)})
            decoded = json.loads(data)
            self.assertEqual(decoded["integer"], large)
            self.assertEqual(Q(decoded["rational"]), Q(large, 3))
            self.assertEqual(sys.get_int_max_str_digits(), MAX_SERIALIZED_DIGITS)
            self.assertGreater(MAX_SERIALIZED_DIGITS, 0)
        finally:
            sys.set_int_max_str_digits(previous)

    def test_serialization_rejects_values_above_existing_bit_ceiling(self):
        for value in (Q(1 << MAX_BITS), Q(1, 1 << MAX_BITS), 1 << MAX_BITS):
            with self.assertRaisesRegex(ArithmeticError, "rational bit ceiling"):
                encode(value)

    def test_exact_XML_CP_identity_is_not_loaded_constant_identity(self):
        self.assertEqual(Q("0.06")-3*Q("0.02"), 0)
        self.assertNotEqual(FP.constant("0.06").value-3*FP.constant("0.02").value, 0)

    def test_rounding_occurs_between_operations(self):
        S = scalar_type(FP)
        result = (S(1)+S(Q(1, 2**53)))-S(1)
        self.assertEqual(result.r, 0)
        self.assertEqual(result.audit.value, Q(1, 2**53))
        self.assertTrue(result.audit.enclosure.lo <= result.r <= result.audit.enclosure.hi)

    def test_absolute_cancellation_interval(self):
        S = scalar_type(FP)
        result = (S(2**40)+S(Q(1, 2**20)))-S(2**40)
        self.assertEqual(result.r, 0)
        self.assertEqual(result.audit.value, Q(1, 2**20))
        self.assertTrue(result.audit.enclosure.lo <= 0 <= result.audit.enclosure.hi)

    def test_table_key_uncertainty_includes_both_branches(self):
        model = Model.__new__(Model)
        model.table = [(FP(0), FP(0)), (FP(1), FP(1)), (FP(2), FP(0))]
        key = FP(1, IV(1-Q(1, 2**20), 1+Q(1, 2**20)))
        result = model.mixture(key)
        self.assertEqual(result.value, 1)
        self.assertTrue(result.enclosure.lo <= 1-Q(1, 2**20))
        self.assertTrue(result.enclosure.hi >= 1)

    def test_native_root_selection_and_domain_neighbors(self):
        result = fixed_step(1, 1, Q(1, 8), (0, -2, 0, 0))
        self.assertEqual(selected_bits(result), "3fe8000000000000")
        self.assertEqual(from_bits(0x3c30000000000000), Q(1, 2**60))
        self.assertLess(from_bits(0x3c2fffffffffffff), Q(1, 2**60))
        self.assertEqual(from_bits(0x43c0000000000000), Q(2**61))
        self.assertLess(from_bits(0x43bfffffffffffff), Q(2**61))


if __name__ == "__main__":
    unittest.main()
