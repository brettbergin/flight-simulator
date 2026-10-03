# P1 original-flight reconstruction evidence

Issue [#17](https://github.com/brettbergin/flight-simulator/issues/17), [ADR-004](../../decisions/004-persistence-and-replay.md), [runnable proof](../../../native/persistence/proof/README.md).

This record concerns the original synthetic numerical fixture, not C172S fidelity or complete application resume. A fresh process reconstructs72000 fixed120-Hz steps from requested initialization and original receiving-boundary admission records, then continues7200 steps. The same-build equality criterion was selected before measurement: every-step canonical aircraft/atmosphere/diagnostic digest, checkpoint/final state, applied commands, sampled continuation, initialization and admission/event histories must match exactly.

The original arrival order deliberately differs from execution order; two commands remain pending at the save boundary and both apply once after reconstruction. Late source registration, original lifecycle sequences77..81, pause/resume, time scales, fuel consumption and source gates are exercised. Native corruption, identity, version, truncation and semantic negatives plus Node cross-file declaration checks fail closed. The experiment also detected and corrected an OperationalEvent serializer defect: its time-scale payload uses the accepted event spelling `time-scale`; SessionControl uses `time_scale`.

Local Windows11 x64, MSVC19.40.33813.0, pinned CMake3.31.8/Ninja1.13.1/JSBSim1.3.1: the first complete run matched exactly, rejected1939 native negative cases, accumulated595.4573ms for the72000 reconstruction solver steps, and took5328ms for initialization/reconstruction/hashing/traces plus the60-second continuation. These are observed costs on the reference machine; the30-second engineering budget is provisional. The final checked-in [compact Windows receipt](../../../tests/replay/windows-proof.json) identifies its actual executable/library/model/contract/source hashes; reruns and CI produce their own receipts rather than require another build's binary hash.

After the Linux compiler identified ambiguous single-line control flow, explicit braces were added without changing the replay behavior. The Windows rebuild passed all five native tests; its refreshed receipt retained the same checkpoint and continuation trace hashes, with600.3553ms reconstruction solver time and5371ms total proof time.

Capability matrix:

| State | Result and boundary |
|---|---|
| Original synthetic flight integrator and ideal engine/fuel/mass | Reconstructed through all steps; measured continuation exact within one identical build |
| Constant dry ISA atmosphere, full seed identity | Reconstructed; no stochastic weather is enabled, so RNG continuation is not claimed |
| Original registered sources, admitted/pending commands, held axes | Re-admitted at original receiving boundary/order, gates and pending execution verified |
| Original pause/time-scale lifecycle and observed events | Original input sequences retained; event sequences remain independent |
| Ground contacts/terrain, tire/strut and moving surfaces | Unsupported, require separate reconstruction evidence after #16 |
| Real C172S engine/propeller/electrical/sensors/failures, ATC/procedures | Unsupported; absent from this fixture |
| Wall-budget debt/fractional cadence, queues/render/worker state | Unsupported; only a fixed-step caller is exposed by this proof |
| Durable user saves, crash recovery, migrations, unlimited streaming histories | Unsupported; later persistence/runtime issues own these |
| Complete hidden-state checkpoint/visible snapshot teleport | Not implemented or advertised |

Existing public SessionManifest/v1, ReplayHeader/v1 and Checkpoint/v1 layouts remain unchanged. Their `replay-from-start` capability is bound to evidence `p1-original-fixed-step-reconstruction-v1`, exact identities and canonical cut. No blanket `complete-checkpoint` declaration is accepted. Product resume remains reviewed safe restart checkpoints until the integrated runtime proves a paused/drained boundary and all participating subsystems. There is no playable save UI or training-credit claim.
