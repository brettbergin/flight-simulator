# Original interactive model source and rights evidence

Reviewed 2026-10-03. Register component and package ID: `original-interactive-prototype`, version `0.1.0-prototype`. [ADR 006](../../../docs/decisions/006-interactive-prototype.md) defines the bounded combined flight/ground contract. This prerequisite contains original model files and contract evidence; it contains no new native session or Godot consumer implementation.

The exact [three-file package](../../../native/fdm_jsbsim/models/original-interactive/inventory.json) is project-authored content under [MIT](../../../LICENSE). Retain the [full first-party notice](../notices/FirstParty-Interactive-MIT.txt), SHA-256 `ca8c1205d820d40917b54d548b97dde200bc24bc6c3166358e8bc6cc27eb0e9e`. The license permits redistribution of this original content; it does not establish aircraft fidelity, device approval, packaging acceptance or legal rights for unrelated source material.

## Exact source identity and lineage

| Runtime file relative to this model root | Bytes | SHA-256 |
|---|---:|---|
| aircraft/original-interactive/original-interactive.xml | 6151 | 0213ab8c1176e5d20b01f980da9cb94913f3e9ad8866838adc7e77bf3130722a |
| engine/original-synthetic-thrust.xml | 561 | 547581e279e9b3f383422ddff7991b0ff1cef6f02054bf0a979cd6859d9ef073 |
| engine/original-synthetic-direct.xml | 100 | 30c8dbec55a756c71d639aef1cf720decff0ba6730af5ec2062608a08d24d00b |

Canonical LF public inventory is 1380 bytes, SHA-256 **`98b30b5641ce86cc6f0af6298424606aa96a1e4a35ef3e9fcaf377bebb3f00cd`**. That digest is the register's source-revision authority; its branch URL is only a locator. All three XML files byte-match the independently reviewed private investigation. The inventory status now describes engineering-prototype contract content rather than private-unaccepted source; the public inventory therefore has a distinct digest. The private inventory SHA-256 `61c1a7856e4190e5627c52a4ec446db312af57fbacd753fdd7ee0a6998095f91` is retained only as evidence lineage. Neither status grants public runtime acceptance.

The authored combined airframe derives its aerodynamic polynomials, inertia, mass and idealized engine from the historical project-MIT [flight fixture](../../../native/fdm_jsbsim/models/original-synthetic/inventory.json), inventory SHA-256 `1ccadb2e3d5aefe79f5a8f316631744ab4de18084469d2cf1817fb622cfabf7a`. The two engine files are byte-identical copies. Original tricycle gear geometry, spring/damping and material parameters derive from the original project-MIT [cart fixture](../../../tests/ground/fixtures/aircraft/ground-cart/ground-cart.xml), SHA-256 `c546dc4791fc830e6f656b13c7a564322d51fba8f46b43da10af3d2f7ff041a1`. The combined tensor retains flight values 800/1200/1600 **SLUG*FT2**, not the cart's KG*M2 tensor. Both historical source packages are unchanged.

No upstream C172P/C172x model, POH/AFM, manufacturer calibration data, third-party aircraft asset or real-airport data was copied. Source syntax/property identifiers are JSBSim API identifiers; the separately registered JSBSim library remains governed by its LGPL/component policy. Original XML `fdm_config` version `2.0` is a backend format, not a content version or a rights grant.

## Bounded investigation evidence

The [compact proof summary](original-interactive-proof.json) binds the raw source fingerprints, exact model bytes, synthetic prepared surface identity, strict v1 record counts and retained investigation artifacts. Its SHA-256 is `e4691bb69b3027d5c6d45cc76eb5d2578e9fc5d6435a864848a4ae8e437eb750`. Raw private packet SHA-256 is `f0aab13a57fe081323228522670f9bf404a2605e8a91b167a9b928544838873d`; compiled source fingerprint is `195d899990cd87bbd5b7ddce56ccb846288b4ee64f195b71b0b3d7391c8f5bd0`.

The private MSVC 19.40 Release investigation used pinned CMake/Ninja, accepted JSBSim 1.3.1 and the existing v1 contracts. Actual 120 Hz stationary→takeoff→air-control→touchdown→braked-stop ran with one executive and one synthetic plane. Takeoff tick 3755, touchdown tick 7182, stopped all-WOW final tick 8916, final body speed 0.094998056016063329 m/s. The final tick has its own immutable snapshot and atmosphere record. The trace's post-step WOW matches post-step kinematics.

The explicit feedback driver is `scenario.proof` with scenario authority and all 8916 applied commands recorded. It does not represent a human pilot or hidden pilot assists. Repeated states, atmosphere, commands and CSV are byte-identical in this build; 10406 records passed strict v1 validation. Actual 1267 native negative/readback checks cover known-miss retention, unexpected callback/identity/throw disposal, invalid/duplicate input, paused pending commands, scale/resume/event order, off-owner rejection, named-start rejection and a separate 1200-tick trimmed airborne readback case. Independent read-only review reran the checks and full loop with all four traces byte-matching the frozen outputs and verified source/model/lineage/schema/hash evidence.

JavaScript recomputes final speed from the raw final snapshot. The verifier permits `4 × binary64 epsilon × max(1, receipt speed)` solely for the observed one-ULP difference between C++ `std::hypot` and JavaScript `Math.hypot`. This arithmetic allowance was selected after observing that difference; it is not a pre-observation flight/physics tolerance. The actual all-WOW stop threshold remains below 0.1 m/s.

Large raw traces and the private source investigation remain retained review artifacts, identified by the summary's SHA-256 inventory. They are not public runtime implementation or a generally reproducible tracked test in this PR. The subsequent native consumer must reproduce meaningful actual transitions and failure/readback tests with receipts bound to its own final tracked source. No claim of human controllability, full convergence, C172 fidelity or phase-exit acceptance follows from these private results.

## Packaging handoff

The notice audit validates this register entry and exact notice bytes; its generic auditor does not enforce `content_policy`. The new native consumer must reject altered/missing inventory/XML before backend parsing, and delivery must bind every staged model/inventory/notice to these reviewed hashes. Existing portable exports include the historical flight model, not this new package. Extend the relevant release inventory, corresponding-source/DLL replacement/CRT checks and actual exported exercise before distributing a combined consumer. The proof's DLL digest identifies copied bytes, not a loaded-module-path witness or portable release result.

This is an original polynomial flight/gear engineering surrogate. Arbitrary lift/drag/moment coefficients, ideal turbine thrust, gear springs and limits have no Cessna calibration, valid stall/spin envelope, safe-landing score, startup procedure or formal training-credit claim. Aircraft source and pilot evaluation gates remain separate.
