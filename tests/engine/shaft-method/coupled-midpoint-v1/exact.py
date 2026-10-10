"""Independent rational polynomial and interval tools; no native imports.

Polynomial coefficients are ascending powers. Intervals are closed. All work
limits fail explicitly; none turns an uncertified value into an expectation.
"""
from dataclasses import dataclass
from fractions import Fraction as Q
from math import comb, isqrt

MAX_DEGREE = 32
MAX_BITS = 131072
MAX_ROOT_WORK = 16384
ROOT_BITS = (192, 384)


def checked(q):
    q = Q(q)
    if max(q.numerator.bit_length(), q.denominator.bit_length()) > MAX_BITS:
        raise ArithmeticError("reference rational bit ceiling")
    return q


def poly(p):
    p = tuple(checked(x) for x in p)
    while p and not p[-1]:
        p = p[:-1]
    if len(p) > MAX_DEGREE + 1:
        raise ArithmeticError("reference polynomial degree ceiling")
    return p


def add(a, b):
    return poly([(a[i] if i < len(a) else 0) +
                 (b[i] if i < len(b) else 0) for i in range(max(len(a), len(b)))])


def scale(p, k):
    return poly([x * k for x in p])


def mul(a, b):
    if not a or not b:
        return ()
    out = [Q(0)] * (len(a) + len(b) - 1)
    for i, x in enumerate(a):
        for j, y in enumerate(b):
            out[i+j] = checked(out[i+j] + x*y)
    return poly(out)


def derivative(p):
    return poly([i*p[i] for i in range(1, len(p))])


def evaluate(p, x):
    ans = Q(0)
    for a in reversed(p):
        ans = checked(ans*x + a)
    return ans


def compose_linear(p, offset, slope):
    ans = ()
    for a in reversed(p):
        ans = add(mul(ans, (offset, slope)), (a,))
    return ans


def divide(a, b):
    a, b = poly(a), poly(b)
    if not b:
        raise ZeroDivisionError("zero polynomial")
    out = [Q(0)] * max(0, len(a)-len(b)+1)
    rem = list(a)
    while rem and len(rem) >= len(b):
        shift = len(rem)-len(b)
        k = rem[-1]/b[-1]
        out[shift] = k
        for i, x in enumerate(b):
            rem[i+shift] = checked(rem[i+shift] - k*x)
        rem = list(poly(rem))
    return poly(out), poly(rem)


def gcd(a, b):
    a, b = poly(a), poly(b)
    while b:
        a, b = b, divide(a, b)[1]
    return scale(a, 1/a[-1]) if a else ()


def quotient(a, b):
    out, rem = divide(a, b)
    if rem:
        raise ArithmeticError("inexact polynomial quotient")
    return out


def square_free(p):
    p = poly(p)
    return quotient(p, gcd(p, derivative(p))) if len(p) > 1 else p


def sturm(p):
    p = square_free(p)
    if len(p) < 2:
        return (p,) if p else ()
    chain = [p, derivative(p)]
    while True:
        rem = scale(divide(chain[-2], chain[-1])[1], -1)
        if not rem:
            break
        # Positive rescaling only: a monic normalization can flip signs.
        chain.append(scale(rem, 1/abs(rem[-1])))
    return tuple(chain)


def variations(chain, x):
    signs = [1 if v > 0 else -1 for p in chain if (v := evaluate(p, x))]
    return sum(a != b for a, b in zip(signs, signs[1:]))


def open_count(p, chain, a, b):
    """Distinct roots strictly inside (a,b), including endpoint-root handling."""
    if a >= b or len(p) < 2:
        return 0
    return variations(chain, a)-variations(chain, b)-(evaluate(p, b) == 0)


@dataclass(frozen=True)
class IV:
    lo: Q
    hi: Q

    def __post_init__(self):
        object.__setattr__(self, "lo", checked(self.lo))
        object.__setattr__(self, "hi", checked(self.hi))
        if self.lo > self.hi:
            raise ArithmeticError("reversed interval")

    @staticmethod
    def point(q):
        return IV(Q(q), Q(q))

    def __add__(self, other):
        other = iv(other)
        return IV(self.lo+other.lo, self.hi+other.hi)

    __radd__ = __add__

    def __neg__(self):
        return IV(-self.hi, -self.lo)

    def __sub__(self, other):
        return self + -iv(other)

    def __rsub__(self, other):
        return iv(other) + -self

    def __mul__(self, other):
        other = iv(other)
        xs = [self.lo*other.lo, self.lo*other.hi,
              self.hi*other.lo, self.hi*other.hi]
        return IV(min(xs), max(xs))

    __rmul__ = __mul__

    def __truediv__(self, other):
        other = iv(other)
        if other.lo <= 0 <= other.hi:
            raise ArithmeticError("interval denominator includes zero")
        return self * IV(1/other.hi, 1/other.lo)

    def __rtruediv__(self, other):
        return iv(other) / self

    def __pow__(self, n):
        if n < 0:
            return 1/(self**(-n))
        ans = IV.point(1)
        base = self
        while n:
            if n & 1:
                ans = ans*base
            base = base*base
            n //= 2
        return ans

    @property
    def width(self):
        return self.hi-self.lo

    @property
    def midpoint(self):
        return (self.lo+self.hi)/2

    @property
    def magnitude(self):
        return max(abs(self.lo), abs(self.hi))

    def intersects(self, other):
        return self.lo <= other.hi and other.lo <= self.hi

    def intersection(self, other):
        return IV(max(self.lo, other.lo), min(self.hi, other.hi))


