# Capture and deliver files with per-item native drag

ID: 79
Parent: cascade-product
Type: task
Labels: wayfinder:task
Mode: AFK
Status: open
Assignee: none
Blocked by: 77, 78

## Question

Implement task 3 of the [file shelf plan](../../../docs/superpowers/plans/2026-09-26-file-shelf.md) with AppKit, the existing drag monitor/hold and per-file transfer through persistent receipts. Acceptance: non-file drags and a stale pasteboard do not activate the shelf; cancellation does not capture; a partial drop removes only the items whose delivery is proven; asynchronous promises, safe names and collisions without overwrite; real test with Finder, Mail/URL-only, cancellation and partial drop. Targeted tests, root review and commit. Requires the qualified native path and the store of [Persist file shelf entries and receipts](78-file-workspace-persistence.md); a global drag outcome does not prove each file.
