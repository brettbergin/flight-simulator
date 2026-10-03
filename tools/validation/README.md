# Independent reference validation

The version 1 corpus checks the project's original synthetic model. It does not establish C172S performance, simulator qualification, or training credit.

Run the portable algebra and definition checks from the repository root:

    python tools/validation/derive.py
    node --test tests/reference/reference.test.mjs
    node tools/validation/runner.mjs --output .local/validation/algebra-report.json

After generating an accepted #14 harness run, compare its sampled diagnostics and exercise artifact corruption:

    node tools/validation/runner.mjs --run-dir .local/fdm-proof/hz120 --output .local/validation/observed-report.json
    node tests/reference/observed.mjs .local/fdm-proof/hz120

These commands require the accepted schema dependencies installed by npm ci --ignore-scripts --prefix schemas. A missing requested artifact is an error, not a successful skip. The CLI returns nonzero for failed comparisons or invalid input. Unsupported entries remain visible and do not count as passes.

## Reference structure and source boundary

tests/reference/matrix-v1.json is a versioned, strictly validated matrix. Every row carries a configuration, primary source revision/section, conditions, quantity, unit, airspeed domain, distance endpoint, uncertainty, method, status and threshold status. Unknown keys, unresolved/duplicate source IDs, absent maneuver coverage, incompatible schema revisions and altered reviewed budgets are rejected. Updating a reference or tolerance requires a reviewed revision and regenerated report; the runner never fits coefficients or edits the corpus.

original-polynomial-v1.json retains 24 decimal cases frozen independently before backend comparisons, using Decimal arithmetic at 50 digits. The original research packet is retained byte-for-byte with its digest; derive.py recomputes all 408 quantities and rejects changes without rewriting any expectations. The separate SI evaluator implements those published original coefficients without calling JSBSim, parsing its XML or deriving expected values from a trace. Positive/negative alpha, beta, controls and angular rates, speed/density scaling, pitch/trim cancellation and denominator-floor cases exercise distinct terms. Zero-density and near-zero-speed algebra cases are mathematical fixtures, not admitted live-flight envelopes.

The live comparison checks positive drag/side/lift in wind axes and moments about the zero CG in forward/right/down body axes. Each diagnostic uses its own same-tick density, true airspeed, alpha, beta, air-relative rates and raw JSBSim controls. The wind-to-body force rotation is checked independently, including signed cardinal-axis fixtures. Dynamic pressure is checked independently. Telemetry is checked against the accepted scenario/command/output contracts, model pin and artifact digests before comparison. A changed lift value with a freshly updated telemetry digest still fails the independent equations.

The provisional live numerical budget is 1e-6 N or Nm plus 1e-7 times the sum of unsigned coefficient terms, multiplied by dynamic pressure, area and the relevant lever arm. This bounds cancellation without a relative-error singularity at zero. Body-force rotation uses the sum of the three unsigned force term bounds, since each direction-cosine magnitude is at most one. This is a propagated component bound, not a separately fitted tolerance. The budget was selected from source conversion precision before observing results: the pinned JSBSim meter-to-foot factor is 3.2808399, with the area factor its square, whereas the independent evaluator uses exact SI geometry. The frozen decimal algebra budget is 1e-9 absolute plus 1e-12 relative. Neither budget is an aircraft accuracy target.

The package is admitted only at the original zero datum/CG and without contacts. The sampled equation comparison does not independently validate propulsion, gravity, trim quality, integrated trajectory, stall, contact, propeller, atmosphere evolution or instrument indications. #14 supplies its own solver/repeatability evidence; a repeated backend trace cannot replace an independent performance reference.

## Pending aircraft references

All nine C172S rows remain unsupported under #28. Their aircraft version, serial applicability, POH revision, engine/propeller/panel, mass, CG, pressure altitude, temperature, wind, surface, slope, power, mixture, flap/gear, technique and obstacle endpoints are explicitly unknown. Handbook sources define concepts; they supply no aircraft performance targets here. The row labels are planned measurement categories, not an assertion about which airspeed unit/domain an eventual applicable POH uses.

IAS, CAS and TAS must remain distinct. IAS is the indicated reading; CAS corrects instrument and position errors; TAS is the actual speed through the airmass. A future calibration reference must identify its applicable conditions and errors rather than relabeling TAS as IAS or CAS. See [FAA Pilot's Handbook, Chapter 8](https://www.faa.gov/sites/faa.gov/files/10_phak_ch8.pdf).

Takeoff and landing each have separate ground-roll and over-obstacle rows. An over-obstacle distance must name the obstacle height, measurement origin and end, surface/slope, configuration and technique. A ground-roll result cannot satisfy an obstacle-distance target. No default obstacle height is assumed for an uncleared aircraft reference. See [FAA Pilot's Handbook, Chapter 11](https://www.faa.gov/sites/faa.gov/files/13_phak_ch11.pdf).

The matrix cites immutable project model source and pinned JSBSim conversion code; the FAA sources are reference-only links. No restricted aircraft chart/table or third-party dataset is copied or packaged. Project-authored JSON and evaluator code use the existing project MIT license. The accepted rights register continues to govern the model and any redistributed dependency.

## Reports and review

Reports retain matrix/corpus hashes, model inventory, individual outcomes and fixed qualification/fitting flags. With a run supplied they also retain scenario, command, telemetry and provenance hashes, the actual loaded JSBSim identity, executable/compiler/source identity and scripted input profile. Reports contain no personal controller calibration or machine path.

The initial report in docs/evidence/P1/validation-corpus.json captures the accepted #14 Windows run. A new platform/build generates its own report rather than replacing provenance. A reviewer must assess both the provenance and the claimed comparison scope before accepting future aircraft references.
