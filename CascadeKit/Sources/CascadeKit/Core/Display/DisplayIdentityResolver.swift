//
//  DisplayIdentityResolver.swift
//  CascadeKit
//

import AppKit
import ColorSync

/// DisplayIdentityResolver is the one CoreGraphics UUID bridge shared by
/// inventory and hardware-notch calibration persistence.
nonisolated enum DisplayIdentityResolver {

    /// resolve returns the stable UUID for a runtime display ID, or nil when
    /// CoreGraphics cannot expose one for this screen.
    static func resolve(displayID: CGDirectDisplayID) -> DisplayIdentity? {
        guard let uuid = CGDisplayCreateUUIDFromDisplayID(displayID)?.takeRetainedValue() else {
            return nil
        }

        return DisplayIdentity(rawValue: CFUUIDCreateString(nil, uuid) as String)
    }
}
