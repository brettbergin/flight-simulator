# Initial independent validation corpus

Issue: [#19 VALIDATION-CORPUS](https://github.com/brettbergin/flight-simulator/issues/19). Requirements: REAL-023, REAL-024, REAL-025, PRD-003, PRD-026. Prepared 2026-10-03; independent integration review remains with the root reviewer.

The version 1 matrix and runner establish independent numerical checks for the project's original synthetic model, and explicit missing-reference coverage for trim, cruise, climb, takeoff, landing and IAS/CAS stall categories. This evidence does not complete P1, qualify an aircraft, validate C172S behavior or confer training credit.

The initial [machine-readable report](validation-corpus.json) contains 24 passing frozen Decimal identities, one passing comparison of 21 actual sampled diagnostic states, and nine unsupported C172S rows. The accepted run is #14's 120 Hz scripted Windows run from the independently reviewed head 840a2612aeaea88f859397c56ecfb3ce8b85c0ac, merged as 33b66a96e2aae1bfac881077597209198fa4af81. Artifact hashes and actual loaded-library/compiler identity are in the report. Samples cover one scripted trajectory; passing these equations does not demonstrate flight-envelope accuracy.

The analytical cases were frozen before observing the backend trace. The retained original research packet digest is 74f500b759f741ba5a9db47776e7352975ee06de1fe62fa632bd3d4a385cf31d. Its independently computed expected decimal values are retained in the corpus. Reviewed source-conversion rounding determines the live comparison budget; no coefficient or tolerance fitting occurs.

Meaningful checks cover changed decimal expectations, nonfinite/duplicate/incompatible references, guessed aircraft metadata, IAS/CAS relabeling, ground-roll/obstacle relabeling, missing phases and invalid tolerance changes. The integration check rejects an altered artifact with a stale digest, then still detects an incorrect lift after the digest is updated; wrong model provenance also rejects. Missing requested backend data fails rather than skipping.

Reproduce using [the validation commands](../../../tools/validation/README.md). Algebra-only runs report 24 passed and 10 unsupported because the backend comparison was not requested. Artifact-backed runs report 25 passed and nine unsupported. Invalid inputs and failed comparisons return nonzero; unsupported rows are not counted as passes.

C172S quantitative references await #28's exact configuration, source applicability, redistribution decision and declared uncertainty. Ground/obstacle distance also needs implemented ground/propeller behavior and applicable source techniques; IAS/CAS need validated instrument/calibration behavior. No restricted tables or reference aircraft model are included. Further independent trajectory, trim, propulsion and aircraft performance validation remains work for subsequent gates.
