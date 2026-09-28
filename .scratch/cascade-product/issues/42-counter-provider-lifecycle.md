# Verify and complete the counter lifecycle in the provider

ID: 42
Parent: cascade-product
Type: task
Labels: wayfinder:task
Mode: AFK
Status: resolved
Assignee: none
Blocked by: 41

## Question

Real model of the provider: ack, timeout, invalidation and late responses; tests in memory without launching ExtensionKit. Complete the coverage of the actual callback code delivered in the remote counter, beyond the reducer alone. Fix reproduced defects and build the separate prototype.

## Scope

C8 increment already approved, with Ponytail: reuse of the real classes, controlled callbacks, no duplicated model. No scene activation, addon process, new entitlement, change to the launcher/C0d or inferred native qualification. The root verifies the results before any follow-up; several tickets can be completed in the same continuation.

## Answer

Reproduced and fixed the completion lost during initial invalidation: the real model keeps and takes back a single callback, completed on ack, timeout or channel loss. Sol medium implemented; the root reviewed and made the controlled delivery of the acks in the check deterministic, without relying on Task.yield. Covered: invalid/late acks, a single event in flight, repeated initialization and the real 2 s timeout.

Three local checks (reducer, host and provider), compiled with warnings-as-errors, PASS. Release build with Apple Development signing of the three targets and deep/strict verification PASS. [Root review and evidence](../../codex-addon/20260920-counter-lifecycle/root-review.md), [reproducible commands](../../../Prototypes/AddonPlatform/RemoteUI/README.md).

In-memory execution of the actual classes, with controlled callbacks: no OS connection or activated scene. Authentic XPC, UI interaction, physical exit, macOS 14 and Intel remain unqualified. Launcher and C0d gate unchanged; no new Cascade build declared.
