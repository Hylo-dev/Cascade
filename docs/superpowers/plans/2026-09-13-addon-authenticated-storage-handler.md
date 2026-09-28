# C7b authenticated keyed-storage handler implementation brief

> For implementing agents: use the existing plan-execution/TDD/review workflow. Preparation only: no dispatch, implementation or native execution is authorized by this document. Root owns sequencing, budget, integration and delivery.

**Goal:** Carry a bounded authenticated raw storage request through real keyed storage and an exactly correlated retained adapter reply, without returning uncharged Data.

**Architecture:** Reuse the runtime's single admission, process ingress/delivery capacity, canonical connection, common governor and fixed-registry coordinator. First correct existing shared-slot ownership as independently deliverable C7b0; then implement the complete storage handler as C7b1. C7a supplies the separately reviewed concrete coordinator result API.

**Tech stack:** Existing Swift actors, Foundation JSON codec, ResourceGovernor, secure keyed backend; macOS 14 floor, no new library.

**Spec:** `/private/tmp/cascade-keyed-storage-handler-frontier.md`; approved C6 frames brief and C7a outcomes brief; existing addon storage/resource contracts. All source paths below are relative to the Cascade repository.

## Constraints and decision

No new user architecture decision is needed. Both steps are finite host primitives, tested with real storage/governor and bounded recording adapters. C7b0 is a real existing-flow correctness fix with an independent regression boundary. C7b1 must be delivered whole; an uncharged `Data -> Data` bridge is not a useful intermediate delivery.

No native conformer, provider process, SDK client, app driver, installed identity manufacture, C0d gate change, timer, replay cache or automatic retry. No governor policy, keyed backend algorithm, SwiftData/archive or C7a outcome redesign. Respect the already approved observed-disk policy. Foundation workspace admission is an allowance, not a proved RSS limit. User 60% weekly ceiling controls dispatch; this brief does not imply budget approval.

## Verified source facts requiring concrete composition

- Runtime ProcessRecord currently has two Bool credits (`AddonRuntime.swift:91–102`). Delivery writes/releases are at 730/881/945/1126/1155/1174/1360/1396/1533/1584. Action acknowledgment clears the runtime Bool without releasing the adapter's retained payload. Release sites are untyped; a legitimate later A completion can clear a newer storage reply once that job-free path exists. Current one-job-per-owner admission prevents concurrent still-running A and a newer legacy action/source/service B; do not claim that legacy overlap is reachable.
- `receiveCompletionOnlyOutput` releases outputOutstanding before awaiting deferred service completion, while an outer catch can clear it again. Ingress must be owned by an exact invocation claim so stale cleanup cannot release a later transfer.
- `connectedOwner` at 3959 validates runtime token/incarnation/identity/digest/revision but not the caller-supplied nested publication/service handle. Storage must fetch the canonical `.connected(let current)` from ProcessRecord and use its protocol; never authorize from `connection.publicationConnection.negotiatedProtocol` supplied by the caller.
- The protocol chain is runtime attach -> `Publications/PublicationState.openConnection:105` -> `Admission/PublicationSessionRegistry.open:151` -> negotiator. `ResolutionPlanner:53` separately compares manifest minimum with HostEnvironment's protocol ceiling.
- Launch capacity is charged in direct launch near 439, indirect dependency launch near 3845 and recomputed in requiredBytes near 4008. All three must use the same formula. `observeExit:1706` removes the process before deferred drain, so live operation buffers cannot depend solely on the process quote.
- `Storage/AddonStorageCoordinator.owner(for:)` is available only after the complete inventory barrier and returns one epoch-bound fixed-row capability. C7a executeKeyedRequest owns the known/unknown mutation result. Generic coordinator write is not its substitute.
- `ResourceGovernor.withAssetDecodeReservation` is an existing generic protected temporary-memory scope despite its historical name; releaseAll cannot refund its secret while the closure still owns buffers. Its closure must not return Data/DTO graphs. Use it directly through the common governor, without adding a second reservation abstraction.

## C7b0 — exact bounded ownership for existing ingress and delivery

