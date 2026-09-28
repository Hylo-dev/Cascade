//
//  BluetoothNoticeObservationSession.swift
//  Cascade
//

import AppKit
@preconcurrency import ApplicationServices

/// BluetoothNoticeObservationSession owns the shared signal, which outlives every observer callback
/// and is cancelled before unregistering hosts.
nonisolated final class BluetoothNoticeObservationSession: @unchecked Sendable {

    let hosts : [BluetoothNoticeAccessibilityHostSession]
    let signal: BluetoothNoticeObservationSignal

    init(
        hosts : [BluetoothNoticeAccessibilityHostSession],
        signal: BluetoothNoticeObservationSignal
    ) {
        self.hosts  = hosts
        self.signal = signal
    }
}
