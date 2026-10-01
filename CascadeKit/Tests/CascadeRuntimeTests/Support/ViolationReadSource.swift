//
//  ViolationReadSource.swift
//  CascadeKit
//

import CascadeContracts
import Foundation
import Testing
@testable import CascadeRuntime

final class ViolationReadSource: @unchecked Sendable {

    private let lock   = NSLock()
    private var queued: [UUID: [ProcessMetricReadResult]]

    init(_ queued: [UUID: [ProcessMetricReadResult]]) {
        self.queued = queued
    }

    func read(_ binding: ProcessMetricBinding) -> ProcessMetricReadResult {
        lock.withLock {
            guard var results = queued[binding.token], !results.isEmpty else {
                return .unavailable(.readFailed(5))
            }

            let result            = results.removeFirst()
            queued[binding.token] = results

            return result
        }
    }
}
