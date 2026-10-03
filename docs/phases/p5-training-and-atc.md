# P5 — Lessons, ATC, and debrief

Generated from [roadmap](../roadmap.md) and [backlog](../backlog.json). Consult the [issue index](../issue-index.md) for actual GitHub links.

**Outcome:** a repeatable curriculum helps users improve supported procedures and decisions without hiding simulator limitations.

**Deliverables:** lesson schema/evaluators; progressive basic curriculum; checklists and decision scenarios; deterministic towered/untowered communications; taxi/runway clearance state; basic traffic for scenario interactions with declared coverage; expanded debrief timeline/graphs/bookmarks; assistance provenance; idempotent achievements; review export; pilot/qualified instructional review where appropriate.

**Prerequisites:** P4 region, flight phases, and navigation data; accepted event/evaluator/persistence contracts. A few introductory P3 lessons may exist earlier, but a curriculum claim awaits systematic review.

**Parallel lanes:** content authors work one lesson family per issue; evaluator owner implements shared rules; ATC owner handles communication authority/context; debrief/achievement owners consume stable events. Human review is a scheduled gate, not a task agents can self-certify.

**Exit evidence:** same scenario produces consistent events; clearance and phase transitions are tested for misuse; radio content sources reviewed; appropriate go-around/cancellation/diversion recognized; unsupported scan/inspection/judgment marked unevaluated; resumed/replayed awards cannot duplicate; assistance and earlier evaluator versions remain visible; pilot can replay and explain a meaningful event.

**Gate failures:** open-ended generated instruction presented as authoritative, ATC contradictions, high scores masking material events, unsafe achievement incentives, or evaluator claims beyond observed evidence.

**Primary requirements:** PRD-011–014, PRD-021–023, PRD-025–030; UX-006, UX-021–028.

## Dispatch queue

| Task | Area | Dependencies | Owned paths |
|---|---|---|---|
| [LESSON-CURRICULUM](https://github.com/brettbergin/flight-simulator/issues/48) — Create versioned FAA-reference beginner and returning-pilot lessons | training | EPIC-P4, PREFLIGHT-CHECKLISTS, REGIONAL-FLIGHT | `content/lessons/`, `content/jurisdictions/us/`, `docs/lesson-review/` |
| [TRAINING-EVALUATOR](https://github.com/brettbergin/flight-simulator/issues/49) — Implement reproducible objectives, intervention policy and safe scoring | training | EPIC-P4, LESSON-CURRICULUM, ASSIST-PROFILES, REPLAY-RESUME | `native/training/`, `schemas/rubrics/`, `tests/training/` |
| [ATC-RADIO](https://github.com/brettbergin/flight-simulator/issues/50) — Implement deterministic ATC/CTAF phraseology and clearance state | atc | EPIC-P4, REGIONAL-AIRPORTS, NAV-AVIONICS, LESSON-CURRICULUM | `native/atc/`, `content/atc/`, `app/ui/radio/`, `tests/atc/` |
| [AI-TRAFFIC](https://github.com/brettbergin/flight-simulator/issues/51) — Implement seeded pattern/ground traffic and separation encounters | atc | EPIC-P4, ATC-RADIO, WEATHER-PROFILES | `native/traffic/`, `content/traffic/`, `tests/traffic/` |
| [DEBRIEF](https://github.com/brettbergin/flight-simulator/issues/52) — Build timeline/map/replay debrief tied to objective observations | ui | EPIC-P4, TRAINING-EVALUATOR, ATC-RADIO, AI-TRAFFIC, BASIC-DEBRIEF | `app/ui/debrief/`, `app/replay/`, `tests/debrief/` |
| [ACHIEVEMENTS](https://github.com/brettbergin/flight-simulator/issues/53) — Implement honest practice history, goals and safe achievements | training | EPIC-P4, TRAINING-EVALUATOR, LOCAL-PERSISTENCE, DEBRIEF | `native/progress/`, `content/achievements/`, `app/ui/progress/`, `tests/progress/` |
| [INSTRUCTOR-TOOLS](https://github.com/brettbergin/flight-simulator/issues/54) — Implement local instructor controls and qualified curriculum review gate | training | EPIC-P4, DEBRIEF, ACHIEVEMENTS | `app/ui/instructor/`, `content/instructor-presets/`, `docs/evidence/P5/` |

## Agent handoff

Use the canonical issue acceptance/evidence fields. Claim one task with an isolated branch/worktree; coordinate shared paths before editing. Publish interface changes first, then consumers. Record build/content/source versions, test outputs, unresolved gaps and human-review status in the PR. Prepare `docs/evidence/P5/` gate report only after the integrated scenario is actually run. The integrator changes dependency status labels; agents do not self-certify human pilot or owner review.
