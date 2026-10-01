//
//  SDKInvocationGate.swift
//  CascadeKit
//

import CascadeContracts
import Foundation
import Testing
@testable import CascadeAddonSDK

/// SDKInvocationGate is a deterministic one-arrival/one-release gate; no sleeps, polling or
/// abandoned task.
actor SDKInvocationGate {
    private var arrived = false, released = false
    private var arrival: CheckedContinuation<Void, Never>?
    private var releaseWaiter: CheckedContinuation<Void, Never>?
    func pause() async {
        arrived = true; arrival?.resume(); arrival = nil
        if !released { await withCheckedContinuation { releaseWaiter = $0 } }
    }
    func wait() async { if !arrived { await withCheckedContinuation { arrival = $0 } } }
    func release() { released = true; releaseWaiter?.resume(); releaseWaiter = nil; arrival?.resume(); arrival = nil }
}
