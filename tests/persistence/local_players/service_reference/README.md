# Proposed independent service-sequence references

Original MIT. **PROPOSED / unratified / not executed.** This supplement is separate
from the immutable 114 value references and 72 design recipes. It freezes typed
service requests, manually derived conditional state/result expectations and
explicit preservation assertions. It imports no production module and runs no
SQLite, service, thread, native flight, Godot, file actor or GPU.

Proposed future public paths, subject to Root's #218 issue/contract allocation:

- `tests/persistence/local_players/service_reference/expected-v1.json`
- `tests/persistence/local_players/service_reference/generate.py`
- `tests/persistence/local_players/service_reference/source-binding-v1.json`
- `tests/persistence/local_players/service_reference/README.md`

The private gap inventory and handoff are reviewer material, not extra production
schemas or automatically allocated public files. The existing allocation does
not yet include these four paths. No acceptance or consumer dispatch follows
from their presence in this private directory.

`python -B generate.py --check` regenerates the manually authored examples using
only Python stdlib and compares exact bytes read-only. There is no write mode.
Passing this check says only that the declarative packet is reproducible. It
does not evaluate a service or demonstrate SQLite/native outcomes.

All production values in requests and complete receipts use explicit fixture
descriptors: NIL, BOOL, INT decimal String, FLOAT little-endian eight-byte hex,
STRING, STRING_NAME, ARRAY and DICTIONARY. A future driver must restore the actual
Variant types and compare exact bits. DICTIONARY `entries` preserve explicit
actual String keys; descriptors are test data, never submitted production JSON.
`$fixture_binding` denotes a future actual observed String with the named grammar,
not a request argument chosen by a caller or a generated expected fingerprint.
IDs/hashes in the source examples are plainly synthetic and grant no native
authority. Before states and conditional observations require separate actual
setup evidence. Projections and preserved-state lists say precisely where the
example does not provide a whole closed result.

The cases isolate violations to avoid inventing unspecified error precedence.
Observed IO/COMMIT/rollback/exit/file conditions are premises, not tests already
performed. Exact full-result values are used where the protocol supplies them;
the different-process recovery example excludes the unresolved timestamp and
paging examples freeze only order/cursor projections. Future actual tests must
check complete record shape/bits in addition. Preserve raw failures, require
actual child/worker exit, and never count timeout-kill as service join.

Source binding records raw and LF-normalized hashes explicitly. Original CRLF
preparation bytes stay unchanged. A later publication must separately bind
accepted contract/source-allocation commits; current source is still proposed.
No new tolerance, timing allowance, source/model identity or runtime evidence is
authored here. Actual isolated capability/SQLite/Win32 and editor/portable/rebuilt
journeys remain gates, with all original aircraft/phase/pilot limits intact.
