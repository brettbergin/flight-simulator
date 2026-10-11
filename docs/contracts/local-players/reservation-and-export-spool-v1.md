# Local players: native reservations and export snapshot spool v1

Original MIT. **PROPOSED, unratified, source-only.** Requires explicit #218
allocation, independent contract/fixture review and checked contract adoption
before store implementation. Concrete authored layout review belongs to #219
before compilation/execution, as separated below. Complements [protocol-v1.md](protocol-v1.md),
[records-and-lifetimes-v1.md](records-and-lifetimes-v1.md) and
[compiled-source-allocation-v1.json](compiled-source-allocation-v1.json).
It changes no method/DTO/wire key, SQLite pin, schema or flight authority.

## What is bounded

The proposed32MiB limit is a capacity guarantee for the service's owned native
variable buffers, controls and conversion workspace. Every such allocation is
in one fixed-capacity arena; no fallback native vector/string/JSON tree, growing
export buffer or hidden secondary pool is permitted. Encoded length is never
used as a claim about a Variant tree's memory footprint.

This is NOT a process RSS/heap/performance guarantee. Godot-managed caller input
and caller-owned returned Variants, SQLite's internal allocator/cache, native
thread stacks, OS buffers and executable/static data are separately governed by
their existing bounds/source qualification; they are not claimed to fit this
native arena. In particular Godot output construction must be main-thread-only,
directly from the owned flat delivery buffer, without a retained service-owned
Godot tree or another native intermediate tree. The separate DLL must not
silently install a process-global SQLite/Godot allocator.

**Explicit semantic amendment:** the original generic buffer wording is made
concrete here as native service ownership, not total engine heap. Root approved
this proposed scope before consumer output; independent source review and checked
contract adoption remain required. This proposal is not proof of an unwritten
allocator. Engine-managed construction is outside this stated ownership; encoded
bytes cannot substitute for its backing capacity. No physical heap/RSS result
is fabricated.

## Fixed representation and capacity

Reserve one32MiB native arena before the first accepted start can publish its
ID/state or create a worker/root. Native allocation failure at this point returns
out_of_memory with the original new object unchanged. Construction of an empty
LocalPlayers wrapper itself does not resolve a root. The arena has8192 pages of
4096bytes; allocation charge is actual owned capacity rounded up to a page,
including allocation/record headers. All page ownership is explicit. Checked
integer arithmetic precedes sizing; overflow rejects, never wraps.

| Permanent arena region | Bytes | Concrete content |
|---|---:|---|
| Control |131072|16 slot descriptors, fixed FIFO/terminal ordering, arena page/extent metadata, bounded status/diagnostic/root bytes, native synchronization/control ownership |
| Shared worker/admission workspace |1966080|the subregions below; no concurrent writer and admission parser may alias live bytes |
| Remaining allocatable pages |31457280|request blocks, terminal blocks, delivery overlap blocks and shared export snapshot reservation |

Workspace partition is fixed:32768 cells×32bytes=1048576 for a bounded flat
codec traversal/index (not Godot objects),655360bytes canonical/conversion
scratch,98304bytes row/UTF8 scan,65536bytes file IO,65536bytes stack/hash/crypto
scratch,32768bytes metadata/padding. Sum1966080. These are proposed source
representation maxima, not observations of unwritten structures. Compile-time
size/alignment assertions and independently reviewed actual allocation paths
must prove they fit; changing compiler/layout cannot silently overrun them.
The traversal/index and canonical/conversion regions use one nonblocking lease.
Worker leases last only through pure bounded decode/validation/transcoding, never
across SQLite/OS calls, queue locks or scheduler holds. The row/IO/hash regions
are worker-owned; owner status/poll does not borrow them. If admission cannot
acquire the codec lease immediately, it rejects out_of_memory with no state
change; no waiting on the worker/IO or unmetered replacement scratch is allowed.
Source review must close actual lease boundaries and all separately live retained
record bytes. No worker barrier may hold the queue/admission mutex or codec lease.

Each request uses a flat native RequestHeader (at most128bytes) plus contiguous
owned UTF8/canonical preference bytes and fixed scalar fields in the same block.
Strings/blobs use offsets and lengths into that block; no std::string/vector
heap ownership is hidden behind the DTO. Exact FLOAT bits and INT branches use
the accepted codec; no decimal substitution or generic Variant serialization.
Closed field identifiers/kinds are fixed enums, not a new public wire grammar.

Each terminal is likewise a header (at most128bytes) plus bounded owned flat
closed record bytes. Request/terminal headers count inside their640KiB cap.
A request's actual page-rounded charge R is known from checked validated sizing
before copy/admission; R<=655360. Reserve T=655360 for the maximum terminal and
D=655360 for independent flat delivery/copy overlap before accepting any job.
These are capacity reservations, not claims that actual record lengths equal
capacity. T includes a fixed nonallocating minimal failure/file receipt region;
its offsets and worst-case selected/temporary4096byte path storage must be
source-proved before code runs. Never construct that failure by a new allocator
call after a possible effect.

Thus a maximally charged slot is R+T+D=1966080bytes. Sixteen maximum slots plus
the2097152 fixed regions equal33554432 exactly. The16 limit is a ceiling: it
does not promise that every combination of large requests and exports is
admissible. All arithmetic, both memory and outstanding count, is independently
checked; rejection does not reserve a slot or publish an ID.

## Lifetimes and atomic admission

After thread/state/type/cap validation, check outstanding count then atomically
claim the slot, R/T/D and any required shared export credit. Count saturation
returns queue_full; insufficient arena capacity or failed allocation/copy before
acceptance returns out_of_memory. Roll back all temporary claims on rejection.
Only then publish accepted/request_id and the FIFO job. Physical reservation
must be real, not a counter beside an unbounded heap allocation.

