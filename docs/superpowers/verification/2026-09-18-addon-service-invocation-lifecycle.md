# SDK service invocation lifecycle verification: 18 September 2026

**PASS within the scope of the internal component and the bridge to the real runtime.** Three new files implement `ServiceInvocationLifecycle`, the SDK tests and the canonical integration with runtime/broker. No new public client or protocol activated; the 483 pre-existing inputs captured stayed unchanged.

## Final evidence

- **978 tests in 89 suites passed** after the review fix: Runtime 634/51, Presentation 92/9, Kit 170/19, Contracts 65/8 and Tool 17/2. Serial tests in the GUI session required by AppKit.
- The new suites comprise 23 declarations and 52 expanded executions. The first handoff also included 22 broker tests and 5 existing composition cases; the final full verification covers all targets.
- Codex Sol high independent review: one P2 in the replay test, fixed with a compilable RED and GREEN, then **PASS** on re-review. The test now marks the possible handoff before the duplicate request to the runtime; the broker's rejection is not confused with the absence of exposure. The production component is unchanged since the first review.
- Apple Development build succeeded on a final snapshot of **422 inputs**, all compared with the checkout. Signature verified and `/Applications/Cascade.app` updated. Normal close and new process **PID 51036 → 65073**, expected executable and stable for five seconds.

[Original handoff](../../../.scratch/codex-addon/20260918-continuation/service-lifecycle-report.md), [fix and reconciliation](../../../.scratch/codex-addon/20260918-continuation/service-lifecycle-review-fix-report.md), [final freeze](../../../.scratch/codex-addon/20260918-continuation/service-lifecycle-review-fix-final-freeze.json), [original review](../../../.scratch/codex-addon/20260918-continuation/service-lifecycle-independent-review.md), [PASS re-review](../../../.scratch/codex-addon/20260918-continuation/service-lifecycle-independent-review-addendum.md), [final full suite](../../../.scratch/codex-addon/20260918-continuation/service-lifecycle-fixed-full.log), [final snapshot](../../../.scratch/codex-addon/20260918-continuation/service-lifecycle-fixed-build-manifest.json), [signed build](../../../.scratch/codex-addon/20260918-continuation/service-lifecycle-fixed-signed-build.log), [relaunch](../../../.scratch/codex-addon/20260918-continuation/service-lifecycle-restart-evidence.json). The earlier freezes, logs and builds stay preserved as history; on their own they do not qualify the fix.

## Verified behavior

The lifecycle, serialized by the caller, keeps a single ticket and bounded metadata, with no payload, task, queue or history. It validates the value and correlation of the completion before consuming it. Before the possible send, cancellation withdraws the ticket; after exposure, every service operation can stay outcomeUnknown, even if it is called read. An exact response consumed before cancellation keeps its own outcome; if it arrives after, it is discarded without rewriting the local uncertainty.

The fixture uses canonical resolution, acquisition, dispatch, completion ingress and history. It distinguishes a result known to the host from an uncertain local outcome, revocation, replay, new generations and deferred completions. A pending completion is not forwarded as success. The buffers stay within a pre-admitted protected scope, distinct from the host quotas; retained tasks are unblocked and awaited on the error paths too. Logical close does not mean physical drain, refund or rollback.

## Limits and follow-up

Service grant generation stays separate from the publication connection; no combined AddonContext or rewritten grant. The result relay is only trusted test infrastructure. The 64 KiB cases verify typed values, not the full serialized transport of those payloads; the real ingresses of the fixture use small messages. Native limits, peer signatures, Foundation/RSS allocations and physical exit are not qualified. `observeExit` is a simulated input and C0d keeps exit78.

Complete C3 still requires consumer/provider messages and their receipts, subscriptions, session composition, the native channel and tests with real providers. The dedicated codecs are the next tranche, currently developed in an isolated copy; this delivery does not activate them. The public examples already verified stay unchanged and are not presented as native evidence.
