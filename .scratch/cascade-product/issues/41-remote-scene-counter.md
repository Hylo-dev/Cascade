# Connect the remote counter to the prototype's authenticated channel

ID: 41
Parent: cascade-product
Type: task
Labels: wayfinder:task
Mode: AFK
Status: resolved
Assignee: none
Blocked by: none

## Question

Carry out the first C8 source increment already foreseen: the scene's button must notify the counter to the host through the existing authenticated channel, with session correlation, verifiable ordering, bounded memory and no polling. Complete a local check of the logic and build the separate targets; do not activate ExtensionKit or declare a real click test.

## Scope

Three sources of the RemoteUI prototype, a single executable Swift check and documentation. No production SDK API, change to the launcher/C0d, new entitlement or dependency. Protocol and fixture limited to echo and observation of the counter; a single event in flight, a finite budget and rejection of inconsistent events. Sol medium implements; the root reviews, fixes if necessary and verifies before proceeding. The separate qualification of the real scene stays in the [remote UI ticket](19-extension-host-probe.md).

## Operating plan

1. Make an initial event and increment/reset observable, with a fresh session assigned by the host and a verified sequence.
2. Connect the UI and the XPC receiver, invalidating the state on channel loss and preventing unbounded queues.
3. Local Swift check (including rejections and terminality), build of the separate targets, root review; no activation of the fixture.
4. Record outcomes kept distinct from native qualification, keep the launcher blocked and resume the frontier.

## Answer

Implemented the source path counter UI → authenticated channel → host reducer → acknowledgement. Fresh session assigned by the host, checked sequences and transitions, one event in flight, 2 s deadline, at most 1000 actions and application payloads of 1024 bytes. The host emits counterChanged observations; timeout, channel loss and deactivation make the session terminal. No polling and no new dependency.

Sol medium implemented; the root reviewed and fixed logging, response size, late completions during deactivation and single-use admission. [Review and evidence](../../codex-addon/20260920-remote-counter/root-review.md). [Reproducible check](../../../Prototypes/AddonPlatform/RemoteUI/README.md): Swift compilation with warnings-as-errors and assert PASS; Release build of host/provider/container and deep/strict verification of the three signatures PASS. Xcode configuration and C0d gate unchanged.

The check runs the real reducer in memory. XPC transport, scene activation, real clicks, runtime behavior of the callbacks, accessibility, provider exit and the macOS/publisher matrix are not verified. No prototype product launched or registered. The remote UI ticket and the launcher remain open/blocked in their respective scopes.
