# Run the SDK check before the development build

ID: 37
Parent: cascade-product
Type: task
Labels: wayfinder:task
Mode: AFK
Status: resolved
Assignee: none
Blocked by: 35

## Question

Make the check of the public SDK boundaries mandatory in the official development build script: a violation must stop the path before compilation, signing or updating the Applications link.

## Context

Bounded increment required by the [tools and parity plan](../../../docs/superpowers/plans/2026-09-09-addon-runtime-04-release.md#task-042-public-tools-and-mandatory-parity-for-our-widgets), after [Verify the public boundaries of the SDK and the examples](35-sdk-boundary-check.md). When the ticket was opened the check existed and was reviewed, but `scripts/build-development.sh` did not run it yet; the integration is now delivered in the Answer. The [technical preparation](../../codex-addon/20260918-continuation/boundary-build-gate-next-step.md) describes the minimal change, the limits and the evidence.

The command must inherit the selected toolchain and use the explicit root regardless of the invocation directory. Keep the Apple Development identity, the Xcode parameters, signature verification and the Applications update. No change to the Swift targets, the runtime or the native gate.

The verification includes negative fixtures with the real SwiftPM parser/graph and a command trace to demonstrate that Xcode is not entered, plus a positive signed build and a verified restart on the exact copy. The build copy must include the checked examples. Document the guarantee on the official script without attributing it to direct Xcode invocations; the migration of all legacy registrations and native parity remain open.

## Progress: history before the delivery

Taken on after the delivery of the verifier. Development and fixtures in an isolated temporary copy; no change to the frozen source of the subscriptions until its delivery is concluded. The complete positive script and the restart remain the responsibility of the main task.

Corrected isolated implementation and independent review PASS: four real fixtures verify rejection and ordering, without building an app. [Current verification](../../../docs/superpowers/verification/2026-09-18-addon-required-sdk-build-check.md). Import and the positive signed build remain pending; the app sources remain frozen for the review of the subscriptions.

## Answer

Mandatory public check integrated before Xcode in the official script, with no bypass and with explicit root/toolchain. Four real fixtures and independent review PASS; the positive build with all three checked packages, signing and restart at PID 85871 is delivered together with the subscriptions. [Verification and limits](../../../docs/superpowers/verification/2026-09-18-addon-required-sdk-build-check.md). No guarantee added to direct Xcode invocations or to native parity.
