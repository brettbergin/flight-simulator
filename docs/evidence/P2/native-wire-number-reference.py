"""MIT. Independent decimal -> IEEE754 binary64 oracle for issue205.

Only exact integer/Fraction arithmetic is used to select expected IEEE bits.
No float(), Decimal-to-float, Godot, native helper or candidate implementation.
Run with --check for read-only regeneration; default writes adjacent fixture.
"""
from fractions import Fraction
from pathlib import Path
import argparse
import json
import re

GRAMMAR = re.compile(r"-?(0|[1-9][0-9]*)(\.[0-9]+)?([eE][+-]?[0-9]+)?", re.ASCII)
MAX_FINITE = 0x7fefffffffffffff
SIGN = 1 << 63


def represented(bits):
    """Nonnegative finite IEEE encoding as an exact rational."""
    exponent, mantissa = bits >> 52, bits & ((1 << 52) - 1)
    if exponent == 0:
        return Fraction(mantissa, 1 << 1074)
    significand = (1 << 52) + mantissa
    shift = exponent - 1023 - 52
    return Fraction(significand << shift) if shift >= 0 else Fraction(significand, 1 << -shift)


def decimal_token(value):
    """Exact terminating decimal for rational dyadic midpoint inputs."""
    negative = value < 0
    value = abs(value)
    denominator = value.denominator
    power = denominator.bit_length() - 1
    assert denominator == 1 << power
    digits = str(value.numerator * 5 ** power)
    if power:
        digits = digits.zfill(power + 1)
        digits = digits[:-power] + "." + digits[-power:]
    return ("-" if negative else "") + digits


def exact_decimal(token):
    negative = token.startswith("-")
    unsigned = token[1:] if negative else token
    mantissa, *exponent = re.split("[eE]", unsigned)
    whole, dot, tail = mantissa.partition(".")
    coefficient = int(whole + tail)
    power = (int(exponent[0]) if exponent else 0) - len(tail)
    value = Fraction(coefficient * 10 ** power) if power >= 0 else Fraction(coefficient, 10 ** -power)
    return negative, value


def expected(token):
    if len(token) > 2048 or GRAMMAR.fullmatch(token) is None:
        return {"ok": False, "category": "grammar_or_bound", "le_hex": None}
    negative, value = exact_decimal(token)
    if value == 0:
        bits = SIGN if negative else 0
    else:
        # At this exact midpoint, ties-to-even overflows to the hypothetical
        # even 2**1024 significand, hence infinity and explicit rejection.
        overflow_midpoint = represented(MAX_FINITE) + Fraction(1 << 970)
        if value >= overflow_midpoint:
            return {"ok": False, "category": "overflow", "le_hex": None}
        low, high = 0, MAX_FINITE
        while low < high:
            middle = (low + high + 1) // 2
            if represented(middle) <= value:
                low = middle
            else:
                high = middle - 1
        bits = low
        if low != MAX_FINITE:
            lower_distance = value - represented(low)
            upper_distance = represented(low + 1) - value
            if upper_distance < lower_distance or (upper_distance == lower_distance and low & 1):
                bits += 1
        if bits == 0:
            return {"ok": False, "category": "nonzero_underflow_to_zero", "le_hex": None}
        if negative:
            bits |= SIGN
    return {"ok": True, "category": "finite_binary64", "le_hex": bits.to_bytes(8, "little").hex()}


def make_fixture():
    authored = [
        ("reported", "0.059999999999999998"), ("short_equivalent", "0.06"),
        ("reported_negative", "-0.059999999999999998"),
        ("lower_neighbor_text", "0.059999999999999991"),
        ("upper_neighbor_text", "0.060000000000000005"),
        ("scientific_equivalent", "5.9999999999999998e-2"),
        ("zero", "0"), ("negative_zero", "-0"),
        ("negative_fraction_zero", "-0.0"), ("negative_exponent_zero", "-0e-300"),
        ("positive_exponent_zero", "0e+300"),
        ("one", "1"), ("negative_one", "-1"), ("tenth", "0.1"),
        ("integer_inexact", "9007199254740993"),
        ("max_finite_17", "1.7976931348623157e308"),
        ("min_normal_17", "2.2250738585072014e-308"),
        ("max_subnormal_17", "2.2250738585072009e-308"),
        ("min_subnormal_17", "4.9406564584124654e-324"),
        ("negative_min_subnormal", "-4.9406564584124654e-324"),
        ("overflow", "1e309"), ("negative_overflow", "-1e309"),
        ("underflow", "1e-400"), ("negative_underflow", "-1e-400"),
    ]
    midpoint_pairs = [
        ("normal_even", 0x3ff0000000000000),
        ("normal_odd", 0x3ff0000000000001),
        ("subnormal_even", 2), ("subnormal_odd", 1),
        ("normal_boundary", 0x000fffffffffffff), ("zero_boundary", 0),
    ]
    for label, lower in midpoint_pairs:
        midpoint = (represented(lower) + represented(lower + 1)) / 2
        authored.append((label + "_tie", decimal_token(midpoint)))
        authored.append((label + "_negative_tie", decimal_token(-midpoint)))
    # Exact sides of the zero midpoint, not decimal float approximations.
    authored += [("zero_tie_below", decimal_token(Fraction(1, 1 << 1076))),
                 ("zero_tie_above", decimal_token(Fraction(3, 1 << 1076))),
                 ("overflow_exact_tie", str((1 << 1024) - (1 << 970)))]
    authored += [("bad_" + str(i), token) for i, token in enumerate(
        ["+1", "01", ".1", "1.", "1e", "NaN", "0x1", "1 ", "1\n", "--1"])]
    cases = [{"id": label, "token": token, **expected(token)} for label, token in authored]
    # Independently known integer encodings anchor endian/order and key cases.
    lookup = {item["id"]: item for item in cases}
    assert lookup["reported"]["le_hex"] == "b81e85eb51b8ae3f"
    assert lookup["short_equivalent"]["le_hex"] == lookup["reported"]["le_hex"]
    assert lookup["one"]["le_hex"] == "000000000000f03f"
    assert lookup["negative_zero"]["le_hex"] == "0000000000000080"
    assert lookup["min_subnormal_17"]["le_hex"] == "0100000000000000"
    assert lookup["zero_boundary_tie"]["category"] == "nonzero_underflow_to_zero"
    assert lookup["normal_even_tie"]["le_hex"] == "000000000000f03f"
    assert lookup["normal_odd_tie"]["le_hex"] == "020000000000f03f"
    return {"format": "NativeWireBinary64Reference/v1", "issue": 205,
            "oracle": "Exact decimal Fraction, ordered finite IEEE integer search, nearest ties-even",
            "candidate_outputs_consumed": False, "cases": cases}


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    target = Path(__file__).with_suffix(".json")
    generated = (json.dumps(make_fixture(), indent=2, ensure_ascii=True) + "\n").encode("utf-8")
    if args.check:
        assert target.read_bytes() == generated, "Frozen fixture differs; do not overwrite after observations"
    else:
        assert not target.exists(), "Refuse to replace an existing frozen fixture; use --check"
        target.write_bytes(generated)
    print("reference cases:", len(make_fixture()["cases"]), "check" if args.check else "generated")