def iv(x):
    return x if isinstance(x, IV) else IV.point(x)


def bernstein(p, a, b):
    """Convex-hull enclosure on [a,b], not sample extrema."""
    p = compose_linear(poly(p), a, b-a)
    if not p:
        return IV.point(0)
    n = len(p)-1
    bs = [sum(p[i]*Q(comb(k, i), comb(n, i)) for i in range(k+1))
          for k in range(n+1)]
    return IV(min(bs), max(bs))


def sign_on(p, a, b, required):
    """Strict interior sign; exact endpoint zeros are permitted."""
    p = poly(p)
    if not p or a >= b:
        return False
    if open_count(p, sturm(p), a, b):
        return False
    return required*evaluate(p, (a+b)/2) > 0 and all(
        required*evaluate(p, x) >= 0 for x in (a, b))


def cauchy(p):
    p = poly(p)
    if len(p) < 2:
        return Q(0)
    return 1+max(abs(x/p[-1]) for x in p[:-1])


def isolate(p, bits=384):
    """All real roots, square-free Sturm isolation, deterministic finite work."""
    original = poly(p)
    p = square_free(original)
    if len(p) < 2:
        return []
    if len(p) == 2:
        return [IV.point(-p[0]/p[1])]
    if len(p) == 3:
        disc = p[1]**2-4*p[0]*p[2]
        if disc >= 0:
            sn, sd = isqrt(disc.numerator), isqrt(disc.denominator)
            if sn*sn == disc.numerator and sd*sd == disc.denominator:
                root = Q(sn, sd)
                return sorted({IV.point((-p[1]+sgn*root)/(2*p[2])) for sgn in (-1, 1)}, key=lambda x: x.lo)
    chain = sturm(p)
    bound = cauchy(p)
    # Strict Cauchy bound, hence neither endpoint is a root.
    todo = [(-bound, bound, open_count(p, chain, -bound, bound))]
    out, work = [], 0
    while todo:
        a, b, count = todo.pop()
        work += 1
        if work > MAX_ROOT_WORK:
            raise ArithmeticError("reference Sturm work ceiling")
        if not count:
            continue
        m = (a+b)/2
        if evaluate(p, m) == 0:
            out.append(IV.point(m))
            todo.extend([(m, b, open_count(p, chain, m, b)),
                         (a, m, open_count(p, chain, a, m))])
        elif count == 1 and b-a <= max(Q(1), min(abs(a), abs(b)))/2**bits:
            out.append(IV(a, b))
        else:
            left = open_count(p, chain, a, m)
            todo.extend([(m, b, count-left), (a, m, left)])
    return sorted(out, key=lambda x: x.lo)


def multiplicity(p, root):
    result = 0
    while len(p) > 1:
        present = (evaluate(p, root.lo) == 0 if not root.width else
                   open_count(p, sturm(p), root.lo, root.hi) == 1)
        if not present:
            break
        result += 1
        p = gcd(p, derivative(p))
    return result


def dyadic_enclose(q, bits=192):
    scale_ = 2**bits
    n, d = q.numerator*scale_, q.denominator
    floor = n//d
    return IV(Q(floor, scale_), Q(floor+(n % d != 0), scale_))


def round_even_ratio(n, d):
    a, r = divmod(n, d)
    return a + (2*r > d or (2*r == d and a & 1))


def binary64_bits(q, negative_zero=False):
    """Integer-only correct rational -> IEEE nearest/even conversion."""
    q = Q(q)
    sign = q < 0 or (q == 0 and negative_zero)
    q = abs(q)
    if not q:
        return int(sign) << 63
    e = q.numerator.bit_length()-q.denominator.bit_length()
    if q < Q(2)**e:
        e -= 1
    shift = 52-max(e, -1022)
    n, d = q.numerator, q.denominator
    if shift >= 0:
        n <<= shift
    else:
        d <<= -shift
    sig = round_even_ratio(n, d)
    if sig >= 2**53:
        sig //= 2
        e += 1
    if e > 1023:
        raise ArithmeticError("binary64 overflow")
    exp = 0 if sig < 2**52 else max(e, -1022)+1023
    frac = sig if not exp else sig-2**52
    return (int(sign) << 63) | (exp << 52) | frac


