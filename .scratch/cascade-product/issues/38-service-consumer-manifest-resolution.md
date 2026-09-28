# Verify the real dependencies of the ServiceConsumer manifests

ID: 38
Parent: cascade-product
Type: task
Labels: wayfinder:task
Mode: AFK
Status: resolved
Assignee: none
Blocked by: 27

## Question

Connect the published manifests of ServiceConsumer and of the example provider to the REQUIRES matrix of the real ResolutionPlanner, without adding private dependencies to the examples or changing production code.

## Context

[C12](../../../docs/superpowers/plans/2026-09-10-addon-runtime-completion.md#c12-distributable-sdk-tools-and-independent-examples) requires proof of the dependencies between the two examples. The current public tests validate declarations and propagate simulated outcomes; the resolver is already tested on generic fixtures. The [remaining-work audit](../../codex-addon/20260918-continuation/addon-remaining-work-audit.md) identifies this missing link.

## Scope and finite proof

AFK verification in a temporary, archived harness, not a new feature or a change to the package's suite. Copy exactly the two manifests, the three resolver files and Contracts; record hashes and fixtures. The originals and the package remain unchanged, so the public suite does not acquire dependencies on the host or on external paths. The harness is self-sufficient and keeps reproducible data and commands.

Run the real resolver for compatible presence/provider-consumer order, absence, disabled provider, incompatible major, derived cycle and consent between synthetic publishers followed by removal of the consent with a previous binding. Verify the effective bindings and features, the specific reasons and the absence of effects from a revoked previous binding. The variants are derived explicitly from the starting manifests, not offered as new distributable manifests.

No signing, authentication, real grant, launcher, revocation during IPC or native parity is demonstrated. The proof closes with a recorded run, a check that the originals are unchanged and an independent review; the global C12 remains open. Do not invent a RED for production behavior that is already implemented.

## Answer

Source matrix completed: 7 functions/8 cases/1 suite PASS with the real decoder and resolver, 65 inputs archived and 63 originals verified identical. Independent review PASS, with no fixes requested. [Verification and limits](../../../docs/superpowers/verification/2026-09-18-service-consumer-manifest-resolution.md). No production/package/example code changed: only the archived harness and the documentation of the result. C12 and native qualification remain open.
