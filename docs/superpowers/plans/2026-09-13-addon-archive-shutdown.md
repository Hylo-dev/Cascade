# C5 bounded shutdown checkpoint implementation brief

2026-09-13. IMPLEMENTED, INDEPENDENTLY REVIEWED AND DELIVERED after completed C4 delivery. This refines and supersedes the API/ordering and deadline wording in `/private/tmp/cascade-runtime-archive-shutdown-assessment.md`, incorporating all five findings in `/private/tmp/cascade-runtime-archive-shutdown-preflight-review.md`. Implement only after C4 review/delivery and root dispatch. No code, tests, builds, scratch, caches or agents were used for this refinement.

## Scope and evidence

Only `CascadeKit/Sources/CascadeRuntime/AddonRuntime.swift`, `Storage/AddonStorageCoordinator.swift`, and focused new runtime/coordinator shutdown tests. No SwiftData backend/worker, codec, asset store, broker implementation, app event driver, timer, task group, generic scheduler or native-provider changes.

Lifecycle references below use frozen C3 source, avoiding concurrent C4 edits:
- `/private/tmp/cascade-runtime-archive-c3-frozen/AddonRuntime.swift`, SHA256 `05307c43310410d3112239072bb41ddd496671d0b06cee7485da4e8d83a2a9c4`.
- `/private/tmp/cascade-runtime-archive-c3-frozen/AddonStorageCoordinator.swift`, SHA256 `ccabb2cecf8e499a7ec584da18acfd877f412e6f558259cd9842896e15f67c55`.
- Runtime stop:1842, snapshot:1876, archiveInstalled:2485, beginAdmission:3328, validateOperation overloads:3364/3377, connectedOwner:3571, drainDeferredCleanup:3740, validateDeferredServiceCompletion:3860.
- Coordinator close:411, claimArchiveOperation:484, prepare/validate archive operation:505/532, closeBackends:634, available:655, invalidateReadiness:676, finish:683.

C4's currently written `saveAdmittedArchive`, `ArchiveFlushState`, per-owner scalar progress and bounded facade errors are reuse seams, not an additional review of unfinished C4. Rebase line references after its freeze. The approved design:272 already prescribes admission stop, lease revocation, bounded checkpoint opportunity, then process stop. No new product decision is needed for these mechanics; latest successfully committed generation remains the guarantee.

## 1. Runtime one-way phase and exact admission purpose

Add one prepaid optional `ArchiveQuiescence` value (private nonce and absolute monotonic `Duration` deadline); its presence permanently denies normal admission. Terminal `stopped` remains separate. The runtime creates tickets only through:

```swift
func beginArchiveQuiescence(until deadline: Duration) throws -> ArchiveQuiescence
func requestStop() -> StopProgress
// Existing stop() async remains: requestStop(); await drainIfNoActiveAdmission().
```

`beginArchiveQuiescence` is actor-isolated and has no await. Require a valid currentInstant, deadline >= zero and deadline > current monotonic time on first begin. Never convert from civil time or invent a timeout. Same accepted deadline returns the same ticket while quiescing; a different deadline, or any begin after terminal stop, rejects. A ticket from another runtime fails because only this runtime's exact stored nonce is accepted. Repeated begin never advances authority twice.

First begin stores the phase/ticket, advances authority, invokes dispatcher.stop, clears authoritative service permission/grant maps, and schedules existing deferred broker shutdown/reconciliation and applicable unsent-action cleanup. Do not await broker work or run full cleanup here. Retain canonical publications, assignments and asset pins privately for checkpoint under their existing charges. Do not release handed-off service executions, delivered jobs, provider/native reservations, or import/pin references merely on grant revocation. Existing reconciliation/stop/exit paths decide their actual release; requestStopOnce remains deduplicated.

`requestStop` extracts the existing stop prefix through deferred scheduling, without its final drain. It sets stopped and revokes the checkpoint ticket, closes asset creation, removes publications/assets, and requests process stops exactly as existing stop. Repeated calls return current scalar progress without duplicate stop requests. `StopProgress` contains `cleanupPending` and `retainedProcessCount`; these mean logical pending work/canonical process records, not observed OS exit or physical database close. Existing async stop always invokes the drain after the idempotent prefix so it can finish a prior nonawaiting request.

