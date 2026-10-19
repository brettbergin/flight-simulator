# KAWO NASR source ingestion

Source implementation prepared for [#247](https://github.com/brettbergin/flight-simulator/issues/247)
after checked [#245](https://github.com/brettbergin/flight-simulator/pull/245), under
the accepted [airport-source contract](../../contracts/world/airport-source-v1.md).
Root integrated and reviewed the implementation, then ran all 18 focused tests
with the actual pinned archive and explicit dossier: zero failures and zero skips.
The actual-source comparison consumes pre-ingester independent expectations; the
remaining cases are original synthetic parser/mapping defects. Two separate CLI
runs produced identical bytes for all four output files, and the accepted external
pair validator accepted both. An existing-directory CLI attempt refused with code2
and preserved the original output. Final-head hosted CI is recorded by the PR;
these local results do not assert that pending CI has passed.

The [offline ingester](../../../tools/ingest/airports/kawo_nasr_v1.py) reads only
the pinned local FAA 2026-10-01 ZIP and explicit dossier, produces draft normalized
metadata and preserves original dossier bytes. It fixes the raw archive hash,
selected member byte/column/national-row counts and AWO/KAWO/site26099./WA/typeA/US
joins. Expected subset counts are one airport, two paved runways and four physical
ends. No runtime world or playable scenery changes are included.

Independent source facts were transcribed before the ingester existed and are
retained in the [small fixture](../../../tests/airports/kawo/fixtures/expected-source-facts.json)
with SHA256 `333bc105f8117cb01218cfab60d9153cbaa7c52b8632a0a87afaf253cbf498b4`.
The [focused test source](../../../tests/airports/kawo/test_kawo_nasr_v1.py) separates
synthetic malformed parsing/join/numeric cases from the explicitly supplied actual
archive comparison. Default skipped actual tests do not establish real-source
acceptance. Raw ZIP/PDF and national CSV/contact fields stay outside Git.

The [sanitized execution receipt](kawo-source-ingestion-run-v1.json) records exact
interpreter/tool/test/input/output digests, counts and the real pair-validator
result. The [caller dossier](kawo-source-input-dossier-v1.json) retains captured
source and pending rights honestly; retrieval fractional seconds are documented
beside the schema's whole-second value. Actual normalized output is 37,101 bytes,
SHA256 `dcbdeebae109837cb5a8edada7d77c39bdbedaf373bc27e574c62eec4190b9cd`.
The dossier is 1,285 bytes, SHA256
`51c34553737535ca80da3ec611f035e65abf00e0e67f10bcb2e2af6b70c71c20`.
No output is promoted to a content/world pack. Raw products and full run logs stay
outside Git. To reproduce, supply the exact external archive and committed input
dossier, use a new output directory, and run the two explicit README commands.

Independent source review found no production blocker and identified a supported
branch absent from this actual source: nonblank declared distances. A separate
synthetic test now supplies four distinct TORA/TODA/ASDA/LDA values, nonblank
threshold coordinates and displacement, and known zero displacement, with literal
SI expectations and field-locator assertions. This expands meaningful coverage
without altering independent actual-source facts or relaxing the real archive pin.

The 46 accepted source-contract tests and documentation/plan checks passed locally.
Foundation CI runs synthetic parser/mapping tests on Windows and Linux; its default
actual-archive skip is explicit and cannot replace this separately supplied actual
run. The unchanged source schemas/validator retain their accepted identities.

The output preserves generic NAD83 with unknown realization/epoch, source feet-MSL
as `msl-unspecified`, exact Decimal feet conversions, source method/dates and true
bearings distinct from published designators. Blank displaced-threshold, declared
distance and gradient information remains unknown, never a zero/full-runway/flat
default. Dossier retrieval and rights remain caller-declared actual evidence;
the ingester never grants rights or marks output cross-checked.

Turf/glider facilities, taxi/hold/sign/lighting/frequency details, source conflicts,
operational review, datum conversion, terrain/renderer/contact agreement, world/
start/history binding, offline delivery, WORLD016 accuracy and pilot acceptance
remain separate. #243/#38/#41 and P3/P4 remain open. Existing synthetic flights
and their source identities are unaffected.

## Checked source-leaf integration

The reviewed source ingester, focused tests and actual-source evidence joined
cohesive foundation PR246 and checked-merged asd58af4ff077bf498d6a6043bd6b3ea6e6f3bb89f.
Root verified the accepted tree and the final protected Windows/Linux checks.
PR248 was superseded rather than independently merged. This accepts only the
bounded source-ingestion leaf247; draft/pending source metadata, geographic
accuracy, complete airport/world/runtime and broader phase gates remain distinct.
