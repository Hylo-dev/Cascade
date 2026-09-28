# Connect the chain ledger to the CPU measurements

ID: 59
Parent: cascade-product
Type: task
Labels: wayfinder:task
Mode: AFK
Status: resolved
Assignee: codex-root
Blocked by: 58

## Question

Connect the same verified ledger to the coordinator, linearizing every reading/reduction with the exact recipients and returning their provenance. Preflight of the accounts before the readings, atomic registration and disarming, wake reset without zeroing the debt. Sol medium implements; the root and a reviewer verify.

## Answer

Wiring implemented by Sol medium; the root and the independent reviewer had no findings on the frozen code. 49 targeted tests/5 suites PASS. The coordinator pre-admits the bounded domain, reads/reduces under the lock of the single observation, keeps exact recipients even on missing data and maintains the previous arithmetic/debt. Binding lifecycle and wake synchronized with the ledger; manual input separate from the canonical mode. [Report](../../codex-addon/20260922-transitive-cpu/task-59-report.md).
