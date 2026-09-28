//
//  BluetoothMonitoring.swift
//  Cascade
//

/// BluetoothMonitoringStatus exposes whether the concrete system registration
/// is active instead of making an empty stream look like successful monitoring.
enum BluetoothMonitoringStatus: Equatable, Sendable {
    case stopped
    case monitoring
    case unavailable(String)
}

/// BluetoothMonitoring owns a Bluetooth event subscription for the app.
///
/// The explicit lifecycle lets Cascade release every system notification when
/// monitoring is disabled or the application terminates. A new stream is
/// created for each start so an old consumer cannot receive a later session.
@MainActor
protocol BluetoothMonitoring: AnyObject {

    /// status reports the concrete registration state for settings and menus.
    var status: BluetoothMonitoringStatus { get }

    /// start begins monitoring and returns a fresh bounded event stream.
    func start() -> AsyncStream<BluetoothConnectionEvent>

    /// stop ends the stream and releases every system registration.
    func stop()
}