This prerequisite can be implemented, reviewed, fully tested and delivered before C7b1 or C7a. It installs no storage support and leaves protocol 1.0 selection unchanged.

**Files:** modify `Sources/CascadeRuntime/AddonRuntime.swift`, narrowly clarify `AddonRuntimeTransport.swift` ownership documentation, add `Tests/CascadeRuntimeTests/AddonRuntimeSlotOwnershipTests.swift`; reuse/extend the recording adapter and real forwarded gates in existing composition tests with minimal visibility changes. Prefix paths with `CascadeKit/`.

### Scalar ownership and accounting

Replace the two mutable Bool ownership variables with one bounded ProcessCreditState (or equivalent inline fields). No Data, request history, queue or collection is added:

```swift
private enum DeliveryCredit: Equatable, Sendable {
    case action(ticketID: UUID)
    case source(sourceID: UUID)
    case service(workID: UUID)
}
private struct IngressClaim: Equatable, Sendable {
    let id: UUID                 // fresh host ID per invocation, not merely provider handle token
    let handle: RuntimeIngressHandle
}
private struct ProcessCreditState: Sendable {
    var ingress: IngressClaim?
    var delivery: DeliveryCredit?
}
```

ProcessRecord/incarnation supplies the outer authority. Keep convenience `hasOutstandingDelivery`/`hasOutstandingIngress` computed from these optionals, not separately writable mirrors. Charge the fixed new control representation conservatively with `max(512, 4 * MemoryLayout<ProcessCreditState>.stride)` in addition to the existing process quote. Use one computed process-admission formula at both launch paths and requiredBytes. This explicit quote covers transient value copies and avoids hidden history; its dimension is retained state/admitted memory through the existing pool. Do not change physical provider, command, job or payload lifetime reservations.

Central synchronous helpers must accept owner + expected incarnation + exact credit/claim. A release clears runtime state AND calls the adapter receipt only when the current credit matches. An old accepted completion still completes its own dispatcher/broker/job lifecycle when it no longer owns delivery credit; it simply cannot remove another payload.

At successful synchronous action/source/service handoff, install the matching scalar credit before the next await. Every pre-handoff availability check reads the same optional credit. Guard all old unconditional releases: ordinary publication action completion, completion-only action/service, direct action acknowledgment/completion, source startup completion and direct service completion. Do not retain whole ActionDispatcher.Delivery in the new credit: ticket.id plus current incarnation is sufficient; canonical dispatcher validation remains required before credit release.

Action acknowledgment is an actual receipt. If the dispatcher accepts it and the exact current action credit matches, also call `adapter.deliveryWasReceived(incarnation:)` synchronously. This makes runtime and adapter agree the slot is free. A duplicate/late acknowledgment or later action completion cannot release a newer action/source/service credit. The adapter is synchronous/nonrecursive, so exact matching immediately before its call is the ownership linearization point; no new generic adapter receipt protocol is necessary.

Ingress claim helpers must check current incarnation and empty ingress, mint a fresh claim UUID, and store it synchronously. Claim before taking a transferred value; preserve reject (staged only) versus cancel/finish (only successful taker) distinction. If beginAdmission or another await precedes claiming, recheck emptiness after that await. Pass the exact claim into completion-only helpers; any deferred record that may perform later ingress cleanup carries that scalar claim. Keep the claim occupied for the entire transferred adapter lifetime, including deferred service completion. REMOVE the old early Bool-clear timing (ordinary output clears before refunds/finish; completion-only service clears before deferred drain). A single exact-claim cleanup helper performs the actual adapter finish/cancel synchronously and clears the claim together, only after confirming expected incarnation and fresh claim ID. A staged refusal uses reject instead. Deferred completion becomes the authoritative finisher after ownership transfer to its record; outer success/catch cleanup is an exact no-op if that claim was already finished. Only AFTER actual adapter disposition may a new claim occupy the slot; any later old-call cleanup must not affect it. Cleanup checks exact ownership even for a stopping process, not connectedOwner eligibility; observed exit already disposes adapter ingress before removing the process. Never set the current slot to nil by owner alone. Do not cancel another invocation's transferred adapter slot on a failed duplicate take.

