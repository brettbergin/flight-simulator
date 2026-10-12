# Original generic cockpit asset implementation evidence

Status: source, export, actual import and current-source three-context flight qualification passed. Every-original image review passed in all three contexts; the predeclared paired render observation also passed its bounded proxy checks and independent review. Final current-head CI is required before merge. This is the bounded contribution in [PR237](https://github.com/brettbergin/flight-simulator/pull/237) to [COCKPIT-ASSET #23](https://github.com/brettbergin/flight-simulator/issues/23). Parent23 and the aircraft, pilot and phase gates remain open.

The [original-asset contract](../../contracts/cockpit/original-asset-v1.md) merged as `5e7f6042a8a5f313d0bb58d0abb7b0106ae125ad`. Its fixed-engine UV/tangent amendment in [PR236](https://github.com/brettbergin/flight-simulator/pull/236) merged as `3ce24b8ae5f4154d31f5d7a79c7da681e2288d12`; this accounts for imported representation without changing source geometry or aircraft-state interfaces.

## Original source and geometry

The independent original-builder baseline predates candidate output: 74 parts, 84 asset nodes, seven material resources, 9,263 source vertices and 14,328 triangles, including 720 existing seam/pole degeneracies. Baseline SHA256 is `fbe01696c09d17042079060739d5599d649e30164727c4a414492c1402a88eba`. Importer vertex splitting is distinct from this source count; no degeneracy repair or aircraft geometry fitting is claimed.

The editable [Blender source](../../../assets_source/c172/original-prototype/original-cockpit.blend), [generator](../../../assets_source/c172/original-prototype/generate_cockpit.py), original PNG tiles and [generation provenance](../../../assets_source/c172/original-prototype/cockpit-source.json) preserve the frozen geometry and copied-control pivots. Blender 4.5.14 LTS/build `62c1db4208e8` produced the 634,348-byte [GLB](../../../app/cockpit/assets/original-cockpit.glb), SHA256 `fe12aa451d9e2105683a22a0c5353c9cf318b2dca6f46011f83ce3dea0f8d621`. The 2,324,285-byte editable file has SHA256 `375cf88fc65141f6e29052f52f86817b7b35dce60759e618faefa7d078d5809a`.

Seven shared imported materials and two original 256×256 tiles add restrained surface detail. [MIT attribution](../../../third_party/licenses/evidence/original-cockpit-asset.md) remains in the rights register, corresponding source and package notice. No manufacturer manual, drawing, photograph, logo, borrowed texture or downloaded aircraft model is included. The `assets_source/c172` directory is an ownership convention, not C172 applicability evidence.

## Qualified software observations

| Record | Actual result | Boundary |
|---|---|---|
| Independent GLB inspection | Complete baseline geometry, normals, UVs, winding, pivots, materials and embedded-image checks passed | Source-derived references and unchanged contract limits; not aircraft accuracy |
| Pinned Godot isolated import | 939 asset checks and 165 existing geometry checks passed; independent saved-artifact review passed | Actual imported arrays/resources and copied controls; separate from flight and pixels |
| Current whole-flight source | `a151c0f36939c9c74beb35c810522042b3024f33`; editor, portable and independently rebuilt-library contexts passed | Actual process exit0 and join; manifest SHA256 `7701446590328d7a5c320398ad455d1ca5c7a877e29a973900cf84c2d102d2f4` |
| Independent current delivery audit | 32,495 saved checks passed, including full source/import/UID/payload inventories, 253 PCK entries and 9,805 trace rows | Review SHA256 `4fbed3265e20c110ac1122c7f545ecc57ac804c7c4c971c279798a719b24ec5d`; exact editor/portable comparisons and stated replacement tolerances retained |
| Three-context observation production | Actual 60 captures per context, 180 PNGs and 612 authority snapshots total; each capture process exited0 and joined | Three sizes, default presets, six enlarged scans, outside baseline, FOV limits and labeled joined retained/invalid fixtures; production alone is not pixel approval |
| Editor every-original review | All 60 original images independently viewed; saved integrity and scoped pixel approval passed | Combined review SHA256 `d68426a0a10c0b805114cfd2d172cd02da8a0151902b95e0ce4cc7b3c3c0e320` |
| Portable every-original review | All 60 original images independently viewed; saved integrity and scoped pixel approval passed | Combined review SHA256 `cdebf8f73ec7a94d37d7af56a3885e192bac115c0d3307943a434f203888ce83`; shipping executable/PCK attribution retained |
| Rebuilt-library every-original review | All 60 originals independently viewed; saved integrity and scoped pixel approval passed | Combined review SHA256 `053b0dd1408f33f850d89ca228ff61d120168cc048b10c76ef17a295bdad8045`; actual replacement-library attribution retained |
| Paired render observation | Three views per build, 14,406 total callback samples; frozen proxy limits satisfied | Fresh accepted-builder/imported-asset pair; full state restoration and independent saved-result/image review passed |

The current Scene SHA256 is `1cda6011ff093d1d06508287eca698bd130b83f8e233dac0b2c79b33f74c2b03`. The runtime preserves the original eye/focus, live panel, six open bezel rings, copied-state control formulas and exterior. Complete asset validation precedes native-session creation. A malformed or missing asset returns an empty build result, displays a bounded diagnostic and exits test modes nonzero; there is no procedural fallback or asset-owned aircraft state.

Each observation binds the actual Compatibility renderer/OpenGL driver, reference RTX3090 and driver610.88, loaded native modules and exact source/package/import resources. Before/after publications remain equal where no native advancement is requested; saved camera/presentation state restores and actual native/audio owners join. Compatibility pixels establish neither Forward+ appearance nor general performance. The 25-file native and 18-file control source rosters remain unchanged. Numerical results keep their original build attribution; this presentation iteration does not invent a new numerical run.

## Preserved failures and limitations

Export/import failures retain their original results: material tint/roughness handling, repeated texture aliases, default double-sided materials, sphere-pole custom-normal loss and the engine-required tangent representation. The accepted amendment and fresh import establish only their stated source/import scope. The earlier `0xC0000005` attempt remains failed; no faulting-instruction, driver or native crash-cause conclusion is established.

Godot exports the GLB through imported resources. The `71d4` correction removes the incorrect prerequisite that raw GLB bytes must be visible through FileAccess in a PCK, while retaining ResourceLoader and complete decoded-resource guards. A disposable actual probe established that Godot consumes `--rendering-driver` before exposing `OS.get_cmdline_args`. The capture-only `a151` correction checks the actual driver; its external supervisor separately binds launch arguments and actual renderer witnesses. Full inversion preserves ordinary noncapture source.

Windows CI exposed a separate provenance failure: the generator's 26294 LF bytes became 26676 CRLF bytes at checkout. The narrow `.gitattributes` rule preserves the approved generator bytes instead of changing its expected digest or accepting alternate source. Final protected CI remains pending.

Reviewers found no new asset obstruction or qualifier loss under the contract's bounded image criteria. Existing retained HUD/Look overlap remains visible: the helper can overlap ground-speed text, and the wind card covers center/right HUD text and upper panel arcs in the 960×540 joined retained fixture. Retained/stopped/unavailable qualifiers remain explicit and the enlarged instrument scans remain readable. This synthetic post-join composition is not a demonstrated reproduction in ordinary live flight. Deliberate FOV35 cropping, FOV90 small labels, gaze and small-window limits remain explicit; the reviews do not promise every overlay caption is readable at every camera boundary.

No target-C172S geometry, manufacturer sight picture, sensed-instrument behavior, general GPU/FPS/VRAM, human readability, hardware, pilot, training-credit or P1/P2 acceptance follows from these records.

The first portable pixel report attached some observations to the wrong fixture. That report and its initial combined approval remain preserved as superseded evidence. The corrected report associates all 60 observations by exact PNG/capture identity; rebuilt-library notes were corrected before final approval. A separate editor audit verified the original associations and left its report unchanged. No images or capture outcomes were relabeled.

## Paired render observation

Both fresh projects used the qualified `a151` application, native modules, models and import resources. The baseline replaced only the cockpit builder with accepted `3ce24b8` source; the candidate used the imported asset. Both used Compatibility/OpenGL3, the reference RTX3090/driver 610.88, a 2560×1440 window, VSync disabled, a 120 FPS cap, and the same 2048×1024 physical panel target. Each cockpit, enlarged-panel and outside view used five seconds of warmup and two ten-second blocks, with the unchanged thirty-second view deadline. Both processes exited zero and joined native/audio owners.

| View | Callback median, baseline → candidate | Render CPU proxy median | Render GPU proxy median |
|---|---|---|---|
| cockpit | 8.327 → 8.329 ms | 1.390 → 1.381 ms | 1.726 → 1.734 ms |
| panel | 8.327 → 8.334 ms | 1.275 → 1.273 ms | 1.653 → 1.660 ms |
| outside | 8.326 → 8.327 ms | 1.055 → 1.076 ms | 1.666 → 1.664 ms |

All paired and within-run block checks satisfied the existing median max(10%, 0.5 ms) and p95 max(15%, 1 ms) criteria. Full per-view Variant bytes and separate fixed-resolution/original-window snapshots restored exactly, including map presentation and recorder contents. No matching Godot/WholeFlightPreview/FlightProof processes were observed at either measurement boundary; the human playable copy was launched afterward. Render-time getters are engine counter proxies without unique GPU timestamp attribution. This capped, paused three-view experiment does not establish uncapped FPS, full-flight pacing, exact driver allocation or general performance. No project budget was raised.

Comparison SHA256 `66ee057ddf0aec42e18f38242416500bba286e9a76d7bc447a74ca3a03288c65`; independent saved-pair review SHA256 `6ad73a1a5296e72393b81997142089b9db567676083b7c8279462b056a1d8e46`. The first v5 baseline remains failed with zero completed views. Its stale harness assumed an empty recorder and compared map geometry before resize layout settled. The reviewed v6 harness admits the current valid single tick-zero recording and settles/restores each viewport size separately; it clears no recording, excludes no map field and changes no game source.
