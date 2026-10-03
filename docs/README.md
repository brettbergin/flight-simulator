# Flight simulator project plan

This is a serious Windows desktop flight simulator for realistic Cessna flying, thoughtful practice, and enjoyment by an experienced pilot. The first delivery establishes the implementation plan and GitHub work queue. It does not contain a playable simulator. The owner will review this plan before the implementation fleet begins.

## Decisions made for this project

| Decision | Initial choice |
|---|---|
| Runtime | Windows 11 x64; desktop first, VR later |
| Reference PC | i9-12900K, RTX3090, approximately 64 GB RAM; measured performance gate on this machine |
| First aircraft | Explicit C172S fuel-injected conventional-panel target; variant/serial/POH provenance gate; generic models remain labeled prototypes |
| Stack | Godot 4 Forward+ presentation, C++20 native core, JSBSim flight dynamics, SQLite persistence, Python offline data tools |
| Engine account | Owner selected Godot for account-free authoring using its direct download |
| Scope | Offline single-player; synthetic validation airfield followed by dated north Puget Sound region |
| Operations | US/FAA reference lessons first; jurisdiction-neutral core and future jurisdiction packs |
| Controls | Keyboard/mouse and gamepad initially; calibrated yoke/throttle/pedals are core design requirements |
| Business/cost | Public open-source foundation; zero mandatory subscriptions, locally stored profiles |
| Distribution | GitHub Releases; documentation prereleases now, Windows simulator packages after proof gates |
| Realism proof | Reference comparisons, repeatable telemetry, pilot evaluations, and explicitly visible limits |

The central design choice is to prove flight-model accuracy and native integration before building a large world or collecting achievements. Complete aircraft configuration, airport source dates, assist settings, and training rubric versions travel with each recorded session.

## Read in this order

1. [Product scope and requirements](product.md): expected pilot experience and initial boundaries.
2. [Roadmap and iteration gates](roadmap.md) and [individual phase dispatch briefs](phases/README.md): what gets built first and what evidence unlocks the next phase.
3. [Architecture](architecture.md) and [contracts](contracts.md): stack, components, units, ownership, persistence, and extension boundaries.
4. [Aircraft realism and validation](realism-and-validation.md), [training and safety](training-and-safety.md), and [world/data](world-and-data.md): evidence and operational behavior.
5. [Cockpit, HUD, progress, and accessibility](experience-and-progress.md): presentation and learning experience.
6. [Agent execution](agent-operations.md), [copyable issue prompts](agent-prompts.md), and [CI/releases](delivery.md): how a fleet can deliver reviewable work.
7. [Backlog guide](backlog.md), [GitHub issue index](issue-index.md), [requirement traceability](requirements.md), [risks](risks.md), and [source register](sources.md).

## Review focus

Review the aircraft target, desktop/offline priorities, regional scope, phase gates, and what first meaningful flying will include. Budget defaults avoid paid tools and services. Technical unknowns have early proof tasks and fallback decisions. Phase targets are not promised dates. [The owner-review issue](https://github.com/brettbergin/flight-simulator/issues/10) must close before implementation starts.

Simulator practice is recorded as practice. Formal training/device approval and jurisdiction-specific license credit have their own regulatory and instructor requirements; this project has not established those. The plan supports transfer of useful habits through evidence-reviewed scenarios and makes prototype limits visible.

## Current automation

Run `node tools/check-docs.mjs` to validate local documentation/backlog consistency. `node tools/sync-github.mjs` previews the issue plan. Apply is explicit and described in [backlog.md](backlog.md). GitHub's two-platform foundation checks are real automation; native/game build checks are tracked implementation work.
