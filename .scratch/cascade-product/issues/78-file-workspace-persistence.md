# Persist file shelf entries and receipts

ID: 78
Parent: cascade-product
Type: task
Labels: wayfinder:task
Mode: AFK
Status: resolved
Assignee: codex/file-shelf
Blocked by: 76

## Question

The shelf model is set in [Define file collection and lifetime on the shelf](10-file-shelf.md).

Implement task 2 of the [file shelf plan](../../../docs/superpowers/plans/2026-09-26-file-shelf.md): single-writer persistent store, references to the originals without copying, managed results, bookmarks/identity, quotas and delivery receipts. Acceptance: reopening preserves order and IDs; duplicates and same-name files handled; missing originals stay visible; corruption/a future version and failed saves do not destroy the state; a crash between copy, commit and cleanup does not lose the result; removing the only managed copy requires confirmation. Tests with real directories, root review and selective commit. Can be developed offline on the internal boundary of [File shelf contracts and authorized boundary](76-file-workspace-contracts.md); the native qualification is not a prerequisite of this task.

## Answer

Implemented in commit `bbe1144`: persistent host store, bookmarks and descriptors with verified identity, a single writer with explicit close/reopen, shared disk/state/memory quotas, a synchronized atomic manifest and per-item receipts. The root review fixed uncertain commits, pinning of deliveries, concurrent reopening and quota rollback. Root verification: filter `FileWorkspace|ResourceGovernorTests`, 50 tests passed, diff with no whitespace errors.

Delivery accepts promised inputs that are already completed and authorized by the host; native reception and activation in the app remain in the following tickets. The device/inode/generation identity can make a file unavailable after the volume is remounted; filesystems without a usable generation have weaker guarantees against inode reuse. No automatic cleanup of unknown data. Details in the [verification checkpoint](../../../docs/superpowers/verification/2026-09-26-file-workspace-runtime.md).
