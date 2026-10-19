# KAWO native checks

These sources exercise the closed runtime branch. They do not accept an
arbitrary provider, world selector, path inside a pack or numeric start pose.

`readiness.cpp` is an offline predicate/parser executable. Link
`flight::interactive` (and its resident-grid dependency) and give it a private
include path to `native/world_core/grid/src`. Compile the test itself and all
linked numerical translation units under the existing strict FP policy. It
uses the pre-output readiness hand controls and independent Fraction reference
852c26214450d5f238186be33e2139c83faf18df27d6982873f77f6ddfb7feba:
least outward rounding, full 3D distance, full-height rational support,
half-open coverage, missing data beyond the previous small disk, coverage caps,
motion, unsupported rounding and unchanged caller environment. Its artificial
A/D controls test predicates only. Separate actual binary64 parity checks call
the same private canonical-frame constructor as core and runtime, including the
matching-angle algebraic case. Existing frozen grid/codec/independent-reference
suites remain the independent mathematical check of that shared constructor.
Strict syntax cases include decoded duplicate keys, Unicode/surrogates, UTF-8,
BOM, numeric grammar, finite conversion and depth/value limits. SHA standard
known-answer controls are independent of this candidate output.

`journey.cpp` uses the real closed loader, Session and owner worker. Add the
existing `interactive_worker.cpp` source to its target, include the bridge
source directory, link its normal interactive/protocol dependencies, and define
`KAWO_START_REFERENCE_HEADER` to the separate immutable start reference header
1bdfe61cc76b0f2125d152453ac214f687ba812767e0ce591dc33668023e83d6
from pure-author output1f6a464c85a9a01e5314d4eb71ba652ba00931006d89f16412ccdf5c0453b4f2.
Root owns adoption of that reference under the reserved `start-fixture/` path.
Do not replace it with catalog output or native observed state.

Run with `JSBSIM_DEBUG=0` set before construction:

```text
kawo_journey actual ABSOLUTE_ADMITTED_MODEL_ROOT [ticks0..240]
kawo_journey refuse ABSOLUTE_DISPOSABLE_BAD_MODEL_ROOT
```

The default is one actual fixed tick; zero allows startup-only inspection.
The driver checks source/model/recipe cross-refusals before allocation, actual
independent tick0 ECEF/EUS/height/orientation/gear/zero kinematics, real callback
exercise, copied provider readback, exact requested advancing tick count,
provider-free historical readback, and joined mailbox refusal. It emits owned
numeric publications for independent inspection, with no profile/history data.
This bounded held-brake observation is not landing/tire/pilot validation.

Root prepares fresh ordinary disposable payload copies for refusal mode, with
the same actual catalog: missing/changed/extra pack files, wrong bytes/size,
case aliases, symlinks/reparse points and changed inventory. Never mutate the
sealed good payload or replace production pins to make a negative fixture pass.
An exact raw manifest/file hash necessarily refuses a shape/key mutation before
its parser; isolated parser checks supply the separate syntax evidence.

All installation, build, CTest, native execution, before/final seals and retained
evidence remain Root's work. No execution result is asserted by this source.
