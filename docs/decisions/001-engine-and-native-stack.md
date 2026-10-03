# ADR-001: Godot presentation with an independent native simulation

Date: 2026-10-03. Status: accepted for planning; implementation adoption gated by P1 proofs.

Owner preference confirmed 2026-10-03: choose Godot when development requires no engine vendor account. Godot's official Windows download provides a self-contained executable that can be extracted and run directly; no signup is required for this workflow. Unreal's standard download/install workflow requires an Epic Games account. Use the direct Godot distribution rather than a storefront version. [Godot Windows download](https://godotengine.org/download/windows/), [Unreal download instructions](https://www.unrealengine.com/download).

## Context

The first product is a Windows desktop simulator with one faithful C172S configuration, a compact training region, local progress, and no required subscription service. A fleet of implementation agents needs testable subsystem boundaries. A high-quality renderer alone does not validate flight dynamics, cockpit systems, or training behavior.

## Decision

Use standard-precision Godot 4.7.2 Forward+ for presentation, typed GDScript for scenes/UI/input, and C++20 for an engine-independent simulation core. Integrate through a `godot-cpp` GDExtension pinned to the verified 4.5 single-precision API and exact native dependency build. Use Vulkan initially and exercise Direct3D 12 fallback. CMake/Ninja/MSVC 2022 build our Windows x64 libraries and headless harness.

Godot's official archive identifies 4.7.2 as stable. Godot's MIT terms fit the repository's MIT-owned code. `godot-cpp` permits a native extension without building custom engine/export templates, with explicit version/precision compatibility constraints. [Release archive](https://godotengine.org/download/archive/), [license](https://godotengine.org/license/), [GDExtension compatibility](https://docs.godotengine.org/en/4.7/tutorials/scripting/cpp/about_godot_cpp.html).

Default dependencies are free and locally buildable. Lock exact commits/checksums, export templates, CRT flags, extension precision, and source/license notices. Authoring tools may use supported LTS families, but their exact patches must be resolved before reproducible builds are claimed. No globally installed dependency is silently assumed by a release package.

## Alternatives

Unreal offers strong scene authoring and rendering, but its standard authoring workflow requires the vendor account the owner prefers to avoid. The owner selected Godot after considering this tradeoff. Unity similarly introduces a proprietary editor/licensing dependency and a managed/native integration boundary. A custom engine spends early milestones on generic engine capabilities. FlightGear extension/fork offers substantial existing simulation infrastructure and remains a possible scope fallback, with GPL distribution and a different product architecture. See the architecture comparison for source-linked terms.

## Consequences

We build the terrain streamer, aircraft/system bridge, and cockpit interactions ourselves. Regional scope makes that tractable, but renderer choice remains provisional until measured. UI agents can work against immutable snapshots while flight-model agents use a headless harness. Native export/ABI and library distribution become first-class checks.

## Proof and revisit criteria

P1 must export a portable application loading the bridge and JSBSim DLL on a clean Windows runner, exercise a real simulation step, and record dependency IDs. A representative cockpit/airport/weather scene must demonstrate instrument readability and the proposed target-PC budgets. Two measured rendering/streaming corrective iterations failing the same gate trigger a reviewed scope/architecture decision. An Unreal comparison or migration requires the owner's explicit acceptance of its account requirement, a new ADR, and preservation of the independent simulation contracts.

## Toolchain resolution on 2026-10-03

Official source verification confirmed Godot 4.7.2-stable, JSBSim 1.3.1 and SQLite 3.53.4. The official godot-cpp repository has no 4.7 tag or branch at this date. Pin godot-4.5-stable at e83fd0904c13356ed1d4c3d09f8bb9132bdc6b77, targeting its 4.5 single-precision API on the pinned 4.7.2 engine. Godot documents forward compatibility with later 4.x minor versions. The bootstrap probe proves native initializer execution after constructing and destroying a RefCounted instance; it rejects missing positive evidence and engine errors. The exported simulator bridge remains a separate P1 gate. [Official compatibility guidance](https://docs.godotengine.org/en/stable/tutorials/scripting/cpp/gdextension_cpp_example.html).

[The dependency lock](../../third_party/dependencies.lock.json) records exact source commits, source/archive hashes, CMake 3.31.8, Ninja 1.13.1, editor and export-template archive hashes. [Bootstrap instructions](../../tools/bootstrap/README.md) record process-local MSVC 2022 setup and dynamic CRT policy. Python 3.12+ is sufficient for this standard-library bootstrap; CI pins 3.12.5. That baseline is distinct from the planned Python 3.13 data-tool environment, whose packages have not yet been resolved. The reference PC actually uses Python 3.12.5 and MSVC 19.40.33813.0. Hosted compiler/image drift is recorded rather than represented as identical binary reproducibility across different compilers.

Downloads and extracted source trees are checked before build and again in offline mode afterward. Python bytecode output is disabled during binding generation to keep verified source trees unchanged. Upstream JSBSim aircraft XML is excluded from runtime packaging. A reviewed library-only corresponding-source bundle, notices and replacement/build instructions remain prerequisites for simulator redistribution; a successful shared-library build is not that license gate.
