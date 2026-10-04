# Whole-flight engineering preview

Windows x64, PowerShell 7+, original synthetic flight model with tricycle gear. This is not a C172, validated landing lesson or qualified training device. Forward view is a generic engineering camera.

Build the pinned native toolchain first, then:

```powershell
$proof=(Get-Content .local/export-proof/latest-run.json -Raw | ConvertFrom-Json).root
./tools/interactive-preview/run.ps1 -ExportProofRoot $proof -ToolchainRoot .local/toolchain
$run=Get-Content .local/interactive-preview/latest-run.json -Raw | ConvertFrom-Json
& (Join-Path $run.payload 'launch.ps1')
```

No accounts or runtime Python/Node/compiler required. Launcher requires PowerShell 7 and puts userdata beside the fresh payload, with an empty PATH and app-local native libraries. `-HeadlessSmoke` runs an explicitly automated pilot-API driver, plus pause/reset/control/close assertions. The package gate compares exact editor/exported records (except fresh session IDs), verifies all seven actually loaded native module paths/hashes and the full PE/CRT closure, pins the new model, and reruns the combined loop with a separately rebuilt JSBSim DLL in a Unicode path. `-VisualSmoke` is a separately scheduled GPU diagnostic. `-Airborne` starts the human mode airborne; default is ground-ready with brakes held. A watchdog limits smoke processes.

Arrow keys roll/pitch (Down raises nose), A/D yaw and nose-wheel steering, PageUp/PageDown throttle, [/] trim. B toggles brake hold; Space momentary both brakes; Q/E individual brakes. P pauses/resumes; G fresh ground start; F fresh airborne start; R restarts the current start; C toggles chase/forward view; Escape closes and joins the worker. Ground contacts and wheel forces come from native state. Earth-relative speed is not IAS; height is ellipsoidal and clearance is relative to the prepared synthetic plane, not MSL/real terrain.

The fixed 120 Hz player retains bounded wall-clock debt; a stall pauses visibly and requires an explicit fresh restart. Unknown coverage/native faults stop the loop visibly. Human mode has no scripted feedback assists. The smoke driver is labeled separately and does not establish human handling realism. LGPL source/build instructions, replaceable JSBSim DLL, component notices, original authored source and exact package receipts are retained. This package does not install a global runtime or publish a release.
