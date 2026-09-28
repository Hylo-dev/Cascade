//
//  BluetoothNoticeObservationSession.swift
//  Cascade
//

import AppKit
@preconcurrency import ApplicationServices
import Observation
import os

/// The shared signal outlives every observer callback and is cancelled before unregistering hosts.
nonisolated final class BluetoothNoticeObservationSession: @unchecked Sendable {
    let hosts: [BluetoothNoticeAccessibilityHostSession]
    let signal: BluetoothNoticeObservationSignal

    init(hosts: [BluetoothNoticeAccessibilityHostSession], signal: BluetoothNoticeObservationSignal) {
        self.hosts = hosts
        self.signal = signal
    }
}
