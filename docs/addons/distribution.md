# Preparing an addon for distribution

## Delivered path: local source development

`cascade-addon init` generates a SwiftPM library with a provider, a manifest and tests. The project depends on the explicitly given local SDK path; it does not include an executable, an installer or a remote SDK repository. If the path changes, update the dependency in `Package.swift` and verify the project again. The actual generation and validation commands are in the [quickstart](quickstart.md); the [testing guide](testing.md) describes the standalone build.

`cascade-addon validate` checks the manifest's syntax and contracts. It does not authenticate the publisher, verify a signature, install an addon or grant authorizations. The identifier chosen by the developer and the declared entry point do not constitute a verified identity or a process bootstrap. The verified signature of the Cascade build in the delivery reports likewise concerns the host app, not a distributable addon.

The [StandaloneFocus](../superpowers/verification/2026-09-18-standalone-focus-source.md) and [ServiceConsumer](../superpowers/verification/2026-09-18-service-consumer-source.md) examples have standalone source build and test evidence. They remain source libraries: they are not installed addons, signed containers, or proof of native parity between team and external addons.

## Source app and dependencies

`sourceApp.required: false` does not introduce a global dependency on the source app. A root-level `REQUIRES` gates the whole addon; one attached to a feature gates only that feature. A function that requires the source app can be unavailable without blocking an autonomous function. This is resolver behavior; on its own it does not prove the native scenario with an app that was never installed.

In the resolution model, `installed` requires presence that the host catalog can verify; `running` also requires a running app. Resolution does not install software, does not open apps and does not ask for permissions. `bundledLibraries` is an inventory of included code, whereas an external service requires resolution and authorization. Service version and package version stay distinct. See [REQUIRES](requires.md), [protocol](protocol.md) and [services](services.md).

## Native release boundary

The [completion plan](../superpowers/plans/2026-09-10-addon-runtime-completion.md) keeps open the qualified launcher, packaging and native admission, an external catalog with installation/update, bundled/external parity, and qualification of remote scenes. The source guides do not define a new distribution format, a signing policy or an installation command.

Before an artifact can be considered distributable, the native verifications the plan calls for are needed: authoritative identity and digest, authenticated transport, permissions, lifecycle and resources, update and recovery. This path cannot be replaced by copying or moving a registered bundle, or by assigning it example credentials. The [compatibility](compatibility.md) and [performance](performance.md) pages document what the baseline can verify today; complete C11/C12 remain open.
