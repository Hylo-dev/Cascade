//
//  BluetoothAudioRouteReadResult.swift
//  Cascade
//

import AppKit
import CoreAudio
import notify
import Foundation
import os

/// A transient HAL read error must not look like a physical route departure.
nonisolated enum BluetoothAudioRouteReadResult: Equatable, Sendable {
    case output(BluetoothAudioRouteSnapshot)
    case noOutput
    case unavailable
}