The adapter's physical retained payload may be dropped by its documented synchronous stop handling or by receipt/exit. Runtime process-capacity reservation remains retained until actual observed exit under existing semantics; requesting stop or changing an ownership scalar is not a quota refund. Preserve existing deferred-exit process snapshots and cleanup ordering.

### Finite independent regression boundary

- [ ] With real runtime, dispatcher/governor and recording adapter, hand off action A, accept its acknowledgment, and assert its adapter payload was removed while its provider job remains charged. ResourcePolicy permits only one provider job per owner: a second legacy action/source/service cannot hand off on that incarnation until A completes. Prove that refusal without quota widening or fake job admission. Complete A, then hand off real B; a stale/duplicate A acknowledgment or completion cannot release B's exact slot/payload. B subsequently releases only its own slot.
- [ ] Parameterize the newer B as action/source/service where existing fixture reuse permits, always AFTER A's real completion releases its job. Direct and publication completion paths must use the same exact release helper. A legitimate still-running A completion concurrent with a newer STORAGE reply is reachable because storage claims no provider job; that stronger overlap belongs to C7b1, not this prerequisite.
- [ ] Exercise completion-only deferred service ingress with real forwarded completion/refund gates: after the old ingress is actually finished/released, stage and claim a new ingress while the old call can still unwind. Old success/catch cleanup must not clear the new claim or cancel its adapter transfer. Gate placement must be proved from adapter finish/transfer evidence. If existing real gates cannot force old-task/new-claim overlap, assert the transferred/deferred claim remains occupied, duplicate/competing ingress refuses without cancelling it, and only actual finish/cancel restores availability. Do not inject a fake backend success or claim an unobserved overlap.
- [ ] Wrong incarnation, duplicate handle take, pre-admission refusal, stop and observed exit maintain staged/transferred semantics and one slot. Existing completion bypass remains usable for cleanup while normal admission is busy; the new claim is ownership, not a new global admission lock.
- [ ] Verify exact fixed control quote on direct and indirect launches, no extra history after receipts, retained process capacity until observed exit, and necessary precise existing baseline updates.
- [ ] Capture compiling behavioral RED from the old implementation for A acknowledgment failing to release the adapter payload while its job stays charged; test B admission refusal before A completes and stale A versus B afterward as regressions, implement helpers and all call sites, then run new suite plus composition/action/broker/deferred-completion/shutdown suites. Freeze exact patch, preimages, hashes and real gate evidence for independent review. No source commit or app operation by the worker unless separately instructed by root.

## C7b1 — complete authenticated raw request through retained reply

Dispatch only after C6, C7a and C7b0 are independently approved/delivered and root checks remaining budget. The following is a single coherent implementation/review scope; no storage handler is exposed before ownership, quota and receipt pieces are all implemented.

**Files:** modify `AddonRuntime.swift`, `AddonRuntimeTransport.swift`, `Publications/PublicationState.swift`, `Admission/PublicationSessionRegistry.swift`; expose only a nonisolated immutable common-governor identity from `Storage/AddonStorageCoordinator.swift`; add `Tests/CascadeRuntimeTests/AddonRuntimeStorageRequestTests.swift`; minimally extend the bounded recording adapter and existing secure coordinator/keyed test helpers. `PublicationStore` need not forward an opt-in: its call remains default false. C7a executeKeyedRequest is consumed unchanged. No Contracts, SDK, generic resource protocol or backend algorithm edits.

### Installation and canonical permission/profile policy

