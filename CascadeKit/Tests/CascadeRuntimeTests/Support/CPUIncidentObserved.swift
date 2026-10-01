//
//  CPUIncidentObserved.swift
//  CascadeKit
//

import CascadeContracts
import Foundation
import Testing
@testable import CascadeRuntime

final class CPUIncidentObserved: @unchecked Sendable {

    private let lock     = NSLock()
    private var observed = false

    func mark() { lock.withLock { observed = true } }

    var value: Bool { lock.withLock { observed } }
}
