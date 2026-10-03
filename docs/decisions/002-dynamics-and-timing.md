# ADR-002: JSBSim owns aircraft dynamics on a fixed simulation clock

Date: 2026-10-03. Status: accepted for planning; model fidelity remains unvalidated.

## Context

The product must represent aircraft handling, propulsion, mass/CG, contact, and instruments consistently at varying frame rates. A second physics solver or duplicated system ownership can produce believable visuals with physically contradictory results. The upstream C172 model is not automatically the selected C172S fuel-injected configuration.

## Decision

Dynamically link JSBSim 1.3.1 behind one C++ adapter. JSBSim owns aircraft rigid-body/aerodynamic/propulsion/gear integration. Godot supplies presentation and picking; it never independently integrates or applies landing forces to ownship. The adapter exposes typed SI-domain controls/states and audits all upstream property/frame/unit mappings.

JSBSim provides an executive to load models, initialize them, and run steps, and a ground callback for contact queries. This supports our intended headless and embedded use, but does not prove aircraft calibration or every system capability. [Executive API](https://jsbsim-team.github.io/jsbsim/classJSBSim_1_1FGFDMExec.html), [ground callback](https://jsbsim-team.github.io/jsbsim/classJSBSim_1_1FGGroundCallback.html), [1.3.1 releases](https://github.com/JSBSim-Team/jsbsim/releases).

Start with fixed 120 Hz dynamics. Wall time determines how many unchanged steps are due; tick-stamped input/environment events determine behavior. A single simulation worker owns the JSBSim instance. Render snapshots may be coalesced, while input edges/events/recording records remain ordered and complete. Overrun pauses the session instead of enlarging the timestep or discarding ticks. Detailed order and multirate cadence are normative in [architecture](../architecture.md).

Systems ownership is explicit. Initially JSBSim consumes fuel and updates its mass/CG; project systems model electrical buses, starter availability, sensors, and configuration-specific switch logic. A later custom system replacing an upstream owner must disable overlapping behavior and validate the transfer. Aircraft differences belong in manifests and tested adapters, not presentation-only changes.

The selected C172S has its own serial/configuration/POH provenance gate. The bundled C172 XML is labeled experimental development seed until its assumptions are audited and parameters rebuilt or validated. Unproven spins, icing, advanced damage, or avionics remain unsupported capabilities.

## Alternatives

Godot rigid-body flight forces would give us complete control but require implementing and validating a full dynamics solver. Dual-solving through both JSBSim and engine physics risks duplicate or inconsistent forces. Tying dynamics to render delta makes behavior frame-dependent. A socket-separated JSBSim process adds operational/latency complexity before process isolation is needed; the engine-independent core still allows such an adapter later.

## Consequences and gates

Package the JSBSim DLL with notices, corresponding source/build instructions and patches, permitting replacement as required by the exact tagged LGPL terms. [Tagged COPYING](https://github.com/JSBSim-Team/jsbsim/blob/v1.3.1/COPYING).

P1 requires flat/sloped/edge runway contact fixtures, startup/taxi/trim/landing traces, and 60/120/240 Hz convergence measurements. Investigate source data, gear parameters, and numerical settings before adjusting controls to match subjective feel. Same-build replay repeatability is a measured target; cross-platform bitwise determinism is not promised. Aircraft-specific performance and pilot review gates continue through later phases.
