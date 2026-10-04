# Native CI scope rollout evidence

Issue [#124](https://github.com/brettbergin/flight-simulator/issues/124) tracks adoption and two actual hosted scope cases. [Source-scope policy](../../../tools/ci/README.md) preserves protected check names and defaults to full runtime proof. This report establishes CI behavior, not simulator or aircraft qualification.

## Full initial adoption

[PR126](https://github.com/brettbergin/flight-simulator/pull/126) source `9f5fafe1269574c6dd755979bc2a837a050aa495` merged as `eff896332665e5789efdef50a32001684a0fe379`. Its accepted base lacked the new classifier, so adoption ran full proof on both platforms rather than allowing the changed workflow to exempt itself.

[Native run37192909379](https://github.com/brettbergin/flight-simulator/actions/runs/37192909379) and [Foundation run37192909357](https://github.com/brettbergin/flight-simulator/actions/runs/37192909357) completed successfully. All four protected checks passed. Root independently checked exact reviewed source blobs and actual success of compilation, pinned Godot loading, terrain contact, ground-to-flight loop, typed bridge and facade/scene checks on both platforms. Windows additionally passed corresponding-source/DLL replacement, editor/portable preview and ground-to-flight replaceable-package steps. The reviewed head and CLEAN/current-base checks guarded the squash merge.

Independent source, workflow, classifier-guard and mapping review preceded merge. Six adversarial real-Git suites passed locally. The unchanged prior native proof bodies and pinned actions remain available in full scope. Source-scope success alone never replaces a runtime, content-rights, pilot or phase gate.

## Documentation-only probe

This documentation-only report is the real probe. Its hosted outcome is pending. Acceptance requires both named native jobs to succeed with documentation scope receipts, runtime_proof_executed=false and explicitly skipped native-dependent proof steps, while Foundation/static/contract/integrity/classifier guards run. The classifier must come from the accepted immutable base and validate both source and actual tested merge diffs. No simulator behavior claim follows from these jobs.

## Productive code probe

The original piston model/reference source PR is a productive non-prose change. Its outcome is pending. Acceptance requires the accepted classifier to choose full scope on Linux and Windows, run the actual native-dependent proofs and preserve corresponding receipts. An absent/unknown scope does not grant an exemption.

Keep #124 open until all three hosted cases have actual evidence. Later scope changes need exact source review and adversarial guards; unknown or mixed inputs continue to run full.
