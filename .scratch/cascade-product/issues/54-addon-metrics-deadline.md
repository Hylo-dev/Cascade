# Connect the addon measurements to the shared deadline

ID: 54
Parent: cascade-product
Type: task
Labels: wayfinder:task
Mode: AFK
Status: resolved
Assignee: none
Blocked by: 53

## Question

Compose the metrics coordinator's deadline with the runtime's four existing aggregates, serving it from the shared deadline cycle without autonomous timers. Disarm when there are no rows, preserve the maximum 1 Hz cadence and the explicit samples; offer an internal wake hook that breaks the continuity of the measurements without resetting credit or admissions. Verify the change of the deadlines' accounting owner and contention with samples in progress, avoiding repeated wakeups without progress. No wiring to the app or launcher. [Survey](../../codex-addon/20260921-cpu-admission/deadline-followon-audit.md).

[Execution brief](../../codex-addon/20260921-cpu-admission/task-54-brief.md). Terra medium implements; root and Sol review.

The delegated work is split without overlapping files: Terra medium implements the runtime and the deadline tests; Sol medium prepares only the test file for the wake interleavings, which are more complex. A single test scratch is explicitly handed over between workers. The root and a separate Sol medium carry out the final review.


## Answer

Completed on 21 September 2026 in the internal runtime. A fifth aggregate identifier composes the metrics cadence without a timer; deadlines and cleanup precede sampling. The owner change keeps the queue's constraints. A single pending wake token makes interrupted reads stale, keeps debt and admissions and holds back a second wakeup during the reset. Ten new tests; final targeted run 118 tests, full suite 1,153 tests/104 suites PASS. Terra medium implements production and ordinary deadlines, Sol medium the concurrent tests; root and independent Sol: PASS. The initial attempt with a wrong command is not counted among the verifications. [Final review](../../codex-addon/20260921-cpu-admission/task-54-independent-review.md), [delivery and evidence](../../../docs/superpowers/verification/2026-09-21-addon-cpu-admission.md). No activation of the launcher or of the macOS wiring.
