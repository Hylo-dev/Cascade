# Connect the CPU credit to the shared observations

ID: 48
Parent: cascade-product
Type: task
Labels: wayfinder:task
Mode: AFK
Status: resolved
Assignee: none
Blocked by: 47

## Question

Explicitly associate the observed bindings with the event-driven addon and keep the account in the existing coordinator, shared across processes and provider restarts. Charge every internally produced interval only once; distinguish incomplete observations from accounting failures. [Brief](../../codex-addon/20260920-cpu-credit/task-48-brief.md), [design review](../../codex-addon/20260920-cpu-credit/ownership-design-review.md). Sol medium implements; the root reviews. No additional timer, sanction or native path.

## Answer

Internal wiring implemented by Sol medium, reviewed by the root and by a second Sol medium: PASS. Bounded accounts per verified identity, shared across processes, retained after unregister/exit/provider restart/wake. The intervals just reduced are charged in the same actor; the final result per owner distinguishes complete, incomplete and persistent error, with no balance in the last two cases.

71 targeted tests in four suites PASS, including 12 new wiring tests; full root replay: 1,122 tests in 99 suites PASS. [Worker report](../../codex-addon/20260920-cpu-credit/task-48-report.md), [independent review](../../codex-addon/20260920-cpu-credit/task-48-independent-review.md), [delivery and limits](../../../docs/superpowers/verification/2026-09-20-addon-cpu-credit.md). No wiring to sanctions or the launcher.
