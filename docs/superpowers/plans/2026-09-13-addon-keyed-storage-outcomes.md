# C7a — concrete coordinator keyed-request outcomes

2026-09-13. Implemented, independently reviewed and delivered. The approved proposal below defines the exact scope. C6's validated StorageRequest is the dependency; use its frozen API after delivery. C7b authenticated ingress/reply, native transport and app composition remain separate.

## Scope and production API

Own only `CascadeKit/Sources/CascadeRuntime/Storage/AddonStorageCoordinator.swift`, NEW `CascadeKit/Tests/CascadeRuntimeTests/AddonStorageKeyedRequestTests.swift`, and minimal test-helper visibility/gate adjustments in existing keyed/coordinator tests if needed. Do not change AddonKeyedStorage, C6 DTOs, existing generic perform/read/write/remove, archive save/restore/shutdown semantics, runtime/adapter or package configuration. No new backend abstraction or injected commit callback.

Add module-internal nested bounded values and one concrete method:

```swift
enum KeyedRequestRefusal: Equatable, Sendable {
    case invalidRequest
    case invalidOwner
    case unavailable
    case busy
    case cancelled
    case readFailed(AddonFailure.Code)
}
enum KeyedRequestResult: Equatable, Sendable {
    case read(Data?)
    case acknowledged
    case refused(KeyedRequestRefusal)
    case outcomeUnknown
}
func executeKeyedRequest(_ request: StorageRequest, owner: Owner)
    async -> KeyedRequestResult
```

This concrete host operation returns a bounded result with at most65,536-byte read Data, never raw backend/Owner access or arbitrary Error/NSError/errno descriptions. `acknowledged` means the backend successfully returned from write/remove, not a new durability guarantee or permission to deliver a response to a revoked provider. Removing a missing key is acknowledged under existing backend semantics. outcomeUnknown neither claims success nor proves no mutation; callers must not automatically replay it.

Keep correlation separate: requestID is carried by the caller's C6 value but the coordinator does not store a replay table, mint IDs, encode a response or perform request matching. C7b later binds this result to its canonical outstanding request and response credit.

## Exact pre-call and execution ordering

1. Check cancellation. Check current available() (readiness and single active slot), validateOwner(owner), then request.validate() and existence of the current private backends. These are all synchronous actor-local checks. Map failure before backend invocation to the exact refused case. Unknown validation errors become invalidRequest; a missing backend becomes unavailable. No operation slot is claimed and no disk method called if these checks fail.
2. Capture the same private BackendAccess used by perform, mint one existing Operation(kind:.normal), assign active and `defer { finish(operation) }`. No extra queue/table, parallel operation or replacement of active. The only caller-supplied Owner must belong to this coordinator's current readiness epoch/fixed row. The backend operation always receives access.owners.keyed and storageClass:.data; never provider class/owner/path input.
3. Switch on the validated operation. Read calls keyed.read; write calls keyed.write with validated nonnull value; remove calls keyed.remove. No optional-value fallback can accidentally convert malformed write into an empty write. Store no request/value on coordinator properties.
4. For read, AFTER backend success and before returning Data: recheck Task cancellation, exact active operation, !isClosing and validateOwner. If any check fails, discard Data and return refused; no read bytes escape stale authority. Check returned value<=65,536 defensively. Backend read failures map as below, with no fabricated bytes.
5. For write/remove, once the `await` call to the concrete keyed method is made, **any thrown error maps outcomeUnknown**. This intentionally includes backend busy, quota, cancellation, cleanupRequired and committedDurabilityUncertain; this slice has no precise backend acceptance/commit result to prove which side of that boundary failed. Do not classify by a later status/read or a description. Conservative uncertainty is truthful even when the filesystem in a particular test remained unchanged.
6. A write/remove that returns normally produces acknowledged immediately, with only nonthrowing exact-operation finish in defer. Do NOT run Task.checkCancellation, readiness/Owner validation or the generic perform postcheck after successful mutation. A concurrent coordinator close/cancel does not relabel known success. Coordinator close during active work still returns draining and leaves the active ID/access intact; explicit later close performs existing cleanup.

