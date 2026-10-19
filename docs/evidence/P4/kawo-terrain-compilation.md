# KAWO offline terrain compilation evidence

On 2026-10-19, the bounded KAWO terrain compiler produced its first complete offline candidate. A fresh second compilation produced identical complete bytes for all three outputs. Independent selected-value comparisons, schema validation, native payload queries and actual-result reviews passed. Protected CI for the final source remains pending; this record does not admit an installed world or complete the airport/environment phase. [Issue #257](https://github.com/brettbergin/flight-simulator/issues/257) tracks the implementation and checked-merge evidence.

The governing interface is the [KAWO compiler contract](../../contracts/world/kawo-terrain-compiler-v1.md), accepted in PR #256 at `e0da79a426c0b2bb4b1e35bbdf8ef3f1399e20de`. The [sanitized execution summary](kawo-terrain-compilation-run-v1.json) binds the original receipts, compiler module, tools, input pair, independent references, native sources and binary by raw SHA-256 and byte count. Original receipts remain retained separately; the summary omits absolute authoring paths.

## Outputs and repeated bytes

| Output | Bytes | SHA-256 |
| --- | ---: | --- |
| `ground.fgrd` | 25,973,686 | `b2c53308fdc427900d84b541aff51ba66cbb71bc483fcee0ea16d067dbd15cfb` |
| `compile-receipt.json` | 22,937 | `cb1e0b28384aeb1c11173d991b5790a8a16e64953c2c479be6b07136c5f489f0` |
| `VALIDATION-REQUIRED.txt` | 49 | `eb74e3425b110b7c6bfa88bb2be34f5cb34fbe5cfeb7edb15ca715c2b471cb2b` |

The [byte-exact compiled receipt](kawo-terrain-compile-receipt-v1.json) retains the canonical source/payload/anchor/runway relationships.

The repeat comparison examined complete byte arrays, with independent length and digest observations. Both launches also retained unchanged source, installed-tool, control, work/cache and external source-pair observations. This demonstrates repeatability for these two runs and pinned inputs; it is not a claim about every host or toolchain.

The grid contains 3,073 columns by 2,049 rows at 4 m spacing: 6,296,577 valid vertices, zero missing vertices, and 98,385 packed validity words with zero padding. Its local east/south origin is (-6,144 m, -4,096 m). Two runway material rings accompany the terrain. Material coefficients are original prototypes.

| Full-grid compiler observation | Value | Contract limit |
| --- | ---: | ---: |
| Minimum / maximum local up | -20.406444549560547 / 155.17593383789062 m | admitted definition range |
| Maximum triangle gradient norm | 5.521415811377986 | 16 |
| Vertical bracket span | 175.61362838745117 m | 2,048 m |
| Maximum pre-round residual | 2.4393536079969635e-8 m | 1/4,096 m |
| Maximum final update magnitude | 1.368345436958407e-8 m | 1/4,096 m |
| Maximum post-Float32 residual | 7.63225619948571e-6 m | 1/1,024 m |

## Separate checks

- **33 offline unit tests passed.** Synthetic sampling, scalar grouping, Float32 and millimetre rounding, solver-driver boundaries, exact facets and input admission exercise the module without GIS acquisition.
- **23 synthetic native harness checks passed** in one CTest. These test harness inputs and refusals; they do not substitute for loading the actual candidate. The adopted CI runner also configured, built and passed these checks locally with the pinned native environment.
- **The actual candidate comparator passed:** 81 exact Float32 words, four compiled runway-end EUS coordinates and 16 exact integer-millimetre coordinates matched references frozen before compiler output.
- **Three actual schema checks passed:** descriptor, compile receipt and embedded airport geometry. The Node/AJV closure, schema controls and candidate bytes were unchanged before and after the joined process. Relational and numerical checks remain separate from schema conformance.
- **The actual native payload passed** real codec decoding, immutable grid preparation and Boundary queries. It checked the 81 words and two rings, then queried all four runway ends at ellipsoid altitudes 0 m and 1,000 m. All eight observed height differences from the frozen references were exactly zero; returned height, normal and material bits were independent of those two query altitudes. The fixed qualification tolerance remains 1/1,024 m.

The native validator was built as x64 C++20 with MSVC 19.40.33813.0, `/W4 /WX /permissive- /fp:strict`. Its actual executable and source identities are in the summary. No installed WorldPackage or aircraft Session was used. The independent selected worksheet reuses the qualified coordinate-operation backend; its independently authored scalar/raw-sample checks and native comparisons have bounded coverage, not whole-grid geographic ground truth.

An additional actual CLI refusal check deliberately supplied an existing output directory. The unchanged compiler exited with code 1 and `Refusal: new output directory/existing parent`; its only file, a 28-byte sentinel, remained byte-identical and no terrain/receipt/marker was created. Independent outer source/tool/preflight checks remained unchanged. This expected refusal occurred before a completed sealed-stack constructor; no worker native-resource observation is invented for that path.

The compiler reports eight updates and ten map evaluations per vertex across 129 blocks. Offline driver tests check that call boundary. No runtime per-vertex solver transcript was emitted or compared; the selected final-word comparisons, full-grid admission observations and native queries establish their stated checks only.

## Resources, provenance and remaining gates

Worker elapsed time was 375.531 s initially and 377.609 s on repeat. The first whole attempt took 493.838 s including outer checks. Both runs accounted for a 1,655,776,396-byte working-array bound. Observed worker peak working sets were 1,656,676,352 and 1,657,659,392 bytes. These are offline measurements on this authoring machine, not game performance or a universal memory bound.

The pinned authoring stack was CPython 3.12.14, pyproj 3.7.2 / PROJ 9.5.1, Pillow 12.3.0 and certifi 2025.8.3. The [terrain-tool evidence](terrain-tools.md) and [source qualification](kawo-terrain-source-qualification.md) describe its prior checks. Source realization and epoch remain unknown. The horizontal policy is `epsg1188-geog2d-approximation`; the vertical policy is `navd88-plus-geoid18-unverified-frame`. GEOID18 is evaluated under an unverified source-frame assumption. Total 3D accuracy remains **UNKNOWN**. FAA feet-MSL observations remain separate from NAVD88 DEM values; numerical agreement does not resolve these source limitations.

The [derived-data rights review](kawo-derived-data-rights.md) governs the reviewed dossier and narrow use of derived factual data. Raw FAA archives, charts, USGS TIFF/XML and NOAA grid/README files are not included in this candidate. Attribution, modification notices and assembly checks remain required before any later distributable package.

Protected CI for the final source remains pending. Catalog/world packaging, source association, aircraft start, rendering, visible terrain checks, operational airport completeness and pilot/phase review remain separate work. This offline candidate is prototype simulation content with no navigation suitability, aircraft-fidelity or training-credit claim.
