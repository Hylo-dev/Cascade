# Verify and complete the counter receiver lifecycle

ID: 43
Parent: cascade-product
Type: task
Labels: wayfinder:task
Mode: AFK
Status: resolved
Assignee: none
Blocked by: 41

## Question

Real receiver of the host: single-use configuration, rejections, invalidation and consistent observations; tests in memory without an OS connection. Complete the coverage of the actual callback code delivered in the remote counter, beyond the reducer alone. Fix reproduced defects and build the separate prototype.

## Scope

C8 increment already approved, with Ponytail: reuse of the real classes, controlled callbacks, no duplicated model. No scene activation, addon process, new entitlement, change to the launcher/C0d or inferred native qualification. The root verifies the results before any follow-up; several tickets can be completed in the same continuation.

## Answer

Reproduced and fixed repeated invalidations after a rejection: the callback is taken back under the lock and invoked outside the lock. The check uses the real receiver, without NSXPCConnection, and covers observations/acks, single-use configuration, invalid/early/late events and 32 concurrent closes with a single invalidation.

Three local checks (reducer, host and provider), compiled with warnings-as-errors, PASS. Release build with Apple Development signing of the three targets and deep/strict verification PASS. [Root review and evidence](../../codex-addon/20260920-counter-lifecycle/root-review.md), [reproducible commands](../../../Prototypes/AddonPlatform/RemoteUI/README.md).

In-memory execution of the actual classes, with controlled callbacks: no OS connection or activated scene. Authentic XPC, UI interaction, physical exit, macOS 14 and Intel remain unqualified. Launcher and C0d gate unchanged; no new Cascade build declared.
