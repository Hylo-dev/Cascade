# C4 — bounded significant-event archive flushing while enabled

Independent preflight approved with the terminal-history marking correction incorporated below; not implementation authorization. Execute only after C2/C3 independent review and their complete delivery verification, with root's explicit dispatch and remaining weekly budget. Current implementation remains in the [retained-registry plan](2026-09-13-addon-archive-registry-integration.md). Shutdown quiescing is a following separately preflighted slice.

## Discovery and scope

Graph-first search for AddonRuntime/AddonStorageCoordinator/DeadlineQueue again returned `project not found or not indexed` for Cascade; exact-file/targeted search fallback was used. Current runtime is an internal actor with no retained task queue or wake callback. `serviceDeadlines`/`nextDelay` are explicit host calls; AddonRuntimeAdapter has transport/process methods, no archive/event-loop wake API. C3 is specified by `/private/tmp/cascade-runtime-archive-c2c3-brief.md`, not yet implemented at this assessment.

This first slice provides automatic marking of significant canonical changes and an explicit one-attempt host-event flush call. It does not claim that production app bootstrap/event-loop wiring exists. Do not add Task-per-publication, a generic scheduler, per-owner timers, a debounce delay, AsyncStream buffering, or a fourth DeadlineQueue key. A host event driver can call the new method after accepted runtime events and must yield/return on no commit or failure; wiring that driver belongs to its actual owner-integration step.

Files:
- Modify `CascadeKit/Sources/CascadeRuntime/AddonRuntime.swift`: bounded archive progress in existing OwnerPool; exact mutation hooks; captured progress tag; pending-only entry sharing reviewed B2 save body.
- Modify `CascadeKit/Sources/CascadeRuntime/Storage/AddonStorageCoordinator.swift`: one round-robin scalar cursor and one-attempt facade using C3's accepted private operation/helper.
- Create `CascadeKit/Tests/CascadeRuntimeTests/AddonRuntimeArchiveFlushTests.swift` with existing real runtime/fake transport fixture plus real SwiftData/coordinator/governor.
- Extend focused existing B2 save tests only where their real gated-capture fixture is necessary; do not copy native PNG/runtime fixtures into a second harness.
- No PublicationState, AssetState, B1 codec, backend, governor, public SDK, adapter, app UI, launcher or dependency-library changes are needed for this slice.

## Exact proposed value/API contract

Nested runtime progress, one per already fixed and prepaid OwnerPool (runtime catalog maximum32):

```swift
private struct ArchiveProgress: Sendable {
    var current: UUID? = nil
    var saved: UUID? = nil
    var attempted: UUID? = nil
}
```

`current != saved` means dirty. `current != saved && current != attempted` means automatically eligible. Optional initial nil tags are clean. A fresh UUID per committed significant change is an opaque generation marker, not a counter/permission/serialized field; it avoids overflow bookkeeping and retains no history. Failed attempted generations stay dirty but suppressed (observable as retryRequired). A new significant change generates a new marker, and the existing explicit C3 save facade remains the force/retry path after a host-selected resource/lifecycle opportunity. No automatic retries on each nextDelay or timer tick.

```swift
enum ArchiveFlushState: Equatable, Sendable {
    case unavailable
    case clean
    case pending
    case busy
    case retryRequired
}

// Actor-local scalar query; no allocation of a list or owner table.
func archiveFlushState(identity: VerifiedAddonIdentity) -> ArchiveFlushState

// Same binding/admission/governor as saveArchive; nil means no eligible change remained.
func savePendingArchive(
    owner: AddonID,
    to archive: SwiftDataArchive
) async throws -> SwiftDataArchiveSaveOutcome?

// Existing saveArchive signature and unconditional explicit-save behavior stay compatible.

// Nested coordinator result; no private backend or callback escapes.
enum ArchiveFlushResult: Equatable, Sendable {
    case noCommit
    case committed(owner: AddonID, outcome: SwiftDataArchiveSaveOutcome)
}

enum ArchiveFlushFailure: Error, Equatable, Sendable {
    case coordinator(Failure)
    case runtime(AddonFailure.Code)
    case archive(SwiftDataArchiveFailure)
    case cancelled
    case unavailable
}

func flushNextArchive(runtime: AddonRuntime) async throws -> ArchiveFlushResult
```

