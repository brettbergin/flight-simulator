# Original piston native work in progress

Issue [#127](https://github.com/brettbergin/flight-simulator/issues/127), implementing the opt-in original engineering profile from [ADR010](../../decisions/010-original-piston-profile.md). This evidence records useful native behavior and an unresolved research gate. It does not accept the feature, publish a playable profile, close issue127 or claim C172 fidelity, pilot evaluation or a phase gate.

## Source and frozen trial

Base model source landed in PR128/main `ad24168c4266f1e3fc2b59f997781628ea40a50d`. The corrected source inventory is `f7766fda173d8ee83d4c4a8c02f6333124175a1f7064d3f4d8e78df3d17da12a`; the [source evidence](original-piston-source.md) records the unsupported unit attribute correction and preserved historical v2 corpus. The current [v3 reference](../../../tests/engine/reference/expected-v3.json) binds corrected loader metadata with all55 numerical cases and budgets unchanged. The source-package marker remains historical unvalidated source status; it is not a claim that subsequent trials were never attempted.

The frozen [native limits](../../../tests/engine/native-limits.json), SHA256 `9b667d4b61e47e94af1eed20701119bd72d6de63e6eac28b8597ab44ae6d9feb`, specify cold preparation, exact open-loop control schedules, source-stage fuel/shaft observations, engineering targets, convergence frames/events and a separate tiny-fuel mechanism fixture before observations. Limits were independently reviewed and ratified before execution. No parameter, schedule, expected value or budget was changed after observed output.

The reviewed corrected source candidate has 40 declared LF-normalized native fingerprint inputs, fingerprint `3f58b62a6f490677557dd9a56f1ad0583a25a26b333e90c202d1e729666b81f5`, and 56 source/metadata bindings. Local candidate receipt SHA256 `00c4bd68766ddf6a85b598e971939f8a0816e2aa22ce80a6e01c4ad91362d3b0` was independently verified before the corrected trial. Compiled first-party code used pinned MSVC19.40.33813 `/MD` and warnings as errors, with independently hash-verified existing pinned JSBSim/godot-cpp libraries in a separate private output. This compilation is narrower than a complete canonical dependency rebuild/export proof.

Native implementation preserves the old default/two-argument bridge selection, axes-only capabilities and original model closure. The new profile checks its seven-file source closure and one-piston/direct/fixed-prop topology, uses fresh IC running flags false, performs no `InitRunning`, trim or hidden positive tick, and publishes actual post-prop shaft/running/fuel state. Four strict boolean pilot system commands share the existing admission sequence and apply at the next unexecuted boundary. Mixture is an admitted axis. Completed snapshots retain actual applied truth; a failure destroys the executive and retains the previous owned publication. Read-only diagnostics expose source-stage quantities to the native tests, without a production mutation interface.

## Actual corrected trial and known failure

One authorized corrected suite invoked all12 processes successfully, retaining complete snapshots, atmosphere/stage diagnostics, commands, stdout/stderr and process statuses. Suite receipt SHA256 `87ad6b630c872ed102e694bbbb93c3d9a9ee2405912b3f37b1359caa1f5a27d2` records **1,618,553 checks with two failed checks**. This is an overall failed research gate.

| Observation | Result |
|---|---|
| 120Hz cold-start first Running | 4.2416666667s |
| First Running at60/120/240Hz | 4.2666666667 / 4.2416666667 / 4.2291666667s |
| 120Hz first stopped after braking at39s | 39.3333333333s |
| 240Hz accumulated world path | 8.2834984521m |
| Tiny fixture actual versus requested first draw | 0.0000001kg / 0.0000044284172kg |
| Tiny fixture Starved atK/K+1, Running atK+2 | false / true / false |

Admission/type/authority/current-boundary rejection, same-build replay, pause/retained truth, no-spark/no-feed/mixture-zero negatives, actual starter release, warm running, run-up, taxi/braking, three causal shutdown variants, post-prop publication, pre-drain mass/fuel stages and the separate tiny-fuel mechanism met their frozen targets. These prototype observations are not manufacturer operating limits or aircraft calibration.

The shaft agreement budgets fail during early starter engagement:

| Time | 240Hz shaft rad/s | 60Hz absolute error / budget rad/s | 120Hz absolute error / budget rad/s |
|---|---|---|---|
| 1.1s | 3.7062037449 | 0.6861320803 / 0.4318117349 | 0.2279004233 / 0.2159058675 |
| 1.2s | 6.5535797592 | 0.6586076962 / 0.6026542958 | 0.2186705893 / 0.3013271479 |

These are the only eligible failing samples and the largest absolute shaft errors over the entire comparison. Refinement inequality passes at both times, and all other eligible shaft samples, world position/velocity and event-time checks pass. Source-bound diagnosis receipt SHA256 `e985dc264056e0f100768899e0d48aad7f7c25a352238bf09eddaf8f168ded97` records the full error basis and first crank steps.

Commands after completedt1 apply at61/121/241 for60/120/240Hz, exactly the next tick. Source inspection found no extra run, wrong units or cached-RPM publication error. Pinned FGPiston uses `torque*max(RPM,1)/5252` starter power, and FGPropeller changes from a divisor of1 to actual angular speed at its near-zero threshold before an explicit discrete torque update. These floor/branch effects produce rate-dependent early transients. This is evidence of an unmet engineering hypothesis, not justification to relax the budget or inject RPM. Resolving the gate requires separately reviewed numerical work; unchanged failed evidence remains authoritative meanwhile.

## Regression and remaining work

Source checks pass: 12 static model corruption guards, all55 reference regeneration/source bindings, frozen schedule/header reproduction, documentation/license integrity and synthetic failed-process reporting. The latter preserves nonzero process exit codes, skips dependent comparisons and requires complete nonempty traces for determinism. The original first unit-loader failure remains preserved separately; no empty-trace equality is accepted as deterministic physics.

The isolated legacy `interactive_loop` and `interactive_negative_readback` CTest cases pass with the new native source and old profile. A private wrapper required explicit source/model paths because CMake's reserved source-root variable resolves to that wrapper; the initial missing-path harness failure is retained and was not a physics failure. Canonical full-build/remaining legacy CTest proof, input/facade/status/scene integration, exported and source-replacement proof, hardware/device evaluation and visual paused-state proof remain distinct gates. No accepted cached native output, owner-running game or legacy model asset was overwritten.

The unresolved research gate prevents an accepted feature merge or published playable new profile. Draft consumer preparation may exercise the already-observed 120Hz behavior while retaining this failure and prototype labeling. C172 applicability, sensors, electrical/thermal procedures, realistic propeller windmilling, calibrated performance and owner phase acceptance remain open.
