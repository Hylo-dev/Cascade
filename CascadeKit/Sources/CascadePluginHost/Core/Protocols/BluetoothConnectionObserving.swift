//
//  BluetoothConnectionObserving.swift
//  CascadeKit
//

/// BluetoothConnectionObserving is the system's Bluetooth link notifications as the Bluetooth
/// source sees them: one observer per monitoring session, which hands every connection and
/// disconnection to the handler it was built with and reads the devices connected now for a
/// silent baseline. It is a protocol so the source can be tested against a fake system, without
/// IOBluetooth and so without asking macOS for Bluetooth access.
protocol BluetoothConnectionObserving: AnyObject, Sendable {

    /// start registers for connections and says whether the system accepted.
    func start() -> Bool

    /// stop unregisters everything; a callback already queued is stale from now on.
    func stop()

    /// beginBaselineReplacement makes every callback queued so far stale and holds new ones
    /// until `finishBaselineReplacement`, returning the new baseline's epoch.
    func beginBaselineReplacement() -> UInt64

    /// connectedDevices reads the devices connected now and watches their disconnection.
    func connectedDevices() -> [BluetoothConnectedDevice]

    /// finishBaselineReplacement returns, in arrival order, the callbacks that raced the baseline.
    func finishBaselineReplacement() -> [IOBluetoothConnectionCallback]
}
