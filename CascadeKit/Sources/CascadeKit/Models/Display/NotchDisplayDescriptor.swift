//
//  NotchDisplayDescriptor.swift
//  CascadeKit
//

import AppKit

/// NotchDisplayDescriptor is the settings-safe description of one connected
/// logical display. Runtime IDs address the current session; only `identity`
/// may be persisted across reconnects.
public nonisolated struct NotchDisplayDescriptor: Equatable, Sendable {
    public let runtimeID       : CGDirectDisplayID
    public let identity        : DisplayIdentity?
    public let name            : String
    public let hasHardwareNotch: Bool
    public let style           : ExternalNotchStyle

    public init(
        runtimeID       : CGDirectDisplayID,
        identity        : DisplayIdentity?,
        name            : String,
        hasHardwareNotch: Bool,
        style           : ExternalNotchStyle = .notch
    ) {
        self.runtimeID        = runtimeID
        self.identity         = identity
        self.name             = name
        self.hasHardwareNotch = hasHardwareNotch
        self.style            = style
    }
}
