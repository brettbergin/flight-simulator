# P1 external-ground contact evidence

GROUND-PROOF #16 consumes provider API v1 from merged PR88 and `GroundSample/v1`/`AircraftSnapshot/v1`. This records an actual JSBSim 1.3.1 engineering experiment separately from the flight-only model and save/export proofs. It is not target-C172S handling, aircraft gear qualification, an airport package or a playable cockpit.

The [original MIT fixture inventory](../../../tests/ground/fixtures/inventory.json) pins the ground-cart XML to SHA256 `c546dc4791fc830e6f656b13c7a564322d51fba8f46b43da10af3d2f7ff041a1`, 2275 canonical LF bytes. The [independent original analytical packet](../../../tests/ground/fixtures/analytical-reference.json), SHA256 `80d519138f8fc78432d63908f2b7523949ed3c57cb72a684e772fe6043763130`, was frozen before external contact traces were observed. It includes WGS84 geometry, ECEF plane/ray intersections, flat support fractions and spring/damper examples; it is not manufacturer data. Values were not fitted to make a real-aircraft comparison pass.

## Actual trials and independent checks

Windows local MSVC 19.40.33813.0 passed 182080 native assertions and Node 3/3 verification tests; integrated CTest passed 6/6. Repeated per-tick assertions are not 182080 distinct scenarios. Thirty eight-second trials exercise stationary, coasting, steering, braking and touchdown on flat and 3% north/2% east planes at 60/120/240 Hz. There are 510 aligned full 2 Hz snapshots. Additional actual-engine cases cover all four preflight misses, callback miss/exception/wrong world, throwing boundary identity, incomplete initial coverage before allocation, invalid controls, unloaded/loaded seams, low-friction braking and byte-identical repeated touchdown.

CG remained above the plane, states remained finite, final contacts were stable and full-brake cases settled. Flat touchdown peak compression was .144683/.134792/.129206 m at 60/120/240 Hz, with corresponding CG minima .855809/.866384/.872017 m above the plane. Slope peak compression was .144011/.134670/.129073 m. These measurements do not define safe aircraft landing rates or damage limits. Actual transient acceleration reached approximately 141.4 m/s². The initial 100 m/s² finite guard failed; its explicit 400 m/s² research revision and limits are recorded in the [adapter README](../../../native/fdm_jsbsim/ground/README.md).

Independent Node equations verify every published compressed acting contact point against the ECEF plane within .0001 m using actual CG position, body→NED quaternion and local NED/ECEF basis. Normal forces agree with the independent linear spring/damper equation and leg/normal projection within .02 N plus 1e-5 relative. This additional force allowance was selected before the first force-equation comparison, after native trial traces existed; it is a conservative engineering tolerance for SI conversion, frame projection and roundoff, not an analytically proved bound or part of the original frozen packet. The packet's separate 3e-7 relative spring/damper XML conversion budget remains unchanged. The first force comparison passed without tolerance fitting. Full `AircraftSnapshot/v1` schema/semantic validation covers every sample again. Wrong surface digest, missing contact, altered force, wrong tick and incompatible schema are rejected.

At flat stationary equilibrium the independent example `W=1100×9.81=10791 N`, support 3597 N per wheel and compression .02398 m gives clearance .97602 m. Tests allow .004 m clearance and 110 N per-contact differences and require final speed/rate <.005 in SI. The allowance includes pinned rotating/J2 gravity, conversion and numerical settling. 9.81 m/s² is the authored example, not the backend's exact effective gravity; equal thirds are not a universal sloped-equilibrium target.

## Numerical comparison

Thresholds were authored before these external-provider traces ran. Steering/brake onset is physical .5 s (`tick>Hz/2`). Each lower-rate trace compares 17 aligned 2 Hz samples against 240 Hz. Sampled maxima are not continuous-time error bounds.

| Quantity | Threshold for 60/120vs240 | Largest observed 60vs240 | Largest observed 120vs240 |
|---|---:|---:|---:|
| ECEF position distance | .15 m | .0868374 m | .0281260 m |
| Body velocity distance | .15 m/s | .0472504 m/s | .0153236 m/s |
| Quaternion rotation distance | .02 rad | .00296581 rad | .000959649 rad |
| Body rate distance | .05 rad/s | .00173100 rad/s | .00125595 rad/s |

The [compact local receipt](../../../tests/ground/proof/windows-proof.json) preserves all 20 comparisons, binary/library/contract/inventory identities and build metadata. CI retains each Windows/Linux build's own raw receipt without cross-platform bit-identity claims. One same-build touchdown repeat compares every canonical sampled snapshot byte-for-byte. This does not inherit smooth-flight tolerances or promise arbitrary contact robustness.

## Contact authority and coverage

One JSBSim executive owns contacts and aircraft integration. The callback supplies geodetic vertical AGL in feet, ellipsoid contact location, ECEF normal and zero stationary-surface velocity. Friction reaches all actual gear properties; lower static friction lengthens measured stopping distance. No Godot contact solver or runway correction exists in this proof.

Known misses block before input/tick/solver mutation. Unloaded seams stop before the bounded gear footprint reaches the unavailable tile; repeated blocks preserve state and unapplied controls. Congruent loaded seams are byte-identical to a uniform-plane control, with height continuity checked within north 9..11 m around the seam at 10 m, separately from initial settling. Unexpected callback faults dispose the executive, retain only the previous owned publication and reject retries. Actual JSBSim Unbind invokes getters during destruction, requiring a disposal-only callback guard; no detached getter values enter integration/publication. See the [ownership and guard details](../../../native/fdm_jsbsim/ground/README.md).

## Acceptance scope and next consumers

REAL-010/PRD-006: one contact authority and bounded original stationary/coast/steer/brake/touchdown proof. WORLD-010/011/016: explicit ellipsoid datum, local normal, immutable identity, loaded/missing coverage and congruent-plane continuity. Evidence is partial within P1's synthetic scope; real aircraft/airfield/world-streaming behavior belongs to later phases.

#20 needs a separately reviewed unified flight/ground intake and gear/world state contract before this seam becomes a runtime feature. #22/#31 consume geometry/contact evidence without treating arbitrary parameters as C172S values. #39/#40 still own real datum conversion, coverage and streaming. #17 proves the original flight model only; ground replay/resume is unproved. No phase completion, aircraft fidelity, human pilot review or training-credit acceptance follows from these checks.