Add optional `storageCoordinator: AddonStorageCoordinator? = nil` to both host make overloads and private initializer. Store the runtime-side coordinator reference WEAKLY: C5 coordinator ArchiveShutdownContext already strongly retains runtime through terminal idempotency, so a strong reverse runtime reference would form a permanent cycle. The host remains responsible for retaining coordinator/governor across their documented lifecycle. Store immutable installed-support policy separately from this weak reference; do not derive negotiation policy later from weak-reference liveness. Capture a strong local coordinator before accepted operation awaits and keep it through the entire operation, so pending C7a work cannot lose its backend. A missing weak binding refuses dependencyUnavailable. Do not weaken C5 shutdown context or change its terminal idempotency. Expose a nonisolated `resourceGovernorTarget: ResourceGovernor` on the coordinator returning its existing immutable governor (prefer a computed property if supported, without a duplicate retained reference); reject mismatch before retaining/using the installation. Define a refining internal `AddonRuntimeStorageAdapter: AddonRuntimeAdapter` with the raw storage methods below. Non-nil coordinator requires an adapter conforming to that protocol; configuration mismatch is an invalidPayload host factory error, not a runtime fallback to callbacks. No coordinator field or path comes from provider input.

Explicit canonical host policy still participates: enable storage framing only when coordinator + refined adapter are installed AND the supplied HostEnvironment advertises major 1/minor >= 1. Use effective resolver minor `min(environment.protocolVersion.minor, implementedCeiling)`, where implementedCeiling is 1 with both seams and 0 without; leave major unchanged. Construct the bounded effective HostEnvironment preserving osVersion, hostCapabilities, applications, grants, explicitBindings, protocol major and serviceAccessGrants exactly; change only the effective protocol minor. Do not add grant fields or retain another environment graph. This prevents a bare environment1.1 flag admitting unsupported min1 providers. Default environment1.0 and nil installation preserve normal default1.0 behavior. With seams installed but environment1.0, the handler remains unavailable. Host fixtures that enable this path explicitly use environment1.1.

Forward `supportsKeyedStorageFrames: Bool = false` through PublicationState.openConnection and session registry open to the existing negotiator. Runtime attach supplies the frozen installed policy; all standalone/default callers remain false. No mutable provider flag, offer field or profile value independently turns it on.

During already-prepaid catalog installation derive one per-owner immutable `storageOwnGranted` Boolean from BOTH manifest permission `.storageOwn/.addon` and environment.grants[owner] containing `storage.own`. Store it in the existing OwnerPool alongside its exact catalog identity; do not retain the grants dictionary. Add a fixed `max(256, 4 * MemoryLayout<Bool>.stride)` per-owner handler-control allowance only when storage framing is installed/enabled, before retaining the new permission projection. This covers fixed installation reference/control copies; zero owners retain no new proportional table. Runtime has no grant-update API: current disable/stop/quiescence gates revoke new storage admission; this slice does not invent a separate mutable grant lifecycle.

Every storage authentication check obtains owner through connectedOwner, then reads the canonical ProcessRecord `.connected(current)` and exact installed catalog identity/digest/enabled state, accepted resolution and derived storage permission. Read profile only from current.publicationConnection.negotiatedProtocol, never the caller's nested session. Recheck after every owned await, including admission/workspace/owner acquisition. The runtime's global operation authority revision also remains required; no shutdown-ticket exception for storage.

### Adapter vocabulary and fixed capacity

```swift
struct RuntimeStorageIngressHandle: Hashable, Sendable {
    let token: UUID
    let incarnation: RuntimeIncarnation
    let encodedBytes: Int
    let sequence: UInt64
}
struct RuntimeStorageReceipt: Equatable, Sendable {
    let token: UUID                 // fresh host delivery nonce
    let incarnation: RuntimeIncarnation
    let connectionToken: UUID
    let sequence: UInt64
    let requestID: UUID
    let operation: StorageOperation
}
struct RuntimeStorageResponseDelivery: Equatable, Sendable {
    let receipt: RuntimeStorageReceipt
    let payload: Data
}
// Add RuntimeAdapterDelivery.storageResponse(RuntimeStorageResponseDelivery).
protocol AddonRuntimeStorageAdapter: AddonRuntimeAdapter {
    func takeStorageIngress(_ handle: RuntimeStorageIngressHandle,
                            incarnation: RuntimeIncarnation) -> Data?
    func rejectStorageIngress(_ handle: RuntimeStorageIngressHandle,
                              incarnation: RuntimeIncarnation)
    func cancelStorageIngress(_ handle: RuntimeStorageIngressHandle,
                              incarnation: RuntimeIncarnation)
    func finishStorageIngress(_ handle: RuntimeStorageIngressHandle,
                              incarnation: RuntimeIncarnation)
}
```

