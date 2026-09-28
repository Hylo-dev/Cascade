# SDK storage outstanding-request lifecycle — finite implementation brief

Current status: delivered and independently approved. Final 781 serial tests / 77 suites, 393 identical inputs and 47 reviewed hashes; signed build and normal restart to PID 12667 at 56% weekly use. [Verification](../verification/2026-09-13-addon-sdk-storage-lifecycle.md). The original two-file brief follows.

## Goal and source reuse

Add the internal scalar lifecycle needed by the planned concrete SDK storage client: one connection generation, one pending request, sequence and ticket correlation, explicit handoff uncertainty, cancellation/close, and one-time reply disposition. This is not a transport or a concrete AddonStorageClient. Existing public read/write/remove API and AddonContext are unchanged.

Verified existing sources:

- `CascadeKit/Sources/CascadeAddonSDK/AddonContext.swift` declares AddonStorageClient and injects it; no SDK storage lifecycle/session helper or concrete transport exists in the SDK source inventory.
- Reuse `CascadeContracts.ConnectionGeneration` (descriptive UUID value), `StorageOperation`, `StorageRequest.validate()`, `StorageResponse.validate()`, `StorageFrameProfile` and existing AddonFailure.Code. C6 already owns shape/key/value/result/failure limits; do not duplicate those checks.
- `StorageResponse.validate(matching:)` requires the whole request. Retaining that request would retain write Data, so this helper instead calls the two existing validation methods at their respective entry points and compares only the stored requestID/operation scalars itself. Do not manufacture a fake request/key/value just to invoke the matching overload, or add another Contracts API.
- Host PublicationSessionRegistry and runtime action journals are authority/accounting components in another module, not SDK client helpers. Do not import Runtime, add a Transport target/channel protocol, or copy those registries into SDK.

**Own exactly:** NEW `CascadeKit/Sources/CascadeAddonSDK/Storage/StorageRequestLifecycle.swift`; NEW `CascadeKit/Tests/CascadePresentationTests/StorageRequestLifecycleTests.swift`. The existing CascadePresentationTests target already depends on CascadeAddonSDK and hosts its tests; use `@testable import CascadeAddonSDK`, avoiding a Package.swift change for this finite internal helper. Inspect local test conventions first. No production public API changes and no placeholder TransportStorageClient implementation.

## Ownership and isolation

Use an internal `final class StorageRequestLifecycle`, intentionally NOT Sendable and not annotated unchecked Sendable. All methods are synchronous; the future concrete client owns one instance inside its serialization domain/actor and must not share it concurrently. Reference identity avoids duplicating a live request ledger through value-type copies. No actor, mutex, continuation, callback, Task or async wait is needed for pure transitions.

Stored state is constant-size: generation, private issuer UUID, lastIssuedSequence UInt64, closed Bool, and one optional pending record. Pending contains a scalar ticket, handoff phase and locallyCancelled Bool. It never stores StorageRequest, StorageResponse, Data, String/key, Error/reason text, closures or a history collection. Arguments and their buffers remain caller-owned; methods inspect them synchronously and return scalar tickets/dispositions only. This helper neither prepays host quota nor proves framework/native memory bounds. Later transport/SDK code must separately own raw/value/reply buffers and physical credits; helper transition completion is not their release receipt.

## Exact internal API

Names below are the proposed implementation contract. Keep all types module-internal; only Ticket's issuer/nonce construction is fileprivate/private.