Use a private `AdmissionPurpose` (`normal` or `archiveQuiescence(ticket)`) stored in AdmissionOperation, defaulting to normal. Only the shutdown archive method can construct the exceptional purpose. This purpose must reach the existing shared B2 save validation helpers; do not duplicate capture/encoding/save code and do not add an ignoreStopped Boolean.

Source-enumerated authority placements:
1. Both beginAdmission prechecks, including its post-drain check: normal purpose requires no quiescence; shutdown purpose requires the exact current ticket, unexpired monotonic window, not stopped and current enabled owner.
2. AdmissionOperation validator: exact active operation/owner/authority revision plus the matching purpose gate. UInt64 revision-only validator remains normal-only and rejects quiescence.
3. connectedOwner: reject quiescence. This closes ack, completion-only and service result paths that do not always claim admission.
4. archiveInstalled: factor immutable identity/common-governor/catalog/digest checks from lifecycle-purpose checks; ordinary binding/save/restore remains normal-only. Shutdown uses only the typed exception; enabled/disabled, identity, accepted resolution, digest and feature checks remain unchanged.
5. validateDeferredServiceCompletion: add the phase guard alongside authorityRevision and !stopped. It is called before prepareInvocationCompletion, after that await, and after commitInvocationCompletion BEFORE publication completion activation (3747–3790). This rejects even a completion copied out of the outer dictionary before quiescence. Preserve the existing cancel-preparation, cancel-ingress and provider-stop catch path; clearing deferredServiceCompletions alone is insufficient.
6. snapshot returns no publications during quiescence/terminal state; assetImage returns nil. Diagnostic counts stay bounded; Snapshot.isStopped still means terminal. Private B2 canonical visitors remain available only through admitted checkpoint. Earlier borrowed CGImages retain their existing native lifetime protection.
7. Disable remains immediate and removes the selected owner's private checkpoint authority/content. Expiry/prune still update canonical state and C4 dirty tags; they never reopen normal admission. Normal C4 flush-state queries report unavailable during quiescence; private shutdown selection uses the narrow ticket path.

## 2. Exact runtime attempt result, not error inference

Add an internal bounded `ShutdownArchiveFailure` with runtime(AddonFailure.Code), archive(SwiftDataArchiveFailure), cancelled, unavailable cases. Convert unknown errors immediately; no arbitrary Error/NSError payload escapes. Add:

```swift
enum ShutdownArchiveAttempt: Sendable {
    case busy
    case skipped
    case windowClosed
    case refused(ShutdownArchiveFailure)       // no accepted runtime operation
    case failed(ShutdownArchiveFailure)        // accepted runtime operation
    case committed(SwiftDataArchiveSaveOutcome)
}
func saveQuiescingArchive(
    owner: AddonID,
    to archive: SwiftDataArchive,
    quiescence: ArchiveQuiescence
) async -> ShutdownArchiveAttempt
```

Validate exact ticket and immutable backend binding before changing progress/attempt state. A dirty owner includes pending AND retryRequired (`current != saved`, ignoring `attempted` suppression); shutdown is one host-selected retry opportunity. Clean or disabled/unavailable owners are skipped. Wrong binding returns refused without modifying runtime markers.

Distinguish busy at the actual actor-local admission seam: after authentication, before any await, inspect activeOperation/cleanup ownership and return busy if it cannot claim. Do not catch resourceDenied and guess busy, and do not query archiveFlushState afterward. Extend the private begin-admission path with an exact busy result if needed; its post-cleanup suspension validation must still use the ticket. A quota/resourceDenied after an AdmissionOperation is created returns failed. A cancellation/revocation during pre-admission deferred cleanup returns refused (or windowClosed for elapsed/terminal ticket), not busy. Only busy consumes no selected coordinator row. Track operation acceptance in a local scalar, not a per-owner table.

Once accepted, reuse C4's lazy archive.start INSIDE runtime admission and B2 saveAdmittedArchive. Set the current attempted marker only for the accepted dirty attempt; recheck dirty state after deferred cleanup. Return skipped if no longer dirty. Each runtime-owned await rechecks purpose/owner/clock, with one final check immediately before calling archive.save. Preserve C4's captured-tag acknowledgment on known commit, not the current tag. Keep ordinary finishAdmissionAndDrain ownership/liveness; no new cleanup task is created. Once the backend returns committed, return committed after cleanup even if the window closed meanwhile. Do not postvalidate and relabel it.