These are module-internal transport values, not Codable authority. Receipt equality matches every scalar. Do not make it Hashable by adding new Hashable conformances to Contracts enums just for a nonexistent dictionary.

Extend the C7b0 ingress claim to a typed publication/storage handle plus fresh claim UUID. Extend DeliveryCredit with storageReserved(reservationNonce:UUID) and storageAccepted(RuntimeStorageReceipt). The reserved variant occupies the same one delivery slot before any mutation. Releasing storageReserved on pre-execution refusal, suppression or rejected handoff is ONLY an exact scalar cancellation: do not call adapter.deliveryWasReceived because no storage payload was accepted. Only an exact storageAccepted(receipt) release sends that adapter receipt. Extend the C7b0 release helper with this distinction rather than treating reserved credit as a delivered payload. Extend ProcessCreditState with lastStorageSequence:UInt64 initially0. Its existing measured fixed quote must be recomputed for the final representation and raised if needed before either launch path; no history/set. Keep one occupied ingress and one delivery per incarnation across all kinds.

Add `maximumStorageIngressBytes` and `maximumDeliveryBytes` scalar fields to RuntimeStartDelivery with defaults preserving existing construction (0 and 80KiB). Enabled runtime supplies min(maximumEnvelopeBytes,192KiB) and 256KiB. Existing publication ingress remains bounded by maximumEnvelopeBytes (default512 KiB). Enabled process delivery quote is 256KiB, otherwise80KiB; use the same formula in direct launch, indirect launch and requiredBytes. A smaller explicitly configured maximumEnvelopeBytes can reject a larger otherwise-legal frame; the default configuration supports the full C6 domain.

The refined recording adapter stores a single typed ingress slot, not separate publication and storage dictionaries capable of retaining both. It retains only one current Data-bearing reply payload per admitted incarnation: no response history or stored lastResponse copy may survive receipt. Observations use scalar counts/compact receipts or computed access to the current slot, like existing lastAction. Any decoded peer/test copy has separate caller-owned lifetime and cannot serve as proof that the adapter released its own payload. It admits/copies raw bytes only against the launch-provided prepaid capacity, checks kind/complete handle on take, and never retains oversized raw input. Distinguish staged versus transferred ownership exactly as the base interface. A raw Data with excess backing capacity must not be retained as if only its logical count were charged: staging makes a compact bounded owned copy under prepaid ingress capacity (use `raw.withUnsafeBytes { Data($0) }`, not `Data(raw)` that may share excess backing); caller input/copy overlap remains caller-owned. No real socket buffering is claimed here.

Existing tryHandoff carries the response; accepted retains one adapter-owned payload until exact receipt, documented stop disposal or observed exit. RejectedBeforeHandoff guarantees no retained/exposed payload. No blocking IPC or recursive runtime callback is allowed. Storage accepted receipt releases only its exact credit and then calls the existing synchronous adapter receipt; stale/foreign/duplicate receipts return false with no release.

### Complete runtime API and scalar outcomes

```swift
enum RuntimeStorageOutcome: Equatable, Sendable {
    case value, missing, acknowledged, outcomeUnknown
    case failure(AddonFailure.Code)
}
enum RuntimeStorageReplyDisposition: Equatable, Sendable {
    case handedOff, rejectedBeforeHandoff, suppressed
}
enum RuntimeStorageRequestResult: Equatable, Sendable {
    case refused(AddonFailure.Code)
    case completed(RuntimeStorageOutcome, RuntimeStorageReplyDisposition)
}
func receiveStorageRequest(_ ingress: RuntimeStorageIngressHandle,
                           connection: RuntimeConnection) async -> RuntimeStorageRequestResult
func receiveStorageReceipt(_ receipt: RuntimeStorageReceipt,
                           connection: RuntimeConnection) -> Bool
```

No Data, DTO, coordinator Owner or arbitrary Error escapes these results. Local known mutation outcome remains separate from whether a provider reply may be delivered. A read's `.value` summary is only a bounded fact; no bytes escape a revoked connection.

