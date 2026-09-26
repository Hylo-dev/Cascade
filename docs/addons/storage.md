# Addon persistence boundaries

`CascadeRuntime.AddonStateStore` persists one versioned checkpoint per verified publisher/addon identity.
It is a package service for host integration. The separate internal `AddonKeyedStorage` backend is now
implemented and reviewed; see the keyed-storage section below. The existing SDK `read(key:)`,
`write(_:key:)` and `remove(key:)` interfaces are unchanged and their authenticated transport remains pending.
The host asset pipeline, image decoding and explicit publication sharing are described in [assets.md](assets.md).
Internal SwiftData save/restoration and notice replay prevention are implemented below.
Automatic application wiring and the qualified migration-process adapter remain separate work.
This implementation does not complete all of C5 or the `storage-assets` evidence record.

## Host lifecycle and authority

The host creates an existing private directory (0700, current user), then calls
`AddonStateStore.open(root:registrations:namespaceLimit:governor:diskBudget:)`. The complete retained identity
registry contains 1–256 unique `StateRegistration` entries, including disabled or uninstalled addons whose user data
remains. Each registration binds a `VerifiedAddonIdentity` to its own nonzero `maximumSchemaVersion`. The optional
`namespaceLimit` can tighten the 256-entry ceiling. This retained-data metadata bound is separate from the resolver’s
32-active-addon limit. A publisher is nonempty and limited to 512 UTF-8 bytes. An unknown identity cannot acquire
an owner handle. Registration is trusted host input; this service does not verify signatures itself. Schema support
is canonical per identity: another addon’s higher schema cannot authorize reading, writing or migrating this owner’s
future-version data. Changing schema support requires a new host registration when reopening the store.

Root traversal opens each component with `openat` and `O_NOFOLLOW | O_DIRECTORY`. The root is held by an open
descriptor and an exclusive nonblocking `flock` for the store lifetime. No provider-supplied key, file path or
publisher claim selects a file. The filename is a SHA-256 namespace over the UTF-8 publisher byte-length,
publisher, and addon ID. `StateOwner` and all tickets have module-internal constructors and are checked against
the store's canonical tables. Reopening issues new capabilities. `revoke(owner:)` invalidates the live owner
and all its pending tickets before attempting staging cleanup, and retains the committed user data and disk charge.
If cleanup fails, the old capability remains revoked and the staging disk charge remains until safe cleanup succeeds.
Trusted host code may subsequently acquire a fresh handle for a verified reconnection.

The root must be accessible only to the trusted host, not to addon processes. These checks are not a sandbox
against another compromised process with the host's UID and arbitrary filesystem access. The exclusive lock
coordinates participating store instances. Namespace-bound checksums also reject accidentally swapped files
between publishers. Identity hash collisions are subject to SHA-256's cryptographic assumption.

Keep the store strongly owned until explicit `close()`. Close releases only reservations issued by this store,
closes the directory descriptor, and leaves committed/staged disk files intact. Dropping an unclosed store closes
the descriptor as a fallback but does **not** asynchronously release governor accounting; explicit close is a host
lifecycle requirement. Suspend new storage admission while closed and reconcile before resuming. No arbitrary
`ResourceGovernor.releaseAll(owner:)` is used. An owner ID shared by different publishers receives conservatively
shared governor ceilings, but never shared file authority.

## Operations, format and failure behavior

- `read(owner:)` returns an optional `StateCheckpoint`; missing is distinct from corrupt or unsupported state.
- `write(_:schemaVersion:owner:)` prepares and atomically commits a checkpoint. Repeating identical bytes and
  schema avoids disk writes and preserves the revision.
- `stage`, `commit` and `cancel` expose an explicit preparation boundary. Reads continue to return the old
  committed record until commit. There is at most one staged record and one migration per namespace.
- `removeUserData(owner:)` is an explicit host/user deletion, separate from cache management. The checkpoint
  store has no cache-purge operation. Revocation, provider exit and reconnection do not delete committed data.

Each namespace has at most `<64 lowercase hex>.state` and `<64 lowercase hex>.stage`. A record is a 64-byte
header and at most 65,536 payload bytes. All integers are unsigned, big endian:

| Byte range | Meaning |
| --- | --- |
| 0–7 | ASCII `CASCST01` |
| 8–11 | Nonzero schema version, UInt32 |
| 12–15 | Payload byte length, UInt32 |
| 16–23 | Nonzero monotonically increasing revision, UInt64 |
| 24–55 | SHA-256 of namespace filename stem bytes, header bytes 0–23, then payload |
| 56–63 | Reserved zero bytes |
| 64 onward | Opaque checkpoint payload |

This checksum detects corruption and namespace substitution; it is not a MAC against a malicious host.
The store validates magic, length, revision, reserved bytes and digest before returning a record. Revisions
cannot wrap. Schema versions above that owner registration’s supported maximum return `.futureSchema(version)` after integrity
validation. Malformed bounded regular files return `.corrupt`. Reads and writes fail for that namespace, preserving
its bytes and charge; other valid namespaces remain usable. Explicit user-data removal permits recovery from
bounded corrupt/future files. Payload content is opaque; domain-specific migration validation remains a host task.

