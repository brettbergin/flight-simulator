"""Recompute frozen original equations using independent Decimal arithmetic.

Checks expectations without importing JSBSim or the JavaScript evaluator.
It never rewrites the reference file or learns parameters from telemetry.
"""
from decimal import Decimal as D, localcontext
from pathlib import Path
import json
import hashlib

ROOT = Path(__file__).resolve().parents[2]

def evaluate(inputs):
    x = {k: D(v) for k, v in inputs.items()}
    rho, speed, alpha, beta = (x[k] for k in
        ('rho_kg_m3', 'tas_mps', 'alpha_rad', 'beta_rad'))
    denominator = max(D('.6096'), 2 * speed)
    phat = x['p_aero_rad_s'] * 10 / denominator
    qhat = x['q_aero_rad_s'] * D('1.7') / denominator
    rhat = x['r_aero_rad_s'] * 10 / denominator
    qbar = rho * speed * speed / 2
    area_force = qbar * 17
    clift = D('.22') + 5 * alpha
    cdrag = D('.03') + D('.08') * alpha * alpha
    cside = -D('.5') * beta + D('.15') * x['jsb_rudder']
    croll = -D('.05') * beta - D('.6') * phat + D('.08') * x['jsb_aileron']
    cpitch = D('.02') - alpha - 8 * qhat - D('.7') * (x['jsb_elevator'] + x['jsb_trim'])
    cyaw = D('.1') * beta - 2 * rhat - D('.08') * x['jsb_rudder']
    return dict(qbar_pa=qbar, qS_n=area_force, phat=phat, qhat=qhat, rhat=rhat,
        CL=clift, CD=cdrag, CY=cside, Cl=croll, Cm=cpitch, Cn=cyaw,
        lift_wind_n=area_force*clift, drag_wind_n=area_force*cdrag,
        side_wind_n=area_force*cside, roll_body_nm=area_force*10*croll,
        pitch_body_nm=area_force*D('1.7')*cpitch, yaw_body_nm=area_force*10*cyaw)

def check():
    corpus = json.loads((ROOT/'tests/reference/original-polynomial-v1.json').read_text())
    research_bytes = (ROOT/'tests/reference/frozen-research-v1.json').read_bytes()
    if hashlib.sha256(research_bytes).hexdigest() != corpus['frozen_research_sha256']:
        raise ValueError('Frozen independent research digest changed')
    research = json.loads(research_bytes)
    if corpus['cases'] != research['cases']:
        raise ValueError('Cases differ from pre-observation research packet')
    count = 0
    with localcontext() as ctx:
        ctx.prec = 50
        for case in corpus['cases']:
            expected = {k:D(v) for k,v in case['expected_decimal'].items()}
            derived = evaluate(case['inputs'])
            if expected.keys() != derived.keys():
                raise ValueError('Expected quantity set changed')
            for key, value in expected.items():
                if value != derived[key]:
                    raise ValueError(f"Independent decimal mismatch: {case['id']}/{key}")
                count += 1
    print(json.dumps({'status':'passed','precision_digits':50,'cases':len(corpus['cases']),'quantities':count}))

if __name__ == '__main__':
    check()
