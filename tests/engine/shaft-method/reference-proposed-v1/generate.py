#!/usr/bin/env python3
# Original project source, MIT. No solver or consumer imports.
from fractions import Fraction as F
from decimal import Decimal, localcontext
from pathlib import Path
import hashlib
import json
import struct
import sys

HERE = Path(__file__).resolve().parent
IDEAL_A = F(1, 100)
BINARY_A = F.from_float(0.01)
U = F(1, 2**53)


def ratio(x):
    return {"numerator": str(x.numerator), "denominator": str(x.denominator)}


def bits(x):
    return struct.pack("<d", x).hex()


def decimal(x, precision=150):
    with localcontext() as ctx:
        ctx.prec = precision
        return Decimal(x.numerator) / Decimal(x.denominator)


def resolve(w, p, inertia, h, a):
    """Exact Fraction branch decisions; return omega squared plus event names."""
    assert w >= 0 and inertia > 0 and h >= 0
    if h == 0 or p == 0:
        return w*w, []
    if p > 0:
        if w < a:
            tau = inertia*(a-w)/p
            if h <= tau:
                end = w+p*h/inertia
                return end*end, ["up_threshold"] if h == tau else []
            h -= tau
            w = a
            events = ["up_threshold"]
        elif w == a:
            events = ["up_threshold_tau_zero"]
        else:
            events = []
        return w*w+2*p*h/inertia, events
    magnitude = -p
    events = []
    if w > a:
        tau = inertia*(w*w-a*a)/(2*magnitude)
        if h < tau:
            return w*w-2*magnitude*h/inertia, events
        h -= tau
        w = a
        events.append("down_threshold")
    sigma = inertia*w/magnitude
    if h >= sigma:
        return F(0), events+["stop"]
    end = w-magnitude*h/inertia
    return end*end, events


def root(x, precision):
    with localcontext() as ctx:
        ctx.prec = precision
        return (Decimal(x.numerator)/Decimal(x.denominator)).sqrt()


def recipe(label, w, p, inertia, h, binary_only=False):
    inputs = {"omega_rad_s": w, "net_power_ft_lbf_s": p,
              "inertia_slug_ft2": inertia, "dt_s": h}
    binary = {k: F.from_float(float(v)) for k, v in inputs.items()}
    sq, events = resolve(binary["omega_rad_s"], binary["net_power_ft_lbf_s"],
                         binary["inertia_slug_ft2"], binary["dt_s"], BINARY_A)
    ref = root(sq, 150)
    rounded = float(ref)
    assert bits(rounded) == bits(float(root(sq, 220)))
    # Proposed forward-roundoff target, not a theorem for an unspecified helper.
    scale = max(abs(binary["omega_rad_s"]), BINARY_A,
                abs(binary["net_power_ft_lbf_s"])*binary["dt_s"]/binary["inertia_slug_ft2"])
    # sqrt power term also sets the branch-local arithmetic scale.
    power_scale = root(2*abs(binary["net_power_ft_lbf_s"])*binary["dt_s"]/
                       binary["inertia_slug_ft2"], 150)
    scale_decimal = max(decimal(scale), power_scale)
    with localcontext() as ctx:
        ctx.prec = 150
        tolerance = Decimal(64)*decimal(U)*scale_decimal
    value = {"id": label, "inputs_ideal_fraction": {k: ratio(v) for k, v in inputs.items()},
             "inputs_binary64_le": {k: bits(float(v)) for k, v in inputs.items()},
             "binary64_threshold_le": bits(0.01),
             "expected_binary_input_omega_decimal": str(ref),
             "expected_binary_input_omega_nearest_binary64_le": bits(rounded),
             "binary_input_events": events,
             "proposed_abs_error_rad_s": str(tolerance),
             "exact_zero_required": sq == 0,
             "zero_duration_identity_required": h == 0}
    if not binary_only:
        ideal_sq, ideal_events = resolve(w, p, inertia, h, IDEAL_A)
        value.update(expected_ideal_omega_squared=ratio(ideal_sq),
                     expected_ideal_events=ideal_events)
    return value


