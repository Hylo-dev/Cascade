//
//  BluetoothNoticeSuppressionStatus.swift
//  Cascade
//

/// BluetoothNoticeSuppressionStatus distinguishes observation from verified prevention.
nonisolated enum BluetoothNoticeSuppressionStatus: Equatable, Sendable {

    case stopped
    case permissionRequired
    case observing
    case unsupported(String)
    case failure    (String)
}
