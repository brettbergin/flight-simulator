# P7 — Windows release and pilot acceptance

Generated from [roadmap](../roadmap.md) and [backlog](../backlog.json). Consult the [issue index](../issue-index.md) for actual GitHub links.

**Outcome:** a downloadable build reliably supports its declared flying/practice scope on the reference machine.

**Deliverables:** release automation; full packaged dependency/license manifest; clean-machine launch checks; checksums; release notes and known fidelity gaps; final performance/settings matrix; save compatibility report; accessibility/usability review; regression scenario pack; crash recovery/offline verification; pilot evaluation report with resolved critical findings. Broader minimum specifications are published only after tests on additional hardware.

**Prerequisites:** accepted P6 scoped features, or explicit documented release scope selecting a narrower earlier-phase build. Every included feature has evidence; postponement does not erase its requirement.

**Parallel lanes:** regression/reliability; visual/readability QA; license/source audit; performance/scenery settings; pilot session preparation; release packaging. Integrator freezes core/content versions and owns the release candidate.

**Exit evidence:** clean Windows user profile/download/archive run without developer environment; installed offline full flight/save/debrief; migration/interruption recovery; repeatable package/build manifest; tests and pilot feedback linked to exact artifact; critical safety/content contradictions resolved or removed from supported scope; provisional 2560×1440 default-quality reference-PC target assessed over a ten-minute representative warm run (average ≥60 fps, p95 frame time ≤20 ms, p99 ≤33 ms), with simulation tick behavior measured independently; instrument readability at 1080p/1440p plus captured smaller window dimensions reviewed; tag/release approved under repository delivery policy. No general minimum-spec claim follows from testing this one PC.

**Gate failures:** DLL dependence on development machine, hidden release permissions/secrets, unusable update/downgrade, missing licenses, significant flight/instrument discrepancies, or publishing realism claims beyond evidence.

**Primary requirements:** PRD-017–020, PRD-026–034; UX-001, UX-009, UX-012–022, UX-028.

## Dispatch queue

| Task | Area | Dependencies | Owned paths |
|---|---|---|---|
| [WINDOWS-PACKAGING](https://github.com/brettbergin/flight-simulator/issues/61) — Build clean Windows ZIP delivery and simulator release workflow | delivery | EPIC-P6, NATIVE-EXPORT, REALISM-REPORT | `tools/package/`, `.github/workflows/simulator-release.yml`, `tests/install/` |
| [SAVE-UPGRADE](https://github.com/brettbergin/flight-simulator/issues/62) — Validate upgrade, rollback, incompatible saves and crash recovery | persistence | EPIC-P6, WINDOWS-PACKAGING, LOCAL-PERSISTENCE, REPLAY-RESUME | `tests/persistence/upgrade/`, `tools/package/`, `docs/evidence/P7/` |
| [REFERENCE-PERFORMANCE](https://github.com/brettbergin/flight-simulator/issues/63) — Measure reference-PC frame pacing, memory, latency and loading | validation | EPIC-P6, WINDOWS-PACKAGING, LIGHT-VISIBILITY | `tools/benchmark/`, `docs/evidence/P7/performance/` |
| [ACCESSIBILITY-QA](https://github.com/brettbergin/flight-simulator/issues/64) — Validate readable cockpit, UI focus, captions and comfort settings | ui | EPIC-P6, WINDOWS-PACKAGING, HUD-CAMERA, FLIGHT-AUDIO | `tests/ui/accessibility/`, `app/ui/`, `docs/evidence/P7/accessibility/` |
| [CONTROLLER-QA](https://github.com/brettbergin/flight-simulator/issues/65) — Validate hardware calibration, reconnect and first-run defaults | input | EPIC-P6, WINDOWS-PACKAGING, INPUT-PROFILES | `tests/input/hardware/`, `app/input/`, `docs/evidence/P7/controls/` |
| [CONTENT-SECURITY](https://github.com/brettbergin/flight-simulator/issues/66) — Harden content/save/replay parsing and optional crash reporting | security | EPIC-P6, WORLD-PROVENANCE, LOCAL-PERSISTENCE, WINDOWS-PACKAGING | `native/content/`, `native/persistence/`, `tests/security/`, `app/ui/privacy/` |
| [SOAK-STABILITY](https://github.com/brettbergin/flight-simulator/issues/67) — Run extended flights, reset/reload loops and failure recovery soak | validation | EPIC-P6, SAVE-UPGRADE, REFERENCE-PERFORMANCE, CONTENT-SECURITY | `tests/soak/`, `tools/soak/`, `docs/evidence/P7/stability/` |
| [PILOT-ACCEPTANCE](https://github.com/brettbergin/flight-simulator/issues/68) — Complete returning-pilot feedback and qualified instruction acceptance | validation | EPIC-P6, SOAK-STABILITY, ACCESSIBILITY-QA, CONTROLLER-QA, REALISM-REPORT | `docs/evidence/P7/pilot/`, `docs/lesson-review/` |
| [RELEASE-CANDIDATE](https://github.com/brettbergin/flight-simulator/issues/69) — Ratify release evidence, signing decision and publish first simulator alpha | delivery | EPIC-P6, PILOT-ACCEPTANCE, WINDOWS-PACKAGING | `docs/releases/`, `CHANGELOG.md`, `tools/package/` |

## Agent handoff

Use the canonical issue acceptance/evidence fields. Claim one task with an isolated branch/worktree; coordinate shared paths before editing. Publish interface changes first, then consumers. Record build/content/source versions, test outputs, unresolved gaps and human-review status in the PR. Prepare `docs/evidence/P7/` gate report only after the integrated scenario is actually run. The integrator changes dependency status labels; agents do not self-certify human pilot or owner review.
