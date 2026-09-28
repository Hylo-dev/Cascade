# File shelf contracts and authorized boundary

ID: 76
Parent: cascade-product
Type: task
Labels: wayfinder:task
Mode: AFK
Status: resolved
Assignee: none
Blocked by: none

## Question

The shelf model is set in [Define file collection and lifetime on the shelf](10-file-shelf.md).

Record the internal work already delivered for task 1 of the [file shelf plan](../../../docs/superpowers/plans/2026-09-26-file-shelf.md): bounded public contracts, `FileWorkspaceClient` on the shared services client and host authority over canonical ServiceWork. The closure covers only this boundary and the modeled tests; the native qualification stays in the next ticket.

## Answer

Commits `eb18b8e` and `f402d8c` delivered the contracts, the SDK client and the internal service boundary. The [runtime path verification](../../../docs/superpowers/verification/2026-09-26-file-workspace-runtime.md) records 21 FileWorkspace tests passed (7 contracts, 4 client, 10 authority), 22 ServiceBroker tests passed and a root review with fixes for stable domain errors and sanitized host text. The development build succeeded and Cascade was restarted from the updated build. The full package had a pre-existing intermittent failure in NotchControllerTests, which passed on the targeted rerun: it is not claimed as fully green. These tests do not qualify the bootstrap, the native transport, a signed provider on the shared path or the physical exit; the launcher stays blocked.
