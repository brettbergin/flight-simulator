# Modified JSBSim source notice

JSBSim 1.3.1 remains at upstream commit 3b25f25e49b42d0489c04ac805674fc1450ca579.
Flight-simulator contributors modified FGPiston.cpp/.h and FGPropeller.cpp/.h
on 2026-10-09 under the existing LGPL-2.1-or-later grants. The exact recipe binds
four pristine before-images and four preferred-source after-images.

This variant retains the separately reviewed held-power angular method and
legacy default, then adds ADR015's source-law coupled midpoint method and
explicit public-boundary engine-mode chronology. No aircraft XML parameters
are included or changed. It is a new numerical surrogate, not an aircraft
performance or friction-model validation. The original vendor copyright,
LGPL notices and embedded third-party grants remain in the delivered source.

Schema3 and its four-file recipe are separate from preserved pristine schema1
and held-power schema2 packages. Reconstruct directly from pristine source;
never apply this recipe to another modified variant. First-party wrapper MIT
licensing does not replace vendor or third-party grants. Compilation, numerical
qualification, runtime DLL replacement and aircraft/pilot acceptance are
separate evidence gates.
