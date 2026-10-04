# Flight UX iteration

Date: 2026-10-03. Issue [#100](https://github.com/brettbergin/flight-simulator/issues/100).
The owner reported a successful takeoff and landing in the prior preview and
requested substantially better visual and functional flight UX. That is a
qualitative human report; it does not qualify aircraft handling or training.

This iteration replaces the debug text slab with a responsive graphical
instrument panel and compact flight status. Original procedural geometry
adds a rounded high-wing aircraft, glazing, struts, wheels and propeller,
runway markings, apron, taxi paint, buildings, vegetation and distant ridges.
Scenery is decorative and has no colliders. The sole prepared ground plane,
native model, v1 records, physics authority and worker remain unchanged.

The panel derives TAS from native velocity minus copied NED wind/turbulence,
displays WGS ellipsoid feet, true heading, kinematic vertical speed, native
attitude and explicitly labeled body yaw rate. Fuel and held controls come
from copied native state. These are engineering truth displays, not modeled
sensors; no IAS, barometric altitude, turn/slip sensor, RPM or C172 limits
are invented. The cockpit camera has a generic 2D panel, not a modeled C172
interior. Synthesized throttle/wind sound is original presentation.

Smooth keyboard commands have an explicit sensitivity and rate bound with
no attitude feedback. Gamepad selection is deliberate, with dead-zone
mapping and selected-device disconnect pause. Focus loss pauses. Cockpit,
chase and orbit cameras, mouse look/zoom/recenter, panel/help/audio toggles
and a readable session menu preserve simulation authority. Menu input is
consumed; pause preserves native state, controls and fractional timing debt.
Fresh starts close/join the previous session. Deliberate quit also waits for
actual audio resource retirement rather than suppressing leak warnings.

The pinned Godot integration checks exercise the existing whole-flight loop
and new menu/native-state invariance, camera-only changes, dead-zone limits,
synthetic disconnect pause and synthetic keyboard press/hold/release ramps.
The panel's isolated formula checks cover wind/turbulence subtraction, units,
heading, deep-copy ownership, fuel and missing weather. Actual reference-PC
captures cover cockpit/chase/orbit, banked flight, pause menu, help, restart,
960×540 and 1920×1080. Final package/source identities and independent review
are recorded in the implementation PR. Synthetic input tests do not establish
real-device usability; actual pilot evaluation and audio quality remain open.

Reproduce with [the existing Windows runner](../../../tools/interactive-preview/README.md).
It stages and inventories all authored helper sources, runs editor/portable
whole-flight and UX checks, audits native/model/source/notices and repeats
the actual rebuilt-DLL loop. `launch.ps1 -VisualSmoke` captures the app's own
viewport images and joined cleanup, independently of headless CI. This is
functional/visual evidence, not the deferred long rendering benchmark.

P1/#18, production P2 cockpit/input/airfield acceptance, C172 calibration,
systems, real airports, persistence and training qualification remain open.
