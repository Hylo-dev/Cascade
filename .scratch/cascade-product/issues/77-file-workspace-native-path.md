# Qualify the native path of the files.workspace service

ID: 77
Parent: cascade-product
Type: task
Labels: wayfinder:task
Mode: AFK
Status: open
Assignee: none
Blocked by: 19, 22

## Question

Complete the still-open native part of task 1 of the [file shelf plan](../../../docs/superpowers/plans/2026-09-26-file-shelf.md). Connect a signed provider that uses `CascadeAddonSDK` to the runtime and to the `files.workspace` service through authenticated production bootstrap/transport; demonstrate authorization, revocation and physical exit on the same path. Record adapters, composition and evidence in the [runtime verification](../../../docs/superpowers/verification/2026-09-26-file-workspace-runtime.md). The message-based/in-process fixture is not enough. No production mounting and no change to the launcher gate before the required qualifications.

Superseded on 2 October 2026: by the [plugin engine spec](../../../docs/superpowers/specs/2026-09-29-plugin-engine-design.md) (§6, §7) the file shelf is a system surface of the kernel, and `CascadeAddonSDK` is deleted, so this native addon path no longer applies. Closing the ticket is left to the map's owner.
