//
//  NetworkPlugin.swift
//  CascadeKit
//

import CascadeContracts
import CascadePluginSDK
import Synchronization

/// NetworkPlugin is the network widget: whether the Mac is online, through which kind of link,
/// and whether the system calls that link constrained or expensive. It reads the `network`
/// source, which knows the kind of link and never its name, so it needs no permission, and
/// publishes only when the path changes; a refresh, which comes at start and after a restart,
/// gets the last path again. It never asks for a wake. PluginHost runs it on one thread, so the
/// lock is never contended.
final class NetworkPlugin: PluginProvider {

    static let id      = PluginID(rawValue: "com.cascade.network")!
    static let feature = "network"

    private let last = Mutex<PluginNetworkState?>(nil)

    func handle(
        _ event: PluginEvent,
        context: PluginContext
    ) throws -> PluginOutput {
        switch event {
            case .source(let source):
                guard let state = PluginNetworkState(source) else { return try PluginOutput() }

                let changed = last.withLock { last in
                    defer { last = state }
                    return last != state
                }
                guard changed else { return try PluginOutput() }

                return try PluginOutput(publications: [NetworkFace.publication(for: state)])

            case .refresh:
                guard let state = last.withLock({ $0 }) else { return try PluginOutput() }

                return try PluginOutput(publications: [NetworkFace.publication(for: state)])

            default:
                return try PluginOutput()
        }
    }
}
