"""Independent closed-form grid reference. SOURCE ONLY until Root executes it.

Python standard library only. No project imports, grid traversal, triangle search,
geodesy consumer calls, or floating-point trigonometry. Actual input doubles are
frozen by hex, then converted EXACTLY using Decimal.from_float. The interval
arithmetic encloses closed-form plane intersections and analytic WGS84 witnesses.
The generated JSON is a reference artifact, never production content.
"""
from decimal import Decimal, localcontext, ROUND_FLOOR, ROUND_CEILING
from math import factorial
import hashlib
import json
from pathlib import Path
import sys

PRECISION = 110
TERMS = 100
LONGITUDE_HEX = "0x1.0000000000000p-10"
LATITUDE_HEX = "0x1.921fb54442d18p-1"
MAX_RAY_HORIZONTAL_HEX = "0x1.0624dd2f1a9fcp-9"
MIN_RAY_UP_HEX = "0x1.ffff583a53b8ep-1"
MAX_CHECK_BYTES = 1048576


def rounded(op, direction):
    with localcontext() as ctx:
        ctx.prec = PRECISION
        ctx.rounding = direction
        return op()


class I:
    """Closed Decimal interval, outward-rounded at every arithmetic operation."""
    def __init__(self, low, high=None):
        self.lo = Decimal(low)
        self.hi = self.lo if high is None else Decimal(high)
        if self.lo > self.hi:
            raise ValueError("reversed interval")

    def __add__(self, other):
        other = interval(other)
        return I(rounded(lambda: self.lo + other.lo, ROUND_FLOOR),
                 rounded(lambda: self.hi + other.hi, ROUND_CEILING))

    __radd__ = __add__

    def __neg__(self):
        # copy_negate is exact, independent of the ambient Decimal context.
        return I(self.hi.copy_negate(), self.lo.copy_negate())

    def __sub__(self, other):
        return self + -interval(other)

    def __rsub__(self, other):
        return interval(other) + -self

    def __mul__(self, other):
        other = interval(other)
        pairs = [(a, b) for a in (self.lo, self.hi)
                 for b in (other.lo, other.hi)]
        return I(min(rounded(lambda a=a, b=b: a * b, ROUND_FLOOR)
                     for a, b in pairs),
                 max(rounded(lambda a=a, b=b: a * b, ROUND_CEILING)
                     for a, b in pairs))

    __rmul__ = __mul__

    def __truediv__(self, other):
        other = interval(other)
        if other.lo <= 0 <= other.hi:
            raise ValueError("interval divisor contains zero")
        reciprocal = I(rounded(lambda: Decimal(1) / other.hi, ROUND_FLOOR),
                       rounded(lambda: Decimal(1) / other.lo, ROUND_CEILING))
        return self * reciprocal

    def sqrt(self):
        if self.lo < 0:
            raise ValueError("negative sqrt")
        # Decimal.sqrt rounds correctly to nearest irrespective of rounding mode.
        # One adjacent value on each side therefore encloses each endpoint root.
        with localcontext() as ctx:
            ctx.prec = PRECISION
            return I(ctx.next_minus(self.lo.sqrt(context=ctx)),
                     ctx.next_plus(self.hi.sqrt(context=ctx)))

    def json(self):
        return {"lower": str(self.lo), "upper": str(self.hi)}


def interval(value):
    return value if isinstance(value, I) else I(value)


def sin_cos_exact_binary64(hex_operand):
    exact = Decimal.from_float(float.fromhex(hex_operand))
    if not -1 <= exact <= 1:
        raise ValueError("this bounded Taylor reference only admits |angle|<=1")
    x = I(exact)
    negative_x_squared = -(x * x)
    sin_term, cos_term = x, I(1)
    sine, cosine = sin_term, cos_term
    for n in range(1, TERMS):
        sin_term = sin_term * negative_x_squared / ((2*n)*(2*n+1))
        cos_term = cos_term * negative_x_squared / ((2*n-1)*(2*n))
        sine, cosine = sine + sin_term, cosine + cos_term
    # Taylor alternating remainder for |x|<=1 is <= 1/200! for both sums.
    # Interval roundoff was already enclosed at every step. This extra symmetric
    # tail bound needs no assumptions about dependency/cancellation in intervals.
    tail = I(1) / factorial(2 * TERMS)
    remainder = I(tail.hi.copy_negate(), tail.hi)
    return exact, sine + remainder, cosine + remainder


def vector_json(values):
    return [interval(x).json() for x in values]


