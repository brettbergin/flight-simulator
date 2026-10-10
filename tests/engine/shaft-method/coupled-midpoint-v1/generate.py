#!/usr/bin/env python3
"""Independent ADR015 reference source candidate. Execution requires Root gate.

No vendor/helper import, compiler, native output, fitted tolerance, or random
sweep. Rational intervals are authoritative; hexadecimal binary64 is a proved
representation, never an automatic native comparison tolerance.
"""
import argparse
import hashlib
import json
import sys
from pathlib import Path
from fractions import Fraction as Q
import xml.etree.ElementTree as ET

from exact import (IV, RF, add, scale, mul, poly, evaluate, derivative,
                   compose_linear, bernstein, isolate, multiplicity, sign_on,
                   cauchy, binary64_bits, from_bits, rn, rounding_cell, floor_cell,
                   time_function, torque_function, verified_time, dyadic_enclose, checked, MAX_BITS)

METHOD = "event_aware_coupled_midpoint_v1"
CONTRACT_MERGE = "eb410a634a9f18b4ea9177640aff391def5e7988"
U = Q(1, 2**53)
ETA = Q(1, 2**1075)
MAX_FINITE = from_bits(0x7fefffffffffffff)
REFINEMENT_BITS = 384
# 30103/100000 strictly exceeds log10(2). Retain a finite bound sufficient
# for every admitted integer, plus sign/rounding slack. Keep Python's decimal
# conversion guard finite. The pinned Python provides this API.
MAX_SERIALIZED_DIGITS = max(640, (MAX_BITS*30103+99999)//100000+2)


def encode(value):
    if isinstance(value, Q):
        checked(value)
        if sys.get_int_max_str_digits() != MAX_SERIALIZED_DIGITS:
            sys.set_int_max_str_digits(MAX_SERIALIZED_DIGITS)
        return f"{value.numerator}/{value.denominator}"
    if isinstance(value, IV):
        return {"lo": encode(value.lo), "hi": encode(value.hi)}
    if isinstance(value, dict):
        return {str(k): encode(v) for k, v in value.items()}
    if isinstance(value, (list, tuple)):
        return [encode(x) for x in value]
    if type(value) is int:
        checked(value)
    return value


def canonical(value):
    # Apply even for a packet with only JSON integers and no rational fields.
    sys.set_int_max_str_digits(MAX_SERIALIZED_DIGITS)
    return (json.dumps(encode(value), sort_keys=True, indent=2, allow_nan=False)+"\n").encode()


class FP:
    """Ideal algebra on rounded constants plus conservative per-op enclosure.

    This is a prospective operation audit, not a native operation-order claim.
    Every operation adds u*maxabs+2^-1075, valid for nearest/even gradual
    binary64, including underflow. Overflow/zero denominator fails.
    """
    def __init__(self, value, enclosure=None):
        self.value = Q(value)
        self.enclosure = enclosure or IV.point(value)

    @staticmethod
    def constant(decimal):
        return FP(rn(Q(decimal)))

    def result(self, value, bounds):
        if bounds.magnitude > MAX_FINITE:
            raise ArithmeticError("coefficient enclosure may overflow binary64")
        err = U*bounds.magnitude+ETA
        return FP(value, bounds+IV(-err, err))

    def __add__(self, other):
        other = fp(other)
        return self.result(self.value+other.value, self.enclosure+other.enclosure)

    __radd__ = __add__

    def __neg__(self):
        return FP(-self.value, -self.enclosure)

    def __sub__(self, other):
        return self + -fp(other)

    def __rsub__(self, other):
        return fp(other) + -self

    def __mul__(self, other):
        other = fp(other)
        return self.result(self.value*other.value, self.enclosure*other.enclosure)

    __rmul__ = __mul__

    def __truediv__(self, other):
        other = fp(other)
        return self.result(self.value/other.value, self.enclosure/other.enclosure)

    def __rtruediv__(self, other):
        return fp(other)/self

    def __pow__(self, n):
        ans = fp(1)
        for _ in range(n):
            ans = ans*self
        return ans


def fp(x):
    return x if isinstance(x, FP) else FP(Q(x))


class Model:
    def __init__(self, repo, roster):
        self.roster = roster
        self.pins = {}
        roots = []
        for item in roster["model_inputs"]:
            path = repo/item["path"]
            data = path.read_bytes()
            digest = hashlib.sha256(data).hexdigest()
            if digest != item["sha256"]:
                raise ValueError(f"pinned model changed: {item['path']}")
            self.pins[item["path"]] = digest
            roots.append(ET.fromstring(data))
        self.engine, self.propeller = roots
        self.pi = FP(from_bits(int(roster["backend_pi_bits"], 16)))
        self.parameters = {}
        for name in ("displacement", "static-friction", "sparkfaildrop", "cycles",
                     "bsfc", "volumetric-efficiency", "compression-ratio", "stroke",
                     "starter-rpm", "starter-torque", "dynamic-fmep", "static-fmep"):
            literal = self.engine.findtext(name)
            self.parameters[name] = FP.constant(literal)
        # Actual FGPiston loader retains 1-XMLdrop, rounded once after subtract.
        # Raw XML drop and the semantic loaded factor are distinct constants.
        self.spark_factor = FP(rn(1-self.parameters["sparkfaildrop"].value))
        self.table = [(FP.constant(a), FP.constant(b)) for a, b in
                      (line.split() for line in self.engine.find("table[@name='MIXTURE']/tableData").text.splitlines()
                       if line.strip())]
        # Mimic documented constexpr constant construction before displacement
        # multiplication. Keep its rounded result separate from ideal IN3.
        # constexpr operations themselves round after EACH operation.
        inch = rn(Q(1, 12))
        ft = rn(Q("0.3048"))
        ft3 = rn(rn(ft*ft)*ft)
        m3toft3 = rn(1/ft3)
        in3 = rn(rn(rn(inch*inch)*inch)/m3toft3)
        d_loaded = rn(self.parameters["displacement"].value*in3)
        self.displacement = FP(d_loaded)
        self.ideal_displacement = Q(self.engine.findtext("displacement"))*Q("0.0254")**3
        self.D, self.I = FP.constant(self.propeller.findtext("diameter")), FP.constant(self.propeller.findtext("ixx"))
        self.rho = FP(Q(1, 512))
        # Mirror ONLY the audited floating operation DAG in the enclosure
        # layer; the independent ideal formulas/polynomial oracle stay exact.
        self.two_pi = 2*self.pi
        d2 = self.D*self.D
        d4 = d2*d2
        d5 = d4*self.D
        k2 = self.two_pi*self.two_pi
        k3 = k2*self.two_pi
        self.L = (self.rho*d5)/k3
        p = self.parameters
        alpha = (fp(550)*60)/(5252*self.two_pi)
        self.t0 = (alpha*p["starter-torque"])*1
        self.ws = (p["starter-rpm"]*self.two_pi)/60

    def mixture(self, ratio):
        # Ideal loaded-constant interpolation and the rounded key enclosure
        # are separate. At a knot the latter may select either neighboring
        # source interval; enclose all possible intervals/clamps, not just the
        # interval selected by the ideal key.
        ideal = None
        if ratio.value <= self.table[0][0].value:
            ideal = self.table[0][1].value
        elif ratio.value >= self.table[-1][0].value:
            ideal = self.table[-1][1].value
        choices = []
        if ratio.enclosure.lo <= self.table[0][0].value:
            choices.append(self.table[0][1].enclosure)
        if ratio.enclosure.hi >= self.table[-1][0].value:
            choices.append(self.table[-1][1].enclosure)
        for (a, b), (c, d) in zip(self.table, self.table[1:]):
            if ideal is None and a.value <= ratio.value <= c.value:
                ideal = ((ratio.value-a.value)/(c.value-a.value))*(d.value-b.value)+b.value
            if ratio.enclosure.hi >= a.value and ratio.enclosure.lo <= c.value:
                # Full key enclosure is conservative even beyond this branch;
                # zero table span is rejected by the interval divisor guard.
                factor = (ratio-a)/(c-a)
                choices.append((factor*(d-b)+b).enclosure)
        if ideal is None or not choices:
            raise AssertionError("MIXTURE interpolation exhausted")
        return FP(ideal, IV(min(x.lo for x in choices), max(x.hi for x in choices)))

    def frame(self, map_pa, mixture, magnetos, mode, ratio_override=None):
        p = self.parameters
        MAP, pamb, temp = FP.constant(str(map_pa)), fp(101325), FP.constant("288.15")
        ratio = p["compression-ratio"] if MAP.value < 1 else pamb/MAP
        if ratio.value > p["compression-ratio"].value:
            ratio = p["compression-ratio"]
        gamma = FP.constant("1.3")
        ve = (gamma-1)/gamma+(p["compression-ratio"]-ratio)/(gamma*(p["compression-ratio"]-1))
        efficiency = p["volumetric-efficiency"]*ve
        density = MAP/(FP.constant("287.3")*temp)
        q = FP.constant("1.3")*FP.constant(str(mixture))*101325/pamb
        if ratio_override is None:
            far = q/FP.constant("14.7")
        else:
            # C07 explicitly supplies a held q outside the base command set.
            # Its loaded q must actually divide back to the declared dyadic
            # table input; a merely nearby table knot is not called exact.
            divisor = FP.constant("14.7").value
            q = FP(rn(Q(ratio_override)*divisor))
            far = FP(rn(q.value/divisor))
            if far.value != ratio_override:
                raise ArithmeticError("C07 loaded q does not reproduce declared ratio knot/side")
        me = self.mixture(far)
        air = self.displacement*efficiency*density/(4*self.pi)
        fuel = air*far*FP.constant("2.2046")*3600
        pmep = (MAP-pamb)*p["volumetric-efficiency"]
        kr = 60/self.two_pi
        pump_den = p["cycles"]*22371
        pump_scale = ((550*self.displacement)*kr)/pump_den
        pump = pmep*pump_scale
        spark = fp(1) if magnetos == 3 else self.spark_factor
        if magnetos == 0:
            combustion = fp(0)
        else:
            combustion = (((550*fuel)*me)*spark)/p["bsfc"]
        if mode == "running":
            static_friction = p["static-fmep"]*pump_scale
            stroke_rate = p["stroke"]/360
            dynamic = -(((p["dynamic-fmep"]*stroke_rate)*FP.constant("0.3048"))*(pump_scale*kr))
            c = [-550*p["static-friction"], (pump-static_friction)+combustion,
                 dynamic, fp(0)]
        elif mode == "stopped":
            c = [-550*p["static-friction"], pump, fp(0), fp(0)]
        elif mode == "cranking":
            c = [fp(0), pump, fp(0), fp(0)]
        else:
            raise ValueError("unknown source mode")
        return c, {"MAP": MAP, "PMEP": pmep, "ve_reduced": efficiency,
                   "a_air": air, "a_fuel_pph": fuel, "fuel_air_ratio": far, "equivalence_ratio": q,
                   "ME": me, "spark": spark, "combustion_c1": combustion}

    def aero(self, c, V, above_cp=False, starter=False, above_starter=False):
        c = list(c)
        V = fp(V)
        A = (self.two_pi*V)/self.D
        if V.value <= 0:
            c[3] = -(FP.constant("0.06")*self.L)
        elif above_cp:
            c[2] = c[2]+FP.constant("0.02")*A*self.L
            c[3] = -(FP.constant("0.06")*self.L)
        else:
            c[3] = -(FP.constant("0.02")*self.L)
        if starter and not above_starter:
            c[1] = c[1]+self.t0
            c[2] = c[2]-self.t0/self.ws
        return c


def coefficient_report(c):
    return [{"ideal_on_loaded_constants": x.value,
             "prospective_straight_line_binary64_enclosure": x.enclosure,
             "scalar_fixture_input_bits": f"{binary64_bits(x.value):016x}"} for x in c]


def dyadic_coefficients(c):
    return tuple(rn(x.value) if isinstance(x, FP) else rn(Q(x)) for x in c)


def midpoint_polynomial(I, w0, h, c):
    m = (w0/2, Q(1, 2))
    if c[0] == 0:
        return add((-I*w0, I), scale(compose_linear(c[1:], *m), -h))
    lhs = scale(mul((-w0, 1), m), I)
    return add(lhs, scale(compose_linear(c, *m), -h))


def B_polynomial(w0, c):
    m = (w0/2, Q(1, 2))
    m2, m3 = mul(m, m), mul(mul(m, m), m)
    return add((0, c[0]), add(scale(m2, c[1]+c[2]*w0),
                             scale(mul(m3, (2*w0-m[0], -m[1])), c[3])))


def H(I, w0, x, c):
    m = (w0+x)/2
    T = evaluate(c[1:], m) if c[0] == 0 else evaluate(c, m)/m
    if not T:
        raise ArithmeticError("undefined discrete time map")
    return I*(x-w0)/T


def root_report(p, roots):
    coarse = isolate(p, 192)
    reports = []
    for r in roots:
        matches = [s for s in coarse if s.lo <= r.lo and r.hi <= s.hi]
        if len(matches) != 1:
            raise ArithmeticError("384-bit enclosure not nested in unique 192-bit enclosure")
        residual = bernstein(p, r.lo, r.hi)
        if not residual.lo <= 0 <= residual.hi:
            raise ArithmeticError("root residual enclosure excludes zero")
        reports.append({"root": r, "enclosure_192": matches[0], "multiplicity": multiplicity(p, r),
                        "residual": residual, "rounding": rounding_cell(r, p),
                        "binary64_floor": floor_cell(r, p)})
    return reports


def fixed_step(I, w0, h, c, endpoint=None):
    """Independent F/Sturm classification; never the production H bisection."""
    I, w0, h = Q(I), Q(w0), Q(h)
    c = tuple(map(Q, c))
    if I <= 0 or w0 < 0 or h < 0 or c[0] > 0 or c[3] > 0:
        return {"status": "reject", "reason": "descriptor domain"}
    if h == 0:
        return {"status": "hold", "final": IV.point(w0), "no_assignment": True}
    if w0 == 0 and (c[0] < 0 or c[1] <= 0):
        return {"status": "hold", "final": IV.point(0), "constrained_rest": True}
    torque = torque_function(c)
    drift_value = torque.value(w0)
    if not drift_value:
        return {"status": "hold", "final": IV.point(w0), "initial_equilibrium": True}
    drift = 1 if drift_value > 0 else -1
    eqp = poly(c[1:] if c[0] == 0 else c)
    equilibria = [r for r in isolate(eqp) if r.hi >= 0]
    if any(r.width and r.lo <= w0 <= r.hi for r in equilibria):
        raise ArithmeticError("uncertified initial speed/equilibrium ordering")
    future = [r for r in equilibria if (r.lo > w0 if drift > 0 else r.hi < w0)]
    eq = (min(future, key=lambda r: r.lo) if drift > 0 else max(future, key=lambda r: r.hi)) if future else None
    cap, kind = None, None
    if endpoint is not None:
        endpoint = Q(endpoint)
        if drift*(endpoint-w0) <= 0:
            raise ValueError("event endpoint is not outgoing")
        cap, kind = IV.point(endpoint), "event"
    if eq is not None:
        if cap is not None and eq.intersects(cap):
            if eq.width or cap.width or eq.lo != cap.lo:
                raise ArithmeticError("uncertified event/equilibrium ordering")
            cap, kind = eq, "equilibrium"  # Coincident equilibrium has priority.
        elif cap is None or (eq.hi < cap.lo if drift > 0 else eq.lo > cap.hi):
            cap, kind = eq, "equilibrium"
    finite_stop = c[0] < 0 or (c[0] == 0 and c[1] < 0)
    if drift < 0 and cap is None:
        cap, kind = IV.point(0), "stop" if finite_stop else "equilibrium"
    p = midpoint_polynomial(I, w0, h, c)
    roots = isolate(p)
    audit = {"polynomial": p, "all_real_roots": root_report(p, roots),
             "equilibria": equilibria, "drift": drift, "canceled": c[0] == 0}
    if cap is not None:
        a, b = sorted((w0, cap.lo if drift > 0 else cap.hi))
        if a != b and not sign_on(B_polynomial(w0, c), a, b, drift):
            return dict(audit, status="reject", reason="time map not strictly monotone on connected branch")
        # Algebraic equilibrium endpoints get an interval H enclosure. Exact
        # rational boundaries (all declared arrival tests) remain exact.
        if not cap.width:
            boundary_time = IV.point(H(I, w0, cap.lo, c))
        else:
            m = (cap+IV.point(w0))/2
            T = IV.point(0)
            for coefficient in reversed(c[1:] if c[0] == 0 else c):
                T = T*m+coefficient
            if c[0] != 0:
                T = T/m
            boundary_time = I*(cap-w0)/T
        audit.update(boundary_kind=kind, boundary=cap, boundary_time=boundary_time)
        if h >= boundary_time.hi:
            if kind == "equilibrium":
                return dict(audit, status="reject", reason="finite discrete equilibrium arrival/crossing")
            return dict(audit, status=kind, final=cap, consumed=boundary_time,
                        remaining=IV.point(h)-boundary_time, positive_zero=kind == "stop")
        if h >= boundary_time.lo:
            raise ArithmeticError("uncertified ordering against algebraic boundary time")
    candidates = [r for r in roots if r.lo >= 0 and
                  (r.lo > w0 if drift > 0 else r.hi < w0) and
                  (cap is None or (r.hi < cap.lo if drift > 0 else r.lo > cap.hi))]
    if len(candidates) != 1:
        return dict(audit, status="reject", reason="not exactly one connected admissible root")
    selected = candidates[0]
    # Positive-drift B follows admitted per-segment concavity; negative drift
    # without a cap would violate finite descriptor policy above.
    if drift > 0 and not (c[0] <= 0 and c[3] <= 0):
        raise ArithmeticError("missing positive drift concavity premise")
    for report in audit["all_real_roots"]:
        r = report["root"]
        report["classification"] = ("selected connected continuation" if r == selected else
                                    "negative speed" if r.hi < 0 else
                                    "wrong drift direction" if drift*(r.midpoint-w0) <= 0 else
                                    "outside nearest source-event/equilibrium boundary")
    audit.update(status="advance", final=selected)
    return audit


def scalar_groups(roster):
    rows = []
    for group in roster["kernel"]:
        hs = group.get("h_sides", [group["h"]])
        for index, h in enumerate(hs):
            I, w0 = Q(group["I"]), Q(group["w0"])
            c = tuple(Q(x) for x in group["c"])
            result = fixed_step(I, w0, Q(h), c)
            expected = group["status_sides"][index] if "status_sides" in group else group["status"]
            if result["status"] != expected:
                raise ArithmeticError(f"{group['id']}: independent result contradicts frozen policy {expected}")
            rows.append({"id": group["id"], "variant": index, "I": I, "w0": w0,
                         "h": Q(h), "c": c, "result": result})
    return rows


def coefficient_groups(model):
    rows = []
    specs = [("C01", 60000, "1", 3, "running", 0),
             ("C02", 60000, "1", 1, "running", 0),
             ("C03", 60000, "0", 0, "stopped", 0),
             ("C04", 60000, "1", 0, "cranking", 0)]
    for tag, map_pa, mixture, mag, mode, V in specs:
        c, diagnostics = model.frame(map_pa, mixture, mag, mode)
        engine = list(c)
        if mode == "cranking":
            engine[1] += model.t0
            engine[2] -= model.t0/model.ws
        diagnostic_w = Q(0) if mode == "cranking" else Q(100)
        c = model.aero(c, V, starter=mode == "cranking")
        rows.append({"id": tag, "coefficients": coefficient_report(c),
                     "diagnostics": {k: {"ideal": v.value, "enclosure": v.enclosure} for k, v in diagnostics.items()},
                     "pre_step_engine_power_polynomial": [x.value for x in engine],
                     "diagnostic_w": diagnostic_w,
                     "pre_step_engine_power": evaluate([x.value for x in engine], diagnostic_w),
                     "net_power_polynomial": [x.value for x in c],
                     "at_rest_net_power": evaluate([x.value for x in c], Q(0))})
    base, _ = model.frame(60000, "1", 0, "cranking")
    ws = model.ws.value
    below, above = model.aero(base, 0, starter=True), model.aero(base, 0, starter=True, above_starter=True)
    if evaluate([x.value for x in below], ws) != evaluate([x.value for x in above], ws):
        raise ArithmeticError("ideal taper coefficients discontinuous")
    rows.append({"id": "C05", "speeds": [ws*(1-Q(1, 4096)), ws, ws*(1+Q(1, 4096))],
                 "below": coefficient_report(below), "above": coefficient_report(above),
                 "exact_ideal_continuity": True, "outgoing_side": "drift", "initial_equilibrium_priority": True})
    for V in (-10, 0, 30):
        base, diagnostics = model.frame(101325, "1", 3, "running")
        lo, hi = model.aero(base, V), model.aero(base, V, above_cp=True)
        if diagnostics["PMEP"].value != 0:
            raise ArithmeticError("ambient MAP PMEP is not zero")
        k = (2*model.pi*V/model.D/2).value
        # Exact XML-decimal CP collapse is distinct from algebra on loaded
        # binary64 constants: RN(.06) is not exactly3*RN(.02). Keep native
        # coefficients/enclosures intact, and report that loaded-law join
        # rather than incorrectly requiring it to be a rational identity.
        xml_join_delta, loaded_join_delta = None, None
        if V > 0:
            xml_lo, xml_hi = [x.value for x in base], [x.value for x in base]
            A = 2*model.pi.value*V/model.D.value
            xml_lo[3] = -Q("0.02")*model.L.value
            xml_hi[2] += Q("0.02")*A*model.L.value
            xml_hi[3] = -Q("0.06")*model.L.value
            xml_join_delta = evaluate(xml_lo, k)-evaluate(xml_hi, k)
            if xml_join_delta != 0:
                raise ArithmeticError("exact XML CP collapse discontinuous")
            loaded_join_delta = evaluate([x.value for x in lo], k)-evaluate([x.value for x in hi], k)
        rows.append({"id": "C06", "V": V, "below": coefficient_report(lo), "above": coefficient_report(hi),
                     "k": k if V > 0 else None, "J1_not_polynomial_knot": True,
                     "exact_XML_CP_join_delta": xml_join_delta,
                     "ideal_on_loaded_constants_join_delta": loaded_join_delta})
    knot = model.table[3][0].value
    if model.mixture(fp(-1)).value != model.table[0][1].value or model.mixture(fp(1)).value != model.table[-1][1].value:
        raise ArithmeticError("MIXTURE clamped end policy changed")
    for delta in (-Q(1, 2**30), Q(0), Q(1, 2**30)):
        _, diagnostics = model.frame(60000, "1", 3, "running", knot+delta)
        rows.append({"id": "C07", "ratio": knot+delta,
                     "held_q": diagnostics["equivalence_ratio"].value,
                     "held_q_bits": f"{binary64_bits(diagnostics['equivalence_ratio'].value):016x}",
                     "ME": diagnostics["ME"].value, "ME_enclosure": diagnostics["ME"].enclosure,
                     "zero_RPM_ratio_limit": knot+delta, "end_clamp_assertion": True})
    return rows


def piecewise_step(I, w0, h, segments):
    """Finite known knot sequence; source expressions and times stay independent."""
    remaining, x = Q(h), Q(w0)
    results, counts = [], {"cp": 0, "starter": 0}
    for segment in segments:
        result = fixed_step(I, x, remaining, segment["c"], segment.get("endpoint"))
        results.append(result)
        if result["status"] == "event":
            if result["consumed"].width:
                raise ArithmeticError("rational source event expected")
            remaining -= result["consumed"].lo
            x = result["final"].lo
            for event in segment["events"]:
                counts[event] += 1
            continue
        return {"segments": results, "final": result.get("final"),
                "status": result["status"], "crossings": counts}
    raise ArithmeticError("piecewise roster lacks final segment")


def event_groups(model):
    rows = []
    L, pi, D = model.L.value, model.pi.value, model.D.value
    k, ws, t0 = pi*30/D, model.ws.value, model.t0.value
    # Scalar E laws intentionally use exact rational coefficients with backend
    # dyadic constants; they are not asserted to be actual production frames.
    # h is rounded explicitly. Ideal rational source coefficients and their
    # eventual rounded native realization are separate arithmetic layers.
    def cp(c, V, above):
        A = 2*pi*V/D
        c = list(map(Q, c))
        c[3] -= Q("0.06" if V <= 0 or above else "0.02")*L
        if V > 0 and above:
            c[2] += Q("0.02")*A*L
        return tuple(c)
    drive = 1+Q("0.06")*L*(3*k/2)**2
    lo, hi = cp((0, drive, 0, 0), 30, False), cp((0, drive, 0, 0), 30, True)
    losslo, losshi = cp((-550, 0, 0, 0), 30, False), cp((-550, 0, 0, 0), 30, True)
    # To preserve exact knot continuity, E scalar coefficients are passed as
    # exact rational fixtures. Native uses individually rounded inputs and
    # its separately ratified coefficient perturbation enclosure. h alone is
    # explicitly rounded; reference never snaps the final endpoint to target.
    def crossing(tag, start, target, pieces, stop=False):
        time = Q(0)
        x = start
        for seg in pieces:
            endpoint = seg.get("endpoint", target)
            time += H(model.I.value, x, endpoint, seg["c"])
            x = endpoint
        h = rn(time+(Q(1, 8) if stop else 0))
        result = piecewise_step(model.I.value, start, h, pieces)
        rows.append({"id": tag, "I": model.I.value, "w0": start, "h": h,
                     "h_ideal_construction": time, "target_construction_only": target,
                     "input_coefficient_representation": "exact rational scalar law; native rounding audited separately",
                     "source_segments": pieces, "result": result})
    crossing("E01", k/2, 3*k/2, [{"c": lo, "endpoint": k, "events": ["cp"]}, {"c": hi}])
    crossing("E02", 3*k/2, k/2, [{"c": losshi, "endpoint": k, "events": ["cp"]}, {"c": losslo}])
    for drift, c in ((1, hi), (-1, losslo)):
        rows.append({"id": "E03", "initial": k, "drift": drift, "selected_c": c,
                     "initial_crossings": {"cp": 0}, "result": fixed_step(model.I.value, k, Q(1, 4096), c)})
    pump = 1+Q("0.06")*L*(3*ws/2)**2
    lowstarter = (Q(0), pump+t0, -t0/ws, -Q("0.06")*L)
    highstarter = (Q(0), pump, Q(0), -Q("0.06")*L)
    crossing("E04", ws/2, 3*ws/2, [{"c": lowstarter, "endpoint": ws, "events": ["starter"]}, {"c": highstarter}])
    for drift in (-1, 0, 1):
        # Shift the abstract drive to give exactly the requested knot torque.
        base = Q("0.06")*L*ws**2+drift
        c = (Q(0), base, Q(0), -Q("0.06")*L)
        if drift < 0:
            c = (Q(0), base+t0, -t0/ws, -Q("0.06")*L)
        rows.append({"id": "E05", "initial": ws, "drift": drift, "selected_c": c,
                     "initial_crossings": {"starter": 0}, "result": fixed_step(model.I.value, ws, Q(1, 4096), c)})
    # Actual source operation order must be ratified against Ground's code.
    # There is never an approximately-coincident classification.
    ws64 = rn(rn(rn(Q(1200)*rn(2*pi))/60))
    V64 = rn(D*ws64/pi)
    k64 = rn(rn(rn(rn(2*pi)*V64)/D)/2)
    events = sorted(set((k64, ws64)))
    final = max(events)*Q(3, 2)
    start = min(events)/2
    u = 1+Q("0.06")*L*final**2
    pieces = []
    x = start
    for boundary in events+[final]:
        above_cp, above_starter = x >= k64, x >= ws64
        c = list(cp((0, u, 0, 0), V64, above_cp))
        # Scalar E06 defines exact dyadic knot k64 rather than silently using
        # the slightly different ideal pi*V64/D. Enforce continuity explicitly.
        if above_cp:
            c[2] = Q("0.04")*k64*L
        if not above_starter:
            c[1] += t0
            c[2] -= t0/ws64
        seg = {"c": tuple(c)}
        if boundary != final:
            seg.update(endpoint=boundary, events=[name for name, knot in (("cp", k64), ("starter", ws64)) if knot == boundary])
        pieces.append(seg)
        x = boundary
    crossing("E06", start, final, pieces)
    rows[-1].update(knot_recipe={"V64": V64, "k64": k64, "ws64": ws64,
                                "coincident": k64 == ws64, "operation_order_matches_vendor_v3": True})
    crossing("E07", 3*k/2, Q(0), [{"c": losshi, "endpoint": k, "events": ["cp"]}, {"c": losslo}], stop=True)
    return rows


def global_bound(I, c, compact, T, n):
    f = torque_function(c, I)
    f1, f2 = f.derivative(), f.derivative().derivative()
    F = f.bounds(*compact).magnitude
    L = f1.bounds(*compact).magnitude
    # Separate factor bounds are conservative a-priori bounds, not samples.
    M2 = L*F
    M3 = f2.bounds(*compact).magnitude*F**2+L**2*F
    C, h = M3/24+L*M2/8, T/n
    if h*L/2 >= 1:
        raise ArithmeticError("smooth stability precondition fails")
    q = (1+h*L/2)/(1-h*L/2)
    propagation = Q(n) if q == 1 else (q**n-1)/(q-1)
    return {"Fmax": F, "L": L, "M2": M2, "M3": M3, "C": C,
            "h": h, "q": q, "E": C*h**3/(1-h*L/2)*propagation}


def continuous_inverse(I, c, w0, T, compact, tau):
    g, f = time_function(I, c), torque_function(c, I)
    Fmax = f.bounds(*compact).magnitude
    if Fmax == 0:
        return IV.point(w0)
    drift = 1 if f.value(w0) > 0 else -1
    left, right = (w0, compact[1]) if drift > 0 else (compact[0], w0)
    # Must bracket by certified continuous time, not guessed display endpoints.
    far = right if drift > 0 else left
    far_time = verified_time(g, w0, far, tau/4)
    if far_time.lo <= T:
        raise ArithmeticError("continuous compact interval does not bracket time")
    for _ in range(256):
        if right-left <= Fmax*tau:
            return IV(left, right)
        m = (left+right)/2
        t = verified_time(g, w0, m, tau/4)
        if t.lo <= T <= t.hi:
            pad = Fmax*max(T-t.lo, t.hi-T)
            return IV(left, right).intersection(IV(m-pad, m+pad))
        before = t.hi < T
        if before == (drift > 0):
            left = m
        else:
            right = m
    raise ArithmeticError("continuous inversion work ceiling")


def dyadic_refinement_state(state):
    """Outward-only compression between certified midpoint-map iterations.

    Arbitrary rational Cauchy-grid endpoint factors must not be exponentiated
    by the next polynomial construction. This changes only the enclosing
    representation: the existing global bound and compact checks still apply.
    """
    return IV(dyadic_enclose(state.lo, REFINEMENT_BITS).lo,
              dyadic_enclose(state.hi, REFINEMENT_BITS).hi)


def refinement_groups(model):
    source, _ = model.frame(60000, "1", 3, "running")
    source = tuple(x.value for x in model.aero(source, 0))
    source_compact = (Q(99), Q(101))
    source_f = torque_function(source, model.I.value)
    source_F = source_f.bounds(*source_compact).magnitude
    source_L = source_f.derivative().bounds(*source_compact).magnitude
    source_T = 1/(8*(1+source_F+source_L))
    families = [("K07", Q(1), Q(2), (Q(0), Q(0), Q(-1), Q(0)), (Q(1), Q(2)), Q(1, 2)),
                ("K09", Q(1), Q(2), (Q(0), Q(0), Q(0), Q(-1)), (Q(1), Q(2)), Q(1, 8)),
                ("C01", model.I.value, Q(100), source, source_compact, source_T)]
    rows = []
    for tag, I, w0, c, compact, T in families:
        f = torque_function(c, I)
        # Closed enclosure must not contain an equilibrium or singularity.
        fb = f.bounds(*compact)
        if fb.lo <= 0 <= fb.hi:
            raise ArithmeticError("smooth compact contains uncertified equilibrium")
        bounds = {n: global_bound(I, c, compact, T, n) for n in (8, 16, 32)}
        E_min = min(x["E"] for x in bounds.values() if x["E"] > 0)
        tau = min(T/2**24, E_min/(64*bounds[32]["Fmax"]))
        continuous = continuous_inverse(I, c, w0, T, compact, tau)
        if tag in ("K07", "K09"):
            analytic = (IV.point(w0/(1+w0*T)) if tag == "K09" else None)
            # Linear drag exp is enclosed by an exact alternating Taylor sum.
            if tag == "K07":
                term, total = Q(1), Q(1)
                for j in range(1, 129):
                    term *= -T/j
                    total += term
                next_term = term*(-T/129)
                analytic = w0*IV(min(total, total+next_term), max(total, total+next_term))
            if not continuous.intersects(analytic):
                raise ArithmeticError("continuous oracle contradicts independent analytic solution")
        partitions = []
        for n, bound in bounds.items():
            state = IV.point(w0)
            for _ in range(n):
                # For h*L/2<1, the midpoint map is increasing in initial speed.
                endpoints = [fixed_step(I, x, T/n, c) for x in (state.lo, state.hi)]
                if any(x["status"] != "advance" for x in endpoints):
                    raise ArithmeticError("refinement left smooth continuation domain")
                state = dyadic_refinement_state(IV(
                    min(x["final"].lo for x in endpoints),
                    max(x["final"].hi for x in endpoints)))
                if state.lo < compact[0] or state.hi > compact[1]:
                    raise ArithmeticError("refinement enclosure leaves certified compact")
            error = state-continuous
            if error.magnitude > bound["E"]:
                raise ArithmeticError("ideal discrete refinement exceeds a-priori global error bound")
            partitions.append({"N": n, "discrete": state, "error_interval": error, "a_priori": bound})
        rows.append({"id": tag, "I": I, "w0": w0, "c": c, "T": T,
                     "compact": compact, "tau": tau, "continuous": continuous,
                     "partitions": partitions, "native_arithmetic_enclosure": "requires separate operation audit"})
    return rows


def continuous_event_groups(model, events):
    rows = []
    for row in events:
        if row["id"] not in ("E02", "E07"):
            continue
        scale_time = row["h_ideal_construction"]
        tau = scale_time/2**24
        parts, w = [], row["w0"]
        for seg in row["source_segments"]:
            end = seg.get("endpoint", row["target_construction_only"])
            integral = verified_time(time_function(row["I"], seg["c"]), w, end, tau/(4*len(row["source_segments"])))
            parts.append(integral)
            w = end
        rows.append({"id": row["id"], "T_scale": scale_time, "tau": tau,
                     "continuous_times": parts, "continuous_total": sum(parts, IV.point(0)),
                     "discrete_time_to_geometric_target": scale_time,
                     "known_zero_endpoint": row["id"] == "E07", "no_smooth_order_claim": True})
    return rows


def analytic_integral_crosschecks():
    """Existing K03/K05 stop limits independently cross-check quadrature."""
    rows = []
    for tag, I, w0, c, stop in (
            ("K03", Q(1), Q(1), (Q(0), Q(-2), Q(0), Q(0)), Q(1, 2)),
            ("K05", Q(2), Q(3), (Q(-2), Q(0), Q(0), Q(0)), Q(9, 2))):
        tau = stop/2**24
        certified = verified_time(time_function(I, c), w0, Q(0), tau)
        if not certified.lo <= stop <= certified.hi:
            raise ArithmeticError("analytic torque/loss stop contradicts certified quadrature")
        rows.append({"id": tag, "analytic_stop_time": stop, "tau": tau,
                     "continuous_time_interval": certified, "known_zero_endpoint": True})
    return rows


def assertions(roster):
    rows = []
    for group in roster["assertions"]:
        item = dict(group)
        item["evidence_kind"] = "prospective native assertion, not executed by mathematical generator"
        if item["id"] == "M03":
            cases = []
            for prior in (False, True):
                for rpm in (Q(480)-Q(1, 4096), Q(480), Q(480)+Q(1, 4096)):
                    for hp in (Q(1, 8)-Q(1, 2**20), Q(1, 8), Q(1, 8)+Q(1, 2**20)):
                        for fuel, spark in ((True, True), (False, True), (True, False)):
                            running = prior
                            if not fuel or not spark or (prior and rpm < 480):
                                running = False
                            elif not prior and rpm > 480:
                                running = True
                            if hp < Q(1, 8):
                                running = False
                            cases.append({"prior": prior, "rpm": rpm, "hp": hp, "fuel": fuel,
                                          "spark": spark, "expected_running": running})
            item["expanded_policy_cases"] = cases
        rows.append(item)
    return rows


def generate(repo, roster):
    model = Model(repo, roster)
    events = event_groups(model)
    packet = {"schema": "coupled-midpoint-reference-v1", "method": METHOD,
              "contract_merge": CONTRACT_MERGE, "model_pins": model.pins,
              "backend_pi_bits": roster["backend_pi_bits"], "arithmetic_comparison_status": "prospective, not native ratification",
              "loader_constants": {name: {"dyadic": value.value, "bits": f"{binary64_bits(value.value):016x}"}
                                   for name, value in model.parameters.items()},
              "loaded_source_state_constants": {"SparkFailDrop": {"dyadic": model.spark_factor.value,
                    "bits": f"{binary64_bits(model.spark_factor.value):016x}",
                    "construction": "RN(1 - RN(XML sparkfaildrop)); clamp[0,1] inactive for pinned XML"}},
              "displacement": {"ideal_xml_SI": model.ideal_displacement, "loaded_binary64_SI": model.displacement.value},
              "coefficients": coefficient_groups(model), "kernel": scalar_groups(roster), "events": events,
              "refinement": refinement_groups(model), "continuous_events": continuous_event_groups(model, events),
              "analytic_integral_crosschecks": analytic_integral_crosschecks(),
              "assertions": assertions(roster)}
    groups = {row["id"] for key in ("coefficients", "kernel", "events", "assertions") for row in packet[key]}
    expected = set(roster["named_groups"])
    if groups != expected or len(expected) != 41:
        raise ArithmeticError("finite named roster coverage mismatch")
    packet["named_group_count"] = len(groups)
    packet["expanded_mathematical_rows"] = sum(len(packet[k]) for k in ("coefficients", "kernel", "events"))
    packet["pending_native_assertion_groups"] = [row["id"] for row in packet["assertions"]]
    from native_fixture import build_native_cases
    native = build_native_cases(model, roster, packet, FP, fixed_step)
    packet["native_fixture_schema"] = native.pop("schema")
    packet["native_cases"] = native.pop("native_cases")
    packet["native_fixture_scope"] = native
    return packet


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo-root", type=Path, required=True)
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument("--write-new", type=Path, help="fresh output only; never overwrites")
    mode.add_argument("--check", type=Path, help="read-only deterministic byte comparison")
    args = parser.parse_args()
    roster_path = Path(__file__).with_name("cases.json")
    roster = json.loads(roster_path.read_text(encoding="utf-8"))
    packet = generate(args.repo_root.resolve(), roster)
    packet["roster_sha256"] = hashlib.sha256(roster_path.read_bytes()).hexdigest()
    packet["generator_sources"] = {name: hashlib.sha256(Path(__file__).with_name(name).read_bytes()).hexdigest()
                                   for name in ("generate.py", "exact.py", "native_fixture.py")}
    data = canonical(packet)
    if args.check:
        if args.check.read_bytes() != data:
            raise SystemExit("reference packet differs (no file written)")
        print("reference packet matches exactly; no native qualification claimed")
    else:
        args.write_new.parent.mkdir(parents=True, exist_ok=True)
        with args.write_new.open("xb") as out:
            out.write(data)
        print(f"fresh reference packet written: {args.write_new}")


if __name__ == "__main__":
    main()
