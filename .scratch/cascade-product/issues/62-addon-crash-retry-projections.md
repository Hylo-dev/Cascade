# Prepare the demand and tickets for crash retries

ID: 62
Parent: cascade-product
Type: task
Labels: wayfinder:task
Mode: AFK
Status: resolved
Assignee: codex-root
Blocked by: 60

## Question

Expose bounded internal projections of the retries already emitted by AddonHealthStore and of the broker's unexpired canonical demand. Add cancellation of the retries only, preserving sessions and history. These support the already approved 1/5/30 seconds policy, without timers, relaunches or a new policy. Terra medium implements; the root and a reviewer verify.

## Answer

Internal projections implemented by Terra medium, root and independent Sol reviews PASS. Four targeted tests passed in the shared build: ordered and bounded tickets, cancellation of the retries only without losing sessions/history, unexpired canonical demand for a verified provider. No relaunch or timer added. [Report](../../codex-addon/20260922-transitive-cpu/task-62-report.md). The mechanical outcome of the shared round does not approve the separate runtime task 61, still under review on the v1.4 protocol.
