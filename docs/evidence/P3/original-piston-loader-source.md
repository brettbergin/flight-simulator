# Original piston loader source amendment

Source-only prerequisite for [issue127](https://github.com/brettbergin/flight-simulator/issues/127), following accepted [ADR014](../../decisions/014-event-aware-shaft.md) and the historical [issue125 source publication](original-piston-source.md). The exact final source/reference/rights review and protected CI must pass before this amendment merges. It does not implement cold-start controls, repair time-step convergence or qualify a playable engine.

## Correction and source identity

Pinned JSBSim 1.3.1 commit `3b25f25e49b42d0489c04ac805674fc1450ca579` reads `design-oil-temp-degK` as constructor-unit Kelvin, but its generic XML conversion lookup rejects the original nonempty supplied `unit="DEGK"` attribute. The only XML change removes those exact 12 bytes; the value remains 350, all other engine parameters remain unchanged, and aircraft/propeller XML bytes remain exact. No vendor parser changes or parameter fitting are included.

The active seven-file model is the exact preserved corrected source from commit `c7a2886a9504034ef08e696567510330d2a0df51`, with model ID `original-piston-prop-v1`, version `0.1.0-prototype`, and backend `original-piston-prop`. This is a source-format revision of the original engineering prototype before its first accepted runtime implementation; no playable piston release is upgraded. Exact hashes, rather than identity/version alone, distinguish rejected and corrected source. Runtime admission must bind the corrected inventory explicitly.

| Artifact | SHA256 |
|---|---|
| Archived original inventory | f8ef5011243ef8cf16e13924a5cdc902c2055ba4789a4bfd0cba209533594b7a |
| Corrected inventory | f7766fda173d8ee83d4c4a8c02f6333124175a1f7064d3f4d8e78df3d17da12a |
| Corrected ledger | eb471b5590351bee000c346acfa091a2c84ae526540794afe0e23833ca02106c |
| Archived original engine XML | 0d1b3eb87f1af2131a495c26ae7a3fb2fdd2a38d3d4309c67a77daaff2cf069e |
| Corrected engine XML | 4212b398118be77cdff44f6e41abfded7e4fd8fcfece422dba27fd64ad30b638 |
| Historical v2 expected packet | bd2ec9562308dbb950b684018ff924c4f820278400c7a2664f1342f11f049777 |
| Corrected-binding v3 expected packet | 36aac20d85e841743d7eb9a357be8a0d40d8f103c1cbc60e084dde9ef23db63b |
| Preserved original v2 generator | c81596d5e4155463620687d987838294ef0fa39ce32157df15cbc91a7c51ebb7 |

The source README and ledger explain implicit Kelvin; inventory and the matching original-MIT rights entry bind those exact metadata bytes. The package's historical preparation marker `unvalidated-no-backend-trial` remains unchanged and must not erase historical private failures described by ADR014. Those historical corrected-loader observations failed coupled convergence; this source-only amendment makes no new solver observation or retrospective claim of runtime acceptance.

## Preservation and independent references

All seven original model files are archived byte-for-byte at `tests/engine/reference/loader-rejected-v2-model/`. The original `generate.py`, `expected-v2.json` and `reference-manifest-v2.json` remain unchanged. Historical generation uses the explicit archived model argument rather than the active corrected directory. The additive `generate_loader_v1.py` reproduces v3 for the active model. All 55 cases, equations, expected numerical values, arithmetic budgets and nonbinding metadata are identical between v2 and v3; only top-level `model_binding` differs.

The historical v3 preparation manifest is preserved separately. The current v3 publication manifest binds the actual additive generator filename and bytes, the reproduced expected packet and corrected source, so its chronology cannot silently claim the original generator was replaced. These calculations use Python standard-library Decimal arithmetic without importing a solver or observing model output.

## Verification and remaining gates

The static checker requires no supplied oil-temperature unit. A new corruption guard reinjects `unit="DEGK"`, updates the ledger's unit and rebinds all inventory hashes; rejection must therefore reach the unit policy rather than merely detect stale bytes. Together with the existing guards, 12 source tests cover exact closure, scalar policy, topology, tables, inherited geometry and metadata. Explicit UTF-8 fixture reads preserve non-ASCII provenance on Windows.

Foundation CI checks both read-only reference routes and corrected-model/v3 binding. Reproducible commands, from the repository root:

```sh
python tests/engine/reference/generate.py --check --model-pack tests/engine/reference/loader-rejected-v2-model
python tests/engine/reference/generate_loader_v1.py --check
python tests/engine/check_model.py --model-root native/fdm_jsbsim/models/original-piston-prop --reference-packet tests/engine/reference/expected-v3.json
python -m unittest discover -s tests/engine -p test_check_model.py
node tools/check-docs.mjs
node tools/license-audit/audit.mjs --dependency-lock third_party/dependencies.lock.json
```

Passing these checks establishes source/reference integrity only. Independent final source/reference/rights review and protected CI remain required for merge. No new method output, JSBSim library modification, cold runtime, exported executable or owner game is produced or changed here. The next gate binds the actual reviewed stable arithmetic implementation, patch/materializer, corresponding-source closure and unchanged pretrial criteria before any new method observation. Input/engine-status/UI integration, exported and replaced-DLL proofs, C172 applicability, hardware, pilot and phase acceptance remain separate.
