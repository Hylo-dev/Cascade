//
//  AuxiliaryContentGate.swift
//  CascadeKit
//

import AppKit
import Testing
@testable import CascadeKit

/// AuxiliaryContentGate deliberately ignores cancellation, like an in-flight
/// system query, to prove session identity protects against late completions.
@MainActor
final class AuxiliaryContentGate {

    private var continuation: CheckedContinuation<NSViewController?, Never>?
    private var didReturn    = false

    func wait() async -> NSViewController? {
        let content = await withCheckedContinuation { continuation = $0 }
        didReturn   = true
        return content
    }

    func resume() {
        continuation?.resume(returning: NSViewController())
        continuation = nil
    }

    func waitUntilRequested() async {
        for _ in 0..<100 where continuation == nil { await Task.yield() }
        #expect(continuation != nil)
    }

    func waitUntilReturned() async {
        for _ in 0..<100 where !didReturn { await Task.yield() }
        #expect(didReturn)
    }
}
