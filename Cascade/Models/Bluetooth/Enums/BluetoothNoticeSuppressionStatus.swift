//
//  BluetoothNoticeSuppressionStatus.swift
//  Cascade
//

import AppKit
@preconcurrency import ApplicationServices
import Observation
import os

/// BluetoothNoticeSuppressionStatus distinguishes observation from verified prevention.
nonisolated enum BluetoothNoticeSuppressionStatus: Equatable, Sendable {
    case stopped
    case permissionRequired
    case observing
    case unsupported(String)
    case failure(String)
}