```swift
final class StorageRequestLifecycle {
    struct Ticket: Equatable, Sendable {
        fileprivate let issuer: UUID
        fileprivate let nonce: UUID
        let generation: ConnectionGeneration
        let sequence: UInt64
        let requestID: UUID
        let operation: StorageOperation
    }
    enum HandoffObservation: Sendable {
        case accepted
        case rejectedBeforeHandoff
    }
    enum LocalFailure: Equatable, Sendable {
        case cancelled
        case closed
        case notSent
        case outcomeUnknown
    }
    struct LocalCompletion: Equatable, Sendable {
        let ticket: Ticket
        let failure: LocalFailure
    }
    enum ResponseDisposition: Equatable, Sendable {
        case deliver
        case discardCancelled
    }

    init(generation: ConnectionGeneration, profile: StorageFrameProfile?) throws
    func begin(_ request: StorageRequest) throws -> Ticket
    func beginHandoff(_ ticket: Ticket) throws
    func observeHandoff(_ observation: HandoffObservation,
                        ticket: Ticket) -> LocalCompletion?
    func consume(_ response: StorageResponse,
                 generation: ConnectionGeneration,
                 sequence: UInt64) throws -> ResponseDisposition
    func cancel(_ ticket: Ticket) -> LocalCompletion?
    func close() -> LocalCompletion?

    // Exact checked arithmetic used by begin, independently testable at UInt64.max.
    static func nextSequence(after lastIssued: UInt64) throws -> UInt64
}
```

Ticket equality includes issuer, nonce, generation, sequence, requestID and operation. Each successful begin mints a fresh nonce. Caller supplies a validated request; the future concrete client must mint a fresh request UUID when constructing it. This helper does not claim UUID uniqueness across history: the same requestID under a newly issued sequence is a new request, and old replies fail sequence correlation. No public ticket initializer, replay Set or stored copy of request.value is added. A ticket from another lifecycle instance remains foreign even if generation/request fields match.

Initializer requires profile `.v1_1`, otherwise AddonFailure.versionConflict; it retains the supplied generation and starts sequence0/idle/open. The profile/generation are trusted caller configuration but do not authenticate a peer; no raw decoding occurs here.

## Transition rules and exact outcome semantics

### Admission and sequence

`begin` checks closed first (sessionRevoked), then pending capacity (resourceDenied), then calls request.validate(), then computes nextSequence. All fallible work precedes mutation. nextSequence requires lastIssued < UInt64.max or throws resourceDenied, returning lastIssued+1 without wrap. On success store the fresh Ticket with phase prepared, locallyCancelled=false, and advance lastIssuedSequence. Failed validation, busy, closed or exhausted admission changes nothing. A prepared request cancelled or later rejected before handoff leaves a gap; never reuse/decrement an issued sequence. Host C7b1 accepts increasing sequences, not necessarily consecutive ones.

Each lifecycle starts0 for one supplied generation. No restore/reopen or seeded-counter public constructor. Tests exercise max-1 -> max -> rejection through the actual nextSequence helper that begin calls; do not loop billions of times, lower production limits, inject arbitrary session state, or claim a full-instance traversal to UInt64.max. A new connection generation uses a new instance.

### Actual handoff boundary and races

`beginHandoff` requires the exact current Ticket, open state and prepared phase. Wrong/foreign/retired ticket or closed -> sessionRevoked; calling it twice on a current attempted/accepted request -> invalidPayload. It changes phase to attempting BEFORE the future transport can expose bytes or suspend. No physical submission is permitted unless this method succeeds.

This marks possible handoff, not proof that bytes were sent. Actual transport may report accepted or an explicit guarantee of rejectedBeforeHandoff. A generic thrown transport error is NOT such a guarantee. This helper does not perform I/O or create that guarantee.

`observeHandoff` handles only an exact current ticket in attempting phase. accepted changes phase to accepted; pending remains. rejectedBeforeHandoff clears pending: if no local cancellation has been reported, return LocalCompletion(ticket,.notSent); otherwise return nil to avoid completing the caller twice. For wrong/old ticket, no pending, closed state, prepared phase or already accepted phase, return nil with no mutation. This tolerant late-notification behavior is intentional: a response may arrive and consume the ticket before an asynchronous send method returns its handoff observation. A late observation must not affect the next request or reverse an already delivered result. Do not retain tombstones to distinguish all past observations.

