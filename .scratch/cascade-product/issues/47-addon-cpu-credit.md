# Implement the addon's shared CPU credit

ID: 47
Parent: cascade-product
Type: task
Labels: wayfinder:task
Mode: AFK
Status: resolved
Assignee: none
Blocked by: 46

## Question

Implement the internal value of the approved CPU credit, with monotonic refill, retained observed debt and bounded arithmetic. [Brief](../../codex-addon/20260920-cpu-credit/task-47-brief.md). Terra medium implements, the root reviews before the next wiring. No native qualification or activation.

## Answer

Internal value `AddonCPUBudget` implemented by Terra medium and rechecked by the root: 100 ms shared, monotonic 5 ms/s refill, retained debt and explicit overflow without mutation. 12 targeted tests PASS; no per-job reset. [Report](../../codex-addon/20260920-cpu-credit/task-47-report.md). Independent review and overall delivery remain recorded in the continuation report. The component does not apply sanctions or start processes.
