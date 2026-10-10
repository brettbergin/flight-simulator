# Pointer-operated original engine controls

Date: 2026-10-10. Integration evidence in preparation for [#158](https://github.com/brettbergin/flight-simulator/issues/158), partial #21/#23, REAL-019/021, PRD-015/017/020 and UX-009–013. Consumes accepted [ADR017](../../decisions/017-frontend-pointer-engine-controls.md) and the [qualified original piston player](../P3/original-piston-player.md). This is an original prototype interaction, without a C172 procedure or aircraft qualification claim.

## Behavior and authority

The optional engine controls expand from a compact caption. Primary-left drags throttle/mixture; desired-value buttons operate ignition and fuel feed; starter is held momentarily. Cyan shows actual native state, gold successfully sampled mapper intent, and orange local queued preview. Releasing starter changes its pending preview to OFF, without repainting actual or sampled values. Paused controls require explicit Resume. Collapsing the controls restores the unobstructed view.

The existing mapper alone owns pilot intent. The panel cannot call the facade or native simulation. Complete Raw input and pinned device validity are checked before sampled mutation; conflicting bindings pause before a flight action or Run. Fixed levers remain disabled. Mouse-look release exposes the pointer without changing the camera. Focus, modal, widget, profile and session transitions retire capture; observed physical button release is required before rearm. Actual paused starter=true remains visible until the facade admits recovery release.

The engine/model, nine instrument formulas, native command ordering, preset formats and assist provenance are unchanged. Pointer capture is transient and is not saved.

## Development evidence

The frozen prospective mapper passed 347 pointer checks alongside the existing legacy/reference/piston fixtures. The integrated public host and panel passed 667 actual Windows assertions: 268 host and 399 panel checks, with actual mouse capture observed. Separate complete synthetic Raw accompanies real viewport GUI events; this does not establish physical controller or pilot acceptance.

The first combined package attempt passed mapper, host and all 118,618 flight assertions, but failed two compact tooltip checks. Guidance depended on a drawing callback. The correction updates tooltip text synchronously with UI state, keeping drawing free of that mutation. Two additional assertions require correct hover guidance before any draw. The corrected focused headless host/panel fixture passes668 checks (267 host and401 panel); the failed package attempt remains retained and is not accepted delivery evidence.

A prospective pointer-operated native lifecycle passed 118,618 assertions over 13,321 complete command/publication rows. It covers the unchanged 111-second startup, run-up, taxi, held-brake stop and mixture-cutoff/coast schedule, plus explicit post-shutdown feed/ignition cleanup. The original frozen limits are unchanged. GUI lever coordinates are retained exactly rather than snapped to reference literals. Malformed Raw and a bound primary-button gesture prove no submission or Run. This private trial precedes the final public package and is not its acceptance evidence.

The first lifecycle trial failed exact command comparison because the native JSON parser represents schema_version as float1.0 and the expected fixture used int1. The retained full rows show no other command difference or physical-limit failure. The repaired fixture preserves strict equality and uses the already established parser representation; the failed receipt remains retained.

Independent review inspected all 48 original prospective Windows captures at 960×540, 1080p and 1440p in all four camera modes. Source/pixel review hash: `72cca8c094eb1f80fe1a9c560ebc11ac2c0e52e0ebbbc95e898aa514a6dd833c`. Actual/requested values remain unchanged during an unsampled mixture preview. Expanded controls at 960 can cover the physical right engine column or part of the outside aircraft/horizon; all six flight dials and native summary strips remain visible, and collapse restores the view. Full long binding guidance remains available in the tooltip.

The public observer adds six bounded fixed/conflicting/remapped-look views, records full binary before/after truth including panel data, and compares exact Variant bytes across each view sequence. View-only trials isolate external focus/device callbacks; separate host fixtures exercise their production behavior. Captures after two complete draws do not observe every operating-system presentation.

## Remaining delivery gates

Final frozen editor, portable and independently rebuilt-library checks, package/source/model/module/rights closure and independent exported pixels remain pending. New pointer receipts must be separately identifiable, retain full lifecycle traces, and fail closed when any mandatory group or source binding is missing. Current protected checks must pass before a reviewed PR merge. Owner feedback, hardware/listening/pilot review, source-supported C172 applicability and P1/P2/P3 acceptance remain open; this leaf cannot close broad #21/#23.
