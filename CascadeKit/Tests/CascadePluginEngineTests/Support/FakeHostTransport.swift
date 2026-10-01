//
//  FakeHostTransport.swift
//  CascadeKit
//

import CascadeContracts
import Synchronization

@testable import CascadePluginEngine

/// FakeHostTransport is the in-memory transport: every connection is a `FakeHostLink`.
final class FakeHostTransport: PluginTransport {

    private let made         = Mutex<[FakeHostLink]>([])
    private let losesOnStart: Bool

    init(losesOnStart: Bool = false) {
        self.losesOnStart = losesOnStart
    }

    var links: [FakeHostLink] {
        made.withLock { $0 }
    }

    func connect(
        onLoss       : @escaping @Sendable () -> Void,
        onSourceEvent: @escaping @Sendable (PluginSourceEvent) -> Void
    ) -> any PluginHostLink {
        let link = FakeHostLink(losesOnStart: losesOnStart, onLoss: onLoss, onSourceEvent: onSourceEvent)
        made.withLock { $0.append(link) }
        return link
    }
}
