# KAWO derived-data source-use review

Root recorded the limited project review at **2026-10-19T06:01:28Z**, under the
owner-authorized implementation scope. The [decision record](kawo-derived-data-rights-v1.json)
identifies all seven source artifacts and decisions. This is a project review,
not new agency permission, an exclusive project license for source data, or
approval of an assembled world.

The FAA NASR archive remains **reference-only**. Approved use is confined to
derived numerical KAWO airport/runway facts and identifiers, with source credit.
The [Copyright Office facts/expression distinction](https://www.copyright.gov/help/faq/faq-protect.html)
supports this limited project inference; it does not license the archive's
arrangement, prose or charts. The source is the [official NASR distribution](https://www.faa.gov/air_traffic/flight_info/aeronav/Aero_Data/NASR_Subscription/).
Caribbean/Bermuda records and their [separate reproduction restriction](https://www.faa.gov/air_traffic/flight_info/aeronav/Aero_Data/Airport_Data/)
are outside this KAWO scope.

The two USGS DEMs and two companion metadata artifacts are classified
**redistributable**, based on their captured 3DEP metadata and [3DEP policy](https://www.usgs.gov/3d-elevation-program/about-3dep-products-services),
subject to [USGS copyright/third-party distinctions](https://www.usgs.gov/faqs/are-usgs-reportspublications-copyrighted).
The NOAA GEOID18 grid and README are classified **redistributable** from the
retained [GEOID18 notice](https://cdn.proj.org/us_noaa_README.txt) and official
[PROJ-data inventory](https://raw.githubusercontent.com/OSGeo/PROJ-data/master/copyright_and_licenses.csv).
The exact artifact bindings, rather than mutable policy URLs alone, identify
the reviewed sources.

The approved assembly scope contains derived numerical facts, modified compiled
DEM, original geometry/materials and attribution. **No raw ZIP, TIFF, XML, geoid
grid, README, charts, logos, foreign records or third-party artwork ships.**
Credit FAA, USGS, NOAA NGS and PROJ-data; describe actual mosaicking,
interpolation, resampling, coordinate assumptions and Float32 rounding. Preserve
source dates, warranty/temporal/critical-use limits and no-endorsement notices.
Approximate frame compatibility and unknown total 3D accuracy remain visible;
this review establishes no navigation suitability or aviation training credit.

## Exact records and conformance

SHA256 identities and byte lengths:

| Record | Bytes | SHA256 |
| --- | ---: | --- |
| Decision | 11706 | `de36435e556bc567182b90cf1a409c282450205a6000450197fc7ff3a797893e` |
| [Successor dossier](kawo-reviewed-source-dossier-v1.json) | 15785 | `974345fd8eedff2e339e4eb21b8ac3a09ed69c66c4d2a045b430f9655bd15cee` |
| Re-ingested airport | 37101 | `63463d30c55f8aba56a3426efd7c2dd61287a99d66d307f3940b589b97fd6c18` |

The historical captured dossier `5db1367751d58196c440d24869e82c55fd17e3f24cfd50ac96bad788d6ec07c1`
and airport `f051644694c0b5e1ad45f2c118b169054785fce2a11c1e66bfcfc2d732c79170`
remain unchanged with pending rights. The successor retains all artifact
identities, dates and source facts; its snapshot UTC is review/authoring time,
distinct from retrieval, collection and effective dates. Source capture states
remain `captured`; the new airport remains `draft`, with identical facts and a
new dossier binding.

Fresh external preflight passed. Its retained receipt SHA256 is
`33cc40489ceb0a182acba63fa2c14f2a0e53588b643fa7d5280cba150c2ccaf9`;
the seven pinned validator/schema/package controls and complete
553-file/64-directory installed AJV closure had identical before/after
observations, hash
`897410294b974ea57adead3b2bc2f61f603883d7031db582a181e554a729b38b`.
This proves source-pair conformance only. The compiler contract permits this
later reviewed pair without rewriting captured-source pins. Full-grid terrain,
compiler output, runtime, aircraft and pilot acceptance gates remain separate.
