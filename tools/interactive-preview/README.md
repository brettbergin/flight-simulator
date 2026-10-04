# Whole-flight engineering preview

Windows x64, PowerShell 7+, original synthetic flight model with tricycle gear. The player now includes an original high-wing aircraft, synthetic airfield scenery, a responsive graphical instrument panel, camera controls, smooth pilot input and procedural sound. This is not a C172, validated landing lesson or qualified training device. Instruments display derived native truth, with TAS and ellipsoid height explicitly labeled.

Build the pinned native toolchain first, then:

```powershell
$proof=(Get-Content .local/export-proof/latest-run.json -Raw | ConvertFrom-Json).root
./tools/interactive-preview/run.ps1 -ExportProofRoot $proof -ToolchainRoot .local/toolchain
$run=Get-Content .local/interactive-preview/latest-run.json -Raw | ConvertFrom-Json
& (Join-Path $run.payload 'launch.ps1')
```

No accounts or runtime Python/Node/compiler required. Launcher requires PowerShell 7 and puts userdata beside the fresh payload, with an empty PATH and app-local native libraries. `-HeadlessSmoke` runs an explicitly automated pilot-API driver, plus pause/reset/control/close assertions. The package gate compares exact editor/exported records (except fresh session IDs), verifies all seven actually loaded native module paths/hashes and the full PE/CRT closure, pins the new model, and reruns the combined loop with a separately rebuilt JSBSim DLL in a Unicode path. `-VisualSmoke` is a separately scheduled GPU diagnostic. `-Airborne` starts the human mode airborne; default is ground-ready with brakes held. A watchdog limits smoke processes.

Choose Resume, runway or airborne start from the initial menu. Arrow keys roll/pitch (Down raises nose), A/D yaw and nose-wheel steering, PageUp/PageDown or W/S throttle, [/] trim. B toggles brake hold; Space momentary both brakes; Q/E individual brakes. Pilot axes ramp at 0.9 normalized units/second toward the selected sensitivity; this input mapping has no attitude/velocity feedback. P or Escape opens/resumes the pause menu; quitting is a deliberate menu action that joins the worker and retires audio. G starts a fresh ground session; F fresh airborne; R restarts the current start.

1/2/3 select cockpit/chase/orbit; C cycles views. Hold right mouse to look, scroll to zoom, Home to recenter. H shows controls/provenance; V toggles the main instrument panel; M mutes audio; F11 toggles fullscreen. The cockpit view is a generic forward view with a 2D panel, not a modeled C172 interior. Decorative scenery has no colliders; the immutable prepared plane remains the only ground surface.

J explicitly selects the first connected gamepad or returns to keyboard. Left stick controls roll/pitch, right-stick X yaw, triggers increase/decrease throttle, A holds both brakes, Start opens the menu. Dead zone is 0.12 with signed rescaling. Selected-device loss pauses before another physics step; window focus loss also pauses. Automated mapping tests are synthetic and do not establish real-device calibration. Menu input cannot command the aircraft. Camera, panel and sound choices do not change native state.

Ground contacts and wheel forces come from native state. TAS subtracts copied NED wind/turbulence from earth-relative velocity; it is not IAS or a modeled airspeed sensor. Altitude is WGS ellipsoid height, not MSL/barometric altitude; VSI is kinematic and heading true. Body yaw rate is explicitly labeled rather than pretending to be a turn/slip instrument. No C172 limit arcs, RPM or unsupported sensor behavior are invented. Sound is original synthesized presentation driven by throttle/speed, not measured engine acoustics.

The fixed 120 Hz player retains bounded wall-clock debt; a stall pauses visibly and requires an explicit fresh restart. Unknown coverage/native faults stop the loop visibly. Human mode has no scripted feedback assists. The smoke driver is labeled separately and does not establish human handling realism. LGPL source/build instructions, replaceable JSBSim DLL, component notices, original authored source and exact package receipts are retained. This package does not install a global runtime or publish a release.
