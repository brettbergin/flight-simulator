"""Independent, finite binary64-input realization of the mathematical roster.

No vendor imports, executable calls, observed outputs or tuning loops. This
module is source-only until the separate Root generation authorization.
"""
from fractions import Fraction as Q
from exact import IV, rn, binary64_bits, evaluate


def bits(q):
    return f"{binary64_bits(Q(q)):016x}"


def scalar_type(FP):
    """Integer-rounded value plus independently propagated absolute interval."""
    class S:
        def __init__(self, value, audit=None):
            self.r = rn(Q(value))
            raw = binary64_bits(self.r)
            exponent = (raw >> 52) & 2047
            if self.r and not 963 <= exponent <= 1083:
                raise ArithmeticError("native fixture DAG operation outside reviewed exponent domain")
            self.audit = FP(self.r) if audit is None else audit

        def other(self, x):
            return x if isinstance(x, S) else S(x)

        def __add__(self, x):
            x = self.other(x)
            return S(self.r+x.r, self.audit+x.audit)

        __radd__ = __add__

        def __neg__(self):
            return S(-self.r, -self.audit)

        def __sub__(self, x):
            return self+-self.other(x)

        def __rsub__(self, x):
            return self.other(x)+-self

        def __mul__(self, x):
            x = self.other(x)
            return S(self.r*x.r, self.audit*x.audit)

        __rmul__ = __mul__

        def __truediv__(self, x):
            x = self.other(x)
            return S(self.r/x.r, self.audit/x.audit)

        def __rtruediv__(self, x):
            return self.other(x)/self
    return S


def selected_bits(result):
    if result["status"] in ("hold", "stop", "event"):
        final = result["final"]
        if final.width:
            raise ArithmeticError("non-point native boundary/hold")
        return bits(final.lo)
    selected = [x for x in result["all_real_roots"]
                if x.get("classification") == "selected connected continuation"]
    if len(selected) != 1 or "bits" not in selected[0]["binary64_floor"]:
        raise ArithmeticError("native fixture exact floor certificate unresolved")
    return selected[0]["binary64_floor"]["bits"]


def rejection_reason(result):
    # These two independent mathematical categories have distinct reviewed
    # production admission errors. Unknown categories fail source generation.
    if result.get("reason") == "time map not strictly monotone on connected branch":
        return "coupled shaft: decay continuation uncertified"
    if result.get("reason") == "finite discrete equilibrium arrival/crossing":
        return "coupled shaft: finite equilibrium arrival or uncertain ordering"
    raise ArithmeticError("unmapped native fixture mathematical rejection")


