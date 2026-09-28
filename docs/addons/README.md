# Developing addons for Cascade

The contracts, the declarative components and the `AddonProvider` interface are available in the `CascadeKit` package. The runtime that launches external packages is not enabled yet: the [launcher qualification](../superpowers/verification/2026-09-10-addon-launcher-decision.md) still has to be completed for the identity and termination of managed processes. The [risk of delegated work](../superpowers/specs/2026-09-10-addon-control-policy.md) was explicitly accepted. Team widgets will also have to use this path once it is qualified.

## Validating a manifest

From the project checkout, with a toolchain compatible with Swift tools 6.2:

```sh
swift run --package-path CascadeKit cascade-addon validate /path/Manifest.json
```

The command uses the same validator as `CascadeContracts`, reads at most 64 KiB plus one check byte, and rejects directories, pipes and other non-regular files. It does not execute code or commands contained in the manifest.

Exit status `0` confirms that the document is valid under the current contracts; `1` means an unreadable or invalid file, `2` wrong arguments. Manifest validation does not verify the signature, user authorizations, the presence of the required services, or admission of the package into the runtime.

The `cascade-addon init` command generates a source project with a provider, a manifest and tests built on the public SDK products: follow the [getting started guide](quickstart.md). The distributable format and the native bootstrap still require launcher qualification.

## Available contracts

- [Creating an addon source project](quickstart.md)
- [Verifying an addon provider](testing.md)
- [Package and protocol compatibility](compatibility.md)
- [Performance and resource accounting](performance.md)
- [Source development and distribution](distribution.md)
- [Standalone source examples](examples.md)
- [Protocol and messages](protocol.md)
- [Session negotiation and admission](sessions.md)
- [REQUIRES dependencies](requires.md)
- [Declarative content](content.md)
- [Glass lighting](../architecture/glass-lighting.md)
- [Lifecycle, queues and actions](lifecycle.md)
- [Command authorization and coordination](actions.md)
- [Shared services and broker permissions](services.md)
- [State checkpoints and migrations](storage.md)
- [Images, message transfers and SDK clients](assets.md)
- [Manifest schema](manifest.schema.json)
- [Completion plan](../superpowers/plans/2026-09-10-addon-runtime-completion.md)

## Image client

`MessageAddonAssetClient` implements import, sharing and release through
an injected `AddonAssetMessageChannel`. The internal connection to the runtime is
verified with a test bridge that uses the real codec, ImageIO and accounting.
Negotiating 1.2 requires the host storage and asset capabilities; asset messages use schema 1.
The channel must be bound to an authenticated connection, consume the receipts and
complete physical cleanup: the test bridge is neither a distributable OS transport nor a production bootstrap.

## Storage client

`MessageAddonStorageClient` implements read, write and removal over an injected message channel. Correlation, cancellation and uncertain outcomes are also verified against the real backend; the production channel must provide authentication and physical cleanup. External memory must be admitted before the messages are built and encoded. See [contract and limits](storage.md#concrete-sdk-message-client).
