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
/// external plugin.
final class PluginSystem {

    private let host      : any PluginSurfaceHosting
    private var engine    : PluginEngine?
    private var surfaces  : PluginSurfaceRouter?
    private var isStarting = false

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
        let engine = PluginEngine(
            executor: SharedHostExecutor(transport: XPCPluginTransport(serviceName: serviceName, requirement: requirement)),
            sources : [:],
            sink    : surfaces.makeSink()
        )

        for manifest in manifests {
            engine.register(manifest, grants: Set(manifest.features.flatMap(\.permissions)))
        }

        self.surfaces = surfaces
        self.engine   = engine
    }
}
