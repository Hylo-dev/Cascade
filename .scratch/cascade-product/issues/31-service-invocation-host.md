# Connect service invocations to the runtime and the SDK exchange

ID: 31
Parent: cascade-product
Type: task
Labels: wayfinder:task
Mode: AFK
Status: resolved
Assignee: —
Blocked by: 29, 30

## Question

Implement the complete internal message path for service invocations, with canonical authority, pre-admitted resources, exact receipts and the SDK result, keeping compatibility with the previous protocols.

## Context

[Execution plan](../../../docs/superpowers/plans/2026-09-18-addon-service-invocation-host.md), which incorporates the technical review on the composition of generations, raw completion, slot reservations and event-driven draining. C3 tranche authorized by the user's continuation; no change to the native guarantees or to the product permissions. Complete public client and subscriptions come later.

## Progress

Taken on with Codex Sol high; the previous model and quotas remain unchanged until the verifications and the independent review.

## Resolution comment: 18 September 2026

Complete internal path delivered with canonical 1.3 negotiation, shared generation, SDK executor, exact quotas and receipts. Two concurrency windows and the first attempt at the new refunds fixed with causal evidence; final review PASS. Full suite 1,034 tests / 93 suites, Release Runtime and signed build PASS; Applications link updated and restart PID 68582 → 18542 verified for 5 s. [Verification and limits](../../../docs/superpowers/verification/2026-09-18-addon-service-invocation-host.md). Complete public client, subscriptions and native transport come later.
