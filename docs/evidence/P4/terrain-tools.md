# Pinned offline terrain tool qualification

Implementation for [#250](https://github.com/brettbergin/flight-simulator/issues/250)
consumes the checked [terrain-tools-v1 contract](../../contracts/world/terrain-tools-v1.md)
and unchanged lock from PR246. Root reviewed every executable source before use,
then obtained an independent passive review. The complete installer and actual
Windows native/resource/decoder qualification passed; hosted checks on the final
PR head remain separate. This creates no current-game dependency or world.

The [helper instructions](../../../tools/ingest/terrain/README.md) describe explicit
Create/Qualify commands. A PowerShell full baseline audit precedes Python. The
worker rechecks the complete retained CPython3.12.14 manifest, directly validates
and installs exactly three pinned wheels into a separate interpreter copy without
inherited site packages, and uses `-I -B -S`. No pip, resolver, source build,
download, global install or alternate GIS environment is involved. The original
interpreter acquisition archive remains unknown, not a fresh-machine promise.

## Actual environment and resources

The [path-redacted execution receipt](terrain-tools-run-v1.json), SHA256
`71c0e5b2251dbe1c8e97c163b2cd7dd9237ee02b47e4b73c6732ee517458312c`,
binds source/input/native/data/license identities and results. The complete local
installation manifest has2745files/152directories/111,914,037bytes, separate from
the original retained interpreter. Its593,260-byte creation receipt hashes to
`fe460208fb4dcf6ef8ac3a5d0147636afecb4291fb444c547fae7e0e550072ad`.
Original wheel RECORD/licenses remain byte-exact provenance; explicit member to
installed-path mappings account for relocating the entire embedded PROJ data tree
into the single sealed `proj-data` directory. No second embedded data root remains.
Successful Create-v2 used worker source
`0fe7209b039291b7b6ad6811e5ea507bc2248ae1da978dfab3a4f91c6208cb04`;
successful Qualify-v3 used the final worker recorded below. Their respective
source identities are separated in the receipt. Later corrections affected
qualification version/resource introspection, not creation or installed bytes.

Actual imports report pyproj3.7.2, PROJ9.5.1 compiled/runtime, Pillow12.3.0 and
certifi runtime2025.08.03. The latter is the pinned module's literal spelling;
canonical wheel METADATA remains2025.8.3. Nineteen wheel native binaries were
actually loaded from their exact sealed paths/hashes. This is distinct from the
complete available native inventory, which includes unneeded/unloaded binaries.
Database metadata matches EPSGv11.022/2024-11-05, layout1/4 and PROJ_DATA1.20.

Both the actual pyproj resource record and a separate explicit C-API context
resolved the pinned database and NOAA grid inside the sealed directory. PROJ
networking was disabled before import and in the pyproj/C contexts; fresh working
and user-cache directories stayed empty. Four disposable copies with missing or
changed grid/database bytes refused before import. A separately verified
missing-grid copy also refused a mandatory absolute-file grid-open probe. The
usable environment and complete baseline remained unchanged afterward. These
checks establish the recorded search/resource behavior, not OS network sandboxing.

EPSG9595 is inspected only to examine its registered resource. The documented
`use_proj_alternative_grid_names=True` requests its registered PROJ GeoTIFF name,
`us_noaa_g2018u0.tif`, rather than legacy `g2018u0.bin`; the sealed database's
grid_alternatives row binds that relationship. No coordinate is evaluated or
real source transform selected. The operation's0.015m registry accuracy is not
accuracy of these source files or any composed geographic workflow. Generic
NAD83 source metadata does not establish NAD83(2011) compatibility. See the
[official pyproj API](https://pyproj4.github.io/pyproj/stable/api/crs/coordinate_operation.html).

## Actual source decoder

The exact497,020,458-byte east USGS source is classic little-endian TIFF42,
10012x10012 Float32, LZW/Predictor1 with256x256 tiles. Only primary IFD0 supplies
the decoded plane; overview pointer/frame facts are retained separately. Actual
Pillow/libtiff4.7.1 produced400,960,576 raw Float32 bytes containing100,240,144
finite samples, zero NoData and zero nonfinite samples. The observed decoded hash
is `bf94d3dd0750bd904198beca2b9d2a5b8ac0cfa4d377ff5b9d39ec427efab8ca`.
It is an observation, not an independent full-plane oracle.

Twelve deterministic compressed tiles, including clipped padded edges, matched
the separately implemented LZW reader byte for byte. Predeclared literal tests
cover early width changes, clear/reset, dictionary saturation, next-code behavior,
Float32 raw words, malformed streams and tile padding. Only those reported tile
bytes have independent decode comparisons. Full-plane decoding took18.25seconds;
the complete positive worker took33.843seconds with1,260,269,568bytes peak working
set, below the predeclared1800second/2GiB child bounds. This is a bounded full-plane
decoder, not a streaming compiler or performance guarantee.

## Preserved failures and remaining gates

Create-v1 rejected legal zero-payload ZIP directory headers. The corrected parser
keeps those headers separate from the exact regular-file RECORD roster and adds
positive, collision, traversal, case/type and payload tests. Qualify-v1 exposed
certifi's padded runtime spelling; Qualify-v2 used the default legacy grid name.
Both were corrected by explicit exact source/API facts, without changing pinned
inputs, installing another package, choosing another operation or broadening
acceptance. Every failed attempt remains local. Fresh Create-v2 and Qualify-v3
passed;21 focused synthetic tests also passed. Final worker source SHA256 is
`5f62cd58f0574694b8344a99a06c6660ed66e4a45b45b2693c92d1a0aa885e58`.

The actual sealed Windows qualification does not claim an installed game, terrain
compiler output, geographic/source datum accuracy, physical/render terrain
agreement, runtime world/start/history admission or phase acceptance. CI runs the
small offline stdlib tests on Windows/Linux; it does not possess this retained
interpreter or qualify the actual source environment. Only this tool leaf can
close after final checked review/merge. Parent243/40 and aircraft/pilot gates stay open.
