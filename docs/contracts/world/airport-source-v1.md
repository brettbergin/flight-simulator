# KAWO source-dossier and airport source record v1

Proposed #243 prerequisite contract, 2026-10-18. Requires checked acceptance and
independent review. This is a COMPLETE bounded source-interchange contract, not
the resident terrain/contact/runtime contract. It introduces no aircraft/world
selection, native/facade method, terrain payload, geoid transform or usable airport.
Parent #243 and #38/#39/#40/#41/P3/P4 remain open. The next physical/contact contract
must separately freeze binary bytes, APIs, readiness and source compatibility.

## Scope and exact files

- [Common closed definitions](../../../schemas/world/resident-airport/v1/common.schema.json).
- [AirportSourceDossier/v1](../../../schemas/world/resident-airport/v1/source-dossier.schema.json).
- [NormalizedAirport/v1](../../../schemas/world/resident-airport/v1/normalized-airport.schema.json).
- [Offline byte-pair conformance](../../../tools/ingest/airports/source-contract.mjs).
- [Conformance rejection/relationship tests](../../../tests/world/resident-airport/source-contract.test.mjs).

The schemas are JSON Schema2020-12 with no remote references. Every record is
closed: required keys are explicit, optional values are present as null, unknown
keys and future versions reject. Existing WorldPackage/v1 and the14-boundary
registry remain unchanged. A future world manifest may list these files under
`airport-source-dossier` and `airport-source-record` roles, with raw hashes/lengths,
without adding keys to WorldPackage/v1. Source records alone do not admit that pack.
The dossier does not reference the airport output, preventing a content-hash cycle.

This v1 is intentionally KAWO only. Its airport shape covers airport identity,
reference point, field elevation and runway ends/dimensions/surface, declared
runway distances and referenced source notes. It does not yet encode taxi graphs,
lighting, frequencies, patterns, procedures, closures or an operational planner.
Retain those facts in dated source evidence/notes until a versioned structured
contract covers them; do not let consumers parse free-text notes as instructions.

## Units and meaning of observations

All observation `value` lengths/elevations/displacements/declared distances are
meters; `true_bearing_deg.value` is degrees true in [0,360); latitude/longitude are
source geodetic degrees in [-90,90]/[-180,180]. Convert published feet by exact
0.3048 meters/foot, recording the original source locator/value/unit in the source
note. Runway designators are published strings, never numbers inferred from true
alignment. Do not recalculate their text from a current magnetic model.

Observation status is `known`, `unknown`, `conflicted` or `not_applicable`. Known
means a captured source fact is identified; it does NOT mean that the source is
current, physically surveyed, datum-converted, pilot-reviewed or safe for runtime.
Known has non-null bounded value and at least one source reference. Other states
retain null numeric/text values; do not choose a convenient value from conflicts.
Missing displaced thresholds and declared distances remain unknown, not zero and
not an inferred full-runway distance. No substitution of TORA/TODA/ASDA/LDA occurs.

Known source coordinates may have null horizontal_crs when the source does not
establish it. A non-null CRS retains authority/code, realization and epoch; missing
realization/epoch remains null. Preserve generic NAD83 as generic NAD83. Never
label it WGS84 or perform a silent datum transformation. Elevation vertical_datum
is a closed source label; `msl-unspecified` and `unresolved` remain admissible SOURCE
facts. A height of known numerical value with unresolved vertical realization is
not a canonical ellipsoid height. No geoid-zero fallback, canonical mesh vertex
or GroundSample is produced by this contract.

Source text and notes are metadata. Known endpoints with identical coordinates
in the same stated CRS reject as inconsistent runway geometry. Different or
unresolved source realizations still require a later transformation/geometry
review; this check is not a distance or runway-survey validation.

## Dossier provenance, rights and dates

Dossier records exact source ID/kind/publisher/HTTPS URL, retrieval UTC, optional
effective interval, capture state, raw artifact identity, rights classification
and notes. UTC uses whole-second YYYY-MM-DDTHH:MM:SSZ. Effective intervals are
half-open; when both ends are known, start must precede end. Retrieval/review must
not be after the dossier snapshot. A future effective cycle may be captured before
its start; that is not a claim it was current on retrieval.

