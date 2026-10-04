# Optional local landmark routes

Implementation candidate for [#130](https://github.com/brettbergin/flight-simulator/issues/130). This adds a session-local flying goal to the accepted original aircraft and synthetic airfield. It consumes [ADR007](../../decisions/007-sim-loop-facade.md), [ADR008](../../decisions/008-input-presets.md), [ADR009](../../decisions/009-cockpit-readings.md), the six [existing landmarks](../P1/airfield-landmarks.md), [controls PR118](https://github.com/brettbergin/flight-simulator/pull/118), and [cockpit PR121](https://github.com/brettbergin/flight-simulator/pull/121). The separate original piston runtime in #127 remains unmerged.

## Flying with a route

Pause and select **Landmark route**. Choose one of the three suggested itineraries or select up to four different landmarks in order, then select **Use selected route**. Return to the ordinary menu and resume when ready. The compact card shows the current destination, planar range in kilometres, bearing in degrees from the prepared airfield anchor's north, and the itinerary. The existing optional airfield locator also shows a purple line and destination marker.

Pause and reopen the board to select **Next leg (manual)**. Passing a landmark does not advance or score the flight. **Stop route** removes the itinerary. Either **Return** button replaces it with a reference to the selected synthetic runway's pavement end and selects that end in the locator. This is a geometric destination, not an approach clearance or a landing recommendation. **Show aids** hides or shows the card and target marker while retaining the route. A new flight clears the route; it is not saved to a profile.

## State and geometry

The private board receives owned copies of the six original scenery names/positions and the existing qualified Readback. It cannot call simulation, input, profile, clock or aircraft APIs. The scene performs the existing explicit pause before editing. Already-paused route edits are presentation operations. The UI retains focusable choice buttons across publications rather than rebuilding them each frame.

Geometry uses the native binary64 `canonical.anchor_eus_position_m`, with a source-derived canonical consistency check. Rendering interpolation, render-origin rebases and visual camera position are not navigation inputs. Range is `sqrt(dx*dx + dz*dz)` on the synthetic horizontal plane. Bearing is the wrapped angle from anchor north; within 0.01m of the target it is unavailable. This is neither sensed GPS nor a geodesic/global true course. The map clips an off-map target marker to the chart boundary; the card retains its actual planar range.

Paused readings remain labeled. Invalid, empty, host-blocked or retained terminal publications suppress range/bearing and the current map marker. Retained state preserves its historical identity. Manual itinerary completion has no achievement, proficiency, logbook or hours effect.

## Verification

The original reference generator uses independent high-precision Decimal angle evaluation and integer Pythagorean ranges. Its sixteen pre-runtime cases cover coincidence, all cardinal directions and quadrants, a noncardinal 5-12-13 triangle, north wrapping, translation, negative coordinates and large finite positions. The frozen comparison limits are 1e-7m and 1e-7deg; shortest wrapped angle comparison is used. The reference SHA256 is `bc21cab1e8bc9331c9b54338d62e4a535d46082c6bf73b992d3597d2d9ff8ad5`.

The source-bound pinned Godot leaf run passed 146 checks: reference geometry, copying, invalid selection atomicity, unavailable/retained state, fresh-session clearing, manual completion, both pavement ends, focus/button identity, aid visibility and minimum UI bounds. The integrated route scene passed 51 actual-native checks, including complete paused Readback/debt/mapper/origin/command/lifecycle preservation, explicit live pause, modal input isolation, three deliberately advanced native ticks, reset/join, raw-anchor rebase invariance and historical suppression. The unchanged instrument scene also passed its 107 checks.

The first exported screenshot review rejected visual qualification despite successful package/state assertions: the legacy locator classified native outcome `paused` as stopped. Its original images and receipts remain retained. The correction accepts current `completed`/`paused` outcomes and explicitly suppresses historical, blocked and stalled truth. Six new scene assertions exercise both current paused guidance and a labeled retained paused presentation fixture; the GPU fixture now asserts that the current locator actually permits guidance drawing. No aircraft parameter or comparison limit changed.

Final runtime source is `af32a05ddfcda800a11a397c338f5dd95fb773d9`. Fresh isolated package run `run-d3ab5e402a1e46a69fb3c6b4a4fd217f` passed:

| Context | Host assertions | Route geometry/UI | Actual route scene |
|---|---:|---:|---:|
| Pinned Godot editor | 741 | 146 | 51 |
| Portable exported runtime, empty PATH | 705 | 146 | 51 |
| Replacement JSBSim DLL in a Unicode path | 705 | 146 | 51 |

Each context also passed the existing 30,398 facade, 310 input and 3,226 instrument checks. Host counts are shown separately; the active leaf group counts match. Original whole-flight records remained equal between editor, portable and replacement runs. Exact source/corresponding-source, model pins, generated UID policy, tool identities and seven loaded native module paths/hashes passed the package audit. The native source identity remains `35cf7b603d99b9accb123405f7569a901ed9e28d32110acbc296b376facd6416`; bridge SHA256 remains `5fa8c9ff0bf82ce79b8110b625c17c8d62c589acc746ee05d6f785d2f6a7d256`.

The corrected exported GPU observer produced twelve actual captures: menu, chooser, current target and hidden aids at 960x540, 1920x1080 and 2560x1440. All dimension/state assertions passed. Each of its three sessions remained paused at native tick zero, and complete Readbacks stayed unchanged through the presentation edits. Screenshot review verified readable controls, the compact card, a visible purple destination line/marker, the correct PAUSED locator label and hidden target aids. This is short observer evidence rather than pilot interaction or flight-load performance acceptance.

Final manifest SHA256 is `fc7f7b937d740c2e8b24cde0e431de49730b4726958b82dac5f0bdee8e555295`; package audit SHA256 is `62475b3ecf28f4a228d0b864b7291ccc46b3a612095f4bccaa6da1eb64d551d0`; exported visual receipt SHA256 is `04bd6d691ee155db546771a6a46122d1be847fea5404fd864bbe44ca2b80e6d3`. EXE SHA256 is `d34d36f3be1a6c49c56525ae86469b92e4f417ddf0b43cf00dd80c385c4b0562`; PCK SHA256 is `0ec67c390d30eb3e92e57e66f3f1926246d78abd71090dc8e5de176d7d344b72`. The frozen package and rejected predecessor remain local engineering artifacts; the owner's earlier running game and profiles were preserved. Protected CI and independent final-source review are required before merge; later documentation-only evidence commits do not change these runtime bindings.

The original flat scenery, simplified aircraft, pilot/hardware assessment, operational navigation, source-supported C172 validation, durable progress and P1/P2 gates retain their existing limits. This feature supplies an optional goal for free flight, not a qualified lesson or production route planner.
