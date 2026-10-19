# Standalone resident-grid tests

Consume the unchanged core, codec and exact-admission references in this directory.
`native.cpp` and `codec/native.cpp` use independent expected geometry and literal
payload bytes. `private_arithmetic.cpp` separately checks the implementation's
private integer kernel using predeclared exact/raw-word witnesses; it creates no
public arithmetic API.

After the [pinned bootstrap](../../../tools/bootstrap/README.md), run:

```powershell
./tools/ci/resident-grid.ps1
```

Use a fresh `-BuildDirectory` for another attempt; preserve failed attempts.
The standalone CMake project links no JSBSim, SQLite, Godot or game runtime.
It includes the existing unchanged ground-contract test alongside the three new
suites. Strict compiler flags apply; tests remain offline and frame-independent.

See [executed evidence and limits](../../../docs/evidence/P4/resident-grid-component.md).

For the separately reviewed manual resource observation, configure this same
standalone project with `-DFLIGHT_GRID_RESOURCE_OBSERVER=ON` and the pinned tools,
then run `resident_grid_resource_observer` from its fresh build directory. The
option defaults OFF and adds no CTest or CI performance gate. It reports actual
fixed-grid counts, times and whole-process Windows memory; it instruments no
allocations and claims no worst-case or real-time suitability.
