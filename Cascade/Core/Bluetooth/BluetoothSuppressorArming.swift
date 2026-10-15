//
//  BluetoothSuppressorArming.swift
//  Cascade
//

import CascadeContracts

/// BluetoothSuppressorArming decides which Bluetooth states arm the native banner's suppressor:
/// the first state of a new connection, the moment macOS raises its own banner, and only once.
/// The source sends a state again, at the same number and revision, when a battery read changes
/// only its list of devices, and that is no new banner: arming then could dismiss a real macOS
/// banner while Cascade shows nothing. So an event arms only when its number is newer than the
/// last one armed. Numbers never repeat within one PluginHost, and a source that starts again
/// begins with a baseline, number zero, which forgets the last number armed, since a restarted
/// PluginHost counts from one again.
nonisolated struct BluetoothSuppressorArming: Sendable {

    private var lastArmedEventID: UInt64?

    mutating func arms(for state: PluginBluetoothState) -> Bool {
        guard state.eventID != 0 else {
            lastArmedEventID = nil
            return false
        }
        guard state.isNewConnection, state.eventID > lastArmedEventID ?? 0 else { return false }

        lastArmedEventID = state.eventID
        return true
    }
}
