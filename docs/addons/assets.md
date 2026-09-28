# Image decoding and memory ownership

`AssetRasterBacking` and `AssetDisposalCoordinator` form an internal host primitive that gives a raster image a lifetime independent of the
producer wrapper. The runtime now owns canonical import aliases and publication
pins through `AssetState`; the SDK exposes the matching asset client and metadata contracts. The
message-based path from `AddonAssetClient` to canonical `AddonRuntime`/`AssetState` is
implemented and exercised against a real host test bridge; a production OS transport is
still deliberately absent.

## Input and execution

The host supplies trusted, already-decoded immutable pixels with an accounting owner
and positive dimensions. The fixed format is tightly packed premultiplied RGBA8,
byte-order32Big, sRGB, four bytes per pixel. Dimensions, checked multiplication and
exact input length are validated before destination allocation. The maximum is
1,000,000 pixels (4,000,000 bytes). No compressed image or provider path is accepted.

The caller accounts for its supplied Data, including overlap during creation. The
factory admits and allocates one separate fallible destination and constructs real
CGDataProvider/CGImage objects outside MainActor. The returned object exposes neither
a mutable pixel pointer nor governor release authority. This does not measure private
framework/GPU copies or the complete resident footprint of the process.

## Shared admission and actual lifetime

Raster bytes count against both asset and aggregate admitted-memory ceilings in the
existing ResourceGovernor. Protected backing admission additionally counts 4,096 bytes
for per-backing context, slot and disposal bookkeeping against admitted memory and
retained state. The governor entry adds its existing 1,024 retained-state bytes.
Thus a backing with N pixel bytes occupies N asset bytes, N + 4,096 admitted-memory
bytes and 5,120 retained-state bytes. No ceiling is raised.

Dropping a producer wrapper or replacing a logical image does not refund pixels that
remain referenced by an image consumer. The final real provider callback disposes the
pixel allocation. Quotas remain occupied until the exact protected reservation is
refunded by the common governor. General single/bulk release cannot bypass that
lifetime. A stale, duplicate or foreign lifetime token cannot free unrelated data.

## Bounded disposal and close

One coordinator belongs to the host runtime. Its empty fixed control state is part
of the host baseline; proportional slots and work are admitted before allocation.
There is one in-flight factory admission and a maximum of 1,638 slots, also subject
to the actual shared governor limits. Concurrent creation fails with busy instead
of accumulating an unbounded waiter queue.

Callbacks mark their existing slots. A single shared drain refunds disposed backing
reservations without a per-image task, polling timer or full-table drain copy. Intrusive active
and pending links avoid retaining a table sized to a historical peak. Pending
or stalled refunds conservatively keep quotas occupied. Refund failure remains
observable and charged instead of being reported as successful cleanup; the active
host must retain and inspect a faulted coordinator. One asynchronous observer at a
time may await a captured pending watermark; concurrent observers fail with busy.

Close rejects new creation and invalidates in-flight return authority. It neither
refunds live buffers nor waits for unknown external consumers to release images.
Provider contexts and pending disposal keep the coordinator alive for cleanup,
without a slot retaining an image/provider/context cycle. Cancelling a completed
creation cannot refund an image still in use. Synchronization covers pending disposal,
not the lifetime of arbitrary external references.

## Bounded encoded-image decoding

`AssetImageDecoding` now has an internal host implementation,
`BoundedAssetImageDecoder`. It uses Apple's ImageIO and CoreGraphics, then hands
normalized pixels to the existing raster coordinator. It accepts complete data,
not provider paths or URLs. Callers still own and account for their original Data.

