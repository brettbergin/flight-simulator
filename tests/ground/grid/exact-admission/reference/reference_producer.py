"""Independent exact dyadic admission witnesses; SOURCE ONLY before Root execution.

Two hand-derived planes and one extrema identity, not a grid/provider algorithm.
Only standard-library Fraction/struct arithmetic; no production imports or writes.
"""
from fractions import Fraction as F
import hashlib
import json
from pathlib import Path
import struct
import sys

MAX_CHECK_BYTES = 1048576


def raw_f32_value(word):
    # Every finite binary32 is exactly representable by Python's binary64 float.
    return F.from_float(struct.unpack("<f", struct.pack("<I", word))[0])


def raw_f32_word(exact_integer):
    # Only the explicitly bounded multiples of4 from0..2044 use this path.
    if not (0 <= exact_integer <= 2044 and exact_integer % 4 == 0):
        raise ValueError("outside fixed integer height construction")
    word = struct.unpack("<I", struct.pack("<f", exact_integer))[0]
    if raw_f32_value(word) != exact_integer:
        raise AssertionError("integer height was not exactly represented")
    return word


def rational(value):
    value = F(value)
    return {"numerator":str(value.numerator),"denominator":str(value.denominator)}


def make_artifact():
    epsilon = F(1, 1 << 149)
    negative_epsilon = raw_f32_value(0x80000001)
    thirty_two = raw_f32_value(0x42000000)
    maximum = raw_f32_value(0x44FFFF00)
    if negative_epsilon != -epsilon or thirty_two != 32 or maximum != 2048-F(1,32):
        raise AssertionError("raw Float32 premise differs from hand oracle")
    # These are the two explicitly hand-derived facet coefficient pairs.
    p0, q0 = thirty_two/2, -negative_epsilon/2
    p1, q1 = (thirty_two-negative_epsilon)/2, F(0)
    norm0, norm1 = p0*p0+q0*q0, p1*p1+q1*q1
    if norm0-256 != F(1,1<<300):
        raise AssertionError("triangle0 exact excess proof mismatch")
    if norm1-256 != F(1,1<<145)+F(1,1<<300):
        raise AssertionError("triangle1 exact excess proof mismatch")
    control_span = maximum + F(1,32)
    forbidden_span = maximum-negative_epsilon+F(1,32)
    first_gradient = (F(4)-negative_epsilon)/4
    last_gradient = (maximum-2044)/4
    if control_span != 2048 or forbidden_span != 2048+epsilon:
        raise AssertionError("span equality/excess proof mismatch")
    if first_gradient != 1+F(1,1<<151) or last_gradient != F(127,128):
        raise AssertionError("span-case gradients mismatch")
    if not first_gradient < 16:
        raise AssertionError("span case unexpectedly violates gradient bound")
    row = [raw_f32_word(4*i) for i in range(512)] + [0x44FFFF00]
    control_heights = row+row
    forbidden_heights = list(control_heights)
    forbidden_heights[0] = forbidden_heights[513] = 0x80000001
    validity = [0xFFFFFFFFFFFFFFFF]*16 + [3]
    if len(control_heights) != 1026 or sum(word.bit_count() for word in validity) != 1026:
        raise AssertionError("span vector/mask counts differ")
    source = Path(__file__)
    oracle = source.with_name("hand-oracles.json")
    return {
        "kind":"independent-exact-dyadic-admission-reference",
        "version":1,
        "producer_sha256":hashlib.sha256(source.read_bytes()).hexdigest(),
        "hand_oracles_sha256":hashlib.sha256(oracle.read_bytes()).hexdigest(),
        "epsilon":rational(epsilon),
        "gradient":{
            "control_words_hex":["00000000","42000000","00000000","42000000"],
            "control_admitted":True,"control_norm_squared":rational(256),
            "forbidden_words_hex":["80000001","42000000","00000000","42000000"],
            "forbidden_admitted":False,
            "triangle0":{"p":rational(p0),"q":rational(q0),
                         "norm_squared":rational(norm0),"excess":rational(norm0-256)},
            "triangle1":{"p":rational(p1),"q":rational(q1),
                         "norm_squared":rational(norm1),"excess":rational(norm1-256)}
        },
        "span":{
            "control_admitted":True,"forbidden_admitted":False,
            "control_span_m":rational(control_span),
            "forbidden_span_m":rational(forbidden_span),
            "forbidden_span_excess_m":rational(forbidden_span-2048),
            "first_forbidden_gradient":rational(first_gradient),
            "last_gradient":rational(last_gradient),
            "control_height_words_hex":[f"{word:08x}" for word in control_heights],
            "forbidden_height_words_hex":[f"{word:08x}" for word in forbidden_heights],
            "valid_words_hex":[f"{word:016x}" for word in validity],
            "control_anchor_up_m":rational(raw_f32_value(row[256])),
            "control_anchor_ellipsoid_height_m":rational(100+raw_f32_value(row[256]))
        },
        "scope":"exact mathematical admission only; no provider or geographic/runtime pass"
    }


def unique_object(pairs):
    result = {}
    for key,value in pairs:
        if key in result:
            raise ValueError("duplicate expected JSON key")
        result[key] = value
    return result


def reject_nonfinite(value):
    raise ValueError("nonfinite expected JSON constant: "+value)


def main():
    if len(sys.argv) == 1:
        print(json.dumps(make_artifact(),indent=2,sort_keys=True))
        return 0
    if len(sys.argv) != 3 or sys.argv[1] != "--check":
        print("usage: reference_producer.py [--check expected.json]",file=sys.stderr)
        return 2
    try:
        with Path(sys.argv[2]).open("rb") as source:
            data = source.read(MAX_CHECK_BYTES+1)
        if len(data)>MAX_CHECK_BYTES:
            raise ValueError("expected JSON exceeds1MiB")
        expected = json.loads(data.decode("utf-8"),object_pairs_hook=unique_object,
                              parse_constant=reject_nonfinite)
        if expected != make_artifact():
            print("exact-admission reference mismatch",file=sys.stderr)
            return 1
    except (OSError,UnicodeError,ValueError) as error:
        print("exact-admission reference check failed: "+str(error),file=sys.stderr)
        return 1
    print("exact-admission reference matches")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
