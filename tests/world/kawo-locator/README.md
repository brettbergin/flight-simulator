# Manual KAWO locator layout observation

`capture_layout.gd` supplies explicitly synthetic UI positions to the actual map
Control. It does not create or move a native aircraft. The independent cardinal
controls exercise all four selected ends, both along/across signs, coincident
bearing suppression, retained/unavailable state, and three supported sizes.
Actual font and row bounds must pass. Eight original viewport images require
separate inspection; 513 assertions are not a pixel or flight-fidelity verdict.

Stage this source as `res://kawo_locator_layout.gd` in a fresh, fully prepared
frontend project with the current actual `interactive/flight_map.gd` and all its
normal dependencies. Use the pinned authoring Godot, isolated profiles and the
existing supervised process helper. An exported release script override is not
an accepted entry point for this manual authoring observation.

```powershell
& $godot --audio-driver Dummy --path $project --rendering-method gl_compatibility --rendering-driver opengl3 --script res://kawo_locator_layout.gd -- $freshAbsoluteOutput
```

The output path must not exist. Preserve logs, original PNGs and receipt; reject
process/script/engine errors, failed assertions or leaked resources. The original
first run exposed the too-short footer and is retained in the linked evidence.
The actual [Scene capture](../terrain/kawo_gpu_capture.gd) separately supplies
47 views, including four normal KAWO map selections over unchanged paused native
truth; use its existing fresh-output and requested-renderer route. These are
different scopes, and neither is manual geographic flight or pilot acceptance.

See [issue269 evidence](../../../docs/evidence/P4/kawo-locator-readability.md).
