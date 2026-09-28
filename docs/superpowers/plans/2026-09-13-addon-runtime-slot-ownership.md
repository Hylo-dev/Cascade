# Exact runtime ingress and delivery ownership

2026-09-13. Implemented, independently reviewed and delivered; approved proposal follows.

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


Source assessment and future complete storage-handler scope: `/private/tmp/cascade-keyed-storage-handler-brief.md`. C7b1 is not part of this implementation boundary.


Dispatch ledger: C7a delivered with 732 tests, signed build/link and verified PID 6324. Corrected b0 preflight approved with exact ingress lifetime and one-job feasible tests. Sole implementation worker dispatched at50% weekly use; review/full delivery pending.


Delivery ledger: independent implementation approved;93 focused tests/six suites and740 full serial tests / 75 suites pass.390 inputs/44 approved hashes verified; signed build/link and normal restartPID 6324→ 8362 successful. Weekly53%. [Evidence](../verification/2026-09-13-addon-runtime-slot-ownership.md).
