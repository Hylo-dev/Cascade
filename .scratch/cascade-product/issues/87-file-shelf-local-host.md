# Prepare the local host and the shelf's verified copies

ID: 87
Parent: cascade-product
Type: task
Labels: wayfinder:task
Mode: AFK
Status: resolved
Assignee: codex/file-shelf
Blocked by: 78

## Question

Run phase A of the [approved local plan](../../../docs/superpowers/plans/2026-09-26-local-file-shelf.md): a single host/store/governor, a snapshot of 12 by default and a wire maximum of 32, add/remove/relink with stable IDs, opaque per-item preparation without early pinning, a verified FD copy with exclusive creation, no overwrite and `fsync`. Persistence and receipt precede the removal of only the delivered entry; originals, errors and cancellations preserved. Targeted tests, root review and selective commit. The exception is only for the local page: grants, quotas and the addon gate do not change.

## Answer

Implemented in `a0508ef` and accepted after the root's review and fixes: facade with shared store/governor, bounded snapshots, preserved IDs, per-entry/generation capability, controlled copy without overwrite and a receipt only after the copy completes. The review verified cleanup on cancellation, concurrency, metadata, shared lifetime and the preview gate. Independent root verification: 73 tests passed (53 runtime, 9 presentation, 11 contracts), log `.superpowers/sdd/2026-09-26-file-shelf/root-task87-tests.log`. It is not yet an app delivery: page, drag and native QA follow in the next local tickets; the addon launcher and the native gate stay unchanged.
