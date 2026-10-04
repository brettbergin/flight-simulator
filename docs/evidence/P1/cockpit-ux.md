# Physical cockpit and flight locator

Date: 2026-10-03. Issue [#102](https://github.com/brettbergin/flight-simulator/issues/102).
This continues the owner's request to prioritize visual and functional flight UX
over broad foundation work. It builds on accepted #100/PR101 and the unchanged
original #98/PR99 model, native worker, prepared plane and 14 v1 records.

Original procedural interior geometry adds windshield/side-window apertures,
pillars, roof, doors, glare shield, dashboard, seats, yoke, pedals, throttle and
trim cues. No manufacturer dimensions, external art, colliders or new systems
are claimed. The interior shares the copied authoritative aircraft pose.
Control animations consume held pilot commands and cannot send commands.
These controls are visual cues, not clickable systems.

A dedicated 1024×512 SubViewport draws the same native-truth panel onto a
physical 2:1 dashboard surface. TAS/attitude/ellipsoid altitude occupy the top
row; true heading/body yaw rate/kinematic vertical speed the bottom row. Fuel
and held controls remain explicit. Small-window labels reserve the digital
readout space; no unsupported IAS, barometric, magnetic, turn/slip or RPM
indications are added. The 4 key focuses the panel; 1 restores the forward
cockpit. V adds an optional overlay. The top status and fault bar remain
visible when the overlay is hidden. Window minimum is 960×540.

The Tab locator uses the same accepted tangent frame as the synthetic visual
airfield. It plots copied aircraft position and projected nose heading, exact
runway/apron/taxiway bounds, runway-center distance and an offscreen locator.
A near-vertical nose displays unavailable heading. Zoom has a 1–32 km span;
the in-memory trail samples at most once per native second, retains up to
600 points and clears on a new session. This is not a navigation chart,
GPS instrument, progress store or assist. Pause/map/camera changes cannot
alter native flight state. Nothing is uploaded.

Integrated headless checks exercise the actual existing whole-flight loop and
new cockpit pose/readout agreement, all four camera modes, fault delivery
with the overlay hidden, independent tangent projection/heading cases,
near-vertical heading, paused sampling, bounded history, zoom and session
reset. Actual reference-PC viewport inspection covers forward cockpit runway
visibility, panel texture orientation/readability, side-window view, map,
banked flight, menu/help, small cockpit/overlay/panel and full HD, including
a fault display. Initial review found runway markings disappearing with an
overly small camera near plane; retaining 0.1 m restored depth precision
without changing ground geometry or physics.

Reproduce with [the Windows runner](../../../tools/interactive-preview/README.md).
The implementation PR records the exact reviewed source, final editor/export/
rebuilt-DLL package identities, required CI and independent artifact review.
Viewport captures are functional/visual evidence; they do not replace the
deferred long rendering benchmark, real-device exercise or pilot evaluation.

P1/#18, production P2 cockpit/sensor/input acceptance, C172 calibration and
systems, real-airport/navigation fidelity, durable progress and training
qualification remain open.
