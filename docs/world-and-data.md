# World, airports, navigation and data

Status: design baseline, 2026-10-03. Geographic content is a versioned simulator world, not a service for planning or navigating a real flight. Airports and procedures change. All published facts below identify research evidence and must be revalidated when the world pack is built.

## Delivery sequence and coverage

**WORLD-001:** ship an original synthetic training airfield first, with controlled elevation, an asphalt runway, apron, taxi route, hold lines, windsock, lighting, signs, obstacle fixtures and optional traffic. Add a second runway only when needed to exercise crossing or wrong-surface cases. Fixtures are intentionally designed and named as fictional; they do not claim to reproduce an airport.

**WORLD-002:** the first geographic pack covers a compact Pacific Northwest region: the Arlington–Everett–Seattle corridor, with KAWO, KPAE and KBFI as staged candidates. Lowland landmarks, shorelines, water, modest terrain and nearby urban airspace support progressively richer scenarios. Mountain passes and distant airports are later scope. Route boundaries, available airports and out-of-coverage behavior must be visible before launch.

| Airport | Intended teaching role | Verified research evidence | Implementation gate |
| --- | --- | --- | --- |
| KAWO — Arlington Municipal | Initial geographic home; non-towered radio, local patterns and mixed traffic | [Airport sponsor data](https://www.arlingtonwa.gov/236/About-the-Airport) lists runway 16/34 and 11/29, small-prop pattern 1,200 ft MSL, and right traffic for 11/16; [local patterns](https://arlingtonwa.gov/241/Traffic-Patterns) cover gliders/ultralights and local constraints | Confirm pinned FAA airport record, Chart Supplement, geometry and exceptions; review local material before scored operations |
| KPAE — Paine Field | Towered operations, runway choice and airport-service schedule scenarios | [Sponsor noise procedures](https://www.painefield.com/159/Noise-Abatement-Procedures) distinguish tower-open/closed operations; [2026 construction](https://www.painefield.com/188/Airfield-Construction) documents temporary lengths and nighttime closures | Do not hardcode an old full-length runway as contemporary; pin configuration/date and reviewed schedules/closures |
| KBFI — Boeing Field | Later controlled urban destination; parallel-runway alignment, complex taxi and regional airspace awareness | [Sponsor pilot information](https://kingcounty.gov/en/dept/executive-services/transit-transportation-roads/airport/pilot-information) identifies wrong-runway/parallel-final hazards and links VFR routes updated 2026-09-25 | Review those routes, airport diagram and surrounding airspace together; no generic pattern/route shortcut |

This is a product choice inferred from these teaching opportunities. It is not an endorsement of any airport for an actual beginner's flight. Sponsor pages can conflict with dated FAA publications or transient notices. Preserve the conflict, seek applicable current evidence, and withhold scoring for disputed details. Never resolve a conflict by choosing whichever number fits the current art.

**WORLD-003:** geographic rollout validates one airport at a time. KAWO is first; KPAE and KBFI follow only after their local operational and visual evidence is ready. Free-flight exploration may offer visibly simplified scenery, but training routes are restricted to validated coverage. A world-boundary transition must not generate a flat obstacle-free surface that makes an emergency lesson deceptively easy.

## Source strategy

| Data domain | Preferred source | Plan and source-specific limitation |
| --- | --- | --- |
| Airport/runway/frequency/NAVAID/fix records | [FAA 28-day NASR subscription](https://www.faa.gov/air_traffic/flight_info/aeronav/Aero_Data/NASR_Subscription/) | Import a specific cycle; direct verification on 2026-10-03 showed the 2026-10-01 current cycle. Account for announced 2026 format changes |
| Airport text, hours, pattern notes and diagrams | [FAA digital Chart Supplement](https://www.faa.gov/air_traffic/flight_info/aeronav/digital_products/dafd/) and sponsor material | Different products have different cycles; reconcile them. Chart Supplement is published every 56 days |
| Chart symbology and later chart/procedure products | [FAA digital products catalog](https://www.faa.gov/air_traffic/flight_info/aeronav/digital_products/) | Start with an original simulator map; product-level rights/provenance gate before redistribution of actual chart raster/PDF |
| Terrain elevation | [USGS 3DEP](https://www.usgs.gov/3d-elevation-program/about-3dep-products-services) | 3DEP products are available without use restrictions; retain tile metadata, resolution, survey epoch and vertical datum |
| Structures/roads/water/landmarks | [USGS National Map](https://www.usgs.gov/the-national-map-data-delivery/gis-data-download), individually reviewed public/local datasets or original artwork | Verify per-layer rights and currency. Bare-earth terrain does not include every obstacle |
| Obstacles | [FAA obstacle products](https://www.faa.gov/air_traffic/flight_info/aeronav/obst_data/) plus original scenario fixtures | Preserve accuracy codes and timestamps; DOF is not proof that every local tree/wire/building is modeled |
| Weather | [NOAA Aviation Weather Center API](https://aviationweather.gov/data/api/) | Later opt-in native client/provider; cache station observations/forecasts with report times and fallback behavior |
| Magnetic field | [NOAA/NCEI WMM](https://www.ncei.noaa.gov/products/world-magnetic-model) | Candidate WMM2025 with test vectors; preserve coefficient/software terms, epoch and model validity |
| Temporary conditions/closures | Authored scenario notices initially; official access when later justified | No automated filing or operational use; real live NOTAM/TFR completeness is not assumed |

**WORLD-004:** start with source links and authored/synthetic fixtures, not a bulk data mirror. Retain the repository's MIT license for original code and text. Third-party manuals, charts, assets, derived data and libraries keep their own terms; an MIT root license cannot relicense them. Maintain a source/rights manifest and notices in release packages. Actual logos, aircraft branding, photographs and cockpit textures need separate rights consideration.

**WORLD-005:** paid scenery, satellite imagery, navigation databases and manufacturer documents are optional later dependencies, each requiring cost/rights review. Do not scrape Google/Bing/Apple tiles or redistribute a commercial chart because it is viewable online. Do not assume an airport brochure is federally authored or public domain. A published POH's availability also does not establish permission to redistribute it. If a needed resource is unavailable, continue with original/synthetic content and record the fidelity limitation.

## World package contract

**WORLD-006:** every pack manifest includes `pack_id`, semantic version, source records, retrieval UTC, effective interval per source/product, package build UTC, coverage polygon, coordinate/datum definitions, quality tier, licenses/notices, compiler version, content checksums and compatible simulator versions. Every authored correction contains its own explanation, evidence and reviewer. Historical packs remain immutable so replay and lessons can reproduce their world.

**WORLD-007:** ingestion is an offline build pipeline: acquire approved source → archive manifest/checksum → validate format/version → normalize units/coordinates → cross-check relationships → apply reviewed authored corrections → compile tiles/airport graph → validate scenarios → package → publish as a release asset. Raw blobs do not enter Git by default. Small fixtures and manifest samples do. No download is trusted just because it returned HTTP 200.

**WORLD-008:** importers reject missing runway endpoints, invalid latitude/longitude, contradictory units, nonexistent route references, unsupported airspace reference types and unrecognized schemas. Preserve warnings for incomplete but usable records. Require clear handling of effective-date mismatch; do not silently join frequency data from one cycle to runway geometry from a different cycle.

**WORLD-009:** make source priority explicit by field. FAA records/diagrams are reference candidates; sponsor information may add local context; authored changes are traceable overlays. Imagery is a visual aid, not authority for runway dimensions/closures. Compare named airports' identifiers and coordinates before matching datasets; similarly named airports exist in different jurisdictions.

## Coordinates, terrain and rendering

**WORLD-010:** use global geodetic position and a floating local origin for rendering. Convert to a documented physics frame; test heading/bearing, longitude wrap, altitude references and origin shifts. Terrain/airport art/traffic/nav/ATC all use the same transforms. Rebase without moving the aircraft relative to a runway or introducing a flight-dynamics impulse.

**WORLD-011:** retain the source horizontal CRS and vertical datum; convert deliberately to the simulation's datum. An orthometric DEM height is not interchangeable with ellipsoid height. Store geoid model/version where required. Airfield elevation and runway slopes must stay consistent with ground contact and instruments; avoid a single flat pad that moves terrain obstacles into the runway path.

**WORLD-012:** stream terrain by spatial tiles with level of detail, memory budgets and look-ahead. Keep immediate terrain/contact and essential runway signs/lights resident. Loading failure substitutes an explicitly simplified safe presentation or pauses the affected scenario; it must not allow flight through missing collision. Benchmark on the verified target PC once hardware/peripherals are captured.

**WORLD-013:** landmarks serve pilotage: water/shorelines, roads, ridgelines, major structures and airport visual geometry need recognition at realistic viewing distances. A dense photoreal world is not required for the first pack. Prefer airport layout/readable markings, sight picture, realistic visibility and terrain relationships over decorative building variety.

## Airport schema and validation

**WORLD-014:** airport records contain identifiers/names, position/elevation, runways with physical and displaced thresholds, dimensions/surface/slope, headings, declared distances where applicable, closures, lighting/PAPI/VASI, signs, taxiways, hold-short areas, aprons/stands, tower schedule, services/frequencies, pattern directions/altitude reference, local procedures, noise context and diagram references. Distinguish unavailable, unknown and not applicable.

**WORLD-015:** a taxiway graph contains traversable segments, runway-protected polygons, hold locations, direction restrictions, widths and ground-controller routes. Signs and ATC instructions refer to the same graph. Surface hazards use the actual aircraft footprint, not just a center point. Record active runway geometry and temporary closure overlays in saved sessions.

**WORLD-016 — proposed geometric targets:** synthetic geometry should match its design to 0.1 m in horizontal dimension and 0.05 m in surface elevation; sourced airport compiled endpoints/dimensions should agree with normalized inputs to 1 m or the source's stated precision, whichever is looser. Georegistration against an independent defensible reference aims for 5 m horizontally. These are product targets, not survey accuracy claims. Do not claim better geographic accuracy than the source. Terrain validation compares sample points with stated source resolution/error and flags smoothing or airport edits.

**WORLD-017:** inspect a complete circuit and taxi path at each supported runway by day and night; verify sign orientation, hold-line placement, runway numbers, threshold/displacement, aiming cues and visual separation from parallel surfaces. Compare independent source samples and collect screenshots for the release evidence bundle. A procedurally generated airport is not automatically validated because its coordinates parsed correctly.

## Navigation and map experience

**WORLD-018:** original map/EFB layers show airport coverage, terrain, airspace with floor/ceiling reference, route, checkpoints, simulator notices, weather stations and data dates. Training overlays can show wind correction, pattern shape or aircraft position. Independent practice lets the player remove ownship/path aids. Map features and cockpit navigation consume the same versioned world records.

**WORLD-019:** represent VOR/NDB/DME/ILS/GPS capabilities according to installed equipment and released scope. Test tuning/ident, range/line-of-sight approximations, flags, CDI/OBS geometry and station service status. Synthetic aids are clearly identified. Procedure fixes alone do not establish correct full IFR procedure execution; holding, leg types, minima and missed-approach behavior require later evidence.

**WORLD-020:** separate true/magnetic headings, runway designators and compass indication. Calculate magnetic variation for location/date using a validated model, or freeze a documented authored value in a synthetic scenario. Do not automatically rename a runway when the magnetic model changes. [WMM2025](https://www.ncei.noaa.gov/products/world-magnetic-model) is a candidate through its documented validity period; its implementation must pass published test vectors.

## Weather and data freshness

**WORLD-021:** offline authored weather is the reproducible default. Store a three-dimensional atmosphere description: pressure/temperature/density, wind with altitude/spatial variation, gust/turbulence seeds, cloud bases/tops/coverage, visibility/precipitation, time and optional hazard regions. The renderer, engine/aerodynamics, windsocks, radio weather and scenario evaluator share that state.

**WORLD-022:** live weather is later optional. Use a native provider with a descriptive user agent, caching and conservative request volume; the [AWC API](https://aviationweather.gov/data/api/) currently documents rate/size limits, 30-day historical access and no CORS support. Treat these as revisitable constraints, not a permanent API contract. A proposed default station refresh is five minutes, with jitter/backoff and no more than one concurrent provider request; tighten based on service guidance. A desktop build needs no public proxy for the initial implementation.

**WORLD-023:** every weather item stores observation/issue/valid/retrieval times, station/location, raw report, parser version and quality flags. Missing temperature/wind/ceiling is unknown rather than zero. Differentiate observations, forecasts and advisories. Do not derive terrain shear or a complete cloud field from one METAR without labeling authored interpolation.

**WORLD-024:** scenario start shows world effective date and weather mode/age. A proposed observation-age badge turns stale after 90 minutes, configurable for station/report type; this is a product display policy, not operational acceptability. Provider failure offers last saved conditions with their age or offline weather, with an explicit mode change. Evaluation scenarios freeze their input snapshot; no mid-attempt live update changes the rubric unexpectedly.

**WORLD-025:** persistent weather caches and airport packs update independently from the simulator binary. Pack updates are explicit downloads with size, checksum and license notice; install atomically, retain compatible previous packs for replays and support offline launch. A normal game update must not force a scenery redownload or destroy progress. Freshness checks never pretend to supply a complete operational briefing.

## World acceptance gate

**WORLD-026:** a regional release requires manifest/rights review, schema checks, datum tests, airport geometry/sign checks, local-procedure review, documented effective dates, radar/nav/map consistency, scenario walkthroughs and offline/provider failure checks. Keep source uncertainty and simplifications visible in the fidelity report. A later jurisdiction adds its own official aeronautical sources, licenses, rules and reviewers before claiming local training relevance.
