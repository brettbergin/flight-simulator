# Private render geometry proof

This actual headless Godot check consumes the supplied presentation `frame.gd` module, staging its exact bytes into ignored `.local/render-geodesy/`. It tracks no duplicate implementation. It checks CPU coordinate/basis/Camera3D projection behavior only: no GPU image, physics contact, world runtime, public terrain API, exported-game guard or pilot acceptance follows from a pass.

From the checkout with the checksum-verified pinned editor already available:

~~~powershell
python tools/benchmark/geodesy/run.py --frame C:/path/to/flight-simulator/app/proof/render/frame.gd
~~~

The root renderer recipe preselected 2560×1440, 70° vertical FOV, half-pixel continuity; this test retains those budgets. It exercises five cockpit points 0.8–4m in front of the camera with changing yaw/pitch across20×50km long legs and500 transactions spaced2km of eastward progression, with declared lateral/height changes. The actual pre-rebase radius is recorded and can slightly exceed2km at leg changes; it is a CPU diagnostic point, never a presented frame. Every candidate camera is recentered tozero before presentation. Independent binary64 projection is compared with actual Camera3D before/after rebase. Source canonical arrays must remain byte-identical. The mixed old-camera/new-origin negative must visibly exceed the same pixel budget. Staged/current module changes reject the result.

Original WGS84 scalar cases include prime/east90 equator, declared-longitude poles, dateline, elevated mixed position and near-pole. EUS signs, orthonormal/right-handed frames, geodetic outward normal, near-pole/dateline local roundtrip, actual float Basis and Camera projection before/after both seam cases are checked. Constants follow the accepted [WGS84 contract](../../../docs/contracts.md). Exact-pole longitude cannot determine a unique east/yaw: the current module preserves atan2(y,x), and this ambiguity is explicitly recorded rather than silently changing its domain or API.

The runner checks the editor's entire extracted tree against its existing pinned bootstrap receipt, logs actual engine/executable/module/test/reference identities, and rejects errors or incomplete traces. Result/log/receipt stay ignored; no local pilot state is read. Source-change negatives are guard checks, not a claim that an exported production build disables or enables any assertion.

Thresholds are frozen before the first run: ECEF agreement10nm; scalar basis norm/dot/handedness2e-12; float Basis determinant2e-6; local roundtrip0.1mm; projection/rebase0.5px. These are engineering proof budgets for this declared numerical/render pin and camera geometry, not universal geodesy accuracy, arbitrary FOV/distance stability or GPU continuity claims. The first long-track case is a planar synthetic ECEF trajectory rather than an airport route/flight model.
