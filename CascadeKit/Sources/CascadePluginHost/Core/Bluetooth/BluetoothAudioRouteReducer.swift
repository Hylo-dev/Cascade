//
//  BluetoothAudioRouteReducer.swift
//  CascadeKit
//

/// BluetoothAudioRouteReducer treats default audio route changes independently
/// of ACL connection callbacks.
/// In particular, A → built-in → A must emit again even if A stayed connected.
struct BluetoothAudioRouteReducer {

    private var hasBaseline = false
    private var currentUID : String?

    mutating func replaceBaseline(_ snapshot: BluetoothAudioRouteSnapshot?) {
        hasBaseline = true
        currentUID  = snapshot?.uid
    }

    mutating func receive(_ snapshot: BluetoothAudioRouteSnapshot?) -> BluetoothConnectedDevice? {
        let previousUID    = currentUID
        let wasInitialized = hasBaseline
        replaceBaseline(snapshot)

        guard wasInitialized, previousUID != currentUID else { return nil }

        return snapshot?.bluetoothDevice
    }
}
