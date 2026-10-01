//
//  StartGate.swift
//  CascadeKit
//

@testable import CascadeAddonSDK
import CascadeContracts
import Foundation
import Testing

/// StartGate is a one-shot synchronization point so a test can cancel a task deterministically
/// before the client operation begins.
actor StartGate {
    private var continuation: CheckedContinuation<Void, Never>?
    private var isOpen = false

    func wait() async {
        if isOpen { return }
        await withCheckedContinuation { continuation = $0 }
    }

    func open() {
        isOpen = true
        continuation?.resume()
        continuation = nil
    }
}
