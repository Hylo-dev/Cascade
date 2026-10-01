//
//  ArchiveGate.swift
//  CascadeKit
//

import CascadeContracts
import Darwin
import Foundation
import SwiftData
import Testing
@testable import CascadeRuntime

/// ArchiveGate retains one controlled continuation per side, without polling or waiter arrays.
actor ArchiveGate {
    private var entered = false
    private var releaseContinuation: CheckedContinuation<Void, Never>?
    private var enteredContinuation: CheckedContinuation<Void, Never>?

    func enter() async {
        entered = true
        enteredContinuation?.resume()
        enteredContinuation = nil
        await withCheckedContinuation { releaseContinuation = $0 }
    }

    func waitUntilEntered() async {
        if !entered { await withCheckedContinuation { enteredContinuation = $0 } }
    }

    func release() {
        releaseContinuation?.resume()
        releaseContinuation = nil
    }
}
