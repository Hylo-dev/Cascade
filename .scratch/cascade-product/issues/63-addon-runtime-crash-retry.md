# Connect crash retries to the shared deadline

ID: 63
Parent: cascade-product
Type: task
Labels: wayfinder:task
Mode: AFK
Status: resolved
Assignee: none
Blocked by: 61, 62

## Question

Compose the already approved crash policy into the internal runtime: exit cause provided by the host, a health session even before the metrics, current canonical demand, consumption only once, and waits of 1/5/30 seconds in the shared queue. Stop/disable/wake cancel retries; no replay of uncertain commands and no native start. Sol medium implements with a fake adapter, the root and the reviewer verify. Preliminary analysis in [audit](../../codex-addon/20260922-transitive-cpu/post61-crash-audit.md).

## Answer

Pure runtime implemented and reviewed PASS by the root and an independent Sol. Pre-metric session at the handoff, unexpected exit classified by the host, current canonical demand, 1/5/30 second tickets and quarantine at the fourth crash with demand. The crash decision uses the shared cleanup; the demand checks and the due consumption share the admission, with a check also after the reserves. Retries without demand removed, refusals before the handoff refunded, refused handoff consumed without replay. Stop/disable/wake also cancel suspended decisions. Delegated CPU during a retry uses only the exact ticket.

[Worker report](../../codex-addon/20260922-transitive-cpu/task-63-report.md), [independent review](../../codex-addon/20260922-transitive-cpu/task-63-independent-review.md): 230 targeted tests/20 suites PASS. Root full suite **1,209 tests/113 suites PASS**, [log](../../codex-addon/20260922-transitive-cpu/package-tests.log). Seven final hashes verified. No native activation or qualification. The [tranche verification](../../../docs/superpowers/verification/2026-09-22-addon-transitive-cpu.md) retains the signed build and the updated launch verified from 497 identical inputs.
