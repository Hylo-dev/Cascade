# Define the service control and update messages

ID: 33
Parent: cascade-product
Type: task
Labels: wayfinder:task
Mode: AFK
Status: resolved
Assignee: —
Blocked by: 30

## Question

Implement closed, bounded message contracts for acquisition, subscription, source start and updates, distinguishing acceptance of the intent from availability of the service and without activating incomplete features in the runtime.

## Context

[Execution plan](../../../docs/superpowers/plans/2026-09-18-addon-service-subscription-frames.md). Pure syntax that can be built in an isolated Contracts harness while the delivery of the invocation path is completed; integration and the complete client come later. The 35% waiver and the Codex-only continuation remain active.

## Progress

Taken on; six new files, without changing the existing contracts or the negotiated protocol. Import into the project after the verified delivery of the invocation path.

Isolated implementation frozen and independent review PASS with no findings: 14 targeted tests / 91 Contracts tests in 10 suites. [Evidence and limits](../../../docs/superpowers/verification/2026-09-18-addon-service-subscription-frames.md). Six files still outside the real package; ticket not resolved until integration and delivery.

## Resolution comment: 18 September 2026

Six contracts/tests imported after the delivery of the invocations; independent review PASS. Full suite 1,048 tests / 94 suites, signed build on 439 inputs and restart PID 18542 → 20946 verified for 5 s. [Evidence and limits](../../../docs/superpowers/verification/2026-09-18-addon-service-subscription-frames.md). The 1.4 profile remains non-activated syntax: host, complete client and event delivery are the next increment.
