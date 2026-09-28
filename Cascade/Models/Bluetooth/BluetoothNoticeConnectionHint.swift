//
//  BluetoothNoticeConnectionHint.swift
//  Cascade
//

import Foundation

/// BluetoothNoticeConnectionHint permits matching only shortly after a real connection.
nonisolated struct BluetoothNoticeConnectionHint: Sendable {
    let deviceName : String
    let expiresAt  : Date
}
