# Manual original-pigment paint board

Issue271 retains `capture_paint_board.gd`, the original authoring observation used
for 26 independent white/gap/crossing crops. It uses the actual unmodified
production shader and frozen `tests/world/runway-paint/controls-v1.json`, not a
duplicate paint classifier. Its source identity constants bind the reviewed World;
changing these identity pins never authorizes changing expected control values.
The first earlier paint qualification and this successor remain distinct evidence.

Stage this source as `res://paint_board.gd` in a fresh isolated authoring project.
Stage the current KawoWorld and its unchanged Reader/CanonicalFrames/UInt64
dependencies at their normal `res://world/terrain/` and `res://simulation/` paths.
Copy the frozen controls byte-for-byte to `res://paint_controls_v1.json`. Set
the viewport to1280x800 and renderer to Forward+. Import with the pinned Godot
first, then use its actual Vulkan renderer and fresh isolated profiles:

```powershell
& $godot --audio-driver Dummy --path $project --rendering-method forward_plus --rendering-driver vulkan --script res://paint_board.gd -- $freshAbsoluteOutput
```

The output must not exist. Retain logs, receipt, complete original board and all
26 original tile PNGs. Reject process/script/engine errors, failed source/renderer
guards or resource leaks. The board records four unaveraged central pixels per
crop; it performs no color threshold, classifier, CPU paint verdict or image
retouching. Root separately inspected expected white/gap/winner behavior. A zero
exit means completed observation, not automatic shader/aircraft acceptance.

Use the existing fixed Node host in [runway-paint](../runway-paint/README.md) for
separate 132 geometry and 156 actual material-uniform checks. Use the unchanged
[actual Scene capture](../terrain/kawo_gpu_capture.gd) for the 47 native paused
views, ordinary camera zoom and public-origin transactions. Keep those scopes
separate from the synthetic board, real-time flight and final exported delivery.

See [surface evidence](../../../docs/evidence/P4/kawo-surface-appearance.md).
