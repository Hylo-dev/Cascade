//
//  LedgerReadSource.swift
//  CascadeKit
//

import CascadeContracts
import Foundation
import Testing
@testable import CascadeRuntime

final class LedgerReadSource: @unchecked Sendable {
    private let lock = NSLock()
    private var queued: [UUID: [ProcessMetricReadResult]]
    private var captured: [ProcessMetricBinding] = []

    init(_ queued: [UUID: [ProcessMetricReadResult]]) {
        self.queued = queued
    }

    var bindings: [ProcessMetricBinding] { lock.withLock { captured } }

    func read(_ binding: ProcessMetricBinding) -> ProcessMetricReadResult {
        lock.withLock {
            captured.append(binding)
            guard var results = queued[binding.token], !results.isEmpty else {
                return .unavailable(.readFailed(5))
            }
            let result = results.removeFirst()
            queued[binding.token] = results
            return result
        }
    }
}
