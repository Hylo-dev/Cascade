//
//  NSScreen+RuntimeDisplayID.swift
//  Cascade
//

import AppKit

extension NSScreen {

    /// cascadeRuntimeDisplayID exposes the AppKit session identifier to app
    /// integrations without depending on CascadeKit's internal screen adapter.
    var cascadeRuntimeDisplayID: CGDirectDisplayID {
        let screenNumberKey = NSDeviceDescriptionKey("NSScreenNumber")
        return (deviceDescription[screenNumberKey] as? NSNumber)?.uint32Value ?? 0
    }
}
