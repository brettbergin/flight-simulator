# P1 renderer and asset pipeline evidence

Date: 2026-10-03. Issue [#18](https://github.com/brettbergin/flight-simulator/issues/18).
This record measures original visual-load fixtures on the reference PC. It does
not establish a working cockpit, regional scenery, aircraft fidelity or pilot
acceptance. Reproduce with [the benchmark runner](../../../tools/benchmark/README.md).

PR [#93](https://github.com/brettbergin/flight-simulator/pull/93) merged the
implementation after independent review and four required CI checks. The final
clear/dusk/overcast 600-second captures now pass every frozen engineering check
and independent read-only packet review. Earlier leaking or interrupted captures
remain invalid. This completes the bounded renderer feasibility evidence for
#18; the coordinator retains issue acceptance and the separate P1 owner gate.
The playable preview and its Compatibility renderer have separate evidence.

## Workload and effective settings

The exported Godot 4.7.2 standard-precision release uses Forward+ Vulkan on the
RTX 3090. The native bridge and JSBSim binaries come from the accepted
[#15 export proof](native-export.md); the visual scene does not run a concurrent
aircraft worker. The original native proof scene remains independently runnable.

Hardware receipt: Windows 11 Home 10.0.26200/build 26200; i9-12900K (16 cores,
24 logical processors); 68,494,241,792 bytes reported physical RAM; NVIDIA driver
32.0.15.9186. The NVIDIA-connected desktop reports 1360×768 at 60 Hz, and the
Intel-connected display reports 2560×1440 at 164 Hz. Adapter selection is read
back from the actual rendering device. The experiment renders a 2560×1440
SubViewport and scales it into a 1360×768 window. Engine callback intervals
measure rendering workload and scheduling; they are not Windows present timing
or evidence of full-screen 1440p displayed-frame pacing.

The frozen [recipe](../../../tools/benchmark/recipe.json) uses 70° vertical FOV,
near/far 0.05/15,000 m, render scale 1, 2× MSAA, no TAA or VSync, a 120 FPS cap,
10-second warmup and a continuous 600-second measurement per fixture. Actual
readback reports a 4096 directional shadow atlas and four cascades over 6000 m.
The three fixtures are clear, dusk and overcast. Clear has no cloud meshes;
dusk and overcast use 96 opaque shadow-casting cloud meshes and different lighting. These are visual proxies
and do not model volumetric weather or operational visibility.

The scene contains 64 synthetic 1250 m terrain planes with 32×32 subdivisions,
one 30×1200 m runway, 24 markings, 60 buildings and 2400 instanced cone trees.
Every five seconds a fresh identical plane replaces one of four far corners.
Timestamped events bind deadline, epoch, corner, CPU submission and actual node
counts to the raw frame trace. Missed periods are skipped. The checked bound is
64 active terrain nodes plus at most one queued old node during replacement;
it does not establish GPU allocator retirement or a production terrain cache.
Disk/GIS coverage and physics contact streaming are absent.

## Measured results

All three fresh exported captures use the same accepted source at
`0ce6d6f469df23c6c3f7e0f60e2d3d91624a183c`, exact frozen recipe and Godot
`4.7.2.stable.official.ed1daf0bf`. Each retains 72,004 distinct positive GPU
observations and passes all twelve engineering checks without filtering slow
frames. The [compact qualification receipt](renderer-qualification.json) binds
verified summaries, raw artifacts, staged source manifests and exported PCKs.

| Fixture | Measured seconds | Frames | Average FPS | Callback p95 / p99 ms | GPU p95 ms | Peak working set bytes | Peak engine allocation bytes |
|---|---:|---:|---:|---:|---:|---:|---:|
| Clear | 600.009319 | 72,004 | 120.0048 | 8.385 / 8.413 | 0.736 | 623,087,616 | 336,898,240 |
| Dusk | 600.009327 | 72,004 | 120.0048 | 8.379 / 8.427 | 2.547 | 622,940,160 | 336,902,848 |
| Overcast | 600.009336 | 72,004 | 120.0048 | 8.376 / 8.404 | 2.516 | 622,837,760 | 336,902,848 |

The frozen limits are average FPS at least 60, callback p95/p99 at most
20/33 ms, GPU render p95 at most 14 ms, at least 95% unique GPU timestamp
coverage and each sampled working-set/engine-allocation peak at most 12 GiB.
The 120 FPS cap limits interpretation of average FPS; these results do not
measure an uncapped maximum. Engine allocation is not driver-reported VRAM.

Each capture verifies 122 terrain attachments including warmup, 23 origin
rebases, 64 steady terrain nodes and at most one queued predecessor during
attachment. The actual WAV stream/playback retire after measurement in
17.930/9.564/17.773 ms and 4/3/4 process opportunities for clear/dusk/overcast,
respectively, with 64 active and zero queued nodes. Each exits zero, reports the
joined bridge, and contains no error or resource-leak rejection. Changed pixels
in the paired origin images are 0.38748%/0.40091%/0.41805%, below the frozen 1%
budget; projection and relative-emitter checks also pass.

Clear preserved two existing owner preview windows, reported paused by the
coordinator; their rendering activity was unmeasured and may have influenced
timings. Dusk and overcast prelaunch inventories found no owner preview or
benchmark process, and the coordinator reserved the GPU for these sequential
runs. This is not an exclusive whole-OS workload claim. One earlier dusk attempt
exited before its report/cleanup; another was stopped on the coordinator's hold
for owner defect debugging. Neither contributes samples or qualifies.

The engineering decision is to retain Godot Forward+ for production integration
within this measured proxy scope. The current interactive preview uses
Compatibility, so these measurements do not establish its gameplay performance.
Independent review recomputed each exact summary and checked source/tool/payload
hashes, raw timings/memory, attachment cadence, actual image pixels and cleanup.
The native-resolution synthetic panel labels were inspected as readable; this
is not final instrument or pilot acceptance.

The earlier static overcast baseline completed 600.009323 seconds/72,004 frames,
120.0048 average FPS, callback p95/p99 8.374/8.397 ms and GPU p95 2.635 ms. Its
working-set peak was 595,607,552 bytes and Godot allocation peak 336,857,408 bytes.
It predates the terrain attachment workload and retains its historical cloned
verifier; it is a comparison baseline, not the final workload witness.

Average FPS is count divided by raw elapsed time; quantiles use nearest rank.
No slow frames are removed. Delayed GPU observations have captured-frame IDs;
only distinct positive observations contribute GPU quantiles. Render CPU costs
include measured viewports and frame setup, excluding other main-thread work.
Godot's TIME_PROCESS monitor reports one-second maxima and is labeled separately.
The [pinned rendering server source](https://github.com/godotengine/godot/blob/ed1daf0bf001b61586d9930840f2f1394092c079/servers/rendering/rendering_server_default.cpp)
binds viewport timestamp observations to captured frames; the
[pinned main-loop implementation](https://github.com/godotengine/godot/blob/ed1daf0bf001b61586d9930840f2f1394092c079/main/main.cpp)
defines the process-monitor semantics. These observations cannot establish the
architecture's whole-main-thread p95 target.

## Readability and origin continuity

Actual exported 1920×1080/70° overcast and 1360×768/80° dusk diagnostic captures
were inspected at their native dimensions. Main labels, six fixed numeric
examples and green engine/radio text can be read. The small unit labels and dial
ticks are marginal in the smaller, wider-FOV capture. Reused generic dial scales
and example needle placement do not constitute accurate aircraft instruments.
The conspicuous synthetic/fixed-values labels remain visible. The smaller view
motivates cockpit zoom/UI scale and dedicated marked instruments in
[#23 camera](https://github.com/brettbergin/flight-simulator/issues/23),
[#24 instruments](https://github.com/brettbergin/flight-simulator/issues/24) and
[#27 cockpit acceptance](https://github.com/brettbergin/flight-simulator/issues/27).
This engineering inspection is not the pilot's readability signoff.

Both diagnostic runs completed 2401 frames over 20.0075 measured seconds, with
six verified tile replacements including warmup. Callback p95/p99 was
8.371/8.391 ms at 1080p and 8.372/8.383 ms in the smaller view. GPU p95 was
2.490/2.159 ms, respectively. They are deliberately classified diagnostic;
alternate resolution/FOV and short duration cannot pass the canonical target.

Each GPU run saves an actual paired image at identical canonical state before
and after an origin transaction. Local particles are frozen during that pair;
TAA is disabled and RGB/RGBA captures are normalized before comparison. An
independent PNG decoder checks CRC/size/filter bounds and recomputes RGB pixels.
The preselected budget permits at most 1% of pixels to differ by more than
8/255 in any channel. The diagnostic pairs changed 8135/2,073,600 pixels
(0.3923%) at 1080p and 2661/1,044,480 (0.2548%) in the smaller view. This permits
small shadow/rasterization variation; it is not a claim of pixel identity.

During measurement, camera, canonical terrain parent, camera-mounted panel,
lighting, silent spatial audio and local-coordinate particles share one origin
version. Projection error has a 0.5-pixel budget, relative-emitter geometry a
0.001 m budget, canonical arrays remain unchanged, and a deliberately stale
participant version must be detected before presentation. Silent PCM
tests spatial geometry only; audible continuity and world-space particle
history remain unmeasured.

The [independent actual-Godot geometry proof](../../../tools/benchmark/geodesy/README.md)
passed 8616 checks and 500 transactions over twenty 50 km routes. Maximum
projection/reference error was 0.1490854 pixels against the frozen 0.5-pixel
budget. Cardinal EUS signs, orthonormal handedness, dateline and near-pole camera
projections, source changes and mixed-origin negatives are checked. Exact-pole
yaw ambiguity is explicit. This CPU geometry proof is separate from GPU images.

## Actual asset authoring and CI boundaries

The [original Blender-to-GLB fixture](../../../tools/benchmark/pipeline/README.md)
was generated with the separately pinned optional Blender 4.5.14 LTS authoring
tool. It contains two original cuboids, a translated pivot, PBR material and a
one-second rotation. Independent GLB accessor checks verify meters, Blender to
glTF orientation, parenting/pivot, linear material values and all 31 sampled
rotation keys. Actual Godot editor import confirms transforms, materials and
animation samples; the exported GPU scene visibly includes the imported mesh.
Nine meaningful corruption groups reject scale, parent, material, track,
midpoint and truncated/bounded-data failures. No manufacturer art or reference
document is redistributed. The
[rights record](../../../third_party/licenses/evidence/original-render-proof.md)
keeps original assets, procedural code, Godot/font terms and authoring tools
separate.

Hosted CI checks scripts/resources, actual GLB import, CPU geometry and explicit
headless GPU rejection. It cannot provide a GPU performance pass. Independent
packet tests reject forged summaries, corrupted source/payload/verifier bytes,
wrong device/settings, discontinuous traces, inadequate memory coverage,
runtime/leak diagnostics, changed image statistics and forged tile events.

The first release attempt failed because official templates reject command-line
scene overrides; the runner now stages its main scene before export. Initial
image-format assumptions and generator-audio shutdown leaks were found in actual
runs and fixed before the final workload. Those failed experiments remain
invalid, rather than being included in performance results. Independent review
also found that editor import alone missed a lazy-loaded panel script. The
corrected CI helper explicitly loads all seven staged script/scene/GLB resources,
checks actual editor/archive/tree/lock identities and executed loader/settings
bytes, and rejects a separate invalid lazy panel. Root independently reproduced
the successful compile/headless-rejection and three source-drift negatives.

Two clear-sky attachment runs completed their 600-second measurements but leaked
two objects at exit. The verbose repeat identified `AudioStreamWAV` and
`AudioStreamPlaybackWAV`, each with one retained reference. Both captures remain
invalid. The [pinned audio server](https://github.com/godotengine/godot/blob/ed1daf0bf001b61586d9930840f2f1394092c079/servers/audio/audio_server.cpp)
retires stopped playback through mixer and main-thread updates. Immediate exit
after stopping the emitter could precede that retirement.

The revised fixture stops measurement, closes the trace/report, then observes
weak references to both actual resources while allowing engine updates. It
requires both resources to disappear, 64 active/zero queued terrain nodes and
at least two process opportunities within a two-second monotonic deadline.
`cleanup.json` and its matching runtime marker record this separate interval;
the independent verifier checks their clocks and bytes. Shutdown leaks still
invalidate a capture. No measurement thresholds are relaxed, and this check
does not establish GPU allocator retirement. Silent PCM is the audio scope;
an immediate pause request before deferred playback registration did not prove
an actual paused state.

Actual isolated ownership controls passed: ordinary and queued-node cleanup
exited cleanly, while a retained WAV reference and an extra active terrain node
each exhausted the deadline and exited with failure. A revised short exported
capture observed both resources retire after four process opportunities. Its
20-second measurements remain diagnostic; the three canonical captures above
now demonstrate the same bounded cleanup after their full measurements.

## Artifact identities and remaining gates

Frozen renderer source SHA-256:
`f86759f666d9de3baa412f53a144380aeea3ba1cf7e1c69d3d1b96e5a4183bff`.
Frame source:
`10f4298a3ad2baafdf0bebbad27dc8930ca0cc0e97f7c3cf29869569054b3787`.
Panel source:
`12c2d3a8be1fe212ba119e393e062f553c41cad174b82e80f63f73782fb24a87`.
Exact staged project/export/native/tool hashes, source settings, raw CSV,
sampled process memory, runtime reports and native-resolution PNGs stay in
ignored `.local/benchmark/` run directories. Raw local paths are not committed.
The compact qualification receipt identifies reviewed captures and their
artifact hashes. Large local packets are retained for review and reproduction;
this PR does not publish a simulator release or promise public raw artifacts.

Whole-main-thread CPU cost, Windows present pacing, end-to-end input latency,
concurrent authoritative-worker scheduling, real-region streaming and residency,
production instrument readability, temporal weather, audible continuity and
pilot evaluation remain separate product evidence. These are explicit P2/P4/P7
gates, not passes inferred from primitive proxies.