A valid correlated response is allowed in attempting OR accepted phase. Requiring an accepted observation first would introduce an unnecessary queue or reject a real reply that races ahead of the send call's return. A response in prepared phase is invalidPayload and leaves pending intact. This is safe only when the future channel authenticates the actual reply source; a UUID-shaped response alone is not authority.

### Reply consumption without retaining payload

`consume` checks open/pending, then exact generation, sequence, requestID and operation; call response.validate() before any state mutation. Closed/no pending or wrong generation -> sessionRevoked. Wrong sequence, requestID, operation or prepared phase -> invalidPayload. All rejection paths preserve the current pending request. Semantic response validity remains C6's responsibility; callers of the raw boundary use StorageFrameCodec first.

For a correct response in attempting/accepted phase, clear pending synchronously exactly once. If locallyCancelled is false return deliver; otherwise return discardCancelled. The caller already owns the response: only deliver permits returning its value/result to the awaiting operation. discardCancelled rejects user delivery while permitting the future channel to finish/drain its exact physical response receipt; it does not discard another reply or imply a quota refund. A stale/unsolicited response throws and must not consume a different pending request. An exact duplicate after consumption has no pending authority and fails; after a newer begin it fails generation/sequence/ID correlation without disturbing the new request.

Do not map/read-copy the response Data into a new result type. Missing, present-empty, acknowledgment and failure (including outcomeUnknown) remain the caller-owned C6 response exactly as validated. This helper makes only the delivery/discard decision; no automatic retry follows either result.

### Cancellation

`cancel` affects only the exact pending Ticket; wrong/old/already locally cancelled/closed returns nil unchanged. It reports one LocalCompletion:

- prepared: clear pending, return cancelled. Physical handoff never began under the helper contract; old beginHandoff now fails. A new request may begin at the next sequence.
- attempting/accepted read: keep pending, mark locallyCancelled, return cancelled. This cancels the caller's wait, not proof that the host never performed the read.
- attempting/accepted write/remove: keep pending, mark locallyCancelled, return outcomeUnknown. A generic send failure after beginHandoff must be treated with this same conservative uncertainty unless a rejectedBeforeHandoff guarantee is observed first.

The cancelled in-flight request STILL occupies the one pending slot until its exact response is consumed/discarded, a rejectedBeforeHandoff observation drains it, or the lifecycle closes. A second begin remains resourceDenied. This prevents cancellation from fabricating a free transport credit or accumulating multiple abandoned requests. If cancellation occurs during attempting and an accepted observation arrives later, it preserves locallyCancelled and waits for disposal of the exact reply. A late rejectedBeforeHandoff observation frees the slot but returns no second caller completion and does not retroactively rewrite the earlier uncertainty report. No retry is performed.

### Close

`close` is irreversible/idempotent. First call sets closed and clears pending; subsequent calls return nil. If a pending request had not already reported local cancellation, return one LocalCompletion: prepared/read -> closed; attempting/accepted write/remove -> outcomeUnknown. If there was no pending request or it was already locallyCancelled, return nil. Every later begin/beginHandoff/consume refuses; late observations/cancel are no-ops. New generation requires a new instance.

This close clears only scalar lifecycle authority. It does not close a provider, channel, stream, file or governor reservation and cannot roll back a host mutation. The future concrete channel owner must separately stop or drain actual retained buffers/receipts according to its own bounded contract; this helper must never be used to claim those physical objects have been released. After close, no payload is accepted for user delivery, including an otherwise matching late reply.

LocalFailure is deliberately internal: cancelled can later become CancellationError at the actual SDK task boundary; closed maps to sessionRevoked, notSent to dependencyUnavailable, outcomeUnknown to the existing AddonFailure.outcomeUnknown. Do not add a global cancellation error enum or convert arbitrary errors/reasons here. LocalCompletion is returned at most once per pending ticket across cancel/close/handoff rejection.

## Meaningful finite RED/GREEN matrix

Use real C6 constructors/codec and ConnectionGeneration values. Never forge immutable DTO memory. No fake channel/backend/provider is needed because tests exercise synchronous production transition logic, not claim real I/O.

