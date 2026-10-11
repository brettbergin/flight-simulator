# Original exterior cabin finish

Issue [#209](https://github.com/brettbergin/flight-simulator/issues/209) is a bounded P2 presentation leaf over the original synthetic aircraft. **Status: focused mesh, paired development images, three-context Windows package checks and packaged visual smoke passed. Independent final delivery review passed; current protected CI remains pending.** Historical planning below is retained; the dated development result records only work actually observed. The accepted aircraft/glazing work [#108](https://github.com/brettbergin/flight-simulator/issues/108), propeller presentation [#201 / PR203](https://github.com/brettbergin/flight-simulator/issues/201), [rights register #13](https://github.com/brettbergin/flight-simulator/issues/13) and [renderer proof #18](https://github.com/brettbergin/flight-simulator/issues/18) are prerequisites.

## Visible problem and intended result

The reviewed proposal records six selected existing nose/chase images: abrupt light bands along the elliptical cabin, segmented glazing and decorative paint rods that can float outside or intersect the shell. Those observations identify a presentation problem; static images do not establish a simulation fault. They are baseline observations, not acceptance captures for this change.

The intended correction is continuous station shading and a restrained mirrored ivory/teal/navy paint pattern directly on the opaque shell. Shared per-station derivatives replace row-local shading slopes without moving vertices or changing triangle membership. Only four decorative beltline/tail rods are removed. Body-only vertex colors use an isolated material so glass and the ivory material shared by wings remain unchanged. Simpler clean paint is preferable to extra textures, shaders, coincident faces or a material framework.

## Preserved geometry and authority

Keep the eight authored stations, 16 span subdivisions and 64 angular segments, every vertex position, triangle index/winding and body/glass classification. Preserve the two shell surfaces, `ContinuousCabinShell`, existing function signatures and `airplane/gears/propeller` handles. Local axes remain +X right, +Y up and +Z aft. Native pose, gear/contact origins and wheel offsets remain authoritative; the propeller pivot at `(0,0,-3.18)`, subtree and native phase adapter remain unchanged.

Wings, structural struts, glazing/frame boundaries, spinner, fin, small existing bulbs and other details remain in place. Camera eye/envelope/FOV, lighting, scenery, controls, physics, models, dependency pins and numerical budgets are outside this leaf. Smoother normals cannot remove actual geometric corners or prove photorealism. New geometry/color expressions remain original project MIT source; no external assets, manufacturer livery, logos, registration numbers or aircraft-dimension claims are introduced.

## Required verification

| Gate | Required evidence | Current status |
|---|---|---|
| Geometry preservation | Baseline-versus-candidate positions, triangle/body-glass membership, bounds/counts, clockwise/outward winding and wing checks | Passed focused headless construction and three-context package checks |
| Shading and material isolation | Finite unit outward normals; shared station and angular-wrap continuity; deliberately perturbed boundary rejected; palette/glass/shared-wing-material checks | Passed focused checks and negative fixture |
| Structural/native handles | Four decorative rods absent, structural struts retained; exact gear/contact and propeller pivot/subtree checks; accepted native phase proof remains separate | Handles/local geometry passed; native-origin mapping is separate |
| Source and delivery | Pinned isolated script load/compile, then serial frozen-source editor/export/rebuilt-library checks with source/PCK/modules/models/notices/rights closure | Isolated compile/load and three-context Windows delivery passed |
| Paired visual result | Original before/after nose/right/left/aft and ordinary chase/nose images with independent inspection at the existing small and large window sizes | Development comparison, packaged visual smoke and independent final binding review passed |
| Integration | Final source/receipt/image bindings, independent review and required current CI | Source/development reviews and actual package passed; independent final package review passed; current CI pending |

Pair views at the same paused native state, camera transforms/FOV, lighting, renderer and window size. Begin with unobstructed nose/right/left/aft at 1280x720, then ordinary 960x540, 1920x1080 and 2560x1440 chase/nose views and useful close side/nose views. Preserve copied native state, held controls, tick, command sequence/count and paused state during camera inspection. Do not improve framing, zoom or environment between a pair to conceal defects.

Review actual original images for smoother cabin lighting, clean flush paint, intact glazing/frames, no backface holes or glass paint, and no wing/gear/propeller displacement. Mesh assertions alone do not establish a useful visual improvement. Retain first failures and distinguish development captures from the final source-bound exported package. Existing native-driven dynamic propeller coverage is reused separately; this leaf does not require a numerical/native rebuild or replace that evidence with static pictures.

## Baseline and requirement scope

The documentation proposal is based on commit `646ca112428ab59439af21be8e4bbc8440d43283`. Baseline production source SHA256 values are:

| Source | SHA256 |
|---|---|
| `app/proof/interactive/flight_world.gd` | `95ef69caecfb68dfe22326cb3c2c585a09b659388a098ea0c9a5dad038f68b57` |
| `app/proof/interactive/flight_aircraft_checks.gd` | `1a55b8bd7511fa6c88071c6f5f4ba853ae33cb589ef5b719ff4c391a29483994` |

The [requirement map](../../requirements.md) records **partial contributions** only:

- **PRD-002:** preserve the separation between authoritative simulation and cosmetic geometry/shading. This does not validate forces, propulsion, fuel, mass or contact behavior.
- **PRD-015:** preserve usable existing outside/side/taxi sight pictures and state-driven presentation while improving cabin surfaces. No new operable cockpit control, instrument or calibration is qualified.
- **UX-010:** inspect the existing nose/side/aft/chase views without changing camera presets, eye, FOV policy or flight state. This does not complete view controls, mouse look, adjustable head motion or the full camera requirement.

The original-aircraft label remains visible. This work does not establish manufacturer fidelity, C172S applicability, training credit, pilot evaluation or P2 acceptance. Existing engine coverage and frontend numeric-admission work retain their separate issues and gates. No new shared interface is expected; any required interface change needs its own reviewed contract before consumption.

## 2026-10-11 development result

The original world after-image is SHA256 `ebcca950eb3ea7bebd17c3538d1ab6792fcfd3af06f5a5d1719725bb162ae7a3`; regression after-image is `f35d2671b0e6f5d44590de87226225c6fa62ce8aa63f699baf00bef141398952`. Independent source review approved their bounded ownership. Actual pinned headless construction passed31 checks, including exact before-image body/glass vertex streams, both original wings, outward winding/unit normals,384 station groups,113 angular-wrap groups,216 material-boundary groups and a deliberately perturbed normal rejection. Shell triangle counts remain13,396 opaque and940 glass. Gear tests establish retained handles and local visual geometry, not native contact-to-origin mapping.

The new normal-continuity allowance is a pre-observation0.0003 Euclidean unit-direction comparison for Godot's oct16 storage and a documented binary32 engineering margin; it does not change historical unit/winding checks or native physical criteria. [Pinned normal packing/readback](https://github.com/godotengine/godot/blob/4.7.2-stable/servers/rendering/rendering_server.cpp) and [octahedral mapping](https://github.com/godotengine/godot/blob/4.7.2-stable/core/math/vector3.cpp) support this presentation bound. The preserved first source draft was revised before any new-check output; no failing candidate output was used to fit it.

Two fresh projects derived from accepted PR203 shipping resources produced13 original images each: four1280x720 nose/right/left/aft views and chase/nose/cockpit views at960x540,1920x1080 and2560x1440. Both used the pinned authoring executable, Compatibility and the reference RTX3090. Baseline379 and candidate382 observer checks passed with clean imports/logs, full binary authority equality within every passive camera/viewport comparison, unchanged mutation ledgers and actual native/audio joins. There were no advancing steps or pilot-control submissions; initialization/close use accepted paused zero-completion drains. Across revisions the actual binary camera/projection/mode/look/propeller fields and selected native fields were compared; full cross-session authority identity and full Node3D transform binary capture are not claimed.

Independent review of all13 pairs found a useful modest improvement: smoother cabin highlights and flush teal/navy finish, without apparent white glazing, displacement or floating-stripe regressions. Sharp paint ends, stylized glossy windows and the dense small-window overlay remain. The cold profile's existing unavailable wind cue is intentional under its current qualified domain and is unchanged. These fixed tick-zero authoring-project captures do not prove flight behavior, moving-light appearance, performance or shipping-executable images.

Retained artifact identities: baseline receipt `f06438bc7f4c420c5fe95a682d8f71cc957c38520bc431f3496ef8159f754034`; candidate receipt `46df1f37b69e5222ec8d3a4586ea4ad42a04763bb23fdc847ae50729c2a33086`; independent development artifact review `111601b302d57e7aedd033111ab615b2731d861ed74f329847e50791282e489d`; new test/host source review `e98b6e539e4cec1f58372dfd83dc09173ca541a631e17e9e876033141f85cfb3`. Final editor/portable/rebuilt-library qualification, final source/package review and current protected CI must pass before closing only #209.

## Normal readback allowance

The pre-observation normal test uses a direction-distance allowance of 0.0003. For Godot's oct16 encoding, conservatively bound each decoded UV coordinate error by `d = 1/65535`. The raw octahedral direction has L1 norm one and L2 norm at least `1/sqrt(3)`. Component perturbations bounded by `(2d,2d,4d)` give raw Euclidean error at most `sqrt(24)*d`; normalization contributes the reciprocal minimum length. Thus the paired direction allowance is `2*sqrt(72)/65535`, approximately 0.0002589541886. The remaining approximately 0.000041 is an explicit binary32 engineering margin, rather than a general floating-point proof. This concerns packed presentation normals only; no simulation or aircraft tolerances change.

## 2026-10-11 Windows delivery result

The frozen runtime sources at commit `48af5118986a816be11425b8b871f4ddb84fedce` passed the actual pinned Windows package pipeline. Its manifest SHA256 is `f7db714e457a30ab7f8f5a721fbeb9c7f8964a5acc3d5702d587be7b34303d0e`: 499 shipping files and 227 authoring sources. Editor, portable player and rebuilt-library player each passed the facade, cold-engine, pointer and ground-material checks. The package audit checked exact legacy trace repetition, selected-source/model/notices/rights bindings and complete PE/CRT loading within the payload. The accepted native source fingerprint remains `5e0abfeae9ffd249f8be3f4410d9903f30736698fcb276bdf72f3630132102e5`; exterior presentation does not adopt a different flight model.

Retained unsuccessful attempts remain separate evidence: the initial 120-second facade supervisor timed out and joined/drained its owned process; the next 600-second attempt failed the actual sandbox junction/cleanup fixture checks. A fresh normal-permission run used the existing 600-second parameter and passed unchanged checks. No assertion, source fixture or numeric limit was weakened.

An isolated byte-exact copy of all 499 shipping files then passed the shipping executable's existing visual smoke, with a clean log, native termination and 59 original PNGs on the reference RTX3090 using Compatibility. Visual receipt SHA256 is `6f4ee389cd45ba870b0a3ebeb513e986414ebe9031cc53a20b8da4241905d349`. These include four exterior angles and 16 short moving chase/orbit frames under admitted controls. This shipping campaign is separate from the paired tick-zero development campaign; it is not a paired shipping before/after comparison, performance measurement or human flight evaluation. The receipt's `prepared_world_sha256` identifies the native prepared-world fixture; rendering-source identity comes from the package's actual source/PCK bindings.

Root inspected original shipping nose, right-side and moving-chase images. The smoother shell and flush paint are present; the aircraft and scenery remain visibly stylized prototypes. Independent delivery review passed; final current-head CI is still required before closing only issue209. Aircraft source/calibration, manual hardware/pilot evaluation, unresolved numeric admission and mixture-decay coverage, and phase gates remain open.

Independent final package/image review passed 4,888 bounded checks with no findings. Review SHA256 is `0e1e14a8e0ebb64e4e5f93b2d5018ca312b2800490da9ceb80763eeb4dd4bd7b`. It verified all 499 shipping files, 227 authoring bindings (192 byte-exact, 35 differing only by CRLF), 29,415 schema-valid legacy records, seven loaded modules including five CRT modules, selected-source/model/notices/rights closure, and the isolated shipping-copy binding. Each of the three contexts passed facade63,774, cold-engine16,108, pointer120,489 and ground-material371 checks. The mesh group retains six earlier assertions and adds25 new assertions, for31 total. Twelve meaningful original shipping images were independently inspected; all59 PNG artifacts were bound separately from development images.

The final PCK is 7,931,516 bytes, SHA256 `6af86aa21a3d80a7cab94f2a8458dd1ed1f0c9cfbe27b784b695c2b843ec5382`. The independently audited rebuilt-library stage has481 files: its source/runtime files differ only at the two intended JSBSim DLL copies, while the generated smoke log, smoke receipt and trace are checked separately. Eighteen audit-evidence/notice files added after replacement complete the499-file deliverable. Earlier auditor assumptions that these rosters must be identical and that all31 mesh assertions were newly added were corrected in a fresh review; the original auditor reports remain retained. No product, test or native source changed to satisfy those audit corrections.
