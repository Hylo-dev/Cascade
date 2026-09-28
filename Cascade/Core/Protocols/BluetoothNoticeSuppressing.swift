//
//  BluetoothNoticeSuppressing.swift
//  Cascade
//

import AppKit
@preconcurrency import ApplicationServices
import Observation
import os

/// BluetoothNoticeSuppressing closes a matching native notice after presentation, if supported.
@MainActor
protocol BluetoothNoticeSuppressing: AnyObject {
    var status: BluetoothNoticeSuppressionStatus { get }
    func start()
    func stop()
    func expectConnection(deviceName: String)
}
