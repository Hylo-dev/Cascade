//
//  Recorder.swift
//  CascadeKit
//

import Synchronization

/// Recorder keeps values reported from any thread, in order.
final class Recorder<Value: Sendable>: Sendable {

    private let recorded = Mutex<[Value]>([])

    var values: [Value] {
        recorded.withLock { $0 }
    }

    func record(_ value: Value) {
        recorded.withLock { $0.append(value) }
    }
}