`archiveFlushState` first checks fixed catalog identity, installed.enabled, accepted resolution and runtime enabled/not-stopped authority; failure yields unavailable. Otherwise equal current/saved yields clean; dirty state during active runtime admission/cleanup yields busy; idle dirty state with current==attempted yields retryRequired; remaining dirty state yields pending. Busy is only a transient scalar observation and does not mutate progress. Notice-only traffic and a restored baseline remain clean. The coordinator selects only pending. This is a selection hint, never authority across an await; B2 checks remain authoritative. noCommit means only that this invocation committed nothing: it does NOT imply every owner is clean, because retryRequired work can remain dirty.

## Runtime hooks and capture semantics

1. `commitPublicationAndAssets` (currently around line3060): before mutation, inspect the prepared changed-publication visitor to calculate one Boolean `changesArchive` for non-notice kinds. After BOTH validated synchronous commits, traverse the existing prepared ended-ID visitor and inspect POSTCOMMIT canonical `recordAccounting(id:)?.kind`; combine non-notice endings with that Boolean and mark the owner once. This covers a newly published widget/activity ended in the same batch, which has no precommit record and is excluded from the changed-publication visitor. The ended visitor already excludes missing/no-op ends. No new PublicationState API, retained array or fallible postcommit operation is needed. All failed batches remain unmarked; completion-only and notice-only changes do not mark.
2. `serviceDeadlines` (around1746): before synchronous expire, scan existing assignments without constructing a publication array. A non-notice record with contentBytes >0 whose current-date canonical publication lookup is nil identifies actual expiry; mark that owner in the same synchronous turn as expire. Due timeline projections without terminal expiry do not change the archived graph and do not mark. Confirm the existing expiry predicate matches this check in the implementation preflight; no new state visitor is necessary if current expiry invariants hold.
3. `pruneAssignments` (around3960): when an actual non-notice terminal record is removed, mark its still-enabled owner. This ensures a later saved empty owner generation can replace an older live archive; never resurrect or retain pruned graph/history solely for saving. No-op/missing record removal and notice-only pruning do not mark.
4. import/share/release asset aliases do not mark by themselves: archive capture uses canonical publication pins, not the provider import table. A newly published reference is already covered by step1. Provider exit without changed/pruned canonical archive records likewise does not cause a save.
5. Restoration starts from a clean progress baseline. Do not mark restoration as a new significant provider update or immediately rewrite the just-loaded generation. An elapsed restored record is already normalized safely by B2; no notice/replay behavior changes.
6. Disable remains immediate. Do not mark disabled/stopped owners as eligible or delay revocation for disk work. Existing stop/disable remove canonical authority before awaits; no flush after them and no relaxation of archiveInstalled. A successful save already committed may still report success under the existing rule.

Capture must carry the exact generation it represents. Add an optional scalar capturedChange to ArchiveCapture and ArchivePayload. Read it inside the same synchronous capture helper that reads/encodes the canonical records, before any returned borrowed graph crosses an await. A selection hint or timestamp before the old-revision backend read is not sufficient, because expiry/pruning can occur during that await.

Extract the existing B2 post-admission save body into a private method taking its already admitted operation and installed binding. Existing explicit save and new pending-only save use this one body; do not nest beginAdmission or duplicate the scoped encoder pipeline. The pending method checks eligibility again after beginAdmission's possible deferred cleanup. Validate exact current identity and common governor through archiveInstalled before beginAdmission and before any attempt-tag mutation. Only after runtime admission is accepted and authority is revalidated, set attempted=current. The pending-only method then calls archive.start inside that accepted runtime operation, revalidates authority after the await, and runs the shared B2 save body. This counts a real accepted lazy-start/debt/corrupt-model failure as an attempted generation while leaving pre-admission runtime-busy rejection untouched. There is no second runtime admission, token or callback. Existing explicit B2 save keeps its already-started-backend contract; explicit C3 save/restore retain their reviewed startup ordering. Both wrappers finish/drain their exact admission on success or failure. Busy/pre-admission refusal must not consume/suppress the pending generation.

