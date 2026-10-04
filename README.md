# Flight Simulator

A Windows-first flight simulator built around realistic Cessna operations, repeatable practice, and evidence-based aircraft validation.

**Current stage: P1 engineering previews.** The [Windows whole-flight preview](tools/interactive-preview/README.md) connects ground steering, takeoff, flight, touchdown and braking through one original synthetic aircraft model. The [flight UX iteration](docs/evidence/P1/flight-ux.md) adds an original high-wing aircraft and airfield presentation, graphical instruments, smooth keyboard/optional gamepad input, camera controls, sound and session menus. The [cockpit iteration](docs/evidence/P1/cockpit-ux.md) adds a physical prototype interior, live dashboard, focused panel view and local synthetic-airfield map. A manufacturer-specific C172 cockpit, real airports and calibrated C172S behavior remain future work. See [native evidence and limits](docs/evidence/P1/interactive-preview.md).

Start with [the project plan](docs/README.md), [the roadmap](docs/roadmap.md), and [the issue index](docs/issue-index.md).

Initial direction: Godot presentation, C++20/JSBSim flight core, one explicitly configured C172S target, offline Windows desktop use, and a small dated Puget Sound world pack. Native integration, source rights, flight-model calibration, and pilot evaluation are early proof gates.

```powershell
node tools/check-docs.mjs
node tools/sync-github.mjs
```

The first command checks the planning package; the second previews planned GitHub work without mutations. See [contributing](CONTRIBUTING.md), [agent operations](docs/agent-operations.md), and [delivery policy](docs/delivery.md).

For native builds use the [pinned bootstrap](tools/bootstrap/README.md); harness usage and meaningful headless proofs are documented in [the FDM adapter](native/fdm_jsbsim/README.md).

Source code uses the [MIT license](LICENSE). Third-party software, aircraft references, geographic data, and assets retain their own licensing terms. Practice records are simulator practice; no training-device approval or licensing credit has been established.
