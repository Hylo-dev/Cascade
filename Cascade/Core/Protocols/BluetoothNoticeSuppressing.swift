//
//  BluetoothNoticeSuppressing.swift
//  Cascade
//

/// BluetoothNoticeSuppressing closes a matching native notice after presentation, if supported.
@MainActor
protocol BluetoothNoticeSuppressing: AnyObject {

    var status: BluetoothNoticeSuppressionStatus { get }

    func start()
    func stop()
    func expectConnection(deviceName: String)
}