`pending` has null retrieved_utc and artifact. `captured`/`reviewed` requires actual
retrieval UTC, SHA256 and positive byte count. Reviewed sources require resolved
rights classification. Resolved rights records require a nonempty license label
and review UTC; pending rights cannot claim review UTC. Rights labels are retained
review declarations, not automated legal findings. A reference-only artifact has
no packaged relative_path; its raw hash/length may still identify the referenced
source. A redistributable artifact may have a safe local package-member path.
The validator never downloads, opens or redistributes the source artifact.

Every source reference resolves to a dossier source ID and a bounded record/page/
field locator. Duplicate source IDs or identical references reject. Known facts
cannot cite an uncaptured pending source. Duplicate runway/end IDs or published
end designators reject. Within one two-ended conventional runway, both known
published designators must be reciprocal numbers with L/R swapped and C retained.
A source discrepancy must become conflicted/unknown; the validator never repairs
it. Known runway dimensions must be positive; a known displaced threshold cannot
exceed a known stated runway length. V1 contains 0..8 runways, exactly two ends each;
the current KAWO dataset's actual count is independently checked, not hardcoded
into a generic cardinality assertion.

`review_state=draft` retains incomplete/conflicting source work. `cross-checked`
requires known name/reference/elevation, at least one runway, known dimensions/
surface and physical-end designators/coordinates, no conflicted observations and
no unresolved dossier conflict. Known facts then cite reviewed sources. Optional
thresholds/distances and source datum realization may remain unknown. Cross-checked
is a source consistency state, never a renderer, contact, operational or pilot gate.

`purpose=synthetic-fixture` permits only original-fixture sources. `source-record`
forbids original-fixture sources. The supplied positive fixtures use fake locations
and dimensions and are explicitly synthetic; they are not draft KAWO scenery data.
No source schema can prove that an author truthfully classified its input. Actual
dataset bytes, record matching, rights and datum review remain separate evidence.

## Exact offline validator API and parsing

`validateSourcePair(dossierBytes:Uint8Array, airportBytes:Uint8Array)` is the one
export. Each input is1..4194304 UTF8 bytes, no BOM, no replacement decoding, no
unpaired Unicode surrogate, no duplicate decoded object key, no nonfinite/overflow
number, no trailing content. Maximum structural depth32 and200000 parsed values.
No coercion/default insertion/field stripping is allowed. The airport's
`dossier_sha256` must equal the exact raw dossier bytes, including whitespace.

Import loads only the three named bundled schemas using the repository's pinned
Ajv2020/ajv-formats dependencies; no loadSchema/network hook exists. Artifact paths
are checked as bounded relative components: no empty/dot/dotdot components,
leading slash, drive/URI/backslash, trailing dot or reserved Windows device basename.
Source URLs are absolute HTTPS without credentials. No caller path is opened.

Success returns exactly `{ok:true,errors:[],dossier,airport}` with freshly parsed
owned records. Failure returns exactly `{ok:false,errors:[{path,message},...],
dossier:null,airport:null}` with at most64 diagnostics and path length512. It never
returns a partially accepted record. Caller byte arrays are not mutated. This is
source tooling only; it produces no native authority or persisted player state.

Run `node --test tests/world/resident-airport/source-contract.test.mjs`, existing
schema checks and `node tools/check-docs.mjs` after integration. Tests retain
positive/unknown/source-datum cases and reject raw parser faults, source/rights/
date/hash mismatches, unsafe paths, invalid observations and runway relationships.
Root executes only after source review; this authored packet asserts no test pass.

## Disjoint next leaves

1. Checked acceptance of this source-interchange PR, refs #243 only; no issue close.
2. KAWO source owner maps pinned FAA/sponsor/elevation evidence into these records,
   retaining source raw-value/unit locators and explicit unknown cells; independent
   reviewer checks selected facts/counts/source dates against original records.
3. A separate contact-runtime contract freezes canonical datum transformation,
   compiled terrain bytes/intersections, conservative readiness, immutable provider
   and exact native/facade/source-history admission. No terrain/native consumers
   start from this source-interchange contract alone.
4. After that checked seam and independent expected fixtures, datum/compiler,
   resident native provider and world presentation receive disjoint owned paths.
5. Root integrates actual KAWO start/taxi/circuit/landing and offline delivery,
   keeping synthetic sessions/history and source/fidelity gates honest.