R lives through the worker's last request use; release it only once no borrower
or terminal needs it. T remains until successful owner poll transfer or safe
closed-object destruction. D is reserved for that accepted request even while
pending/undelivered; poll copies the immutable terminal into D, restores owned
caller values directly, and removes exactly the delivered terminal only after
successful construction. Neither copy aliases worker memory. Release T/D only
after transfer; previously returned Godot values belong to the caller and remain
independent. A batch poll has no hidden full-batch native mirror: each slot's D
is already reserved. Catastrophic engine/OS OOM is not certified recoverable by
native reservations and must not be turned into a false COMMIT/join receipt.

An unexpected terminal overflow after a possible COMMIT cannot produce failed.
Use the pre-reserved uncertain/verification_failed receipt and read_only rule;
retain a source-contract defect for correction, never enlarge caps to fit output.
Request completion moves pending to undelivered without freeing its outstanding
slot. Actual joined closure/poll/destruction follows the separately proposed
service lifecycle companion; never free a live worker's arena.

## One shared memory spool, no disk spool/new recovery object

One writer executes FIFO, so at most one export snapshot or output operation is
active. All accepted-but-not-terminal export jobs share one **exclusive18MiB
native snapshot reservation**, acquired atomically before the first such export
is admitted. Later exports may share the same reservation only because they can
never execute concurrently; they still reserve their own R/T/D and result slots.
No second output thread/actor may read a reused spool. Keep this reservation
until every accepted export using it has become terminal and the active spool
has no IO borrower. Undelivered export receipts need T/D, not old snapshot bytes.

The spool holds canonical selected-player **inner payload** bytes, not a second
copy of the escaped outer JSON envelope. Root's proposed export clarification is
explicit: payload.practice is an Array of ALL selected-player PracticeSummary
records, ordered creation_sequence DESC by numeric U64 ordering, or [] when
empty; there is no page limit, filtering or truncation. This clarification also
requires checked contract adoption. Build it completely in the consistent
read transaction; release/finalize that read transaction before any selected
target CreateNew/write/flush/move. Stream the existing outer envelope by escaping
the stable inner bytes through the64KiB IO region, with bounded incremental hash
and full later file verification. Do not create an unlisted disk spool, new
temporary under Players, or persistent cleanup/recovery obligation.

Source-derived proposed capacity proof uses existing SQL/codec caps: Player
blob<=8192, preferences envelope<=614400 (its decoded canonical payload is no
larger),2000 Practice blobs each<=8192. Reducing archive to {linked:bool} adds at
most12bytes versus null and shrinks a nonnull ArchiveLink; charge16 extra per row
conservatively, plus2000 separators and4096 fixed outer-inner structural bytes.
8192+614400+2000×(8192+16)+2000+4096=17044688 <18874368.
The source writer must preserve the canonical/minified UTF8 spellings for this
proof; it cannot turn every Unicode scalar into larger escapes or silently
change record serialization. Independently freeze full near-cap canonical
snapshot fixtures and inspect actual SQL/codec/layout before accepting this
bound. The arithmetic is not proof that an unwritten encoder obeys the premise.

The final outer file cap remains32MiB. Count/hash its exact stream before target
IO, directly over the stable spool; the escaped payload may be larger than the
inner bytes. Over-cap or actually unrepresentable bounded snapshot fails before
target IO with the existing accepted read-work error storage_full. This is a
bounded snapshot/encoding-cap failure, **not a claim of NTFS disk full**. The
published protocol explicitly permits storage_full for read bounded work/snapshot
allocation failure. Its export result stays failed/sequence null with the closed
observed file receipt (phase read or encode, installed false, no temp/verified
file bytes/hash; snapshot identity fields only if actually established).

Arena exhaustion that is already known before admission is out_of_memory, not a
new accepted job or storage_full. An accepted export never loses its E/R/T/D
reservation to a later admission. Actual underlying allocation failure despite
reserved arena or a source bound violation is a preserved defect/known pre-effect
terminal failure, not automatic retry. A selected-file OS error uses its exact
existing file code and observations; no reservation converts it into success.
Only an explicit fresh user retry after polling/reconciliation/freeing capacity
can submit again. The target cannot be overwritten, and file uncertainty is not
DB uncertainty. Unknown worker outcomes retain the protocol's observed receipts.

## Existing source slots and distinct contract/source gates

No new compiled file is necessary: representation/sizing in records.hpp/.cpp,
codec.hpp/.cpp; arena/slots in service.hpp/.cpp; transaction/spool lifetime in
store.hpp/.cpp; bounded IO in filesystem.hpp/windows_filesystem.cpp; direct
Variant conversion in the allocated local_players.hpp/.cpp boundary. Preserve
the exact17 source/15 control allocation; actual bytes/controls/binary identity
are qualified after implementation, not invented now.

#218 accepts the design before store implementation: the native-only ownership
scope, exact arena/representation ceilings and charges, region/lease/lifetime
roles, full-export canonical bound premises, independent fixtures and public
source/test allocation. It does NOT require hashes/layouts/compiler output of
unwritten #219 consumers to close the contract. Freeze exact typed ledger tests
separately from114/72/66; no runtime result is inferred.

#219 then authors concrete offsets/headers/alignment, whole-result maxima and
minimal failure storage, actual lease sites and canonical writer within these
accepted ceilings. Independent review binds that ACTUAL source/layout and intended
compiler/target controls BEFORE compilation or execution; post-build commands,
objects/libraries/binaries and allocator/FIFO/COMMIT/uncertainty/export/NTFS/joins
are subsequent real qualification. Source choices within accepted ceilings are
implementation choices, not invented #218 hashes or arbitrary new approval gates.
No benchmark, RSS cap, C172, flight restore or phase completion is implied.
