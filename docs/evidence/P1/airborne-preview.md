# Human-controlled airborne engineering preview

Date: 2026-10-03. Issue [#94](https://github.com/brettbergin/flight-simulator/issues/94).
Reproduce with [the Windows preview runner](../../../tools/preview/README.md).

This first playable preview starts an original trimmed aircraft airborne. Arrow
keys control roll and pitch, A/D yaw, PageUp/PageDown throttle, brackets trim,
P pauses/resumes, R closes and joins the worker before a fresh attempt, and Esc
closes the application. Down requests nose up; Up requests nose down. The live
overlay reads native attitude, true heading, ellipsoid height, ground-relative
speed, vertical motion, controls and tick. These are prototype indications.

Simulation remains in the accepted `FlightProofSession` worker and unchanged
original-synthetic aircraft package. The UI submits `ControlCommand/v1` with
fixed pilot authority. Integer microsecond pacing retains fractional debt at
120 Hz with batches of 1–32 ticks. A wall stall above 250 ms freezes visibly and
requires a fresh attempt; it never enlarges physics dt or silently discards
debt. Pause and restart are native lifecycle operations.

The view has an original block aircraft, synthetic grid/runway, chase camera
and large text overlay. It uses Godot Compatibility/OpenGL. It does not establish
the separate Forward+ rendering benchmark. There is no ground/contact solver
in this preview; an explicitly labeled proximity guard pauses before the
illustrative ground. Taxi, takeoff, landing, systems, full cockpit, persistence,
real airports and calibrated C172S behavior are future work.

## Actual reference-PC graphics diagnostic

The private precursor was exported and exercised on the reference RTX3090 with
Godot 4.7.2, OpenGL 3.3, 1280×720. It produced three actual viewport PNGs: initial
airborne, controlled/banked and paused, and freshly reset. The run completed
120 controlled native ticks, pause/resume, restart and joined shutdown, exited
zero, and reported no errors or leaked objects. The coordinator inspected the
images for flight view and text readability. This is engineering graphics
evidence; no pilot handling evaluation was recorded.

| Private precursor identity | SHA-256 |
|---|---|
| `preview.gd` | `9b8deb2b11367d732140234e70d06d776a1b9fe3d5a4d0892e4ad9ef533a9fcb` |
| Export executable | `d34d36f3be1a6c49c56525ae86469b92e4f417ddf0b43cf00dd80c385c4b0562` |
| PCK | `87fde97de2119d470e5d8d6814633141a0dba8a14c720e4c96994582f19f8409` |
| Accepted native bridge | `1db6bfc94e88be003b24b17c7fa9cf18dfc0c8f9e2739200ce24dd285d10f852` |
| Accepted JSBSim DLL | `7963d908c74a039e0e8d0664090fad33b777c60e38e9e6e9bb5d85d5da6f7948` |

All seven root and seven `bin/` native/runtime DLL copies matched the accepted
export payload. Corresponding JSBSim source and notices were retained. The
launcher uses an empty PATH and isolated local profile/TEMP directories; it
does not upload pilot profiles or require engine accounts. The private package
was copied to the owner's workspace and launched for human use.

## Public source and packaging

The public runner stages a fresh project and changes resource/profile paths
for reproducibility. It preserves the original native proof scene and API.
Its independent editor/portable functional checks exercise 9,600 native ticks,
controls, attitude response, fractional debt, stall handling, pause/resume,
fresh restart and joined shutdown. Actual public-source receipts and final
review identities are recorded in the implementation PR. The runner rejects
nonzero exits, failed receipts, script/runtime errors and object leaks.

The coordinator also reran the integrated root source through editor import,
editor functional smoke, export and empty-PATH portable smoke successfully.
Both functional receipts passed 24 named checks with no failures. Public
`preview.gd` SHA-256 is
`8771eed3099a2acd0e984cb6062ff193adacb0918e590f05404254036ef46c09`;
the reviewed launcher is
`8001fae4e8e9c9e11795856089b3e74f87ca2a4f1070a2fa93f64f1c8ef8e791`.
Changes from the private precursor are reproducible resource paths, profile
isolation, application naming and recording joined closure before visual
success. Control, flight-view and pacing behavior are unchanged.

The private GPU diagnostic above predates the public path/packaging changes;
it must not be presented as an exact public-package GPU run. A fresh public
graphics smoke remains a separate closure check while the owner uses the
already-open private build. P1, renderer acceptance, human pilot evaluation
and C172S fidelity remain open.
