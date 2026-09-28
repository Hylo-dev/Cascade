//
//  StopReason.swift
//  CascadeKit
//

import Foundation

/// StopReason gives providers an explicit finite lifecycle termination reason.
public enum StopReason: String, Codable, Sendable {
    case idle, disabled, permissionRevoked, resourceExceeded, hostStopping, updated
}
