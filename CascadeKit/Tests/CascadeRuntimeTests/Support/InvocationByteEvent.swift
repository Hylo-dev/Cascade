//
//  InvocationByteEvent.swift
//  CascadeKit
//

import CascadeContracts
import Foundation
import Testing
@testable import CascadeAddonSDK
@testable import CascadeRuntime

/// InvocationByteEvent is a one-shot event signal in adapter/channel ownership, never a runtime
/// waiter queue.
final class InvocationByteEvent: @unchecked Sendable {
    private let lock = NSLock()
    private var signaled = false
    private var continuation: CheckedContinuation<Void, Never>?
    func signal() { lock.withLock {
        if let c = continuation { continuation = nil; c.resume() }
        else { signaled = true }
    } }
    func wait() async {
        await withCheckedContinuation { c in lock.withLock {
            if signaled { signaled = false; c.resume() } else { precondition(continuation == nil); continuation = c }
        } }
    }
}
