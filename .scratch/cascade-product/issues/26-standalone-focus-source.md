# Create the Focus example with the public SDK only

ID: 26
Parent: cascade-product
Type: task
Labels: wayfinder:task
Mode: AFK
Status: resolved
Assignee: none
Blocked by: 24

## Question

Create an independent Focus source library with a declarative countdown, correlated actions, revisions and persistent state, using exclusively the public SDK products. Verify provider re-creation without declaring the native container already qualified.

## Context

C7/C12 increment authorized by the continuation of 18 September. [Plan](../../../docs/superpowers/plans/2026-09-18-standalone-focus-source.md). No verified Focus builtin to migrate; example behavior declared. Parity and control of real processes remain open.

## Progress

Design examined; implementation and verifications in progress.

Independent review of the first handoff: [three P2 fixes requested](../../codex-addon/20260918-continuation/focus-independent-review.md), concerning receipt outcomes with storage unavailable or an uncertain snapshot, and closing the schema of persisted errors. The 31 tests previously passed do not cover these cases; implementer reactivated for regressions and fixes. Delivery not yet approved.

## Answer

Independent source library implemented and reviewed PASS after all findings were resolved. 37 tests passed and external build succeeded, dependencies only on the public SDK. Persistence, revisions and receipts verified also with unusable history and uncertain commits. [Final verification and limits](../../../docs/superpowers/verification/2026-09-18-standalone-focus-source.md). The qualification of the native container and C7/C12 parity remain open.
