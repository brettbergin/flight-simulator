# External-ground JSBSim contact proof

[GROUND-PROOF #16](https://github.com/brettbergin/flight-simulator/issues/16) consumes the accepted [stationary provider v1](../../world_core/ground/README.md). This is an internal caller-thread numerical experiment, not a supported flight Session or a calibrated aircraft. The existing original-synthetic flight model, intake, configuration and public Session remain unchanged.

`flight_ground_jsbsim_proof` owns one dynamically linked JSBSim 1.3.1 executive. It loads only the exact byte-pinned [original MIT ground-cart XML](../../../tests/ground/fixtures/inventory.json): 1100 kg fixed CG, arbitrary inertia, three spring/damper bogeys, no aerodynamic forces or engine. The nose wheel can steer 30 degrees; main wheels have independent brakes. These values do not describe a Cessna's tires, struts, loading or touchdown capability.

Run the pinned [bootstrap](../../../tools/bootstrap/README.md), which builds and runs CTest `ground_contact_proof`, then:

~~~powershell
node --test tests/ground/proof/verify.test.mjs
~~~

The verifier executes the actual native binary and retains 510 full SI `AircraftSnapshot/v1` samples, separate compression/rate diagnostics, actual code-address-resolved shared-library path/hash, executable hash, compiler, contract/inventory hashes and comparisons under ignored `.local/ground-proof/`. CI runs the same proof on Windows and Linux. Raw receipts contain local paths and stay in engineering evidence; compact checked receipts omit those paths. See [P1 ground evidence](../../../docs/evidence/P1/ground-proof.md).

## Geometry and ownership

The [analytic prepared surface](../../world_core/ground/proof/analytic_surface.hpp) is a stationary, bounded ECEF plane anchored at WGS84 latitude .8 rad, longitude -2 rad and ellipsoid height 1000 m. Presets are flat or ascend 3% north/2% east. Orthometric/MSL heights, geoid conversion, real airports, moving decks, walls and overhangs are outside this proof. Two congruent tile regions share a plane/material; unloaded second-tile coverage is explicit.

A query intersects its geodetic vertical ray with the ECEF plane and returns ellipsoid height plus upward normal in the NED basis at that exact query. The callback converts height meters to feet and passes geodetic vertical AGL in feet, contact point and unit normal in ECEF, and zero Earth-relative surface linear/angular velocity. AGL is not perpendicular slope distance: pinned `FGLGear` applies its own normal/leg projection when computing compression and normal force.

Each boundary captures exact content/surface identity and generation. The prepared digest hashes `ground-plane-v1` followed by NUL, then 12 binary64 little-endian values (anchor latitude/longitude/height, north/east grades, north min/max, east min/max, seam north, static/dynamic friction), then one loaded-tile byte. World and surface digests use these exact prepared bytes, generation 1. Scene objects and struct padding do not supply identity.

Initialization preflights CG, the three authored gear positions and footprint before allocating an executive or setting ICs. Before each steering/brake step, the adapter preflights current CG and all uncompressed backend gear positions and checks the conservative horizontal footprint against the immutable plane's convex loaded coverage. Effective static/dynamic friction reaches each actual gear property; rolling coefficient .01 remains the authored tire model's property. Publication uses solved wheel forces and compressed acting locations relative to current CG in body FRD meters. Fixed authored-datum CG is a separate field. JSBSim alone integrates motion and contacts; neither Godot nor the provider adds ownship collision impulses.

## Missing data and disposal

All four explicit misses return `coverage_blocked` before control/solver/clock mutation, retaining the last publication and prior held controls. Supplied controls were not applied. The proof has no provider replacement or automatic recovery API. Actual unloaded-tile trials stop before the swept gear footprint reaches the seam. Loaded congruent-tile trials cross byte-identically to a uniform-plane control, without position correction or a default sphere.

Preflight identity exceptions/invalid responses and unexpected callback miss/exception/identity mismatch terminate the executive. A partially mutated Run never publishes; subsequent calls return `discarded` and cannot resume. This is disposal, not checkpoint rollback. The deleter sets a terminal teardown flag before deleting the executive. Pinned JSBSim `Unbind` invokes AGL getters during destruction; the callback then performs no provider queries and supplies detached zero getter values solely for property unbinding. No Run, force computation or new publication consumes them. Tests cover safe destruction after known misses and terminal destruction after callback faults/poisoned boundaries.

The footprint allowance is `2.5 m + (20 m/s + 2 rad/s × 2.5 m)dt + .5 × 400 m/s² × dt² + .02 m`. A 2.5 m radius encloses the authored gear. Output must remain finite with speed ≤20 m/s, rate ≤2 rad/s, acceleration ≤400 m/s², final center covered by the gear radius and horizontal displacement within the allowance. This is a tested research domain and post-step rejection rule, not a proved continuous acceleration bound or arbitrary-terrain guarantee. Unexpected sampling beyond prepared coverage still discards before publication.

The recovered initial 100 m/s² guard rejected actual 60 Hz touchdown. It was explicitly revised to 400 m/s² after that failure; observed impact acceleration reaches approximately 141.4 m/s². This broadens a finite-result guard without loosening convergence, geometry, spring equation or static-load tolerances. A universal physical bound is not claimed.

## Handoff

#20 must first ratify a unified low-speed flight/ground intake and supported gear/control/world/lifetime contract. Promoting this internal `GroundExecutive` directly into a cockpit would bypass that prerequisite. Initial clearance is 1..3 m, speed ≤10 m/s and body-down speed ≤3 m/s; steps run at fixed 60/120/240 Hz. No aerodynamic takeoff, unified flight-to-landing integration, worker scheduler, damage, tire calibration or runtime streamed terrain is provided here.

#22 can consume verified stationary geometry/query conventions. #31 owns aircraft steering/strut/brake parameters; #39/#40 own source datum and streaming continuity. #17's reconstruction proof is flight-only: exact ground reconstruction and full session resume are unproved. Register/stage this distinct MIT inventory before including it in future distributed ground packages; #15's flight-only export does not include it. Original source and fixtures use the repository [MIT license](../../../LICENSE); no upstream aircraft XML or operational airport data is reused.
