# ADR-001: Godot presentation with an independent native simulation

Date: 2026-10-03. Status: accepted for planning; implementation adoption gated by P1 proofs.

Owner preference confirmed 2026-10-03: choose Godot when development requires no engine vendor account. Godot's official Windows download provides a self-contained executable that can be extracted and run directly; no signup is required for this workflow. Unreal's standard download/install workflow requires an Epic Games account. Use the direct Godot distribution rather than a storefront version. [Godot Windows download](https://godotengine.org/download/windows/), [Unreal download instructions](https://www.unrealengine.com/download).

## Context

The first product is a Windows desktop simulator with one faithful C172S configuration, a compact training region, local progress, and no required subscription service. A fleet of implementation agents needs testable subsystem boundaries. A high-quality renderer alone does not validate flight dynamics, cockpit systems, or training behavior.

## Decision

Use standard-precision Godot 4.7.2 Forward+ for presentation, typed GDScript for scenes/UI/input, and C++20 for an engine-independent simulation core. Integrate through a `godot-cpp` GDExtension pinned to the 4.7 API and exact native dependency build. Use Vulkan initially and exercise Direct3D 12 fallback. CMake/Ninja/MSVC 2022 build our Windows x64 libraries and headless harness.

Godot's official archive identifies 4.7.2 as stable. Godot's MIT terms fit the repository's MIT-owned code. `godot-cpp` permits a native extension without building custom engine/export templates, with explicit version/precision compatibility constraints. [Release archive](https://godotengine.org/download/archive/), [license](https://godotengine.org/license/), [GDExtension compatibility](https://docs.godotengine.org/en/4.7/tutorials/scripting/cpp/about_godot_cpp.html).

Default dependencies are free and locally buildable. Lock exact commits/checksums, export templates, CRT flags, extension precision, and source/license notices. Authoring tools may use supported LTS families, but their exact patches must be resolved before reproducible builds are claimed. No globally installed dependency is silently assumed by a release package.

## Alternatives

Unreal offers strong scene authoring and rendering, but its standard authoring workflow requires the vendor account the owner prefers to avoid. The owner selected Godot after considering this tradeoff. Unity similarly introduces a proprietary editor/licensing dependency and a managed/native integration boundary. A custom engine spends early milestones on generic engine capabilities. FlightGear extension/fork offers substantial existing simulation infrastructure and remains a possible scope fallback, with GPL distribution and a different product architecture. See the architecture comparison for source-linked terms.

## Consequences

We build the terrain streamer, aircraft/system bridge, and cockpit interactions ourselves. Regional scope makes that tractable, but renderer choice remains provisional until measured. UI agents can work against immutable snapshots while flight-model agents use a headless harness. Native export/ABI and library distribution become first-class checks.

## Proof and revisit criteria

P1 must export a portable application loading the bridge and JSBSim DLL on a clean Windows runner, exercise a real simulation step, and record dependency IDs. A representative cockpit/airport/weather scene must demonstrate instrument readability and the proposed target-PC budgets. Two measured rendering/streaming corrective iterations failing the same gate trigger a reviewed scope/architecture decision. An Unreal comparison or migration requires the owner's explicit acceptance of its account requirement, a new ADR, and preservation of the independent simulation contracts.