Every file is opened without following symlinks and checked with `fstat` before reading: it must be a private,
current-user-owned regular file, have exactly one hardlink, and be no larger than the checkpoint maximum plus
header. Nonblocking opens prevent FIFO/device fixtures from hanging before validation. Oversize is rejected
before allocating a payload buffer. Reads are bounded to the validated size and recheck size afterward.

A new stage uses exclusive creation and is fully written and `fsync`ed before returning its ticket. Commit rereads
and validates both the current revision/digest and the staged candidate, checks cancellation, then uses `renameat`
in the same directory. Rename is the visibility commit point. Precommit failure preserves the previous committed
record. Cancellation after the visibility commit does not roll it back. This is atomic visibility and recovery
from process interruption while the OS remains running; it is **not** a tested power-loss durability guarantee.
There is no claim that directory metadata or physical media was made power-failure durable.

On reopen, the service enumerates at most twice the registered namespace count. It validates and charges every
recognized `.state` and `.stage` file before deleting any abandoned stage. Partial but bounded regular stages are
accounted and removed without interpreting their payload. If admission fails, no recovery deletion is attempted
before the complete inventory is admitted. Failure cleanup releases issued reservations; the failed store is not
available for new work. Unknown entries, unsafe files, oversized records or an overbudget inventory explicitly fail
whole-root reconciliation. These cannot be silently excluded from accounting. The host must repair/admit that root
before it resumes persistence. Only files belonging to the registered namespace and fixed `.stage` suffix are
recovery candidates; user data is never treated as cache.

## Resource accounting and execution

The production checkpoint bound is 64 KiB, including for checkpoint data received from `ProviderOutput` once
that integration is connected. This service does not expand checkpoint size to implement arbitrary keyed data.
`ResourceGovernor` enforces its existing 10 MiB disk-state owner limit and shared 100 MiB disk limit, including
other admitted consumers. The store's optional `diskBudget` can only tighten its shared ceiling.

Disk charges are logical file bytes including the 64-byte header, plus a conservative 4,096-byte metadata allowance
for each live file and each registered namespace. Old and staged charges coexist until replacement. Recovered
staging bytes are charged before cleanup. This is **logical quota accounting**, not measurement of APFS allocation,
compression, snapshots, extended attributes or physical sectors. The trusted root must contain only these records.

Before creating namespace tables, the store reserves only 2,048 bytes of retained-state metadata per registered
identity. Governor reservation bookkeeping is charged separately by the governor itself. Empty/inactive registrations
do not reserve checkpoint buffers: opening 100 inactive identities still permits another real 7 MiB state reservation
under the shared 8 MiB ceiling.

Snapshot retention is admitted on demand, separately from disk charges. A pending migration reserves its source
payload size plus 128 bytes of checkpoint/digest overhead. A prepared write reserves its candidate payload plus
128 bytes and, if present, the previous payload plus 128 bytes. Source/previous/candidate snapshots all count while
retained, even if their `Data` storage could share memory. The governor also charges each reservation’s metadata.
Admission precedes placing snapshots in the canonical pending tables; reads/encoding before that point remain
covered by the operation’s temporary-memory reservation. Aggregate admission can deny pending work independently
of the 256-identity metadata limit.

Commit, cancellation, revocation, explicit removal and close release their canonical snapshot reservations. Failed
new admissions release their newly acquired reservations; existing pending tickets keep their already admitted
snapshots until they are committed or invalidated. Invalidating a stage releases its snapshots even when disk cleanup
fails, retaining only the disk charge until safe cleanup. No other subsystem’s reservations are released.

Each payload operation separately reserves four maximum records of temporary memory before file reads, encoding or staging
allocations. The caller already owns supplied `Data`; admission does not account retrospectively for caller/provider
allocation. Returned checkpoint/migration values handed to the host are likewise the caller’s retention responsibility.
All allocations the store controls remain bounded. Cleanup operations (cancel, revoke, remove and close) do not read
payloads and require no new payload-buffer reservation, so they can release snapshots even when shared retained
capacity is completely full. Persisted data retains disk charges after snapshot release.

The store is an actor, independent of MainActor. Its filesystem/codec work is bounded and sequential; reentrant
operations are rejected with `.busy` during an in-flight admission or release. No unbounded worker queue, polling,
per-addon timer or addon closure runs inside the store. Hosts should call persistence on meaningful state changes,
not animation frames or timer ticks. Provider ingress/rate limits remain the coordinator/transport's responsibility.

## Migration boundary

