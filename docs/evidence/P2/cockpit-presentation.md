# Original cockpit finish and physical-panel clarity

Date: 2026-10-10. Bounded delivery for [#159](https://github.com/brettbergin/flight-simulator/issues/159), partial [#23](https://github.com/brettbergin/flight-simulator/issues/23), REAL-019 and UX-009/010/011. Consumes accepted ADR009/010 and the [qualified original piston player](../P3/original-piston-player.md). This is original synthetic aircraft art, with no manufacturer cockpit or calibrated instrument claim.

## Result and preserved behavior

The physical panel renders its existing 1024×512 logical layout into a 2048×1024 texture with explicit top-left anchors and scale2. Six shared open bezel rings, matte glare-shield material, stronger dial ticks and full single-line captions distinguish the instruments. Native RPM and mixture occupy separate rows. Units and qualifiers remain visible: derived TAS, true heading, ellipsoid altitude, body yaw rate and kinematic vertical speed are not relabeled as sensed instruments.

The eye, panel dimensions, camera defaults/FOV limits, look controls, copied native reading formulas and control animations are unchanged. The six48-segment4mm rings add six mesh instances, one distinct material and2,304triangles. Provenance and topology are recorded in [cockpit-presentation.json](../../../content/aircraft/prototype/cockpit-presentation.json) and its [geometry checks](../../../tests/instruments/cockpit_geometry_checks.gd). The flight model, physical reference data and native engine/propeller implementation are unchanged.

## Source and functional checks

Actual-builder/adapter checks pass159 assertions, including winding/openings, geometry/material sharing, measured fallback-font bounds and unavailable/retained engine values. Native scene checks pass119; instrument arithmetic remains3,226 and scan checks83. Independent source review checks the final eleven-file integration, including the narrow observer/compiler/staging registration. Its retained review SHA256 is `38b78e583a420d267570dd2818f6636c3400129687bda76d21929eff39640601`.

The actual Windows package is bound to runtime commit `f45c37af17bca49259c5f7bcc9012e546f01e20c`. Editor, portable export and independently rebuilt JSBSim replacement each pass41,955 facade checks,15,909 piston checks and371 ground-material checks. Original whole-flight traces compare9,805 records under unchanged bounds. The final package has458 payload files and191 authoring bindings; source/model pins, corresponding source, notices, actual loaded module/CRT closure and replacement qualification pass.

| Frozen artifact | SHA256 |
|---|---|
| Package manifest | `8b8b46acaa9ef318b55c620ab2c77b31bd4fb3faa0ffc6db526f6df6eeb1c8d1` |
| Final integration source review | `38b78e583a420d267570dd2818f6636c3400129687bda76d21929eff39640601` |
| Corrected paired render review | `dce3bbb0b77f96c2d7a0ecfe277307a1ba65d24d141176e1f38cccb0d87ad05f` |
| Reviewed visual wrapper | `d7dcb68ed12819a35d27d9e3e80479d2e29444c0323fe40ba9ecb70a8f3fc66b` |

The first full-package attempt failed the existing NTFS junction fixture under the restricted runner. Its failure is retained. An unchanged rerun with the fixture's required host permissions passed; no test expectation, tolerance, model or physics source changed.

## Bounded render observations

A prospectively frozen before/after experiment captured default cockpit, PANEL and outside views at2560×1440. Each view uses five seconds of warmup and two contiguous ten-second measurement blocks; all7,203 rows per build are retained. Callback and exposed render CPU/GPU proxies pass the original block-stability and before/after investigation thresholds. Callback medians stay approximately8.32ms under the unchanged120FPS cap. Independent review recomputes all14,406rows and checks all six original PNGs; the outside image is byte-identical.

These short paused trials do not establish isolated throughput, Windows presentation latency or a representative-flight performance gate. The owner's already-running game was present in both trials; a headless ground preflight overlapped the last outside baseline block. No causal per-material cost is inferred. The target reports2048×1024 and exposed format2. Its RGBA8 color texels calculate to8,388,608bytes; exact driver attachment/allocation remains unobserved. This is an explicit limit on the allocation evidence requested by#159, not a total VRAM claim.

Review rejected overlapping two-line captions before capture. The corrected12px full captions use measured baselines262.7/485. A subsequent inherited full-rect-anchor warning was fixed with explicit top-left anchors, then a fresh candidate passed. Rejected source/capture reviews and original traces remain retained; no failed candidate is represented as accepted evidence.

## Actual Windows views

The [bounded observer](../../../tests/instruments/cockpit_visual.gd) renders38 fixed views per context using the pinned Compatibility/OpenGL renderer on the reference RTX3090. Three sizes—960×540,1920×1080 and2560×1440—cover ordinary cockpit and PANEL views from actual paused legacy ground, legacy prepared-airborne and original cold-ground sessions. Separate forward FOV35/90 views test zoom; look endpoints are explicitly turn-away boundary observations. Joined retained truth and explicitly invalid copied display fixtures test honest unavailable indications without fabricating an airborne piston state.

All114 captures pass exact roster, PNG dimensions/hashes, target metadata, complete state/source preservation and native/audio join checks. Matching editor, portable and rebuilt-library pixel arrays are identical. Each trial uses a fresh private project/payload and profile; original qualified files and the owner's game remain untouched. Replacement captures use the final portable closure plus exactly the two already-proven rebuilt JSBSim DLLs; the historical replacement qualification tree is preserved.

Independent review approved that package's functional integrity (`da819c4f1920ae0c7d2b62c8998ceb2926b9a82887fd115f6c034e63a3b9414e`) and withheld whole-layout acceptance (`a10ed737ad8eb638ad668196d01e4b33d3bf7d901b298a2518c4379cc7fc658b`): the minimum-window wind card obscured heading and retained/invalid header labels touched. Those original114 images remain retained.

The corrective source spaces the header using actual font measurements and reserves a bounded upper-left wind card above the physical panel. A first wrapped-container preflight exposed an oversized empty first-frame card; it remains rejected. A fixed92px manual panel then passed all38 view/state checks, including the unchanged first recipe. Fresh final package and three-context visual qualification remain pending; the old manifest above is a historical checkpoint, not evidence for this later layout source.

Boundary turn-away views do not prove readability while looking away, and the960wide-FOV view can require the existing scan/zoom for small qualifiers. These observations do not establish human controller/pilot acceptance, sensed-instrument fidelity, calibrated sight picture, listening evaluation, C172S source applicability or any phase gate. Broad#23/#24 and owner review remain open.
