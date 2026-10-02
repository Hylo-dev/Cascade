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
/// actions the menu invokes, such as previews. Cascade's own sources, such as volume beside its
/// key tap, are offered next to PluginHost's, and Cascade may observe any source's states as they
/// reach the engine, as the native Bluetooth banner's suppressor does.
final class PluginSystem {

    private let host         : any PluginSurfaceHosting
    private let kernelSources: [String: any PluginEventSource]
    private var engine       : PluginEngine?
    private var surfaces     : PluginSurfaceRouter?
    private var isStarting   = false
    private var disabled     = Set<PluginID>()
    private var observers    : [String: @Sendable (PluginSourceEvent) -> Void] = [:]

    /// statusHandler receives the engine's status on the main thread whenever it changes: each
    /// plugin's state and PluginHost's, for settings.
    var statusHandler: (PluginEngineStatus) -> Void = { _ in }

    /// actionHandler routes an accepted control to a native resource owner. The engine invokes
    /// it only after revision, control, manifest and permission checks, then we hop to main.
    var actionHandler: (PluginActionRequest) -> Void = { _ in }

    init(
        host   : any PluginSurfaceHosting,
        sources: [String: any PluginEventSource] = [:]
    ) {
        self.host          = host
        self.kernelSources = sources
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

    /// observe hands every state of a source to `observer` as it reaches the engine, on the thread
    /// that delivers it. Observers join the sources when the engine is composed, so they are set
    /// before `start`.
    func observe(
        _ source     : String,
        with observer: @escaping @Sendable (PluginSourceEvent) -> Void
    ) {
        observers[source] = observer
    }

    /// reenable brings back a plugin stopped after a hang or quarantined.
    func reenable(_ plugin: PluginID) {
        engine?.reenable(plugin)
    }

    /// restartHost tries PluginHost again after repeated crashes made the engine give up on it.
    func restartHost() {
        engine?.restartHost()
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
            submit    : { [weak self] request in
                self?.engine?.submit(request, onAccepted: { [weak self] accepted in
                    DispatchQueue.main.async {
                        MainActor.assumeIsolated { self?.actionHandler(accepted) }
                    }
                })
            },
            visibility: { [weak self] isVisible, key in self?.engine?.setVisible(isVisible, for: key) }
        )
        let executor = SharedHostExecutor(transport: XPCPluginTransport(serviceName: serviceName, requirement: requirement))
        let hosted   = Dictionary(
            uniqueKeysWithValues: PluginHostCatalog.names.map { name in
                (name, HostedPluginSource(name: name, host: executor) as any PluginEventSource)
            }
        )
        var sources  = kernelSources.merging(hosted) { kernel, _ in kernel }
        for (name, observer) in observers {
            if let source = sources[name] {
                sources[name] = ObservedPluginSource(source: source, observer: observer)
            }
        }
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
        engine.observeStatus { [weak self] status in
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self?.statusHandler(status) }
            }
        }

        self.surfaces = surfaces
        self.engine   = engine
    }
}
