"""Original MIT. Preconsumer IEEE-754 fixtures; no simulator/codec imports."""
from fractions import Fraction
from pathlib import Path
import hashlib
import json
import struct

def scaled(value, exponent):
    return value * (1 << exponent) if exponent >= 0 else value / (1 << -exponent)

def nearest_even(value):
    quotient, remainder = divmod(value.numerator, value.denominator)
    comparison = remainder * 2 - value.denominator
    return quotient + int(comparison > 0 or (comparison == 0 and quotient % 2 == 1))

def encode_fraction(value, negative_zero=False):
    sign = int(value < 0 or (value == 0 and negative_zero))
    value = abs(value)
    if value == 0:
        return sign << 63
    exponent = value.numerator.bit_length() - value.denominator.bit_length()
    if value < scaled(Fraction(1), exponent):
        exponent -= 1
    if exponent < -1022:
        significand = nearest_even(scaled(value, 1074))
        return (sign << 63) | significand
    significand = nearest_even(scaled(value, 52 - exponent))
    if significand == 1 << 53:
        significand >>= 1
        exponent += 1
    if exponent > 1023:
        return (sign << 63) | (0x7ff << 52)
    return (sign << 63) | ((exponent + 1023) << 52) | (significand - (1 << 52))

def decode_bits(bits):
    sign = -1 if bits >> 63 else 1
    exponent = (bits >> 52) & 0x7ff
    fraction = bits & ((1 << 52) - 1)
    if exponent == 0x7ff:
        return None
    mantissa = fraction if exponent == 0 else fraction + (1 << 52)
    return sign * scaled(Fraction(mantissa), -1074 if exponent == 0 else exponent - 1023 - 52)

MAX_FINITE = scaled(Fraction((1 << 53) - 1), 971)
finite_choices = [
    ('positive-zero', Fraction(0), False),
    ('negative-zero', Fraction(0), True),
    ('positive-one', Fraction(1), False),
    ('negative-one', Fraction(-1), False),
    ('one-half', Fraction(1, 2), False),
    ('rounded-one-third', Fraction(1, 3), False),
    ('rounded-one-tenth', Fraction(1, 10), False),
    ('positive-minimum-subnormal', scaled(Fraction(1), -1074), False),
    ('negative-minimum-subnormal', -scaled(Fraction(1), -1074), False),
    ('largest-subnormal', scaled(Fraction((1 << 52) - 1), -1074), False),
    ('minimum-normal', scaled(Fraction(1), -1022), False),
    ('positive-maximum-finite', MAX_FINITE, False),
    ('negative-maximum-finite', -MAX_FINITE, False),
    ('equator-ecef-representative', Fraction(6378137), False),
    ('polar-ecef-representative', Fraction('6356752.314245'), False),
    ('landmark-east-representative', Fraction(850), False),
    ('runway-south-representative', Fraction(-1700), False),
    ('tick-duration-representative-not-tick-identity', Fraction(1, 120), False),
    ('exact-two-to-53-scalar-not-tick', Fraction(1 << 53), False),
    ('two-to-53-plus-one-rounded-scalar-not-tick', Fraction((1 << 53) + 1), False),
]
nonfinite_choices = [
    ('positive-infinity', 0x7ff0000000000000),
    ('negative-infinity', 0xfff0000000000000),
    ('positive-quiet-nan', 0x7ff8000000000001),
    ('negative-quiet-nan', 0xfff8000000000001),
    ('positive-signaling-nan', 0x7ff0000000000001),
    ('negative-signaling-nan', 0xfff0000000000001),
]

def generate():
    cases = []
    for name, original, negative_zero in finite_choices:
        bits = encode_fraction(original, negative_zero)
        little = bits.to_bytes(8, 'little')
        decoded = decode_bits(bits)
        python_value = -0.0 if negative_zero else float(original)
        assert struct.pack('<d', python_value) == little, name
        assert Fraction.from_float(struct.unpack('<d', little)[0]) == decoded, name
        assert encode_fraction(decoded, negative_zero) == bits, name
        cases.append({
            'name': name,
            'input_rational': {'numerator': str(original.numerator), 'denominator': str(original.denominator)},
            'negative_zero': negative_zero,
            'binary64_bits_hex': f'{bits:016x}',
            'binary64_le_hex': little.hex(),
            'exact_stored_rational': {'numerator': str(decoded.numerator), 'denominator': str(decoded.denominator)},
            'finite': True,
            'expected_bit_roundtrip': True,
        })
    for name, bits in nonfinite_choices:
        assert decode_bits(bits) is None
        cases.append({'name': name, 'binary64_bits_hex': f'{bits:016x}', 'binary64_le_hex': bits.to_bytes(8, 'little').hex(), 'finite': False, 'expected_finite_decoder_admission': False})
    return {
        'schema_version': 1,
        'status': 'independent-preconsumer-reference-proposed-awaiting-contract-review',
        'scope': 'Binary64 scalar representation only, not a recorded archive/schema/aircraft admission decision. All expected bits precede consumer observations. No size/depth/file/atomic limit ratification.',
        'oracle': 'Exact Fraction normalization and round-to-nearest-ties-even; independently cross-checked Python struct little-endian bytes and Fraction.from_float. No codec/simulator imports or outputs.',
        'budgets': {'bit_comparison': 'exact64-bit equality', 'little_endian_hex_comparison': 'exact16-lowercase-hex equality', 'tolerance': None},
        'case_count': len(cases), 'finite_cases': len(finite_choices), 'nonfinite_rejections': len(nonfinite_choices),
        'cases': cases,
    }

if __name__ == '__main__':
    output = Path(__file__).with_name('expected-binary64-v1.json')
    rendered = (json.dumps(generate(), indent=2) + '\n').encode('utf-8')
    if output.exists():
        assert output.read_bytes() == rendered, 'Preserve existing frozen packet; changed expectations require a separate version.'
    else:
        output.write_bytes(rendered)
    print(json.dumps({'path': str(output), 'sha256': hashlib.sha256(rendered).hexdigest(), 'case_count': 26, 'generator_sha256': hashlib.sha256(Path(__file__).read_bytes()).hexdigest()}, indent=2))
