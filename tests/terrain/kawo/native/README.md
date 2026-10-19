# Standalone KAWO native payload qualification

Issue257 headless acceptance harness only. It links the accepted contracts,
ground boundary and resident grid/codec; no Session, JSBSim, Godot, SQLite,
profiles, saves, world catalog or runtime source is linked or mutated. This
source requires Root review before any build/test/native execution. No successful
build, test count or actual payload result is claimed by this source packet.

`reference/selected_controls_v1.hpp` is copied byte-exact from Root's accepted
mechanical transcription, SHA256
`c34f5d1e22088a0da9ab989ac7157a3616aeffac7ac284b96a9230e4408637b7`.
Its data derives from the independently frozen756727-byte reference
`ed63fb9a14cff9db1ab5dbd6ae0637d62591da9acfed43077f804155a7744cb2`,
actual worksheet `ae5f2a5840d96470193b4e8d8ec586f22333ad0d06216f8fdc616d489cc1135d`
and launch `807512fb65c824414390bfb188f912ce2cbcf53a26c13a2a09d0fa38f47dd88e`.
The harness does not regenerate these expectations, import a compiler or read
candidate output to decide expected words/heights/rings.

## Inputs and checks

The manual command has exactly these ordered arguments:

```
kawo_payload_validator --payload ABSOLUTE_FILE --observed-payload-sha256 LOWERHEX64
```

The digest is explicitly **Root's external observation**, not a hash computed
by this executable. Root must hash the same actual file before/after this run,
compare its raw digest/length against the compiler receipt and retain the exact
invocation, executable/source/build identities, stdout/stderr and exit status.
No world manifest exists at this seam. The test ContentRef names the frozen
selected reference, while prepared_surface_sha256 carries the external observed
payload digest. Output labels that identity qualification-only; it cannot be
used as installed-world/catalog authority. File read is bounded by the accepted
codec maximum276946836 bytes, requires an ordinary absolute regular file with
no symlink/reparse ancestors, exact-length read and EOF. The controlled outer
before/after digest check remains necessary; no hostile concurrent-file or
cryptographic native-file-admission claim is made.

The existing native decoder validates actual owned bytes, then the harness checks
the fixed3073x2049/4m grid, exact anchor/origins, all6296577 valid vertices with
zero padding, missing/default policy, exact two original material IDs and0.8/0.6
binary64 factors, both ordered priority100 asphalt polygons/mm rings, and all81
independent final Float32 words. It moves the decoded Definition into the real
immutable PreparedGrid, retaining no mutable alias. Native preparation supplies
the accepted full-definition gradient/span/budget admission.

All four independent working-radian positions are sampled through the real
Boundary at query ellipsoid heights0 and1000m. Every returned sample must be
valid, preserve all header/location bits and qualification ContentRef, have a
unit upward NED normal and an admitted original material with exact factors,
and match independent ellipsoid ground h within inclusive1/1024m. Height,
normal and material are identical across the two query altitudes. Either terrain
or asphalt is allowed at the exact endpoint because quantized polygon ownership
must not be guessed. There is no synthetic flat-height fallback.

The native API returns ellipsoid h, not an EUS endpoint. The frozen header's EUS
words remain for Root's separate receipt/facet correspondence checks; the harness
does not pretend those are a native return value or parse compile-receipt JSON.
It writes observations only to stdout and failures to stderr, with nonzero exit
on rejection. No accepted-product file or game state is written.

## Root build and test guidance

After adopting the reviewed sources under their mirrored paths, use the pinned
bootstrap's actual CMake/Ninja/compiler/CTest paths and environment. Example
PowerShell variables below are placeholders for those already qualified paths;
these commands have not been run by this packet's author.

```powershell
& $CMake -S "$Repo/tests/terrain/kawo/native" -B "$Attempt/build" -G Ninja -DCMAKE_BUILD_TYPE=Release -DCMAKE_MAKE_PROGRAM="$Ninja" -DCMAKE_CXX_COMPILER="$Cxx"
& $CMake --build "$Attempt/build" --target kawo_payload_validator kawo_validation_tests
& $CTest --test-dir "$Attempt/build" --output-on-failure
& "$Attempt/build/kawo_payload_validator.exe" --payload "$Candidate/ground.fgrd" --observed-payload-sha256 $ObservedPayloadSha256
```

Use a fresh Root-owned attempt/build directory and retain failures. The standalone
project needs no downloaded dependency or root simulator configure. Keep existing
resident-grid/codec CTests unchanged and run their appropriate regression lane
separately; this harness is not a replacement.

`kawo_validation_refusals` contains isolated synthetic value/argument controls:
exact options/lowercase digest, generic valid codec grid refused as wrong product,
inclusive endpoint tolerance and outward-nextafter failures, missing/nonfinite
ground, wrong header/world, signed-zero echo, wrong material/normal and changed
coefficient. It constructs no fake passing KAWO terrain and is not actual product
evidence. Actual payload/native acceptance requires Root's later manual run on
compiler output and independently bound receipt/reference checks.

Successful native qualification establishes decode/preparation and selected
four-end correspondence only. Full source support/convergence, compiler residual
traversal, repeated-byte determinism, memory/time, rights/notices, assembled world,
aircraft starts, rendering, flight/contact, pilot review and phase acceptance
remain separate gates. Total3D source accuracy remains UNKNOWN.
