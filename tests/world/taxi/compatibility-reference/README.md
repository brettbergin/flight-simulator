# Complete hypothetical apron compatibility references v1

PROPOSED independent preconsumer reference packet for issue225 and ADR027. It is normative only after the checked contract and independent fixture review authorize its consumers. Original MIT; repository LICENSE applies. No producer, Godot, JSBSim, codec, validator, database, filesystem save or native module was executed to create these expectations.

These four files are additive to the original wire49, observed42, archive40/26, local-player114/72/66/110/16/13 and old start fixtures. Those files remain byte-exact. The companion start-reference/expected-v1.json is the independently authored fixed-pose mathematical input. Run the read-only verifier from any directory:

    python -B tests/world/taxi/compatibility-reference/generate.py --check

For a private isolated checkout the same command accepts --pose-reference <exact independent expected-v1.json>. It verifies the frozen SHA before reading that data, constructs original expected values with only the standard library and compares exact output bytes. It never writes expected data. The source-binding lists every prospective normative input and each historical source observation; a reader/source hash is not an implementation observation.

## Typed transport and closed definitions

The packet root is exactly schema,status,license,transport,hypothetical_identities,fixtures,cases,lifecycle_recipes,criteria. fixtures is an ID map; each value is exactly role,typed_value,exact_typed_sha256. A case is exactly id,boundary,fixture,expected. expected is a boundary-specific assertion recipe, NOT a new public DTO or a claimed runtime receipt. lifecycle_recipes are deliberately declarative future assertions with inputs/actions/expected values. They are not executed evidence and must never be counted as worker, callback, copy or native tests merely by reading this file.

Every object in a materialized Readback, ReadingSet, EngineStatus, Recording, PracticeSource, Player, Preferences, Practice or export snapshot uses its existing exact closed keys. Each test-transport singleton {"$binary64_le":"16lowerhex"} marks an actual finite FLOAT at that same position; INT tokens, BOOL, String, null, Arrays and Dictionaries remain exact distinct branches. A test materializer must decode those eight little-endian bytes directly, never parse the whole typed value with NativeWireDecoder (which intentionally makes all numeric tokens FLOAT), coerce BOOL/INT or round decimal text. Only the explicit StringName substitution recipe changes a named runtime key's type. These transport markers are not accepted Readback inputs, arbitrary archive tags or a new wire schema.

Exact typed SHA256 means SHA256 of sorted-key compact UTF8 JSON of this typed transport. Test comparison preserves all FLOAT bits, including negative-zero vertical speed, all INT/BOOL branches, full canonical U64 strings and every copied nested value. The existing absolute canonical qualification1e-7m remains unchanged; no other numerical allowance is introduced. Canonical ECEF is copied from the frozen pose; copied anchor EUS[108,1.05,18] is a valid authored rounded value within that existing bound. Mass, atmosphere and zero motion are original structurally valid hypothetical inputs, not post-RunIC, ISA, gear contact, ready-engine or aircraft performance predictions. contacts[] makes no contact proof. Tick0/60/120 is an authored complete sampling sequence, not an observed flight trajectory.

## Identity is synthetic and cannot authorize installed source

hypothetical_identities includes the exact original descriptor, its canonical UTF8 spelling and SHA256. Its fields explicitly say native_authority=false and compiled_or_loaded=false. Source and controls use distinct descriptor roles/digests; only the source digest appears in the required Readback/Recording/PracticeSource fingerprint position. The control digest is separate labeled pure-test context, not a fabricated full generated native identity. Player/practice identities are separate32hex prefixes of separately labeled descriptors.

A pure test MAY bind its expected source fingerprint to this synthetic descriptor solely for structural/navigation fixture assertions. It MUST label that context synthetic, never replace/inject generated production identity or feed it to Scene/native adoption. In a real runtime harness the exact installed generated identity remains authoritative; its actual fingerprint must differ from all these descriptors and the fixture must reject. Required native_truth=true inside the ReadingSet is its existing literal contract field, not evidence that these authored values came from native. Archive decode/hashed metadata/history never grants native authorship. Current adapters require complete actual qualified Readback/source closure. A structurally valid hypothetical historical descriptor can remain in an illustrative record without pretending to be current source.

## Coverage and future execution gates

