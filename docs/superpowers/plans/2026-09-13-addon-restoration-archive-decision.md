# Restart archive — SwiftData selected

On 2026-09-13 the user selected **SwiftData** and instructed implementation to proceed. This supersedes the GRDB recommendation below, retained as decision history. See the [selected design and qualification](../specs/2026-09-13-addon-swiftdata-archive-design.md).

The user approved asset sharing within a plugin's compatible host privacy scopes.
That implementation is complete. The separate archive decision is now resolved:
SwiftData stores coherent owner generations, and the user explicitly approved
observing internal file overage and blocking subsequent writes. The
[storage plan](2026-09-13-addon-swiftdata-storage.md) tracks implementation; the
[restoration sequence](2026-09-13-addon-publication-restoration.md) specifies fresh
host authority, original lifetimes and whole-generation validation.

## Existing constraints

- Restore only still-valid canonical publications, preserving complete timelines,
  revisions and original absolute activity deadlines. Never replay notices or commands.
- A checkpoint holds at most 64 KiB; a timeline can contain 256 KiB. Extending the
  checkpoint limit or persisting only a projected display snapshot would break the contract.
- Existing keyed records commit individually. They do not provide a transaction
  spanning publication metadata, shared raster blobs and reference ownership.
- Asset aliases and host privacy partitions currently have in-memory authority.
  A decoded `AssetHandle` cannot itself grant access or reconstruct a private scope.
- Quotas, retained registry completeness, revocation and recovery must still apply
  under the common governor. Adding a database does not automatically satisfy these.

## Earlier recommendation — superseded

Use a private host SQLite archive through GRDB for the restoration slice. Store
canonical publication records, durable asset ownership/reference records and raster
BLOBs in the same database transaction, so a committed restoration generation does
not reference an uncommitted blob. Keep this separate from the current SDK keyed
preferences and versioned checkpoint formats; this proposal does not migrate them.

GRDB provides Swift database access, migrations and concurrency support on top of
SQLite; its documented deployment requirements support this project's macOS 14
floor. SQLite supplies the transaction machinery. This direction reuses a library
instead of implementing an additional transaction journal in Cascade.
Sources checked on 2026-09-13: [GRDB documentation](https://github.com/groue/GRDB.swift),
[SQLite atomic commit](https://www.sqlite.org/atomiccommit.html).

After this direction is accepted, first specify and test the archive transaction
contract: verified publisher/addon keys; durable host privacy partition identities;
fresh authorized alias reconstruction; versioning; terminal history; and recovery
of missing/corrupt/unsupported generations. Persist civil dates, never old monotonic
clock values. Private partitions without an authenticated reconstruction rule must
remain unavailable. Existing runtime asset admission is still required before display.

Before production integration, verify bounded database work and account for database
pages, transaction journals/WAL and temporary buffers under the common resource
policy. No physical power-loss qualification or hard allocation ceiling follows merely
from adopting SQLite. No new dependency has been added for this proposal.

## Alternative

Extend the existing file approach with immutable generation files and one atomic
manifest replacement. This retains the current storage technology but requires
Cascade to implement and qualify multi-record recovery, orphan cleanup, reference
accounting and migrations. It is less aligned with the user's request to reuse an
available library for capabilities such as transactions.

## Decision status

**SwiftData selected by the user.** The framework choice is resolved; no GRDB
package or Foundation-only archive was introduced. The reproducible probe has qualified real save/reopen, concurrency and observed
file growth on the available host. The distinct
[observed disk policy](2026-09-13-addon-swiftdata-disk-policy-decision.md) is explicitly
approved. Its protected governor ledger is implemented and reviewed; backend and
restoration integration are tracked by the storage plan. Application-controlled
payload admission remains strict, and macOS 14 runtime qualification is not claimed.
