# Renderer feasibility proof

Issue [#18](https://github.com/brettbergin/flight-simulator/issues/18) uses an
original synthetic panel, bounded terrain tiles, runway/building/tree geometry,
shadow-casting cloud geometry and the [tiny actual GLB fixture](pipeline/README.md).
The scene is a visual-load fixture. Fixed readings are examples; no aircraft,
sensor, real airport or meteorological fidelity is asserted.

Use the accepted [native export proof](../export/README.md) first. Its isolated
run directory supplies the reviewed native DLLs and original model data; the
renderer runner recursively stages authored resources into its own project.
The original native proof scene and project remain unchanged. Official release
templates prohibit command-line scene overrides, so the isolated project sets
its main scene before import/export.

```powershell
node --test tools/benchmark/reduce.test.mjs tools/benchmark/evidence.test.mjs
python -m unittest discover -s tools/benchmark/pipeline -p test_fixture.py
python tools/benchmark/pipeline/verify_pipeline.py --godot <pinned-editor>
python tools/benchmark/geodesy/run.py --godot <pinned-editor> --output .local/render-geodesy/fresh-run
python tools/benchmark/verify_headless.py --godot <pinned-editor>
./tools/benchmark/run.ps1 -ExportProofRoot <accepted-export-run-directory> -ToolchainRoot <pinned-.local/toolchain-directory> -Fixture overcast -Duration 600
```

Repeat the GPU command for `clear` and `dusk`; use separate fresh run directories.
The default target is 2560×1440, vertical FOV 70°, Forward+ Vulkan on the RTX 3090,
2× MSAA, no TAA/upscaling/VSync, 120 FPS cap and a 10-second warmup. An actual
1360×768 window presents the exact-size offscreen viewport through a scaled blit.
This measures engine callback intervals and rendering work; it does not measure
Windows displayed-frame pacing. Runtime settings and adapter are read back;
headless execution, unintended fallback, minimization, size/VSync changes,
source drift and runtime/leak diagnostics reject the run.

The [frozen recipe](recipe.json) identifies thresholds before observation. Raw
monotonic callback intervals use wall time; no slow frames are removed. Average
FPS is frame count divided by measured elapsed time. Quantiles use nearest rank.
Delayed GPU observations have unique captured-frame IDs; render CPU and GPU
costs are reported separately across the active measured viewports. The static
panel texture is drawn before warmup. Godot's one-second `TIME_PROCESS` maximum
is separately labeled and cannot establish whole main-thread p95 CPU cost.

Each run preserves settings, sanitized hardware fields, exact staged source and
export/native hashes, cloned immutable verification tools, CSV samples, process
working-set samples, runtime receipts and native-resolution PNG captures under
`.local/benchmark/`. The independent reducer verifies actual files, continuous
intervals, sample uniqueness, memory coverage, runtime markers and image pixels.
Shorter or alternate resolution/FOV captures are diagnostic and cannot become
canonical target captures. The engine allocation monitor is not driver-reported
VRAM residency; working-set peaks are sampled at one-second cadence.

Before measurement, two actual GPU images hold identical canonical source state
across an origin transaction. The independent RGB/RGBA PNG decoder validates CRC,
size and filters, then recomputes changed-pixel counts. The preselected research
budget allows at most 1% of pixels to change by more than 8/255 in any RGB channel.
This permits small shadow/rasterization changes; it is not pixel identity.
During the run, camera, canonical terrain parent, lighting, camera-mounted panel,
silent spatial audio and local-coordinate particles move coherently through
2 km origin shifts. Projection and relative-emitter checks retain their own
preselected budgets and a mixed-version negative must be detected. The
[independent geometry proof](geodesy/README.md) covers cardinal signs, dateline,
near-pole cases and long routes; exact-pole yaw remains explicitly ambiguous.

Headless hosted CI compiles scripts, verifies the actual import, checks geometry
and rejects GPU benchmark claims. GPU captures run on the reference PC. Whole
main-thread CPU, concurrent authoritative-worker scheduling, real regional
streaming, audible continuity, world-space particles, temporal weather,
end-to-end input latency, final instrument readability and pilot evaluation
remain separate product evidence. These primitive proxies support an engineering
renderer decision, not acceptance of a finished simulator.

Every five seconds an identical terrain mesh replaces one of four far corners.
Timestamped attachment events retain frame, deadline, epoch, corner index and
CPU submission cost. Missed periods are skipped. Independent verification binds
events to the raw measured frames and recomputes cadence, counts and quantiles.
The scene retains 64 active terrain nodes and at most one queued old node during
each transaction; this does not bound GPU allocator retirement. This fixture
does not implement storage, GIS coverage or physics contact streaming.
