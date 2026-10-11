# Modified JSBSim source notice

JSBSim 1.3.1 remains at upstream commit
`3b25f25e49b42d0489c04ac805674fc1450ca579`. This distinct corresponding-source
variant is `jsbsim-1.3.1-event-aware-coupled-midpoint-local-window-v2`.

The four-file recipe inherits flight-simulator contributors' 2026-10-09 ADR015
FGPiston.cpp/.h and FGPropeller.cpp/.h modifications. On 2026-10-11 contributors
changed only FGPropeller.cpp further under the existing LGPL-2.1-or-later grants:
structured decay certificate status and one bounded connected local-window
attempt after original whole-endpoint noncertification. The other three inherited
after-images and all four pristine before-images remain byte-identical to v1.

The full certificate is still attempted first. Eight splits are shared across
at most two attempts; the nine-slot workspace, original 64-bisection solve and
fatal arithmetic/environment/capacity/stagnation guards remain. The mathematical
source law/method name `event_aware_coupled_midpoint_v1`, legacy/default methods,
engine/fuel/contact chronology and all model coefficients remain unchanged.
The new variant identity distinguishes its expanded numerical admission policy.
No aircraft XML or validated aircraft-performance claim is supplied.

Preserve the immutable coupled-midpoint-v1 archive, recipe, source and original
rejection evidence. Reconstruct this recipe from pristine upstream, never by
patching another modified variant. Original vendor copyright/LGPL notices and
embedded third-party grants remain. First-party wrapper MIT licensing does not
replace them. Compilation, numerical/regression qualification, corresponding
source reproduction and actual runtime replacement are separate evidence gates.
