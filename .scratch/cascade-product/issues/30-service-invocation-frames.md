# Define and implement the dedicated service invocation messages

ID: 30
Parent: cascade-product
Type: task
Labels: wayfinder:task
Mode: AFK
Status: resolved
Assignee: —
Blocked by: 28

## Question

Implement bounded DTOs and codecs for the request, the correlated response and the invocation to the provider, keeping the existing limits and without enabling a new protocol in the runtime.

## Context

[Execution plan and limits](../../../docs/superpowers/plans/2026-09-18-addon-service-invocation-frames.md). C3 technical tranche authorized by the user's continuation; separate from the SDK cycle under review. The first implementation uses an isolated copy; integration into the package and delivery follow the closing of the previous tranche.

## Progress

Taken on with Codex. No handler, adapter, bootstrap or new negotiation activated.

## Answer

Five files imported from the isolated harness and reviewed PASS. 990 tests / 90 suites, signed build and restart verified. [Evidence and correlation boundaries](../../../docs/superpowers/verification/2026-09-18-addon-service-invocation-frames.md). Syntax-only profile, negotiation unchanged; complete handlers and clients remain separate.