`beginMigration(to:owner:)` returns a bounded source and a canonical `StateMigrationTicket` bound to the owner
capability, old schema/revision/digest and a target within that owner registration’s supported schema ceiling. It executes no migration code. The trusted host may send
that source to a qualified external worker when its process adapter exists. `stageMigration(_:ticket:owner:)`
accepts the returned bounded bytes only while the old checkpoint still matches. `commitMigration` revalidates
source and candidate before atomic replacement. A failed candidate, stale source, cancelled ticket or revoked
owner cannot replace old data. `cancelMigration` discards only the associated prepared stage and its ticket.

No API accepts a custom migration closure or a provider filesystem path. Structural/schema bounds and checksum
validation are implemented; semantic validation of opaque payloads and launching an isolated migration worker are
not claimed. Recreating an owner handle or reopening the process does not revive any old migration ticket.

## Keyed-storage host backend — C5b

`AddonKeyedStorage` is an internal host actor, separate from the 64-KiB versioned
checkpoint above. It stores several independent values per verified publisher/addon.
Each key contains 1–256 UTF-8 bytes without NUL and each value contains 0–65,536 bytes.
An empty value exists; a missing key returns no value. Keys retain their exact bytes:
no normalization, trimming or case conversion. Slashes and dots are valid because
keys are hashed, never used as paths. Visually identical Unicode spellings with
different bytes are different keys. Domain-separated namespace/key hashes and the
record checksum bind every record to the exact identity, key and data/cache class.

The host opens an existing private root with 1–256 retained registrations, including
disabled or uninstalled addons whose data remains. Namespace identity is the verified
publisher plus addon ID, independent of executable digest and connection generation.
Registration does not itself verify signatures. Canonical opaque handles and tickets
are checked after governor suspension; close, processed revocation and reopening
invalidate old capabilities. Provider exit never implicitly deletes user data.
The future authenticated adapter must bind permissions and current session authority
to these operations and propagate revocation; no provider-supplied owner is trusted.

The host selects the data or cache class. The future SDK preferences facade always
uses data; a provider cannot choose cache to enlarge its persistent-data quota.
Explicit user-data removal and host cache purge are distinct operations. Stable data
survives legitimate updates by the same publisher and source-app absence.

### Admission, format and bounded work

The injected common ResourceGovernor enforces 10 MiB data, 20 MiB cache and 30 MiB
combined per addon, plus 100 MiB globally across admitted consumers. Checkpoints and
keyed data share the data ceiling. Disk pools are resized atomically while preserving
reservation identity and metadata charges; other consumers' reservations are never
released. A write needs space for both the old record and the full staged candidate.
Logical file bytes include the record header and key, plus a conservative 4,096-byte
allowance per file and actual managed directory. The root's allowance is assigned to
the first retained registration for the ledger lifetime. These are logical admission
limits, not measured APFS allocation, resident memory or a physical-space guarantee.

Records have a 128-byte header (`CASKV001`, version 1), raw key and value, with a
maximum complete size of 65,920 bytes. Big-endian fields encode class, key/value sizes,
nonzero revision, namespace/key hashes and checksum; reserved fields must be zero.
Malformed or unknown live records retain their charge and cannot be silently replaced.
Known oversized files are charged from file metadata but are not loaded as payloads.
Explicit deletion is the recovery path for unsupported live values.

Admission precedes controlled retention: 2 KiB per namespace and 8 KiB fixed operation
metadata, with 267,776 temporary bytes for payload work and bounded candidate retention.
The governor also counts its reservation metadata. Supplied/returned Data belongs to
the caller's retention budget. There is one active operation/stage for the store;
concurrent callers receive busy rather than entering an unbounded queue. Inventory
streams into namespace totals without retaining a per-key map. File/directory metadata
charges also bound entry counts. Only the root descriptor is held between operations;
the scan peak is seven store-owned descriptors. Filesystem calls are synchronous,
bounded and off MainActor; cancellation is checked around work, not an instant syscall
interruption guarantee. There are no polling loops, timers or addon closures.

### Commit and recovery

Stage creation is exclusive. Short writes and interrupted syscalls are handled; the
candidate file is synchronized before atomic replacement. Final authority, file
identity checks, rename and committed bookkeeping have no intervening await. Before
rename, cancellation or processed revocation preserves the old value. After rename,
the new value is visible; a containing-directory sync failure returns
`committedDurabilityUncertain`, retains the new record and charge, and requires a real
read of that key or reconciliation before another stage. It is not a safe automatic
retry signal. Failed staging cleanup returns `cleanupRequired` and retains its full
charge until unlink and the required directory synchronization are confirmed.

Directory existence and its charge are distinct from durability. A failed parent
sync after mkdir remains pending across retry/close. Retry must synchronize that same
managed parent successfully; reconciliation also confirms discovered root/namespace
entries before publishing fresh handles. Already-confirmed ordinary writes avoid
repeating ancestor syncs. These are actual filesystem fsync checks and process-level
recovery tests, not physical power-loss qualification. The trusted host must secure
and establish the supplied root itself, including durability of its entry in unmanaged
ancestors; the backend manages descendants of its held root only.

