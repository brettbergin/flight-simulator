# Full-record reference companion (proposed)

Original MIT. PROPOSED preconsumer amendment for issue #218; not contract acceptance,
consumer permission, database/flight execution or a change to the original 114,
72 or 66 references. Root selected the following freeze choices before consumer
outputs. Existing record, semantic, filesystem and ownership gates remain.

1. `LocalPlayerSummary` payload `practice` is an Array of **all** selected-player
   PracticeSummary values from the same coherent read snapshot as `player` and
   `preferences`. Empty history is `[]`. Order is immutable `creation_sequence`
   descending by full canonical-U64 numeric comparison (length, then digits),
   never latest commit, rowid or lexical-only sorting. Never silently truncate.
   Each summary is the complete Practice record with only `archive` replaced by
   the exact closed `{linked: bool}`. No external path is opened for this export.
2. Apply the already frozen codec canonical spelling to this envelope and
   payload: ASCII lexical object-key order, unchanged admitted Array order,
   canonical INT tokens, actual U64 Strings, schema-position binary64 LE tags,
   quote/backslash escaping and lowercase four-hex C0 escaping; other Unicode
   scalars literal UTF8. No BOM, whitespace or trailing LF. Hash exact payload
   UTF8 text; outer `payload_json` is that String, not a second structured value.
3. Structural scanner count: root is one value; recursively each object member
   VALUE and each array element is one value; object keys do not add values but
   retain their existing key/Unicode/type/byte checks. A root container has
   depth1; each nested container adds one; primitives do not increase container
   depth. The original PreferencesStorage codec values<=30000 and container
   depth<=12 apply SEPARATELY to its outer envelope JSON and decoded payload JSON,
   each scanned before binary64 tag restoration. They do NOT apply to the whole
   LocalPlayerSummary export aggregate or to all 2000 summaries combined. The
   export remains complete closed Player/Preferences/PracticeSummary records,
   at most2000 owned practice rows, separately bounded native spool and exact
   outer file<=32MiB; no truncation to satisfy a preferences-only scanner cap.
   These counting conventions and explicit scope are frozen preconsumer choices,
   not a change to the original codec caps or a claim of executed qualification.
4. Byte and structural gate fixtures do not bypass semantic closed-record
   validation. Spaces, arbitrary arrays and scalar Strings can pass one cap and
   still fail schema. A complete valid COUNT-cap history is not a theorem about
   the largest possible encoded byte size. No existing cap or tolerance changes.

This companion requires Root integration and checked contract acceptance before
consumer adoption. The lifecycle amendment, reservation/scheduler design,
actual full service/fault allocation and source/compiler/storage qualifications
remain separately gated. No new DTO field, source authority or persisted view
setting is introduced.
