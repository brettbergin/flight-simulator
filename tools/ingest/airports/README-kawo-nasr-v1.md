# Pinned KAWO NASR source ingestion

This offline standard-library Python tool produces a draft AirportSourceDossier/v1
and NormalizedAirport/v1 byte pair for [#247](https://github.com/brettbergin/flight-simulator/issues/247),
under the accepted [source contract](../../../docs/contracts/world/airport-source-v1.md).
It does not build terrain, transform datums, admit a world or change the playable
synthetic airport. [ADR028](../../../docs/decisions/028-kawo-source-and-resident-environment.md)
and [discovery evidence](../../../docs/evidence/P4/kawo-source-discovery.md) explain
the separate geographic/runtime work under #243, #38/#41 and P4.

Use Root's explicitly selected frozen Windows CPython 3.12.14 (the standard library
only); no pip packages, subprocess, network access or automatic acquisition exists.
The fixed FAA 2026-10-01 archive is 8030968 bytes, SHA256
`aba48ea877f249d9b8cd63988b14b3432a6a09ad1fbe9561a5e6443c99c03dd0`.
There is no hash/cycle override or newer-source selection. Raw archives/PDFs stay
outside Git. This tool does not parse charts or copy third-party images.

## Caller-supplied dossier

Supply actual dossier bytes, not a generated retrieval/rights assertion. The dossier
must be KAWO `purpose=source-record`, with exactly one bound `faa-nasr` source at
the pinned archive URL, captured/reviewed with its actual retrieval UTC and artifact
hash/size. Its effective_from is `2026-10-01T00:00:00Z`; effective_until may remain
null or be the next cycle `2026-10-29T00:00:00Z`. Raw ZIP artifact relative_path must
be null: this tool references it externally and does not package it. Captured source
with pending rights is permitted; reviewed source with pending rights is refused.
No rights or timestamps are upgraded. Root supplies captured/pending/draft state
until the separate source review supports more. Optional extra dossier sources and
conflicts remain unchanged; the accepted JS validator checks their full schema and
relationships. Python preflight is deliberately narrower than that final validator.

## Produce and validate

Set `$Python` to the reviewed absolute interpreter, and supply explicit local source
and dossier paths. The output directory must not exist; its parent must exist.

```powershell
& $Python -I -B tools/ingest/airports/kawo_nasr_v1.py --archive $Archive --dossier $Dossier --output $Output
node tools/ingest/airports/validate-kawo-output.mjs --directory $Output
```

The first command writes `dossier.json` (the caller's exact bytes), `airport.json`
(deterministic sorted-key UTF-8/LF plus final LF), `ingest-receipt.json` (source/tool/
output hashes and bounded counts), and `VALIDATION-REQUIRED.txt`. Every airport
output remains `review_state=draft`. The second command invokes the accepted
`validateSourcePair` API on those exact bounded bytes and prints its result/digests.
The Python command never invokes Node. A Python success is not pair validation;
retain both receipts. The marker remains a reminder even after external validation.
On any failure, retain logs/partial newly created output for review; never reuse
an old directory or silently overwrite a previous attempt. The tool does no cleanup.

ZIP member names are closed, never extracted, and bounded to 32 members, 32 MiB
per member and 256 MiB total declared uncompressed data. Production requires the
exact ten-root-member roster. Only APT_BASE.csv, APT_RWY.csv and APT_RWY_END.csv are
decoded, as strict UTF-8 without BOM/NUL. Each field is bounded to 8192 characters;
headers require unique exact consumed column names and the observed total column
counts 90/26/80. Extra known source columns are discarded rather than copied into
outputs. National row counts are pinned to 19427/23191/39829; every row has the
header's column count and total rows are bounded to 100000 per selected table.
The complete archive hash already fixes all headers/member bytes. Duplicate ZIP
names (including case aliases), encryption, unsupported compression, Unix special members,
changed source counts/sizes and target-identity/cycle inconsistencies reject.

KAWO matching requires AWO/KAWO/site26099./WA/typeA/US, one airport, exactly two
ASPH runways 11/29 and 16/34, and four unique joined physical ends. Partial target
identity matches reject rather than disappear from the filtered set. Output order
is fixed by runway/designator, independently of input row order. Feet are parsed
with bounded Decimal grammar and multiplied by exact 0.3048 before final JSON
number conversion. Original field/value/unit and stable record locators remain
with observations; source method/dates, AGL TPA, old magnetic variation, traffic
flags and blank gradient/threshold-elevation facts remain explicitly labelled notes.
These notes are metadata, not procedures or machine instructions.

Known physical ends are retained separately from landing thresholds. The actual
`LAT_DISPLACED_THR_DECIMAL`/`LONG_DISPLACED_THR_DECIMAL` fields are used; blank
coordinates/displacement/declared distances stay unknown. No physical-end equality,
zero displacement, full-runway distance, flat gradient or ellipsoid height is
inferred. Horizontal coordinates remain generic NAD83 (EPSG:4269), null realization/
epoch, and vertical observations remain `msl-unspecified`. Published true bearings
and designators are separate. Turf/glider facilities and omitted lighting/taxi/
frequencies/closures/obstacles/operations are not disproved by the paved subset.

## Focused tests and independent real-source comparison

```powershell
& $Python -I -B -m unittest discover -s tests/airports/kawo -p 'test_*.py' -v
```

That default run is synthetic parsing/mapping only; the actual archive comparison
is skipped unless Root explicitly supplies both private inputs:

```powershell
$env:KAWO_TEST_ARCHIVE = $Archive
$env:KAWO_TEST_DOSSIER = $Dossier
& $Python -I -B -m unittest discover -s tests/airports/kawo -p 'test_*.py' -v
Remove-Item Env:KAWO_TEST_ARCHIVE, Env:KAWO_TEST_DOSSIER
```

The actual-source test compares the immutable pre-importer hand-transcribed
[facts fixture](../../../tests/airports/kawo/fixtures/expected-source-facts.json),
SHA256 `333bc105f8117cb01218cfab60d9153cbaa7c52b8632a0a87afaf253cbf498b4`,
against output coordinates, all four elevations/headings, runway dimensions/surface
and required unknowns. It checks repeat byte identity and existing-output refusal.
Synthetic malformed ZIP/CSV/numeric/join tests call private bounded seams and never
relax production archive pins; they are not actual FAA archive acceptance evidence.
No owner/manager/contact rows or full national CSV tables are committed as fixtures.

Root also runs the accepted source-contract tests, existing schema checks and
documentation check, records exact source/output identities and reviews final-head
CI. Source consistency is separate from WORLD016 geographic accuracy, physical
terrain contact, airport operational completeness, human/pilot and P4 acceptance.
