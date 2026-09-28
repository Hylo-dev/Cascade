# Classify new CPU consumption beyond credit

ID: 50
Parent: cascade-product
Type: task
Labels: wayfinder:task
Mode: AFK
Status: resolved
Assignee: none
Blocked by: 49

## Question

Apply the approved counting to the intervals produced by the coordinator: one classification per addon and round, distinguishing a new overrun, no new overrun and an unavailable measurement. Keep the guarantees on incomplete data and on residual debt. [Brief](../../codex-addon/20260921-cpu-violations/task-50-brief.md). Terra medium implements; the root and an independent reviewer verify before the wiring to health.

## Answer

Internal classification delivered by Terra medium, reviewed by the root and Sol medium: PASS. Predicate on the new positive CPU interval that leaves a negative balance, aggregated once per owner. Idle debt excluded; positive evidence kept even with partial measurements; absence of evidence/persistent error remains unavailable. No duplicated counter.

76 targeted tests in five suites PASS, including five new tests, with behavioral red and green. The root asked for a single owner observation and a real test of refund/credit exhaustion. [Report](../../codex-addon/20260921-cpu-violations/task-50-report.md), [independent review](../../codex-addon/20260921-cpu-violations/task-50-independent-review.md). Overall delivery after the wiring to health.