Both new calm-only starts have complete current paused/live and retained closed Readbacks; full samples/metadata; Recording1 or2 recording/manual/closed values; exact archive1/2 envelope text; PracticeSource; durable Practice and ordered selected-player export. Old readers reject unfamiliar new names intact; new readers must accept the additive closed domain and preserve old fixture bytes without relabeling or silently changing versions. Older-reader complete rejection channels are provided. New-domain invalid types/unknown keys/incomplete pair/canonical null/source mismatch and source model/wind contradictions remain rejected. Missing optional piston shaft reading is a valid unavailable null channel; a null scalar in AircraftSnapshot.systems is malformed. Bool engine channels cannot become FLOAT0.

Archive utf8_text is the complete no-LF outer UTF8 JSON; payload_json is an exact String of schema-position tagged floats. Its payload SHA and full outer byte count/SHA are independent direct byte construction. The decoded_recording member is the intended complete source value for comparison, NOT a claim an invalid archive decoded. Bad checksum and rehashed malformed payload cases separately reject with null failure value/payload_sha and nonempty error. Existing file IO/path/NTFS rules are unchanged and unexecuted here.

The export is the full closed LocalPlayerSummary envelope and coherent authored snapshot: all two selected-player summaries, creation_sequence numeric DESC3,2; no external archive paths, truncation or sorting repairs. Both saved slots are null Default and Audio gains actual FLOAT. Existing rich preset/codec/DDL fixtures remain separate. SQLite state/index consistency, source adapter and real export IO still require actual implementation tests. An export is neither a physics resume nor flight-hour/score claim.

Same-session reopen, stale foreign/current callbacks, retained old recording after failed replacement, same-session Recorder.begin rejection, complete different-session identity_changed seal, foreign-thread refusal and deep-copy recipes are predeclared expected behavior. An actual later test must exercise the real APIs/threads/widget tokens, observe true worker/audio joins and compare full authority/Mapper/recording bytes; these recipes alone cannot establish those observations. Prior metadata/sample prefix remains while the real old close truthfully seals closed. No new record/practice/navigation source adoption follows failed initialization. Current-looking historical guidance is unavailable.

Issue225 must complete independently reviewed full-value fixture preparation before corresponding reader/archive/PracticeSource consumer changes, then compile/source-qualify and exercise the actual native/apron/UI/35-row camera matrix separately. This packet does not accept ADR027, close #22/P2, validate C172, provide pilot/training credit, or qualify a shipping build.

## Additive U64/source-binding successor

The original 101 typed values, 62 boundary recipes and all 16 lifecycle recipes
are preserved exactly as semantic prefixes. Twenty new complete values and
their boundary expectations extend both apron source pairs: an active Practice
whose immutable creation/latest commit/tick is MAX_U64, and a manually ended
Practice whose begin sequence is MAX_U64-1 and end sequence is MAX_U64. Their
revisions remain respectively 1 and 2. Exact endpoint subtraction uses
MAX_U64-120 to MAX_U64 and produces 120; the active interval has zero difference.
These are mathematical record-domain examples, not elapsed native Readback,
actual flights, reachable database states or observed SQLite transactions.
Existing Readbacks, Recordings and archives are untouched. No max-uint tick is
converted into native elapsed seconds, FLOAT or a signed SQLite integer.

Each valid boundary record has a full one-summary export envelope with exact
inner/outer UTF8 spelling, byte count and checksums. Complete malformed clones
put String 00, actual INT0, or String 18446744073709551616 at creation_sequence;
their export envelopes are correctly rehashed and still semantically invalid.
No coercion, silent correction or checksum-only acceptance is permitted. The
otherwise admitted changing-transaction counter_exhausted rule is conditional
protocol evidence only; no worker/database call was made here.

The current consolidated ADR027 is the additive normative-override proposal;
the original ADR011/012/022/026 files retain their historical bytes. The new
source binding records these current prospective source bytes and separately
binds the preserved predecessor public files. Old reader observations are
rebound to identical Git-LF source, with their original raw pins retained as
historical provenance. Existing 25 immutable reference inputs are raw-byte
unchanged. Checked contract acceptance and independent review still precede
consumer changes; actual current-source/native/three-context qualification is
separate. These original synthetic descriptor hashes never authorize a real
installed source or replace a generated production fingerprint.