After backend.save returns a known commit, set saved=capturedChange before finishAdmissionAndDrain. Do not set saved to the then-current tag. Cleanup may itself mark a newer generation; preserve it. No postcommit cancellation/authority check turns the known save into an error. If capture sees a newer change than the initially attempted tag, it may be acknowledged exactly on success; on failure that genuinely newer change remains eligible for a later single attempt. This is bounded by actual new changes, not a self-generated retry loop.

## Coordinator ownership and scheduling

Use existing C3 fixed registry, retained archive slots and single active Operation; add only a scalar round-robin index. Claim coordinator operation/readiness before selection. Scan at most registrations.count rows from the cursor, querying archiveFlushState for each verified identity. Revalidate operation/readiness after every query. No selected-owner array, pending Task, captured graph, per-owner callback or escaping backend is retained.

For the first eligible row, advance the cursor to (selectedIndex+1) modulo registrations.count before attempting it, then use C3's private accepted-operation path: privately get the archive, validate runtime binding, revalidate coordinator authority, and invoke savePendingArchive. For this pending-only branch, skip C3's separate lazy start because the runtime method owns startup under its accepted admission; do not duplicate framework preparation. This prevents pre-open debt from remaining automatically eligible forever and prevents a busy runtime from consuming an attempt. Close after the actual runtime call has been accepted can drain that accepted work under the same known-commit rule. Frequent first-row changes cannot permanently starve later dirty rows because the next call resumes after the previously attempted index. Return after this single attempted owner, including nil/noCommit. Do not call the public C3 save method recursively while coordinator.active is held; share/refine its private helper to select explicit versus pending runtime save. Existing explicit C3 signatures remain unchanged.

Return committed(owner,outcome) with only nonthrowing operation cleanup afterward. On uncommitted failure, map known coordinator/AddonFailure.Code/SwiftDataArchiveFailure cases into ArchiveFlushFailure and return control to the host; CancellationError maps to cancelled and unknown platform errors to unavailable. Never store or return an arbitrary NSError/userInfo/error description in C4 outcomes. Existing explicit C3 methods keep their error contract. No internal retry or immediate deadline is installed. The cursor allows another owner to be considered on a subsequent explicit event even if the previous owner's unchanged generation was suppressed. Busy runtime admission leaves its generation pending; after the competing event completes, the host may call the pump again. Wrong binding/foreign governor also cannot mutate attempted or saved. Return only the bounded C4 failure enum, never capture a backend error payload, generation bytes or graph in pending state or ArchiveFlushResult. C4 deliberately does not invent a production wake owner that is absent from the current application wiring.

## Controlled retention quote

Before constructing OwnerPool, add `archiveProgressBytes = max(256, 4 * MemoryLayout<ArchiveProgress>.stride)` to the existing per-owner base state admission in install. This quotes retained and overlapping copied scalar progress explicitly instead of silently borrowing unproven spare capacity from the16KiB metadata allowance. It adds256 bytes per owner on the current ABI, at most8192 for the32-owner runtime. requiredBytes already includes pool.baseBytes, so later cleanup cannot refund these fields independently.

The coordinator needs no per-row array: its existing fixed registrations/slots are reused. Add256 bytes to its fixed metadata quote for cursor/selection/result control, charged once under its existing admission owner convention. All quotes are established before controlled retention. No new reservation entry/lease family is introduced.

CapturedChange adds only an optional UUID to existing capture/payload controls; add an explicit128-byte conservative scalar allowance to B2's outer control scope before capture begins (outer quote becomes8MiB+65,536+128). Do not add another maximum-payload reservation. Existing capture leaves/metadata, raster copy, encoding and backend scopes remain unchanged and separately admitted. No graphs, decoded images or serialized generations are retained as pending work.

## Finite meaningful RED sequence