The deadline bounds admission and the runtime-to-backend handoff only. Once archive.save is called, its whole accepted operation can commit after elapsed deadline, cancellation or logical stop. Its existing beforeCommit filesystem check receives NO runtime ticket/deadline callback. Never claim every expiry before native ModelContext.save rolls back.

## 3. Coordinator context coexists with active work

Add ONE prepaid optional `ArchiveShutdownContext`: immutable runtime reference, requested deadline, context UUID; phase acquiring/ready/terminal; optional acquired ticket; cursor; unvisited row count. No per-owner array, queue or graph. Retain it for coordinator lifetime so terminal begin cannot reopen; clearing only after actual disposal is not a reusable shutdown window. Context may coexist with the existing active operation slot.

```swift
func beginArchiveShutdown(runtime: AddonRuntime, until deadline: Duration)
    async throws -> ShutdownProgress
func flushNextShutdownArchive() async -> ShutdownStepResult
func finishArchiveShutdown() async -> ShutdownProgress
func requestClose() -> CloseStatus // actor-local synchronous logical revocation
// Existing close() async throws performs/retries actual closeBackends.
```

ShutdownProgress is scalar: phase acquiring/ready/terminal, unvisitedOwners (registry rows not visited), cleanupPending. ShutdownStepResult distinguishes busy, exhausted, windowClosed, failed(owner,failure,accepted,unvisitedOwners), committed(owner,outcome,unvisitedOwners). A result with failed tags or exhausted does NOT assert all state clean/durable. Bounded coordinator failures can use the existing C4 mapper; no hidden error payload.

First begin is permitted while ordinary work is active, but only from an already initialized ready coordinator (not during initial startup/explicit closing). The first-begin readiness check explicitly requires readinessEpoch != nil and !isClosing; do not call available(), because its active-operation rejection would contradict this contract. Validate finite input representation/nonnegative deadline before mutation; the runtime authoritatively validates its current clock. Store acquiring context and immediately invalidate ordinary readiness/Owner epochs. DO NOT assign active, clear active, overwrite its operation ID, erase retained BackendAccess/ArchiveAccess, or start parallel checkpoint work. Await runtime.beginArchiveQuiescence; store returned ticket first, then check context phase. Transition to ready only if the same context is still acquiring. On failure remain fail-closed terminal, request runtime stop and synchronous coordinator closure, then return the bounded failure. Backend work already accepted retains its exact finish path and known-commit semantics.

Repeated begin with the same runtime object and exact deadline returns current progress (including acquiring/terminal) and does not perform a second ticket request. Different runtime or deadline rejects; no deadline extension, ticket replacement or terminal reopen. Ordinary coordinator start rejects once this shutdown context exists. Existing start/restart behavior outside a shutdown context remains unchanged.

Concurrent finish/requestClose marks context terminal synchronously BEFORE awaiting runtime entry. A late begin result is retained but cannot reopen the window; issue idempotent requestStop if necessary. Existing active work finishes only through finish(originalOperation), whose exact-ID check remains unchanged.

## 4. One pass, one accepted attempt per step

Initialize cursor once from the existing C4 round-robin index and unvisitedOwners = registrations.count. No wrap into a second pass. A shutdown step requires ready context; acquiring or active != nil returns busy without consuming a row. It claims the existing single active slot with its own operation ID, preserving serialization through every await and releasing only that ID in defer.

Use privately retained registry/archive slots, never a revoked public Owner capability. For each selected row, call the exact runtime shutdown attempt method with the stored ticket. It authenticates binding before lazy start. If no archive slot exists the row is unavailable/skipped. Clean, disabled and unavailable rows consume one visit; refused consumes one visit and returns failed with accepted=false. Busy consumes neither row nor runtime attempt and immediately returns busy. windowClosed starts no further work and returns windowClosed without scanning. A failed accepted attempt consumes one visit and returns failed; resource denial after admission is a failure, not busy. A committed attempt consumes one visit and returns committed. Skipped rows may be scanned within the bounded remaining row count until one attempt is returned or the pass is exhausted. After every runtime await, recheck the same local context before selecting another row; skipped/refused/window results must never continue scanning after a concurrent terminal transition. A known committed result still returns unchanged. This local check never replaces runtime ticket validation at handoff.

