# KAWO world journey evidence

On 2026-10-19, isolated headless frontend checks passed with the actual native
flight bridge, reviewed KAWO pack and canonical terrain renderer sources. The
Scene adopted KAWO, returned to the original synthetic world and joined its
workers. This is bounded integration evidence for [issue #263](https://github.com/brettbergin/flight-simulator/issues/263),
under the [runtime contract](../../contracts/world/kawo-runtime-v1.md).
It does not complete the airport/environment phase or establish an installed,
visually reviewed flight experience.

## Observed checks

The retained focused qualification receipt has raw SHA-256
`0d5ef96b841a3fd0530b7f854b9e4cf6da884dde49b2db6a00ab1cb0cbf02bae`.
Its source and staged-copy checks remained unchanged. Every child joined without
timeout and exited zero. Absolute private paths in the original receipt are not
reproduced here.

| Suite | Passed checks | Scope |
| --- | ---: | --- |
| Source controls | 59 | Synthetic historical Recording3/archive3 values, source association, exact anchor words, selector types, strict pack JSON and bounded integer-field correspondence |
| Actual Scene journey | 24 | Real native/Facade/Scene/renderer adoption, replacement, archive round trip and joins; storage disabled |
| Archive-link reducer | 55 | Synthetic scheduling/ACK reduction, prune-ACK handling and explicit failure barriers; no persistence service or real flight |
| Actual archive/store journey | 28 | Real native KAWO tick 61, file Save, practice end/link ACK, store load and guarded historical linked Open in an isolated test root |

The Scene began with a real paused synthetic flight. Wrong selector type,
crossed wind and unsupported start were rejected while that flight's readback
remained unchanged. Valid KAWO selection closed and joined the old worker,
adopted the paused tick-zero geographic source, retained the terrain root's
custom origin participant and committed the actual origin protocol.

Presentation queries left the paused native readback unchanged. The map exposed
both compiled runways and selected designators 34, 16, 11 and 29. Synthetic taxi,
landmark-route and circuit aids stayed unavailable for KAWO. The actual recording
used revision 3 and passed exact archive encode/decode correspondence. Returning
to the synthetic world closed the geographic worker, restored synthetic geometry
and recording revision 1, then closed and joined the final worker.

The source checks and Scene checks live in
[the focused integration sources](../../../tests/integration/sim_loop/kawo_scene_checks.gd).
The Scene child took 18.769 seconds including its preparations and replacements.
That elapsed time is not a frame-rate or real-time performance measurement.

## Corrections and pending checks

An earlier retained attempt rejected valid KAWO preflight because parsed JSON
byte-count floats were compared through deep container equality against generated
registry integer literals. The correction admits only declared bounded integral
count fields, preserving exact row order, closed keys, paths, hashes, roles and
the runtime/120 clock. Raw payload identity and tagged binary64/anchor policies
are unchanged. The passing suites above include this correction.

The synthetic reducer checks model a verified file saved at tick 61 waiting
for an ordinary observation ACK or a synthetic close/end ACK before one archive
association request. They preserve its original practice/player/source/digest,
distinguish submission from matching link ACK and do not replay failed or
uncertain mutations. These checks do not prove durable storage.

The passing reducer suite also covers a successful prune ACK arriving
while an old practice's archive association remains unsent: the retained intent
becomes explicitly failed, and admitted link routes still drain through their
own terminal reduction. Malformed or failed prune results leave the intent
unchanged; an explicitly acknowledged failure can release the closed history
barrier.

The separate actual-store supervisor receipt has raw SHA-256
`d442edfda63f4483af8daae30fc578b56efd0551ca34b77e293d1f89b5e2c9dc`.
Its 28 checks passed with the current qualified flight bridge and the reviewed
B44 `LocalPlayersTest` DLL in a fresh capability-bound test root. Retained input
seals remained unchanged; the child joined with no stderr. This used the real
controller, Scene, recorder, archive writer and native storage service. Only Raw
input was supplied by the fixture; no local owner profile was opened.

That journey created and selected a test player, began the KAWO practice at tick
zero, advanced the actual native flight to tick 61 and paused. Saving produced a
verified archive3 file while the association remained `pending_endpoint`.
Repeated idle pumps produced no forced sub-120 observation, early end or link.
Native close then supplied the actual tick-61 endpoint; its committed end ACK
preceded one committed archive-link ACK. A real store load returned the exact
acknowledged practice, including the original player, source, window and digest.
The Scene's guarded linked Open restored the exact Recording3 as historical
review without starting another flight. Flight, audio and storage joined.

This proves the stated close/end path on the isolated test service. It does not
prove the ordinary-120-observation path against real storage, cross-launch
durability, every failure/recovery case or a shipping storage aggregate.

## Limits

These runs used deterministic fixture input and a headless renderer. They do not
establish GPU appearance, visible terrain seams, manual takeoff/landing quality,
installed/editor/package delivery equivalence, input hardware behavior or frame
performance. Broader storage, deletion/recovery and replacement qualification
retain their own gates. The complete Players backlog remains separate.

The KAWO terrain retains its documented approximate datum policy and unknown
total 3D accuracy. Basic compiled physical runway geometry does not supply
operational thresholds, taxiways, procedures or navigation suitability. Aircraft
fidelity, pilot evaluation and training-credit claims remain outside this
evidence.

## Isolated Windows package qualification

The complete portable preview package passed on 2026-10-19 at source commit
`bf02bc10251421a9994b7b44ae077be9b16caa23`. Editor, portable and rebuilt-library
replacement checks passed, including actual combined flight, source/model and
notice inventories, PE/CRT dependency closure and replacement-library execution.
The KAWO source closure bound the exact catalog, renderer and seven physical
world files; its raw receipt SHA-256 is
`f577d15b6a0a868a432ccc74f187fbe2469785f6bd4d096d267253d4d480c5cf`.
The final package audit is
`b8826d8dc9e700fdefc7a4241ac8d1bb740e87a0844c0b651289214df6f7e924`;
the complete manifest is
`8e01f0605bda389c049c352b8f9be009bc4965ad4699eb80192d5214731f0f24`.

The 109,268,480-byte release executable is
`d34d36f3be1a6c49c56525ae86469b92e4f417ddf0b43cf00dd80c385c4b0562`;
its 11,697,488-byte PCK is
`de48fe9687a63694a98efae34f0a6612eb1d5d8b1c6f3f6f76b40b34a4356aea`.
These are retained isolated artifacts, not an installed-game update or release.

An earlier package attempt passed runtime checks but failed its final inventory:
the seven physical world files were absent from the reconstructed-source
manifest. The correction declares only those seven already-validated files;
the fresh complete run above passed the unchanged final audit.

Two later attempts to invoke a focused KAWO script through the release
executable's script override timed out without the harness's initialization or
terminal marker. Both were terminated and joined; the sealed package remained
unchanged. They are failed test invocations, not a passed packaged KAWO journey.
The pinned [engine startup policy](https://github.com/godotengine/godot/blob/ed1daf0bf/main/main.cpp#L4018-L4029)
can clear script overrides in release builds. Actual shipping-executable KAWO
selection and scenery-resource loading therefore remain separate checks through
the game's existing test dispatch. The combined-flight package tests above use
the synthetic world; they do not establish a geographic takeoff or landing.
