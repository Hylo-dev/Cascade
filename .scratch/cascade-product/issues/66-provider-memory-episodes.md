# Classify provider memory episodes

ID: 66
Parent: cascade-product
Type: task
Labels: wayfinder:task
Mode: AFK
Status: resolved
Assignee: none
Blocked by: 65

## Question

Implement a constant-state machine for a canonical process: <=64 MiB recovery, above 64 and up to 96 moderate only on entry, above 96 severe with precedence, a missing measurement keeps the state. No clock, owner, I/O, timer or UI policy. Terra medium implements, the root and the reviewer verify.

## Answer

Terra medium implementation verified by the root and an independent Sol: constant-state classifier per incarnation, 64/96 MiB boundaries and continuity correct. 3 targeted tests PASS; [review](../../codex-addon/20260923-provider-memory/task-66-independent-review.md).
