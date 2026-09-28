# Retain the CPU recipients of active chains

ID: 58
Parent: cascade-product
Type: task
Labels: wayfinder:task
Mode: AFK
Status: resolved
Assignee: codex-root
Blocked by: 57

## Question

Implement a bounded internal ledger of canonical interests and transitive recipients per physical binding. Keep the chains that existed between readings, avoiding phantom chains created by non-simultaneous edges; deduplicate interests and multiple paths. Linearize observations and interest changes without comparing different clocks. No timer, unbounded event queue or native activation. Sol medium implements; the root and an independent review verify before the wiring to broker/coordinator/runtime.

## Answer

Bounded ledger implemented by Sol medium, root and independent Sol reviews PASS. Instantaneous closures accumulated per binding, no phantom chains, synchronized observation and reset without CPU accounts. Nine new tests, 29 targeted tests/3 suites PASS; negative behavioral test on chains restored. [Evidence](../../codex-addon/20260922-transitive-cpu/task-58-report.md). Wiring to the coordinator and the broker in the dependent tasks.