After a consumed row, advance cursor modulo the fixed registry and decrement unvisitedOwners once. An owner whose later expiry/prune creates another tag is never revisited during this context. Its newer tag remains dirty after an older capture commits. The pass is best effort and may end unsaved. A failed retryRequired owner cannot starve the next row and cannot spin. Returning from an accepted save during concurrent terminal transition still reports a known commit; context validation must not undo it. Cursor accounting may update the same terminal context but never changes its phase back to ready.

## 5. Logical close and draining are separate

Extract coordinator's synchronous readiness-invalidating prefix as requestClose. It also terminally revokes any coordinator shutdown context, leaves active untouched, marks cleanup outstanding and returns closed only if cleanup is already known complete; otherwise draining, including idle-but-open backends. It does not call archive.suspend, checkpoint.close, keyed.close, governor methods, or create a Task. Being synchronous on the coordinator actor, requestClose closes coordinator admission only: it cannot synchronously invalidate the separate runtime ticket. Already accepted runtime work remains owned until finish/close actually invokes runtime.requestStop, its deadline is observed at a supported runtime boundary, or it completes. Do not claim cross-actor immediate ticket revocation. A single prepaid cleanup-pending scalar suffices; no physical-close claim.

finishArchiveShutdown first terminally revokes its context, invokes runtime.requestStop, then invokes coordinator requestClose synchronously and returns progress WITHOUT awaiting closeBackends. Awaiting the runtime actor hop is necessary for a logical stop receipt but is not a strict wall-time scheduling guarantee. No backend cleanup await belongs in this method. While that actor hop is pending, the terminal coordinator context already prevents new checkpoint steps; runtime rejects further handoffs once requestStop enters. No claim of zero cross-actor scheduling latency is made.

Existing explicit close begins with requestClose, returns draining if active exists, otherwise claims its existing closing operation and awaits the existing closeBackends. Preserve references/tokens throughout. Before invoking requestClose, close captures the context runtime if any; afterward it invokes that runtime requestStop regardless of whether the context was acquiring, ready, or already terminalized by an earlier requestClose. Do not condition this actor hop on the post-requestClose phase. The context runtime remains retained, including while ticket acquisition is still pending, and backend drain follows the actual logical-stop hop. Repeated close can finish after a previously accepted operation exits. A held idle backend/governor cleanup gate must not delay finishArchiveShutdown's logical receipt. Do not make finish call awaited close to obtain a seemingly stronger status.

## 6. Quotas, limits and caller obligation

Prepay control state at normal construction/owner setup: runtime +max(256,4*MemoryLayout<quiescence/admission-control>.stride) per OwnerPool (256 each gives8192 maximum32 owners); coordinator +max(1024,4*MemoryLayout<shutdown-control>.stride) once, covering retained runtime/ticket/phase/cursor/results and cleanup scalar. Do not count existing C4 256/owner and cursor allowance twice. No ownerless checkpoint graph/allocation is created; terminal scalar state remains within the runtime/coordinator's existing bounded object allocation even for an empty catalog.

No new task, lease system or maximum buffer per owner. Existing one-owner canonical charges and B2 scopes stay unchanged: open/read16MiB+64KiB, outer payload8MiB+64KiB+128, reviewed capture/encoding scopes, each raster-copy scratch2*byteCount, backend save8MiB+2*candidate+64KiB, existing1024 bookkeeping per reservation. Logical stop and requestClose require no fresh quota admission. Retained native images and pending controlled buffers/observed disk keep protected charges until actual release/completion, even while draining.

The host supplies the monotonic deadline and calls stepped methods/terminal finish from its existing event/lifecycle owner. This slice owns no wake, timer, detached cleanup task or event loop. SwiftData synchronous construction/fetch/save can outlive the window, and even actor entry is not hard real-time. Do not use a task-group timeout or promise physical native completion by a deadline. Actual app shutdown-driver wiring remains a following, separately reviewed composition; these primitives alone do not claim automatic app termination delivery.

## 7. Finite TDD evidence and order

A. Runtime phase/stop extraction: compiling behavioral RED for immediate normal admission/connected callback rejection, empty public snapshot/nil image, real canonical timeline+PNG still privately checkpointable, ordinary save denied, immediate disable, wrong runtime/ticket/binding, valid/elapsed monotonic deadlines. Existing stop semantics still pass with requestStop followed by explicit stop drain.

B. Deferred authority: gate real forwarded service completion before and after broker preparation; quiesce while held. No late publication/completion activation after release, ingress/preparation cancellation occurs, handed-off reservations remain until existing release evidence, no duplicate stop/release. Do not replace broker with a fake successful commit.

