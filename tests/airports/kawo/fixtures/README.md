# Independent KAWO source expectations

`expected-source-facts.json` is the unchanged pre-ingester hand transcription of
selected raw FAA NASR fields and same-archive documentation. Its SHA256 is
`333bc105f8117cb01218cfab60d9153cbaa7c52b8632a0a87afaf253cbf498b4`.
The separate source owner retained this fixture before the importer was authored;
the importer does not generate, rewrite or consume its expected values.

The source is the fixed 2026-10-01 APT archive identified inside the fixture and
the [source discovery record](../../../../docs/evidence/P4/kawo-source-discovery.md).
This small factual subset contains no full CSV/contact rows, chart, PDF or image.
Large original artifacts and retrieval receipts remain private/outside Git.

The fixture is neither an AirportSourceDossier/v1 nor NormalizedAirport/v1. It is
not a world pack or operational reference. Generic NAD83 realization/epoch and
specific feet-MSL vertical realization remain unresolved. Independent source facts
do not prove contemporary airport operations or geographic survey accuracy.

The sibling Python tests construct separate original synthetic rows and malformed
ZIP/CSV cases in memory. Passing them proves only those parser/mapping checks.
Only an explicitly supplied exact-hash actual archive/dossier run can exercise the
real-source comparison, followed by the accepted external byte-pair validator.
