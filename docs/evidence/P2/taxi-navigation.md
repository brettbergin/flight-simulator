# Original apron starts and synthetic taxi navigation

Status: implementation in progress for [issue225](https://github.com/brettbergin/flight-simulator/issues/225), following the checked [ADR027 contract](../../decisions/027-synthetic-taxi-navigation.md). The contract merged in [PR226](https://github.com/brettbergin/flight-simulator/pull/226). Development results below do not establish final delivery, aircraft fidelity, pilot evaluation or a phase exit.

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

## Remaining delivery and acceptance

Before this issue can close, actual pilot-control journeys must demonstrate cold startup and ready-apron taxi to both stop references, deliberate runway entry, takeoff/landing, traversal of all three return links and parking. Manual route advancement alone is insufficient evidence. Actual current14 native tests and preserved physical/reference suites, original21 plus14 apron camera rows, original minimum-size and larger visual observations, editor/portable/rebuilt-library checks, complete corresponding source/rights and current-head hosted CI remain required.

All signs, pavement, aircraft and route references are explicitly original synthetic practice content. This work introduces no real airport, surveyed geometry, C172 qualification, ATC clearance, training credit, automatic taxi, physics resume or pilot/hardware acceptance. Durable local players remain separate [issue219](https://github.com/brettbergin/flight-simulator/issues/219) and [issue220](https://github.com/brettbergin/flight-simulator/issues/220) work.
