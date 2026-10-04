# Original piston source and reference evidence

Issue [#125](https://github.com/brettbergin/flight-simulator/issues/125), following accepted [ADR010](../../decisions/010-original-piston-profile.md) in PR123/main `50d0b104659768c7ac6a837250af791fd9c42ba6`. This leaf supplies source prerequisites. It does not implement a session, expose engine controls or run JSBSim.

## Frozen artifacts

| Artifact | SHA256 |
|---|---|
| Model inventory | f8ef5011243ef8cf16e13924a5cdc902c2055ba4789a4bfd0cba209533594b7a |
| Parameter ledger | b59fff1d35dbd702392d12cfa4ac9477d9fafa8927454a067e60d06aaaaed24a |
| Aircraft XML | b9a41861fcbca1917978312d73a192cbe2c2ea0e6ef0e13512c76148a6c9d4c5 |
| Piston XML | 0d1b3eb87f1af2131a495c26ae7a3fb2fdd2a38d3d4309c67a77daaff2cf069e |
| Fixed-pitch propeller XML | b4f3f376f062d869a338bb2757466c9ba23d6320d895d3fc5921e351748bb0af |
| Independent expected-v2 packet | bd2ec9562308dbb950b684018ff924c4f820278400c7a2664f1342f11f049777 |
| Decimal reference generator | c81596d5e4155463620687d987838294ef0fa39ce32157df15cbc91a7c51ebb7 |

The [model source](../../../native/fdm_jsbsim/models/original-piston-prop/README.md) retains the project-original airframe/gear/aerodynamics subtrees and authors a separate piston, direct-drive fixed-pitch propeller and one tank. Every effective scalar, unit, table, installation choice and backend approximation has provenance in the ledger. The [rights evidence](../../../third_party/licenses/evidence/original-piston-prop.md) records original MIT source and inherited attribution. No manufacturer aircraft data or model is included.

The [reference corpus](../../../tests/engine/reference/README.md) contains 55 pre-solver cases with frozen arithmetic budgets. The independent reference author did not use model output. Root separately inspected pinned backend equations and units, reviewed every generator branch, and checked selected independent Decimal calculations, strict startup thresholds and supplied/requested fuel arithmetic. Root approved numerical scope only; the reference author independently reviewed the delivery-authored static checker and its 11 corruption guards.

Publication changed inventory/ledger status and corrected an ASCII temperature=-9999 note. All XML, numerical ledger fields, 55 expected cases and budgets remain unchanged from the preserved private candidate. Historic v1 packet SHA256 `57a0b8f4ed8fecf9d9ba9a7a8666ec6c80395d90680a4048d5a57e14abd170c9` and original generator `b15215de424cf42afce39b688c7021eebf650a333d885c973f391bd68d07eeae` remain recovery evidence. The publication generator changes only repository-relative model/default output paths and removes one extra final blank line. No expected value was fitted to observed physics.

Independent final pack/checker review receipt SHA256 `9f9d98a45cf4e8eb75a7ecac486d504fae56d6a9d81bf1001065d701c10bc800`; Root final numerical/binding review SHA256 `7af2ad22a824792f39660ebd9a073eed8052b6fcf2048f4cc8a0a446f234242d`. Their scope is source consistency, exact preservation and branch/unit arithmetic. Review receipts remain local coordination records; all reproducible source/reference inputs are in the repository.

## Verification and remaining work

Local Windows source checks pass: 11 static guard tests, exact read-only reference regeneration and source/reference binding. Foundation CI runs these offline on both supported CI platforms. Scoped LF checkout rules preserve exact source inventories. Generic license auditing checks notice integrity; the model checker separately enforces exact XML/metadata closure and inheritance.

Protected hosted checks and final tracked-source review must pass before merge. No old model XML, runtime pin, native library, bridge, app scene or owner-running game changed. The old default profile and its accepted proofs retain their own identities.

Next work implements native cold tick0, immediate-boundary ignition/starter/feed and mixture, actual shaft/fuel/combustion observations, rejection/fail-stop behavior and bounded coupled runtime trials. Integrated startup success/latency, RPM domain, fuel-use baseline and convergence require limits frozen before first observation. EngineStatus/input/scene consumers and exact exported/replacement proofs follow those gates. C172S applicability, sensed power/indications, calibrated physics, controls hardware, pilot evaluation and owner phase acceptance remain open.

## Consumer loader correction in issue127

The first authorized bounded native suite failed in model loading, before any coupled tick: the pinned backend rejected `unit="DEGK"` on `design-oil-temp-degK`. The historical receipt SHA256 is `60bed0b6b503a8564a7e59323363437600f2a8c328a200b362eac823062e4289`; all nine invoked processes retained identical stderr SHA256 `4acb7efb3205ce64c482ada5a6ff8a73e2571be7c50e5891300f90384ecbc419`. Research-clock and tiny-fuel cases were not reached. This is failed loader evidence, not startup/flight evidence.

Pinned `FGPiston.cpp:242` requests target `DEGK`; `FGXMLElement.cpp:481..529` has no registered conversion for that label and accepts the raw number in target units when the XML unit attribute is absent. The correction removes only that attribute, retaining the authored Kelvin value350. No scalar value, table, world, control schedule, pass/fail target or numerical budget changes.

| Current corrected artifact | SHA256 |
|---|---|
| Piston XML | 4212b398118be77cdff44f6e41abfded7e4fd8fcfece422dba27fd64ad30b638 |
| Parameter ledger | eb471b5590351bee000c346acfa091a2c84ae526540794afe0e23833ca02106c |
| Model inventory | f7766fda173d8ee83d4c4a8c02f6333124175a1f7064d3f4d8e78df3d17da12a |
| Independent expected-v3 binding | 36aac20d85e841743d7eb9a357be8a0d40d8f103c1cbc60e084dde9ef23db63b |
| Current Decimal generator | cfe6e02e11a24f9debdcd86b3aa50e185ae6d6b92ff93952917192dac926bc91 |

The frozen-artifact table above records accepted issue125 history. `expected-v2.json` and its manifest remain exact historical files. Current v3 rebinds only corrected source hashes: all55 cases and budgets compare exactly as JSON values. The checker now requires the implicit Kelvin branch and a twelfth corruption guard rejects rehashed explicit unsupported DEG K syntax even when its ledger/hash bindings are changed. The reference generator/checker and approved schedules pass source-only checks. Model/source metadata and rights/native pins bind the correction; these static results do not assert a successful retry. Remaining runtime gates still apply.