def from_bits(bits):
    sign, exp, frac = bits >> 63, (bits >> 52) & 2047, bits & (2**52-1)
    if exp == 2047:
        raise ValueError("nonfinite bit pattern")
    q = Q(frac, 2**1074) if exp == 0 else Q(2**52+frac)*Q(2)**(exp-1075)
    return -q if sign else q


def rn(q):
    return from_bits(binary64_bits(q))


def rounding_cell(root, p):
    a, b = binary64_bits(root.lo), binary64_bits(root.hi)
    if a == b:
        return {"bits": f"{a:016x}", "certificate": "entire root enclosure rounds identically"}
    # A rational root may itself be an exact rounding tie; integer RN proves it.
    if not root.width and evaluate(p, root.lo) == 0:
        return {"bits": f"{binary64_bits(root.lo):016x}", "certificate": "exact rational tie/even proof"}
    return {"interval_only": True, "reason": "rounding-cell boundary unresolved"}


def binary64_floor_bits(q):
    """Greatest finite binary64 <= rational q, independently of native solve."""
    bits = binary64_bits(q)
    if from_bits(bits) > q:
        bits += 1 if bits >> 63 else -1
    return bits


def floor_cell(root, p):
    a, b = binary64_floor_bits(root.lo), binary64_floor_bits(root.hi)
    if a == b:
        return {"bits": f"{a:016x}", "certificate": "whole root enclosure has same binary64 floor"}
    # An exactly representable algebraic root can straddle interval floors.
    # The unique-root enclosure plus exact polynomial zero proves this case.
    candidate = from_bits(b)
    if root.lo <= candidate <= root.hi and evaluate(p, candidate) == 0:
        return {"bits": f"{b:016x}", "certificate": "exact representable polynomial root"}
    return {"interval_only": True, "reason": "binary64 floor boundary unresolved"}


@dataclass(frozen=True)
class RF:
    numerator: tuple
    denominator: tuple

    def __post_init__(self):
        a, b = poly(self.numerator), poly(self.denominator)
        if not b:
            raise ZeroDivisionError("zero rational-function denominator")
        common = gcd(a, b)
        if common:
            a, b = quotient(a, common), quotient(b, common)
        object.__setattr__(self, "numerator", a)
        object.__setattr__(self, "denominator", b)

    def value(self, x):
        return checked(evaluate(self.numerator, x)/evaluate(self.denominator, x))

    def derivative(self):
        a, b = self.numerator, self.denominator
        return RF(add(mul(derivative(a), b), scale(mul(a, derivative(b)), -1)), mul(b, b))

    def bounds(self, a, b, subdivisions=16):
        lows, highs = [], []
        for i in range(subdivisions):
            left, right = a+(b-a)*i/subdivisions, a+(b-a)*(i+1)/subdivisions
            out = bernstein(self.numerator, left, right)/bernstein(self.denominator, left, right)
            lows.append(out.lo)
            highs.append(out.hi)
        return IV(min(lows), max(highs))


def time_function(I, c):
    return RF((I,), c[1:]) if c[0] == 0 else RF((0, I), c)


def torque_function(c, I=1):
    return RF(tuple(x/I for x in c[1:]), (1,)) if c[0] == 0 else RF(tuple(x/I for x in c), (0, 1))


def simpson(g, a, b, target):
    """Certified oriented integral; bounded dyadic sums prevent huge lcm growth."""
    if a == b:
        return IV.point(0)
    if target <= 0:
        raise ValueError("positive quadrature target required")
    if b < a:
        return -simpson(g, b, a, target)
    d4 = g
    for _ in range(4):
        d4 = d4.derivative()
    fourth = d4.bounds(a, b).magnitude
    n = 2
    while n <= 4096:
        step = (b-a)/n
        weighted = IV.point(0)
        for j in range(n+1):
            weight = 1 if j in (0, n) else (4 if j % 2 else 2)
            weighted += weight*dyadic_enclose(g.value(a+j*step))
        estimate = weighted*(step/3)
        error = (b-a)*step**4*fourth/180
        out = estimate+IV(-error, error)
        if out.width <= target:
            return out
        n *= 2
    raise ArithmeticError("4096-panel certified quadrature target unmet")


def verified_time(g, a, b, target):
    one = simpson(g, a, b, target)
    two = simpson(g, a, b, target/2)
    if not one.intersects(two):
        raise ArithmeticError("independent target refinement enclosures disjoint")
    return one.intersection(two)
