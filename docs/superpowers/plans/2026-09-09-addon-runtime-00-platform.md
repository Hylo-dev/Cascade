# Addon Platform Proof Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Prove packaging, isolation, authentication, stop and remote UI before incorporating a launcher into the product.

**Architecture:** Distinct test host and test addon container, with a headless entry point and a remote scene. The proof code produces evidence of actual processes and is not imported by production.

**Tech Stack:** Swift, Xcode, Foundation/XPC, ExtensionFoundation/ExtensionKit; public APIs with verified availability.

**Spec:** [specification](../specs/2026-09-09-addon-runtime-design.md), [main plan and constraints](2026-09-09-addon-runtime.md).

## Verified status

Real standalone prototype implemented; authenticated echo and rejection of corrupted JSON pass. Normal quit/crash of the host terminates the provider in the fixture. Explicit stop with the host open and control of subprocesses do not pass. **00.1/00.2 are partial, 00.3 has only a compiled, unqualified prototype; P0 is not concluded.** The direct child process added later proves stop and metrics, but a launch delegated to Launch Services escapes the supervisor and keeps the gate closed. [Evidence and matrix](../verification/2026-09-09-addon-runtime-P0.md).

## Global Constraints

- macOS 14 as the app's minimum. The deployment target is not raised implicitly.
- All future team widgets use the same SDK and controls as external addons.
- No private API, presumed privileged task port, root or invented signature of another publisher.
- No loading of addon code into the graphics process. Cascade must be open.
- A case that cannot be run is marked unverified; a compilation does not prove the behavior on another macOS.

## Task 00.1: Independent container and minimal protocol

**Files:** create Prototypes/AddonPlatform/AddonPlatform.xcodeproj/project.pbxproj, Host/ProbeHost.swift, Provider/ProbeProvider.swift, Shared/ProbeMessage.swift, Host/Info.plist, Provider/Info.plist, Provider/Provider.entitlements, README.md; create scripts/test-addon-platform.sh.

**Interfaces:** the test protocol uses only Foundation.Data, with a JSON request and a JSON response. Fields: requestID UUID, operation string, payload string; response requestID, providerPID Int32, value string. Allowed operations: echo, checkpoint, exit, spin. The endpoint is obtained from the extension path, not by guessing the name of an XPC service inside the source app.

```swift
@objc protocol ProbeChannel {
    func request(_ data: Data, reply: @escaping (Data) -> Void)
}
```

- [ ] Configure the host and a small independent container app with the extension. Check availability, legacy metadata and signing mode in the local headers/interfaces; write in the README the matrix for 14/15/26 and the current available system.
- [ ] Implement in the shell test an echo request with a UUID and known text, collection of the real PIDs and an external timeout of 2 s. The test must fail before the listener responds; afterwards it must assert hostPID != providerPID and the identity of the response. Do not use an in-process listener.
- [ ] Implement discovery, enablement through the path the system allows, and an async channel. Validate the peer through the system's signing identity, not a field declared by the provider. Also try an unauthorized client, with the rejection recorded.
- [ ] Prove the sandbox profile, not just PID separation: direct access not granted to another addon's files/credentials/services, network and subprocess creation. Record the accesses actually denied and the acceptable entitlements. A valid signature with entitlements incompatible with the profile must be rejected; if the platform does not allow a promised restriction, that profile does not pass P0.
- [ ] Run the case with only the addon's container app; the example's full source app must not exist nor provide files/frameworks. Use a fixture environment and folders, without uninstalling the user's apps.
- [ ] Record packaging, endpoint, identity, signature and repeatable steps; commit only the proof files after verification.

**Run:** `/bin/zsh scripts/test-addon-platform.sh --case standalone-echo`. Exit 0 only with distinct processes, a response within the timeout and proof of identity; save the JSON in Prototypes/AddonPlatform/Results/standalone-echo.json, ignoring Results in git and citing the results in the report.

## Task 00.2: Stop, fault injection and metrics

**Files:** create Prototypes/AddonPlatform/Host/ProbeSupervisor.swift, Provider/ProbeFaults.swift, Tests/ProcessLifecycleTests.swift; modify scripts/test-addon-platform.sh; create docs/superpowers/verification/2026-09-09-addon-runtime-P0.md.

**Interfaces:** ProbeFaults supports spin (non-cooperative loop), allocate (progressive buffers within the test guardrail), malformed (non-JSON response). ProbeSupervisor exposes `run(caseName: String) async throws -> ProcessEvidence`; ProcessEvidence contains hostPID, providerPID, exitObserved Bool, elapsedMilliseconds Double, cpuReadable Bool, footprintReadable Bool, reason String.

- [ ] Write a test that starts spin, first quits the host normally and then kills it in a second run. Before correct handling the test must detect the leftover process or a timeout; the external test supervisor always has a cleanup limited to fixture PIDs with verified identity.
- [ ] Implement the stop through the documented lifecycle. For ExtensionFoundation verify the last-connection condition; do not equate NSXPCConnection.invalidate with termination. For a direct child process do not assume that it dies with its parent. Verify the exit even if it does not respond to a cooperative stop.
- [ ] Read CPU and footprint with APIs allowed for the real identities and target OS. Prove a denied read, a PID no longer valid and reuse of the process identity without reporting a foreign PID. Allocation test with the harness safety ceiling: 64 MiB additional and an external deadline of 5 s, no unbounded stress of the machine.
- [ ] Compare IPC wait and restart by repeating 20 echo requests with pauses set by the harness. Measure total CPU/footprint and response p95 without deriving a definitive budget from a single run. Do not add freezing to the product.
- [ ] Document the launcher choice, the exact APIs used, the controllable processes, the signing differences and the untested OSes. Moving to P2 is denied if the stop after a host crash is not proven; meanwhile continue P1 on the pure models.

**Run:** `/bin/zsh scripts/test-addon-platform.sh --case lifecycle`; repeat with `--case metrics` and `--case unauthorized-peer`. Each outcome has PID, executable path, identity, timestamp and reason; a process still present is FAIL, not "connection closed".

## Task 00.3: SwiftUI scene in the real panel

**Files:** create Prototypes/AddonPlatform/RemoteUI/ProbeScene.swift, Host/ProbeSceneHost.swift, Tests/RemoteSceneTests.swift; modify the test project and scripts/test-addon-platform.sh; update the P0 report.

**Interfaces:** remote scene with a title, an increment button and a menu. The host receives activation/deactivation and hosts EXHostViewController through an AppKit adapter. UI commands use ProbeChannel; no SwiftUI.View transferred as an IPC object.

- [ ] Add a counter test: a click increments the value received through the channel, a press in the rest of the notch stays handled by the host. Wait for a callback, not an arbitrary sleep, as proof of correctness.
- [ ] Mount a scene in the nonactivating test panel. Verify resize, clipping, transparency, focus, menu, VoiceOver and closing; repeat 20 openings and record the number of processes and the footprint after release.
- [ ] Make the scene's process hang/crash. The host must close and reopen its own panel without waiting for replies and show a fallback. Verify that releasing the scene does not end a separate work lease in the lifecycle proof.
- [ ] Run signatures of distinct publishers only if available; explicitly note the untested cases. Do not present the local signature as cross-publisher verification.
- [ ] Report the outcome of the ordinary scene, of the faults and of the OS matrix. If the remote UI does not work on the minimum target, describe the limitation and the choice required before its production task; do not introduce a fallback to in-process code.

**Run:** `/bin/zsh scripts/test-addon-platform.sh --case remote-scene`. The automated part verifies messages/exit; the visual and VoiceOver verifications must be noted separately, with images and steps, without declaring them covered by the counter test.
