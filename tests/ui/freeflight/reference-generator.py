"""Original fixed-anchor geometry references; no Godot, native code or solver.

Ranges are exact integer/rational choices. Bearings use independent 80-digit
Decimal atan series plus half-angle reduction, not a runtime atan2 call.
"""
from pathlib import Path
from decimal import Decimal as D, localcontext
from math import isqrt
import argparse, hashlib, json

HERE = Path(__file__).resolve().parent
PI = D('3.141592653589793238462643383279502884197169399375105820974944592307816406286208998628')
CASES = [
    ('coincident', (0, 0), (0, 0)),
    ('north', (0, 0), (0, -10)),
    ('east', (0, 0), (10, 0)),
    ('south', (0, 0), (0, 10)),
    ('west', (0, 0), (-10, 0)),
    ('northeast_345', (0, 0), (3, -4)),
    ('southeast_345', (0, 0), (3, 4)),
    ('southwest_345', (0, 0), (-3, 4)),
    ('northwest_345', (0, 0), (-3, -4)),
    ('noncardinal_5_12_13', (0, 0), (5, -12)),
    ('north_wrap_positive', (0, 0), (199, -19800)),
    ('north_wrap_negative', (0, 0), (-199, -19800)),
    ('negative_translated_345', (-4096, -2048), (-4093, -2052)),
    ('negative_west', (-500, -100), (-1500, -100)),
    ('large_finite_axis', (16384, 16384), (16384, -16384)),
    ('large_finite_345', (-16384, 16384), (-13384, 12384)),
]


def atan(value):
    if value < 0:
        return -atan(-value)
    if value > 1:
        return PI / 2 - atan(1 / value)
    scale = D(1)
    while value > D('.125'):
        value = value / (1 + (1 + value * value).sqrt())
        scale *= 2
    term, total, n = value, D(0), 0
    while True:
        contribution = term / (2 * n + 1)
        total += contribution
        if abs(contribution) < D('1e-82'):
            return total * scale
        term *= -value * value
        n += 1


def bearing(dx, dz):
    if dx == dz == 0:
        return None
    north = -D(dz)
    if north == 0:
        radians = PI / 2 if dx > 0 else -PI / 2
    else:
        radians = atan(D(dx) / north) + (PI if north < 0 else 0)
    degrees = ((radians + 2 * PI) % (2 * PI)) * 180 / PI
    return float(degrees)


def packet():
    with localcontext() as ctx:
        ctx.prec = 90
        rows = []
        for name, own, target in CASES:
            dx, dz = target[0] - own[0], target[1] - own[1]
            squared = dx * dx + dz * dz
            exact_range = isqrt(squared)
            assert exact_range * exact_range == squared
            assert max(map(abs, target)) <= 20000
            rows.append({'id': name,
                         'own': {'x': own[0], 'z': own[1]},
                         'target': {'x': target[0], 'z': target[1]},
                         'range_m': exact_range,
                         'bearing_deg': bearing(dx, dz)})
        assert [x['bearing_deg'] for x in rows[:5]] == [None, 0, 90, 180, 270]
        assert len({x['id'] for x in rows}) == 16
        return {'format': 'LandmarkGeometryReference/v1',
                'scope': 'Private source-only fixed-anchor x/z geometry; no physics coverage, aircraft admission, sensor, geodesic, operational or training claim',
                'authorship': 'Project-original coordinate cases and Decimal equations; MIT; no runtime or model output',
                'frame': 'Accepted fixed-anchor east/up/south; x east, z south; height excluded',
                'bearing_basis': 'Prepared-anchor north; atan2(target.x-own.x, -(target.z-own.z)); normalized [0,360); null at coincident points',
                'method': 'Exact integer Pythagorean ranges; Decimal90 context with 80-digit-or-better atan half-angle/Taylor evaluation and independent quadrant selection; JSON bearings rounded once to binary64',
                'tolerances_before_observation': {'range_abs_m': 1e-7, 'bearing_abs_deg': 1e-7, 'bearing_comparison': 'shortest wrapped angular difference', 'zero_range': 'exact null bearing'},
                'integration_tolerance_basis': 'Consistent copied ECEF/geodetic Readback reconstruction can introduce small fixed-anchor cancellation; no output fitting',
                'case_count': len(rows), 'cases': rows}


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--check', action='store_true')
    parser.add_argument('--output', type=Path, default=HERE/'reference.json')
    args = parser.parse_args()
    value = packet()
    data = (json.dumps(value, indent=2) + '\n').encode('utf-8')
    if args.check:
        if args.output.read_bytes() != data:
            raise SystemExit('Landmark reference drift; preserve frozen cases and budgets')
    else:
        if args.output.exists():
            raise SystemExit('Refuse overwrite; use --check or a reviewed version')
        args.output.write_bytes(data)
    print(json.dumps({'cases': value['case_count'], 'sha256': hashlib.sha256(data).hexdigest(), 'runtime_or_solver_executed': False}))
