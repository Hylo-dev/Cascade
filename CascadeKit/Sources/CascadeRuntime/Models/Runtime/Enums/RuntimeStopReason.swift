//
//  RuntimeStopReason.swift
//  CascadeKit
//

import CascadeContracts
import Foundation

/// RuntimeStopReason explains why the adapter should withdraw queued work and stop a process.
enum RuntimeStopReason: Equatable, Sendable {
    case disabled
    case stopped
    case connectionLost
    case deadlineExceeded
}
