# Native-truth reading references

These original synthetic fixtures test the pure [ADR009](../../docs/decisions/009-cockpit-readings.md) reading leaf. They establish no native aircraft, sensed instrument, hardware, GPU, pilot or phase qualification.

`reference.json` is byte-identical to the 35-case v2 packet frozen before consumer observation: SHA256 `413eb124254432f8b39d7079b773d14e276415aa54749de3a1d85e527bf70aae`. [Preparation manifest](preparation-manifest.json) and [preparation notes](preparation-README.md) preserve the earlier 31-case v1 lineage, five direct runtime recipes, original generator hash and unchanged budgets. The historical `consumer_source_observed=false` flags describe reference preparation, not later test execution.

The promoted generator retains the original Fraction/libm formulas and every numeric input/reference. Its only changes are a repository-relative invocation, pinned preparation-contract identity and read-only byte/hash checking; it never overwrites observed-output goldens. The preparation contract hash stays historical when documentation changes. From repository root:

```text
python tests/instruments/generate_reference.py --check
node tests/instruments/validate_inputs.mjs
```

The schema validator checks the 58 nested v1 records, including explicitly bad coordinate/duplicate-ID inputs. It observes no reading consumer and writes only its diagnostic `input-validation.json`.

`instrument_checks.gd` exposes synchronous `static run()->Dictionary` and calls the actual `NativeReadings.from_readback(Variant)`. Runtime staging must place this directory at `res://instrument_tests` and the leaf at `res://cockpit/instruments/native_readings.gd`, with the accepted Wire/UInt64/Frames helpers. Godot JSON decoding restores only the declared complete-fixture `input.debt_quanta` integer path under an exact guard. Direct float-debt invalidity is reintroduced afterward; decimal tick/session identities are never converted. The fixture additionally checks closed output types/units, null identity/unavailable reasons, copies, repeated same-input calls and structurally invalid variants. Display conversions are compared against frozen SI-to-display references; actual drawings need their own integration/visual evidence.

Allowances remain SI absolute `2e-12`, radians absolute `2e-12`, display absolute `2e-9`, relative `4e-15`; comparisons use max(absolute, relative*abs(reference)). These bound scalar arithmetic only, not simulation convergence or aircraft realism. The frozen singularity threshold is `1e-6` and is tested by the two vertical attitude fixtures. A fingerprint of 64 f characters is fixture metadata, not a loaded-module witness.
