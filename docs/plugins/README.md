# Plugins

Cascade's widgets, notices and activities are plugins. A plugin is data in and data out: it receives events and answers with declarative documents, and Cascade, the kernel, validates them, keeps them and draws them. A plugin never hands Cascade a view, so it cannot block the notch, trap inside it or make it redraw for nothing.

First-party plugins run in **PluginHost**, an XPC service bundled in Cascade, each on a thread of its own. A plugin that crashes or hangs costs a PluginHost restart, and the notch keeps showing its last valid content meanwhile. The decisions and their reasons are in the [plugin engine spec](../superpowers/specs/2026-09-29-plugin-engine-design.md); these pages describe what the code does today.

## Pages

- [Manifest](manifest.md): manifest v2, features, requirements and how manifests are validated.
- [Content](content.md): the document, the SwiftUI-mirror builder, the three tiers, limits and identity.
- [Lifecycle](lifecycle.md): what wakes a plugin, sources, staleness, restarts and the failure table.
- [Actions](actions.md): controls, optimistic state and how the kernel authorizes an action.
- [Testing](testing.md): testing a plugin as a value, and the engine's own tests.
- [Performance](performance.md): budgets, kernel-drawn time and what idle costs.
- [Services, storage and assets](services.md): planned, not built yet.
- [Glass lighting](../architecture/glass-lighting.md): the document-level lights.
- [Activity and notice contracts](../architecture/live-activity-contracts.md): the presentation rules notices and activities follow.

## Where the code lives

| Module | Role |
| --- | --- |
| `CascadeContracts` | Pure values: manifest v2 (`PluginManifest`), nodes and documents (`PluginNode`, `PluginDocument`), publications, events, the node table and its diff. |
| `CascadePluginSDK` | What a plugin imports beside the contracts: `PluginProvider`, `PluginContext` and the builder. It knows nothing of the kernel. |
| `CascadePlugins` | The first-party plugins, their manifests as JSON and their String Catalogs. `FirstPartyPlugins` lists them. |
| `CascadePluginHost` | PluginHost's library: the runner that gives each plugin a thread, the XPC listener, and the catalog sources PluginHost implements. |
| `PluginHost/` | The XPC service target. In Debug it also carries the probes `CascadeTests/PluginHostIntegrationTests.swift` uses to make it hang, trap and exit. |
| `CascadePluginEngine` | The kernel without UI: `PluginKernel` (registry, broker, supervisor, scheduler), `PluginEngine` around it, the executors, the XPC transport, the budgets and the health policy. |
| `CascadeKit` | The renderer (`PluginNodeStore`, `PluginNodeView`, `PluginDocumentView`), the tier-2 components and the surface adapters (`PluginSurfaceRouter`, `PluginWidget`, `PluginNotice`). |
| `Cascade/Core/Plugins/` | The composition root, `PluginSystem`, which offers the kernel's own sources beside PluginHost's. |
| `cascade-plugin` | The manifest checker, target `CascadePluginTool`. |

## What exists

| Plugin | Entry point | Surface | Source | Tier-2 components |
| --- | --- | --- | --- | --- |
| `com.cascade.battery` | `BatteryPlugin` | Widget (2x1, 2x2, 1x1) | `power` | `power.battery` |
| `com.cascade.clock` | `ClockPlugin` | Widget (2x2, 2x1, 1x1) | none | none |
| `com.cascade.bluetooth` | `BluetoothPlugin` | Notice | `bluetooth` | `bluetooth.device`, `bluetooth.battery` |
| `com.cascade.power` | `ChargingPlugin` | Notice | `power` | `power.battery` |
| `com.cascade.volume` | `VolumePlugin` | Notice | `volume` | `volume.level` |

PluginHost implements the `power` and `bluetooth` sources. The `volume` source runs in the kernel, beside the volume key tap it shares a subsystem with (`Cascade/Core/Volume/VolumePluginSource.swift`); that placement amends the spec's §6, which put volume in PluginHost.

The user places widgets on the notch grid: a long press starts editing, where a widget can be moved, added from the gallery, removed or resized to any size its manifest declares, and a display, once edited, keeps its own arrangement, saved by its UUID (`WidgetHost`). Settings show, on the Widget page under Plugins, the state of every plugin with Re-enable, and PluginHost's with Restart.

## Still pending

- **Music as a plugin**, with the media and spectrum services and the `audio.spectrum`, `media.scrubber` and `audio.outputPicker` components (the services and Music sub-project). Until then Music is native (`MediaLiveActivity` and the expanded fallback), and plugin activities are accepted but not shown.
- **The layout sub-project**: slot pages and the arbitration of compact and expanded space. Plugin widgets meanwhile use today's grid and its editing.
- **External plugins**: discovery, installation, a process per plugin behind the same `PluginExecutor` protocol, and user approval of permissions.
- **Services, storage and assets**: see [the planned page](services.md).

The file shelf and its unsupported-file notice are not pending: they are a system surface, which stays native by rule (spec §6, §7).

## Validating a manifest

```sh
swift run --package-path CascadeKit cascade-plugin validate CascadeKit/Sources/CascadePlugins/Resources/*.json
```

The tool decodes each file with the same `PluginManifest` rules Cascade applies when it registers a plugin and prints one line per file. It exits `0` when every file is valid, `1` when any is not, and `2` on wrong arguments. A version 1 manifest is refused by name. Validation does not run the plugin and does not check a signature. `scripts/build-development.sh` runs it on every bundled manifest before Xcode compiles anything; see [Manifest](manifest.md#validation).
