# Probe an external SwiftUI UI inside the notch

ID: 19
Parent: cascade-product
Type: prototype
Labels: wayfinder:prototype
Mode: HITL
Status: open
Assignee: none
Blocked by: 01

## Question

Which installation experience and which isolation can be achieved by hosting an ExtensionKit SwiftUI scene in the notch panel, on the candidate macOS versions? Build a minimal test, separate from the product, with distinct source app and host: discovery and enablement, resize, transparency, focus, clicks, drag and accessibility. Also observe crashes or hangs of the remote UI without waiting for synchronous replies in the host. Verify signatures from different developers only if the necessary identities are available; explicitly record what was not tested. The prototype and the measurements let the user weigh the trade-off against loading bundles from a folder, without automatically turning the alternative into approved architecture.

## Progress of 9 September 2026

The direction is now approved: ordinary content in the host and remote scenes for advanced SwiftUI. [P0](../../../docs/superpowers/plans/2026-09-09-addon-runtime-00-platform.md) turns this ticket into operational tests of packaging, authenticated peer, shutdown even after a host crash, metrics and the scene in the panel. The prototype stays separate from production.

The ticket remains open because the tests have not been run. A local build does not demonstrate different macOS versions, actual isolation or signatures from distinct publishers. Any obstacles must come before the API freeze and do not authorize a fallback to addon code inside the host.

## Realignment of 14 September 2026

The platform tests are no longer all unrun: the [launcher report](../../../docs/superpowers/verification/2026-09-10-addon-launcher-decision.md) records observed limits of the alternatives; the current plan distinguishes the RemoteUI prototype, which has only been compiled, from the qualification of a real scene in the notch. The interaction, accessibility, different-publisher signature and macOS matrix tests required by this ticket are not concluded.

The [C0d diagnostics](../../../docs/superpowers/verification/2026-09-12-addon-managed-death.md) are verified offline, with the native test suspended. The design needed for the process exit requirement is now in the separate [ticket on managed processes](22-managed-process-exit-proof.md), to avoid confusing it with the remote UI experience.

This ticket remains open for the UI prototype and the evaluation with the user. Being available in the frontier means the topic can be taken up: it does not authorize removing the C0d gate or getting around it during the test.

## Source increment: 20 September 2026

The [prototype's counter](41-remote-scene-counter.md) now publishes correlated events on the authenticated channel and receives acknowledgments from the host. Reducer check and signed build of the three targets PASS, with root review/fixes. No native activation performed: this ticket remains open for the actual test of the scene, interactions, accessibility and the required matrix. The launcher block is confirmed by the user.

The subsequent checks of the actual callbacks of the [provider](42-counter-provider-lifecycle.md) and the [host](43-counter-host-lifecycle.md) are completed with reproduced fixes. They are not proofs of XPC or of an activated scene: this ticket remains open.
