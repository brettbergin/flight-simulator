# ADR-005: Versioned data packages and capability-based aircraft expansion

Date: 2026-10-03. Status: accepted for planning; initial runtime trusts reviewed first-party content only.

## Context

The user wants Cessna-class aircraft initially and room for other types later. Different variants have different engines, systems, performance, instruments, checklists, and limitations. Scenery and aircraft downloads can also carry unclear rights, stale navdata, or executable scripts. Parallel agents require one authoritative contract rather than unstructured assets and property strings.

## Decision

Define versioned JSON-schema manifests for aircraft, world packages, scenarios, snapshots, commands, events, replay headers, and checkpoints before P2 parallel feature work. Runtime aircraft capabilities declare the exact implemented/configured engine, fuel, gear, electrical, avionics, instrument, and failure support. Cockpit controls, lessons, and checklists bind to those capabilities. New aircraft introduce reviewed package data and any tested adapter/system extensions; they do not clone the whole app or rely on scattered aircraft-name branches.

Every package records content hashes, schema compatibility, source provenance/licenses, target applicability, source dates/cycles, datums, and implemented/approximated/unsupported behaviors. Authored visual assets use a reproducible Blender-to-GLB pipeline. GIS/navdata imports are build/update processes producing immutable runtime tiles/catalogs. Bound runtime file sizes, XML interpretation, expressions, and paths. Pin sources/converters rather than silently downloading current data during a lesson.

Initial first-party packages carry data and audited JSBSim configuration, meshes, textures, sound, navigation/terrain data, and scenario declarations. Community packs remain disabled until validation exists. Reject downloaded executable DLLs, GDScript/Python, scripted Godot scenes, SQL extensions, external entity/file/network references, and unsupported JSBSim runtime facilities. New trusted native code ships through reviewed application releases.

Underlying open tooling does not grant blanket rights to aircraft or scenery. FlightGear's GPL and add-on policy, for example, require attention when copying its aircraft components; those files cannot simply be marked as our MIT assets. [FlightGear license](https://www.flightgear.org/about/license/), [official add-on FAQ](https://wiki.flightgear.org/FG_Add-on_FAQ).

## Alternatives

Aircraft-specific code copies create drift across variants and complicate validation. Arbitrary executable plug-ins enable flexible features but add a security, distribution, versioning, and reproducibility burden before an extension API is mature. Unversioned live source data makes scenario replay and airport validation unstable. Global imagery streaming spends early effort and recurring cost outside the first training-region outcome.

## Consequences and gates

Packages may only use capabilities that the runtime and evaluator recognize; unknown major schemas fail with clear diagnostics. Preserve original source/manifests and import settings. One owner controls each shared contract; fixtures let cockpit/training/world agents work independently. P1/P2 require schema rejection fixtures, malicious path/XML rejection, GLB scale/orientation/pivot checks, license/source inventory, datum/reference-point comparison, and exported offline loading. Future native plug-ins, cloud sync, global streaming, or multiplayer require separate ADRs and compatibility/security tests.
