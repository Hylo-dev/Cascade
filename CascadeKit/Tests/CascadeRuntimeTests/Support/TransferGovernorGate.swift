//
//  TransferGovernorGate.swift
//  CascadeKit
//

import CascadeContracts
import CoreGraphics
import Foundation
import ImageIO
import Testing
@testable import CascadeRuntime

/// TransferGovernorGate holds a real actor hop on a detached test worker, with no wall sleep.
/// Every test releases and awaits its worker before inspecting final accounting.
final class TransferGovernorGate: @unchecked Sendable {

    private let condition = NSCondition()

    private var entered  = false
    private var released = false
    private var arrival : CheckedContinuation<Void, Never>?

    func hold() {
        condition.lock()
        entered = true
        arrival?.resume()
        arrival = nil

        while !released { condition.wait() }
        condition.unlock()
    }

    func reached() async {
        await withCheckedContinuation { continuation in
            condition.lock()
            if entered {
                continuation.resume()
            } else {
                arrival = continuation
            }
            condition.unlock()
        }
    }

    func open() {
        condition.lock()
        released = true
        condition.broadcast()
        condition.unlock()
    }
}
