# Actual combined flight and gear checks

Build with [the pinned bootstrap](../../tools/bootstrap/README.md). CTest runs `interactive_loop` and `interactive_negative_readback` against the exact accepted original model. The scripted loop uses visible `scenario.proof`/scenario authority and requires stationary settling, actual takeoff, airborne control, touchdown and a final all-WOW stop below 0.1 m/s. It records matching completed-tick contacts, kinematics, atmosphere and every applied command. Final tick-zero/readback and terminal stop are not inferred from an earlier sample.

After the native build, run:

```powershell
node --test tests/interactive/verify.test.mjs
```

The verifier runs two actual loops and the native negatives, validates strict unchanged v1 records including lifecycle events, checks explicit scenario authority, compares complete state/weather/command/CSV bytes within this build, verifies final stop truth and pins model/unchanged lineage/default world/public source. It separately rejects altered inventory and airframe bytes. Output and `public-source-receipt.json` go to ignored `.local/interactive-proof/`. The receipt binds LF-normalized public source paths, dependency and contract digests, exact model inventory and executable hash; it never substitutes the private precursor's source hash.

Native negatives exercise each known missing result, unexpected callback missing/throw/nonstandard throw/identity/world faults and terminal disposal, invalid/duplicate/stale/wrong-session/self-elevated/unregistered/unsupported/assisted commands, canonical authority despite reversed arrival, paused pending input and constant dt at changed scale, owner-thread copied readback/close rejection, exact named starts, altered prepared shape/material/source, explicit research purpose and bounded control/lifecycle capacity without consuming a rejected sequence. The separate airborne prepared start runs 1200 actual finite ticks. Short explicit 60/240 Hz research cases exercise purpose/clock admission; they do not claim full combined-model convergence.

These are scripted engineering checks, not human handling, Cessna fidelity, production scheduler latency, GPU performance, combined resume or portable export acceptance. Human controls and actual package/model/DLL/source/notice/runtime checks belong to the subsequent preview delivery. Original coefficient/gear bytes are not tuned by these tests.
