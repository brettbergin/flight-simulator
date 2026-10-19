# KAWO source discovery

Status: engineering inputs retrieved on 2026-10-18 Pacific (2026-10-19 UTC), under
[#243](https://github.com/brettbergin/flight-simulator/issues/243). This is not an
admitted world pack or an airport validation. Raw large products remain outside
Git. Source checksums identify the observations; a source date does not certify
present airport operation.

## Acquired inputs

| Product | Bytes | SHA256 |
| --- | ---: | --- |
| FAA 2026-10-01 APT CSV ZIP | 8,030,968 | `aba48ea877f249d9b8cd63988b14b3432a6a09ad1fbe9561a5e6443c99c03dd0` |
| USGS bounded 1 m DEM discovery response | 22,703 | `cd5f20f1d2407825524ec6cf0322d7792c36cc7bfd967810aa15db97a7d7555b` |
| USGS x56y534 ScienceBase metadata | 10,755 | `ec1bf3e24926bb8f1dd8db05ed1e751a26085e2740ea360f2b3acd52ef307f80` |
| USGS x56y534 tile XML | 12,170 | `c969dc8fcc548ef0670e3fb315ea461cc1f1f59461539816e3b946328f91f8dc` |
| USGS x56y534 GeoTIFF | 497,020,458 | `b62bd2d39d081642fd2b1710a2e3971a216702903b36812304a61ec79f6ac97e` |
| NOAA explicit GEOID18 coordinate probe | 219 | `2f8164bf648ff796db570267f08d00a4ded4517fdb917cf5e68716dd713c7d5c` |

The [FAA archive](https://nfdc.faa.gov/webContent/28DaySub/extra/01_Oct_2026_APT_CSV.zip)
contains the cycle's CSV README, APT layout and structure definitions. Its matched
AWO/KAWO records comprise one airport, two paved runways and four physical runway
ends. The source reports 11/29 as 3,498 x 75 ft and 16/34 as 5,332 x 100 ft. These
are published dimensions, not measured compiled geometry. Turf/glider facilities
and other missing surface detail are not disproved by this filtered paved set.

The same-cycle README establishes NAD83 as the US horizontal datum family. It
does not identify its realization or coordinate epoch. The layout identifies
airport/runway-end elevations as feet MSL; that does not establish NAVD88.
Retain the airport's estimated position method separately from its surveyed
elevation method and the stated 2006 source dates. True runway alignment,
published designator and dated magnetic variation are distinct fields. Blank
declared-distance or displaced-threshold fields are unknown until their source
semantics are resolved; they are not automatically zero or full runway length.

## Terrain input and unresolved registration

The official [ScienceBase tile record](https://www.sciencebase.gov/catalog/item/5eacfbcd82cefae35a2509fa)
and its linked
[GeoTIFF](https://prd-tnm.s3.amazonaws.com/StagedProducts/Elevation/1m/Projects/WA_Western_North_2016/TIFF/USGS_one_meter_x56y534_WA_Western_North_2016.tif)
identify the WA Western North 2016 project. The actual raster header is 10012 x
10012, Float32, LZW, 1 m spacing, EPSG:26910 (NAD83 / UTM 10N), raster-area
registration, top-left projected corner 559994 / 5340006 m and NoData -999999.
The [actual tile metadata](https://prd-tnm.s3.amazonaws.com/StagedProducts/Elevation/1m/Projects/WA_Western_North_2016/metadata/USGS_one_meter_x56y534_WA_Western_North_2016_meta.xml)
describes NAVD88 heights in meters and refers accuracy questions to original
project metadata. Its metadata interval is 2016-03-17 through 2017-05-28;
publication is 2020-03-30. Retain these separately from aviation effective dates.

The tile's reported geographic bounding rectangle contains the published airport
reference and four runway-end positions. That is a discovery relationship, not
proof of complete non-NoData coverage or a validated circuit extent. Adjacent
tile overlap, actual sample registration, missing cells and required resident
coverage need explicit checks before compilation.

The [NOAA GEOID18 probe](https://geodesy.noaa.gov/api/geoid/ght?lat=48.16075&lon=-122.15902777&model=14)
returns -22.711 m and reported error 0.033 m at the literal queried coordinates.
It is not an airport ellipsoid-height result. GEOID18 requires compatible
NAD83(2011) coordinates/heights; it cannot alone transform an unspecified NAD83
realization to WGS84. Exact original terrain realization, transformation/grid,
uncertainty and independent known points remain unresolved. Do not flatten the
airport onto the DEM or silently treat chart MSL as ellipsoid height.

## Rights and next evidence

The USGS product metadata identifies 3DEP products as public domain and requires
modified data to be described without implying USGS endorsement. Preserve source
notices and all authored overlay explanations. FAA product and third-party rights
remain source-specific. Sponsor maps, photographs, logos and commercial basemaps
have not been cleared or imported.

The source-dossier/normalized-airport contract precedes ingestion. A separate
complete physical surface/datum/start/source-compatibility contract precedes
runtime consumers. Chart Supplement, diagram/taxi/hold/sign data, actual terrain
transform and obstacle completeness remain open. No current player was changed
to KAWO, and no procedure scoring, real-flight suitability or pilot acceptance is
claimed by this source discovery.

## Source-contract verification

The proposed source interchange passed 46 offline conformance checks, the existing
14-contract generation check, all 11 contract regression tests and documentation
checks on Windows. Independent source review corrected reciprocal runway pairing
and coincident endpoint rejection before this run. These results establish the
bounded metadata seam only; final-head CI and checked merge precede ingestion.