Close drains the active operation, invalidates handles and closes the descriptor,
but retains durable disk pools and the bounded ledger. Reopening the same backend
reconciles that ledger; a fresh backend admits the whole inventory before cleanup or
capability publication. Abandoned pending files are charged before removal, never
promoted to live data. Failure to admit inventory rolls back only that attempt's growth.
The checkpoint service's older close contract above releases its own reservations;
the host must suspend global storage admission and reconcile all persistent stores
before resuming after shutdown/restart. The coordinator below implements this gate
for host callers; application bootstrap and authenticated transport still need integration.

Root traversal and held-file checks reject symlinks, unsafe types/modes/ownership and
multiple hard links before payload reads. The exclusive root lock coordinates store
instances. The root is private to the trusted host and inaccessible to addon processes;
these checks are not isolation from another compromised process with arbitrary access
under the host UID.

## Global storage admission coordinator

`AddonStorageCoordinator` composes checkpoints, keyed storage and SwiftData archive
inventory behind one internal readiness gate. Its factory requires all three roots
and a fixed, complete registry of1–256 verified identities, including disabled or
uninstalled addons with retained data. Ordinary coordinator metadata is prepaid:
24KiB +1280 bytes fixed plus3KiB per row, with governor bookkeeping separate. All full root URLs
and derived archive child URLs must meet the4,096-byte file-URL bound. Fixed names
and archive slots cannot grow on owner acquisition. The host retains this coordinator
and its governor across logical close/retry.

Before any checkpoint/keyed recovery, startup safely retains the existing archive
parent and records its4KiB allowance on a protected zero-initialized observed token,
attributed to the first fixed registration. It discovers/reconciles every known C1
archive, including absent and inactive owners, storing returned objects before checking
cancellation. Unknown or unsafe outer entries, incomplete enumeration and blocked owner
inventories prevent readiness; known safe owners are still inventoried where authority
permits. Unknown namespaces are neither followed nor attributed to an arbitrary addon.
Inventory does not create a missing owner directory or open a SwiftData container.

Only after this complete raw-inventory barrier does startup open checkpoints, then
open/reopen the same keyed actor and acquire fixed backend owners. Parent identity,
outer membership and no-follow directory/private-ownership checks run after subsequent
startup awaits before a new readiness epoch is published. This is a verified historical
inventory, not an atomic multi-directory transaction or descriptor-confined SwiftData
access. A raw-safe corrupt model can fail its later archive operation without falsely
making every owner's raw inventory incomplete.

Owner capabilities belong to one coordinator and readiness epoch. Raw backends and
backend owner handles remain private; competing operations fail instead of joining an
unbounded queue. Close revokes capabilities before awaiting cleanup and reports draining
while accepted work is active. The host retries close after that work returns. Logical
closure retains archive slots, the shared parent open-file description and protected
root/owner ledgers; reopening does not duplicate their charges or contend with retained
parent locks. Created files are never refunded merely because a worker is suspended.
The existing ordinary coordinator metadata is not claimed protected against external
`releaseAll`; coordinator cleanup itself never uses that broad operation.

This primitive does not support an empty or changing retained registry. Application
bootstrap, dynamic installation, authenticated SDK transport and process qualification
remain separate. Concrete coordinator/runtime save and restoration forwarding is implemented below;
inventory alone does not activate a publication or launch a provider.

### Integration still required

The backend has 38 focused keyed/resize tests and passes the 474-test serial package
run after independent review. Native authenticated storage transport is pending:
65,536 value bytes plus the key cannot fit the unchanged 64-KiB generic service payload.
Dedicated request/response contracts and a Foundation JSON codec now provide a
192-KiB frame for full values, exact UTF-8 keys and bounded failures. Optional protocol
1.1 negotiation is implemented; existing operational callers still use 1.0. The host
must install authenticated dispatch and negotiate the canonical capability before SDK
storage can be claimed operational. Correlation alone is not authorization; the final
transport must preadmit buffer lifetimes and enforce its complete 512-KiB envelope.
See the [frame evidence](../superpowers/verification/2026-09-13-addon-keyed-storage-frames.md). Authenticated asset transport and qualified external
migration remain separate C5 work. Internal publication restoration and notice replay
protection are implemented in the runtime archive section below.
No production launcher, distribution signer or minimum-OS qualification follows from
these filesystem tests. See the [C5b evidence](../superpowers/verification/2026-09-12-addon-keyed-storage.md).

### SwiftData restart archive qualification

The user selected SwiftData for the separate publication/asset restart archive.
The [selected design](../superpowers/specs/2026-09-13-addon-swiftdata-archive-design.md)
uses private host storage, explicit saves, no CloudKit/autosave and immutable values
at the runtime boundary. The native probe in
`Prototypes/AddonPlatform/SwiftDataArchive` exercises real save/reopen, rollback,
unsaved changes and repeated-write file growth. It is not a production storage client.

