//
//  BluetoothAudioRouteSource.swift
//  Cascade
//

import AppKit
import CoreAudio
import notify
import Foundation
import os

/// Every source operation runs on the worker's serial queue. Only immutable
/// snapshots cross that boundary; implementations must never start discovery.
nonisolated protocol BluetoothAudioRouteSource: AnyObject {
    func start(onChange: @escaping @Sendable () -> Void) -> Bool
    func snapshot() -> BluetoothAudioRouteReadResult
    func stop()
}
