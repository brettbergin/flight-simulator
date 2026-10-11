# Original piston observed-review contract evidence

Status: **accepted [ADR022](../../decisions/022-piston-observed-review.md), [#195](https://github.com/brettbergin/flight-simulator/issues/195); [PR196](https://github.com/brettbergin/flight-simulator/pull/196) merged as `7ddbff810a8301d69a25d4b4e43d0f02bdebfe8c` after independent review and all four required hosted checks passed**. This is a contract and reproducible authored reference, not an implemented recording feature or native flight trace.

At contract freeze the cold-profile Scene deliberately omitted recording. The amendment permits a later bounded consumer to record actual flight and engine samples, inspect them while paused, save a new review file and reopen it as imported history. It preserves legacy Recording1/archive1 and admits only the exact original piston identity/start/world in Recording2/archive2. Full EngineStatus comes from the same owned Readback as flight readings; missing channels stay unavailable. It introduces no Cessna procedure, scoring, database, autosave or physics continuation.

## Measured synthetic reference

The [small generator](piston-observed-review-reference.py) starts from the existing immutable [legacy dense reference](../../../tests/debrief/observed_archive/reference/dense-2401.fsreview.json), SHA256 `33d5e338aa0dd7b57157dcb0bce613e3d1a1126170c5045a0dfb8b2b93ea8afc`. It authors the exact proposed piston-only shape, full ten-channel EngineStatus and four numeric binary64 tags. Its selected values and source fingerprint are synthetic; the fixture supplies format density and consistency evidence, never native identity authentication, engine behavior or new codec output.

| Measured property | Result |
|---|---|
| Samples | 2,401 |
| Legacy payload values | 225,725 |
| Added EngineStatus values per sample | 61 |
| Version2 payload values | 372,186 |
| UTF8 payload bytes | 6,339,255 |
| Whole envelope bytes | 7,419,985 |
| Whole fixture SHA256 | `72af4ea7ad6caabaf7d8238b9bf74b2fc3084e2d7d4a1015cfbfaf915c4266c1` |

These actual authored bytes exceed the existing250,000-value policy. ADR022 explicitly permits at most400,000 inner values for recognized version2 only; version1 remains250,000 and both independent byte caps remain8,388,608. The unchanged outer scanner admits the closed recognized envelope first, then selects one fixed inner policy; unknown/mixed versions and failed admission cannot retry under a larger budget. Exact inner tuple/profile/shape validation still follows. Large diagnostic-heavy records may be refused without truncation or silently expanding a cap. The superseded362,582 all-Boolean estimate is not used as evidence.

Independent review reconstructed the complete wire independently from the frozen legacy reference without calling the author generator, reproduced the exact fixture bytes/hash and checked the source/profile/world, duplicated fuel/throttle/mixture, version/budget and authority design. Review SHA256 `c16c9fc088024aab25109af0b9993cf4c83acfd34e70195331156d247e831238`; authored packet SHA256 `ef32dcf2b5a0eee41bd7f5d50bb3bd808d4de6675c8747d3596fc6296284cf87`. The published generator changes only its returned report filename from the private source; the [published measurement](piston-observed-review-wire-reference.json) makes the same metadata adaptation. This is not byte identity of the old report. Published generator SHA256 of the Git file content with LF line endings `9008e512ef6955bcac95d625ce5bd5ea5e24c9ccd6f6098863c88c4fa8480d3d`. Wire fixture bytes remain unchanged; production codec compatibility is still unproved.

To reproduce, create a fresh isolated output directory and run `python docs/evidence/P2/piston-observed-review-reference.py tests/debrief/observed_archive/reference/dense-2401.fsreview.json OUTPUT_DIRECTORY`. It refuses a different baseline and an existing output file, writes only authored wire data, and launches no simulator. The large generated fixture belongs in test output; this contract commits only the generator and measured metadata. It does not publish private pilot data or a binary flight capture.

## Dispatch and remaining gates

Accepted foundations #13/#127/#134/#138 were freshly verified CLOSED before issue195 creation. The original owner authorization permits this bounded P2 engineering contract while #75/#74/#35 and aggregate phase/source/pilot gates remain open. Parent #75 still owns the complete circuit/event/profile/resume debrief. This amendment changes neither its dependencies nor its acceptance.

After checked ADR022 acceptance, Root published and dispatched separate runtime [#197](https://github.com/brettbergin/flight-simulator/issues/197). That consumer must prove production exact v1/v2 round trips, actual strict boundaries, actual cold observations and readable historical engine output, unchanged current native/Raw/pointer/starter/recorder authority after the ordinary initial pause, real selected-file IO and fresh-process historical Open. Existing IO/security limits and qualified package/source checks remain required. This reference proves none of those runtime outcomes.
