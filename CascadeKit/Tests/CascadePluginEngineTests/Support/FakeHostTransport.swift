//
//  FakeHostTransport.swift
//  CascadeKit
//

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

    func connect(onLoss: @escaping @Sendable () -> Void) -> any PluginHostLink {
        let link = FakeHostLink(losesOnStart: losesOnStart, onLoss: onLoss)
        made.withLock { $0.append(link) }
        return link
    }
}
