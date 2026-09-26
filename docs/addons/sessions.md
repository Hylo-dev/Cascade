# Publication sessions and protocol negotiation

`ProtocolOffer` is a closed capability value in `CascadeContracts`. Its offer
schema is 1; `major` is 1...65535 and the inclusive minor interval is
0...65535, with minimum no greater than maximum. `contentSchemas` contains
1...8 distinct identifiers in 1...65535. Initializers and decoding reject
invalid fields; `ProtocolOffer.decode` rejects raw input over 8192 bytes before
JSON decoding. An offer carries no authenticated identity or authority.

`ProtocolNegotiator.negotiate` supports minor 1.0 through the highest capability the
trusted host actually implements. Defaults stay at 1.0; a keyed-storage host may opt
into 1.1, and a host that also provides an asset-capable runtime adapter may opt into
cumulative 1.2. The internal runtime additionally selects cumulative 1.3 only with its complete service invocation handler/adapter, compatible environment and prepaid capacities. Cumulative 1.4 requires the complete control/source/event handler and subscription adapter plus all earlier capabilities, compatible environment and prepaid maximum capacities; partial assemblies retain their earlier selection. Both the provider's interval and the trusted manifest's `ProtocolVersion`
minimum must admit the selected minor. Host content policy may narrow the
library-supported schemas `[1, 2]` to a nonempty subset. The result contains the sorted
intersection with the offer; no common version/schema produces `versionConflict`.
Future offered schema IDs never become supported simply because they appear in the
offer. `storageFrameProfile` reports 1.1 only at minor >= 1 and `assetFrameProfile`
reports the `.v1` asset syntax only at minor >= 2. `serviceInvocationFrameProfile` reports `.v1_3` only at minor >= 3; `serviceSubscriptionFrameProfile` reports `.v1_4` only at minor >= 4. These public capability values alone do not activate a handler. `NegotiatedProtocol` is immutable
and is not a decodable authorization token.

Content schema 2 requires explicit negotiation, including documents with
absent or empty `glassLights`. A provider needing lights can offer only schema
2. The host neither strips lights nor relabels schema 2 as schema 1.
`ProviderOutput.validateContext(..., contentSchemas:)` checks every document
in all five immediate representations and every future timeline entry. Its
source-compatible default `[1]` is conservative. Context validation also keeps
owner, increasing revision and completion correlation checks; values alone do
not authenticate a peer.

## Canonical host boundary

`PublicationStore.openConnection` takes a host-verified `VerifiedAddonIdentity`,
exact verified digest, trusted manifest protocol, provider offer and host-assigned
publication IDs. Signature, audit token, process and manifest verification must
precede this call; this component does not perform them. Publisher and digest
are nonempty and at most 512 UTF-8 bytes each. Authorized IDs must be unique,
belong to the verified addon and number at most 16; zero IDs is allowed.
Incoming publications and operations cannot grant or expand this set.

The returned `PublicationConnection` is opaque and not Codable. Its generation
and negotiated protocol are readable, but matching public wire values cannot
construct authority. The store retains the canonical handle. A successful
replacement for the same identity issues a fresh generation and invalidates
the old handle, including when the verified digest changes. A failed opening
leaves the previous connection usable. Handles from another store are rejected.
Closing an obsolete handle does not close its replacement.

An addon namespace remains bound to its verified publisher after normal close.
A different publisher cannot take that namespace until explicit owner removal.
Normal close releases connection authority while retaining current and future
publications, their revision history, and the publisher binding. Reopening
requires host-assigned IDs again and preserves increasing publication revisions.
An explicitly ended publication session remains ended across reconnects.

## Atomic publication state admission

