# Shared native-truth cockpit and instrument scan

Scope: partial engineering delivery for [#23](https://github.com/brettbergin/flight-simulator/issues/23), [#24](https://github.com/brettbergin/flight-simulator/issues/24), REAL-019, PRD-015 and UX-009/010/011. Consumes accepted [ADR009](../../decisions/009-cockpit-readings.md) and checked [controls PR118](https://github.com/brettbergin/flight-simulator/pull/118). Package, exported visual inspection and protected CI evidence are pending for this candidate.

The ordinary scene derives one copied ReadingSet from its native readback and publishes the same values to the physical dashboard, overlay and instrument scan. Unit conversion occurs in one shared display adapter. The independent pre-consumer arithmetic corpus and budgets remain unchanged. Missing or invalid channels show unavailable; historical publications retain an explicit RETAINED label. Labels distinguish derived TAS, true heading, ellipsoid height, kinematic vertical speed and body yaw rate from sensed instruments.

Pause through the existing menu, choose **Instrument scan**, then select a dial. Selection returns to the paused menu; explicit Resume passes through existing released-control/native acceptance. The selected dial can remain alongside the outside view during flight. Pause again to change or dismiss it. Scan operations send no flight axes or lifecycle commands and preserve the preceding camera. A fresh session or invalid/empty publication clears focus.

Original procedural geometry, dimensions, eye position and FOV provenance live in [cockpit-presentation.json](../../../content/aircraft/prototype/cockpit-presentation.json). No manufacturer model, calibrated sight picture or GLB is implied. Responsive scan layouts preserve status/retained strips and fit the minimum960x540 window.

## Engineering verification

Independent source reviews cover the reading producer, original metadata, display adapter, scan and new integration fixtures. An actual copied native package passes83 scan and107 scene checks for the current integrated consumers; the direct adapter passes51 checks. The pinned arithmetic suite separately passes3,226. These bounded headless observations establish display behavior, copied scalar identity and view-only invariants. They do not establish visual acceptance. See [integration check scope](../../../tests/instruments/scan-README.md).

The package workflow stages exact recursive cockpit/test/provenance sources, includes corresponding source, binds generated Godot UID metadata separately and rejects changed/missing staged bytes. Editor, portable and replacement observations and exported GPU captures must qualify the frozen commit before merge.

## Remaining issue and phase gates

#23 retains GLB/material/animation/source-specific geometry and calibrated sight-picture requirements. #24 retains InstrumentSnapshot sensing, power, lag, failures and engine indication requirements; no IAS, barometric/MSL altitude, magnetic compass, RPM or suction is fabricated. Physical controller/pilot exercises, exact C172 source/fidelity review and P1/P2 owner gates remain open. This delivery does not close either issue or an epic.
