# Local players: recovery-copy records v1

Original MIT. **PROPOSED** companion to [ADR026](../../decisions/026-durable-local-players-and-practice-history.md); no file service or database has executed.
These are finite internal recovery records, not a new public wire format, logical
backup, restore operation, multi-file atomic snapshot or migration acceptance.

Every object is closed with actual String keys. IDs are32lowerhex, SHA25664lowerhex,
FILE_ID_INFO volume_serial_hex16lowerhex/file_id_hex32lowerhex. UTC uses the main
proposal's date grammar. Relative names are fixed tokens below; no record contains
an arbitrary cleanup path. Routine logs contain none of these private file details.

The fixed root is Players/recovery. A set is recovery-<id>. It contains only
intent.json, optional manifest.json, and the four fixed data names players.sqlite3,
players.sqlite3-wal, players.sqlite3-shm, players.sqlite3-journal. Basename case is
exact; case aliases, reparses, link-count!=1, nonordinary or extra files refuse
automatic opening/deletion. A partial owned set counts toward the two-set limit.

Intent is exactly `{format,version,id,created_utc,source_files}` with
format="LocalPlayersRecoveryIntent", version actual INT1. source_files has exactly
four ordered rows main,wal,shm,journal. Each row is exactly
`{role,name,present,bytes,source_identity}`. present is actual bool; absent means
bytes/source_identity null. Present bytes is an actual INT within that role's cap;
source_identity exactly `{volume_serial_hex,file_id_hex}` witnessed on the held
source handle. This intent is CreateNew+FlushFileBuffers before any data copy.
It contains no invented hash or destination identity. A directory/intent creation
failure leaves observed remnants with no fabricated valid intent; such a set is
reported partial and cannot be silently erased by the normal deletion job.

The complete manifest is exactly `{format,version,id,created_utc,intent_sha256,files}`
with format="LocalPlayersRecoveryCopy", version INT1; same id/UTC as intent.
files has the same exact ordered four rows. Each is exactly
`{role,name,present,bytes,sha256,source_identity,copy_identity}`. All four nullable
fields after present are null for an absent file. A present row uses actual
complete source/copy byte count/hash and FILE_ID_INFO identities. Copy/source
bytes/hash equality and original roster/identity stability are required before
CreateNew manifest.json and its checked flush. Hash includes the whole intended
file, never a prefix. Manifest and intent together<=1MiB (intent<=64KiB,
manifest<=960KiB); each main<=256MiB,wal<=64MiB,shm/journal<=8MiB. Complete set
definition requires every declared copy+manifest+intent reread/hash/identity to
match. Missing final manifest is partial, never proof that SQLite may open.

Partial state is inferred from actual files/intent completeness; no overwrite of
intent or a final manifest turns failure into success. Worker crash before final
manifest leaves this same inspectable partial state. A syntactically valid
manifest alone does not qualify the set: enumerate actual roster and reread every
declared copy. A recovery copy contains potentially private data of ALL players,
including logically deleted content; that is shown before selected deletion.

One disposable work-<id> copy under the same recovery root is separately owned
by its selected retained set's id and a CreateNew intent. At most one work set,
same<=336MiB input caps; SQLite scratch growth is checked and actual disk-full
is failure, never permission to destroy the retained set. SQLite qualification
may recover/change this WORK COPY only. No work file enters the immutable
manifest. On normal close the worker closes every statement/connection/handle,
rechecks the fixed known work roster/identities, removes only that work set, and
records observed completion. Unknown remnants retain it and block creation of
another work set until explicitly managed; no recursive guessed cleanup.

RecoverySummary in the protocol is observed, not trusted stored text: id, actual
complete/partial state, valid intent UTC or null, current total bytes within cap,
actual complete manifest SHA or null. An unknown/oversize directory prevents
bounded recovery opening and is reported as explicit external storage management
required, not invented as an ordinary deletable record. list is finite under
the fixed root, rejects excessive directories without loading all their data.

delete_recovery selects one/two known displayed IDs, default Cancel confirmation
of ALL-player scope. It is serialized after all qualification/DB/snapshot/export
handles have closed, while the lifetime owner lock remains held. The service
must be unavailable with no SQLite connection; ready/read_only must first perform
an explicit joined close and reopen a management-only owner object. Successful
start_management() never qualifies/opens SQLite. It exposes list/delete/close
only; its exact fixed API and result are in [service protocol](protocol-v1.md). It does not accept a
root/SQL/mode argument or product environment override.

For a complete set validate the full fixed manifest/intent roster and identities.
For a partial set a valid intent proves only permitted fixed names/ownership;
validate each actual file identity as an ordinary unique same-root file before
deleting it. Delete data files, then manifest, then intent, then empty directory;
observe each actual deletion. A crash/mid-delete failure preserves remaining
files and cannot be reported as fully deleted. Result deleted_ids contains only
sets proved completely absent after successful known-file operations; retained_ids
contains all others. A linked owned work-<id> is included after the same fixed
intent/roster/identity checks; the ID is fully deleted only when both known
directories are absent. Do not call a partial success a DB commit or hide the retained
paths. File uncertainty alone does not establish database transaction uncertainty.
No external archive/export deletion, forensic-erasure promise, restore, automatic
snapshot pruning or backup import is authorized.

The deny-WRITE source handles protect the copying interval only. Release them
before normal original SQLite RW open; the owner lock stays held for cooperating
instances. External editing is unsupported. The same-directory path/handle checks
and identities are observations under a stable-parent assumption, not a proof
against arbitrary same-user pathname races. OS flush calls, checked copies and
actual close/join must receive real isolated tests and source review later.