### Phase order, workspace and sequence

1. Synchronously check cancellation, canonical connection and frozen installed profile (nil/default -> versionConflict), then declared/granted permission. Only after those checks capture the weak coordinator as a strong operation-local reference before any await (a lost previously installed binding -> dependencyUnavailable). Then check exact ingress incarnation, 1...min(192KiB,configuredIngressCap) encoded bytes and sequence >0 and >lastStorageSequence. Check shared ingress and delivery free. Reject only this staged storage handle on refusal. Nil/default profile is versionConflict; missing permission permissionDenied; stale/oversize/malformed handle invalidPayload; revoked session sessionRevoked; occupied capacity resourceDenied. No decode/take/backend operation or sequence consumption occurs here.
2. Obtain existing normal runtime admission (busy resourceDenied, no queue), then revalidate all conditions after any cleanup await. Claim the exact ingress and reserve a fresh storage delivery-credit nonce synchronously before the next await. Do not overwrite an active legacy delivery; no per-request delivery allocation is needed because process capacity is prepaid.
3. Enter `governor.withAssetDecodeReservation(bytes:8*1024*1024, owner:owner)` BEFORE adapter.take or JSON decode. The protected scope covers controlled raw/copy overlap, decoded request/value, the conservative C7a135,168-byte application-value boundary, returned read value, response DTO, Foundation codec allowance and encoded output coexistence. This is deliberately conservative application admission, not a measured native/framework heap guarantee. The backend separately owns its 267,776-byte scratch/staged state/disk. No generic releaseAll or process exit can refund this protected scope while these buffers remain live.
4. Inside a private runtime-actor helper invoked by that protected closure (make this helper `async -> RuntimeStorageRequestResult`, nonthrowing, and catch/map its pre-execution errors internally): revalidate operation/canonical authority/claims. Obtain `await storageCoordinator.owner(for: current.identity)` under the same scope and revalidate again. A not-ready/busy/foreign registry fails without raw take, sequence consumption or backend execution. It may become stale later; C7a checks its epoch itself. Take the exact storage ingress only now; remember transfer ownership. Require actual Data.count==handle.encodedBytes, then decode synchronously with C6 and the canonical profile. Use a nested/local scope so buffers die before the outer protected closure returns.
5. After successful decode and final synchronous operation/identity/profile/permission/credit/sequence validation, consume lastStorageSequence=ingress.sequence and retain only requestID/operation/sequence in the pending reply correlation. Invoke C7a's concrete executeKeyedRequest immediately from this actor entry. There must be no separate awaited validation callback followed by a nonisolated mutation handoff. The actor hop to the coordinator is the handoff boundary; later disable/cancel cannot promise rollback of accepted backend work. UInt64.max is allowed once; afterward no larger sequence exists and requests fail rather than wrap.
6. Busy/refusal before step5 consumes no sequence. A C7a refusal after its method was invoked consumes the already accepted sequence, even if the coordinator became busy in the intervening actor hop. This does not claim backend mutation. Malformed wire or quota/owner failure before step5 releases this ingress and reserved delivery; it does not consume the sequence, emits no fabricated response UUID and returns only refused. There is no disconnect policy change or retry loop. Reusing an old UUID at a genuinely new sequence is a new operation; there is no unbounded UUID dedup guarantee.
7. C7a result mapping: read(some)->C6 value; read(nil)->missing; acknowledged->acknowledged; outcomeUnknown->failure code outcomeUnknown. Refused invalidRequest->invalidPayload, invalidOwner/cancelled->sessionRevoked, unavailable->dependencyUnavailable, busy->resourceDenied, readFailed(code)->that code. Use one short fixed host-owned reason per code (not filesystem NSError text), retaining the C6<=4096 bound. No automatic read-after-failure, retry or later status query to infer mutation outcome.
8. After C7a returns, preserve its bounded local summary before any fallible delivery check. Encode the bounded response within the same protected scope; compact the encoded payload with `encoded.withUnsafeBytes { Data($0) }` before handing off, so a framework encoder buffer with excess capacity is not retained under the reply-slot quote. Both temporary copies coexist only inside the protected scope. Immediately before synchronous tryHandoff, revalidate current normal authority/cancellation, exact incarnation/canonical connection/permission/profile and exact reserved delivery nonce. This check and tryHandoff occur in the same runtime actor entry with no intervening await. On revocation or encoding failure, drop all response bytes and release only the exact pending credit; return completed(summary,suppressed). A known acknowledged or outcomeUnknown result must never be rewritten as a pre-call refusal by post-execution cleanup.
9. On accepted synchronous handoff, change the exact reserved credit to storageAccepted(receipt) before any await. Payload now has prepaid256KiB process delivery ownership. On rejected handoff, release the exact pending credit and return completed(summary,rejectedBeforeHandoff); failure to send is not rollback. Finish/cancel the ingress according to successful take ownership, clear only the exact ingress claim, and let all raw/request/read/DTO/encoded local references die before the protected closure returns. It returns only scalar result; after C7a returns, all later failures are handled inside this helper against its preserved outcome, never thrown to an outer pre-admission catch. The governor scope can throw only before entering the helper; its final protected release is nonthrowing. Then finishAdmissionAndDrain; no fallible post-cleanup authority check changes a known result.
10. A later exact storage receipt requires canonical current connection, matching accepted receipt, current incarnation and connection token. Release only that slot. A foreign/old receipt cannot release a legacy credit or a newer storage request. Stop/quiescence/exit retain or dispose payloads under existing adapter contract and process lifetime accounting; no new artificial acknowledgment is generated.