There is no await between pre-call validation and assignment/dispatch apart from the concrete backend hop. Cancellation arriving after the last pre-call check is therefore an after-handoff uncertainty if the backend throws. This is a truthful observation boundary, not an assertion about native syscall start time.

## Bounded error mapping

Pre-call:
- CancellationError -> refused(.cancelled).
- Coordinator.Failure.busy -> refused(.busy).
- invalidOwner -> refused(.invalidOwner).
- unavailable/invalidConfiguration or missing retained backend -> refused(.unavailable).
- request validation/type combination failure -> refused(.invalidRequest).

Read backend failures (no mutation was requested):
- CancellationError -> refused(.cancelled).
- KeyedStorageFailure.invalidOwner/invalidTicket/closed -> refused(.readFailed(.sessionRevoked)).
- busy/quotaExceeded -> refused(.readFailed(.resourceDenied)).
- invalidKey/oversized -> refused(.readFailed(.invalidPayload)).
- futureFormat -> refused(.readFailed(.versionConflict)).
- invalidConfiguration/unsafePath/unrecognizedEntry/corrupt/staleRevision/cleanupRequired/committedDurabilityUncertain/io -> refused(.readFailed(.dependencyUnavailable)).
- AddonFailure from resource access -> refused(.readFailed(failure.code)); discard its text.
- Any other read error -> refused(.readFailed(.dependencyUnavailable)).

Post-read coordinator checks map as their pre-call equivalents. Map only the compact existing code enum, not a retained error payload. Mutating backend catch is always outcomeUnknown regardless of enum/code; keep it visibly separate so a future overly helpful common error mapper cannot turn it into a retry-safe refusal.

## Validation/profile and caller memory contract

The argument is a C6 immutable StorageRequest. Revalidate it cheaply at entry; do not reencode/decode. Its fixed schema/operation rules, exact key UTF-8 semantics and value bound are C6's responsibility. The method contains no raw Data codec, protocol1.1 negotiation, peer identity, storage.own grant or SDK authorization. Owner is a trusted host capability from the fully reconciled registry; that is the only authorization boundary implemented here. Host tests may construct requests directly; the later authenticated handler must check canonical connection/profile/permission before calling. No profile field or new payload owner/class/batch is added.

The caller owns/prepays request DTO memory before actor submission and owns returned read Data until release. No raw-frame reservation is claimed here. Keep caller protection through this method and subsequent response construction/handoff; this method returning does not release that external reservation. Conservative application-value accounting can reserve two65,536-byte buffers plus4KiB key/scalar/correlation allowance for the boundary (135,168 bytes), separate from any raw input/encoding/parser scopes; this is a caller formula, not an internally enforced or total-RSS limit. One operation cannot simultaneously have a write value and read result, but the conservative coexistence allowance avoids relying on COW or caller copies. The existing keyed backend separately reserves its267,776-byte record scratch, staged value/state and disk coexistence.

No new retained coordinator fields are necessary: BackendAccess and Operation already fit the prepaid fixed metadata/one active-operation convention. The result/request reference is an operation-local async lifetime covered by caller value allowance plus existing fixed control allowance. Therefore add NO new long-lived control reservation or metadata increase merely for enum declarations. If implementation unexpectedly introduces retained properties, stop that expansion and justify the exact extra quote rather than silently relying on this assessment.

## Real gates and precise evidence

Use secure temporary three-root coordinator fixtures with complete fixed registrations and the real shared governor/backend. Existing `AddonKeyedStorageTests.swift` has KeyedFileFaults (forwarding real syscalls; selective write/unlink/directory-sync failures) and KeyedResourceGate (real governor result forwarding, temporary/diskResize/release). Coordinator factory already accepts keyedFileOperations and RuntimeResourceAccess. Reuse those fixtures by the smallest visibility change, capturing preimages; avoid duplicate fake backend implementations.

The release gate's FIRST write release occurs during stage, BEFORE rename. It does NOT prove postcommit cancellation. For a write final-return case, extend the test gate with a bounded skip count, then hold the commit-phase release after the stage scratch release. Verify through the actual record file that the new value is visible while held before close/cancel. For remove, there may be no scratch/retention release: hold the actual diskResize return from finish's pool shrink AFTER unlink and verify the record is absent while held. These are real forwarded governor-return gates, not fake storage successes. The test must identify the actual phase by file evidence, not just rely on a guessed invocation count.

