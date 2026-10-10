# Proposed independent shaft-method reference packet

Status: PROPOSED; no coordinator ratification, accepted contract amendment or consumer/backend observation. Original MIT arithmetic reference source.

The packet has 45 exact Fraction branch recipes, 9 mathematical constant-held-power partition recipes and 18 input/result rejection cases, plus four separate signed-zero/no-op recipes. Decimal150 and Decimal220 independently agree on the nearest binary64 result. Rational a=1/100 and actual binary64 literal0.01 are distinct. Cases use genuine1/60,1/120,1/240 intervals; partition checks do not claim coupled engine convergence.

`generate.py --check` compares bytes without rewriting. `--create` uses exclusive creation only and refuses to replace an existing packet. No native code, solver or proposed implementation is imported.

The proposed absolute forward-roundoff target is64u times the branch-local scale, with u=2^-53. It is motivated by two gamma32 envelopes for at most two events. It remains an engineering target until the actual stable arithmetic order, event rounding and operation count have been independently reviewed before any method output. It is not a general formal bound or permission to loosen existing physical budgets. Exact stops require+0; zero time/power require original RPM no-write. Extreme finite intermediate-overflow cases are not given algorithm-independent guessed failure expectations.

See the adjacent source review for two contract clarification requirements, source/selector chronology, prior55-case immutable bindings and source/rights obligations. The four signed-zero recipes reflect proposed no-op/stop semantics and must be ratified in the amendment before implementation. All observations remain false.
