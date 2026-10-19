# ADR028: KAWO source normalization before physical environment integration

Status: proposed under [#243](https://github.com/brettbergin/flight-simulator/issues/243),
2026-10-18. The owner prioritized airports and environments after the Players
flight-menu UI checks. Existing phase and aircraft/pilot gates remain open.

The present world is synthetic: its rendered scenery sits over an analytic native
contact plane. A recognizable geographic airport needs sourced runway geometry,
terrain, matching physical contact and an explicit world/start identity. Renaming
that synthetic plane cannot supply those properties.

Accept the complete [source interchange](../contracts/world/airport-source-v1.md)
as the first bounded seam. It preserves exact source provenance, datum uncertainty,
unknown displacement/distances and conflicts without creating canonical terrain
or native state. The initial geographic target remains KAWO; KPAE/KBFI follow as
separate packs. [Discovery evidence](../evidence/P4/kawo-source-discovery.md) records
actual input hashes and remaining datum/lineage gaps.

Ingestion consumers wait for this checked source contract. A separate checked
contract must freeze the exact physical/render terrain representation, datum
transformation, resident readiness, coverage behavior and native/facade/history
admission before runtime consumers. The current synthetic world, source identities,
recordings and saves retain their existing meanings. WorldPackage/v1 and the
fourteen-boundary registry remain unchanged.

This split permits useful source work while numerical surface details are reviewed.
It does not waive original parent dependencies, admit a terrain implementation,
certify operational data or close #243. Future leaves need distinct ownership,
independent geometry/datum expectations and full integrated circuit/delivery
evidence. Source records labelled cross-checked establish metadata consistency,
not survey accuracy, aircraft fidelity or pilot acceptance.

The next bounded seam is the [immutable resident-grid core](../contracts/world/resident-grid-core-v1.md).
After its checked acceptance and independently frozen numerical references, a
standalone native component may implement that provider and its headless tests.
This intentionally precedes the file codec/compiler and geographic/runtime
admission seams: those consumers still wait for their own complete contracts.
Exact cells, triangles, material classification, missing support and pure rectangle
coverage are fixed here; a rectangle query supplies no native motion theorem.
The separate [offline tool pins](../contracts/world/terrain-tools-v1.md) permit a
local authoring bootstrap only after checked acceptance. They do not choose a
geographic transform or expand native/runtime packaging.
