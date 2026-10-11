# ADR021: Initial manual overlay mirror feasibility

Status: **proposed scoped rejection under [#192](https://github.com/brettbergin/flight-simulator/issues/192); evidence independently reviewed; checked decision publication pending**. This evaluates one candidate under accepted ADR017/019 and the #179 gaze findings. It defines no accepted UI API or production consumer.

## Decision

Reject the initial whole-horizontal-mirror candidate as a sufficient manual-dock solution. Stop this candidate's campaign after its mandatory960x540 piston PANEL case fails. This is a scoped incompatibility result, not a claim that every manual dock or every deliberate gaze is impossible.

The candidate calls the current presentation layout, then reflects the affected overlay column and opposite status group horizontally. It preserves width, height, y, fonts, complete text, local hits, requested visibility, top native/control strips and camera projection. It adds no menu choice, saved preference, widget API, native behavior or automatic gaze-following layout.

The actual mirrored piston PANEL original at gaze(-1.1,+0.15), FOV58 exposes the airspeed face but still places the unavailable circuit notice at y447..479 and bottom engine feedback at y480..534 across the exposed heading face/readout/caption. Mirroring the full composition does not remove those status-group collisions. Hiding/reflowing them, changing FOV/camera, suppressing requested aids or treating conservative cell bounds as readable ink would test a different candidate.

## Measured domain and limits

The initial triage contains four configurations, each current default plus mirrored counterpart: both original synthetic profiles at960x540, COCKPIT0 gaze(+1.1,+0.15)/FOV72 and PANEL3 gaze(-1.1,+0.15)/FOV58; map open, piston engine expanded, paused tick0. Capture-integrity checks passed:306 checks,8 originals,4 pairs,40 original Variant truth files; exact paired camera/projection/physical-panel, authority/Raw/pointer and source/font/local-hit witnesses. Separate independent review directly inspected all8 originals and passed201 offline evidence checks. It confirmed improvement in both COCKPIT samples and legacy PANEL, but the mandatory piston PANEL collision remains. Neither camera-clipped readings nor improved individual faces become a six-pack readability pass.

1920/2560, recentered controls, map closed, piston collapsed, additional FOV/gaze, retained/unavailable combinations and CHASE alternatives are **UNMEASURED for this candidate**. The earlier540-row #179 sweep measured the existing fixed docks only. No broader three-size/FOV campaign is warranted for this unchanged candidate once a mandatory minimum-window case fails.

The observer used a pinned authoring executable with the unchanged qualified portable PCK. It is not a shipping-executable test or a new package/physics qualification. Actual source remains paused; no Resume, native Run or controls submission occurs. Idle-capture comparisons do not prove modal selection, active-capture retirement, held-button rearm or OS/hardware input behavior.

## Existing and future contracts

ADR019 production geometry, camera/FOV/hide intent and existing widget APIs remain unchanged. No Default/Left/Right control, choice lifetime/reset policy or consumer is authorized by this result. A different candidate needs its own bounded, independently reviewed actual feasibility evidence before an API or consumer is proposed.

If a later feasible candidate advances, ADR017 safety remains mandatory: modal entry retires a real capture exactly once before geometry changes; a subsequent choice must not retire an already-empty capture again. Identical choices and gaze-only frames preserve generation. Real held-button rearm persists until complete Raw observes release and a fresh press. No manufactured up, starter pulse, pilot-intent submission, native tick, implicit pause/Resume or stale gesture is permitted. This triage implements or proves none of those future interactions.

Only #192's scoped feasibility spike may become eligible for closure after independent result review, documentation checks, current required CI and checked publication. Arbitrary-gaze UX, runtime implementation, parent issues, aircraft realism, human/pilot/hardware review and phase gates remain open.

Conditional future ownership, only after a different feasible independently reviewed decision is accepted: `app/simulation/flight_scene.gd` for paused menu/layout; `tests/integration/first_flight/scene_checks.gd` and `tests/integration/input/pointer_engine_scene_checks.gd` for actual capture/modal/Raw and full-authority checks; `tests/integration/first_flight/layout_visual_checks.gd` for bounded original views; affected `tools/interactive-preview/simulation-staging.ps1`, `simulation-staging.test.ps1` and `README.md` for resource closure; `docs/evidence/P2/manual-flight-overlay-dock.md` for consumer evidence. Root owns canonical mapping and package execution. No consumer issue is created by this rejected candidate.

See the [execution and independent original-image evidence](../evidence/P2/manual-flight-overlay-dock-contract.md). This decision supersedes none of ADR019.
