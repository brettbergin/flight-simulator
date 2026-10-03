# Aviation and world source register

Reviewed online on **2026-10-03**. This register records research used for the design; it is not a licensed source-data bundle. Acquire exact publications/files with versions, applicability, permissions and SHA-256 checksums during implementation. Links can point to newer editions later. Technical-stack sources belong in the relevant architecture decision records.

## Aviation instruction and operations

| Source ID | Primary source | Verified version/context | Intended use and acquisition requirement |
| --- | --- | --- | --- |
| SRC-FAA-ACS | [FAA Airman Certification Standards catalog](https://www.faa.gov/training_testing/testing/acs) and [Private Pilot airplane ACS PDF](https://www.faa.gov/training_testing/testing/acs/private_airplane_acs_6.pdf) | FAA-S-ACS-6C; catalog lists effective 2024-05-31. PDF revision history identifies November 2023 | Curriculum references; capture actual file revision/hash rather than infer edition from catalog alone |
| SRC-FAA-PHAK | [Pilot's Handbook of Aeronautical Knowledge](https://www.faa.gov/regulations_policies/handbooks_manuals/aviation/phak) | FAA-H-8083-25C | Systems/instruments/performance/human-factors background; use index addenda |
| SRC-FAA-AFH | [Airplane Flying Handbook](https://www.faa.gov/regulations_policies/handbooks_manuals/aviation/airplane_handbook) | FAA-H-8083-3C | Maneuver context; current addenda must accompany base publication |
| SRC-FAA-INDEX | [FAA aviation handbooks/manuals index](https://www.faa.gov/regulations_policies/handbooks_manuals/aviation) | Index lists October 2025 addenda for AFH/PHAK | Track superseded source content before writing lesson text |
| SRC-FAA-AIM | [FAA current AIM](https://www.faa.gov/air_traffic/publications/atpubs/aim_html/) | Direct open showed effective 2026-07-09, Change 3; an older FAA URL/search result showed an earlier change | ATC and operating context; select current publication endpoint and capture exact pages |
| SRC-FAA-PATTERN | [AIM airport operations](https://www.faa.gov/air_traffic/publications/aim_html/chap4_section_3.html) | General pattern guidance with published/local exceptions | Research reference; reconcile applicable current AIM version when implementing |
| SRC-FAA-NONTOWER | [AC 90-66C](https://www.faa.gov/regulations_policies/advisory_circulars/index.cfm/go/document.information/documentID/1041885) | Active, issued 2023-06-06 | Non-towered communications/operations context; distinguish guidance from regulatory requirements |
| SRC-FAA-RUNWAY | [Runway Safety Publications](https://www.faa.gov/airports/runway_safety/publications) | Collection of FAA runway-safety resources | Select specific publication/video references when a runway lesson is authored |
| SRC-US-PREFLIGHT | [14 CFR 91.103](https://www.ecfr.gov/current/title-14/chapter-I/subchapter-F/part-91/subpart-B/section-91.103) | eCFR displayed current through 2026-10-01; continuously updated | Preflight legal reference for US content; capture point-in-time edition, not unversioned legal constants |
| SRC-FAA-ATD | [AC 61-136B](https://www.faa.gov/regulations_policies/advisory_circulars/index.cfm/go/document.information/documentID/1034348) | Active, issued 2018-09-12 | Explains separate ATD approval program; this project makes no approved-device credit claim |

The simulator's proposed lesson inventory and thresholds are original design decisions unless explicitly attributed to an applicable source. Do not present a general FAA handbook as an aircraft-specific checklist or a general ACS area mapping as approved course coverage.

## Aircraft references

| Source ID | Primary source | What it establishes | What remains open |
| --- | --- | --- | --- |
| SRC-TXTAV-SKYHAWK | [Textron/Cessna Skyhawk](https://cessna.txtav.com/en/piston/cessna-skyhawk) | Current marketed aircraft uses IO-360-L2A, fixed-pitch propeller and G1000 NXi | Does not supply a configuration-specific analog 172S POH/AFM or full aerodynamic model |
| SRC-TXTAV-1VIEW | [Textron Aviation apps/1View](https://txtav.com/en/apps) | Manufacturer platform for flight/maintenance/service/parts/wiring publications and subscriptions | Obtain permitted access and exact document applicability; access is not redistribution authorization |

**Open aircraft source gate:** choose model year/serial applicability and installed analog equipment; acquire applicable POH/AFM, revisions and supplements; identify approved source for table/limit extraction and rights; document aerodynamic derivative gaps. Until then, the aircraft is a selected target profile with provisional coefficients. Do not copy a random online POH or relabel a third-party flight-model seed as validated C172S data.

## Aeronautical, geographic and weather data

| Source ID | Primary source | Verified detail | Implementation requirement |
| --- | --- | --- | --- |
| SRC-FAA-NASR | [28-day NASR subscription](https://www.faa.gov/air_traffic/flight_info/aeronav/Aero_Data/NASR_Subscription/) | Direct page showed current 2026-10-01 and preview 2026-10-29; announces Sept 2026 schema changes | Pin effective cycle; format fixtures/schema version; do not ingest preview as current |
| SRC-FAA-ENASR | [eNASR browser](https://www.faa.gov/air_traffic/flight_info/aeronav/Aero_Data/eNASR_Browser/) | Current/next/PreChart datasets; preview data can change | Useful discovery context; importer uses released pinned files |
| SRC-FAA-CS | [Digital Chart Supplement](https://www.faa.gov/air_traffic/flight_info/aeronav/digital_products/dafd/) | 56-day publications; current 2026-09-03, next 2026-10-29 on reviewed page | Exact region/page/effective dates and related notices; don't assume all products share NASR cycle |
| SRC-FAA-PRODUCTS | [Digital products catalog](https://www.faa.gov/air_traffic/flight_info/aeronav/digital_products/) | Airport diagrams, VFR/IFR charts, CIFP and obstacle products | Product-specific rights and provenance review; no blanket chart redistribution assertion |
| SRC-FAA-NOTICES | [Safety alerts/charting/data-product notices](https://www.faa.gov/air_traffic/flight_info/aeronav/safety_alerts/) | Notices identify source corrections and format changes | Consult relevant notices during import and document applied corrections |
| SRC-FAA-OBSTACLES | [FAA obstacle products](https://www.faa.gov/air_traffic/flight_info/aeronav/obst_data/) | Daily/56-day products include obstacle metadata and accuracy codes | Preserve source accuracy; not a complete guarantee of all local obstacles |
| SRC-USGS-3DEP | [3DEP products/services](https://www.usgs.gov/3d-elevation-program/about-3dep-products-services) | Products free of charge and without use restrictions | Select tiles/resolution, retain metadata/datums; verify each ancillary layer separately |
| SRC-USGS-TNM | [National Map GIS download](https://www.usgs.gov/the-national-map-data-delivery/gis-data-download) | Distribution entry point for elevation and other geospatial layers | Check specific source/layer metadata before packaging |
| SRC-NOAA-AWC | [Aviation Weather Center Data API](https://aviationweather.gov/data/api/) | Product formats, cache files, limits, no CORS and history scope documented | Recheck schema before code; native request adapter/cache/failure behavior |
| SRC-NOAA-RIGHTS | [NOAA education/outreach FAQ](https://www.noaa.gov/office-education/outreach-communication/faq) | Nearly all NOAA content is public domain; exceptions require attention | Verify specific product and third-party notices; don't assume every NOAA-hosted asset is unrestricted |
| SRC-NOAA-WMM | [NCEI World Magnetic Model](https://www.ncei.noaa.gov/products/world-magnetic-model) | WMM2025, model validity and published test vectors | Pin coefficient/model/software terms; validate implementation against test data |

## Initial airport research

| Source ID | Airport sponsor source | Design implication |
| --- | --- | --- |
| SRC-KAWO-DATA | [Arlington airport data](https://www.arlingtonwa.gov/236/About-the-Airport) | Specific runway directions and pattern altitudes belong in airport records |
| SRC-KAWO-PATTERNS | [Arlington traffic patterns](https://arlingtonwa.gov/241/Traffic-Patterns) | Mixed glider/ultralight traffic and local pattern/noise context need reviewed scenarios |
| SRC-KPAE-NOISE | [Paine Field noise procedures](https://www.painefield.com/159/Noise-Abatement-Procedures) | Voluntary noise procedures are subject to safety/ATC discretion; tower-closed conditions differ |
| SRC-KPAE-CONSTRUCTION | [Paine Field airfield construction](https://www.painefield.com/188/Airfield-Construction) | 2026 construction changes runway availability and length; version historical conditions |
| SRC-KBFI-PILOT | [Boeing Field pilot information](https://kingcounty.gov/en/dept/executive-services/transit-transportation-roads/airport/pilot-information) | Sponsor documents wrong-runway hazards and links current local VFR route material |
| SRC-KBFI-ROUTES | [KBFI VFR routes, 2026-09-25](https://cdn.kingcounty.gov/-/media/king-county/depts/executive-services/airport/pilot-information/bfi-vfr-routes-20260925.pdf?hash=056DB9C1DE0591C866C17E5DD987AA75&rev=f8a8ea4e67ce42dcaf49005b2176f2c9&sc_lang=en) | Local routing deserves separate review alongside surrounding airspace before scored instruction; retain sponsor landing-page link if document URL changes |

Airport website information is discovery evidence, not a substitute for dated official datasets, current notices and review. Facts in these pages must not be copied into software without field applicability and source dates. Sponsor graphics/brochures may have their own copyright terms.

## Required source manifest and maintenance

Each implemented source record needs ID, title/publisher, original URL, acquired UTC, document/product version, effective interval, applicability, exact section/page/record, checksum, rights statement/license URL, derivation description, redistribution decision, credited attribution, reviewer and confidence. Link data values and lessons to those records. Keep raw restricted material outside public repository/release assets; store metadata and authorized original derivations instead.

Source changes open an impact review covering aircraft limits/performance, lessons/rubrics, airport procedures, data importers and release fidelity reports. Historical data remains pinned for reproducibility; updated data arrives in a new pack/version. Stale links or differing catalog/PDF revision dates are reported as ambiguity and checked against actual artifacts. No recurring source monitor or paid subscription is created by this documentation task.
