# Independent local-player value references v1

Original MIT. **PROPOSED / preconsumer / unratified.** These original references
supplement the unchanged 72 logical design recipes. They do not prove storage,
crash recovery, SQLite, worker ownership, flight restoration, or pilot fidelity.

Future public files are exactly `tests/persistence/local_players/reference/`
`expected-v1.json`, `generate.py`, `source-binding-v1.json`, and `README.md`.
Source binding identifies exact proposed public contract bytes and accepted
validators; there are no private paths, private-script prerequisites or captured
consumer outputs in the four-file publication.

After publication, read-only regeneration is:

```console
python -B tests/persistence/local_players/reference/generate.py --check
```

Until publication, Root may run that same command against the private directory.
The generator imports only Python standard-library mathematics/JSON/hash/path/
argument utilities, never production modules. Default authorship refuses to
overwrite expected bytes; `--check` compares exact bytes and never writes.

The 114 closed reference rows comprise 18 IEEE bit patterns (15 finite and three
nonfinite rejections), 20 numeric-path families with positive/negative witnesses,
three whole canonical preferences envelopes, 23 uint64 lexical/type cases,
13 exact arithmetic cases, five creation-key pages, 16 strict encoded fragment
rejections, five revision recipes, eight copy/boundary recipes and three Unicode
spelling cases. Each family witness is **field-level**, not a complete admitted
preset. Arrays remain ordered and object keys ASCII lexical. Payload and envelope
UTF8 bytes/hashes are frozen independently of any decoder. Signed zero and
subnormal float bits stay tagged; normalized enum/key/index positions stay INT;
continuous admitted INT/FLOAT branches retain their type. Audio requires FLOAT.

`binary64_be_hex` describes a binary64 word in conventional high-byte-first hex;
`$binary64_le` is its exact eight-byte **little-endian** transport. Exact rational
values expose the bit derivation, including the distinction between decimal .06
and its binary64 value. Finite primitive transport does not imply Audio/path
admission: negative/minus-one/above-one/huge finite numbers fail Audio bounds.
No epsilon, decimal stringify/parse substitution, or signed-zero normalization
is allowed. `String` is an actual String, not StringName; `INT` and `FLOAT` are
actual Godot types, not JSON-inferred numbers. A test driver must restore them
explicitly from the descriptor and compare FLOAT bits, including minus zero.

Whole canonical bundles deliberately use both preset slots null. Full preset
shape, conditional paths, OS physical-key roundtrip, declared slots, alias and
Escape conflicts, continuous calibration sibling constraints, collection sizes,
UTF8/depth/value/encoded-size caps remain separate actual boundary tests. Do not
infer a max-int physical key is supported merely from its nominal numeric bound.
Encoded rejection rows are fragments at declared paths, not standalone successful
records. Corrupt hashes, duplicate/unknown keys or misplaced tags reject even if
a token itself is mathematically finite.

U64 operands remain canonical Strings through full `18446744073709551615`,
including values adjacent to 2^53 and beyond signed64. Zero is valid as a generic
U64/tick but invalid as a stored positive revision. Overflow/regression rejects
without partial mutation. Paging uses immutable creation keys, strict less-than
cursor, and nullable next cursor only when more owned rows exist. Edited rows'
latest commit values do not reorder them; inserted newer rows do not reappear
behind an existing cursor. These arithmetic pages do not simulate concurrent SQL
snapshots. Stale revisions reject before identical-content no_change tests;
unchanged max revision can return no_change while a changing max revision fails.

Copy and thread examples describe **future required actual tests**, not executions
performed by this generator. Their snapshots must include actual queue/results
and previously owned values; Python copying is not a substitute. Database
transactions, CREATE_NEW/file guards, KnownFolder, WAL/fsync, process death,
same-process reopen, uncertainty/reconciliation and export/delete require their
separately authorized tests after accepted contracts. No references are fitted
to any consumer and no existing physics, archive, native-wire or convergence
budget is changed. Root ratification and independent source review are pending.
