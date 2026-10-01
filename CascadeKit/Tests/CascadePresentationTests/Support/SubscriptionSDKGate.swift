//
//  SubscriptionSDKGate.swift
//  CascadeKit
//

import CascadeContracts
import Foundation
import Testing
@testable import CascadeAddonSDK

actor SubscriptionSDKGate {
    private var arrived = false
    private var open = false
    private var arrival: CheckedContinuation<Void, Never>?
    private var continuations: [CheckedContinuation<Void, Never>] = []
    func arrive() { arrived = true; arrival?.resume(); arrival = nil }
    func waitForArrival() async { if !arrived { await withCheckedContinuation { arrival = $0 } } }
    func pause() async { arrive(); if !open { await withCheckedContinuation { continuations.append($0) } } }
    func release() { open = true; let all = continuations; continuations.removeAll(); for continuation in all { continuation.resume() } }
}