For post-rename/post-unlink durability uncertainty: create a stable key and class directories first, arm directory-sync failure immediately before replacement/remove, and forward the real rename/unlink. Existing KeyedFileFaults can inject the sync error; if staging also syncs, use a narrow same-fixture condition targeting the final class-directory sync after the pending candidate has disappeared (write) or named value has disappeared (remove). Record syscall/file evidence to prove the intended point. Do not fail ancestor mkdir sync and label it a post-rename test. Reset faults before fresh authorized read/reopen verification.

Existing paths supporting these seams: keyed commit has rename+accounting+sync followed by await finish (AddonKeyedStorage.swift:432–490); removeFile unlinks+updates charge then syncs (:991–1015); finish (:715 onward) releases reservations and shrinks pools. No production callback or async hook inside filesystem commit is needed.

## Finite TDD matrix

1. Two real owners: execute full65,536-byte write with256-byte key, read, empty read value, missing read, remove and remove-missing. Verify bytes through existing read/record and no cross-owner/cache effects. Request IDs are not used as paths or owners.
2. Wrong coordinator Owner, old epoch after close/reopen, not-ready, competing active operation, pre-cancelled Task: exact refused case and unchanged real files. Busy checks consume no operation/side effect. Invalid request entry validation can use a real decoded/constructed C6 value only where its API permits; do not unsafeBitCast immutable DTOs merely to test unreachable malformed state. C6 already proves malformed wire rejection.
3. Forwarded temporary/resize gate before mutation then task cancellation: file stays old and result is outcomeUnknown, demonstrating intentionally conservative AFTER-handoff mapping. Compare with pre-cancelled Task refused(.cancelled).
4. Parameterized write/remove: hold real FINAL cleanup return after rename/unlink, verify new value/absence while held, close coordinator (draining) or cancel task, release gate. Result must remain acknowledged. This is the key compiling RED against a naive wrapper using generic perform.
5. Parameterized write/remove: inject actual postvisibility directory-sync failure; result outcomeUnknown, actual new bytes/absence remain, protected disk accounting remains truthful. Distinguish injected fsync failure from physical power loss; do not claim crash-durability qualification.
6. Read held before/final backend return, coordinator close/cancel while held: result refused and no Data. Subsequent explicit close/reopen yields fresh Owner and correct persistent bytes.
7. Quota/IO failure after mutating backend invocation maps outcomeUnknown; no implicit retry. Normal successful read after resetting a fault can reconcile/observe the actual value. Assert new method creates no extra permanent governor state charge and never releases another owner's storage; existing backend quota/lifecycle tests remain adjacent coverage.

Start with real compiling RED for known mutation return under close/cancel, then implementation/GREEN for new tests plus keyed/coordinator suites. Keep existing generic coordinator write's postcheck semantics unchanged and test both methods where useful to demonstrate the intentional new operation contract. Freeze exact source/test diff, preimages, hashes, API/error mapping and syscall/gate evidence. No backend outcome redesign is necessary for this conservative slice; any discovered genuine inability to prove a gate is a test-fixture refinement, not a user product decision.


Root source assessment confirms the concrete coordinator/backend ordering and exhaustive bounded failure mapping. In gated tests, release every held forwarded gate on assertion, error and cancellation paths; actual file visibility/absence while held is required before claiming a postcommit gate. The first stage scratch release alone is not that evidence. Independent final preflight remains required before C7a dispatch.


Dispatch ledger: independent preflight approved without architectural changes. C6 delivery completed with 723 tests, signed build/link and verified PID 4658. Root dispatched this exact scope to the sole implementation worker at 48% weekly use; implementation and delivery evidence remain pending.


Delivery ledger: three frozen files independently approved, 72 focused tests / five suites, 732 full serial tests / 74 suites, 389 input files and 42 approved hashes verified. Signed build/link and normal restart PID 4658 → 6324 succeeded. Weekly use:50%. See [verification](../verification/2026-09-13-addon-keyed-storage-outcomes.md).
