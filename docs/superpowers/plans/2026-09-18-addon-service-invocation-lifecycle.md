# Service invocation lifecycle and canonical runtime bridge

The user’s sustained Codex-only continuation authorizes this bounded pure C3 increment; reserve35% waived. Root has reviewed the [design investigation](../../../.scratch/codex-addon/20260918-continuation/service-client-design.md), particularly the missing consumer wire/subscription/generation contract, and selects its internal lifecycle plus real-runtime test bridge. No additional product or native decision is inferred. Existing approved command semantics are binding.

## Global constraints

Exactly three new files: `CascadeKit/Sources/CascadeAddonSDK/Services/ServiceInvocationLifecycle.swift`, `CascadeKit/Tests/CascadePresentationTests/ServiceInvocationLifecycleTests.swift`, `CascadeKit/Tests/CascadeRuntimeTests/ServiceInvocationLifecycleIntegrationTests.swift`. No existing source, Package, Contracts, Runtime, example, transport/profile or C0d edits. Root owns plans, tracker, docs and delivery. Preserve dirty checkout; no Git mutation/worktrees/commits or native execution.

Internal non-Sendable caller-serialized ledger, at most one pending ticket; no Data, invocation, response, grant snapshot, task, callback, timer, queue or lock retained. Bound request contract/operation metadata through existing validation. Ticket issuer/nonce plus service generation/requestID/grantID give exact local identity, not peer authentication or indefinite logical deduplication. No sequence or public client conformance invented.

Follow the design’s begin/beginHandoff/observeHandoff/consume/cancel/close contracts. Call both existing InvocationCompletion.validate() and service validateCorrelation expectation before retirement; the latter compares exact requestID/contract/operation but does not replace value validation. Invalid completion leaves pending occupied; response while attempting may precede acceptance. Cancellation before possible exposure retires with cancelled; every possibly exposed service operation yields outcomeUnknown, even one named read. Later exact completion is discarded after cancellation, without rewriting the earlier local outcome. Proven request-side rejection alone is notSent. Close is permanent logical revocation, no physical drain/refund/rollback claim. Owner of a future concrete client must still serialize whole-operation finalization and physical drain.

Integration uses actual installed catalog/resolution/runtime/broker/governor and canonical provider completion-only ingress. Construct ledger with actual service grant generation; publication connection generation remains separate. A trusted test relay can use canonical serviceOutcome to offer known completed response; never present pendingServiceCompletion as success or a new wire message. No AddonContext generation rewriting. Host identities and observeExit are explicit modeled test inputs, not signature or physical-exit proof.

Preadmit test/SDK payload and returned-response lifetime before Data construction, separately from runtime/broker scopes. Keep all buffers within paid scope and joined tasks; return only scalar observations. No quota released by ledger transitions. Adapter mutable state must be synchronized or exclusively serial; use deterministic gates, no sleep/polling. Keep bridge fixture narrow and bounded.

## Execution and finite acceptance

Capture absent new paths and all existing source preimages/hashes. Meaningful compiling RED, then GREEN for the focused lifecycle and actual-runtime integration matrix in the design. Include exact errors and causal gates: admission/identity/correlation, all handoff/cancel/close orders, host-known versus locally unknown outcome, predispatch retirement, revoked late result, fresh service generation/replay, deferred completion and actual accounting lifetime. Reuse adjacent broker/composition coverage instead of duplicating broad suites. Any impossible case or required API modification must be reported before changing scope.

Worker freezes exact diff, hashes, test commands/output and scope reconciliation in dedicated service-lifecycle artifacts. Root performs independent review, full package checks once accepted, exact app snapshot signed build/link and normal restart verified. Complete only this internal source scope; C3/public service transport/subscriptions/native qualification remain open. Optional test gaps must be explicit, never relabeled as exhaustive proof.

## Delivery

Implemented and independently reviewed after one corrected replay-test finding. [978 tests / 89 suites, signed build and verified normal restart](../verification/2026-09-18-addon-service-invocation-lifecycle.md). No full service client or native qualification claimed.
