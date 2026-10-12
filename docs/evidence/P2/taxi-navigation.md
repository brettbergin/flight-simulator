# Original apron starts and synthetic taxi navigation

Status: bounded implementation merged in [PR227](https://github.com/brettbergin/flight-simulator/pull/227) as `0022c23be4491060cb62c3893ec96862ceaa3f8c`, completing [issue225](https://github.com/brettbergin/flight-simulator/issues/225). It consumes the checked [ADR027 contract](../../decisions/027-synthetic-taxi-navigation.md) from [PR226](https://github.com/brettbergin/flight-simulator/pull/226). Development observations below retain their historical scope; the final Windows qualification section records later engineering acceptance. Aircraft fidelity, pilot evaluation and phase exits remain separate.

## Player behavior

The First flight page adds separate Ready apron and Cold apron choices at the original PARK1 stand. Ready uses the existing direct-thrust prototype with its engine prepared; Cold uses the original piston prototype with its shaft stopped and existing startup controls. The original three flight choices remain separate.

The paused Taxi page offers outbound references for runway36/18 and return itineraries over each of the three original links. World signs, holding paint, the map and optional target marker consume one original layout. Route progression is manual. Selecting a route or pressing Next never moves the aircraft, supplies a clearance, scores a landing or changes flight controls. Successful fresh session adoption resets navigation; stale callbacks and historical readbacks cannot attach a route to another flight.

## Development evidence

The reference PC uses Windows, MSVC14.40, the pinned JSBSim local-window-v2 backend and Godot4.7.2. A fresh bindings-enabled native build completed, with independently qualified first-party fingerprint `047b9d60fce80506a095b7d3cd9d483b21743137fe00d66382216f746ce4156c`. The compiled source and build-control rosters retain 25 and18 entries. This raw-source development build does not supply committed-Git provenance for final qualification.

| Check | Observed result | Limit |
|---|---|---|
| Integrated package/source and camera admission | 74 tests passed | Offline admission fixtures, no rendered camera claim |
| Delivery staging | Identity26, camera32, reconstruction12 and strict taxi admission checks passed | Offline source/receipt checks |
| Native apron starts | The actual `interactive_apron_starts` CTest passed, producing26 observations | Bounded pose, engine, continuation and rejection checks; no taxi journey |
| Taxi Scene and Navigation | 677 checks passed over both real paused apron sources; host failures and stderr empty | Native adoption, pause/call/state/recorder invariants and manual navigation; no movement or legibility claim |
| Complete staged taxi group | 950 checks passed: layout139, panel77, map57 and Scene677 | Also passed in the fresh full interface run; no movement or visual claim |
| Complete native flight-interface regression | Passed, with76,606 harness checks, no failures and empty stderr | Isolated editor-native development; no portable, replacement, visual or aircraft qualification |
| Original briefing regression | 252 original checks plus native baseline join passed before the full run | Original four tabs, fonts, hit sizes and visibility assertions preserved |
| Native qualification self-tests | 29 native and11 player tests passed | Synthetic admission and tamper fixtures, not the actual physical/native qualification suites |

The first native apron run failed its unchanged fixed-position guard. The correction uses the canonical ECEF ray for the initial geocentric latitude because the vendor's rounded ellipsoid differs from the canonical frame; the existing initial-condition height solve adjusts radius before RunIC. The corrected fresh build passes the original position tolerance. No post-start relocation, hidden settling ticks, parameter edits or tolerance changes were introduced. The failed apron CTest and its 16 old-start observations remain retained.

Early integration staging attempts also remain failed evidence: an isolated source copy lacked its locked Node validator dependencies, and a later project omitted the required packaged Microsoft runtime files. Fresh offline dependency installation and exact runtime-file staging allow the focused native Scene checks to pass. These are staging corrections; failed packets are not relabeled as successful runs.

The first complete flight-interface run failed: legacy First flight circuit context clipped at960x540, and six original rejection assertions expected the pre-ADR027 error strings. A first layout correction fixed clipping but failed the original four-tab assertion. The final correction appends apron choices after the circuit guidance in Start & state, preserving all four tabs, original tests, fonts, hit sizes and callbacks. Rejection tests preserve the original six invalid tuples, use the accepted expanded-domain messages and add eight invalid apron combinations. The fresh full regression passed; earlier failed receipts remain failed evidence.

A separate six-attempt pilot-command journey run failed all complete journeys. Ready starts encountered the initially uncompressed gear/contact transient before their strict stationary hold. Cold starts completed actual startup, outbound taxi and stops for both runway ends, deliberate entry and takeoff, but exceeded the frozen longitudinal flight corridor before landing. All six native closes joined. These observations guide controller corrections; they do not establish landing, return-to-parking success, aircraft fidelity or a physics defect.

## Delivery requirements at the development freeze

At the development freeze, closure still required actual pilot-control journeys demonstrating cold startup and ready-apron taxi to both stop references, deliberate runway entry, takeoff/landing, traversal of all three return links and parking. Manual route advancement alone is insufficient evidence. Actual current14 native tests and preserved physical/reference suites, original21 plus14 apron camera rows, original minimum-size and larger visual observations, editor/portable/rebuilt-library checks, complete corresponding source/rights and current-head hosted CI remain required.

All signs, pavement, aircraft and route references are explicitly original synthetic practice content. This work introduces no real airport, surveyed geometry, C172 qualification, ATC clearance, training credit, automatic taxi, physics resume or pilot/hardware acceptance. Durable local players remain separate [issue219](https://github.com/brettbergin/flight-simulator/issues/219) and [issue220](https://github.com/brettbergin/flight-simulator/issues/220) work.

## Final Windows qualification

Final source head `edeaec785f3d9f11f667d3544d0975b082309343` passed all twelve hosted checks before PR227 merged. Fresh whole-flight editor, portable and rebuilt-library runs passed the native facade/input, all35 camera rows, taxi/ground, pointer controls, piston, observed replay and smoke checks. Independent review checked all876 committed source entries, all243 PCK resources, complete project and payload inventories, corresponding source, dependency notices and actual library replacement. The fourteen native tests remain attributed to unchanged qualified `892fd3b4156fea786cf81ddb061708a07582ff6b` source; a documentation or asset change does not invent a new native execution.

| Actual context | Original captures | Complete native journeys | Closure |
|---|---|---|---|
| Editor | 142 | Six passed | Game and all12 native lifecycle joins completed |
| Portable shipping EXE/PCK | 142 | Six passed | Capture exited0; separate final-reader correction qualified the original evidence |
| Shipping EXE/PCK with rebuilt library | 142 | Six passed | Capture and final wrapper exited0; all12 native lifecycle joins completed |

Each campaign exercised ready or cold apron departure, both runway stop references, deliberate runway entry, takeoff, landing, all three return links and stopped parking through ordinary native commands. Full native-state comparisons around paused interactions/captures and complete native-call, pilot-command and recorded-sample ledgers passed independent review. Manual Next was not used as movement evidence.

The original portable capture completed successfully, but its final wrapper rejected copied inventory paths because forward slashes differed lexically from Windows backslashes. All1517 original source/payload file rows retained exact bytes and hashes. A reviewed one-line path comparison correction and successful read-only postverification qualified those original results. The failed wrapper and initial unqualified review remain preserved. The subsequent rebuilt-library campaign used the corrected reader and completed with a clean outer exit.

Independent image review inspected every contact view and selected full-resolution originals. All142 rebuilt-library PNGs and decoded pixels matched the qualified portable captures exactly. No new visual blocker was found. Intentional gauge cropping in window/forward views, small slanted panel qualifiers, prototype scenery and near-zero wind formatting remain visible limits. These checks do not establish FPS performance, pilot comfort, manufacturer sight-picture accuracy or operational training.

The final independent review records are `taxi-edeaec-editor142-independent-review-v1` (SHA256 `99059c8d975e2b7d753b2c4f62920a12e496aa77964115cd5cb1e917dd3d7892`), the separate portable `qualified-portable-addendum-v1` (`80867024a7f7f6cffd9e453e75d590914e5d24b05db0fc3c7a619a6ddd12b285`), and `taxi-edeaec-replacement142-independent-review-v1` (`483a5bec2eef415d13c938de28211c00ff5ae5f0d01b46364fd17c9d03bc4094`). Binary captures remain local evidence rather than ordinary source history. [Issue225's completion record](https://github.com/brettbergin/flight-simulator/issues/225#issuecomment-6117755416) and the PR description retain the public qualification summary.

Parent airfield, aircraft, hardware/pilot and phase gates remain open. No automatic taxi, clearance, arrival scoring, aircraft relocation, physics resume or physics-budget change is introduced.
