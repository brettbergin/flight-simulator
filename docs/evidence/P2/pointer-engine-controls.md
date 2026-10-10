# Pointer-operated original engine controls

Date: 2026-10-10. Implementation evidence for [#158](https://github.com/brettbergin/flight-simulator/issues/158), partial #21/#23, REAL-019/021, PRD-015/017/020 and UX-009–013. Consumes accepted [ADR017](../../decisions/017-frontend-pointer-engine-controls.md) and the [qualified original piston player](../P3/original-piston-player.md). This is an original prototype interaction, without a C172 procedure or aircraft qualification claim.

## Behavior and authority

The optional engine controls expand from a compact caption. Primary-left drags throttle/mixture; desired-value buttons operate ignition and fuel feed; starter is held momentarily. Cyan shows actual native state, gold successfully sampled mapper intent, and orange local queued preview. Releasing starter changes its pending preview to OFF, without repainting actual or sampled values. Paused controls require explicit Resume. Collapsing the controls restores the unobstructed view.

The existing mapper alone owns pilot intent. The panel cannot call the facade or native simulation. Complete Raw input and pinned device validity are checked before sampled mutation; conflicting bindings pause before a flight action or Run. Fixed levers remain disabled. Mouse-look release exposes the pointer without changing the camera. Focus, modal, widget, profile and session transitions retire capture; observed physical button release is required before rearm. Actual paused starter=true remains visible until the facade admits recovery release.

The engine/model, nine instrument formulas, native command ordering, preset formats and assist provenance are unchanged. Pointer capture is transient and is not saved.

## Development evidence

The frozen prospective mapper passed 347 pointer checks alongside the existing legacy/reference/piston fixtures. The final integrated public host and panel passed 671 actual Windows assertions: 268 host and 403 panel checks, with actual mouse capture observed. Separate complete synthetic Raw accompanies real viewport GUI events; this does not establish physical controller or pilot acceptance.

Two combined package attempts passed mapper, host and all 118,618 flight assertions, but failed compact tooltip checks. The first prompted a useful correction: tooltip text now updates synchronously with UI state, and two additional assertions require correct guidance before drawing. The second attempt still failed those checks. Isolated comparisons then identified the test setup: the retained failing runs started with a 64×64 headless viewport, outside the panel's hover coordinates. Running the host first had enlarged the viewport and concealed this dependency. The panel fixture must establish and verify its own viewport, then restore the previous size. Both failed package attempts remain retained and are not accepted delivery evidence.

A prospective pointer-operated native lifecycle passed 118,618 assertions over 13,321 complete command/publication rows. It covers the unchanged 111-second startup, run-up, taxi, held-brake stop and mixture-cutoff/coast schedule, plus explicit post-shutdown feed/ignition cleanup. The original frozen limits are unchanged. GUI lever coordinates are retained exactly rather than snapped to reference literals. Malformed Raw and a bound primary-button gesture prove no submission or Run. This private trial precedes the final public package and is not its acceptance evidence.

The first lifecycle trial failed exact command comparison because the native JSON parser represents schema_version as float1.0 and the expected fixture used int1. The retained full rows show no other command difference or physical-limit failure. The repaired fixture preserves strict equality and uses the already established parser representation; the failed receipt remains retained.

Independent review inspected all 48 original prospective Windows captures at 960×540, 1080p and 1440p in all four camera modes. Source/pixel review hash: `72cca8c094eb1f80fe1a9c560ebc11ac2c0e52e0ebbbc95e898aa514a6dd833c`. Actual/requested values remain unchanged during an unsampled mixture preview. Expanded controls at 960 can cover the physical right engine column or part of the outside aircraft/horizon; all six flight dials and native summary strips remain visible, and collapse restores the view. Full long binding guidance remains available in the tooltip.

The public observer adds six bounded fixed/conflicting/remapped-look views, records full binary before/after truth including panel data, and compares exact Variant bytes across each view sequence. View-only trials isolate external focus/device callbacks; separate host fixtures exercise their production behavior. Captures after two complete draws do not observe every operating-system presentation.

## Frozen Windows delivery

The final qualification froze source commit `587f5256df967279622658a4ca411e788565993b`. Retained run `run-79b5aa74a6e74164be6e6c8deca7e89f` completed successfully. Its manifest SHA-256 is `ce99969d4822f18aef1afc5334efcaecc86246dbe4e177454ce2dad514bcffaf`; package audit is `8a7adf918383a301e4462c94a3b55e2232a3031354d419b0124f1bda0e4c2f0a`. After merging accepted cockpit main, all 198 authoring sources still match the frozen manifest byte for byte. The later documentation/merge commits do not change or relabel the qualification's source identity.

Each of editor, portable Windows and independently rebuilt-library contexts passed 119,635 separately identified pointer assertions: 347 mapper, 403 panel, 267 headless production-host and 118,618 flight checks. Each retained full trace has 13,321 rows and 16 exact commands. Existing facade checks (41,961), cold-piston checks (15,914), ground materials, native identity, dependency/module checks, clean import/export, package validation and corresponding-source/rights closure also passed. The four pointer groups are mandatory for this coupled package and retain their own bounded receipt plus hash-bound external full trace; historical facade and piston receipts remain separate.

| Context | Pointer receipt SHA-256 | Full trace SHA-256 |
|---|---|---|
| Editor | `27b70b407bdb9bb0c2a2c8886f7a03e0828854ee65625db4d3506b20ca528c4c` | `926daf3c3010a22a4b2d3052e3b423ef4ba6cea6d5bbce6ff0b3702c29e07b8c` |
| Portable | `e6ccdbaa30978761e3ced72ddb3899d8d9a59fa1c260f560f4575c4fdb3bd345` | `dbe81cefd954a58ca5e93850d68ee23938166fd9de334edad58e79f6bcaa4fe9` |
| Rebuilt library | `8bf76bfc954ce67693cc634f4eff247fed0339486df8907c6c66198ccb2f01be` | `7c4a42c4f69dce4b09c25efe361e180ac0c0052599df425073143a23c6dc4636` |

Independent final source/package review `af959934aef906d21c380a6b6dcc53b786ae41c901d7427125efa8bfe6db7b20` checked the cumulative mapper/panel/host/tool changes, all three full traces, immutable native/model contracts and actual package contents. The final distribution contains 469 payload files and 405 corresponding-source files. Its 474 license-component file occurrences describe 469 unique files; the five shared attribution paths have identical content. Earlier replacement checks precede final distribution assembly; the separate final GPU replacement trial instead copies the complete final payload and replaces only the two JSBSim DLLs.

Fresh Windows Compatibility/RTX3090 captures ran serially in all three final contexts, each with 54 PNGs and 108 full before/after binary truth files. They cover live collapsed, live expanded, unsampled pending mixture, paused, fixed controls, conflicting primary bindings and remapped look at 960×540, 1920×1080 and 2560×1440. All processes exited successfully, package originals remained unchanged, and copied-runtime/source/native/model/rights closure passed. Receipt SHA-256 values:

- Editor: `f09a3c74483eac7c04a5145acd46eb89947d6062139504176bf56bda448e7b72`.
- Portable: `a4a92cf5a85b137cfb8355d9b710d1f5f90c834b306b432ec1f5c4df09cd26b5`.
- Rebuilt library: `3c049f869e84b4bd0725246b0f9bdb7cbb13a15a4ef0d32a4c830b336c9a0819`.

Independent final saved-pixel review `1e465874672ef3da1817f16dda2e885583b818620d0aa67b64eac9b36a611778` accepted the three-context artifacts with retained layout limits. All 162 actual PNGs matched the 54 previously individually inspected originals byte for byte; nine current originals were additionally opened. The reviewer checked all 324 full binary truth files, before/after byte equality, 21 sequence comparisons, actual dimensions, 14 source/resource pins per context and copied-runtime closure. This review targets the frozen source/campaign, not an inferred later Git head. The known expanded-panel occlusion and small binding text at 960 remain visible and documented; collapse clears the occlusion and full guidance is available through the tooltip. These bounded captures do not measure every OS presentation or establish a frame-time budget.

## Remaining gates

### Standalone Windows CI preflight correction

The first PR164 Windows native job failed in its standalone input preflight: the new mapper imports `wire_validation.gd`, which imports `uint64.gd`, but this small fixture project staged neither file. Retained job `114275102766` and its uploaded editor log identify the missing resource. The complete qualified player already stages both dependencies. The correction adds exactly those two source mappings to `tools/input-controls/check.py`; it changes no runtime code, assertion, fixture or acceptance threshold. All 198 qualified authoring sources remain byte-identical.

The corrected local Windows preflight `536d2ea2097b4a1c926156a8de35a6d1` completed import, editor, export and portable execution successfully, with all 310 existing input assertions passing in each runtime. Its six staged source identities and clean logs are retained separately from the full player qualification. Current hosted checks must rerun on the corrected PR head; the earlier failing hosted result is not treated as a pass.

Current protected checks and final evidence review must pass before merge. Owner feedback, physical hardware/listening/pilot review, source-supported C172 applicability and P1/P2/P3 acceptance remain open; this leaf cannot close broad #21/#23. The controls are qualified frontend interactions with the unchanged original model, not an aircraft procedure or training-credit claim.
