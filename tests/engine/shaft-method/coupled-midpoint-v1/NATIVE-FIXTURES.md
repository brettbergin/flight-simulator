# Frozen native realization interface

Status: source-only, no packet or native value generated. `native_fixture.py` produces this metadata only under later explicit reference-generation authorization. All41 named groups remain unchanged. Root/Ground own actual library/public chronology observations; these pure fixtures do not claim full engine acceptance.

Top-level packet additions: `native_fixture_schema`, `native_cases`, `native_fixture_scope`. Each native case is:

```
{request_id: unique ASCII identifier,
 group_id: existing C/K/E/R/M group,
 kind: K|E|W|C|L|G|P,
 request_tokens: [payload-only ASCII tokens in exact protocol order],
 expected: {status: advance|hold|stop|event|reject|accept|policy|coefficients,
            fields?: {result_field: exact string/bool/int},
            intervals?: {native_bits_field: {lo: rational, hi: rational}},
            remaining?: {lo: exact_rational, hi: same_exact_rational},
            reason?: exact production rejection string},
 additional independent coefficient/root/branch/input metadata...}
```

The normal packet encoder represents rationals as numerator/denominator strings. It encodes IV as lo/hi; no binary64 tolerance is hidden in decimal text. The preparer prefixes request_id and kind to request_tokens. Native responses must correspond exactly once to every prepared request.

Protocol orders:

- K: c0,c1,c2,c3,I,w,h bits; endpoint flag0/1; endpoint bits. Expected w_bits,hold,stop,source_event. Exact remaining only for stop/event.
- E/W: mode0/1/2; preRPM,h,c0,c1,c2,t0,ws,w,I,rho,D,V bits. R02_unknown_mode deliberately uses3. E expects w_bits,hold,stop,cp_crossings,starter_crossings. W supplied w is0; expects exact rpm_bits.
- C: running,cranking ints0/1; StarterTorque,StarterGain,StarterRPM,RPM,Cycles,displacement_SI,StaticFriction_HP,PMEP,MAP,R_air,T_amb,reducedVE,q,ME,sparkFactor,ISFC,FMEPStatic,FMEPDynamic,Stroke,fttom,h bits. Expected c0_bits,c1_bits,c2_bits,t0_bits,ws_bits interval membership. ME is a held input; table_audit records the independently derived key/ME, not a native table observation.
- L: mode; preRPM,h,c0,c1,c2,t0,ws,w,cpKnot,L,A bits; direction-1/+1. Invokes exact extracted CBuildLaw; expects c0_bits..c3_bits intervals. This is a primitive coefficient observation, not actual geometry execution.
- G: named guard, with one operand bit token only for operand. Exact expected source error is frozen per request. Controls must restore even on exception.
- P: prior,spark,fuel ints0/1; RPM,IdleRPM,indicatedHP bits. Exact extracted current-boundary policy; expected running boolean. Its fixed20 rows cover sided/equal RPM and HP policy plus supplied-fuel/spark conditions. Actual DLL HP-equality mutation is not claimed.

The native layer uses a finite <=192 request ceiling. This prospective ceiling was enlarged from128 before any values to include complete R02 invalid scalar positions; it is not a physics budget. Independent integer RN makes every geometry/coefficient intermediate explicit. Checked S operands/operations are normal-or-zero with exponent[-60,60], or generation fails. Exact arithmetic/B/Sturm root classification remains independent of production H-map bisection and its resource policy.

Ideal E05 and native E05 differ explicitly: native exact knot equilibrium requires a representable dyadic law, so native E05 uses abstract rho0,t0=2,ws=4 and c1=-1/0/1. No original loaded engine frame is claimed. E01/02/03/04/06/07 use source-rounded geometry/coefficient laws with original h constructions retained. Native K15 h is RN(21/500), while the ideal rational record stays21/500. Expected bits always come from the native dyadic polynomial, never the ideal record.

Actual invalid-publication retention R02, unsupported-content/topology R03, actual M01-M05 chronology and M06 selector/default remain independently bound observations. A successful pure probe cannot close these gates or the original coupled cross-rate budgets. Missing required actual observations must remain visible rather than reported as a complete41-group pass.
