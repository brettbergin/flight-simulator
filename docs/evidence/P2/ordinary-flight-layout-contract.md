# Ordinary-flight overlay layout contract preparation

Status: proposed documentation contract for [#177](https://github.com/brettbergin/flight-simulator/issues/177). [ADR019](../../decisions/019-ordinary-flight-overlay-layout.md) freezes the proposed presentation decision; consumer [#178](https://github.com/brettbergin/flight-simulator/issues/178) and [changed-gaze design #179](https://github.com/brettbergin/flight-simulator/issues/179) remain separate. No renderer, human or phase acceptance is recorded here.

## Preparatory observations

Godot4.7.2 standalone headless probes measured actual fallback-font bounds and production-default camera projection, without instantiating the flight consumer/native runtime. The corrected typography/marker probe passed76 checks: it accounts for the full103-wide requested-circle/actual-line footprint and complete native formatter rollover `-10.00e307`. Result SHA256 `f1d41fa3091f0863925a375bd8b01996237b01a857b701b0ec22ec96619746cd`.

The selected release-layout matrix contains468 offline fixed-region/font-allocation cases and12,654 passing arithmetic checks at960x540/1920x1080/2560x1440. It includes legacy/collapsed/help-off and current/noncurrent/open/closed-map states. Matrix SHA256 `00803091ca1c9f0c6e68d85041c64e74a55c02372babdfe84ecc07c3be9813bb`. These are not468 rendered images or actual interaction trials. Source-supported examples are not exhaustive finite formatter or OS key-name coverage. Raw preparatory artifacts are coordinator-retained review inputs; their hashes identify the observations without claiming a published runtime test suite.

The unchanged retained native strip y84..118 intersects conservative PANEL cell2 bounds at960 for both profiles. Those full source-cell rectangles include blank space around a round dial; neither actual dial-ink occlusion nor clearance follows from the intersection. It remains an explicit consumer glyph/pixel check. Added full noncurrent-summary composition, current chart annotations, simultaneous captured-look/button-rearm status, actual pointer events and composed release strings remain unproven by these preparation checks. Changed-gaze exposed-face collisions are a separate named follow-up, independent of camera clipping.

## Contract acceptance checklist

- [x] Concrete geometry, exact feedback setter and separate summary admission/accessor drafted; native/current-geography authority and legitimate null/noncurrent values preserved.
- [x] Fixed release location specified for legacy, collapsed engine and Help off, using measured font10 ascent11/descent3 in14 pixels.
- [x] Preparatory76-check typography and468-case fixed-region calculations retained with their limitations.
- [ ] Review this exact public ADR/evidence/ADR018 amendment and final issue bindings independently.
- [x] Confirm accepted named prerequisites and publish the canonical three-leaf dependency/ownership mapping without changing the110 prior objects. Grouped first-flight PR174 merged as `6286e4e5c2921bcbead553ad88eba4bd794ba0df` after all eight checks; #166/#167 are closed. New #177/#178/#179 have copyable agent prompts.
- [x] Local documentation/generated-plan checks pass for113 issues,36 labels and147 requirements; all14 unchanged schema definitions and11 contract tests pass.
- [ ] Current required hosted CI passes on the exact contract PR.
- [ ] Merge the contract and record its accepted commit/review identity before consumer dispatch.

## Consumer acceptance remains pending

- [ ] Implement only accepted presentation seams within issue-owned paths, including CircuitGuide and its scenario tests; preserve complete copies, original route ownership and current geographic admission.
- [ ] Actual composed glyph/hit/marker bounds and source-supported formatting/status/remap negatives across both profiles, three sizes/modes and all specified states.
- [ ] Actual full Raw pointer/control admission, bound conflicts, starter release/cancel, idempotent layout and real capture retirement; no fabricated release or native mutation.
- [ ] Original GPU pixels: all six default exposed primary faces/requested CHASE readings, native/status/wind/source labels, full target/count/metrics/footer, complete fixed schematic and release access. Resolve retained-strip warning using actual ink.
- [ ] Actual open/close/restore map and engine-collapse interactions, ordinary controlled exported flight and cold paused/explicit Resume regression, with full authority/resource receipts.
- [ ] Fresh editor/export/rebuilt-library source/PCK/native/package closure and current protected hosted CI.
- [ ] Record human/pilot/hardware/performance/listening and phase gates separately; this contract satisfies none of them.
