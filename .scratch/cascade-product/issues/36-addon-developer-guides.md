# Document addon compatibility, performance and distribution

ID: 36
Parent: cascade-product
Type: task
Labels: wayfinder:task
Mode: AFK
Status: resolved
Assignee: codex-01a0b0f2
Blocked by: 24, 25, 26, 27, 28, 31, 32, 33

## Question

Complete the three developer guides still missing that C12/04.2 foresees, describing the APIs, limits and evidence actually delivered and keeping the open native requirements explicit.

## Context

The [addon plan](../../../docs/superpowers/plans/2026-09-10-addon-runtime-completion.md) allows documentation and validation before the complete qualification. Package compatibility, internal negotiation, observed measurements and distributable packaging are separate areas; the guides cannot turn the proposals into implemented features.

## Progress

Taken on for Codex execution on three new documents only. Immutable baseline: delivery of the subscription contracts of 18 September; live sources/caches of the services worker excluded. Review by the main task before integration into the index. No build, addon process, signing or distribution by the documentation worker.

## Answer

Delivered the [compatibility](../../../docs/addons/compatibility.md), [performance](../../../docs/addons/performance.md) and [distribution](../../../docs/addons/distribution.md) guides, linked from the addon index. Independent review by the main task PASS: 32 valid local links and six sources compared with the hashes of the immutable delivery. Clarified the distinction between ordinary admission and observed disk debt. [Review and evidence](../../codex-addon/20260918-continuation/addon-developer-guides-independent-review.md).

Documentation only: no new build or native qualification, no invented installation format or command. Compatibility refers to the delivered baseline; it will be updated at the actual delivery of the complete client in progress. The global C11/C12 remain open.

Superseded on 2 October 2026: the guides this ticket delivered were deleted with `docs/addons`, and the [plugin pages](../../../docs/plugins/README.md) replace them. Kept as a dated record.