The effective trusted grant set is fixed for this runtime installation. Disable/quiescence/stop deny admission and replies; their immediacy applies to new runtime-controlled handoffs, not an already accepted filesystem mutation. There is no new per-request deadline field or hard timeout claim in this scope.

### C7b1 finite TDD and evidence matrix

- [ ] Actual governor, three secure roots, complete fixed registry, real C7a backend, runtime and one-slot recording storage adapter: full65,536-byte write with256-byte UTF-8 key; read exact bytes; distinct empty/missing; remove and remove-missing. C6 encodes requests/replies; storage class is always data. Two identities remain isolated, cache unchanged.
- [ ] Real weak-reference lifetime probe: after C5 shutdown and dropping host/runtime/coordinator references, the new binding does not form a strong cycle; this is object lifetime evidence, not proof of SwiftData physical close or file-descriptor disposal. Hold actual C7a work and drop the host coordinator reference to prove the operation-local strong capture retains it until completion. Missing weak binding refuses without take/mutation.
- [ ] Default nil installation, ordinary adapter mismatch, foreign governor, declared permission without grant (resolver blocks), grant without declaration (handler refuses), missing registered identity and unopened/unsafe coordinator all fail without backend mutation. Installed seams+host1.1 select profile1.1; absent seams+environment1.1 cannot select1.1; host1.0 stays0. Exact canonical1.0 connection with copied top-level fields but another1.1 publication handle cannot elevate profile.
- [ ] Raw oversize and size mismatch, wrong incarnation/kind, malformed schema/shape/type, zero/stale/max sequence; no Data take before quota admission and no decode before verified count. Malformed/quotadenied/preclaimbusy consumes no sequence; accepted C7a failure consumes it. No response cache/replay and no automatic retries. Reused UUID/new sequence behavior is explicit.
- [ ] Fill actual memory quota before request: refusal occurs before adapter take and before real keyed files change. Hold a forwarded real backend/governor operation and assert the8MiB protected workspace remains charged across process revocation/exit until its buffers unwind. Operation scope refunds afterward; backend scratch remains separately visible. Test default full-value request under the active64MiB provider allowance.
- [ ] Occupied action/source/service/storage reply credit blocks a new storage mutation before take/sequence/backend. Accepted storage reply remains in adapter after receiveStorageRequest returns and workspace refunds; its process capacity remains charged until observed exit. Receipt releases occupancy only, not process capacity. Foreign/duplicate/old receipt cannot release the next reply.
- [ ] Cross-kind late receipt regressions with a newer storage-reserved/accepted slot: the strong legitimate overlap is action ACK -> storage request/reply -> still-valid action completion, which must finish its own lifecycle without releasing storage credit/payload. Source/service have no corresponding early acknowledgment: their receipt ends/removes or marks their execution in flight, so old source/service callbacks after a newer storage slot are stale/duplicate refusal tests, with no slot release. Do not fabricate an early source/service receipt. Old deferred ingress cleanup cannot clear a new storage claim. Publication and storage staging cannot coexist in adapter or runtime.
- [ ] Real backend precommit gate: cancellation/disable/quiescence before runtime-to-coordinator handoff prevents invocation. After backend handoff, conservative C7a uncertainty is preserved; no stale read response is handed off. Real postrename/postunlink cleanup gate or sync failure proves acknowledged/outcomeUnknown survives coordinator close/runtime cancel while response delivery is separately suppressed. Check actual file visibility while held; no fake successful backend callback.
- [ ] RejectedBeforeHandoff retains no response and releases only that credit, while known mutation summary/file state survives. Wrong encoded payload or adapter-contract violations are not silently treated as success. Exact synchronous receipt permits the next request; observed exit drops retained payload and allows only a new incarnation/connection sequence state.
- [ ] Check direct and indirect launch plus deferred requiredBytes shrink preserve256KiB enabled delivery capacity and fixed credit metadata; legacy80KiB/default1.0 fixtures have only the separately approved C7b0 control delta. No process-capacity refund at receipt/requestStop; no new queue/owner history remains after repeated requests.
- [ ] First observe compiling behavioral RED for at least unauthorized profile elevation, credit-before-mutation and reply survival past scope/late receipt. Implement entire handler and run new tests plus slot-ownership, C7a, C6/protocol, composition, broker/deferred-completion and shutdown suites. Freeze exact delta/preimages/hashes, command exit status, actual RED/GREEN and gate/file/charge evidence. Root independently reviews then runs full serial suite and signed delivery. Do not claim native transport or SDK operational support.

