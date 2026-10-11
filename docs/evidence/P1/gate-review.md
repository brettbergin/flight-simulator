# P1 engineering gate review

Date: 2026-10-03. Phase issue [#2](https://github.com/brettbergin/flight-simulator/issues/2).
Status: evidence preparation; phase acceptance is pending the owner review.
This report concerns engineering feasibility with original synthetic models.
It does not validate a C172S, a training device or the later product phases.

## Accepted build and evidence

The current playable baseline is main af705ee990c4100c2ef3c916068aa8ee32f08ef7
from [PR #111](https://github.com/brettbergin/flight-simulator/pull/111),
frozen source37467e8973f11b6b7ae87ec4755cd35d0854c14b. Independent review
verified121 frozen package files,42 exact source bindings,29,415 strict v1
records and native/model/source/license closure. All four protected checks
passed. The exported RTX3090 run supplied59 inspected views,123 drawn frames,
clean worker/audio shutdown,120 separately controlled native ticks and13
actual moving ticks in each chase/orbit fixture. These are bounded interactive
and package checks, not full product performance or pilot acceptance.

[Aircraft/rollout correction](aircraft-ground-ux.md), #108/PR109, fixed disjoint
glazing and clockwise body/wing front faces, added explicit throttle idle and
persistent native-held brake feedback, and retained13 unchanged-model brake
trials. [Motion correction](third-person-stability.md), #110/PR111, adds adjacent
native120Hz visual interpolation and matching body/camera translation. Five
fixed pre-admitted-command cadences30/60/144/240Hz and irregular timing reach
the same120-tick native endpoint/weather/held axes with zero debt and one
exactly-once command. Independently sampled live keyboard input is outside
that equivalence claim. Native/model/contact authority is unchanged.

| P1 exit criterion | Evidence and scope |
|---|---|
| Executable units, state, command, clock and content contracts | [Core contracts](../../contracts.md), #11: closed v1 schemas, typed native boundaries, finite SI values, explicit frames, admission/order/version rejection. |
| Pinned build and portable native loading | [Bootstrap](bootstrap.md) / [native export](native-export.md), #12/#15: locked dependencies, actual exported loading, app-local module/PE/CRT checks, corresponding-source/DLL replacement. Portable empty-PATH tests do not substitute for P7 fresh-user/OS qualification. |
| Seeded numerical runs and fixed integration cadence | [FDM evidence](../../../tests/fdm/evidence.md), #14: original flight fixture, repeatable same-build traces, separate 60/120/240 Hz convergence. The combined model runs at fixed 120 Hz; coupled flight/gear convergence is not established. |
| Single contact authority and missing-data handling | [Ground proof](ground-proof.md), #16: original cart on immutable flat/sloped planes, steering/braking, tile-edge/missing-data and terminal disposal, separate rate comparison. [Combined preview](interactive-preview.md), #95/#98: one native executive through ground movement, takeoff, flight, touchdown and stop on its prepared flat plane. |
| Pause, controls, reset and bounded overload | [Interactive contract](../../decisions/006-interactive-prototype.md) and [preview evidence](interactive-preview.md): actual tick/sequence controls, pause/reset/join, retained wall debt and visible stall/coverage faults. The bounded private preview also proves fixed-command cadence equivalence as described above; production full-range identities, all-scale pacing, lifecycle/origin adoption and reusable scheduling remain #20. |
| Reconstruction or justified fallback | [Save proof](save-proof.md), #17: fresh-process reconstruction of 72,000 original flight-only ticks plus 7,200-tick continuation, exact same-build comparisons and malformed/truncated trace rejection. No combined-model resume, hidden-state checkpoint, durable save, atomic write or migration is claimed. Product save/recovery remains #34/#35. |
| Rights, configuration and validation references | [Validation corpus](validation-corpus.md), #13/#19: configuration-specific target/source matrix, original model provenance and explicit reference gaps. Original fixtures are MIT; dependency terms and replaceability remain separate. The C172S target is not calibrated. |
| Renderer and asset pipeline feasibility | [Renderer proof](render-proof.md), #18: three canonical ten-minute captures each passed all twelve frozen engineering checks and independent packet review. Existing actual Blender-to-GLB scale/orientation/pivot/material/animation, Godot import, origin continuity and rejection evidence remains bound to its source. The compact receipt records hashes, frozen thresholds, retained Godot Forward+ decision and the narrower proxy scope; whole-game and human evidence remain separate. |

The original flight fixture measured `Session::step_fixed` p50 5,300 ns,
p99 12,600 ns and maximum 1,639,100 ns over 72,000 steps. These observations
exclude serialization, rendering and ground contacts. They cannot certify
combined game timing, worker coexistence or input latency.

Historical accepted implementation baselines include #11/PR85 (`0f198616`),
#12/PR84 (`95f1ed41`), #13/PR83 (`e058888e`), #14/PR87 (`33b66a96`),
#15/PR91 (`41995f6c`), #16/PR92 (`76e489af`), #17/PR89 (`278d631e`)
and #19/PR90 (`ab7f3003`). The linked evidence files and retained receipts
identify each fixture's full source/model/build hashes. These separate
experiments are not all executions of the latest combined model.

The combined preview has two explicit ready-to-operate initializations:
ground-ready and airborne-prepared. Its engine is already running. Engine
start, electrical/fuel lifecycle, cold-and-dark procedures and source-based
C172S performance are later work. Earlier references to P1 “startup” mean
solver/application initialization, not an aircraft engine-start procedure.

## Review decision and retained gates

The renderer engineering evidence is complete; aggregate owner review is pending. No P1 epic
closure or dependent phase acceptance is implied by this draft. The owner can assess whether these bounded
engineering results justify product integration. A recorded decision must
identify this scope and its remaining limits.

Production aircraft realism, pilot evaluation, calibrated devices, durable
profiles/saves, full cockpit interactions, sensor behavior, sourced terrain,
real-airport data, weather, lesson evaluation and training qualification
retain their own gates. P2/P4/P7 still own whole-main-thread cost, displayed
frame pacing, authoritative-worker coexistence, input latency, real VRAM
residency and supported hardware measurements. Proxy-renderer results do
not satisfy those targets.

## Next dependency handoff

The next integration queue contains #20 (SIM-LOOP), #21 (INPUT-PROFILES) and #23
(COCKPIT-ASSET) as the first canonical P2 work. The owner's renewed continuous implementation request authorizes preparing these reversible consumers against merged contracts while this aggregate gate remains visibly open. It does not supply pilot evaluation, C172 source rights or later phase acceptance. #20 first consumes the reviewed #112 facade/origin contract for the reusable facade over the accepted native API, copied prior/current
publications, visual-only interpolation, session/fault invalidation, bounded
wall pacing and reset/join/rebase ownership. Its implementation then proves
equivalent authoritative traces at 30/60/144 Hz and jittered rendering.
The native model, 120 Hz and v1 records remain authoritative.

#21 adds remapping/calibration against that accepted interface; #23 keeps
prototype geometry and eye point explicit. #22/#25 depend on #20; #24
depends on #20/#23; #26 joins cockpit, instruments and input; #27 owns the
integrated human exercise. Existing preview slices are useful inputs and
evidence, but do not automatically close those product issues.

### Bounded first-flight frontend dispatch

[ADR018](../../decisions/018-first-flight-briefing-and-circuit-aid.md) proposes two reversible P2 frontend leaves against the accepted interfaces: an in-game paused briefing over the three existing starts, and an optional original synthetic circuit reference for legacy ground-ready/calm/runway36. After the checked contract, accepted issue158 delivery and each leaf's named prerequisites, agents may implement their disjoint leaf files in parallel. One integrator owns shared scene/map/lifecycle/tool changes and joins both in one cohesive dependency-group PR. Actual briefing adoption/discard/lifecycle tests and both leaves' acceptance, exported interaction, independent readability review and protected checks are required before merge. This bounded handoff does not close #2/#3/#21–27, approve source-supported aircraft procedures or replace hardware/pilot and phase evaluation.

### Bounded original audio preparation

The recorded owner authorization permits the reversible [audio contract #187](https://github.com/brettbergin/flight-simulator/issues/187) against accepted SIM-LOOP #20, LICENSE-REGISTER #13 and ordinary-flight layout #178 while aggregate gates remain open. [ADR020](../../decisions/020-original-audio-cues.md) specifies existing-source TAS/engine cues, sample-count synthesis, one Scene-owned master setting and a paused Audio modal. The [implementation child #188](https://github.com/brettbergin/flight-simulator/issues/188) stays blocked until that checked contract is accepted and Root dispatches it. Root owns shared Scene/input/modal/lifecycle and delivery integration; the audio leaf owns its disjoint producer, renderer, panel and focused tests. This partial work keeps #25/#2/#3 and live-caption, load/warning, source, device and pilot gates open. It does not refresh historical P1 package or aircraft claims.

## Bounded aircraft source-preparation handoff

[Issue #169 — C172P source assessment](https://github.com/brettbergin/flight-simulator/issues/169) records a [conditional maintained-model candidate](../P3/c172p-candidate-assessment.md) and [metadata-only identities](../P3/c172p-candidate-source-index.json). Accepted #13/#19 foundations permit this source preparation while aggregate gates remain open. Exact certified configuration, POH/normal references, recursive host/license closure and a separate runtime contract remain prerequisites; no aircraft is imported or adopted. Existing original-model evidence and selected C172S work are preserved. This paragraph does not refresh historical package claims or accept #2/#3/#4/#28/#76, hardware/pilot/training or phase gates.
