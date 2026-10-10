# Paused first-flight orientation and circuit integration

This grouped implementation of [briefing #166](https://github.com/brettbergin/flight-simulator/issues/166) and [circuit reference #167](https://github.com/brettbergin/flight-simulator/issues/167) consumes [ADR018](../../decisions/018-first-flight-briefing-and-circuit-aid.md). It explains supported prototype starts, the current control assignments and manual software steps inside the paused simulator. The optional original circuit drawing is a geometric reference, not an aircraft procedure or evaluation. Final exported delivery, independent review and merge remain required below.

## Resulting interaction

Open **First flight** from the paused menu. The three choices are engine-off familiarization, a ready runway start and an airborne start. Each maps to the exact existing native profile/start pair in [the frozen original briefing](../../../content/scenarios/first-flight/briefing.json). Its 2,835 LF UTF-8 bytes have SHA256 `461ded9adf22b5265c6b487c23590efe30acb929f3c056356742a93206d400df`. The labels and manual steps do not establish C172 procedures, safe speeds or flight completion.

Choosing a fresh flight uses the existing explicit discard confirmation when required. Successful adoption opens the briefing **paused at tick0**, including confirmed replacements; it never resumes then pauses to simulate this result. Back returns to the paused menu, where Resume remains explicit. A failed replacement joins its native owner, closes the session and clears stale briefing/circuit/route presentation. Controls can be opened through its actual bound key or joystick action while the briefing is open. Flight commands and look remain consumed by the modal.

The opaque, tabbed panel separates actual copied state, supported choices, current assignments and manual orientation steps. `FirstFlightPanel.set_state(readback,preset,current_wind)` recursively owns copies and qualifies full ADR009 truth. BindingHelp uses the actual v1/v2 validator for all14 declared actions, six axes and v2 systems, including map/runway/zoom assignments, joystick identifiers and axis reversal. It distinguishes configured assignments from observed hardware availability; it polls no devices. Missing or invalid assignments and absent legacy engine systems remain unavailable. The panel has no native/device/clock/persistence call or Resume signal. Actual state labels retain TAS, wind NED and WGS84 ellipsoid height distinctions. Manual Next/Previous only changes the visible software step. There is no automatic phase detection, achievement, persistent progress or new saved-review field.

The checkbox requests a session-local circuit reference under current-session/current-widget/paused guards. It starts off and resets for a fresh session. Available geometry requires the exact legacy ready-ground profile, accepted world/anchor/source, calm adopted weather with all three actual wind components zero, and runway36. Unsupported selections remain selected and show an unavailable reason. The [separate geometry evidence](synthetic-circuit-reference.md) records the fixed source, domain checks and complete schematic.

The map retains its ownship center, selected runway, extent and existing manually selected route. Its circuit layer clips geographic segments without fitting the whole circuit into the locator. The separate card fits all fixed points and five labels. When the enabled locator shows the current manual target, it suppresses the duplicate route card; closing the map restores that actual card in the freed space. It never advances or rewrites the route. Presentation uses side columns in cockpit views and clears the lower chase instrument overlay. Aid off restores the previous layout. Unsupported cold-engine sessions use a compact unavailable notice that leaves the expanded engine controls accessible.

## Executed development evidence, 2026-10-10

Pinned Windows Godot4.7.2 and the actual qualified coupled backend ran in an isolated staging project with fresh process profiles. The six focused groups passed **2,688 assertions**, with no failures or native/audio ownership leaks:

| Group | Assertions | Evidence scope |
|---|---:|---|
| Original briefing fixture | 18 | Exact content/choice admission and malformed/missing source rejection |
| Copied panel and binding help | 116 | Current assignments, owned copies, manual steps and unavailable state |
| Geometry/source admission | 297 | Full qualified baseline, copied binary64 values, domain negatives and frozen points |
| Schematic/notice card | 1,222 | Full fixed diagram, five legend labels, compact unavailable fit and clearing |
| Independent map projection | 58 | Independently prepared clipping/translation cases, copied state and route/extent preservation |
| Actual integrated scene | 977 | Ten coupled adoption rows, real native pause calls, immediate/discard/failure paths, modal safety, rebase and three-size layout matrix, including drawable route-footer bounds |

The scene tests observe the real facade/native adapter. Their sole production override supplies complete synthetic Raw input, plus a counted internal facade-construction seam; they do not replace lifecycle or physics methods. They compare complete already-paused native truth, mapper state, recording, origin, held/pending controls and observer ledger. Adoption records require tick0, a nonempty all-successful pause-attempt ledger and zero completed native Run calls. Actual resume/tick behavior is checked separately. Rebase changes the committed rendering origin while preserving native flight and absolute geometry. Named fault injection tests exercise joined failure recovery.

The headless layout matrix covers ready-ground and cold-engine profiles at960×540/1920×1080/2560×1440 in default cockpit, panel and chase views. It projects the actual six bezel mesh bounds and checks card/text, native status and engine-control slots. These checks establish bounds, not pixel readability. The older ordinary cold map can still cover existing instruments/controls; this iteration does not claim to repair every aid-off or cold-map layout.

An actual RTX3090 OpenGL Compatibility run passed **644 checks across39 original GPU views and78 paired full binary Variant truth files**. It includes15 briefing pages, nine available circuit/map views, nine closed-map route-card views, three aid-off views and three unsupported-runway views. Each image is bound to actual source hashes and unchanged before/after truth. Ordinary choice/checkbox/Back/Resume callbacks and one deliberately scheduled native tick per window size are used. Map changes use configured binding admission followed by actual action dispatch; this is not physical event delivery. The host is manually scheduled during capture, so the run does not measure continuous-flight performance. Separate independent pixel review is required; capture success alone is not visual acceptance.

The upstream-only build must observe its own complete native paused baseline and preserve the frozen original capture separately. It cannot relabel a saved capture's source fingerprint. An initial local attempt correctly failed because an old bridge DLL lacked the current `angular_integration_method` field. That failed attempt is retained; it is not qualified evidence. A pinned rebuild and fresh actual upstream integration are required.

## Delivery and remaining gates

Eight recursive source groups bind all13 new authoring resources to staged runtime and corresponding-source copies, including the integration and visual observers. Compiler enumeration, generated UID admission and package manifests include these groups. Missing/changed sources, aliases/links, malformed receipts and missing groups must fail closed. Selected native source identity remains independently bound; coupled and upstream acceptance rosters are different and explicit.

Final grouped acceptance requires the current PowerShell/Node receipt and source checks, fresh upstream checks, all three Windows delivery contexts (editor, portable export and rebuilt library), one bounded exported flight interaction, independent three-size pixel review and all current protected CI. Development results above do not substitute for these gates. Original failed attempts remain retained separately.

Pilot/hardware observations, sensed instruments, selected C172S applicability/performance, aircraft procedures, formal training credit and broad P1/P2/P3 review remain open. The aid choice is session-local and is not stored in saved flight reviews. No prototype impression establishes aircraft fidelity.
