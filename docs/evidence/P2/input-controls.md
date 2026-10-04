# Paused controls and explicit presets

Status: implementation candidate for [#21](https://github.com/brettbergin/flight-simulator/issues/21), consuming the merged [ADR008 contract](../../decisions/008-input-presets.md). This is an original input/UX slice over the unchanged synthetic aircraft and accepted native facade. It does not close P1/P2 review, independent mixture support, a manual practice flight or hardware qualification.

## Resulting experience

The pause menu opens a Controls screen with one primary source per flight axis, keyboard remapping, observed hardware axis selection, raw and mapped target bars, native-held values, inversion, deadzone, gain and slew controls, and paused endpoint/neutral calibration. Learn waits for release and deliberate movement. Apply changes a validated guest preset only after the controller accepts the complete configuration; Cancel preserves the prior preset and connection selection. Mixture is visibly fixed at1 because the current prototype lacks that capability.

Keyboard defaults retain the existing signs, solved-start biases, gains and rates. Independent left/right pedals and explicit Q/E/Space/B brake overrides use the existing complete pilot command. Brake hold is seeded from each accepted fresh start, survives pause, focus and preset changes, and changes only on its declared toggle. The mapper has no aircraft-state feedback or native authority.

Focus loss, selected-device removal, malformed readings and missing observed controls pause before another solver step. Resume checks centered/released flight controls and the current connection generation, then separately obtains native acceptance. Absolute throttle/trim use visible matching before takeover. Device GUIDs are hints; selection is explicit and runtime numeric IDs never enter a saved preset.

## Preset storage

Load edits the paused draft. Save writes only the explicitly selected JSON path; there is no automatic settings store or launch autoload. SQLite remains the future profile/settings authority under ADR004.

The pinned Godot Windows [directory rename implementation](https://github.com/godotengine/godot/blob/4.7.2-stable/drivers/windows/dir_access_windows.cpp#L319) removes an existing destination before moving its replacement. Consequently the consumer does not use that operation for replacement. On Windows local NTFS it uses the built-in Windows PowerShell helper with fixed code and base64-encoded path data, invoking the .NET replacement operation for an existing file or same-directory move for a new file. A verified temporary is flushed, closed, reread and decoded before replacement. There is no delete fallback. Unsupported environments and failures report an unsaved result and retain the temporary. This bounded interchange operation is separate from durable profile/flight-save qualification.

## Evidence and limits

The independent analytic reference contains38 compact exact Fraction cases, prepared before the consumer and promoted with its generator. Active checks use actual pinned Godot constants and the actual mapper/codec; they distinguish sparse observations, connection generations, edge actions, takeover and the brake latch from synthetic hardware behavior. Existing facade/scene checks remain active.

The short visual fixture opens the actual Controls screen at960x540 and1280x720, learns a synthetic key, applies a draft, exports/imports an explicit test preset, rejects an invalid draft, cancels and verifies focus pause without another native tick. Captures and source-bound editor/export/replacement receipts must be retained for the frozen implementation before merge. Programmatic gestures and synthetic device readings are labeled; they are not a human or gamepad/yoke/pedal walkthrough.

Current engineering checks, final package counts and exact build bindings belong to the implementation PR's closure record. Required CI and independent source/package review remain necessary. Actual device availability, manual flight completion, broader hardware QA [#65](https://github.com/brettbergin/flight-simulator/issues/65), unsupported mixture and phase review remain open.
