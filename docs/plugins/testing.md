# Testing

A plugin is a value that turns events into output, so most of it is tested without PluginHost, XPC or a notch: create the provider, call `handle(_:context:)` with a `PluginEvent`, and assert on the `PluginOutput` and its documents. The engine has its own layers of tests for what a plugin cannot see.

## A plugin's tests

From `CascadeKit/Tests/CascadePluginsTests/ChargingPluginTests.swift`:

```swift
@Test
func connectingTheChargerShowsTheNotice() throws {
    let plugin = ChargingPlugin()
    _ = try publications(plugin, power(19, external: false, charging: false))

    let shown  = try #require(try publications(plugin, power(19, external: true, charging: true)).first)
    let notice = try #require(shown.notice)

    #expect(shown.surface == .notice)
    #expect(notice.delivery == .show)
    #expect(shown.document?.componentReferences == [try PluginComponentReference(id: "power.battery", version: 1)])
}
```

Cover what the kernel will do to the plugin:

- **The first event after a restart.** A plugin receives the latest state of its sources and a `refresh` after every restart, so check that it rebuilds its content from those alone, and that a first source state is a baseline when it should be, not an event.
- **Repeated and missed states.** Sources coalesce, so a plugin may see the same state twice or skip several. Feed it both.
- **Every action it declares**, including a value at the edge of a slider's range, and an action for a feature or a name it does not handle.
- **The document, by kind and children.** Compare trees with `==` or check `componentReferences` against what the manifest declares. `PluginBuilderTests` shows a builder-written tree compared with the one written by hand.
- **Limits.** A document that breaks a limit throws in `PluginDocument.init`, so a test that builds the largest content the plugin can produce finds the problem before the kernel does.

`FirstPartyPluginsTests` decodes every bundled manifest and checks that each has a provider and a name in settings.

## Imports

A plugin imports only `CascadePluginSDK` and `CascadeContracts`, plus Foundation and Synchronization; its tests may also `@testable import` the plugin's own target. A plugin that imported CascadeKit, the engine, AppKit or SwiftUI would no longer be data only, and could not move to its own process unchanged. `CascadePlugins` depends on nothing else in `Package.swift`, so the package refuses any other Cascade module. `scripts/check-plugin-host-imports.sh` checks the sources of `PluginHost/` and of `CascadePluginSDK`; it does not read the plugins' own sources, so a system framework such as AppKit in a plugin is caught only in review.

## The engine's tests

- **Kernel.** `PluginKernelTests` drive the value-type `PluginKernel` with explicit instants and a `FixedHealthPolicy`: coalescing, budgets, the watchdog, crash attribution, grants and revocation run with no thread, timer or plugin.
- **Engine.** `PluginEngineTests` run `PluginEngine` with `InProcessExecutor`, fake sources and a recording sink.
- **Transport and executor.** `SharedHostExecutorTests` use a fake transport; `XPCPluginTransportTests` run both ends of the real XPC code inside the test process through an anonymous listener. The real service is exercised by `CascadeTests/PluginHostIntegrationTests.swift`, against a Debug PluginHost whose probes answer, hang, trap and exit.
- **Renderer.** `PluginNodeStoreTests` check that a diff notifies only the models of the nodes it changed and that an unconfirmed value reverts; `PluginSurfaceRelayTests` that a burst of deliveries is one hop to main.

Run the package tests serially:

```sh
cd CascadeKit && swift test --no-parallel
```

The engine's tests prove the decisions, not the whole app: a build and a relaunch of Cascade are still how a change is seen working.