SwiftData-managed DB/WAL/SHM and history bytes cannot be counted merely as the latest
payload. The evaluated macOS 14 API does not establish a maximum file growth before
a save, and post-save size checks do not satisfy the existing preadmission rule.
The user explicitly approved an
[observed disk policy](../superpowers/plans/2026-09-13-addon-swiftdata-disk-policy-decision.md)
for these framework-managed files: inventory after operations, retain the complete
measured charge even above an owner/global ceiling, and block subsequent writes
until reconciliation shows the debt is gone. This is not a bounded overshoot
guarantee. Application-controlled buffers and candidate payloads still need strict
admission, and the macOS 14 floor is unchanged.

The common governor now has an internal opaque observed-disk token tied to one
governor, owner and lifetime. Initial positive bytes and positive growth are strictly
admitted; checked expected-size reconciliation can record actual growth beyond
quota. Status reports canonical bytes and owner/global overage. Data and cache
growth check both owner and global disk debt, including growth through ordinary
reservations. An unrelated owner's local debt does not block another owner unless
a global ceiling is exceeded.

Generic release, owner cleanup and state/disk resizing cannot refund these protected
entries. Only this token's truthful measured shrink changes its disk charge; final
release requires measured zero. Optional retained actor/root metadata shares the
protected lifetime and is strictly admitted to state and memory. A zero-byte token
can admit metadata under existing disk debt so newly discovered retained files can
be counted; it grants no permission to write. The token does not inspect files,
authorize deletion or make incomplete inventory safe.

The internal owner-bound `SwiftDataArchive` backend is implemented and independently
reviewed against this governor boundary. Its 18 new tests plus adjacent governor
tests pass (44 tests total). The combined runtime restoration delivery passes 679 serial package tests, with a signed
build and verified restart. Production startup must
include every retained archive root in the complete-registry admission barrier before
normal persistence is exposed. The fixed-registry coordinator inventory is implemented and independently approved;
concrete runtime forwarding is independently approved and included in that delivery.


### SwiftData owner backend contract

Each persistent archive binds one verified identity, private root and common governor.
`make` strictly admits 16 KiB of retained actor/root metadata plus governor bookkeeping,
locks the existing private root and records its raw inventory without opening SwiftData.
Failed inventory or overbudget discovery preserves the returned object and its ledger.
Keep both alive across retries and logical suspension. Dropping the object releases
its descriptors, but does not refund retained files or promise physical database close.

`discover` also supports an owner whose derived private directory does not yet exist.
It retains a duplicate of the caller's already-held parent open-file description and
the same protected zero-byte token with16KiB lifetime metadata. It creates no directory
or container. Only checked descriptor-relative absence is accepted as zero inventory;
unsafe, busy, replaced or incompletely measured paths stay blocked and conservatively
charged. Once a child descriptor has been held, deletion or replacement cannot turn
it into a fresh absent archive. Sibling archives share the parent lock description.

The first `start` strictly prepays the4KiB directory allowance on that same token before
creating a missing directory, then observes both success and failure. A proven still-
absent path may refund unused prepayment; a created directory stays charged even if
framework startup later fails. Parent replacement after a completed scan preserves all
newly known bytes as well as previous charges. `inventoryStatus` is a separately
reconciled raw-files snapshot: a fully inventoried corrupt model may fault archive
operations while its raw status stays complete. The coordinator must refresh this
inventory before publishing normal storage access; status is not lasting authority.

`start` opens a private ModelActor worker with CloudKit disabled, autosave disabled and
no undo manager. Each operation uses a fresh local ModelContext; model objects do not
escape. One row stores the namespace, schema 1, positive UInt64 revision, bounded verified
digest, at most 8 MiB opaque Data and a domain-separated SHA256 checksum. Revision text
is canonical decimal to preserve the full unsigned range. A save requires the expected
previous revision and a strictly larger new revision. Unknown schema, corrupt checksum,
foreign namespace, duplicate rows or invalid metadata fail without exposing a generation.
The runtime separately checks its current installed digest and feature authority.

Strict disk prepayment is existing measured files plus 1 MiB estimated framework
workspace and 4 KiB envelope/store allowance; saving also prepays the full candidate
payload. Actual post-operation inventory replaces estimates. Every logical file length
and 4 KiB per file/directory count, including unexpected regular files and bounded
unknown subdirectories. Unsafe or incomplete scans preserve at least the previous
charge and all known bytes, including larger opened-file measurements, until a complete
safe scan can justify shrink. Unknown/unsafe entries block normal use and are never
repaired, truncated or deleted automatically. This is logical quota accounting, not
APFS allocation measurement or a sandbox against arbitrary host-UID access.

`withGeneration` keeps a protected temporary-memory reservation through its host
callback. The callback must not retain the payload afterward; this internal contract
is not enforced by Sendable. Opening/reading reserves two maximum payloads plus 64 KiB
control memory. Saving reserves one maximum old payload plus twice the actual candidate
size and 64 KiB control memory. Original caller buffers and restoration allocations are
separately admitted. Framework-internal cache/RSS is not a hard footprint guarantee.

