#!/usr/bin/env python3
"""Original MIT independent proposed steady-wind arithmetic, no consumer imports.
--write-new only creates a missing expected-v1.json; --check never writes it.
"""
from decimal import Decimal, localcontext
from fractions import Fraction
from pathlib import Path
import argparse
import hashlib
import json
import struct

HERE = Path(__file__).resolve().parent
PROPOSAL = {"commit":"ec9bcc5b513f83bb7cf383e7520408fbdd7e4535", "path":"docs/decisions/013-steady-wind-starts.md", "git_lf_sha256":"64548f1c876f77d635bd116710fcd5ca44d27e436b8b6b105d0c66406ea20e8f"}
DESIGNS = [
    {"name":"ground-reference-design-v1.md", "sha256":"16e02ab8276160dff4c6d22c7fc73e463096e5de95c0471e79fb456c5f20d043"},
    {"name":"ground-reference-design-v2.md", "sha256":"d9a3f4bc9fa71e0bca763905d2566d6c9dfbe67faf53a9eb3e125491549793de"},
]
F = Fraction
PROFILES = [("calm",[0,0,0],None), ("from-north",[-5,0,0],F(0)), ("from-west",[0,5,0],F(3,2)), ("from-east",[0,-5,0],F(1,2))]


def decimal(value):
    value = F(value)
    return Decimal(value.numerator) / Decimal(value.denominator)


def atan_inverse(integer):
    x = Decimal(1) / Decimal(integer)
    square = x*x
    total = Decimal(0)
    term = x
    index = 0
    while True:
        add = term / Decimal(2*index+1)
        updated = total + add
        if updated == total:
            return total
        total = updated
        term = -term*square
        index += 1
        assert index < 1000


def bits(value):
    return struct.pack('<d', float(value)).hex()


def rational(value):
    value = F(value)
    d = decimal(value)
    return {"fraction":str(value), "decimal":str(d), "binary64_le":bits(d)}


def norm_squared(vector):
    return sum((F(v)*F(v) for v in vector),F(0))


def norm(vector):
    squared = norm_squared(vector)
    d = decimal(squared).sqrt()
    return {"squared_fraction":str(squared), "decimal":str(d), "binary64_le":bits(d)}


def vector(values):
    return [rational(v) for v in values]


def angle(multiplier, pi):
    if multiplier is None:
        return None
    multiplier = F(multiplier)
    value = decimal(multiplier)*pi
    return {"pi_fraction":str(multiplier), "radians_decimal":str(value), "binary64_le":bits(value)}


def matrix(q):
    w,x,y,z = map(F,q)
    assert w*w+x*x+y*y+z*z == 1
    return [[1-2*(y*y+z*z), 2*(x*y-w*z), 2*(x*z+w*y)],
            [2*(x*y+w*z), 1-2*(x*x+z*z), 2*(y*z-w*x)],
            [2*(x*z-w*y), 2*(y*z+w*x), 1-2*(x*x+y*y)]]


def multiply(rotation,v):
    return [sum((F(rotation[i][j])*F(v[j]) for j in range(3)),F(0)) for i in range(3)]


