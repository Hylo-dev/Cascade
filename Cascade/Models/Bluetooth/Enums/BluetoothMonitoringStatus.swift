//
//  BluetoothMonitoringStatus.swift
//  Cascade
//



/// BluetoothMonitoringStatus exposes whether the concrete system registration
/// is active instead of making an empty stream look like successful monitoring.
enum BluetoothMonitoringStatus: Equatable, Sendable {
    case stopped
    case monitoring
    case unavailable(String)
}
