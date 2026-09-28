# Connect CPU overruns to runtime health

ID: 51
Parent: cascade-product
Type: task
Labels: wayfinder:task
Mode: AFK
Status: resolved
Assignee: none
Blocked by: 50

## Question

Compose in the runtime the measurement coordinator and the existing health store, with explicit host binding, sessions tied to the process incarnation and consumption of internally requested batches only. Record one moderate violation per owner when the classifier proves it; reject stale results after waits and keep the history across restarts. [Brief](../../codex-addon/20260921-cpu-violations/task-51-brief.md), [verified design](../../codex-addon/20260921-cpu-violations/health-integration-design.md). Sol medium implements, the root and an independent reviewer verify. Internal integration and tests with a fake adapter, without native activation or releasing reserves based on the metrics.

## Answer

Completed on 21 September 2026 by Sol medium, with root and independent review PASS. The runtime owns the coordinator and the health store, registers bindings only for the current incarnation, rechecks identity/session after waits and records incidents only from its own samples. Stop and exit revoke the authority; the shared cleanup detaches the measurements without releasing physical reserves. Debt and history survive the provider restart. Fixed during review: the cleanup of bindings stopped by deadline; reuse without late cancellations verified.

Eight new integration tests; 100 targeted tests in total (98 in seven suites plus two in a transport suite) and 1,135 package tests in 101 suites PASS. The quarantine is recorded in the internal state: activation in the app, native binding, shared deadline and sanctions remain separate. The next [choice on reducing new work](52-addon-cpu-reduced-admission.md) is needed before enforcement. [Report](../../codex-addon/20260921-cpu-violations/task-51-report.md), [independent review](../../codex-addon/20260921-cpu-violations/task-51-independent-review.md), [verification and delivery](../../../docs/superpowers/verification/2026-09-21-addon-cpu-violations.md).
