# Route the local shelf and recognize the incoming drag

ID: 88
Parent: cascade-product
Type: task
Labels: wayfinder:task
Mode: AFK
Status: resolved
Assignee: codex/file-shelf
Blocked by: 80, 87

## Question

Run phase B of the [approved local plan](../../../docs/superpowers/plans/2026-09-26-local-file-shelf.md): a dedicated page slot in the engine, default on opening when occupied and manual navigation preserved. `NSDraggingDestination` recognizes current files, pulses only once and shows the target; text, cancellation and a stale pasteboard do not capture. Verify display/owner change, closing and Reduce Motion. No fake activity, no Music fallback and no opening of the launcher. Targeted tests, root review and selective commit.

## Answer

Implemented in `ec14e70` and accepted after root review: a dedicated contextual slot, default selection of the occupied shelf without erasing the manual choice, recognition of the file drag and a finite pulse/preview with handling of cancellation and Reduce Motion. Independent root verification: 71/71 targeted tests passed (`root-task88-tests.log`). The combined filter passed 139/140 tests; the only failure is the already documented pre-existing intermittent drag test, so the combined suite is not claimed green. App composition, outgoing delivery and QA in the real notch follow in the local tickets; no qualification of the addon launcher.
