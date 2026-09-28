//
//  BluetoothAudioRouteReducer.swift
//  Cascade
//

import CoreAudio
import Foundation

/// Default audio route changes are independent of ACL connection callbacks.
/// In particular, A → built-in → A must emit again even if A stayed connected.
nonisolated struct BluetoothAudioRouteReducer {
    private var hasBaseline = false
    private var currentUID: String?

    mutating func replaceBaseline(_ snapshot: BluetoothAudioRouteSnapshot?) {
        hasBaseline = true
        currentUID = snapshot?.uid
    }

    mutating func receive(_ snapshot: BluetoothAudioRouteSnapshot?) -> BluetoothConnectedDevice? {
        let previousUID = currentUID
        let wasInitialized = hasBaseline
        replaceBaseline(snapshot)
        guard wasInitialized, previousUID != currentUID else { return nil }
        return snapshot?.bluetoothDevice
    }
}
