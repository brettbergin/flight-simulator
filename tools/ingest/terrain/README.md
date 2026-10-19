# Offline terrain tools

This authoring-only helper implements the checked [terrain-tools-v1 contract](../../../docs/contracts/world/terrain-tools-v1.md). It installs no game dependency and selects no geographic operation. Issue #250 qualification is incomplete until the owner reviews and executes these sources and retains the resulting receipts.

Use Windows x64 PowerShell and the explicitly named retained CPython 3.12.14 runtime. The launcher first checks the locked raw runtime manifest, every baseline file and directory, and the executable/DLL/license. Only then does it start that executable with `-I -B -S`. No PATH Python, pip, resolver, source build, online acquisition or inherited site package is used.

```powershell
./tools/ingest/terrain/bootstrap.ps1 -Mode Create `
  -BaselinePython 'C:/absolute/retained/python.exe' `
  -RuntimeManifest 'C:/absolute/retained/manifest.json' `
  -Inputs 'C:/absolute/acquired-inputs' `
  -ToolRoot 'C:/absolute/repository/.local/terrain-tools/first' `
  -ReceiptRoot 'C:/absolute/repository/.local/terrain-tools-receipts/create-first'

./tools/ingest/terrain/bootstrap.ps1 -Mode Qualify `
  -BaselinePython 'C:/absolute/retained/python.exe' `
  -RuntimeManifest 'C:/absolute/retained/manifest.json' `
  -Inputs 'C:/absolute/acquired-inputs' `
  -ToolRoot 'C:/absolute/repository/.local/terrain-tools/first' `
  -ReceiptRoot 'C:/absolute/repository/.local/terrain-tools-receipts/qualify-first' `
  -Raster 'C:/absolute/USGS_one_meter_x56y534_WA_Western_North_2016.tif'
```

The commands are interfaces for later reviewed execution, not evidence of a successful run. Use a new receipt directory for every attempt. Creation also requires a new tool directory. Neither command overwrites an existing file. Failed attempts remain with `receipt.json` and process output; discard them manually after reviewing their evidence. All output roots must be below this checkout's `.local`, disjoint from inputs and the baseline, and contain no reparse points. No cleanup or deletion command is supplied.

The acquisition directory supplies the three exact wheel filenames, NOAA grid and README, `proj-grid-registry-v2.geojson`, and `wheel-inspection/inventory.json`. Research leftovers in that input directory are not installed. Every selected input is checked by size/hash; the installed wheel member roster must match RECORD, metadata/native/license inventory and the fixed ABI. Unsafe ZIP names, duplicate names/case aliases, symlinks, executable installation scripts, `.pth`, unsupported `.data` layouts and unbounded expansion fail.

`tool_root/environment` is a separate copy of the complete retained interpreter except `Lib/site-packages`. It is **not** a venv or an assertion that the original baseline contained no third-party packages. The child executable has the same bytes as the parent but a different absolute path and installed-file manifest. New site packages are admitted explicitly by the isolated worker; Python's `site` machinery is never enabled. Existing retained stdlib bytecode is copied as recorded; bytecode writing stays disabled.

The complete wheel `pyproj/proj_dir/share/proj/` tree is relocated byte-for-byte to the single `tool_root/proj-data` directory, followed by the pinned NOAA grid and README. No second embedded `proj.db` remains in site packages. Original wheel METADATA/WHEEL/RECORD/licenses are retained unchanged. `creation.json` records each archive member's **actual installed path**, including relocation; the original RECORD is provenance, not a false claim that its old relative locations remain installed. Manifests seal every environment/data file and directory and reject additions, omissions and byte changes before and after qualification.

Qualification uses the copied interpreter, a new empty working directory and a new empty PROJ user-cache directory. It clears inherited Python/PROJ overrides, disables PROJ networking before import and explicitly selects the single sealed data directory after import. It checks module and actually loaded wheel DLL paths, compiled/runtime versions, exact database bytes/metadata, full resolved grid path/hash and strict missing-grid refusal. Negative cases run only in separately created disposable copies; the usable tree is not modified. The receipt distinguishes a pyproj context's reported data directory from a separately inspected C-API context; neither alone establishes operating-system sandboxing. No credentials or owner flight/profile data are read.

The decoder probe checks the fixed full-size 10012 by 10012 Float32 LZW east USGS primary image. It retains source tags, overview pointer/frame count, full-plane decoded hash, exact Float32 bits, twelve independent LZW tile comparisons (including clipped padded edges), counts of nonfinite/NoData values, elapsed time and process peak working set. The full-plane hash is an observation; only the reported tile bytes have independent LZW comparisons. Budgets are 1800 seconds per child process, 2 GiB peak working set, 768 MiB installed bytes, 8 MiB decoded independent blocks and 128 MiB expanded bytes per wheel. Qualification makes four disposable environment copies in its fresh receipt directory; allow up to 3 GiB plus logs there. This is a full-plane decoder, **not a streaming terrain compiler**. The source TIFF and NOAA grid have separate meanings. Successful decode or PROJ resource loading makes no source-datum compatibility, real-operation selection, total geographic accuracy, terrain/contact or runtime claim.

Receipts remain local. They contain local absolute tool/source paths and are not publishable as-is. Root may publish a reviewed path-redacted summary under `docs/evidence/P4/terrain-tools.md`. Retain complete package/native/license inventories and database terms; the project's MIT license does not replace third-party notices. The interpreter's original upstream acquisition archive is unknown and stays null. This helper does not promise fresh-machine Python acquisition.

Focused stdlib tests are in `tests/world/terrain-tools/test_terrain_tools.py`. They construct small fixed synthetic manifests and wheel/TIFF inputs to exercise private parsers and refusal rules. They do not alter production lock values or qualify the actual environment. Root executes them with an already reviewed interpreter only after reviewing this implementation.

The independent LZW reader follows the policy documented in the official [LibTIFF v4.7.0 tagged `tif_lzw.c`](https://gitlab.com/libtiff/libtiff/-/raw/v4.7.0/libtiff/tif_lzw.c): MSB-first codes, 9–12-bit widths, clear256/end257/first258, and the TIFF early width transition. Its own byte-string implementation was authored separately. Literal tests distinguish the early transition at next-free511 from512, exercise later1023/2047 transitions, dictionary reset, the self-referential next-code case, truncated/bad streams, Float32 bit patterns and logical-raster versus padded-tile bounds. These are predeclared expectations, not expected values generated by Pillow.