def build():
    with localcontext() as context:
        context.prec = 110
        pi = 16*atan_inverse(5)-4*atan_inverse(239)
        assert str(pi).startswith('3.14159265358979323846264338327950288419716939937510')
        foot = F(381,1250)
        assert F(5)/foot == F(6250,381)
        assert F(5)*F(3600,1852) == F(4500,463)
        cases = []
        for name,wind,multiplier in PROFILES:
            n,e,d = wind
            cases.append({"id":"profile."+name, "kind":"profile", "profile":name,
                          "input_wind_toward_ned_mps":vector(wind), "expected_ftps":vector([F(v)/foot for v in wind]),
                          "expected_speed_mps":norm([n,e]), "expected_from_true_rad":angle(multiplier,pi),
                          "expected_toward_anchor_eus_mps":vector([e,-d,-n]), "expected_speed_kt":rational(F(5)*F(3600,1852) if name!='calm' else 0),
                          "calm":n==0 and e==0})
        small=F(1,2**600)
        subnormal=F(1,2**1074)
        tiny = [("signed-zero",[F(0),F(0),F(0)],None),
                ("tiny-south",[small,0,0],F(1)), ("tiny-north",[-small,0,0],F(0)),
                ("tiny-west",[0,small,0],F(3,2)), ("tiny-diagonal",[small,small,0],F(5,4)),
                ("min-subnormal-south",[subnormal,0,0],F(1))]
        for name,wind,multiplier in tiny:
            inp=vector(wind)
            if name=='signed-zero':
                inp[1]["binary64_le"]='0000000000000080'
                inp[1]["decimal"]='-0'
            speed=norm(wind[:2])
            assert name=='signed-zero' or float.fromhex('0x0.0000000000001p-1022') <= struct.unpack('<d',bytes.fromhex(speed['binary64_le']))[0]
            cases.append({"id":"direction."+name,"kind":"zero-or-tiny", "input_wind_toward_ned_mps":inp,
                          "expected_speed_mps":speed,"expected_from_true_rad":angle(multiplier,pi),
                          "expected_toward_anchor_eus_mps":vector([wind[1],-wind[2],-wind[0]]),
                          "calm":name=='signed-zero', "speed_comparison":"within4ulp-positive" if name=='tiny-diagonal' else 'exact-bits',
                          "input_zero_sign_copied":name=='signed-zero',"expected_projection_zero_sign":"either-zero-sign"})
        body_cases=[('identity',[1,0,0,0],[40,3,-2],[40,3,-2],[1613,2038,1608,1668]),
                    ('mixed',[F(1,3),F(2,3),F(2,3),0],[27,-9,18],[3,15,-30],[1134,1189,1009,1309]),
                    ('yaw',[F(3,5),0,0,F(4,5)],[25,0,5],[-7,24,5],[650,605,435,915])]
        for name,q,body,known_ground,known_squares in body_cases:
            rotation=matrix(q)
            ground=multiply(rotation,body)
            assert ground==list(map(F,known_ground))
            for profile_index,(profile,wind,_) in enumerate(PROFILES):
                air=[ground[i]-wind[i] for i in range(3)]
                assert norm_squared(air)==known_squares[profile_index]
                cases.append({"id":"air-relative."+name+'.'+profile, "kind":"air-relative", "profile":profile,
                              "input_body_to_ned_wxyz":vector(q), "input_ground_body_mps":vector(body),
                              "input_wind_toward_ned_mps":vector(wind),"input_turbulence_ned_mps":vector([0,0,0]),
                              "exact_rotation_rows":[[str(x) for x in row] for row in rotation],
                              "expected_ground_ned_mps":vector(ground), "expected_air_ned_mps":vector(air),
                              "expected_tas_mps":norm(air), "expected_ground_speed_mps":norm(ground[:2]),
                              "expected_vertical_speed_up_mps":rational(-ground[2])})
        runway=[]
        for name,wind,_ in PROFILES:
            n,e,_=wind
            for end in [36,18]:
                head,right=(-n,-e) if end==36 else (n,e)
                label='calm' if name=='calm' else 'headwind' if head>0 else 'tailwind' if head<0 else 'from right' if right>0 else 'from left'
                runway.append({"id":"runway."+str(end)+'.'+name,"profile":name,"runway":end,
                               "expected_headwind_mps":rational(head),"expected_wind_from_right_mps":rational(right),"expected_label":label,
                               "source_wind_unchanged":True})
        assert len(cases)==22 and len(runway)==8 and len(set(c['id'] for c in cases+runway))==30
        assert sum(c['kind']=='profile' for c in cases)==4
        assert sum(c['kind']=='zero-or-tiny' for c in cases)==6
        assert sum(c['kind']=='air-relative' for c in cases)==12
        return {"format":"PrivateSteadyWindReference","version":1,
                "status":"proposed-preconsumer-unratified-contract-unmerged","license":"MIT-original-test-material",
                "proposed_contract":PROPOSAL,"prior_designs":DESIGNS,
                "arithmetic":"Fraction exact rationals; Decimal110 sqrt and Machin rational atan series; struct little-endian binary64 targets. No consumer/native import/output.",
                "unit_definitions":{"foot_m":str(foot),"knots_per_mps":"900/463"},
                "pure_budgets":{"direct_si_roundtrip_abs_mps":"2e-14","direct_ftps_abs":"2e-13","ordinary_speed_components_abs_mps":"1e-12","circular_angle_abs_rad":"1e-12","air_relative_component_norm_abs_mps":"2e-12","tiny_diagonal_max_ulp":4,"tiny_cardinal_speed":"exact-bits-and-positive","tiny_calm_classification":"exact-no-absolute-tolerance"},
                "native_nominal_engineering_criterion":{"abs_per_ned_component_mps":"1e-6","scope":"NEW proposed engineering accuracy at actual RunIC/posttrim/every admitted completed state; not direct-unit/pure math tolerance or libm theorem; no native output observed; requires coordinator ratification/contract merge/dispatch"},
                "case_count":22,"runway_expectation_count":8,"cases":cases,"runway_expectations":runway,
                "limits":["No full Readback or authenticated native fingerprint fabricated.","Tiny inputs are pure arithmetic research only, not additional admitted weather selections.","No backend/trim/aerodynamic/handling/pilot/training/source acceptance.","No existing model, contact, startup, trim or convergence expectation/budget changed."]}


def emitted():
    return (json.dumps(build(),ensure_ascii=True,indent=2)+'\n').encode('utf-8')


def main():
    parser=argparse.ArgumentParser()
    group=parser.add_mutually_exclusive_group(required=True)
    group.add_argument('--check',action='store_true')
    group.add_argument('--write-new',action='store_true')
    options=parser.parse_args()
    expected=HERE/'expected-v1.json'
    data=emitted()
    if options.check:
        assert expected.read_bytes()==data,'Reference regeneration mismatch; never overwrite expectations'
    else:
        with expected.open('xb') as f:
            f.write(data)
    print(json.dumps({'passed':True,'case_count':22,'runway_expectation_count':8,'expected_sha256':hashlib.sha256(data).hexdigest(),'mode':'read-only-check' if options.check else 'create-new-only','no_consumer_output':True}))


if __name__=='__main__':
    main()