- [ ] Idle begin produces sequence1 with exact requestID/operation/generation and fresh opaque ticket. Second begin refuses resourceDenied without replacing it. Bad profile fails versionConflict. A prepared cancellation permits sequence2, never reuses1; a prepared rejected-before-handoff result after beginHandoff also permits a later sequence.
- [ ] Actual compiling RED for foreign ticket transition, wrong generation/sequence/ID/operation response preserving the current pending request, and second consumption/late observation affecting a newer pending request. Use legal C6 responses representing each mismatch. Verify the original correct response can still be consumed afterward.
- [ ] Real Foundation C6 encode/decode input/output in at least one fixture; malformed raw response fails the codec before consume and leaves the existing lifecycle pending. Reuse validated request/response bounds, not new synthetic byte parsers. A write with full64KiB and a full-size read response work without state retaining or reencoding their payloads. Confirm missing versus present-empty stay distinct in the caller-owned response; lifecycle returns deliver for either correctly correlated shape.
- [ ] Prepared reply refuses. beginHandoff -> response BEFORE observeHandoff(accepted) succeeds once; the late handoff observation is harmless. Later begin with the same wire request UUID but a newer sequence is valid; an old sequence cannot consume it. No fake response timing gate is needed: these are reachable serialized callback orders.
- [ ] prepared cancel -> cancelled, no duplicate completion, stale beginHandoff fails and next sequence begins. attempting/accepted cancel parameterized read/write/remove -> cancelled versus outcomeUnknown; pending stays busy. Exact reply then returns discardCancelled and clears it; another cancel/old observation never completes twice.
- [ ] cancel during attempting -> later accepted preserves abandoned pending; later exact reply discards. cancel during attempting -> rejectedBeforeHandoff drains with no second completion. Rejection before cancellation produces one notSent; later cancel returns nil. Response before cancellation produces deliver; later cancel returns nil. Caller cannot automatically replay any path.
- [ ] close idle/prepared/attempting/accepted/already-cancelled: exact one completion classification, permanent refusal and late-reply rejection; second close/late handoff/cancel no mutation. A different lifecycle instance using a fresh generation accepts its own work and rejects the old Ticket/response generation.
- [ ] Production nextSequence helper returns1 from0 and max from max-1, then throws resourceDenied at max. Source review verifies begin calls it before committing pending/lastIssued state. Do not add a session restore API solely for this test.
- [ ] Source/stored-field inspection confirms only scalar state, no Data/String/request/response/error/continuation history, no @unchecked Sendable, no Runtime/governor/native import. This is structural source evidence, not a memory-footprint benchmark or a weak-reference test of caller-owned Data.
- [ ] Implement compiling permissive stubs only to observe actual behavioral RED, then minimal final transition logic and GREEN for the new suite plus AddonContext/AddonProvider/asset-client and C6 contracts. Use the root-owned serial scratch only when dispatched; do not create a new scratch to evade coordination. Preserve every final test and freeze exact two-file patch, preimages/new-file manifest, hashes and actual command/RED/GREEN evidence. Root separately reviews, builds and delivers; no commit/native launch by the worker without explicit instruction.

## Approval and later boundary

This brief does not claim a complete client or an authenticated channel. Ticket/generation/correlation state is descriptive local protocol bookkeeping. A later TransportStorageClient still needs a bounded concrete channel, canonical peer connection, raw/decoded buffer ownership, actual handoff guarantees, physical receipt disposal and cancellation/drain integration before AddonContext.storage can be called operational. No new protocol profile, host permission field, public storage signature or native launcher decision is selected by this pure lifecycle slice.


Preparation ledger: finite scope independently preflighted and approved; implementation not dispatched. Complete host handler must be delivered and weekly budget checked before any SDK implementation dispatch.

Independent preflight report: `/private/tmp/cascade-sdk-storage-lifecycle-preflight-review.md`, approved without pending findings. Complete host-handler delivery and budget remain prerequisites.