Only one operation runs at a time; competing operations fail rather than queue.
Suspension invalidates admission before awaiting work and keeps the worker, lock and
ledger. A known successful save returns its committed revision even if subsequent
observation reports overbudget, faulted or suspended. A failure before commit rolls
back unsaved context changes and still inventories files. An already-open valid archive
can be read under disk debt, while subsequent saves and new framework opens require
strict admission. Status values are observations, not continuously refreshed telemetry.

Backend tests use actual SwiftData stores and fresh same-process containers; the
separate native probe supplies cross-process save/reopen evidence. The available host
runs macOS 27 with deployment target 14; macOS 14 execution, arbitrary native save failures
and power-loss durability have not been qualified.

### Canonical restoration preparation

`PublicationState` has an internal bounded visitor for the owner's canonical archive
records. It preserves the complete timeline, latest revision, publication kind and
original session deadline. Notices are excluded; elapsed or explicitly ended content
is represented by terminal history rather than a replayable publication. Capture
cannot recover history already pruned by the runtime.

Restoration preparation validates the whole candidate against the verified namespace,
current state, byte/family bounds and original deadlines without changing live state.
Namespace binding and record activation happen only in the final synchronous commit.
The prepared value is tied to both the state's revision and its mutation nonce, so
divergent copied states cannot exchange proposals with different accounting. Preparation
does not create a provider connection, sequence or serialized-handle authority.

These reviewed primitives pass25 focused/adjacent publication tests and are composed
with asset reconstruction and host assignment admission in the runtime APIs below.
The internal runtime boundary does not establish production application startup.

### Bounded archive values

The internal `RuntimeArchiveEnvelope` uses Foundation binary property lists with fixed
positional rows. Recursive publications live in separate JSON Data leaves decoded by
the existing contract types. UTF-8 metadata and UUIDs are bounded Data leaves; row
counts and declared leaf sizes are checked before materializing their values. Unknown
versions, extra slots, invalid lengths and dangling/cross-partition asset references
are rejected. The format is host persistence, not a provider transport or authority grant.

A generation permits at most 16 records including terminal history, 8,192 alias-table
occurrences, and the existing raster coordinator's slot limit. All Data occurrences
share an 8 MiB aggregate cap, including repeated references to the same binary-plist
object. Each publication JSON body is at most 266,240 bytes; raster layout remains
tightly packed RGBA8 with at most one million pixels. The complete encoded payload
must also fit 8 MiB, independently of its leaf-byte total.

The contract decoder checks tree depth/node limits and array limits before decoding
additional elements. Content and timeline remain mutually exclusive, with that check
performed before either graph is built. All existing semantic validators and valid
revision zero remain. `inspect` decodes and drops one publication at a time, returning
a checked structural memory quote for the separately admitted complete restoration.
These synchronous helpers admit no resources themselves: callers must hold input,
envelope, inspection, decoded-graph and native-raster reservations across their actual
lifetimes. An individually valid archive can still exceed the remaining common budget.

The codec and all contract tests pass (63 tests across seven suites). Independent
production review and a scoped test review are complete; a mutation test proves that
aggregate leaf rejection precedes decoding an excessive later scalar. Runtime capture and activation are implemented by the separately reviewed host APIs below.


### Coherent runtime archive save

`AddonRuntime.saveArchive(owner:to:)` accepts only the current installed, enabled
identity and an archive using the same resource governor. It holds the runtime's
single admission while reading the prior scalar archive revision, capturing canonical
publication records and validating their current feature authority. Capture includes
full timelines and terminal history, preserves the original session deadline, and
excludes notices. Save uses a checked next archive revision and compare-and-swap;
a conflict does not silently overwrite another generation.

Canonical asset pins remain capturable after their import handle has been revoked.
The save deduplicates native backing identity only within its privacy partition,
then copies tightly packed RGBA pixels through the existing raster archive actor.
Publication JSON and metadata cross asynchronous boundaries under protected memory
reservations; the decoded publication graph does not. Capture and encoding workspaces
are released before the separately prepaid SwiftData save, while the encoded payload
remains charged through the backend handoff.

Authority is checked after suspension points and before backend handoff. Once the
backend reports a known commit, cancellation, disable or stop cannot convert that
outcome into an apparent rollback. The current runtime API supplies coherent host
capture; the fixed complete-registry coordinator is implemented below, while
application wiring remains separate. The focused save evidence covers real SwiftData, shared and isolated rasters,
full timelines, terminal history, quota refusal and cancellation around commit.


### Atomic runtime restoration

`AddonRuntime.restoreArchive(owner:from:)` returns only an empty result or the committed
archive revision and active/terminal counts. It checks current installed identity,
executable digest, enabled features and the shared governor. It creates no provider
connection. A missing generation keeps restoration available; an existing generation,
even empty, seals the owner after successful activation. Ordinary assignment and every
accepted provider start also permanently seal restoration for that runtime lifetime.
Stopping, disabling or pruning content does not make an old archive replayable.

