# P4 — Regional navigation and environment

Generated from [roadmap](../roadmap.md) and [backlog](../backlog.json). Consult the [issue index](../issue-index.md) for actual GitHub links.

**Outcome:** a planned regional flight demands navigation, weather/load judgment, and a credible arrival or diversion.

**Deliverables:** dated/redistributable region pipeline; verified KAWO/KPAE/KBFI candidates or documented replacement; terrain/obstacles and airport diagrams within defined scope; runway/taxi metadata; airspace and navigation layers; route/fuel plan; compass/navigation equipment relevant to configuration; wind/pressure/temperature/visibility/cloud presets; crosswind validation; alternate/diversion scenario; day/night progression when lighting and visibility evidence is ready.

**Prerequisites:** P3 complete session/persistence; airport/source approval; position/altitude datum and magnetic/true contracts; environmental model fidelity sufficient for the scenario. Live weather is optional and not a dependency.

**Parallel lanes:** region-data tooling/provenance; airport leaf packages; weather visuals and sound; modeled atmosphere/visibility; map/navigation; cross-country lesson data. A single owner integrates geography/datum contracts and coverage manifests.

**Exit evidence:** one airport-to-airport flight and one supported diversion with consistent planner/cockpit/map/debrief positions; dated airfield/airspace source checks; terrain/runway alignment; demonstrated response to wind, load, density, and visibility changes; offline installed map/data; source terms and coverage gaps visible; performance on the reference PC.

**Gate failures:** decorative terrain represented as complete obstacle coverage, inconsistent altitude datum or magnetic variation, stale data hidden from users, or weather visuals that disagree with the force/visibility model.

**Primary requirements:** PRD-005, PRD-007–008, PRD-014, PRD-019, PRD-022, PRD-031, PRD-034; UX-003, UX-008, UX-014–015.

## Dispatch queue

| Task | Area | Dependencies | Owned paths |
|---|---|---|---|
| [WORLD-PROVENANCE](https://github.com/brettbergin/flight-simulator/issues/38) — Build dated world-pack manifests and ingestion rights audit | world | EPIC-P3, LICENSE-REGISTER | `tools/ingest/`, `schemas/world/`, `content/world/manifests/` |
| [GEODESY](https://github.com/brettbergin/flight-simulator/issues/39) — Implement WGS84/ECEF/NED, vertical datum and magnetic conversions | world | EPIC-P3, CORE-CONTRACTS, WORLD-PROVENANCE | `native/world_core/geodesy/`, `tests/geodesy/` |
| [TERRAIN-STREAMING](https://github.com/brettbergin/flight-simulator/issues/40) — Implement bounded offline terrain tiles, LOD and surface queries | world | EPIC-P3, GEODESY, GROUND-PROOF, WORLD-PROVENANCE | `native/world_core/tiles/`, `app/world/terrain/`, `tools/ingest/terrain/` |
| [REGIONAL-AIRPORTS](https://github.com/brettbergin/flight-simulator/issues/41) — Build dated KAWO, KPAE and KBFI airport operational packs | world | EPIC-P3, WORLD-PROVENANCE, TERRAIN-STREAMING | `content/world/airports/`, `tools/ingest/airports/`, `tests/airports/` |
| [NAV-AVIONICS](https://github.com/brettbergin/flight-simulator/issues/42) — Implement configured COM/NAV, VOR/ILS, transponder and compass | cockpit | EPIC-P3, AIRCRAFT-EVIDENCE, ELECTRICAL-SENSORS, GEODESY, WORLD-PROVENANCE | `native/sim_core/avionics/`, `app/cockpit/avionics/`, `tests/nav/` |
| [MAP-ROUTES](https://github.com/brettbergin/flight-simulator/issues/43) — Implement route planner, map layers and offline cross-country preparation | ui | EPIC-P3, REGIONAL-AIRPORTS, NAV-AVIONICS, FLIGHT-PLANNING | `app/ui/map/`, `native/world_core/routes/`, `tests/planning/routes/` |
| [WEATHER-PROFILES](https://github.com/brettbergin/flight-simulator/issues/44) — Implement offline atmosphere, winds, pressure and weather presets | weather | EPIC-P3, CORE-CONTRACTS, WORLD-PROVENANCE | `native/sim_core/weather/`, `content/weather/`, `tests/weather/` |
| [GUSTS-TURBULENCE](https://github.com/brettbergin/flight-simulator/issues/45) — Implement reproducible spatial gusts, turbulence and bounded shear | weather | EPIC-P3, WEATHER-PROFILES, FDM-HARNESS | `native/sim_core/weather/turbulence/`, `tests/weather/turbulence/` |
| [LIGHT-VISIBILITY](https://github.com/brettbergin/flight-simulator/issues/46) — Implement daylight/night, clouds, visibility and airport lighting | weather | EPIC-P3, TERRAIN-STREAMING, WEATHER-PROFILES, RENDER-PROOF | `app/world/sky/`, `app/world/lighting/`, `tests/render/` |
| [REGIONAL-FLIGHT](https://github.com/brettbergin/flight-simulator/issues/47) — Validate offline regional cross-country, diversion and return | validation | EPIC-P3, REGIONAL-AIRPORTS, MAP-ROUTES, GUSTS-TURBULENCE, LIGHT-VISIBILITY | `content/scenarios/regional/`, `tests/scenarios/regional/`, `docs/evidence/P4/` |

## Agent handoff

Use the canonical issue acceptance/evidence fields. Claim one task with an isolated branch/worktree; coordinate shared paths before editing. Publish interface changes first, then consumers. Record build/content/source versions, test outputs, unresolved gaps and human-review status in the PR. Prepare `docs/evidence/P4/` gate report only after the integrated scenario is actually run. The integrator changes dependency status labels; agents do not self-certify human pilot or owner review.
