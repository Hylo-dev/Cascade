//
//  RecordingSink.swift
//  CascadeKit
//

import Synchronization

@testable import CascadePluginEngine

/// RecordingSink keeps every change and rejection the engine delivers.
final class RecordingSink: PluginPublicationSink {

    private let recorded = Mutex<(changes: [PluginPublicationChange], rejected: [PluginActionRequest])>(([], []))

    var changes: [PluginPublicationChange] {
        recorded.withLock { $0.changes }
    }

    func deliver(_ changes: [PluginPublicationChange]) {
        recorded.withLock { $0.changes += changes }
    }

    func reject(_ request: PluginActionRequest) {
        recorded.withLock { $0.rejected.append(request) }
    }
}
