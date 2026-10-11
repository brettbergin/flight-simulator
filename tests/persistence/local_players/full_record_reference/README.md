# Independent complete local-player references

Original MIT. Proposed independent preconsumer reference input for #218, not a
store implementation or execution result. The previous 114 scalar references,
72 design recipes and 66 service references remain byte-for-byte unchanged.

Proposed public files:

- `tests/persistence/local_players/full_record_reference/generate.py`
- `tests/persistence/local_players/full_record_reference/expected-v1.json`
- `tests/persistence/local_players/full_record_reference/source-binding-v1.json`
- `tests/persistence/local_players/full_record_reference/README.md`
- `tests/persistence/local_players/full_record_reference/player-summary-v1.json`
- `docs/contracts/local-players/full-record-reference-amendment-v1.md`

From the repository root after authorized publication, read-only regeneration:

```text
python -B tests/persistence/local_players/full_record_reference/generate.py --check --schema-source schemas/save/local-players/v1/schema-v1.sql
```

The generator hashes the exact supplied DDL before using it. It imports only
Python standard-library modules, not production code, validators, SQLite,
Godot, native libraries, previous consumer outputs or database files. It writes
only its own two reference outputs when `--check` is absent. The proposed
companion makes export Array/order and structural counting choices explicit.

The 110 closed rows are grouped, not a combinatorial test campaign: seven complete
preference bundles, nineteen malformed complete preference bundles, nine Player
and Practice families, closed source tuples, complete two-player/three-practice
row/blob/hash/index datasets and targeted corruptions, exact SQL declarations
and mutations, full equality/revision/cursor values, four complete encoded
preference corruption cases, two canonical small exports, and bounded scanner/
count-cap expansions. See each row's group/basis; counts are descriptive only.

Every leaf uses explicit typed descriptors. `INT.decimal` restores an actual
bounded signed integer only where appropriate, and `FLOAT.binary64_le` restores
exact eight bytes including negative zero/subnormal values. Ordinary reference
JSON numbers are small structural counts, not the typed record oracle. A
`STRING_NAME` descriptor appears only in a negative case. Whole typed input and
expected normalized/decoded values permit deep-copy/mutation checks without
parsing binary64 through Godot decimal JSON. Rich preset enum inputs include
FLOAT1/2/index -0/key65/button127; expected enums are INT, while continuous INT
and FLOAT branches remain distinct. Device/vendor/product metadata are Strings.

ASCII key65 is A,68 D,74 J,75 K,77 M,78 N,82 R; systems use I/O/S/F. No consumer
or OS key-name roundtrip was run. Actual pinned Godot main-thread key parity,
nonfinite and subnormal admission, strict actual Variant types and native
validator parity must be qualified later. The ordinary accepted v1 validator
has less explicit String checks than v2; these references follow the durable
contract's stricter actual-String rule, never infer StringName authority.

`player-summary-v1.json` is the complete ORIGINAL synthetic 7,641-byte canonical
export, without trailing LF. Its exact length/hash is also in expected JSON.
Names/device metadata contain quotes, backslash, literal Greek/Japanese and a
tab: only the tab uses lowercase `\u0009`, and the outer envelope escapes that
payload String again. Hash is corruption detection, not authentication. The
selected player has two summaries in creation10,9 order although their latest
commit order is11,12. Linked archive is reduced to `{linked:true}`; no path,
product root, SID, flight log, owner profile or crash dump is included. Synthetic
fingerprints never identify a loaded source.

`CAP_full_2000_summary_export` supplies a complete Practice template, complete
Player/Preferences and exact finite expansion rules for all IDs, session IDs,
creation/commit values and order. Counts, inner/outer bytes and SHA are independently
computed before consumers. It is the 2000-row COUNT boundary, not a maximum-size
proof. Scanner-space/String/Array expansions are deliberately not semantically
valid records; `within_this_cap_only` never means record admitted. Depth counts
containers only. PreferencesStorage outer envelope JSON and decoded payload JSON
are scanned SEPARATELY before binary64 tag restoration, each with values<=30000
and container depth<=12. These preferences-layer limits are NOT a global cap on
the LocalPlayerSummary export aggregate. Full exports retain ALL selected-player
closed summaries (up to2000), exact coherent records and separate32MiB outer-byte
and native spool limits. The frozen 2000-row example intentionally exceeds30000
aggregate values; no row is dropped and no scanner cap is silently enlarged. A full arbitrary SQL string is an inspection reference, not an
observed sqlite_schema or SQLite constraint-execution result.

Database-row transports use actual column names: `record.utf8_hex` restores the
BLOB; its `bytes`/`sha256` are independent fixture observations, while separate
`record_sha256` restores the actual stored TEXT column. Other column Strings
restore as TEXT, meta bounded integer leaves as INTEGER. Do not insert the
transport object itself into SQLite. Complete row fixtures require fresh test
setup and independently observed runtime qualifier results, never a mock DB.

Exact shape/bytes/type checks can run offline later. Native origin, archive Save
association, actual schema/column/FK/index inspection, process/lock/worker/fault
behavior, memory reservation/export spool, NTFS path validity, crash recovery and
shipping source identities remain real independent qualification obligations.
No fixture simulates those operations or grants #219/#220 permission. A
Practice's backdated last_observed_utc is intentional: UTC is not a monotonic
flight clock, and ticks alone determine the endpoint interval. General runtime
store failure expectations are `corrupt_store`; request classification and
lifecycle precedence stay in their separately reviewed companion.
