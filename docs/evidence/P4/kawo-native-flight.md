# KAWO native startup and contact evidence

On 2026-10-19, six selected headless native CTests passed against the KAWO prototype payload and the existing original interactive aircraft. After adding explicit final-contact assertions, the targeted journey executable was rebuilt and its two KAWO startup/contact tests passed again; the four earlier regression results remain separate historical observations. The geographic path loaded the fixed pack, initialized an actual JSBSim Session, exercised the resident-grid callback, and completed 240 fixed steps at 120 Hz. These are bounded startup and two-second ground-contact observations, not a KAWO flight, airport operational acceptance, or aircraft validation. [Issue #261](https://github.com/brettbergin/flight-simulator/issues/261) tracks the runtime integration.

The governing interface is the [resident KAWO runtime contract](../../contracts/world/kawo-runtime-v1.md), accepted at `65d448034196df7de20b882f230803acf670a431`. The [terrain compilation evidence](kawo-terrain-compilation.md) covers the earlier offline payload checks. This record concerns the subsequent native consumer; it does not replace those checks.

## Actual build and content

The fresh x64 RelWithDebInfo build used MSVC 19.40.33813.0, C++20 and the dynamic Microsoft runtime. Actual commands used `/fp:strict` for PreparedWorld, Session, all three resident-grid implementation translation units, and the production interactive bridge/worker. Disabling unnecessary module scanning removed their formerly empty production response files. Actual archive members matched all five object artifacts, and the bridge linker consumed both interactive and resident-grid archives.

| Identity | SHA-256 |
| --- | --- |
| Interactive source fingerprint | `a4ec21a8729a996f1f003bcd43c612fc28f8329ee02fcf990cd40e5b75f5aac9` |
| Interactive build controls | `da143795701f16d0bbba56f094ce92c765222fd88e861ae90c13a99fe3062f9f` |
| Resident component digest | `c8fb140ab69366329aab125cfb021255a74a8be982bf0750b956871f0d69cf8c` |
| Bridge DLL | `10f7810e3046dc5863dd696eb3b6cfc60c811cb2f3ae5b5e2f3042fff99e2b35` |
| KAWO journey executable after assertion-only rebuild | `bdd3c38708f5a52f0d2d5d8459fbd29c68c6354b2d5e05d2f806b47bdd7c8be9` |
| Journey test source | `68abefaafbadea2b6713b8f9dc27cd216d1b8fed504b77e373edb8c576a938fa` |
| KAWO readiness executable | `b89c7f9360b7dff4608320808a744e0596272a6ed5d6a659850082a4a6ef010b` |
| Ground payload | `b2c53308fdc427900d84b541aff51ba66cbb71bc483fcee0ea16d067dbd15cfb` |
| World manifest | `939b1436943a9677407ad0edb03fb5a638bce2880d9f98d7b1452b7222c4269c` |
| Ready-runway-34 recipe | `05cb113c22168c15c27065732c2b10273de5f24400cff47cbcda973e208d6d0f` |

Four original configure/build source-and-tool snapshots were byte-identical. The initial six-test launch separately sealed the actual build binaries, staged model/pack files, and pinned CTest executable; its before/after snapshot SHA-256 was `5c1d61366fcc906e9778039a93ac87b7fd7861aba808520fa87060b420e7e4bb`. It joined with exit code zero in 9,870 ms outer elapsed time; CTest reported 9.50 seconds.

The assertion-only targeted rebuild also passed with unchanged source/tool snapshots (`5e5b425a4281007f1aff8135821b11b72d2b9fc7a0f4c5244e4a207680bccdaa`). Its actual journey compile remained `/fp:strict`. The fresh two-test rerun sealed the new executable and the same pack/model/CTest inputs, with equal before/after snapshots `d7292f8c8c1f4fbd3263f47912ea1d151a68af4863f3b2c995d27bb22ece8a26`. It joined with exit code zero in 8,231 ms; CTest reported 7.86 seconds. Both launches used isolated environments with `JSBSIM_DEBUG=0`. No production numerical source or source-reference value changed for this rerun.

## Checks and observations

| Selected CTest | Actual result and scope |
| --- | --- |
| `interactive_loop` | Initial run: existing synthetic scripted combined trial passed: takeoff, touchdown, final tick 8,916. This is a separate synthetic world, not a geographic KAWO circuit. |
| `interactive_negative_readback` | Initial run: existing output reported 75,761 steady-wind checks and 85,568 interactive negative/readback checks passed. |
| `interactive_apron_starts` | Initial run: 339 existing apron checks passed, preserving eight old starts and one newer start. |
| `kawo_readiness` | Initial run: 179 parser/predicate and actual shared-operand parity checks passed. Synthetic readiness controls remain distinct from whole-world operational validation. |
| `kawo_startup` | Fresh rerun: 61 checks passed at tick zero; 17 installed geographic callback queries were observed. The initial run also passed 61 checks. |
| `kawo_ground_contact` | Fresh rerun: 310 checks passed, including 240 completed fixed steps, an exact final tick of 240, and nine explicit final-contact checks. Callback queries increased from 17 to 1,937. The initial 301-check run preceded these assertions. |

The [native journey source](../../../tests/interactive/kawo/journey.cpp) binds the exact independently frozen start-reference words, checks actual startup ECEF/anchor coordinates, the full rotation matrix, zero velocity/rates, original model method, held ready-state controls, and all nine source-derived nominal gear-arm words. It rejects crossed geographic/synthetic bindings, unsupported starts, wind and angular overrides. It also exercises copied worker replies, historical publication after Session close, and refusal of calls after the worker joins. Actual initialization uses the runtime Session path, including its zero-time RunIC initialization; this is not a claim that JSBSim never invokes its internal Run routine during RunIC.

The retained tick-zero snapshot has fuel 100 kg, zero body velocity/rates and three initially unloaded gear contacts. The strengthened 240-tick test asserts final live/valid ground readback, valid snapshot/orientation, exactly three contacts, and each gear weight-on-wheels with a finite body force whose finite NED projection has a negative down component (upward support). These are sign/validity/contact assertions, with no tolerance fitted to the first run.

After two seconds with the ready-state brakes held and throttle zero, the fresh final snapshot also shows body speed below 0.000002 m/s and fuel approximately 99.90434 kg. Speed and fuel here are observations, not asserted settling or consumption budgets. The test does not establish a braking distance, force-magnitude acceptance band, or a full settling envelope.

## Retained bindings and limits

The fresh two-test receipt is bound by raw SHA-256 `b41ba9409779bb7d87fe030df8880c11fa833d45780971257b845e82476b2c31`; stdout is `d2301ae4bdb57fb662d4124998b066ccc858fbece0c066857a5a78de17d44702`; its two-test LastTest.log is `3b072596e78a781a428bae324df609532892184094c20a35e85c68a9323a16a6`. The targeted rebuild receipt is `ecc0d0f6c521e46c380c1291d5026bba37ecb8c20493a61ae532dc0a01d3ee1b`.

The initial six-test receipt remains `b99abdd4caefe80a8e7d53e46e29e6560fa0c3928b5b43e03f045186f871f4be`, stdout `380031eff65a17e03ec945324d7c0ddf1db774d4501d6c22d5476dca0b84c697`, and historical six-test LastTest.log binding `bb4187dfb0fbd1172918f783e19f35ec8915f16e3eaf89f6b4e1fb0c1b94a061`. The current CTest log contains the newer two-test rerun. The original initial receipt/stdout, rebuild/rerun records, and machine-specific artifacts remain retained separately.

The aircraft is an original synthetic prototype, not a validated Cessna variant. The geographic working frame remains approximate, source realization/epoch and total 3D accuracy remain unknown, and canonical ellipsoid height is not validated MSL/barometric altitude. This run does not establish KAWO taxi steering, braking distance, takeoff, landing, a circuit, long-duration stability, weather behavior, installed-game rendering/UI, package identity, or pilot evaluation. Those remain separate gates; no aircraft-fidelity, navigation-suitability or training-credit claim is made.
