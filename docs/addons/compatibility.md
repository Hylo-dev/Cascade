# Addon compatibility

## Package and verified environment

The SDK package and the generated project declare `swift-tools-version: 6.2` and macOS 14; the public targets `CascadeContracts`, `CascadePresentation` and `CascadeAddonSDK` use the Swift 6 language mode. These declarations are not a matrix of tested platforms. The documented verification runs of 18 September use Apple Swift 6.4 on macOS 27 arm64: they do not qualify execution on macOS 14 or Intel. See the [evidence for the delivered contracts](../superpowers/verification/2026-09-18-addon-service-subscription-frames.md) and the [CPU calibration](../superpowers/verification/2026-09-18-addon-process-cpu-calibration.md).

For a standalone provider, use the `CascadeAddonSDK` and `CascadeContracts` products; `CascadePresentation` is a public dependency of the SDK and offers the declarative components. `CascadeRuntime`, `CascadeKit` and the app sources belong to the host: their presence among the SwiftPM products does not make them dependencies of the public addon path. The [testing guide](testing.md) spells out this boundary. A successful source build does not prove ABI stability, compatibility between binaries compiled with different toolchains, or native bundled/external parity.

## Manifest, protocol and content

Validate the manifest against the [public schema](manifest.schema.json) and the [contract](protocol.md). Package version, service version, manifest version, protocol minor and content schema have distinct roles; do not infer one from another. `REQUIRES` expresses compatibility and dependencies, without authenticating the provider or granting permissions.

Host negotiation starts from protocol 1.0 and selects the intersection of the provider's offer, the manifest's requirement and the capabilities that are actually connected:

| Cumulative minor | Required host capability |
| --- | --- |
| 1.1 | Keyed storage dispatch |
| 1.2 | Storage plus an asset-capable adapter |
| 1.3 | Earlier capabilities plus the complete internal service invocation assembly, handler, compatible environment and reserved capacities |
| 1.4 | Earlier capabilities plus the complete control/source/event handler, subscription adapter, compatible environment and prepaid maximum capacities |

An offer or a syntax profile does not enable these capabilities. The default remains 1.0 and the legacy paths up to 1.3 are preserved; incomplete assemblies keep the earlier level. Complete 1.3/1.4 connections compose the publication session and the broker with one common canonical generation, without rewriting Grants. The public client `TransportServiceClient` implements invoke/subscribe/unsubscribe together through an injected channel; the host keeps authority and a refresh does not renew the interest's expiry. See [sessions](sessions.md), [services](services.md), the [historical evidence for the 1.4 syntax](../superpowers/verification/2026-09-18-addon-service-subscription-frames.md) and the [reference for the complete host and SDK delivery](../superpowers/verification/2026-09-18-addon-service-subscriptions-host-sdk.md), with their verification limits. This composition does not qualify a native adapter/bootstrap, C0d, macOS 14 or Intel.

Content schemas 1 and 2 are negotiated separately. Schema 2 requires support even without lights; the lights field cannot be dropped to reinterpret the document as schema 1. The check covers every representation and the future timeline entries. [Content](content.md) describes the components, limits and renderer behavior.

## What a source example proves

Generation, validation and provider tests verify contracts and use of the public APIs. They do not prove installation, signed identity, authenticated transport, actual termination or native admission. The local SDK path is explicit and needs a new verification when the baseline changes; follow the [quickstart](quickstart.md), [testing](testing.md) and [distribution](distribution.md) guides.
