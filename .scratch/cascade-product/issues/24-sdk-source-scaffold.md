# Generate a buildable SDK addon project

ID: 24
Parent: cascade-product
Type: task
Labels: wayfinder:task
Mode: AFK
Status: resolved
Assignee: none
Blocked by: 23

## Question

Complete the `cascade-addon init` command with a buildable source project based exclusively on the public SDK products, a validated manifest, a developer-provided identity and protection of existing files. Verify the independent build without declaring the package already installable or the launcher qualified.

## Context

The 18 September request to continue the addon work up to the Codex limit extends the continuation to the remaining tranches of the approved plan. This C12 increment can proceed before C0/C1: [implementation plan](../../../docs/superpowers/plans/2026-09-18-addon-sdk-scaffold.md). [Codex progress](../../codex-addon/20260918-continuation/plan.md).

## Progress

18 September: taken on, implementer Codex Sol high. New destination, explicit identifier and SDK; atomic publication without overwriting; provider example and tests to be built externally. Review and delivery still to be done.

## Answer

Source generator implemented and reviewed PASS: manifest, provider and tests based on the public SDK products; explicit paths, new destination and publication without replacement. 17 targeted tests, 5 tests of the independent project and 896 tests / 84 full suites passed. Signed build and restart verified. [Delivery and limits](../../../docs/superpowers/verification/2026-09-18-addon-sdk-scaffold.md). The distributable format, the bootstrap and native parity remain open.

Superseded on 2 October 2026: `cascade-addon init` and the addon SDK it scaffolded for were deleted with the v1 runtime, and the manifest tool is now `cascade-plugin`, which only validates. Kept as a dated record.
