//
//  RasterGate.swift
//  CascadeKit
//

import CascadeContracts
import CoreGraphics
import Foundation
import Testing
@testable import CascadeRuntime

actor RasterGate {
    private var entered = false
    private var released = false
    private var arrival: CheckedContinuation<Void, Never>?
    private var waiter: CheckedContinuation<Void, Never>?
    func pause() async {
        entered = true
        arrival?.resume()
        arrival = nil
        if !released { await withCheckedContinuation { waiter = $0 } }
    }
    func reached() async {
        if !entered { await withCheckedContinuation { arrival = $0 } }
    }
    func open() {
        released = true
        waiter?.resume()
        waiter = nil
    }
}
