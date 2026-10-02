//
//  BluetoothMonitoringStatus.swift
//  Cascade
//

/// BluetoothMonitoringStatus exposes whether the Bluetooth source's system
/// registration is active, as its states say, instead of making silence look
/// like successful monitoring.
enum BluetoothMonitoringStatus: Equatable, Sendable {

    case stopped
    case monitoring
    case unavailable(String)
}
