# Manage the SDK lifecycle of service invocations

ID: 29
Parent: cascade-product
Type: task
Labels: wayfinder:task
Mode: AFK
Status: resolved
Assignee: —
Blocked by: 28

## Question

Implement the internal cycle of correlation, cancellation and uncertain outcomes of SDK invocations and verify it through the real runtime and broker, keeping the session authorities separate. No new public client, message or subscription semantics.

## Context

Authorized continuation of the C3 plan. [Plan and limits](../../../docs/superpowers/plans/2026-09-18-addon-service-invocation-lifecycle.md). [Design and contracts still to be defined](../../codex-addon/20260918-continuation/service-client-design.md).

## Progress

Design examined and tranche taken on with Codex; verification and delivery still to be done.

## Answer

Internal component and canonical bridge implemented, fix of the replay test re-evaluated PASS; 978 tests / 89 suites, signed build and restart verified. [Evidence and limits](../../../docs/superpowers/verification/2026-09-18-addon-service-invocation-lifecycle.md). Complete public client, subscriptions and native tests remain open.
