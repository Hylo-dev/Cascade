# Verify the pre-tracing bootstrap abort offline

ID: 39
Parent: cascade-product
Type: task
Labels: wayfinder:task
Mode: AFK
Status: resolved
Assignee: none
Blocked by: none

## Question

Implement the finite model already proposed by the investigation on managed processes: bounded parsing of the trusted bootstrap's channel, terminal loss of authority and conservative evaluation of the observations. Always distinguish the model's prediction from the observed physical exit; no native operation or opening of the gate.

## Context

The [design investigation](../../codex-addon/20260918-continuation/managed-process-design.md#smallest-implementation-ready-next-increment-bootstrap-abort-entirely-offline-first) identifies this step as concrete preparation for the decision on processes. The [ticket on managed processes](22-managed-process-exit-proof.md) remains HITL and open; this increment does not resolve it. The audit of the remaining work was looking for further production components: here only the already specified offline diagnostics are prepared, without inventing a new product subsystem.

Codex continuation authorized in the map's Notes; latest stop at 00:00 Italian time on 19 September. Spec, RED/GREEN tests, independent review and documentation of the finite proofs are required. No tracing, exec, spawn, signal or OS observer in the new model; no change to the drivers, the entitlements, the historical records or the runtime/app.

## Progress: history

Taken on after the verified delivery of the services client and of the build with the mandatory SDK check. [Execution plan](../../../docs/superpowers/plans/2026-09-18-addon-bootstrap-abort-offline.md).

## Answer

Finite model and synthetic evaluator implemented in the two new Python files: 31 tests PASS, behavioral REDs archived, root replay and independent review PASS. Bounded framing and partial memory, absolute deadline, terminal states and rejection of inconsistent observations verified; all native success flags remain false. [Reproducible guide](../../../Prototypes/AddonPlatform/Tracing/BootstrapAbortModel.md) and [complete verification](../../../docs/superpowers/verification/2026-09-18-addon-bootstrap-abort-offline.md).

The 11 original inputs of the diagnostics/driver and the 484 delivered inputs of the app are unchanged. The normal app restart required by the project verified with PID 96743, without attributing it to the offline proof. The ticket on managed processes and the C0d gate remain open/closed respectively: no physical test, tracing, signal or launcher was run.
