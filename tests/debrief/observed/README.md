# Observed flight review independent fixtures

Original project engineering source, MIT under the repository LICENSE. The
reference data use no pilot logs, restricted aircraft data, consumer output or
calibration. The driver checks actual output against those frozen expectations.

Run `python tests/debrief/observed/generate.py`. This stdlib-only generator
reproduces `expected-v1.json` exactly and refuses to replace different frozen
bytes. It resolves its packet relative to its own file; no private cache is
required. Generator SHA256 is
`212ad8eac94b43db801ada0597b8a3e07982151bd8baa03ca75cbc04605e874c`;
packet SHA256 is
`a4c3184c46f2eb76c85ff4ba43fc8aac49e772a447576eeec5663fff1ac78844`.

The 42 cases were frozen before consumer observations: 24 decimal arithmetic
admissions and 18 sampling schedules. Python integers cover full uint64 without
float identities; Fraction defines relative time; Decimal80 defines chords.
Ticks, targets, counts and rational times are exact. Chord absolute allowance is
predeclared 1e-10 metre over integer Pythagorean geometry, not aircraft accuracy.
`root-ratification-v1.json` preserves independent parent review before output.
`preparation-binding-v2.json` binds final ADR011 without changing expectations.

`recorder_checks.gd.new().run(host:Node=null)` returns pass/check/failure evidence
and optionally reports each assertion through `host.check`. Stage this folder
as `res://observed_tests`, production as `res://replay/observed`, accepted helpers
as `res://simulation`, NativeReadings as `res://cockpit/instruments`, and unchanged
`tests/instruments/reference.json` as `res://instrument_tests/reference.json`.
The dense case expands all 2401 samples and checks each exact tick, target,
skip, lateness, canonical scalar and source reading identity.

Only the known synthetic Readback debt_quanta integer counter is restored after
Godot JSON parsing. Tick identities are never parsed into integers. The fixture's
elapsed_s uses inherited Wire float validation, never reference scheduling.
Supplied exact canonical markers retain 3-4-5 geometry while independently placed
ECEF/geodetic values agree within the contract's 1e-7 guard; no budget is widened.
Python qualification categories are declared inputs, not parser acceptance.
The driver separately exercises full Readback/canonical/seed/identity validation,
same-tick and historical-null behavior, copies and actual foreign Thread calls.

This pure driver calls no native session, facade, camera, mapper, profile or scene
lifecycle. Chord assertions verify stored geometry and hard gaps; actual chart
rendering and summaries require separate UI evidence. Root owns native/debt/input/
origin/lifecycle and exported UI tests. No persistence, hardware, pilot, C172 or
phase acceptance is established by this corpus.
