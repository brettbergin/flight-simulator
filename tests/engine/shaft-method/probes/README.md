# Coupled shaft qualification

This suite checks the accepted original-profile shaft contract. It does not certify an aircraft, flight-training credit, or a phase exit. The immutable independent packet and its provenance live in [the reference package](../coupled-midpoint-v1/README.md). Existing thirteen legacy rows, numerical comparisons, and the complete twelve-process physical suite retain their original limits.

Select `event-aware-coupled-midpoint-v1` through the pinned [bootstrap](../../../../tools/bootstrap/README.md). Pristine and held-power builds do not register substitute coupled tests. The modified route requires separate compile-only and test-only invocations. Pass explicit `-ProbeExecutionRatification <absolute future unit record>` during both stages; compilation never creates that record. `-HeadlessNative` disables Godot bindings for the modified route and must match between both stages. It retains all native CTests.

The build extracts the production scalar code verbatim into its own `tests/engine/shaft-method/probes/generated` directory. Only source reading, hashing and static chronology checks occur during extraction. A changed extraction input requires a fresh build directory so previous evidence survives. Actual library fixtures use the configured verified source and replaceable JSBSim library; the extracted strict helper alone does not establish vendor compile settings.

After strict compilation and review, authorize unit execution explicitly:

```text
python -B tests/engine/shaft-method/probes/run.py authorize --config <build>/coupled-probes-config.json --ratification <unit-record.json> --approve-execution
```

The action verifies the staged route/result, pretrial identity, actual verbose strict compiler invocations for both numerical translation units, source/build manifests, model pins and all four executable/library identities. It rehashes every contained source input from the accepted `coupled-ci-pretrial-v1` record, requires its critical public proof/consumer closure, and creates a new `coupled-probe-execution-v1` record; it never runs a native process. This record is separate from the unchanged eleven-field physical execution record. The caller must independently authorize that physical record as before.

`build.ps1 -RunTestsOnly` discovers both `coupled_shaft_math` and `coupled_shaft_native` plus `piston_engine_lifecycle`, then runs the complete CTest set. CTest fixtures order offline math before four native unit children before the physical suite. A failed prerequisite visibly blocks dependent tests and fails the run. No missing record, unsupported backend, missing test, malformed output or generic rejection is a passing substitute.

The runner can also be invoked explicitly with the same approved record:

```text
python -B tests/engine/shaft-method/probes/run.py execute --config <build>/coupled-probes-config.json --ratification <unit-record.json> --output-root <build>/coupled-unit-proof
python -B tests/engine/shaft-method/probes/run.py math
```

Each execution creates `run-<uuid>` with canonical requests, child stdout/stderr, `execution-receipt.json` and, on successful comparison, `validation-result.json`. The four fixed children are kernel, actual-library/default/legacy, actual chronology, and representative terminal-retention failure. The last three must report the same actual loaded library as the configured qualified path. Executable/library/source/model bytes are checked before and after execution. The terminal fixture restores exact FE/MXCSR controls and confirms the last completed state survives an actual unsupported-rounding failure.

Offline validation preserves exact floor bits and rejection reasons, exact point event/stop remainders and complete independent absolute coefficient intervals. Nominal RN-DAG bits are diagnostic. Held-ME scalar checks do not establish actual table evaluation. Static M05 call counts are source proof, not instrumented runtime counters. Abstract scalar fixtures and deliberately seeded isolated chronology inputs are not cold-flight scenarios.

`math` runs the24 independent reference tests,11 unchanged validator corruption tests and15 portable identity tests without loading the library. Full deterministic reference regeneration is a separate CI action; it never rewrites the committed packet during configure, build or CTest. Portable integration requires its own fresh compiler and output evidence; preserved private Windows trials are provenance, not substitute public-build results.
