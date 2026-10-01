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

    private let widgets : any PluginWidgetHosting
    private var engine  : PluginEngine?
    private var surfaces: PluginSurfaceRouter?

    init(widgets: any PluginWidgetHosting) {
        self.widgets = widgets
    }

    func start() {
        guard engine == nil else { return }

        let manifests   = FirstPartyPlugins.manifests()
        let serviceName = (Bundle.main.bundleIdentifier ?? "hylo.Cascade") + ".PluginHost"
        let surfaces    = PluginSurfaceRouter(
            widgets   : widgets,
            manifests : manifests,
            submit    : { [weak self] request in self?.engine?.submit(request) },
            visibility: { [weak self] isVisible, key in self?.engine?.setVisible(isVisible, for: key) }
        )
        let engine = PluginEngine(
            executor: SharedHostExecutor(
                transport: XPCPluginTransport(
                    serviceName: serviceName,
                    requirement: PluginHostSigning.requirement(identifier: serviceName, team: PluginHostSigning.currentTeam)
                )
            ),
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