def build_native_cases(model, roster, ideal_packet, FP, fixed_step):
    S = scalar_type(FP)
    cases = []
    pi = S(model.pi.value)
    two_pi = 2*pi
    D, I, rho = S(model.D.value), S(model.I.value), S(model.rho.value)
    p = {k: S(v.value) for k, v in model.parameters.items()}
    d, spark_drop = S(model.displacement.value), S(model.spark_factor.value)
    table = [(S(a.value), S(b.value)) for a, b in model.table]
    t0 = ((S(550)*60)/(5252*two_pi))*p["starter-torque"]*1
    ws = (p["starter-rpm"]*two_pi)/60
    d2 = D*D
    d4 = d2*d2
    d5 = d4*D
    k2 = two_pi*two_pi
    k3 = k2*two_pi
    L = (rho*d5)/k3

    def emit(group, suffix, kind, tokens, expected, **metadata):
        row = {"request_id": f"{group}_{suffix}", "group_id": group,
               "kind": kind, "request_tokens": [str(x) for x in tokens],
               "expected": expected}
        row.update(metadata)
        cases.append(row)

    def exact_result(result):
        status = result["status"]
        if status == "reject":
            return {"status": "reject", "reason": rejection_reason(result)}
        expected = {"status": status, "fields": {
            "w_bits": selected_bits(result), "hold": status == "hold",
            "stop": status == "stop", "source_event": status == "event"}}
        if status in ("stop", "event"):
            rem = result["remaining"]
            if rem.width:
                raise ArithmeticError("non-exact native event remainder")
            expected["remaining"] = rem
        return expected

    # K15's non-dyadic h is intentionally rounded in this separate record;
    # the ideal kernel row and its polynomial are retained without alteration.
    for source in roster["kernel"]:
        for index, h in enumerate(source.get("h_sides", [source["h"]])):
            c = tuple(rn(Q(x)) for x in source["c"])
            inertia, w, step = (rn(Q(x)) for x in (source["I"], source["w0"], h))
            result = fixed_step(inertia, w, step, c)
            emit(source["id"], str(index), "K", [*(bits(x) for x in c),
                 bits(inertia), bits(w), bits(step), "0", bits(0)],
                 exact_result(result), reference=result,
                 representation="all input scalars independently RN to exact binary64 dyadics")

    def mixture_key(q):
        key = q/S("14.7")
        if key.r <= table[0][0].r:
            return key, table[0][1], "lower_clamp"
        if key.r >= table[-1][0].r:
            return key, table[-1][1], "upper_clamp"
        for index, ((x0, y0), (x1, y1)) in enumerate(zip(table, table[1:])):
            if key.r <= x1.r:
                factor = (key-x0)/(x1-x0)
                return key, factor*(y1-y0)+y0, index
        raise ArithmeticError("native fixture mixture key unclassified")

    def held(map_pa, mixture, magnetos, running, cranking, q_override=None):
        MAP, pamb, temp = S(map_pa), S(101325), S("288.15")
        mr = p["compression-ratio"] if MAP.r < 1 else pamb/MAP
        if mr.r > p["compression-ratio"].r:
            mr = p["compression-ratio"]
        gamma = S("1.3")
        ve = ((gamma-1)/gamma+(p["compression-ratio"]-mr)/
              (gamma*(p["compression-ratio"]-1)))
        reduced = p["volumetric-efficiency"]*ve
        q = S("1.3")*S(mixture)*101325/pamb if q_override is None else S(q_override)
        key, me, branch = mixture_key(q)
        # The extracted C input is a held, already-rounded ME result. The
        # independent actual table calculation is retained as separate metadata.
        values = {
            "StarterTorque": p["starter-torque"], "StarterGain": S(1),
            "StarterRPM": p["starter-rpm"], "RPM": S(0 if cranking else 600),
            "Cycles": p["cycles"], "displacement_SI": d,
            "StaticFriction_HP": p["static-friction"],
            "PMEP": S(((MAP-pamb)*p["volumetric-efficiency"]).r),
            "MAP": MAP, "R_air": S("287.3"), "T_amb": temp,
            "reducedVE": S(reduced.r), "q": S(q.r), "ME": S(me.r),
            "sparkFactor": S(1) if magnetos == 3 else spark_drop,
            "ISFC": p["bsfc"], "FMEPStatic": p["static-fmep"],
            "FMEPDynamic": p["dynamic-fmep"], "Stroke": p["stroke"],
            "fttom": S("0.3048"), "h": S(Q(1, 120))}
        return values, {"ratio_bits": bits(key.r), "ME_bits": bits(me.r),
                        "branch": branch, "key_interval": key.audit.enclosure,
                        "ME_interval": model.mixture(FP(q.r)/FP.constant("14.7")).enclosure,
                        "scope": "independent table oracle; probe C consumes held ME, not FGTable"}

    c_order = ["StarterTorque", "StarterGain", "StarterRPM", "RPM", "Cycles",
               "displacement_SI", "StaticFriction_HP", "PMEP", "MAP", "R_air",
               "T_amb", "reducedVE", "q", "ME", "sparkFactor", "ISFC",
               "FMEPStatic", "FMEPDynamic", "Stroke", "fttom", "h"]

    def assembly(v, running, cranking):
        # Each held scalar is a point input. Its upstream thermodynamic or
        # table uncertainty is NOT silently merged into this conditional C test.
        kr = 60/two_pi
        den = v["Cycles"]*22371
        ps = ((550*v["displacement_SI"])*kr)/den
        c0 = -550*v["StaticFriction_HP"] if running or not cranking else S(0)
        c1, c2 = v["PMEP"]*ps, S(0)
        if running:
            density = v["MAP"]/(v["R_air"]*v["T_amb"])
            air = ((v["displacement_SI"]*v["reducedVE"])*density)/(4*pi)
            fuel = ((air*(v["q"]/S("14.7")))*S("2.2046"))*3600
            combustion = (((550*fuel)*v["ME"])*v["sparkFactor"])/v["ISFC"]
            c1 = (c1-v["FMEPStatic"]*ps)+combustion
            c2 = -(((v["FMEPDynamic"]*(v["Stroke"]/360))*v["fttom"])*(ps*kr))
        alpha = (S(550)*60)/(5252*two_pi)
        torque = (alpha*v["StarterTorque"])*v["StarterGain"]
        limit = (v["StarterRPM"]*two_pi)/60
        return (c0, c1, c2), torque, limit

    # Original C01-04 source-assembly inputs, explicitly held and dyadic.
    for group, mix, mag, running, cranking in (
        ("C01", "1", 3, True, False), ("C02", "1", 1, True, False),
        ("C03", "0", 0, False, False), ("C04", "1", 0, False, True)):
        v, table_audit = held(60000, mix, mag, running, cranking)
        c, torque, limit = assembly(v, running, cranking)
        result = dict(zip(("c0_bits", "c1_bits", "c2_bits", "t0_bits", "ws_bits"),
                          (*c, torque, limit)))
        emit(group, "assembly", "C", [int(running), int(cranking),
             *(bits(v[x].r) for x in c_order)],
             {"status": "coefficients", "intervals": {
                 k: value.audit.enclosure for k, value in result.items()}},
             independent_RN_DAG_bits={k: bits(value.r) for k, value in result.items()},
             table_audit=table_audit,
             held_field_order=c_order, held_field_bits={x: bits(v[x].r) for x in c_order})

    knot = model.table[3][0].value
    for index, delta in enumerate((-Q(1, 2**30), Q(0), Q(1, 2**30))):
        target = knot+delta
        q = rn(target*rn(Q("14.7")))
        if rn(q/rn(Q("14.7"))) != target:
            raise ArithmeticError("native C07 held q does not reproduce declared key")
        v, table_audit = held(60000, "1", 3, True, False, q)
        c, torque, limit = assembly(v, True, False)
        result = dict(zip(("c0_bits", "c1_bits", "c2_bits", "t0_bits", "ws_bits"),
                          (*c, torque, limit)))
        emit("C07", str(index), "C", [1, 0, *(bits(v[x].r) for x in c_order)],
             {"status": "coefficients", "intervals": {
                 k: value.audit.enclosure for k, value in result.items()}},
             independent_RN_DAG_bits={k: bits(value.r) for k, value in result.items()},
             table_audit=table_audit, held_field_order=c_order,
             held_field_bits={x: bits(v[x].r) for x in c_order})

    def frame(mode, c0, c1, c2, torque=t0.r, limit=ws.r):
        return [mode, Q(0), Q(0), rn(Q(c0)), rn(Q(c1)), rn(Q(c2)),
                rn(Q(torque)), rn(Q(limit))]

    def geometry(velocity, density=rho.r):
        density, vel = S(density), S(velocity)
        load = (density*d5)/k3
        A = (two_pi*vel)/D if vel.r > 0 else S(0)
        return load, A, A*S(Q(1, 2))

    def law(f, w, cp_knot, load, A, direction):
        c = [S(f[3]), S(f[4]), S(f[5]), S(0)]
        low = A.r > 0 and (w < cp_knot.r or (w == cp_knot.r and direction < 0))
        c[3] = -(S("0.02" if low else "0.06")*load)
        if A.r > 0 and not low:
            c[2] = c[2]+(S("0.02")*A)*load
        if f[0] == 0 and (w < f[7] or (w == f[7] and direction < 0)):
            c[1] = c[1]+S(f[6])
            c[2] = c[2]-S(f[6])/S(f[7])
        return c

    def torque_sign(c, w):
        q = evaluate([x.r for x in (c[1:] if c[0].r == 0 else c)], w)
        return (q > 0)-(q < 0)

    # Direct CBuildLaw primitive seam; E below separately observes geometry.
    base, _ = held(60000, "1", 0, False, True)
    engine, torque, limit = assembly(base, False, True)
    f = frame(0, *(x.r for x in engine), torque.r, limit.r)
    load, A, cp_knot = geometry(0)
    for index, w in enumerate((limit.r*(1-Q(1, 4096)), limit.r, limit.r*(1+Q(1, 4096)))):
        w = rn(w)
        for direction in (-1, 1) if w == limit.r else (1,):
            c = law(f, w, cp_knot, load, A, direction)
            emit("C05", f"{index}_{direction:+d}".replace("+", "p").replace("-", "m"),
                 "L", [f[0], *(bits(x) for x in f[1:]), bits(w), bits(cp_knot.r),
                       bits(load.r), bits(A.r), direction],
                 {"status": "coefficients", "intervals": {
                     f"c{i}_bits": x.audit.enclosure for i, x in enumerate(c)}},
                 independent_RN_DAG_bits={f"c{i}_bits": bits(x.r) for i, x in enumerate(c)},
                 primitive_scope="CBuildLaw; independent rounded geometry inputs, not geometry execution")
    base, _ = held(101325, "1", 3, True, False)
    engine, torque, limit = assembly(base, True, False)
    f = frame(1, *(x.r for x in engine), torque.r, limit.r)
    for velocity in (-10, 0, 30):
        load, A, cp_knot = geometry(velocity)
        for direction in (-1, 1):
            c = law(f, cp_knot.r, cp_knot, load, A, direction)
            emit("C06", f"V{velocity}_{direction}".replace("-", "m"), "L",
                 [f[0], *(bits(x) for x in f[1:]), bits(cp_knot.r), bits(cp_knot.r),
                  bits(load.r), bits(A.r), direction],
                 {"status": "coefficients", "intervals": {
                     f"c{i}_bits": x.audit.enclosure for i, x in enumerate(c)}},
                 independent_RN_DAG_bits={f"c{i}_bits": bits(x.r) for i, x in enumerate(c)},
                 primitive_scope="CBuildLaw; V<=0 no CP knot and no directional coefficient change")

    def event_expectation(f, w, step, density, velocity):
        load, A, cp_knot = geometry(velocity, density)
        remaining, progress, stop = Q(step), False, False
        crossed, segments = set(), []
        for _ in range(4):
            c = law(f, w, cp_knot, load, A, 1)
            drift = torque_sign(c, w)
            at_knot = (A.r > 0 and w == cp_knot.r) or (f[0] == 0 and w == f[7])
            if at_knot:
                other = law(f, w, cp_knot, load, A, -1)
                if torque_sign(other, w) != drift:
                    raise ArithmeticError("native fixture has uncertified knot drift; prescribe exact abstract fixture")
                difference = abs(evaluate([x.r-y.r for x, y in zip(c, other)], w))
                magnitude = evaluate([abs(x.r)+abs(y.r) for x, y in zip(c, other)], w)
                gu = Q(32, 2**53)
                if difference*(1-gu) > magnitude*gu:
                    raise ArithmeticError("native fixture fails fixed runtime join admission")
                if drift < 0:
                    c = other
            if not drift or (w == 0 and (f[0] != 0 or drift <= 0)):
                return {"status": "hold" if not progress else "advance", "fields": {
                    "w_bits": bits(w), "hold": not progress, "stop": False,
                    "cp_crossings": int("cp" in crossed),
                    "starter_crossings": int("starter" in crossed)}}, segments
            candidates = [(cp_knot.r, "cp")] if A.r > 0 and "cp" not in crossed else []
            if f[0] == 0 and "starter" not in crossed:
                candidates.append((f[7], "starter"))
            outgoing = [(x, name) for x, name in candidates if drift*(x-w) > 0]
            endpoint = min(outgoing, key=lambda pair: drift*pair[0])[0] if outgoing else None
            result = fixed_step(I.r, w, remaining, tuple(x.r for x in c), endpoint)
            segments.append({"w0": w, "remaining": remaining, "c": [x.r for x in c],
                             "coefficient_intervals": [x.audit.enclosure for x in c],
                             "source_endpoint": endpoint, "reference": result})
            if result["status"] == "reject":
                return {"status": "reject", "reason": rejection_reason(result)}, segments
            if result["status"] == "event":
                if result["remaining"].width:
                    raise ArithmeticError("native fixture event time not exact")
                remaining = result["remaining"].lo
                w = endpoint
                progress = True
                crossed.update(name for x, name in outgoing if x == endpoint)
                if remaining:
                    continue
            final_bits = selected_bits(result)
            stop = result["status"] == "stop"
            return {"status": "stop" if stop else "advance", "fields": {
                "w_bits": final_bits, "hold": result["status"] == "hold" and not progress,
                "stop": stop, "cp_crossings": int("cp" in crossed),
                "starter_crossings": int("starter" in crossed)}}, segments
        raise ArithmeticError("native fixture exceeds four event segments")

    ideal_events = {row["id"]: row for row in ideal_packet["events"] if "h" in row}
    k = geometry(30)[2].r
    ideal_k = model.pi.value*30/model.D.value
    drive = rn(1+Q("0.06")*model.L.value*(3*ideal_k/2)**2)
    pump = rn(1+Q("0.06")*model.L.value*(3*model.ws.value/2)**2)
    native_events = [
        ("E01", "0", frame(1, 0, drive, 0), rn(k/2), rho.r, Q(30), ideal_events["E01"]["h"]),
        ("E02", "0", frame(2, -550, 0, 0), rn(3*k/2), rho.r, Q(30), ideal_events["E02"]["h"]),
        ("E03", "positive", frame(1, 0, drive, 0), k, rho.r, Q(30), Q(1, 4096)),
        ("E03", "negative", frame(2, -550, 0, 0), k, rho.r, Q(30), Q(1, 4096)),
        ("E04", "0", frame(0, 0, pump, 0), rn(ws.r/2), rho.r, Q(0), ideal_events["E04"]["h"]),
        ("E07", "0", frame(2, -550, 0, 0), rn(3*k/2), rho.r, Q(30), ideal_events["E07"]["h"])]
    # Exact initial starter equilibrium requires a realizable dyadic law.
    # This abstract scalar fixture deliberately uses rho0,t0=2,ws=4; it is
    # not a claim about original FGPiston frame admission or loaded1200RPM.
    for drift in (-1, 0, 1):
        native_events.append(("E05", str(drift).replace("-", "m"),
                              frame(0, 0, drift, 0, 2, 4), Q(4), Q(0), Q(0), Q(1, 4096)))
    recipe = ideal_events["E06"]["knot_recipe"]
    native_k, native_ws = geometry(recipe["V64"])[2].r, ws.r
    if native_k != recipe["k64"] or native_ws != recipe["ws64"]:
        raise ArithmeticError("E06 independent rounded knot operation mapping changed")
    final = max(native_k, native_ws)*Q(3, 2)
    u = rn(1+Q("0.06")*model.L.value*final**2)
    native_events.append(("E06", "0", frame(0, 0, u, 0),
                          rn(min(native_k, native_ws)/2), rho.r, recipe["V64"], ideal_events["E06"]["h"]))
    for group, suffix, f, w, density, velocity, h in native_events:
        h, w = rn(h), rn(w)
        f[1], f[2] = rn((w/two_pi.r)*60), h
        expected, segments = event_expectation(f, w, h, density, velocity)
        emit(group, suffix, "E", [f[0], *(bits(x) for x in f[1:]),
             bits(w), bits(I.r), bits(density), bits(D.r), bits(velocity)], expected,
             native_segments=segments,
             realization="explicit binary64 frame; independent RN geometry/coefficients and F/Sturm branch; ideal event rows retained",
             abstract_E05_override=group == "E05")

    for index, incoming in enumerate(("0000000000000000", "8000000000000000", "3ff0000000000000")):
        f = frame(0, 0, 0, 0)
        tokens = [str(f[0]), incoming, bits(0), *(bits(x) for x in f[3:]),
                  bits(0), bits(I.r), bits(rho.r), bits(D.r), bits(0)]
        emit("R01", str(index), "W", tokens,
             {"status": "hold", "fields": {"rpm_bits": incoming}})

    # Reject all nonfinite positions before any source-law evaluation. These
    # raw bits are intentionally never lifted into Fraction arithmetic.
    invalid_frame = ["1", bits(600), bits(Q(1, 120)), bits(-550), bits(100),
                     bits(-1), bits(t0.r), bits(ws.r), bits(10), bits(I.r),
                     bits(rho.r), bits(D.r), bits(0)]
    frame_names = ["preRPM", "h", "c0", "c1", "c2", "t0", "ws", "w", "I", "rho", "D", "V"]
    for position, name in enumerate(frame_names, 1):
        for tag, raw in (("nan", "7ff8000000000000"),
                         ("posinf", "7ff0000000000000"),
                         ("neginf", "fff0000000000000")):
            tokens = list(invalid_frame)
            tokens[position] = raw
            emit("R02", f"{name}_{tag}", "E", tokens,
                 {"status": "reject", "reason": "coupled shaft: nonfinite frame"},
                 scope="pure scalar frame rejection; last completed Session publication separately required")
    for name, position, value in (("preRPM_negative", 1, -1), ("h_negative", 2, -Q(1, 8)),
        ("c0_positive", 3, 1), ("t0_negative", 6, -1), ("ws_zero", 7, 0),
        ("w_negative", 8, -1), ("I_negative", 9, -1), ("I_zero", 9, 0),
        ("rho_negative", 10, -1), ("D_zero", 11, 0)):
        tokens = list(invalid_frame)
        tokens[position] = bits(value)
        emit("R02", name, "E", tokens,
             {"status": "reject", "reason": "coupled shaft: invalid frame domain"})
    tokens = list(invalid_frame)
    tokens[0] = "3"
    emit("R02", "unknown_mode", "E", tokens,
         {"status": "reject", "reason": "coupled shaft: unknown operating mode"})
    for name, mode, c0, c2 in (("crank_static", 0, -550, 0),
                             ("crank_dynamic", 0, 0, -1),
                             ("stopped_dynamic", 2, -550, -1)):
        tokens = list(invalid_frame)
        tokens[0], tokens[3], tokens[5] = str(mode), bits(c0), bits(c2)
        emit("R02", name, "E", tokens,
             {"status": "reject", "reason": "coupled shaft: inconsistent mode coefficients"})

    for index, item in enumerate(next(x for x in roster["assertions"] if x["id"] == "R04")["operand_bits"]):
        accepted = item["expected"].startswith("admit")
        reason = ("event-aware shaft: nonfinite or unsupported subnormal arithmetic" if
                  item["bits"] == "0000000000000001" else "coupled shaft: unsupported operand exponent")
        emit("R04", f"operand{index}", "G", ["operand", item["bits"]],
             {"status": "accept"} if accepted else {"status": "reject", "reason": reason})
    for guard, reason in (
        ("ftz", "event-aware shaft: FTZ/DAZ or SSE rounding unsupported"),
        ("daz", "event-aware shaft: FTZ/DAZ or SSE rounding unsupported"),
        ("rounding", "event-aware shaft: unsupported rounding mode"),
        ("product", "coupled shaft: unsupported operand exponent")):
        emit("R04", guard, "G", [guard], {"status": "reject", "reason": reason})
    emit("R04", "lower_progress", "K", [bits(0), bits(-Q(1, 4)), bits(0), bits(0),
         bits(1), bits(Q(1, 2**60)), bits(Q(1, 2**60)), "0", bits(0)],
         {"status": "reject", "reason": "coupled shaft: unsupported operand exponent"})
    for guard, reason in (
        ("bisect64", "coupled shaft: 64 root bisections exhausted"),
        ("split8", "coupled shaft: decay continuation uncertified"),
        ("capacity128", "coupled shaft: exact dyadic capacity")):
        emit("R05", guard, "G", [guard], {"status": "reject", "reason": reason},
             primitive_scope="resource guard only, not admitted actual-engine trajectory")

    policies = []
    for prior in (False, True):
        for rpm in (Q(480)-Q(1, 4096), Q(480), Q(480)+Q(1, 4096)):
            policies.append((prior, True, True, rpm, Q(1)))
        for hp in (Q(1, 8)-Q(1, 2**20), Q(1, 8), Q(1, 8)+Q(1, 2**20)):
            policies.append((prior, True, True, Q(600), hp))
        for spark, fuel in ((False, True), (True, False), (False, False), (True, True)):
            policies.append((prior, spark, fuel, Q(600), Q(1)))
    for index, (prior, spark, fuel, rpm, hp) in enumerate(policies):
        # Independent truth table from contract, not production function import.
        running = (spark and fuel and hp >= Q(1, 8) and
                   (rpm >= 480 if prior else rpm > 480))
        emit("M03", str(index), "P", [int(prior), int(spark), int(fuel),
             bits(rpm), bits(600), bits(hp)],
             {"status": "policy", "fields": {"running": running}},
             scope="extracted source mode branch; actual DLL chronology separately observed")

    ids = [x["request_id"] for x in cases]
    if len(ids) != len(set(ids)) or len(ids) > 192:
        raise ArithmeticError("native fixture roster identity/resource ceiling")
    return {"schema": "coupled-native-fixtures-v1", "native_cases": cases,
            "maximum_requests": 192,
            "reviewed_vendor_source_binding_sha256": "8a5457d2414085214d9b85ca8ccbf5ca0d082ce225e5a2991a1c323b570ef07f",
            "reviewed_arithmetic_audit_binding_sha256": "f4f07b487f26acb3c4916f5e826db0a67d1d15d226eabb9100fc02873520e1cf",
            "not_covered_by_pure_probe": ["R02 actual invalid publication", "R03 actual unsupported topology",
                "M01-M05 actual engine/public chronology", "M06 actual loaded-library selector/default"],
            "comparison": "same dyadic law floor bits; held C/L absolute operation intervals; no ideal-root ULP substitution",
            "packet_values_are_unexecuted_native_expectations": True}
