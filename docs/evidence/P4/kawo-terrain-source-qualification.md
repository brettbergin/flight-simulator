# KAWO terrain source and operation qualification

This evidence supports the bounded [terrain compiler contract](../../contracts/world/kawo-terrain-compiler-v1.md) under [#243](https://github.com/brettbergin/flight-simulator/issues/243). It qualifies exact source decoding, selected coordinate operations and batch-container behavior for an **approximate prototype working frame**. It is not a compiled terrain product, survey, operational airport or world/runtime admission. Source realization/epoch compatibility remains unverified and total3D accuracy is unknown.

## Exact source and tools

The [portable observation pins](../../contracts/world/kawo-terrain-pins-v1.json) retain exact four operation records, their authoring inputs, source/decoded-plane identities, source-specific NoData words, anchor and basis words. SHA256 is `0665004e2ccc95502ede62a8cc2ee342bc5d4784181c6a42aa7ccfc837f97aa8` (25,080 bytes). Full WKT inputs for EPSG1188/9595 remain distinct from their observed emitted definitions; UTM and mathematical ECEF use the exact pipeline literals exercised in the acquisition check. The compiler must instantiate those fixed inputs and verify emitted facts, without selecting a replacement operation.

All execution used the [separately qualified offline tools](terrain-tools.md): copied CPython3.12.14, pyproj3.7.2/PROJ9.5.1 and Pillow12.3.0/libtiff4.7.1. Before execution/import and after completion, the complete installation was checked against its 2,745-file, 152-directory, 111,914,037-byte seal. Actual loaded wheel DLL/PYD paths and hashes, sole database/grid paths, disabled networking and empty owned cache/work directories were checked. No new package or backend was installed for these probes. The fixed tool-qualification input is [TerrainToolQualificationEvidence/v1](terrain-tools-run-v1.json), SHA256 `71c0e5b2251dbe1c8e97c163b2cd7dd9237ee02b47e4b73c6732ee517458312c` (76,231 bytes); this public summary binds the earlier actual qualification, while the compiler still verifies the real installed seal.

The two pinned USGS1m tiles are x55y534 and x56y534 from WA_Western_North_2016. Each primary image is 10012×10012, little-endian Float32/LZW/Predictor1, PixelIsArea, generic NAD83/UTM10N, with NAVD88 metres in companion metadata. Each TIFF reports six frames; these checks read the primary frame only and make no overview qualification claim. Pillow decoded one source at a time without resampling or integer conversion. Both primary planes contain 100,240,144 finite samples, zero NoData and zero nonfinite values.

| Primary plane | Observed decoded SHA256 | Valid minimum / maximum, m |
| --- | --- | --- |
| x55y534 | `17bfa820d54edca27ab130f945f65f6f159d7e598673d3589415ac392832cb85` | 2.1588757038116455 / 185.6197052001953 |
| x56y534 | `bf94d3dd0750bd904198beca2b9d2a5b8ac0cfa4d377ff5b9d39ec427efab8ca` | 9.464057922363281 / 181.95668029785156 |

These full-plane hashes are observations, not independent whole-plane oracles. Twelve predeclared clipped blocks per source were compared byte-for-byte against separate raw TIFF/LZW decoding, including padded edge tiles. East checks were retained from tool qualification; the final acquisition probe added west checks and reproduced the previously observed east-plane hash. The unchanged independent decoder was not generalized to a new storage profile.

Independent exact IEEE/Fraction controls establish west NoData `ffff7fff` (little-endian negative maximum Float32) and east NoData `f02374c9` (-999999). Actual tags and stdlib words agree. Zero, negative heights and a nonowner source's sentinel are not silently reclassified. The exact12-column overlap contains 120,144 sample pairs and 103,896 differing words. Its maximum difference is exactly953/524288 m =0.0018177032470703125 m. The first maximum occurs at row1148, west column10011/east column11, raw little-endian words `6235c841`/`a931c841`. This evidence supports the fixed owner seam; it does not average the two sources.

## Coordinate and height checks

Phase-A checks retained the fixed EPSG1188 geog2D approximation, UTM10/GRS80 conversion and mathematical WGS84 ECEF conversion. The source ARP remains latitude48.16075°/longitude−122.15902777°. Independent high-precision mathematical controls covered ECEF/EUS, quadrants, equator/pole, height/up and the UTM central meridian; native axis/unit order, inverse calls and scalar/list batch consistency passed. The positive-zero anchor height is a mathematical origin, not field elevation or MSL. The operation's published4m component is not a total accuracy claim.

Before evaluating the vertical operation, a separate raw reader decoded twelve NOAA GEOID18 Float32 nodes in three Deflate/Predictor3 tiles using the actual GeoTIFF scale/tiepoint/Point registration. Hand synthetic predictor controls and exact Decimal bilinear references were frozen first. Actual scale values were preserved; neither ideal1/60° replacement nor an Area half-pixel shift was introduced. Two in-area offnodes and the literal source ARP became positive vertical witnesses. A third raw point at49.470833…° is outside the fixed operation's49.38° northern bound and is retained solely as a raw-decoder/explicit pre-transform refusal case.

The fixed full-WKT EPSG9595 operation was evaluated in INVERSE direction with native latitude/longitude degrees and NAVD88 H metres, under the explicit unverified NAD83(2011) working-position assumption. Inverse H=0 and H=100 agreed with independent raw bilinear H+N expectations at all three positive points; maximum height discrepancy was below4.5×10⁻¹⁴ m. The comparison budget2⁻²⁰ m was declared before operation output, with exact boundary/nextafter controls. It is an engineering numerical-conformance allowance, not geographic accuracy or a general rounding theorem. Forward roundtrips returned0/100; all six scalar/list-batch triples agreed bitwise. All twelve Pillow/libtiff node readbacks matched the frozen raw Float32 words.

A fresh child process/context with only the pinned database and disabled network could not resolve the mandatory grid. Attempting this same full WKT's inverse coordinate failed with PROJ error4098, “No inverse operation”; no alternate operation was attempted and the good tool tree remained unchanged. Explicit area guards refused the out-of-area raw point before calling the operation. Bounding-box membership is not an onshore polygon proof or an assumption that PROJ enforces areas automatically.

The final container probe compared lists against owned `array('d')` inputs/outputs for those same four operation inputs, in both required directions, at3 and49,168 points. All ordinate bits matched; inputs stayed unchanged and outputs had independent storage/typecode `d`/itemsize8. Large cases repeat the fixed positive points; they test the container boundary, not additional geographic truth. Nine independent synthetic acquisition tests and nine vertical guard/threshold tests passed.

The final source/container worker took37.922 seconds; its complete attempt including preflight took62.844 seconds. Observed peak working set was1,653,514,240 bytes, below the fixed3GiB process limit. The conservative four-plane working-buffer allowance was1,603,842,304 bytes, below2GiB. This probe permits full-plane backend loads; it claims neither streaming nor zero-copy behavior. These figures do not measure the later compiler or game.

## Source-pair binding and rights

The [combined captured dossier](kawo-terrain-source-dossier-v1.json), SHA256 `5db1367751d58196c440d24869e82c55fd17e3f24cfd50ac96bad788d6ec07c1` (12,237 bytes), preserves the FAA source object and adds the two TIFF/XML pairs plus NOAA grid/README. Actual retrieval UTCs and artifact hashes are retained; its snapshot is the maximum capture UTC, not an invented source effective date. The unchanged accepted FAA ingester produced a new37,101-byte airport record, SHA256 `f051644694c0b5e1ad45f2c118b169054785fce2a11c1e66bfcfc2d732c79170`. The separate accepted `validateSourcePair` succeeded on those exact bytes. This proves source-pair contract consistency only; review_state remains draft. Earlier FAA-only inputs and outputs were preserved.

Rights remain pending in this captured dossier. The USGS companion metadata identifies public-domain3DEP data and requires honest modification descriptions/no implied endorsement; its status is consistent with [USGS copyright policy](https://www.usgs.gov/information-policies-and-instructions/copyrights-and-credits). The retained [PROJ NOAA README](https://cdn.proj.org/us_noaa_README.txt) GEOID18 section labels that grid Public Domain. That is not treated as a license for every part of the multi-model README. These source statements support later explicit rights review; capture alone does not authorize an assembled distributable pack. No raw TIFF, database, grid, archive or third-party image is included here.

## Retained execution identities and next gates

| Actual receipt | SHA256 |
| --- | --- |
| Operation phase A | `378d01ac190896af994cd5e4302cdcd19bb0b56571114d96143dab45820675cc` |
| Independent raw geoid witnesses | `95a7f77436ff1ebd534847a1626e60ea616e127c66228e2f2b06f1b066e0576e` |
| Vertical qualification | `388bbc271474f420840d64ab85b158bca3004f7f496b1e663391a4fb0c95b311` |
| Source decode/container qualification | `11610ccea77455c92e4b5dbbe70161394b914275d17c4caba4a3fde7d95e6ed7` |

Root reviewed every source before execution; independent reviewers examined sources and actual outputs. Failed earlier tool attempts remain retained separately. Raw local receipts preserve complete tool/source/native observations and logs; their private paths are omitted here. Portable pins are a faithful bounded extraction, not a new transform or compiler product. Existing [hand arithmetic references](../../../tests/terrain/kawo/reference/README.md) were frozen independently before consumer implementation.

Checked contract/schema acceptance must precede compiler consumers. Complete-grid inverse support, all eight updates and residuals, final Float32 gradients, exact payload/native admission, four runway-end facet comparisons, repeated-byte determinism and actual compiler time/memory remain later implementation evidence. Runtime world selection, aircraft start, rendering and installed airport evaluation remain later still. These successful source checks close none of those gates.
