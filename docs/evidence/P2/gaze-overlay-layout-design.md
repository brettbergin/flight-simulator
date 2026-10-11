# Deliberate gaze and overlay layout

## Result

[Issue179](https://github.com/brettbergin/flight-simulator/issues/179) establishes a bounded incompatibility: the existing fixed docks cannot guarantee unobscured exposed primary instrument drawing throughout the measured gaze and zoom domain. Actual original pixels show map, circuit, engine-control and current manual itinerary cards covering visible instrument markings. This is a design result, not a UI correction or proof that every stable layout is impossible.

The twelve recentered control images show all six primary instrument faces and captions clear at the existing default FOV in both physical views and both profiles at all three sizes. Deliberately looking away can also remove instruments from the camera view; that separate camera limit is not called overlay occlusion or a readability fix. Native status, controls and release guidance remain visible in the reviewed originals.

## Frozen baseline

The diagnostic uses qualified runtime `028321cd94a102568041b59809515652d726a95c`, accepted without a Git-tree change through [PR190](https://github.com/brettbergin/flight-simulator/pull/190), merge `f7782df6b43d090d971efd14e6354dac07805f3a`. Subsequent [PR191](https://github.com/brettbergin/flight-simulator/pull/191) changes only the original-audio evidence and documentation index. [ADR019](../../decisions/019-ordinary-flight-overlay-layout.md) remains the current presentation policy; [ADR017](../../decisions/017-frontend-pointer-engine-controls.md) remains pointer authority.

Package manifest SHA256 `75c001a9efd683910f15c11b0d2e18de1a9358ed278080186b9b38bd8d698797` binds494 shipping files. PCK SHA256 is `06c1a028907e4f2d8686caaed8e2610671df3063e0d891c4c657b7ebe46354af`. The source preparation froze actual layout/camera sources and four previously qualified recentered physical images before the new measurement. Those older images are baseline controls, not current gaze evidence:

| Previous960 physical control | Original PNG SHA256 |
|---|---|
| Legacy COCKPIT | `df0d1b8bc94d0d350f5ddec744a33a5f8a8c84af866c67776cfa487d0b37fb78` |
| Legacy PANEL | `519e4950c17b70d7b1d63d32344bf85e0a211f6757280c4f060dc373b6e6f230` |
| Piston COCKPIT | `f3d1b1b4b44889f34a350fa465f4f5c2bd94084396cc049f6c27f47fb238a138` |
| Piston PANEL | `e48d0eb90b0bf665f83841744cbd8e04a9e8c45632b87cdfdf43ee680ac769ea` |

## Executed scope

A fresh disposable copy of the exact qualified PCK and native modules ran through the pinned Godot4.7.2 authoring executable on Windows/OpenGL Compatibility, RTX3090. This is packed-resource observation, not a shipping-executable visual test or another complete package qualification. The external observer SHA256 is `2442f5fa68c72d4bbf462bdb7960704ad2743de9bd02a3658c37ef1465b83d07`; its source, preparation inputs and actual packed resources are separately bound in the receipt.

The540 metadata cases cover960x540,1920x1080 and2560x1440; COCKPIT0/PANEL3; legacy plus piston expanded/collapsed; map open/closed; five deliberate gaze fixtures; and FOV35/default72-or58/90. The42 original images include twelve recentered controls, twelve known-negative directions, eight minimum-window FOV extrema, six closed/collapsed variants and four down/rear camera controls. Available legacy circuit and honest piston-unavailable circuit indications remain distinct. This samples neither arbitrary gaze nor every aid/remapping/input state.

The observer uses the actual paused native source at tick0 and accepted Scene/layout helpers, with an explicitly labelled test-only ordinary-presentation exposure that hides the menu while remaining paused. Camera intent is assigned directly for measurement; no real mouse-look delivery is claimed. Map changes use configured complete Raw admission followed by production dispatch, not an OS event. No Resume, completed Run or pilot submission occurs.

Across each gaze/FOV case, original binary snapshots preserve native/facade state, full released synthetic Raw, mapper/filter/latch/debt, held controls/systems, recording, origin and mutation ledgers. Actual pointer look/rearm/terminal, widget capture/preview/terminal/await-release and global mouse mode are included. The fixture explicitly asserts idle capture and visible mouse; legitimate rearm bytes are preserved rather than assumed empty. It does not test active capture relocation. Each of42 draw captures retains byte-identical original before/after truth; three deduplicated authority files and original Variant projection metadata remain separate from JSON navigation records. Native and audio owners join with clean exit0; all494 original and494 copied payload identities remain unchanged.

## Geometry and original-pixel findings

Projection uses the actual Camera3D transform, near plane, FOV and panel QuadMesh transform. The logical1024x512 panel,2048x1024 texture and scale2 remain explicit. Source-derived cells are conservative bounds;128-gon face perimeters approximate authored drawing; actual font advance/ascent/descent rectangles are not glyph ink masks. Incomplete near/behind polygons have null, indeterminate overlay intersections. Viewport clipping is recorded separately. Original pixels decide whether exposed instrument drawing is actually covered.

| Reviewed negative | Visible result |
|---|---|
| 960 COCKPIT, gaze(+1.1,+0.15), default72 | Left locator/card covers exposed altimeter and lower instrument markings in both profiles. |
| 960 PANEL, gaze(-1.1,+0.15), default58 | Right circuit or engine/locator covers exposed TAS and heading drawing. Closing the map or collapsing controls does not establish a general clearance guarantee. |
| 1920 PANEL, same negative gaze | Locator covers exposed TAS upper ticks; its central readout can remain clear. Piston bottom feedback/notice strips also overlap exposed lower heading/caption regions. |
| 2560 PANEL, same negative gaze | The right dock is largely above exposed TAS, but piston bottom strips still overlap exposed heading/caption drawing. |
| Down/rear camera controls | Instruments leave the camera view or lie behind/near its projection; these are camera limits, not clear six-pack verdicts. |

Eight of the22 reviewed legacy originals contain actual side-look primary-ink overlap. At larger sizes some conservative intersections involve blank cell space, while other instruments are camera-clipped. Those cases are not promoted to pixel collisions. The20 piston originals separately retain their actual collisions and default controls. The2560 images were displayed downscaled by one review tool; that review makes no fine-edge metrology claim.

Independent identity/legacy review SHA256 `b363f7d91e8da3918d0e6fd76fd962987fe74536d3c602eeee3733874c4e6b74` passed31261 offline checks, bound all33 packed resource sources, the ordered540/42 roster and all130 PNG/truth identities, and directly inspected22 legacy originals. Independent piston review `d073cdf560287e379f49e374ccc57eb8484abc6543384edd50d35fe1ab24f277` directly inspected20 originals and rehashed62 associated PNG/draw/authority files. Binary equality is distinguished from receipt/source semantic checks; no independent general Variant decoder is claimed. The observer author supplied a separate six-image design analysis, with authorship disclosed. Root directly inspected representative current negatives and a default control. All originals and reports remain locally retained under diagnostic run `638a3aa69179445d807747bee76f9c62`; they are not shipped as public pilot recordings or a standalone reproduction kit.

## Bounded successor

The smallest proposed experiment is an explicit paused-menu Default/Left/Right dock choice, held fixed until another choice. Mirror the whole affected overlay column and its opposite wind/feedback/notice group using existing dimensions, fonts, hit regions and strings. Preserve CHASE, physical camera/projection/FOV, requested hide/collapse states and native header/control strips. Keep geographic projection and current/retained source semantics unchanged. Do not follow gaze, force a HUD, recenter, close the map or auto-collapse controls.

The540-case sweep measured only the existing fixed layout. It does not establish the feasibility of any alternate dock. [Manual dock contract spike #192](https://github.com/brettbergin/flight-simulator/issues/192) must first measure a labelled private candidate with original pixels and actual font/hit rectangles, retain failures and define its exact useful domain or an explicit incompatibility result. Only a feasible independently reviewed decision can authorize a consumer. A reserved3D viewport would change aspect/projection/render/input composition and requires a broader separate design.

Any accepted successor must specify ADR017 capture retirement before geometry changes. Ordinary modal entry already retires a real capture; choosing a dock must not retire it twice or consume another generation for an already retired empty capture. Preserve actual held-button rearm until complete Raw observes release and then a fresh press. Identical choices and gaze-only frames are generation-invariant. No manufactured button-up, hidden starter pulse, native command or implicit Resume is permitted. Actual live capture/drag/starter/modal/release tests belong to a future consumer; the idle diagnostic cannot replace them.

Proposed contract ownership is `docs/decisions/021-manual-flight-overlay-dock.md`, a separate contract-evidence report, `docs/contracts.md` and canonical backlog/index/requirement/phase mappings. A later consumer would own only the existing Scene menu/layout, focused first-flight and pointer integration checks, a bounded image observer and necessary staging/evidence files. Existing widgets gain no speculative public API. Both tasks preserve physics, audio, native contracts, presets, saves and aircraft definitions.

## Preserved failures and remaining gates

The first private preparation failed because its source-list regex required a newline before a bracket that actually closes on the final path line; the partial copy remains unchanged. A fresh GPU attempt rejected all resource comparisons because JSON byte counts and runtime integer counts were compared as typed Dictionaries. The correction requires exact field shape, finite integral count and exact raw SHA/count equality. The next attempt bound all actual sources but hit an untyped conditional-array fixture assignment before the matrix. Initializing the typed list then appending the piston case preserves its original order. Each correction received independent review; every retry used a fresh copy. Failed preparations, logs, process records, sources and inventories remain failures.

This report does not fix gaze readability, validate an alternate consumer, establish live input/hardware/pilot acceptance, calibrate a C172 or close a phase. [The ordinary layout evidence](ordinary-flight-layout.md), [HUD correction](hud-caption-spacing.md) and [audio delivery](original-audio-cues.md) retain their separate scopes. Normal documentation checks and current required CI gate publication of this design result.
