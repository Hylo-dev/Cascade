//
//  PluginHostClient.swift
//  CascadeKit
//

import CascadeContracts
import CascadePluginHost
import Foundation

/// PluginHostClient is the object the kernel exports to PluginHost, through which the host's
/// catalog sources send their states. Each one is decoded with the contracts' validation; one
/// that is too large or does not decode is dropped, so a misbehaving host cannot feed a plugin
/// anything the contracts would refuse.
final class PluginHostClient: NSObject, PluginHostClientProtocol, Sendable {

    static let maximumEventBytes = 8_192

    private let onSourceEvent: @Sendable (PluginSourceEvent) -> Void

    init(onSourceEvent: @escaping @Sendable (PluginSourceEvent) -> Void) {
        self.onSourceEvent = onSourceEvent
    }

    func sourceChanged(event: Data) {
        guard event.count <= Self.maximumEventBytes,
              let decoded = try? JSONDecoder().decode(PluginSourceEvent.self, from: event)
        else { return }

        onSourceEvent(decoded)
    }
}
