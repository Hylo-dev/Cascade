//
//  BluetoothConnectionCallbackGate.swift
//  Cascade
//

import Foundation

/// BluetoothConnectionCallbackGate rejects callback work queued before a stop,
/// restart, or wake baseline replacement.
nonisolated struct BluetoothConnectionCallbackGate {

    private(set) var identity = BluetoothConnectionCallbackIdentity(
        sessionID    : 0,
        baselineEpoch: 0
    )

    mutating func beginSession(sessionID: UInt64) {
        identity = BluetoothConnectionCallbackIdentity(
            sessionID    : sessionID,
            baselineEpoch: 0
        )
    }

    mutating func replaceBaseline(epoch: UInt64) {
        identity = BluetoothConnectionCallbackIdentity(
            sessionID    : identity.sessionID,
            baselineEpoch: epoch
        )
    }

    func accepts(_ callbackIdentity: BluetoothConnectionCallbackIdentity) -> Bool {
        callbackIdentity == identity
    }
}
