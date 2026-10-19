# Local-player frontend: first integrated slice

Status: development evidence collected on Windows on 2026-10-18. Checked PR/CI
acceptance remains pending. This is partial [#220](https://github.com/brettbergin/flight-simulator/issues/220);
it closes no issue, parent, phase, aircraft or pilot gate.

The paused flight menu now connects Players, the default-Cancel end confirmation,
the joined no-flight chooser, create/select/Guest and explicit Controls/Audio Save actions.
The implementation consumes the accepted [frontend integration contract](../../contracts/local-players/frontend-integration-v1.md)
and [checked storage backend](local-players-store.md). Simulation remains the
aircraft authority; a stored player is neither a restored flight nor training credit.

## Development observations

All counts below are bounded checks, not features or pilot evaluations.
Native runs use disposable Root-owned fixtures and the actual qualified Build44 test
storage extension. Production KnownFolder storage is not substituted with a path.

| Observation | Result and bounded meaning |
| --- | --- |
| Existing complete flight-interface regression | 77,638 checks passed with the actual native flight library, no failures or error log, and joined termination. |
| Offline staging and package regression | Existing staging suite, 24 package checks, 26 native-identity fixture checks and focused Players source-closure checks passed. These checks do not qualify a named-player release. |
| Canonical pure presentation/controller checks | 81 passing checks; copied options, exact types/binary64 comparison, page guards and Guest controller behavior. No native persistence claim from synthetic fixtures. |
| Two actual application processes | 49 checks followed by 23; the same authorized disposable store preserves two named players and exact saved Audio bits/revisions, including signed zero and untouched null Controls slots. Each process observes storage join and empty results before exit. |
| Flight-menu Cancel | 14 actual-native checks preserve the current flight and modal authority through cancellation. This is method/signal evidence, separate from ordinary GUI input. |
| Audio retirement transitions | 25 checks with actual native flights and a labelled delayed/one-false Audio fixture, followed by actual production shutdown. Players and Quit cannot admit a replacement flight during retirement; explicit retry stays guarded. The Quit fixture observes the continuation without terminating the test tree or claiming storage join. |
| Combined Scene/storage journey | 37 checks cover actual menu/chooser create, named fresh flight, explicit Audio Save/ACK, paired revision, unchanged flight authority, joined practice end and Guest reset with retained recording context. |
| Visible keyboard and original captures | 101 checks and 21 viewport originals across 960x540, 1920x1080 and 2560x1440. Tab, Enter, Space, Escape and text events travel through ordinary GUI routing. Root inspected all 21 originals. This is bounded visual review, not a pilot assessment. |

The combined run retains actual practice source identity and a nonzero joined
endpoint; it does not infer landing success, a lesson score or official hours.
The two-process run deliberately selects players after launch; startup stays Guest.
Pending Save is not displayed as acknowledged, and edits made before ACK remain
dirty. An old player's receipt cannot activate that player after selecting Guest.

Retained Root-owned receipt hashes (not public uploads of player data):

| Receipt | SHA256 |
| --- | --- |
| Two-process controller | `9ecf9671ce496d9bbd86c9c2f0e7b0200e91fadf2ff1cbb721da1d7cdb7d9185` |
| Combined Scene/storage | `0b581868d7a6fd62675e8ecbb0d62aa78085389d9e9e7d41de2b0c506fd364f2` |
| Passing visible observation | `3886d921cc214028c84fd88491c8477939e1b03dbab6a8f4ebedd89b85c3ce29` |
| Failed visible observation | `dd08b15ee36db6076bf388f0dbd5d1182c662f54de380c5c4f2b9d47bbeacc2a` |

## Failures retained and corrected

An initial Controls indentation error failed parsing and was corrected before the
passing runtime checks. Missing copied dependencies in the temporary test project
were supplied before qualifying the combined development runs.

The first visible observer failed after Escape in the name LineEdit: 38 checks,
eight captures and eight reported failures. The narrow name-page input correction
was rerun from a fresh fixture; the later 101-check/21-capture run passed. The
failed observation remains retained rather than being counted as a success.

A raw GLB import emitted a NUL warning. That attempt is not qualified as a clean
new asset import. These UI observations do not replace existing cockpit import,
asset provenance or rendering gates.

## Delivery and remaining scope

Flight-only staging copies the controller, frontend and checks while excluding
the production storage registration. Its source validation does not establish a
working named-player release. A package without qualified storage remains Guest
with storage unavailable; it must not claim the full Players journey works.

History/detail/prune, archive association, export/collision, logical deletion and
management recovery have source implementations and backend contracts, but their
complete frontend journeys are not proved by the first-slice checks above.
Full applied Controls presets across the frontend relaunch, unknown/refused Save,
and unavailable-storage reconciliation also need their own journey evidence.
The accepted twelve-role flight/storage package aggregate, portable and rebuilt
flight/storage replacement journeys, and separately authorized disposable-user
KnownFolder installation remain open. The full local facade and offline staging regressions passed; final-head CI
results must be added only after their actual runs complete.

The existing human-playable build was preserved. This evidence makes no claim
about hardware controls, target C172 fidelity, real-airport correctness, formal
training-device approval, physical power-loss durability or human pilot acceptance.

## Checked menu integration

PR244 merged as4af88935f133ba6bf84f6ef94e8337d65bc52949. Root verified
its accepted tree exactly equals final head4d16f45d0c521c5d101138f2c2f5dc6fbef9e25c.
All twelve hosted contexts on that final head passed, including Windows
coupled/local-window editor, portable and rebuilt-library player regressions.
This completes the bounded menu integration; no new human package, full installed
named-player journey, aircraft or phase acceptance follows.