1. Compiling stubs for archiveFlushState/savePendingArchive/flushNextArchive, then real publish→pending→one flush→fresh-runtime restore. Expect behavioral RED because no archive is saved. Use real coordinator private-root setup and current B2 fixtures.
2. Commit many revisions before one flush; expect final revision/content in one stored generation. A second flush must not increment backend generation. Notice-only output, completion-only output, importing/releasing an unpublished image, snapshots and due-but-unexpired timeline projection must not create/save dirty work. Invalid rejected publication batch remains unchanged.
3. Add same-batch new widget/activity publication plus immediate end versus notice publication plus end; only non-notice terminal history becomes pending. Save a live publication, then exact expiry/end/prune; flush and fresh-runtime restore must not expose the old live publication. Shared real image pin changes are captured through existing B2 raster tests; no extra decoder implementation.
4. Gate real backend work after capture, cause a permitted canonical expiry/prune while the save is awaiting, then release the gate. First known commit acknowledges only its captured tag; a subsequent flush saves the newer canonical state. This catches clearing current blindly after an old save returns.
5. Force real quota/debt both before initial archive.start and during replacement save, or injected existing backend precommit failure: prior saved generation remains; the owner stays dirty, repeated ordinary pump calls do not repeat that unchanged attempt or grow retained state. Assert retryRequired rather than clean after failure. A new significant change returns pending; the existing explicit save after releasing the reservation can retry retryRequired directly and returns clean only on known success. Repeated lifecycle/resource notifications do not themselves create an unbounded automatic retry loop: the host chooses the explicit existing save opportunity. Separately gate runtime admission busy before the pending attempt and prove it remains eligible after the competing operation finishes.
6. Two owners: pending work remains bounded, one owner attempted per call, cursor reaches the other owner after failure and despite a new first-owner revision between every flush call. Foreign/stale coordinator capabilities and wrong runtime/governor still reject before lazy creation through C3; do not duplicate already-reviewed tests unless extraction changes that path.
7. Disable during a precommit save rejects/cancels and never restores eligibility; disable/close after a known commit preserves the scalar committed result. No delayed disable, postrevocation capture or invented durable-tombstone guarantee.
8. Admission-denial test includes the additional256-byte runtime/coordinator metadata before retention; repeated dirty changes/flush failures retain only fixed scalar metadata. Run new suite plus adjacent B2 save/restore and C3 facade suites after final formatting, then freeze exact diff/hashes/report and release root's scratch. No app/provider build inside the implementation worker.

## Boundaries and decisions

No new architecture or product choice was found for this first host-only slice. Exact automatic application wiring is a real following dependency, not implemented by a new internal facade. Timed coalescing, a crash-loss-window guarantee, durable provider acknowledgments, automatic deletion, SDK transport and C0d are excluded. Shutdown's bounded quiescing/flush/terminal-stop composition must receive its own source-level preflight against current B2 authority before implementation; C4 must not modify terminal stop to bypass that review.


Preflight ledger: independent reviewer confirmed fixed admission/lifetime, captured-tag acknowledgment, retry suppression, memory quotes and expiry predicate. One gap was corrected before code: use postcommit canonical kind for prepared ended IDs, including a new publication immediately ended in the same accepted batch. Required widget/activity/notice regressions are explicit. No substantive new product or architecture choice was identified. C3 interfaces and current-increment delivery still gate dispatch.


Dispatch ledger: C3 independent review and combined 679-test delivery are complete (381 frozen inputs, signed build and verified PID 97296). Root dispatched this corrected C4 scope to the sole implementation worker at 43% weekly use; the single SwiftPM scratch is assigned to that worker. Final implementation review and delivery remain pending.


Following slice: [bounded shutdown checkpoint plan](2026-09-13-addon-archive-shutdown.md), independently preflighted with concrete active-operation, local/runtime revocation, deadline-handoff and one-pass ownership rules. It remains undispatched until C4 review and complete delivery; no hard physical SwiftData completion deadline is claimed.


C4 delivered: independent implementation review approved all five frozen hashes; final 131 focused/adjacent tests pass. Full suite passes 694 tests in 70 suites, with 382 identical inputs, signed build/link and verified normal restart PID 99945. Weekly usage 45%. [Verification](../verification/2026-09-13-addon-archive-event-flushing.md). C5 is dispatched only after this successful delivery.