C. Runtime attempt contract: deterministic busy BEFORE actual admission returns busy; quota denial AFTER admission returns failed. Verify clean/refused/windowClosed versus accepted result without a later state query. Gate BEFORE runtime archive.save handoff and advance clock: no new save/prior generation preserved. Gate AFTER accepted backend handoff, stop/expire, and allow real save: preserve any known committed revision and protected quota until completion. Cancellation claims must name the actual cancellation-check gate exercised.

D. Coordinator races: begin during real held keyed write and accepted archive save; active ID/access survives and ordinary capabilities revoke. Finish/requestClose while ticket acquisition returns cannot reopen. Same begin is idempotent, other runtime/deadline rejects, terminal never reopens. Hold an idle archive/governor cleanup gate and prove finish receipt arrives without releasing that gate; explicit close drains later.

E. One pass: busy selected runtime consumes no row then succeeds when idle; failed/debt retryRequired row consumes one visit and next owner proceeds; clean/disabled rows consume visits; exhausted != clean; newer expiry tag on a visited owner stays dirty with no wrap. Known commit survives concurrent finish and its exact captured tag is acknowledged.

F. Quota: startup control allowance admitted, full-state quota still permits quiesce/requestStop/requestClose, no new buffer per registry row, actual pending native/disk memory protections survive logical terminal state. Cover only relevant adjacent runtime/coordinator/service/asset lifetime suites; no new native-provider runs or power-loss claims.

Implement in these two production files with focused tests, freeze exact diff/hashes/evidence, then independent review. No genuine unresolved architecture choice remains for this bounded best-effort slice. A hard physical save-completion deadline or durable provider-ack guarantee would be a different requirement and is intentionally not introduced.


Final preflight refinements: use readinessEpoch/nonclosing guards without available() for first begin; recheck terminal context before scanning any further row after an await; capture context runtime before requestClose and invoke requestStop even for an already terminal context. Synchronous requestClose only revokes coordinator admission; no immediate cross-actor runtime revocation claim. All terminal transitions use prepaid control state.


Dispatch status: independently preflighted with the explicit final ordering corrections; implementation remains gated on C4 independent review, full package/build/restart delivery and root budget check. No C5 source work has been dispatched.


Dispatch ledger: C4 independent review and full delivery completed (694 tests / 70 suites, 382 frozen inputs, signed build/link, PID 99945). Root dispatched C5 to the sole implementation worker with the existing scratch at 45% weekly use. Exact final ordering corrections above are mandatory. Final C5 review and delivery remain pending.


Next separately preflighted slice, after C5 delivery: [dedicated keyed-storage frames](2026-09-13-addon-keyed-storage-frames.md). Existing contracts already require these frames; defaults remain protocol 1.0 until authenticated handling exists. No runtime transport or application bootstrap is claimed by that future value/codec step.


Implementation-time cleanup refinement: explicit coordinator close owns eventual runtime cleanup as well as backend cleanup. After synchronous requestClose and runtime.requestStop, preserve any active coordinator operation by returning draining. Otherwise claim the existing closing operation, await the existing runtime.stop, refresh its scalar StopProgress, then invoke the existing backend close path. Return draining while known runtime cleanup remains pending even if backend cleanup has completed. requestClose/repeated close also include that known pending runtime state in their receipt. Prompt finishArchiveShutdown never awaits these drains. This reuses existing cleanup and requires a real held-cleanup-gate regression plus eventual completion; retainedProcessCount remains a canonical-record diagnostic, not physical-exit evidence. Root approved this finite ownership clarification before implementation.


Handoff refinement: the shared output-reservation closure calls one private runtime-actor helper that validates the exact operation/purpose/deadline and immediately invokes archive.save before its first suspension. Do not validate through a separate awaited actor method and then initiate save from the nonisolated closure after the helper returns. This preserves the same prepaid payload/captured-marker scope and known-commit outcome, adds no backend callback/reservation, and only guarantees the runtime handoff boundary, not native commit-time expiry. Root approved the narrow self-review hardening; final tests must run after it.


C5 delivered: seven hashes approved, 178 focused/adjacent tests and 710 full serial tests in 71 suites passed. 383 inputs identical, signed build/link, verified normal restart PID 2818; weekly47%. [Verification](../verification/2026-09-13-addon-archive-shutdown.md). C6 dedicated storage frames is now separately dispatched under its approved preflight.
