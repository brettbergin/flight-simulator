"""Original MIT independent analytic fixture generator. No consumer or native imports."""
from decimal import Decimal, localcontext
from fractions import Fraction
from pathlib import Path
import hashlib
import json
import math
import struct

ROOT = Path(__file__).resolve().parents[3]
OUT = Path(__file__).resolve().parent
DEN = 4_000_000
INT64_MAX = 2**63 - 1
UINT64_MAX = 2**64 - 1
SCALES = [Fraction(1, 4), Fraction(1, 2), Fraction(1), Fraction(2), Fraction(4)]


def pacing(total_us, scale):
    # Closed-form elapsed physical simulation time, not a copied debit loop.
    exact_ticks = Fraction(total_us, 1_000_000) * 120 * scale
    ticks = exact_ticks.numerator // exact_ticks.denominator
    fractional = exact_ticks - ticks
    assert (fractional * DEN).denominator == 1
    return ticks, int(fractional * DEN)


def timestamps(name, duration):
    if name != 'jitter':
        rate = int(name)
        i = 1
        while True:
            value = min(duration, (i * 1_000_000) // rate)
            yield value
            if value == duration:
                return
            i += 1
    else:
        pattern = [1000, 5000, 17000, 33000, 50000, 0]
        elapsed = 0
        i = 0
        while elapsed < duration:
            elapsed = min(duration, elapsed + pattern[i % len(pattern)])
            yield elapsed
            i += 1


def wall_case(name, scale):
    # Every case ends at physical simulation time exactly 1s / tick120.
    duration = int(Fraction(1_000_000) / scale)
    previous_wall = previous_tick = 0
    rows = []
    original_walls = list(timestamps(name, duration))
    cuts_us = [duration * cut // 120 for cut in [30, 60, 90, 120]]
    walls = sorted(original_walls + [v for v in cuts_us if v not in original_walls])
    for wall in walls:
        tick, debt = pacing(wall, scale)
        elapsed = wall - previous_wall
        due = tick - previous_tick
        assert elapsed <= 250_000 and due * DEN + debt <= 30 * DEN
        rows.append(dict(wall_us=wall, elapsed_us=elapsed, completed_this_call=due,
                         completed_total=tick, debt_quanta=debt, declared_native_cut=tick in [30, 60, 90, 120] and debt == 0))
        previous_wall, previous_tick = wall, tick
    assert (previous_tick, rows[-1]['debt_quanta']) == (120, 0)
    cuts = []
    for cut in [30, 60, 90, 120]:
        index = next(i for i, row in enumerate(rows) if row['completed_total'] >= cut)
        row = rows[index]
        cuts.append(dict(completed_tick=cut, first_reaching_wall_row=index,
                         wall_us=row['wall_us'], call_final_tick=row['completed_total'],
                         split_at_native_tick=True))
    return dict(profile=name, scale=str(scale), duration_us=duration, rows=rows,
                common_native_cuts=cuts)


def dec(value):
    if isinstance(value, Fraction):
        return str(Decimal(value.numerator) / Decimal(value.denominator))
    return str(value)


def matvec(matrix, values):
    return [sum(a * b for a, b in zip(row, values)) for row in matrix]


def geometry():
    with localcontext() as ctx:
        ctx.prec = 80
        z, one, half = Decimal(0), Decimal(1), Decimal('0.5')
        rt2, rt3, rt6 = Decimal(2).sqrt(), Decimal(3).sqrt(), Decimal(6).sqrt()
        c30, s30 = rt3 / 2, half
        # latitude30deg, longitude60deg, rows East/Up/South in ECEF.
        matrix = [[-rt3 / 2, half, z], [rt3 / 4, Decimal('0.75'), half],
                  [Decimal('0.25'), rt3 / 4, -rt3 / 2]]
        transpose = [list(row) for row in zip(*matrix)]
        origin_a = [Decimal(1_000_000), Decimal(-2_000_000), Decimal(3_000_000)]
        local_a = [Decimal(64), Decimal(16), Decimal(-32)]
        origin_shift = [Decimal(128), Decimal(-8), Decimal(40)]
        ownship = [a + b for a, b in zip(origin_a, matvec(transpose, local_a))]
        origin_b = [a + b for a, b in zip(origin_a, matvec(transpose, origin_shift))]
        # body-to-NED roll30deg at anchor; FRD body axes, row-major anchor EUS.
        body = [[z, c30, -s30], [z, -s30, -c30], [-one, z, z]]
        camera_body = [Decimal('.3'), Decimal('-.2'), Decimal('.15')]
        camera_offset = matvec(body, camera_body)
        camera = [a + b for a, b in zip(ownship, matvec(transpose, camera_offset))]
        supplied = {name: [float(v) for v in values] for name, values in
                    [('origin_a_ecef_m', origin_a), ('origin_b_ecef_m', origin_b),
                     ('ownship_ecef_m', ownship), ('camera_ecef_m', camera)]}
        supplied['ecef_to_anchor_eus'] = [[float(v) for v in row] for row in matrix]
        # Exact rational expression on the actually supplied binary64 values.
        rmat = [[Fraction(v) for v in row] for row in supplied['ecef_to_anchor_eus']]
        expected = {}
        for label in ['origin_a_ecef_m', 'origin_b_ecef_m']:
            origin = [Fraction(v) for v in supplied[label]]
            for point in ['ownship_ecef_m', 'camera_ecef_m']:
                delta = [Fraction(p) - o for p, o in zip(supplied[point], origin)]
                exact = matvec(rmat, delta)
                expected[label + ':' + point] = dict(
                    exact_rationals=[str(x) for x in exact],
                    decimal_reference_m=[dec(x) for x in exact],
                    final_float32_hex=[struct.pack('>f', float(x)).hex() for x in exact],
                    final_float32_le=[struct.pack('<f', float(x)).hex() for x in exact],
                    final_float32_m=[struct.unpack('>f', struct.pack('>f', float(x)))[0] for x in exact])
        canonical_relative = matvec(rmat, [Fraction(c) - Fraction(p) for c, p in
                                zip(supplied['camera_ecef_m'], supplied['ownship_ecef_m'])])
        for label in ['origin_a_ecef_m', 'origin_b_ecef_m']:
            origin = [Fraction(v) for v in supplied[label]]
            camera_local = matvec(rmat, [Fraction(p)-o for p,o in zip(supplied['camera_ecef_m'],origin)])
            ownship_local = matvec(rmat, [Fraction(p)-o for p,o in zip(supplied['ownship_ecef_m'],origin)])
            assert [c-p for c,p in zip(camera_local,ownship_local)] == canonical_relative
        # Raw body-to-current-NED identity at two current latitudes is NOT a
        # common-frame identity. Converting first gives a 30deg frame rotation.
        s15, c15 = (rt6 - rt2) / 4, (rt6 + rt2) / 4
        endpoint_anchor = [[z, one, z], [z, z, -one], [-one, z, z]]
        endpoint_lat60 = [[z, one, z], [-half, z, -rt3 / 2], [-rt3 / 2, z, half]]
        midpoint = [[z, one, z], [-s15, z, -c15], [-c15, z, s15]]
        return dict(assumption='Analytic fixed basis latitude30deg longitude60deg; arbitrary canonical ECEF origin, not geographic/native fixture substitution.',
                    supplied_binary64=supplied,
                    supplied_binary64_le={name: ([struct.pack('<d', v).hex() for row in values for v in row] if name == 'ecef_to_anchor_eus' else [struct.pack('<d',v).hex() for v in values]) for name,values in supplied.items()},
                    ideal_ownship_eus_at_a_m=[64, 16, -32],
                    ideal_ownship_eus_at_b_m=[-64, 24, -72],
                    exact_supplied_value_expectations=expected,
                    invariant_camera_minus_ownship_m=[dec(x) for x in canonical_relative],
                    invariant_scope='The exact rational relative position is independent of render origin; float32 presentation may round only after canonical subtraction/rotation.',
                    near_camera_body_offset_m=[str(x) for x in camera_body],
                    body_roll30_quaternion_wxyz=[str(c15), str(s15), '0', '0'],
                    body_to_anchor_eus_roll30=[[str(v) for v in row] for row in body],
                    frame_change=dict(raw_body_to_current_ned_at_both_endpoints=[1, 0, 0, 0],
                        current_latitudes_deg=[30, 60], longitude_deg=60, anchor_latitude_deg=30,
                        endpoint_common_bases=[[[str(v) for v in row] for row in m]
                                                for m in [endpoint_anchor, endpoint_lat60]],
                        shortest_arc_midpoint_common_basis=[[str(v) for v in row] for row in midpoint],
                        negative='Blending the equal raw NED quaternions before converting frames cannot produce this common-frame midpoint.'))


def main():
    scales = [dict(scale=str(s), exact_quanta_multiplier=int(s * 4)) for s in SCALES]
    transitions = [dict(operation='advance', elapsed_us=4000, scale='1', completed_total=0, debt_quanta=1920000),
                  dict(operation='pause', native_tick='0', debt_quanta=1920000),
                  dict(operation='paused_wall_excluded', elapsed_us=10000000, native_tick='0', debt_quanta=1920000),
                  dict(operation='scale_while_paused', scale='2', native_tick='0', debt_quanta=1920000),
                  dict(operation='resume', native_tick='0', debt_quanta=1920000),
                  dict(operation='advance', elapsed_us=3000, scale='2', completed_total=1, debt_quanta=800000),
                  dict(operation='settled_scale_change', scale='1/4', native_tick='1', debt_quanta=800000),
                  dict(operation='advance', elapsed_us=10000, scale='1/4', completed_total=1, debt_quanta=2000000),
                  dict(operation='settled_scale_change', scale='4', native_tick='1', debt_quanta=2000000),
                  dict(operation='advance', elapsed_us=12500, scale='4', completed_total=7, debt_quanta=2000000)]
    total_ticks = Fraction(4000, 1_000_000)*120 + Fraction(3000, 1_000_000)*240 + Fraction(10000, 1_000_000)*30 + Fraction(12500, 1_000_000)*480
    assert total_ticks == Fraction(15, 2)
    boundaries = [
        dict(name='raw_gap_exact250ms', elapsed_us='250000', scale='1', initial_debt='0', expected='accepted', completed=30, debt='0'),
        dict(name='raw_gap250ms_plus1us_low_scale', elapsed_us='250001', scale='1/4', initial_debt='0', expected='stalled_before_admission_and_step', completed=0, debt='30000120'),
        dict(name='debt_exact30ticks_scale4', elapsed_us='62500', scale='4', initial_debt='0', expected='accepted', completed=30, debt='0'),
        dict(name='debt_30ticks_plus1quanta', elapsed_us='62500', scale='4', initial_debt='1', expected='stalled_before_admission_and_step', completed=0, debt='120000001', synthetic_internal_state=True),
        dict(name='reachable_debt_30ticks_plus120quanta', elapsed_us='62500', scale='4', initial_debt='120', expected='stalled_before_admission_and_step', completed=0, debt='120000120'),
        dict(name='negative_elapsed', elapsed_us='-1', scale='1', initial_debt='1920000', expected='argument_rejected_no_mutation', completed=0, debt='1920000'),
        dict(name='multiply_overflow', elapsed_us=str(INT64_MAX), scale='4', initial_debt='1920000', exact_unrepresentable_accrual=str(INT64_MAX*1920), expected='stalled_overflow_previous_representable_debt_retained', completed=0, debt='1920000'),
        dict(name='addition_overflow', elapsed_us='1', scale='1/4', initial_debt=str(INT64_MAX-119), exact_unrepresentable_sum=str(INT64_MAX+1), expected='stalled_overflow_previous_representable_debt_retained', completed=0, debt=str(INT64_MAX-119), synthetic_internal_state=True),
        dict(name='representable_large_product_is_stall_not_overflow', elapsed_us=str(INT64_MAX//1920), scale='4', initial_debt='0', expected='stalled_before_admission_and_step', completed=0, debt=str((INT64_MAX//1920)*1920))]
    values = [0, 2**53-1, 2**53, 2**53+1, 2**63-1, 2**63, UINT64_MAX-1, UINT64_MAX]
    uint = dict(values=[dict(value=str(v), valid=True, increment=str(v+1) if v<UINT64_MAX else None, increment_rejected=v==UINT64_MAX) for v in values],
                invalid=['', '-1', '+1', '01', '1.0', '1e3', ' 1', '1 ', str(UINT64_MAX+1)],
                comparisons=[dict(left=str(a), right=str(b), order=-1) for a,b in zip(values,values[1:])],
                differences=[dict(new=str(UINT64_MAX), old=str(UINT64_MAX-d), difference=d, small_difference_allowed=d<=32) for d in [0,1,32,33]],
                reversed_difference=dict(new='9223372036854775808', old='9223372036854775809', expected='reject_negative_difference'))
    references = ['docs/decisions/003-geodesy-and-render-origin.md', 'native/sim_core/contracts/include/flight/contracts/geodesy.hpp', 'tools/benchmark/geodesy/run.py']
    evidence = dict(schema_version=1, status='ORIGINAL_ANALYTIC_REFERENCE_NOT_A_NATIVE_TRACE_OR_PHASE_ACCEPTANCE',
                    reference_generator_sha256=hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
                    authoring_method='Python unbounded ints/Fraction closed-form totals; Decimal80 analytic radicals; exact rational operations on supplied binary64 geometry inputs.',
                    source_assumptions=dict(contract_head='fb026246a394d376449233729590e6c211091ef7', preconsumer_reference_sha256='336cc1d905e1b2ebbba3a7473b74e34df01bf75adb1176522bb8b75ccc1fea19', native_hz=120, quanta_per_tick=DEN,
                        original_native_model_and_world_unchanged=True, producer='Independent analytical generator imports no consumer and launches no app/native/benchmark process; original private reference predates the consumer.',
                        schedules='Floor absolute rational frame timestamps to integer microseconds; never round each delta independently.',
                        cuts='Original wall intervals are subdivided at declared native cuts30/60/90/120 so unchanged tick-stamped input/lifecycle schedules can be tested without adding a native API.',
                        boundary_priority='Combined raw-gap/debt/overflow cases require zero admission/solver calls; do not infer diagnostic precedence beyond explicit overflow disclosure.',
                        unreachable_one_quanta='Debt1 is an injected arithmetic-domain case: from reset and integral microseconds, normal debt is a multiple of120. It is not a claimed reachable caller trace.'),
                    references=[dict(path=p, actual_file_sha256=hashlib.sha256((ROOT/p).read_bytes()).hexdigest()) for p in references],
                    scales=scales, wall_profiles=[wall_case(name,s) for s in SCALES for name in ['30','60','144','240','jitter']],
                    lifecycle_transition=transitions, scheduling_boundaries=boundaries, uint64=uint, geometry=geometry())
    target=OUT/'independent-reference.json'
    target.write_text(json.dumps(evidence,indent=2)+'\n',encoding='utf-8')
    print(json.dumps(dict(reference_sha256=hashlib.sha256(target.read_bytes()).hexdigest(), profiles=len(evidence['wall_profiles']), boundaries=sum(len(p['rows']) for p in evidence['wall_profiles']), final_common_tick=120, file_bytes=target.stat().st_size)))


if __name__ == '__main__':
    main()