The load separately admits the backend read, shallow envelope, inspection scratch and
decoded graphs. Every original publication is validated, including elapsed content.
A fixed timestamp governs both the persistent-memory quote and canonical preparation;
final validation rejects clock rollback or newly expired content. Assignment metadata
is retained for terminal history too. Pending metadata remains charged during deferred
cleanup, and only live canonical records allocate native rasters and active families.

Restore rewrites all content variants and complete timelines with fresh publication
asset aliases and fresh isolated privacy groups, preserving original revisions and
session deadlines. The final synchronous commit performs all fallible checks first,
then installs assignments, namespace, publications, direct asset pins and family permits
together. A refusal activates nothing; native pixel refunds follow actual image lifetime.
No restored notice, command or renewed eight-hour activity anchor is introduced.

The reviewed implementation passes102 focused/adjacent tests across ten suites, including
fourteen restoration tests. Complete-registry admission and concrete forwarding are
implemented below; these host APIs alone do not wire application bootstrap or
authenticated SDK transport.


### Concrete runtime archive operations

The fixed-registry coordinator exposes internal `saveArchive(owner:runtime:)` and
`restoreArchive(owner:runtime:)` operations. It validates the exact Owner epoch and
current runtime binding before lazy archive creation, then revalidates after startup
and immediately before runtime handoff. Only bounded scalar results leave the
operation. Close revokes new calls immediately while accepted work drains; after a
known save commit or completed restoration, nonthrowing cleanup preserves that result.
Existing keyed/checkpoint operation checks retain their previous semantics.

[Combined verification](../superpowers/verification/2026-09-13-addon-swiftdata-runtime.md)
covers real fresh-runtime restoration, postcommit close/cancel and actual shared-image
lifetimes. Production event-loop/bootstrap wiring remains a separate integration step.


### Significant-event archive flushing

The runtime marks committed non-notice publication changes, endings, actual expiry and
terminal-history removal with a fixed per-owner scalar generation marker. Notice-only
traffic, projections, rejected output and unpublished image aliases produce no archive
demand. A captured generation is acknowledged only after its known save commits;
newer changes during the save remain pending. Restoration establishes a clean baseline.

The internal coordinator `flushNextArchive(runtime:)` makes at most one attempt, using
a round-robin cursor across its fixed registry. A failed accepted attempt remains dirty
as `retryRequired` but is not repeatedly retried by ordinary calls. A new significant
change or the existing explicit save provides a retry opportunity. Pre-admission busy
and wrong binding consume no runtime attempt. `noCommit` means this call saved nothing;
it does not assert every plugin is clean.

Progress adds 256 bytes per runtime owner on the tested ABI, 256 fixed coordinator
bytes and 128 bytes to the existing output scope. Pending state retains no publication
graphs or pixel buffers. [Verification](../superpowers/verification/2026-09-13-addon-archive-event-flushing.md)
covers 694 serial tests, signed build and verified restart. The production host must
call this internal operation from its event driver; automatic app wiring and bounded
shutdown composition are separate integration work.


### Bounded shutdown checkpoint

The internal runtime can enter one-way quiescence with an explicit monotonic deadline.
Ordinary admission, connected callbacks and public publication/image lookup close
immediately; private canonical state remains charged for a checkpoint. Disable still
removes that owner's authority immediately. The coordinator retains a separate shutdown
context without overwriting an already accepted operation and offers one pass over the
fixed registry. Busy before admission consumes no row; a failed accepted attempt consumes
its opportunity. A newer change on an already visited owner does not restart the pass.

The deadline gates new runtime work and final handoff to SwiftData. A backend call already
handed off may commit afterward; its known result and protected resource charges survive
logical stop. No hard native-write completion deadline is asserted.

`finishArchiveShutdown` obtains a logical stop receipt without waiting for backend cleanup.
The synchronous `requestClose` revokes coordinator admission only; it cannot synchronously
revoke authority on the separate runtime actor. Later explicit `close` reuses runtime.stop
and the existing backend cleanup, reporting draining while known cleanup remains pending.
Returned process counts describe retained records, not observed physical process exit.

The shutdown controls add 256 bytes per runtime owner and 1024 fixed coordinator bytes on
the tested ABI, before retention; logical stop needs no fresh reservation. [Verification](../superpowers/verification/2026-09-13-addon-archive-shutdown.md)
records 710 serial tests, signed build and verified restart. Production lifecycle-driver
wiring remains separate from these stepped internal operations.


### Concrete keyed-request outcomes

`AddonStorageCoordinator.executeKeyedRequest(_:owner:)` uses a current fixed-registry
Owner and the data namespace only. It returns a bounded read, acknowledgment, definite
refusal or outcomeUnknown. Pre-call readiness/Owner/cancellation failures do not invoke
the backend. Reads recheck authority after the backend returns before releasing data.

A successful write/remove retains its acknowledgment even if coordinator closure or
cancellation happens during final cleanup. Every thrown mutating backend call after
handoff is conservatively outcomeUnknown; this does not prove a mutation occurred or
permit automatic retry. Later transport authorization remains separate from that known
local result. Existing generic coordinator operations retain their previous semantics.