The supported profile is PNG or JPEG, at most 1 MiB encoded and 1,000,000 pixels,
one frame, upright orientation, RGB with 8-bit channels, and native sRGB. Grayscale,
CMYK, wide-gamut/HDR, animation and other formats are rejected. Source metadata is
not attached to the returned image. A fixed check requires the expected signature
and terminal bytes; ImageIO performs the actual format inspection and decoding.
This check does not independently validate chunk boundaries, CRCs, or bytes after
an earlier terminal marker. Native completion is checked after drawing too:
ImageIO can report a complete source before deferred pixel decoding discovers a
truncated scan. This is a narrow import profile, not a separate container validator.
Apple documents the default deferred decoding behavior under
[`kCGImageSourceShouldCacheImmediately`](https://developer.apple.com/documentation/imageio/kcgimagesourceshouldcacheimmediately).

One decoder belongs to the runtime. Its synchronous admission gate rejects busy
calls before they can retain input in the worker queue. ImageIO inspection and
CGContext normalization run on a worker actor outside MainActor. There is no
polling, per-image dispatch queue, custom compressed codec, or new package dependency.

Before source inspection the canonical governor reserves 10,162,688 temporary
bytes: two 1 MiB encoded/bridging allowances, 8,000,000 bytes for decoded/normalized
overlap, and 65,536 bytes for control work. The ordinary 1,024-byte reservation
entry charge also applies. Final raster pixels have their own protected reservation.
Owner-wide cleanup cannot refund this temporary scope while decoding is in flight;
the scope ends after the worker returns and releases its staging. Errors, closure
and cancellation discard pending output without refunding a live raster.

The temporary allowance does not impose a hard bound on ImageIO/CoreGraphics
private allocations or codec CPU time. Cancellation cannot interrupt a synchronous
native codec. Hostile-decoder process isolation and resource qualification remain
separate from this internal service. Accounting owner identity still grants no
permission to read or publish private content.

## Message chunks and bounded assembly

The dedicated `AssetTransferRequest`, `AssetTransferResponse` and
`AssetTransferFrameCodec` use Foundation for schema-1 begin/chunk/finish/abort/share/release
messages. Raw chunks are at most 65,536 bytes, total encoded input at most
1,048,576 bytes, and each dedicated JSON frame at most 196,608 bytes before
parsing. The explicit `.v1` profile describes schema-1 syntax; trusted runtime
negotiation enables that profile with cumulative protocol 1.2. Existing publication and asset-handle validators are reused.

`BoundedAssetTransferAssembler` is an internal single-slot primitive bound to an
immutable incarnation, connection, publication and assignment. It accepts only
exactly ordered full chunks and the final remainder. Its nonrenewable 30-second
monotonic deadline requires an explicit host expiry call; it creates no timer,
queue or disk staging. The runtime services its deadline and explicitly disposes
revoked transfers. Publication end or expiry revokes the exact transfer without
closing the process assembler; another authorized assignment can reuse it after
old cleanup completes. Connection/process shutdown closes it irreversibly.

Before allocating its fixed buffer, it reserves `2 * totalBytes + 4096` temporary
memory bytes through the decoder's existing governor, plus the existing 1,024-byte
reservation-entry charge. Generic owner cleanup cannot refund this protected
reservation. The existing shared ImageIO decoder and independently protected raster
backing retain their own charges. Closing or cancelling during native decoding
revokes return authority while memory remains charged until the work ends.

The primitive alone does not authenticate assignments or publish aliases. The
runtime integration below supplies those responsibilities, protected parser/envelope
workspace and aggregate expiry scheduling. The
[assembler verification](../superpowers/verification/2026-09-14-addon-asset-chunks.md)
describes the underlying component boundary.

## Authenticated message integration

The runtime now exposes authenticated asset-message ingress and exact reply receipts
in the same shared transport slot as publication, storage and action work. Protocol
1.2 is cumulative: a trusted host advertises it only when keyed-storage frames and an
asset-capable runtime adapter are both present, otherwise defaults stay 1.0 and
storage-only assembly stays 1.1. `share` and `release` extend the closed schema-1
frame with an optional nested source handle; a `shared` result reports the fresh
target alias, and a release success is a transfer-free `acknowledged` reply.

Each process incarnation owns one prepaid `BoundedAssetTransferAssembler` and at most
one scalar binding/transfer. Begin derives that binding from the canonical assignment
(incarnation, exact connection token, publication and immutable `assignmentToken`);
chunk/finish/abort reuse the host-retained binding and revalidate the canonical
assignment after every suspension. The asset sequence is per canonical connection,
strictly increasing and updated immediately after the authenticated parse. Ingress
bytes are checked against the launch's `maximumAssetIngressBytes` and the actual
count before mutation; the reply is reserved before the operation and freed only by
its exact receipt. Asset frames do not require a storage-ownership grant, and the
assembler's nonrenewable 30-second monotonic deadline is serviced by the runtime's
one aggregate asset key. Stop/exit/disable and exact connection close revoke
assembler return authority synchronously while a live native decode keeps its own
cleanup. Failed protected refunds retain the sole cleanup token for a later bounded
drain; logical revocation never proves physical disposal.

Normal connection close revokes its publication session and import authority,
stops that exact incarnation and drains staged traffic. Durable publications and
actual image pins survive; unpinned imports are released through their existing
backing lifetime. Closing an obsolete or foreign connection cannot close its
replacement. Owner disable is a separate operation that removes durable state.
Already-requested process stop and archive quiescence do not replace connection
cleanup. Physical provider and uncertain handed-off work remain charged until the
appropriate actual exit/completion observation.

The public `MessageAddonAssetClient` drives import, share and release through an
injected `AddonAssetMessageChannel`. It holds one whole-operation slot across all
awaits, issues strictly increasing sequences with fresh request UUIDs, validates
every response and poisons itself on a malformed reply or transport exception.
The channel owns physical generation/sequence correlation, exact receipt consumption
and bounded request/reply disposal before returning from an exchange. Its close must
revoke the connection and join outstanding physical exchange work; cancellation alone
is not proof of disposal. All SDK close/poison callers join one shared channel drain.
Explicit close revokes future calls and is checked both at exchange boundaries and
at successful operation finalization. Finalization and close use the same lock: if
close wins, the operation retains its slot through the shared drain and throws
`sessionRevoked`, even after response validation. If successful finalization wins,
a subsequent close does not retroactively change that completed result.
Cancellation alone preserves a validated successful finish/share/release result;
uncertain mutations are never retried.
The channel is bytes for an already-authenticated connection: it is not an authenticated
bootstrap, and no repository component installs an OS transport. The end-to-end
evidence is a test-only bridge over the real runtime, codec, assembler, ImageIO and
`AssetState`; it does not qualify a native adapter, launcher or macOS 14 runtime.

## Canonical publication ownership

`AddonRuntime.importAsset` accepts self-produced encoded data only for a publication
assigned by the host to the current authenticated connection. The scope includes
verified publisher/addon, executable digest, feature, exact PublicationID and
connection token. Scope is checked again after asynchronous admission and decoding.
An accounting owner alone grants no access. `ContentDocument.Privacy` describes
redaction, not authorization; existing service permission partitions remain a separate
broker authority. This path introduces no service-derived assets or shared cache across addons.

Every successful import returns an opaque `asset-<UUID>` alias and immutable raster
revision 1. Publishing pins the actual backing for the observed publication revision.
All declared IDs count, including currently undrawn references, all five presentation
slots and every retained future timeline entry. The scan uses the admitted canonical
publication, including host lifetime caps, rather than only the current visible entry.
A reference imported for another publication or connection rejects the whole output;
publication state and sequence are not partially advanced.

Asset proposals and canonical publication state validate and commit in one synchronous
runtime turn after resource admission. Import metadata, binding metadata and temporary
proposal overlap use the existing common owner state pool. Fixed charges are 4,096 bytes
per import, 2,048 per binding and 1,024 per distinct pinned alias; conservative proposal
quotes count duplicate references too. Removal-only proposals use the existing
metadata allowance, held until commit finishes; a mixed proposal still prepays every
new pin without subtracting planned refunds. The native raster charge remains separate and
protected until actual disposal. Assetless output needs no asset metadata allocation.

`AddonRuntime.releaseAsset` relinquishes an exact scoped import alias without ending
the publication. It cannot authorize a future revision after release. Provider exit
revokes all its import aliases, while published images survive through their pins. A new connection must import fresh aliases to publish a new revision. End, expiry,
disable and host stop remove logical authority. Retained CGImage consumers can still
own physical pixels; logical revocation never pretends those bytes have been freed.

`AddonRuntime.assetImage` uses the trusted runtime clock and exact PublicationID and
publication revision. A stale view cannot request an earlier instant or silently read
an image from a replacement revision. The presentation resolver forwards the revision
captured when that view was built. A production snapshot handoff to the MainActor
renderer is still required; the default presentation resolver remains empty.

## Explicit sharing and the SDK

`AddonRuntime.shareAsset` and the public `AddonAssetClient.shareAsset` issue a fresh
alias for the target publication over the source's existing immutable raster. The
source and target must belong to the same verified publisher/addon, executable digest,
current connection and host privacy partition. Sharing can cross feature boundaries,
including widgets and activities. Directly using a source alias in another publication
still fails: the host must first issue the destination's scoped alias.

Pixel memory and decoder work are not duplicated. Each new alias reserves the existing
4,096-byte import metadata charge; each published binding retains its usual metadata
charge. Releasing or ending one publication leaves the other aliases and pins intact.
The final actual CGImage reference controls pixel disposal. Sharing cannot revive an
expired, released or previous-connection source through its remaining publication pin.

Host publication assignments carry an immutable `AssetPrivacyPartition`: `.addonOwned`
for ordinary self-produced data or `.isolated(UUID)` for host-separated contexts.
Compatible isolated assignments share the same host UUID. A partition is not accepted
from the provider, encoded in AssetHandle, inferred from ContentDocument.Privacy, or
changed by repeating an assignment request. Future service-derived asset paths must
use canonical broker permission/source partitions; these host labels do not establish
service grants or track the provenance of arbitrary bytes produced by native code.

`CascadeContracts.AssetHandle` contains alias ID, owner, PublicationID, raster revision,
dimensions and byte count. It validates owner consistency, identifier syntax, positive
revision, at most one million RGBA8 pixels and exact byte count. `decode` checks its
8 KiB raw metadata cap before Foundation parsing and requires exactly its defined
fields. A constructed or decoded handle is metadata only, never proof of host authority.

`AddonContext.assets` exposes an injected connection-bound `AddonAssetClient`:

```swift
let original = try await context.assets.importAsset(
    encodedImage,
    publicationID: widgetPublicationID
)
let activityImage = try await context.assets.shareAsset(
    original,
    to: activityPublicationID
)
// Use original.assetID and activityImage.assetID in their respective publications.
try await context.assets.releaseAsset(original)
```

The existing context initializer remains source-compatible. Without an asset client,
all three asset operations fail with `dependencyUnavailable`, including release.
The SDK contracts do not install a transport or load provider code into the host.

## Archive integration

The reviewed internal restoration primitives now capture canonical publication pins
after import revocation, checking exact owner, revision, expiry and all public/sensitive
references before exposing a backing to the host callback. Direct restoration proposals
reuse admitted backings and the existing 2,048-byte binding/1,024-byte alias metadata
charges. They reject missing, extra, foreign or colliding aliases and create no imports
or provider connections. Proposal authority follows the complete state mutation history,
including divergent copied states.

`AssetRasterArchiveCopy` uses CoreGraphics on its own actor to copy only checked canonical
sRGB/RGBA8 rasters. The caller separately prepays copy scratch and retained output Data;
the original native reservation survives until the last image reference is released.
These primitives and adjacent asset/lifetime suites pass 65 tests with independent review.
Runtime assignment joining, deduplicated persistence and coordinated restoration are
now composed through the internal runtime archive APIs. Save deduplicates native backing
identity only inside the permitted privacy partition. Restore validates the whole batch,
mints fresh per-publication aliases and per-load isolated groups, and allocates native
backings only for live canonical records. Metadata and active families are prepaid before
the final synchronous publication/pin/assignment commit. Failure leaves live state intact;
native charges follow the last actual image reference. The extended restoration group
passes102 covering tests, including14 focused cases, with independent review.

The internal message/SDK path is composed and exercised through a test-only bridge.
Production OS transport and authenticated bootstrap, decoder process qualification,
MainActor snapshot handoff, cache integration and real SwiftUI view lifetime remain open.
These internal APIs do not qualify a native addon launcher, distribution signer or
macOS 14 runtime, and do not complete C5 or the production-readiness record.
