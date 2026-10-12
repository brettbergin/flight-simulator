# Original generic cockpit asset implementation evidence

Status: implementation preparation; candidate delivery and visual acceptance remain pending. The original-asset contract merged as `5e7f6042a8a5f313d0bb58d0abb7b0106ae125ad` under issue232. It contributes to issue23 without closing that broader cockpit task or any phase gate.

The independent original-builder baseline was captured before asset output with pinned Godot. It contains 74 parts, 84 asset nodes, seven material resources, 9,263 source vertices and 14,328 triangles, including 720 existing seam/pole degeneracies. The retained source baseline SHA-256 is `fbe01696c09d17042079060739d5599d649e30164727c4a414492c1402a88eba`. The independent GLB checker and actual Godot checks compare complete composed geometry, normals, UVs, winding, materials and control transforms against this baseline with the contract's unchanged tolerances.

Actual private export trials exposed material tint/roughness handling, repeated texture aliases, default double-sided materials and sphere-pole custom-normal loss. These failed trials are preserved and do not qualify the candidate. Source corrections and successful source-only reviews are not substituted for a fresh accepted export or actual import.

The integration preserves the existing builder success API, original eye/focus constants, live instrument panel, six open bezel rings and copied-state controls. Asset validation must complete before opening a native session; missing or malformed resources return an empty build result, show a bounded startup diagnostic and exit test modes nonzero. Simulation state and native source rosters are unchanged.

Required remaining evidence is a fresh reviewed Blender export; independent full GLB validation; pinned Godot import and actual imported-array/material/control checks; exact project, PCK, source and package inventories; retained MIT attribution; and all 60 prospective views in each of editor, portable and independently rebuilt-library contexts with independent review of the actual images. Existing camera, instrument, engine, native-source and whole-flight checks remain required.

This original generic presentation provides no target-C172S geometry, sensed-instrument, measured performance, human readability, hardware, pilot, aviation training-credit or P1/P2 acceptance claim.
