# Native CI scope rollout evidence

Issue [#124](https://github.com/brettbergin/flight-simulator/issues/124) tracks adoption and two actual hosted scope cases. [Source-scope policy](../../../tools/ci/README.md) preserves protected check names and defaults to full runtime proof. This report establishes CI behavior, not simulator or aircraft qualification.

## Full initial adoption

[PR126](https://github.com/brettbergin/flight-simulator/pull/126) source `9f5fafe1269574c6dd755979bc2a837a050aa495` merged as `eff896332665e5789efdef50a32001684a0fe379`. Its accepted base lacked the new classifier, so adoption ran full proof on both platforms rather than allowing the changed workflow to exempt itself.

[Native run37192909379](https://github.com/brettbergin/flight-simulator/actions/runs/37192909379) and [Foundation run37192909357](https://github.com/brettbergin/flight-simulator/actions/runs/37192909357) completed successfully. All four protected checks passed. Root independently checked exact reviewed source blobs and actual success of compilation, pinned Godot loading, terrain contact, ground-to-flight loop, typed bridge and facade/scene checks on both platforms. Windows additionally passed corresponding-source/DLL replacement, editor/portable preview and ground-to-flight replaceable-package steps. The reviewed head and CLEAN/current-base checks guarded the squash merge.

Independent source, workflow, classifier-guard and mapping review preceded merge. Six adversarial real-Git suites passed locally. The unchanged prior native proof bodies and pinned actions remain available in full scope. Source-scope success alone never replaces a runtime, content-rights, pilot or phase gate.

## Documentation-only probe

[PR129](https://github.com/brettbergin/flight-simulator/pull/129) first tested this report at source `8a00f2236c772639240f7a535f7a68f8453a5dba`. [Native run37194321443](https://github.com/brettbergin/flight-simulator/actions/runs/37194321443) succeeded on Linux and Windows. Both scope receipts identify accepted base `eff896332665e5789efdef50a32001684a0fe379` and tested merge `51e672fadc3fa661abae58370525df3c292764c1`, with only this added regular Markdown file in both source and tested-merge diffs. Both declare `docs_only=true`, reason `only-added-or-modified-regular-documentation`, and `runtime_proof_executed=false`.

The actual job records show classifier guards, documentation/backlog checks, accepted schemas, frozen reading references and dependency integrity succeeding on both platforms. The documentation-only reporting step succeeded; every native-dependent compilation, solver, Godot, bridge and package step was explicitly skipped. Linux artifact `11300415857` and Windows artifact `11299893772` each preserve `native-ci-scope/receipt.json`; their identical receipt SHA-256 is `ea3b2be76ca4546b19f360d01f927a87ed3a74a3b30fe1635264c9b2af1ae489`.

This report was then refreshed on accepted model-source main `ad24168c4266f1e3fc2b59f997781628ea40a50d`. Its final current-head checks remain a merge prerequisite; the first probe results above refer to their recorded source, not an untested later revision.

## Productive code probe

[PR128](https://github.com/brettbergin/flight-simulator/pull/128) tested original piston model/reference source `f5ec1734007f9f508b5e84e2738dd269bf7c3b07`. [Native run37194094832](https://github.com/brettbergin/flight-simulator/actions/runs/37194094832) completed successfully on both platforms. The documentation-only reporting step was skipped. Actual compilation and unchanged source/tool receipt checks, synthetic dynamics, pinned Godot loading, asset/geodesy proof, original equation corpus, integrated ground contacts, one-executive ground-to-flight loop, typed bridge and facade/scene steps all succeeded. Windows additionally passed input-editor preflight, corresponding-source/DLL replacement and both portable preview/package proof steps.

These full job results establish that the accepted classifier admitted a productive source change to runtime proof. The new piston model/reference was also checked as source and independent equations. The existing runtime proofs use their accepted historical fixtures; they do not establish new piston startup, integrated shaft behavior, convergence, C172 fidelity or pilot acceptance. An absent or unknown scope continues to grant no exemption.

All three hosted rollout cases now have recorded evidence. Keep #124 open until the refreshed PR129 has passed all four current-head protected checks and its reviewed documentation has merged. Later scope changes require exact source review and adversarial guards; unknown or mixed inputs continue to run full.
