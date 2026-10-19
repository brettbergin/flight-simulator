# First approximate KAWO candidate compiler

`kawo_terrain_v1.py` is an offline authoring leaf governed by
`docs/contracts/world/kawo-terrain-compiler-v1.md`. It uses the sealed Windows x64
CPython3.12.14/pyproj3.7.2/Pillow12.3.0 environment and fixed two-tile source,
operation, constructor-metadata and scalar policies. It adds no game dependency.

Root supplies the existing accepted `KawoTerrainInputs/v1` descriptor, absolute
paths to the actual retained source bytes, a qualified sealed tools directory,
and a new output directory whose parent exists. No pin override, bounds option,
different source/backend or runtime coordinate operation is available.

Run the explicit copied interpreter as `python.exe -I -B -S` with the absolute
compiler path and exactly `--inputs INPUTS_JSON --tools-root SEALED_ROOT --output
NEW_DIRECTORY`. The outer launch must give the process separate empty ordinary
work/cache directories and set `PROJ_DATA` to SEALED_ROOT/proj-data,
`PROJ_NETWORK=OFF`, `PROJ_ONLY_BEST_DEFAULT=YES`, and
`PROJ_USER_WRITABLE_DIRECTORY` to that empty cache. Do not use PATH Python or
globally install dependencies. The compiler starts no subprocess and performs
no download. Root supervises the fixed30-minute authoring budget.

Before execution, Root separately runs accepted `validateSourcePair` on the exact
airport/dossier bytes, retaining complete accepted implementation/schema/AJV-lock
control identities, actual invocation/result and both raw hashes/counts. For the
first reviewed acceptance run use the already reviewed15785-byte974345... dossier
and37101-byte63463... airport. The compiler checks its consumed source values and
raw pair relationship; CLI success does not prove that external semantic gate.
Later reviewed source-pair updates follow the contract's same external binding.

Helper sources must be the original qualified LF bytes, including the exact
5f62... terrain_tools.py,9d6a... terrain_pins.py and7b72... terrain_decode.py
identities. Checkout portability is handled by source staging/attributes; there
is no runtime CRLF normalization or qualification repin.

The compiler verifies the complete installed creation seal before third-party
imports, actual module/DB/grid identities, exact fixed constructor definitions
and canonical constructor JSON. Receipt operation metadata remains the original
qualified discovery/authority records. It decodes only primary Float32 image0,
keeps two source planes, and processes the fixed3073x2049 grid in bounded16-row
blocks. Every point executes eight updates plus fresh pre/post-round checks.
Exact final f32 gradient, span, facet ownership and integer-mm ring predicates
reject rather than repair a failed surface. The four physical runway ends are
intersections with that same final canonical P00-P11 surface.

A completed attempt contains exactly ground.fgrd, compact deterministic
compile-receipt.json and VALIDATION-REQUIRED.txt. Successful output remains a
candidate. Separate source/schema/reference/payload/native decode+preparation,
all four native endpoint comparisons, repeated output determinism, measured
resource budgets and rights/assembly review are required. The candidate marker
is written only after the final installed-seal/raw-input checks. Failed output
directories are retained, never overwritten or reused.

Stdout is a bounded local execution observation with stage times, actual call
counts, memory and native/resource paths. Retain it privately through Root's
outer driver; clocks, paths, RSS and attempt IDs do not enter deterministic
product bytes. No pilot profile or flight history is read.

The working frame remains `approximate-unverified-frame-v1`: generic NAD83
realization/epoch unknown, GEOID18 evaluated under an unverified NAD83(2011)
assumption, and total3D accuracy unknown. FAA MSL elevations are never used as
canonical pavement/ellipsoid heights. This leaf creates no WorldPackage,
catalog, start pose, renderer, native flight or playable/training acceptance.
