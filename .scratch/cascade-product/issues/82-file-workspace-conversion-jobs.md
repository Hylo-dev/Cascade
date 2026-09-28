# Run file conversions in recoverable jobs

ID: 82
Parent: cascade-product
Type: task
Labels: wayfinder:task
Mode: AFK
Status: open
Assignee: none
Blocked by: 77, 78, 81, 86

## Question

Implement task 6 of the [file shelf plan](../../../docs/superpowers/plans/2026-09-26-file-shelf.md): real conversion off the main actor with authorized inputs, closed formats, a confined/supervised FFmpeg process, native documents, progress and recoverable persistent jobs. Acceptance: start returns a job ID without waiting for the conversion; renamed/replaced or non-materialized inputs do not become new targets; no shell interpolation and no access to files/URLs referenced by the media outside the grant; cancel/revocation/restart/quota handled; atomic result and cleanup after persistence. Targeted tests and native process tests, root review, commit. Depends on the verified native path, store and helper; a process simulation does not satisfy the acceptance.

## Execution breakdown: 26 September 2026

[Prepare conversion formats and progress](86-file-workspace-conversion-planning.md) can advance without the native path because it processes only in-memory values. This ticket keeps the full acceptance and the native block; completing the subcomponent does not qualify production processes or conversions.
