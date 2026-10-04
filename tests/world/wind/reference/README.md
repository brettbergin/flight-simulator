# Private independent steady-wind reference packet v1

Status: proposed, preconsumer, unratified. ADR013 is still proposed at the bound commit. Contract merge and coordinator ratification/dispatch are required before promotion or implementation observations. No Godot, native, model, GPU or actual aircraft output informed these targets.

The original MIT generator uses Fraction rational arithmetic, Decimal110 square roots and a convergent Machin atan series for pi, then independently rounds Decimal targets to little-endian binary64 with Python struct. Its working precision exceeds the original design's Decimal90 minimum; numerical comparison budgets,22 recipes and8 runway expectations are unchanged. This is arithmetic reference preparation, not a new operational schema or a certified transcendental-error bound.

- Four profile vectors: exact SI foot381/1250,5m/s6250/381ft/s and4500/463kt, FROM cardinal angles and declared fixed-anchor EUS[E,-D,-N].
- Six signed-zero/tiny recipes: exact cardinal bits, positive min-subnormal and squared-norm underflow cases; diagonal within4ULP and speed strictly positive. No ordinary absolute tolerance can accept zero for nonzero wind.
- Twelve asymmetric body-to-NED/ground-minus-wind cases: exact rational quaternion rotations and squared norms, Decimal norms, wind-independent ground/vertical speeds.
- Eight reciprocal runway interpretations: exact headwind/right-source signs; changing runway never changes wind.

The pure direct-unit budget2e-14m/s (intermediate2e-13ft/s), ordinary pure1e-12m/s/rad, asymmetric2e-12m/s and exact/tiny criteria remain separate from the NEW proposed native nominal agreement criterion1e-6m/s/component. The latter is an engineering acceptance target at actual RunIC/posttrim/admitted completed publications, not a certified libm bound, a direct-unit tolerance or a change to earlier physics/trim/convergence budgets. There is no backend proof here.

Run `python generate.py --check` to regenerate in memory and compare every frozen byte. This command is read-only; a mismatch fails. `--write-new` uses exclusive creation and refuses an existing packet. Neither mode imports or invokes a consumer. The manifest binds original generator/expected bytes and reviewed proposed contract/designs. Preserve all earlier draft/design/review artifacts.

No complete Readback or published native identity is fabricated. Source-qualified consumer/type/lifecycle/copy/invalid-state and actual six nonzero profile/start checks require later separate dispatch. These references establish no C172 calibration, aerodynamic response, handling, pilot acceptance or training credit.
