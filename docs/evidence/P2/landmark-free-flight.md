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

The source-bound pinned Godot leaf run passed 146 checks: reference geometry, copying, invalid selection atomicity, unavailable/retained state, fresh-session clearing, manual completion, both pavement ends, focus/button identity, aid visibility and minimum UI bounds. Integrated native state preservation, editor/export/replacement packaging, and exported GPU captures remain pending for the final candidate. Their final exact source/package identities and observations must be recorded before this leaf closes.

The original flat scenery, simplified aircraft, pilot/hardware assessment, operational navigation, source-supported C172 validation, durable progress and P1/P2 gates retain their existing limits. This feature supplies an optional goal for free flight, not a qualified lesson or production route planner.