`PublicationStore.acceptPublicationState` takes a bounded `ProviderOutput`, a
canonical connection handle, claimed `ConnectionGeneration`, a nonzero increasing
`UInt64` sequence, and optional host-owned `CompletionExpectation`. It derives
previous publication revisions from its actual records. No caller can supply
replay history. Duplicate, older, zero or wrapped sequences are rejected. Only a
successful batch advances sequence; failed batches preserve bytes, content,
revisions and active authority, and do not automatically retry anything.

Before any publication mutation, admission validates the entire output,
completion correlation, owner, assigned IDs for both publications and
`endPublication` operations, and every negotiated content schema. The existing
bounded batch rollback preserves publication count, byte, lifetime and expiry
policy. Session validation and batch commit occur in one actor operation with
no intervening `await`. Explicit owner removal revokes connection authority
before clearing records in the same actor turn, so old handles cannot recreate
removed content.

The returned `PublicationAdmission` contains structurally validated operations,
completion and checkpoint values. **Only the output's `publications` array is
committed.** No operation is executed, including `endPublication`. The composed
`AddonRuntime` separately authorizes and executes operations, persists checkpoints,
and manages command journal correlation/replay. Completion expectations are trusted
host history, never inferred from the incoming result. Admission does not make
external command effects atomic or authorize services, schedules or leases.

The legacy `accept(_:owner:)` overloads remain trusted host composition
primitives. They are not alternative transport ingress APIs; real transport
must use the canonical connection boundary.

## Component limits and runtime composition

The registry retains at most 32 active connections and 256 publisher namespace
bindings, each host-tightenable down to zero. It charges 4096 bytes per active
connection and 1024 bytes per retained namespace against the store's existing
bounded retained byte budget before insertion. Successful replacement adds no
charge; normal close releases only connection charge. Explicit owner removal
releases namespace and connection metadata plus that owner's publication state.
There are no preallocated frame, checkpoint or completion buffers and no timer,
task or addon/UI calls in this component.

These are conservative local accounting charges, not physical memory readings
or measurements of the globally composed `ResourceGovernor`. The internal
`AddonRuntime` composes canonical sessions with protected admission, shared frame
credits, lifecycle events and asset aliases. Its exact connection close uses
runtime-retained component handles, including after a stop request or during archive
quiescence. It preserves durable publications and image pins while revoking sessions
and import authority; physical and uncertain work charges require actual lifecycle
observations before release. Owner disable remains a separate destructive logical
operation. A stale close cannot revoke a replacement connection.

The pure publication store does not implement signature verification, native process
launch/exit or SDK entrypoint binding. The composed message path is exercised by an
in-process test bridge, not a production OS adapter. Native launcher/bootstrap and
macOS 14 qualification remain separate admission requirements; the internal work does
not open the C0d gate or establish whole-platform readiness.

## Service connection generation composition

Fresh canonically negotiated service1.3/1.4 attachments compose publication and broker sessions with the same host-issued generation before exposing the connection. No issued Grant is rewritten, and matching UUIDs do not replace the opaque canonical handles. Failed attachment withdraws provisional authority and cleans up the exact new session; physical process capacity is retained until its separate exit observation.

Legacy0/1/2 connections and independently registered broker sessions retain their existing generation behavior; default1.0 and complete invocation1.3 selection remain available. The cumulative1.4 composition constructs a real `AddonContext` with canonical ready Grants, actual storage/assets and the injected public `TransportServiceClient` implementing invoke/subscribe/unsubscribe together. Invocation/control share one connection sequence and physical slot; latest events and exact receipts do not establish new authority. Reconnect confirms fresh aliases and Grants while retaining only eligible unexpired host interests and their original deadlines.

The [invocation-host record](../superpowers/verification/2026-09-18-addon-service-invocation-host.md) preserves the earlier invocation-only fixture boundary. The [host and whole-SDK record](../superpowers/verification/2026-09-18-addon-service-subscriptions-host-sdk.md) records the reviewed internal delivery and its limits. Public client injection and modeled composition do not qualify a production native adapter/bootstrap, C0d or macOS14/Intel execution.
