# Airborne engineering preview (#94)

This Windows x64 preview uses the accepted FlightProofSession/v1 worker and unchanged original synthetic model. It starts airborne at1000 m WGS84 ellipsoid height with solved trim. Its original block airplane and flat runway are illustrative geometry. NOT C172S; no contact, taxi, takeoff, landing, real airfield, stall/spin validation, certified cockpit/instruments, saving, or training qualification. This proof facade is synchronous; production runtime/cockpit remain #20/#27.

Build/launch helpers require PowerShell 7 (`pwsh`; tested 7.6.5 recorded in the receipt) and the existing pinned Python 3.12.5/bootstrap toolchain. They install nothing. The portable EXE itself requires no Godot account, editor, Python or compiler. Prefer the isolated launcher to direct EXE launch so engine/userdata/TEMP stay beside the new proof run.

From the repository in PowerShell 7:

```powershell
$proof = Get-Content .local/export-proof/latest-run.json -Raw | ConvertFrom-Json
./tools/preview/run.ps1 -ExportProofRoot $proof.root -ToolchainRoot .local/toolchain
$preview = Get-Content .local/preview/latest-run.json -Raw | ConvertFrom-Json
& (Join-Path $preview.payload 'launch.ps1') -HeadlessSmoke
# After the coordinator releases the GPU for this task:
& (Join-Path $preview.payload 'launch.ps1') -VisualSmoke
# Human flight (one instance; close other GPU measurements first):
& (Join-Path $preview.payload 'launch.ps1')
```

The build helper verifies actual engine/template extraction trees and lock identities, accepted native package component bytes/rights/replacement evidence, paced cold import, actual editor functional smoke and exported portable smoke. It stages the preview main scene without editing the native proof project. A fresh `.local/preview/run-*` retains logs, exact source/native/model/package identities and tool versions. `latest-run.json` is written only after success. Failed attempts remain for diagnosis. Visual smoke runs actual rendered frames, saves initial/banked-paused/reset PNGs and a receipt, then quits with a 30-second watchdog; it is a graphics check, not a performance budget result. Native close/join and singular/plural leak/error guards remain required.

Controls: Left/Right roll; Down/Up pitch nose-up/down; A/D yaw; PageUp/PageDown throttle; [ / ] trim; P native pause/resume; R explicitly close/join and start a fresh airborne attempt; Esc joined quit. Roll/pitch/yaw spring back to the native solved baseline on release. Throttle/trim hold. Response is unvalidated.

The overlay derives ellipsoid height (not MSL/AGL), Earth-relative speed magnitude (not IAS), vertical speed, true heading and pitch/bank from actual v1 snapshots. ECEF is subtracted in binary64 before projection into the initial NED tangent frame; Godot render axes are East/Up/South. This scene only visualizes native position/attitude; no render forces/teleports/assists. The illustrative field proximity guard explicitly pauses native stepping above the field; it is not a ground-contact model.

The private host advances fixed 120 Hz through batches of at most 32 ticks, preserves fractional integer wall debt, and freezes before stepping when debt exceeds 0.25 s. P resumes ordinary pause; overrun debt requires explicit R fresh attempt, with no silent drop/catch-up. Native errors/bounded 65,536 history exhaustion stop visibly. Intended for short exploratory flights only.

The payload preserves all seven original DLLs at root and bin, original model, complete dependency notices and full corresponding JSBSim source/rebuild instructions. `source/airborne-preview` contains original MIT authoring source and helpers from this repository. Bundled Godot fallback font remains under existing Godot COPYRIGHT terms; no external art/font/audio or blanket dependency relicensing is added. The proof manifest records actual selected bytes; prior native package acceptance does not confer aircraft or phase acceptance on this preview. Nothing is published automatically.

