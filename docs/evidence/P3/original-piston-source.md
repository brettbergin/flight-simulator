# Original piston source and reference evidence

This record describes the historical issue125 source revision. Its exact seven-file model is preserved under `tests/engine/reference/loader-rejected-v2-model/`; the active model's subsequent format correction and source-only admission are recorded in the [loader amendment](original-piston-loader-source.md). The historical hashes and verification below are retained as chronology, not claims that the original XML initialized successfully in JSBSim.

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
