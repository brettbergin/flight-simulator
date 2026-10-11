# Original live audio captions v1

Status: proposed bounded FLIGHT-AUDIO #25 contract amendment. Normative only after
its reviewed contract PR checked-merges. This is not an implemented overlay,
accessibility qualification, aircraft warning system or P1/P2 acceptance.

## Purpose and compatibility

Provide an optional readable in-flight explanation of the original engine and
airflow cues already admitted by Sound. Preserve ADR020's ten-key AudioCues and
four-key AudioOptions, synthesis, sample timing, playback retirement and native
authority. No new native/wire/preset/record/archive/storage fields or sounds.

This companion supersedes only ADR020's initial paused-only/live-caption deferral
and ADR019's prohibition of a new flag insofar as the distinct live-caption flag
and rectangles below require it. Keep those historical ADR files byte-identical.
The existing paused-caption checkbox retains its original meaning. The explicit
ADR026 named-player AudioOptions lifetime exception still covers exactly its four
existing fields; ADR025 Views settings remain session-only. This new flag is not
part of either bundle. No other aid is relocated, hidden, expanded or reset.

References: [ADR020](../../decisions/020-original-audio-cues.md),
[ADR019](../../decisions/019-ordinary-flight-overlay-layout.md),
[ADR025](../../decisions/025-paused-view-presets-and-comfort.md),
[ADR026](../../decisions/026-durable-local-players-and-practice-history.md),
[P2](../../roadmap.md#p2--first-pilot-operable-cockpit-and-synthetic-airfield).

## One source, truthful captions

Scene publishes to Sound through the existing _observe_audio adoption guard.
After that same observation, obtain Sound.cue_view() and Sound.options_view(),
owned copies of its admitted source and chosen mix. Do not independently read the
facade/native/device or infer cues from pilot commands, animation or old captions.
Scene's actual adopted session/profile and current presentation eligibility must
still match. Structural validity alone never proves native origin. If Sound is
absent or source/adoption eligibility is lost, clear immediately; no cached fallback.

The strip describes original cue source categories and selected mix, not actual
speaker output, hearing, instantaneous sample envelope or playback-retirement
completion. A live source may be silent during existing retirement. This limit is
stated in the paused Audio explanation; no extra playback observation API is added.
No engine load, warning, fault alarm, C172 acoustics, starter engagement or cranking
versus coasting is inferred. Existing starved remains paused-panel information.

Use exactly these ASCII fragments, without numeric RPM/TAS or arbitrary error text:

| Cue | Caption |
|---|---|
| engine_mode legacy | throttle tone |
| running | engine running |
| rotating | shaft rotating |
| stopped | shaft stopped |
| unavailable | engine unavailable |
| tas_mps null | airflow unavailable |
| tas_mps zero, including -0.0 | no airflow |
| tas_mps positive | airflow |

Mix selection is ordered: enabled=false => master muted; otherwise both gains
zero => gains zero; otherwise engine_gain zero => engine muted; otherwise
airflow_gain zero => airflow muted; otherwise mix on. Master mute/gain zero does
not erase source captions. Strict ADR020 validation precedes this selection.

Single-row text is `ORIGINAL CUES | <engine> | <airflow> | <mix>`.
Two-row text is `ORIGINAL CUES | <engine>` then `<airflow> | <mix>`.
Neither text claims a critical-warning caption. No shortened category, ellipsis,
scrolling marquee, color-only code, flashing indicator or synthesized alert.

## Flag, paused control and callback lifetime

Scene owns live_captions_enabled, actual Bool, default true for each application
launch. It survives fresh sessions/profile selections during that launch. It is
not saved, loaded, exported or copied into AudioOptions, Controls or Views; loading
named-player preferences does not change it. Existing Help/HUD/map/circuit flags
do not change it. A later persistence policy requires its own contract amendment.

Add one checkbox in the existing paused Audio modal after its existing paused-
caption checkbox: `Live captions while flying (this launch)`. Preserve all old
controls, gains, paused qualifier/detail behavior, default Back, scrolling and
already-paused entry. Add the checkbox to the existing focus chain; no new action,
shortcut, live hit target, auto-pause or auto-resume. Changing this flag alone never
calls Sound.set_options or reads native state. The paused page explains that live
captions show current cue source/chosen mix and may remain visible while muted;
playback readiness and aircraft warning accessibility are not established.

Add AudioPanel.set_live_captions_enabled(value:Variant)->bool and signal
live_captions_requested(enabled:bool,source_session:String). The setter accepts
actual BOOL only, stores an owned scalar, returns true for identical input and
does not emit. Invalid input returns false and preserves previous flag. The
checkbox restores its last admitted value before emitting a request. Requests
require the same admitted paused context as existing options requests. Scene
connects the actual widget/session/per-opening active guard to the new signal;
retirement invalidates/disconnects it together with existing Audio callbacks.
Foreign/stale/wrong-widget/wrong-session/not-paused/transition requests are inert,
including queued requests after reopening within the same session. Accepted flag
changes update the page without a native read or physics/input side effect.

## Read-only widget boundary

New app/ui/audio/live_captions.gd is one Control, with no signals, polling,
processing, native/device references or growing history. Scene creates it on the
main thread. Its two callable methods are:

* set_context(cues:Variant,options:Variant)->bool: validate the exact ADR020 cue
  and option shapes/relationships before copying. Valid input replaces owned
  context; non-live valid states clear text/hide. Invalid input clears text and
  owned context/hides and returns false, so rejection cannot retain stale live
  text. Identical valid input is idempotent. Partial valid live channels use the
  unavailable fragment above, rather than clearing another available channel.
* set_layout(bounds:Variant,rows:Variant)->bool: accept actual Rect2, finite,
  positive and wholly in the current viewport, plus actual INT rows exactly1 or2
  (not BOOL/FLOAT). Valid input replaces layout and returns true. Invalid layout
  clears text/context, hides, preserves the last valid bounds and returns false.
  Scene then must republish valid context after correcting layout; rejection is
  never a layout-fit pass. Identical valid layout is idempotent.

Neither method makes a hidden widget visible. Scene alone shows it after valid
context/layout and actual current-source/flag/flight eligibility; invalidation
uses empty set_context deliberately (false is expected), plus hide. Flag-off
clears rather than retaining old text; flag-on republishes newest Sound views.
Paused Review/historical archive display never shows live captions, even when its
retained recording has valid audio-like values. The existing paused Audio panel
continues to show its own current paused qualification/details. Source loss while
that modal is open follows ADR020's unavailable context and existing paused/recovery
menu path; no retained live text or extra simulation read repairs it.

Both methods check constructing-owner AND main thread before any context read or
mutation; foreign calls return false and change nothing. A valid context alone
does not grant display: Scene explicitly hides/clears while flag off, menu/modal
open, paused, noncurrent, terminal, initializing, quitting or not adopted. Source
loss sends the complete ADR020 unavailable cue/options view or invalidating empty
context immediately. Never keep old text behind hide and relabel it current.

Every descendant is MOUSE_FILTER_IGNORE and FOCUS_NONE, with no input/gui handler,
accept_event or tooltip dependency. Give complete text Labels stable internal
names CaptionLine1/CaptionLine2 for focused checks; those names are not a new DTO.
No new public generic validator, result accessor or cross-module API is promised.

## Fixed placement within existing docks

Viewport pixels, W>=960/H>=540; c=clampf(W/6,250,360). Visible only in live current
flight outside menu/modal, where ADR019 t=92. All existing docks/controls keep
their positions and visibility. Choose solely by traditional mode, not gaze/FOV:

| Mode | Rectangle (x,y,width,height) | Rows |
|---|---|---|
| COCKPIT0, including Forward horizon/Left/Right presets | (c+28,260,W-c-42,20) | 1 |
| PANEL3 | (10,88,W-c-34,20) | 1 |
| CHASE1 / ORBIT2 | (c+22,304,W-2c-44,44) | 2 |

Use the existing bundled fallback font at14px, light text over dark background
(alpha>=0.93),6px horizontal inset. Row rectangles are20px tall; second row starts
at22px. No vertical padding consumes the row allocation. Full ascent/descent and
unskipped line count must actually fit. If that fails, change/review the proposed
placement before consumer acceptance; do not reduce font, hide text or update a
test to accept clipping. Keep strip/Label rects and all clipping ancestors inside
viewport. No gaze-following placement, automatic camera recenter or aid hiding.

At960, these proposed gaps are independently arithmetic only: Cockpit x278..946,
y260..280 clears circuit y224..256 and default exposed faces beginning284.435;
Panel x10..686,y88..108 clears current native strip ending85 and default exposed
faces beginning111.773; external x272..688,y304..348 clears release ending298,
right map starting696 and CHASE readings beginning356.4. These are not glyph or
pixel observations. Check actual default Cockpit/Panel and requested CHASE HUD at
960/1080p/1440p. Preserve the accepted changed-gaze/FOV/side-view occlusion limits
under #179; this strip does not fix those limits or claim collision-free arbitrary
views. In deliberate gaze/FOV/side-window configurations the new fixed strip may
also intersect moved projected faces; that remains an explicit unqualified limit,
with the user's caption-off choice available, not an automatic visibility policy.
Caption-only source/flag/layout updates never change camera settings, other aid
positions/visibility or pointer generation. Existing resize/different-mode changes
retain ADR019/025's own layout and actual capture-retirement/rearm rules unchanged.
Same-mode gaze/FOV application preserves those fixed aids; caption placement does
not follow gaze. Different traditional mode selects only the rectangle above.
The caption widget has no hit mapping and initiates no capture retirement.

## Synchronous lifecycle and bounded consumer acceptance

Hook existing Scene source publications; clear synchronously on ordinary pause,
menu/modal entry, focus-loss pause, source/adoption loss, failed replacement,
terminal close and teardown before returning from that transition. Re-eligible
resume/adoption publishes the actual newest admitted Sound cue view. Opening or
closing Audio stays paused. No await/sample/device timing is used to claim source
currentness. Keep Sound's existing actual retirement/join criteria unchanged.

Independent hypothetical cue/options examples, labelled presentation-only, precede
consumer outputs. Cover all five engine categories, partial channel availability,
full-range String ticks, -0.0, strict Bool/FLOAT/unknown/missing/type rejection,
mix precedence, deep copies and idempotence. Actual native source tests separately
cover legacy and cold stopped/rotating/running observations without invented origin.
Compare complete native/Raw/mapper/recording/command/debt/origin and native-read
counts around caption/control/layout operations: use only the already published
observation, credit explicit observer-owned reads, and expose extra consumer reads.

Test owner/foreign threads, stale same-session reopening callbacks, immediate
clear/resume/new-session/failure/close, focus/Back, and pointer pass-through against
a consuming negative control. Check actual full text/font14/clipping bounds and
default primary-face clearance at the three sizes with worst-case source/mix text.
Use a small representative original-image set (minimum four traditional modes per
profile at960 plus larger worst-case captures), not another camera-wide campaign.
Seven presets still require mode/unchanged-aid checks; changed-gaze limits remain
reported. Measure results; proposed coordinates and synthetic DTOs are not evidence.

Delivery extends closed Audio source groups to include the leaf/focused tests and
one exact integration group. Keep existing Audio receipt keys cues/options/renderer/
panel/lifecycle and their literal closed fields: combine live-widget tests into
panel and actual Scene caption tests into lifecycle, preserving old assertions,
scope field and all named failures. Both new suites must actually run and contribute
positive actual INT counts; no unavailable-green branch. A separate internal
aggregate need not change a public wire/schema. Preserve old reference bytes.
Package current authoring/staged/corresponding sources, bounded matching UIDs and
all three current editor/portable/rebuilt-library checks through existing scripts.
No new native25/18 member, model change or numerical reference is required by this
presentation contract. Any actual shared source/control change still gets its
existing exact identity/requalification, never an exemption by this prose.

This is partial #25/REAL-020/PRD-018/PRD-020/UX-013. Installed warning captions,
measured engine load, real-device listening/latency, C172 applicability, pilot
accessibility and broad phase acceptance remain open.
