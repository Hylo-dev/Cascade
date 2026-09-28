# Add the shared component and the shelf's animated list

ID: 80
Parent: cascade-product
Type: task
Labels: wayfinder:task
Mode: AFK
Status: resolved
Assignee: codex/file-shelf
Blocked by: 76

## Question

Implement task 4 of the [file shelf plan](../../../docs/superpowers/plans/2026-09-26-file-shelf.md): negotiated content schema 3, a `fileWorkspace` node available to built-in/external addons and a shared SwiftUI renderer for deck, list and conversion. Acceptance: schemas 1/2 preserved and the new node refused, byte/node/asset limits unchanged, validated actions, at most four cards and +N, centered arrow, pagination, stable identity/animations, VoiceOver and Reduce Motion. Contract/layout tests and root review; local preview with 1/4/5/40 items. Can be developed offline without native mounting; do not advertise schema 3 until the renderer/adapters are installed.

## Answer

Implemented in commit `b8b3756` with GPT-5.6 Sol and root review: node and content schema 3 with explicit opt-in, semantic actions with immutable descriptors (at most 64), thumbnails declared and remapped in the archives, shared renderer for deck/list/conversion. The review fixes include long rows within the borders, readable opaque cards, a visible Convert command, groups aligned to the arrow, results distinct from the previews and Start blocked during active jobs.

Independent root verification: 86 targeted tests passed across FileWorkspace, ProtocolAdmission, GlassLight, ContentValidation and ActionAuthorizer; NSHostingView/NSWindow preview with 1/4/5/40 files, long names, reduced motion, compact conversion and an active job. Local screenshots under `/private/tmp/cascade-file-shelf-preview/`; [checkpoint and limits](../../../docs/superpowers/verification/2026-09-26-file-workspace-runtime.md).

Shared component completed, schema 3 not enabled in the production app. Manual VoiceOver navigation and animation timing in the real notch remain to be verified with the native integration; the previews attest the settled states.
