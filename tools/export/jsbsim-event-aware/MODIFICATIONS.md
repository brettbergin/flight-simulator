# JSBSim project modification record

Source variant: jsbsim-1.3.1-event-aware-constant-power-v1.

Flight-simulator project contributors modified FGPropeller.cpp and
FGPropeller.h on 2026-10-09. Both retain their original copyright and
license notices and prominently mark the project changes and date.
The recipe binds exact pristine before-images, preferred editable
after-images, upstream commit/acquisition and materializer.

Changes add an opt-in checked angular-method API and event-aware
constant-power arithmetic with explicit domain and floating-point
environment admission. Fresh objects retain legacy Euler by default.
The original legacy expressions and pre-step thrust/load behavior remain
in their original order. All other 277 vendor files remain unchanged.

Vendor originals and modifications retain their applicable LGPL grants;
first-party wrapper/materializer code is MIT under LICENSE.first-party.txt.
No new replacement restriction or relicensing is introduced. Numerical
qualification, coupled behavior, loaded-library identity, source rights
review and actual DLL replacement have separate evidence requirements.
This record makes no aircraft, pilot, phase or training-credit claim.