def make_artifact():
    longitude, sine, cosine = sin_cos_exact_binary64(LONGITUDE_HEX)
    a = I(6378137)
    plane_cases = {}
    for name, p in (("flat", I(0)), ("east_slope_1_over_16", I(1)/16)):
        # Equatorial anchor EUS: X=(a+h)sin(lon), Y=(a+h)cos(lon)-a.
        # Plane Y=pX gives (a+h)(cos-p*sin)=a directly. No mesh query exists here.
        radius = a / (cosine - p*sine)
        norm = (1+p*p).sqrt()
        plane_cases[name] = {
            "ellipsoid_height_m": (radius-a).json(),
            "anchor_east_m": (radius*sine).json(),
            "anchor_south_m": I(0).json(),
            "normal_ned": vector_json((0, -(sine+p*cosine)/norm,
                                        (-cosine+p*sine)/norm)),
        }
    latitude, s45, c45 = sin_cos_exact_binary64(LATITUDE_HEX)
    f = I(1) / I("298.257223563")
    e2 = f*(2-f)
    prime_vertical = a / (1-e2*s45*s45).sqrt()
    radial_denominator = (c45*c45 + (1-e2)*(1-e2)*s45*s45).sqrt()
    radial_up = (c45*c45 + (1-e2)*s45*s45) / radial_denominator
    radial_south = e2*s45*c45 / radial_denominator
    normal = I(1) / I(3).sqrt()
    max_horizontal = I(Decimal.from_float(float.fromhex(MAX_RAY_HORIZONTAL_HEX)))
    min_up = I(Decimal.from_float(float.fromhex(MIN_RAY_UP_HEX)))
    min_derivative = min_up - 2*I(2).sqrt()*max_horizontal
    source_file = Path(__file__)
    oracle_file = source_file.with_name("source_oracles.json")
    artifact = {
        "kind": "independent-synthetic-reference-not-geographic-data",
        "version": 1,
        "producer_sha256": hashlib.sha256(source_file.read_bytes()).hexdigest(),
        "source_oracles_sha256": hashlib.sha256(oracle_file.read_bytes()).hexdigest(),
        "precision_decimal_digits": PRECISION,
        "taylor_terms": TERMS,
        "interval_meaning": "mathematical closed-form enclosure; excludes consumer conversion error",
        "off_anchor": {
            "latitude_rad_exact": "0",
            "longitude_binary64_hex": LONGITUDE_HEX,
            "longitude_rad_exact": str(longitude),
            "anchor_lat_lon_height": ["0", "0", "0"],
            "sin_longitude": sine.json(), "cos_longitude": cosine.json(),
            "cases": plane_cases,
        },
        "high_latitude": {
            "latitude_binary64_hex": LATITUDE_HEX,
            "latitude_rad_exact": str(latitude),
            "longitude_rad_exact": "0", "anchor_ellipsoid_height_m": "0",
            "sin_latitude": s45.json(), "cos_latitude": c45.json(),
            "ecef_anchor_m": vector_json((prime_vertical*c45, 0,
                                          prime_vertical*(1-e2)*s45)),
            "geodetic_up_ecef": vector_json((c45, 0, s45)),
            "geocentric_radial_anchor_eus": vector_json((0, radial_up, radial_south)),
            "correct_flat_Y10_surface_ellipsoid_height_m": I(10).json(),
            "correct_flat_Y10_normal_ned": vector_json((0, 0, -1)),
            "wrong_radial_flat_Y10_height_parameter_m": (I(10)/radial_up).json(),
            "wrong_radial_flat_Y10_south_displacement_m": (I(10)*radial_south/radial_up).json(),
        },
        "anchor_unit_normal_scalars": {
            "one_over_sqrt_two": (I(1)/I(2).sqrt()).json(),
            "one_over_sqrt_three": normal.json(),
        },
        "proof_bounds": {
            "max_ray_horizontal_binary64_hex": MAX_RAY_HORIZONTAL_HEX,
            "min_ray_up_binary64_hex": MIN_RAY_UP_HEX,
            "max_ray_horizontal_exact": str(max_horizontal.lo),
            "min_ray_up_exact": str(min_up.lo),
            "minimum_F_derivative": min_derivative.json(),
            "minimum_normal_dot_query_up": (min_derivative/I(5).sqrt()).json(),
            "maximum_bracket_horizontal_span_m": (I(2048)*max_horizontal/min_up).json(),
        },
    }
    return artifact


def unique_object(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise ValueError("duplicate expected JSON key")
        result[key] = value
    return result


def reject_nonfinite(value):
    raise ValueError("nonfinite expected JSON constant: " + value)


def main():
    if len(sys.argv) == 1:
        print(json.dumps(make_artifact(), indent=2, sort_keys=True))
        return 0
    if len(sys.argv) != 3 or sys.argv[1] != "--check":
        print("usage: reference_producer.py [--check expected.json]", file=sys.stderr)
        return 2
    try:
        with Path(sys.argv[2]).open("rb") as source:
            data = source.read(MAX_CHECK_BYTES + 1)
        if len(data) > MAX_CHECK_BYTES:
            raise ValueError("expected JSON exceeds 1 MiB limit")
        expected = json.loads(data.decode("utf-8"), object_pairs_hook=unique_object,
                              parse_constant=reject_nonfinite)
        if expected != make_artifact():
            print("reference JSON mismatch", file=sys.stderr)
            return 1
    except (OSError, UnicodeError, ValueError) as error:
        print("reference check failed: " + str(error), file=sys.stderr)
        return 1
    print("reference JSON matches")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
