# Original shared taxi content references

PROPOSED for [contract #224](https://github.com/brettbergin/flight-simulator/issues/224); consumers wait for complete checked acceptance and #215/#218. These original MIT source/math references are independent of the future implementation. Historical proposal status in immutable expected bytes is not rewritten after acceptance.

From repository root:

```sh
python -B tests/world/taxi/reference/generate.py --check
python -B tests/world/taxi/start-reference/generate.py --check
python -B tests/world/taxi/start-reference/generate-prop-disk.py --check
```

Every generator verifies immutable bytes without writing. The content generator admits the fixed source checksum using a duplicate-key-rejecting reader. It derives six rectangle bounds and full interval-union coverage of all 24 itinerary segments with Fraction arithmetic; the deliberate runway-to-parallel gap is rejected. Independent constants come from the old field source, not consumer outputs. Six junction faces derive viewer-right and arrow projection algebraically. Five art-center/cap/stand positions stay distinct. Eleven binary64 metric rows use 110-digit Decimal square root, half-angle atan series and Machin pi, transported as little-endian bits. The minimum subnormal east case is nonzero with exact 90deg bearing; coincident alone has no bearing. Five revision recipes distinguish actual numeric1 from BOOL/String. Seven domain recipes allocate old/new Recording/archive names, not complete records.

Predeclared bounded presentation comparisons are 1e-7m horizontal range and 1e-7deg anchor bearing; exact IDs/types/arrows/counts/bits and tiny-cardinal/coincident rules remain exact. They are not physical budgets, backend goldens or universal floating-point theorems. JSON Schema integer is mathematical: parserFLOAT1.0 may normalize to revision INT1; no generic strict lexical decoder is required. Runtime fixed raw checksum plus closed structural/relational validation is separately specified by [ADR027](../../../../docs/decisions/027-synthetic-taxi-navigation.md).

The four unchanged [pose/start reference files](../start-reference/README.md) bind WGS84 query-local pose, nominal gear and full-phase visual bounds. The two additive [physical disk files](../start-reference/prop-disk-v1.json) derive the original ideal 6ft disk centered body FRD(+2,0,0), including analytical fixed-plane support. Its nominal minimum clearance does not establish actual RunIC/contact/collision/rotating safety. Model, vendor and observed output references remain separate. source-binding-v1.json lists all six exact companion files; original pose bytes are preserved.

Before corresponding recorder/archive/PracticeSource consumers, implementation #225 must prepare independently reviewed complete hypothetical values with explicit synthetic provenance, exact types and closed acceptance/rejection. This tuple matrix does not fulfill that whole-value requirement and must not acquire a fabricated native fingerprint. Actual full qualified observations follow separately. Existing 14 wire schemas, old starts/records/archives, engine references and physical criteria remain unchanged. The independent pose tuple matrix covers 40 profile/start/wind combinations: nine old valid plus two calm-only new recipes.

FAA AIM [Chapter2 Section3](https://www.faa.gov/AIR_TRAFFIC/PUBLICATIONS/atpubs/aim_html/chap2_section_3.html), accessed 2026-10-11, sections2-3-5/8/9/10 supports the factual holding-line/color/arrow conventions. This packet copies no FAA chart, image or text; dimensions, locations and identifiers are original synthetic choices. No clearance, real-airport, official procedure, training, C172, pilot or phase acceptance is claimed.
