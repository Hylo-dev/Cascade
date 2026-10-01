//
//  PluginSystem.swift
//  Cascade
//

import CascadeContracts
import CascadeKit
import CascadePluginEngine
import CascadePluginHost
import CascadePlugins
import Foundation

/// PluginSystem composes the plugin engine in Cascade. The engine runs the bundled first-party
/// plugins in PluginHost over XPC, never in this process, and their publications reach the
/// notch through the surfaces' single hop to main. Bundled plugins signed by us get every
/// permission their manifests declare; the approver is the only thing that will differ for an
/// external plugin. Cascade's own settings reach plugins through it: a switch per plugin and the
/// actions the menu invokes, such as previews.
final class PluginSystem {

    private let host      : any PluginSurfaceHosting
    private var engine    : PluginEngine?
    private var surfaces  : PluginSurfaceRouter?
    private var isStarting = false
    private var disabled   = Set<PluginID>()

    init(host: any PluginSurfaceHosting) {
        self.host = host
    }

    /// start reads the bundled manifests and the app's signing team off the main thread, since
    /// both touch the disk, and composes the engine back on it. A second call while starting or
    /// started does nothing.
    func start() {
        guard engine == nil, !isStarting else { return }

        isStarting = true

        let serviceName = (Bundle.main.bundleIdentifier ?? "hylo.Cascade") + ".PluginHost"
        Task.detached(priority: .utility) { [weak self] in
            let manifests   = FirstPartyPlugins.manifests()
            let requirement = PluginHostSigning.requirement(identifier: serviceName, team: PluginHostSigning.currentTeam)

            await self?.compose(
                manifests  : manifests,
                serviceName: serviceName,
                requirement: requirement
            )
        }
    }

    /// setEnabled switches a plugin on or off for the user, now or, before the engine is
    /// composed, as soon as it is.
    func setEnabled(
        _ isEnabled: Bool,
        for plugin : PluginID
    ) {
        if isEnabled {
            disabled.remove(plugin)
        } else {
            disabled.insert(plugin)
        }
        engine?.setEnabled(isEnabled, for: plugin)
    }

    /// invoke asks a plugin to run one of its declared actions; before the engine is composed it
    /// does nothing.
    func invoke(
        _ action : String,
        value    : PluginValue? = nil,
        feature  : String,
        of plugin: PluginID
    ) {
        engine?.invoke(action, value: value, feature: feature, of: plugin)
    }

    private func compose(
        manifests  : [PluginManifest],
        serviceName: String,
        requirement: String?
    ) {
        let surfaces = PluginSurfaceRouter(
            host      : host,
            manifests : manifests,
            submit    : { [weak self] request in self?.engine?.submit(request) },
            visibility: { [weak self] isVisible, key in self?.engine?.setVisible(isVisible, for: key) }
        )
        let executor = SharedHostExecutor(transport: XPCPluginTransport(serviceName: serviceName, requirement: requirement))
        let sources  = Dictionary(
            uniqueKeysWithValues: PluginHostCatalog.names.map { name in
                (name, HostedPluginSource(name: name, host: executor) as any PluginEventSource)
            }
        )
        let engine = PluginEngine(
            executor  : executor,
            sources   : sources,
            components: PluginSurfaceRouter.components,
            sink      : surfaces.makeSink()
        )

        for manifest in manifests {
            engine.register(manifest, grants: Set(manifest.features.flatMap(\.permissions)))
        }
        for plugin in disabled {
            engine.setEnabled(false, for: plugin)
        }

        self.surfaces = surfaces
        self.engine   = engine
    }
}
