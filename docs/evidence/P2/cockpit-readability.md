# Shared native-truth cockpit and instrument scan

Scope: partial engineering delivery for [#23](https://github.com/brettbergin/flight-simulator/issues/23), [#24](https://github.com/brettbergin/flight-simulator/issues/24), REAL-019, PRD-015 and UX-009/010/011. Consumes accepted [ADR009](../../decisions/009-cockpit-readings.md) and checked [controls PR118](https://github.com/brettbergin/flight-simulator/pull/118). Package and exported visual observations below bind runtime source `b73b2815cfb48d528e07a1664bf1498de5091319`. All four protected checks on the final PR head remain a merge requirement.

The ordinary scene derives one copied ReadingSet from its native readback and publishes the same values to the physical dashboard, overlay and instrument scan. Unit conversion occurs in one shared display adapter. The independent pre-consumer arithmetic corpus and budgets remain unchanged. Missing or invalid channels show unavailable; historical publications retain an explicit RETAINED label. Labels distinguish derived TAS, true heading, ellipsoid height, kinematic vertical speed and body yaw rate from sensed instruments.

Pause through the existing menu, choose **Instrument scan**, then select a dial. Selection returns to the paused menu; explicit Resume passes through existing released-control/native acceptance. The selected dial can remain alongside the outside view during flight. Pause again to change or dismiss it. Scan operations send no flight axes or lifecycle commands and preserve the preceding camera. A fresh session or invalid/empty publication clears focus.

Original procedural geometry, dimensions, eye position and FOV provenance live in [cockpit-presentation.json](../../../content/aircraft/prototype/cockpit-presentation.json). No manufacturer model, calibrated sight picture or GLB is implied. Responsive scan layouts preserve status/retained strips and fit the minimum960x540 window.

## Engineering verification

Independent source reviews cover the reading producer, original metadata, display adapter, scan and new integration fixtures. An actual copied native package passes83 scan and107 scene checks for the current integrated consumers; the direct adapter passes51 checks. The pinned arithmetic suite separately passes3,226. These bounded headless observations establish display behavior, copied scalar identity and view-only invariants. They do not establish visual acceptance. See [integration check scope](../../../tests/instruments/scan-README.md).

The package workflow stages exact recursive cockpit/test/provenance sources, includes corresponding source, binds generated Godot UID metadata separately and rejects changed/missing staged bytes. The frozen Windows packet passes editor, portable and independently rebuilt JSBSim replacement modes. Each mode passes3,226 arithmetic,51 adapter,83 scan and107 native scene checks alongside310 input,30,398 facade and634 wire checks. Its168 payload files and87 authoring source bindings retain exact bytes; checkout-to-Git correspondence permits only declared CRLF-to-LF normalization. Native bridge, prepared world and original model are unchanged. Loaded module, CRT, direct/delay import, corresponding library source, notices, model pins and replacement trace checks pass.

| Frozen artifact | SHA256 |
|---|---|
| Runtime PCK | `8d4e1f7a27e5cdc3b41b6a890398085635bb77e7a751662be65c24359ba7b5b2` |
| Package manifest | `f8aa5395fb812fe8750565159d921931c8df07a67e718d87ea3423f86aa6cbfb` |
| Package inventory | `d529fd298d3c57d7fca5ef47ef510eebaff4d2989e57745dc293f5ce953a149b` |

The actual exported PCK renders with Godot4.7.2 Compatibility/OpenGL3.3 on the reference RTX3090, driver591.86. Thirty-six retained PNG observations cover all six focused dials, the ordinary scan, outside view, cockpit, dashboard, confirmed historical state and explicitly synthetic invalid publication at960x540,1920x1080 and2560x1440. Every captured image matches its requested dimensions. The visual receipt reports zero failures, fixed native tick0 through view selection, unchanged readbacks and joined workers/audio. Contact-sheet and original-image review verifies readable dial labels, unavailable/retained states, status strips, runway/horizon and unchanged original eye/FOV choices. An earlier source41c capture exposed touching scan captions; the corrected b73 captures reserve caption space and remove background overlay ghosting. This is bounded presentation evidence, not a frame-pacing or pilot assessment.

## Remaining issue and phase gates

#23 retains GLB/material/animation/source-specific geometry and calibrated sight-picture requirements. #24 retains InstrumentSnapshot sensing, power, lag, failures and engine indication requirements; no IAS, barometric/MSL altitude, magnetic compass, RPM or suction is fabricated. Physical controller/pilot exercises, exact C172 source/fidelity review and P1/P2 owner gates remain open. This delivery does not close either issue or an epic.
