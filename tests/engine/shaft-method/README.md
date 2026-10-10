# Proposed independent event-aware shaft references

This is the source-only numerical packet for [ADR014](../../../docs/decisions/014-event-aware-shaft.md) and existing [issue127](https://github.com/brettbergin/flight-simulator/issues/127). Publishing it does not execute a method, patch the dependency, validate coupled startup or close the issue.

The six files in `reference-proposed-v1/` preserve the original preparation bytes and metadata. Its manifest still says `PROPOSED-private-preconsumer-not-ratified`: that records its preparation state, not a current private-only distribution restriction. Referenced private proposal/source-review hashes preserve chronology; the public ADR describes the source, equations, clarifications and required future review. The original README's adjacent source-review note refers to that retained preparation review.

The generator imports only Python standard-library Fraction/Decimal arithmetic. It covers 45 branch cases, nine constant-held-power partitions and 18 rejection recipes. Four signed-zero/no-op recipes are a separate supplement. Decimal 150/220 precision agrees on nearest binary64 values. None comes from a backend or implementation observation.

Run from the repository root:

```powershell
python tests/engine/shaft-method/reference-proposed-v1/generate.py --check
```

`--check` is read-only. `--create` uses exclusive creation and refuses to overwrite expected bytes. The manifest fixes sizes/hashes of the five adjacent inputs; preserve its preparation bindings. Expected SHA256 is `b3b90b35bc9f3bd91e26020e608b32a0c1aa9672467d1dff0efaa5d226d99a85`, generator SHA256 `771a0b926a486facfcca2968121779652a2db24cd16b3a7b1ccf8c569fae0a57`.

Before any new helper/backend output, independent review must inspect actual stable operations, event predicates, capacity/exponent guards, compiler assumptions and quotient/root reduction. Root then records a distinct ratification receipt binding the accepted contract, exact reviewed patch/materializer, this packet and predeclared comparison/physical criteria. The 64u case criterion is sampled engineering evidence, not a universal error theorem. Partition recipes also require an independently prederived composed-step comparison criterion. The original 55-case engine packet, model parameters and physical convergence budgets remain unchanged.