## Review/dispatch boundary

C7b0 source is independently rejectable/approvable because the real acknowledgment/adapter-payload defect and exact ingress ownership can be proved without storage. The one-job-per-owner policy forbids simultaneous still-running legacy A and new legacy B; do not widen quota or fake admission to manufacture that overlap. Legitimate A completion versus a newer storage reply is C7b1 evidence. C7b1 consumes that approved ownership layer and C7a's final result API; it must not dispatch before root verifies that both are stable and budget permits the whole implementation, review and delivery. The extra work identified here is source-supported engineering scope, not an unresolved user product decision.


Preparation ledger: C7b0 prerequisite is in implementation. Complete C7b1 independent preflight APPROVED after weak coordinator binding, exact reserved/accepted cleanup, feasible legacy overlap tests and bounded fixture retention corrections. Exact independent report: `/private/tmp/cascade-keyed-storage-handler-independent-preflight.md`. Complete handler remains undispatched pending b0 reviewed delivery and weekly budget clearance.


Dispatch ledger: C7b0 fully delivered with740 tests / 75 suites,390 inputs,44 approved hashes,signed build/link and verified PID 8362. Root dispatched complete independently preflighted C7b1 to sole implementation worker at53% weekly use, with existing scratch/cache. Frozen implementation review/full delivery pending. SDK lifecycle remains undispatched.


Implementation refinement: recomputing max(512, 4×final ProcessCreditState.stride) covers the final inline representation for every process, including legacy processes. If larger than512 bytes, account for the measured fixed difference; legacy80KiB payload/default1.0 and conditional handler-owner allowance remain unchanged. This resolves the preflight test shorthand and adds no new architecture or allocation abstraction.

## Delivered result

Implemented and independently approved after the canonical-peer regression correction. Final 765 serial tests / 76 suites passed; 391 inputs and 45 reviewed hashes matched. Signed build, Applications link and normal restart to PID 11511 verified at 55% weekly use. See the [final verification](../verification/2026-09-13-addon-authenticated-storage-handler.md). Native transport, SDK client and app driver remain separate.
