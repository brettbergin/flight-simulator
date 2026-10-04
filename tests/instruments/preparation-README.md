# Independent cockpit reading references v2

Private pre-consumer packet, prepared before inspecting/importing NativeReadings consumer source or outputs. v1 remains byte-for-byte frozen; v2 appends four narrow references requested in source-independent review. This is a test-reference preparation packet, not aircraft, sensor, native binary or phase acceptance.

30 complete JSON Readback cases plus five direct runtime recipes (35 total). The original 31 references and all numeric tolerances are unchanged. New cases require whole-invalid ReadingSet with null identity and all nine channels null: finite valid-wire velocity x=1e308 whose squared norm overflows binary64; live+paused contradiction; non-hex source fingerprint; TYPE_FLOAT debt counter. The first two are complete JSON fixtures. The last two are direct runtime mutations, intentionally outside parsed JSON fixture normalization.

All 58 nested AircraftSnapshot/AtmosphereSample input validations passed the accepted full schema plus semantic validator with the documented deliberately invalid coordinate/duplicate-ID exceptions. This verifies input validity only, not a nonexistent consumer. The overflow snapshot is valid wire input: each component is finite. Its mathematical squared norm is 1e616, outside finite binary64; no normalization/saturation/per-channel salvage is allowed.

Numeric budgets frozen in v1: SI scalar absolute 2e-12, radians absolute 2e-12, display absolute 2e-9, relative 4e-15, singularity threshold 1e-6. Compare max(applicable absolute budget, relative*abs(reference)). Fraction arithmetic supplies rational rotations and squared norms; Python libm supplies final scalar transcendental operations and independent WGS84 placement. The fixture fingerprint f repeated 64 times is structurally valid research metadata only, not proof of loaded native binary authority.

## Eventual Godot driver rule

Godot JSON parsing produces floating numbers. Restore only each complete fixture's known `input.debt_quanta` integer counter path, with an explicit exact integer/type guard. Do not recursively normalize numbers. Apply direct float-debt-counter mutation AFTER that fixture restoration, setting 0.0 as TYPE_FLOAT and requiring whole-invalid output. Never cast tick/session identity to a floating number; full uint64 tick remains the original decimal String. Direct malformed-fingerprint mutation must set 64 non-hex g characters. These direct mutations need actual driver assertions, not JSON schema substitution.

## Reproduce preparation

From the assigned repository root:

    python .local/cockpit-independent-next-v2/generate_reference.py
    node .local/cockpit-independent-next-v2/validate_inputs.mjs

No NativeReadings import, native solver run, GPU run, pilot data or tracked consumer writes occur. Parent reference SHA256: 440e7949c209c7a52d1d5498c9fe9b9bd6e9e49df47e45581d062a36cda44c35. Parent manifest SHA256: 42336c6efd3f5f4086f17e7dd2b89c219f882fb1f044d5a1f85abb052629e6bc. All parent inventory hashes were rechecked unchanged when sealing v2.