def produce():
    cases = []
    def add(label, w, p, i, h, binary_only=False):
        cases.append(recipe(label, F(w), F(p), F(i), F(h), binary_only))
    add("rational_positive_exact_root", F(1,5), 3, 2, F(3,20))
    add("rational_negative_exact_root", F(7,10), -3, 2, F(2,15))
    add("zero_power_hold", F(1,2), 0, 2, F(1,120))
    add("zero_duration_identity_positive", F(3,7), 3, 2, 0)
    add("zero_duration_identity_negative", F(3,7), -3, 2, 0)
    add("stopped_negative_power", 0, -1, 2, F(1,60))
    add("stopped_zero_power", 0, 0, 2, F(1,60))
    for tag, h in [("before", F(1,200)), ("at", F(1,100)), ("after", F(3,200))]:
        add("upward_"+tag, F(1,200), 1, 2, h)
        add("low_stop_"+tag, F(1,200), -1, 2, h)
    down_tau = F(3,10000)
    for tag, h in [("before", down_tau/2), ("at", down_tau),
                   ("low_remainder", down_tau+F(1,100)),
                   ("stop_at", down_tau+F(1,50)),
                   ("past_stop", 2*(down_tau+F(1,50)))]:
        add("downward_"+tag, F(1,50), -1, 2, h)
    for hz in (60, 120, 240):
        h = F(1,hz)
        for tag, w, p in [("cold_low", F(0), F(1)),
                          ("threshold_up", IDEAL_A, F(1)),
                          ("threshold_down", IDEAL_A, F(-1)),
                          ("low_cross", F(9,1000), F(1)),
                          ("low_stop", F(1,200), F(-1)),
                          ("above_positive", F(2), F(3)),
                          ("above_negative", F(2), F(-3))]:
            add(f"{tag}_{hz}hz", w, p, 2, h)
    encoded = struct.unpack("<Q", struct.pack("<d", 0.01))[0]
    for offset, tag in [(-1,"below"),(0,"equal"),(1,"above")]:
        w = F.from_float(struct.unpack("<d",struct.pack("<Q",encoded+offset))[0])
        for sign in (-1,1):
            add(f"binary_threshold_{tag}_{sign:+d}", w, sign, 2, F(1,120), True)
    partitions = []
    for label, w, p in [("up_event",F(0),F(1)),
                        ("down_and_stop",F(1,10),F(-1)),
                        ("high_positive",F(2),F(3))]:
        sq, events = resolve(w,p,F(2),F(1,20),IDEAL_A)
        for hz, count in [(60,3),(120,6),(240,12)]:
            partitions.append({"id":f"{label}_{hz}hz", "omega0":ratio(w),
                "power":ratio(p),"inertia":ratio(F(2)),"tick_dt":ratio(F(1,hz)),
                "ticks":count,"total_dt":ratio(F(1,20)),
                "expected_ideal_final_squared":ratio(sq),"expected_ideal_events":events,
                "scope":"Mathematical held-P event equation only; no coupled-engine convergence claim"})
    negatives = []
    for field in ["omega_rad_s","net_power_ft_lbf_s","inertia_slug_ft2","dt_s"]:
        for special in ["nan","positive_infinity","negative_infinity"]:
            negatives.append({"id":field+"_"+special,"field":field,"special":special,
                              "expected":"reject-before-shaft-assignment"})
    for label, field, value in [("negative_omega","omega_rad_s",-1),
                                ("negative_dt","dt_s",-1),
                                ("zero_inertia","inertia_slug_ft2",0),
                                ("negative_inertia","inertia_slug_ft2",-1)]:
        negatives.append({"id":label,"field":field,"value":value,
                          "expected":"reject-before-shaft-assignment"})
    negatives.append({"id":"unknown_method","method":"unknown",
                      "expected":"reject-before-shaft-assignment"})
    max_float = F.from_float(sys.float_info.max)
    min_float = F.from_float(struct.unpack("<d", bytes.fromhex("0100000000000000"))[0])
    overflow = {"id":"mathematical_candidate_overflow", "inputs":{
                "omega_rad_s":ratio(max_float),"net_power_ft_lbf_s":ratio(max_float),
                "inertia_slug_ft2":ratio(min_float),"dt_s":ratio(max_float)},
                "expected":"reject-before-shaft-assignment"}
    result_sq,_ = resolve(max_float,max_float,min_float,max_float,BINARY_A)
    assert result_sq > max_float*max_float
    negatives.append(overflow)
    return {"status":"PROPOSED-private-preconsumer-not-ratified",
        "method":"event_aware_constant_power_v1", "backend_output_observed":False,
        "threshold_ideal":ratio(IDEAL_A),"threshold_binary64_le":bits(0.01),
        "oracle":"Exact Fraction branch decisions; Decimal150/220 square-root agreement; Python struct binary64 encodings",
        "comparison_proposal":{"status":"PROPOSED-needs-source-algorithm-review-before-output",
            "formula":"abs(error)<=64*2^-53*max(abs(omega0),a,abs(P)*h/I,sqrt(2*abs(P)*h/I))",
            "rationale":"At most two events; target allows two gamma32 forward-roundoff envelopes at branch-local scale for an independently reviewed stable bounded operation chain. No fitted output and no certified universal cancellation theorem.",
            "requirements":"All exact stopped results +0; h==0 identity; malformed/overflow explicit rejection. Near-event binary-input decisions distinct from ideal rational events."},
        "valid_case_count":len(cases),"valid_cases":cases,
        "partition_case_count":len(partitions),"constant_power_partitions":partitions,
        "invalid_case_count":len(negatives),"invalid_cases":negatives,
        "unfrozen_seams":["omega=-0 normalization/hold policy",
            "Specific finite intermediate overflow/underflow expectations depend on the reviewed stable algorithm; not frozen as mathematically universal failures",
            "RPM conversion no-op and overflow must use actual starting-RPM semantics before helper/backend tests"]}


def encoded():
    return (json.dumps(produce(),indent=2,sort_keys=True)+"\n").encode("utf-8")


if __name__ == "__main__":
    out = HERE/"expected-proposed-v1.json"
    value = encoded()
    if sys.argv[1:] == ["--create"]:
        with out.open("xb") as f:
            f.write(value)
    elif sys.argv[1:] == ["--check"]:
        assert out.read_bytes()==value, "Frozen private packet changed"
    else:
        raise SystemExit("Use --create once, or --check read-only")
    result=json.loads(value)
    print(json.dumps({"status":result["status"],"valid":result["valid_case_count"],
        "partitions":result["partition_case_count"],"invalid":result["invalid_case_count"],
        "sha256":hashlib.sha256(value).hexdigest(),"backend_output_observed":False}))
