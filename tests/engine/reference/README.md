# Original piston and propeller reference calculations

This source-only corpus supports [ADR010](../../../docs/decisions/010-original-piston-profile.md) and [issue125](https://github.com/brettbergin/flight-simulator/issues/125). It covers original engineering inputs, not C172S calibration. No backend output was used to create its expected values.

From the repository root:

```sh
python tests/engine/reference/generate.py --check --model-pack tests/engine/reference/loader-rejected-v2-model
python tests/engine/reference/generate_loader_v1.py --check
python tests/engine/check_model.py --model-root native/fdm_jsbsim/models/original-piston-prop --reference-packet tests/engine/reference/expected-v3.json
python -m unittest discover -s tests/engine -p test_check_model.py
```

Both generators use only Python's standard library and 80-digit Decimal arithmetic. Numeric expectations are decimal strings. Each read-only check regenerates all 55 cases and compares exact serialized bytes. Generation refuses to overwrite an existing packet. Boolean values, branches, identities and ordering compare exactly. Future comparison code must parse numeric strings explicitly and retain tick/sequence integer identity.

The binding revision `expected-v2.json` preserves all cases and budgets from the original pre-solver v1 packet, SHA256 `57a0b8f4ed8fecf9d9ba9a7a8666ec6c80395d90680a4048d5a57e14abd170c9`. That historical revision changed only the source inventory and ledger metadata bindings; its three XML files and numerical parameters were unchanged. Its SHA256 remains `bd2ec9562308dbb950b684018ff924c4f820278400c7a2664f1342f11f049777`. The historic preparation manifest remains byte-for-byte as `reference-manifest-v2.json`; its private preparation paths describe provenance, not required checkout files. Current publication hashes and independent review appear in [source evidence](../../../docs/evidence/P3/original-piston-source.md).

## Separate loader-format binding

The accepted [ADR014](../../../docs/decisions/014-event-aware-shaft.md) identifies a separate loader prerequisite: the original engine XML supplied unsupported `unit="DEGK"`. The active corrected source omits exactly that 12-byte attribute, retaining the raw value 350. All seven rejected-v2 model files remain byte-for-byte in `loader-rejected-v2-model/`. The first command above deliberately supplies that archive to the unchanged `generate.py` (SHA256 `c81596d5e4155463620687d987838294ef0fa39ce32157df15cbc91a7c51ebb7`); its default active-source invocation is no longer applicable. Reproducing historical reference equations does not mean the rejected XML can initialize JSBSim.

`generate_loader_v1.py` is an exact byte import of `tests/engine/reference/generate.py` from preserved commit `c7a2886a9504034ef08e696567510330d2a0df51`, under a separate filename. Relative to the historical generator, only the frozen engine XML hash and default output filename differ. It reproduces the preserved `expected-v3.json`, SHA256 `36aac20d85e841743d7eb9a357be8a0d40d8f103c1cbc60e084dde9ef23db63b`, against the corrected active source. Every non-`model_binding` field, all 55 cases and all budgets equal v2 exactly. Neither generator imports a solver or observes new runtime output.

The active `reference-manifest-v3.json` binds the actual additive generator filename/hash and current reproduction commands. `reference-manifest-v3-historical.json` retains the exact earlier c7a manifest, including its original `generate.py`/README paths and hashes, as historical provenance; those entries are not assertions about current checkout files. The source-only loader correction does not resolve the preserved coupled startup convergence failures, authorize a new shaft implementation/trial, or establish aircraft/pilot/phase acceptance.

## Coverage and budgets

| Cases | Coverage |
|---|---|
| 23 | Clamped linear thrust/load, combustion and mixture tables at knots, interiors and outside endpoints |
| 13 | Pre-update propeller thrust/load, post-update shaft speed, reverse axial flow, separate near-zero floors, signed aligned gyro moments and 60/120/240 Hz discrete updates |
| 4 | Explicit running-branch piston MAP, airflow, fuel, ignition loss, friction and pumping equations |
| 4 | Starter torque at 0/600/1200/1500 RPM, retaining the backend's raw ft·lbf and 5252 scale |
| 7 | Fresh-start RPM strictly above 480 versus running retention at 480, spark and previous-stage fuel flow |
| 3 | Actual partial tank drain, requested-minus-supplied fuel and pre-drain mass-balance phase |
| 1 | Geometry and explicit physical, XML-loader, piston and public SI conversion distinctions |

Use `abs_error <= abs_budget + rel_budget * abs(expected)` for a future binary64 comparator. Frozen absolute/relative budgets are coefficient 2e-12/2e-12; scalar 1e-9/1e-10; force N 1e-7/1e-10; power W 1e-6/1e-10; angular speed rad/s 1e-9/1e-10. These are arithmetic budgets, not aircraft uncertainty or operating limits. Do not shift a branch threshold or hide invalid output under a tolerance.

Propeller thrust and load use pre-update shaft rate; the public shaft observation must use the post-update rate. Near-zero advance uses V/D and a separate load-rate floor. Aligned version1.1/Sense+1 gyro inputs are the backend's inertial angular rates expressed in body coordinates. They are not interchangeable with public Earth-relative body rates.

Piston pressure arithmetic uses 47.88 Pa/psf, distinct from published atmospheric pressure. The XML kg/lb conversion, backend 2.20462 and piston 2.2046 constants remain distinct. Physical inertia conversion is distinct from the approximate loader factor. COMBUSTION is thermal substrate; MIXTURE controls shaft-power efficiency.

## Conditional stage criteria

These criteria require one eligible tank, zero unusable fuel, FuelFreeze=false, no refill/dump/trim and unchanged finite controls. K denotes the accepted switch or final drain tick.

| Trigger | Expected chronology |
|---|---|
| Feed OFF while previously running with fuel flow | Starved=true at K; flow=0 and Running=false by K+1. Shaft may still turn. |
| Final tank draw reaches zero at K | Eligibility precedes drain. Starved may remain false at K, becomes true at K+1; flow=0 and Running=false by K+2. |
| Feed ON while previously starved | Starved clears after current zero-flow calculation at K. New flow can appear K+1. Earliest possible restart is K+2, requiring pre-RPM>480, previous positive flow, spark and current indicated power >=0.125 HP. Restart from a stopped prop is not guaranteed. |
| Mixture zero with prior running and nonzero airflow | Current fuel flow=0, indicated power=-1 HP and Running=false at K; shaft coast is separate. |
| Both ignition switches OFF | Startup clears Running before current power. Fuel may still flow and drain. |
| Pause | No Run, clock, fuel or shaft advance. A truthful held starter request can remain true until a recorded false is applied before the first resumed Run. |

At a partial draw, actual supplied fuel is bounded by the request; the discrepancy is bounded by that same request. Power may use an earlier nonstarved phase. FuelUsedLbs is not an exhaustion-tick tank-decrement measurement. Neither chemical energy nor continuous engine-work conservation is established. Positive CP supplies no aerodynamic windmilling branch. MaxRPM is not an overspeed limiter.

Integrated startup success/latency, stable RPM domain, airframe coupling, fuel-use baseline and convergence require separate limits frozen before the first integrated trial. Preserve failed trials; new designs require reviewed new reference versions rather than retuning these expected values. Aircraft, hardware, pilot and phase acceptance remain open.
