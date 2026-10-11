# Paused cockpit lookout views

Status: implementation in progress under [issue215](https://github.com/brettbergin/flight-simulator/issues/215). The [ADR025 contract](../../decisions/025-paused-view-presets-and-comfort.md) merged in [PR214](https://github.com/brettbergin/flight-simulator/pull/214); decimal admission merged in [PR211](https://github.com/brettbergin/flight-simulator/pull/211). No camera consumer or exported view result is accepted by this reference-only commit.

The [independent reference packet](../../../tests/camera/README.md) preserves 132 original preconsumer direction, settings, lifecycle and smoothing references. Its original expected bytes and generator are unchanged. Source binding and ratification preserve the historical freeze and engineering comparison budgets; they are not aircraft or pilot validation.

The currently qualified original player uses the coupled-midpoint-v1 piston source. The separately tracked [mixture-decay defect #202](https://github.com/brettbergin/flight-simulator/issues/202) remains open. This camera leaf changes no native source, model, Mapper, Facade, held controls, save format or aid layout.

Pending acceptance: policy/page and coherent Scene integration; actual paused native/input/recording invariance and real-release lifecycle checks; seven presets across both profiles and three supported starts; editor/portable/rebuilt-library resource and receipt closure; original captures at three sizes and a 1360x768 focus smoke; moving Chase/Orbit response review; final independent review and current protected checks. Broad HUD-CAMERA #26, retained #179/#192 gaze limits, C172 configuration, hardware/pilot and phase gates remain open.
