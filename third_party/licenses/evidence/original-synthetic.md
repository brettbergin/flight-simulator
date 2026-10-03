# Original synthetic model rights evidence

Reviewed2026-10-03; component ledger ID`prototype-aircraft`, model ID`original-synthetic`, package version`0.1.0-prototype`. The exact three [original model files](../../../native/fdm_jsbsim/models/original-synthetic/inventory.json) and source parameters are authored for this project under [MIT](../../../LICENSE). The [full notice](../notices/OriginalSynthetic-MIT.txt) has SHA256`ca8c1205d820d40917b54d548b97dde200bc24bc6c3166358e8bc6cc27eb0e9e`. XMLfdm_config`2.0` is a backend format version, not a product/content version.

The original project-authored numerical probe was renamed and its ignored duplicate engine geometry removed. No upstream C172P/C172x XML, POH pages, manufacturer calibration data, third-party visual/geographic content or real-aircraft procedure was copied. JSBSim syntax/property identifiers describe the backend API; library rights remain separately governed by the JSBSim register entry. This narrow original-content grant is independent of fidelity/export/phase acceptance.

| Runtime file relative to model root | Bytes | SHA256 |
|---|---:|---|
| aircraft/original-synthetic/original-synthetic.xml | 4691 | e271188986517f459197bb2a4573d5e912a1eeb31e9ad92593ed0ab43424136c |
| engine/original-synthetic-direct.xml | 100 | 30c8dbec55a756c71d639aef1cf720decff0ba6730af5ec2062608a08d24d00b |
| engine/original-synthetic-thrust.xml | 561 | 547581e279e9b3f383422ddff7991b0ff1cef6f02054bf0a979cd6859d9ef073 |

Canonical LF inventory is782bytes, SHA256`1ccadb2e3d5aefe79f5a8f316631744ab4de18084469d2cf1817fb622cfabf7a`; this is the source revision authority. The branch URL in the register is a locator, never the integrity authority. Native compiled pins and independent Node inventory checks reject changed model bytes before backend parsing. The license audit validates notice integrity; #15 must additionally bind every staged model/inventory/notice to this reviewed component policy.

Parameters are original six-axis numerical polynomials with idealized turbine/direct thrust and fuel consumption; no piston/propeller/C172S calibration, contact/stall envelope or procedure validity is claimed. [Model scope and equations](../../../native/fdm_jsbsim/README.md). Separate [asymmetric mass test XML](../../../tests/fdm/models/aircraft/asymmetric-cg/asymmetric-cg.xml) is also original project-MIT analytical test content, excluded from the runtime three-file model inventory. Its KG/IN weighted-CG expectations were frozen independently before backend traces. Field origins and exact conversions are explicit in the contracts and tests.