No new permanent coordinator state, request history or reservation is added. The caller
must prepay request/read-result retention through later handoff; the conservative value
allowance is two 65,536-byte buffers plus 4 KiB, separate from raw frames/parser/output
and the existing 267,776-byte backend scratch. This method provides no wire profile,
storage permission or native SDK authentication. See the [reviewed evidence](../superpowers/verification/2026-09-13-addon-keyed-storage-outcomes.md).

### Authenticated host request handling

The internal runtime accepts raw storage frames only through its installed storage adapter
and coordinator, with the same resource governor. It validates the stored canonical
connection/profile and both declared and host-granted storage permission before transfer.
A caller cannot elevate a legacy connection by substituting nested session handles.

Storage shares exact ingress and delivery ownership with action/source/service traffic.
Increasing connection sequences prevent reused frames; no reply history or retry cache is
retained. A protected 8 MiB scope covers raw frames, values, encoding and compact reply
handoff; accepted replies stay in the prepaid 256 KiB adapter slot until their exact receipt
or teardown. Successful backend mutations remain known even if reply delivery is revoked.
Default protocol 1.0 retains zero storage ingress and its existing 80 KiB delivery capacity.

The runtime holds the coordinator weakly to avoid a shutdown-context cycle; an accepted
operation holds it strongly until completion. The [verification](../superpowers/verification/2026-09-13-addon-authenticated-storage-handler.md)
records 765 passing tests, signed build and verified restart. Production native transport and authenticated bootstrap remain prerequisites for
operational external plugin storage; the concrete injected-channel SDK client is described below.

### SDK request lifecycle

The internal SDK lifecycle tracks one pending scalar ticket per connection generation and
reuses the existing C6 validation. It accepts an exact reply during attempted or confirmed
handoff, so a reply can precede the asynchronous send observation. Foreign, stale or
mismatched replies cannot consume newer work.

Cancellation before handoff retires the ticket. Cancellation after possible handoff keeps
the slot occupied until the exact reply, proven pre-handoff rejection or logical close.
Reads report cancellation; write/remove report outcomeUnknown. No automatic retry follows.
Close in this scalar helper revokes authority only; the concrete channel separately drains
real buffers and receipts. The helper retains no key/value/request/response or history.

The [delivery evidence](../superpowers/verification/2026-09-13-addon-sdk-storage-lifecycle.md)
records 781 passing tests, signed build and verified restart. This helper is an internal
prerequisite reused by the concrete SDK message client below.

### Concrete SDK message client

`MessageAddonStorageClient` implements the public `AddonStorageClient` read/write/remove API over an injected `AddonStorageMessageChannel`. Its concrete `close()` revokes local result authority and awaits a shared physical channel drain. Inject the client into `AddonContext.storage` only after the host has established the authenticated connection and admitted the surrounding allocation lifetime. No production OS channel or bootstrap is supplied by this API.

Storage messages retain schema 1 and profile `.v1_1`. Canonical protocol 1.1 and cumulative 1.2 use that same syntax; unsupported 1.0 fails before exchange. Existing exact-byte key, value and raw-frame bounds apply. Missing values return nil; present empty values remain Data(). Host storage uses the data namespace, without exposing a cache choice to the addon.

The trusted channel correlates the physical generation and sequence, consumes the exact host response receipt, and disposes transport-owned staging before returning reply bytes. The SDK checks the bounded encoded response and its request UUID/operation; physical receipt and generation proof are not contained in those public bytes. The `rejectedBeforeHandoff` exchange result is a specific request-side observation: no host processing/backend execution occurred. A refused reply after a successful write, a generic exception or cancellation cannot establish that fact. The client never automatically retries.

A single whole-operation slot spans encoding, exchange, response validation and any required drain. Clearing the scalar lifecycle ticket does not free that slot prematurely. Cancellation before handoff prevents sending. If cancellation wins after possible handoff, a read is cancelled and write/remove remain outcomeUnknown; an eventual reply is drained. If an exact response is consumed first, a later cancellation does not rewrite its known result. Explicit close and final result delivery are ordered together: close winning after validation prevents result delivery and waits for physical drain; it does not prove a known host mutation was rolled back.

Malformed or mismatched replies, channel generation/profile drift and generic exchange failures permanently revoke the client and trigger the same shared drain. An exact validated host failure preserves its bounded code/reason without poisoning a healthy channel. Close does not observe process exit or release process reservations.

Allocation admission remains an embedding responsibility. Source arguments already exist before the call, and a small Data view can retain a larger backing allocation. Admit source, encoding/decoding workspace and returned-value retention before construction/encoding; channel drain does not deallocate caller-owned results. The runtime integration fixture uses a protected outer SDK allowance, separate from host/backend scopes, and keeps returned Data inside that paid scope. This demonstrates the embedding order, not a measured Foundation/RSS bound or an allocator built into the public client.
