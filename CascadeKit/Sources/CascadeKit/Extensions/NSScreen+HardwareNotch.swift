//
//  NSScreen+HardwareNotch.swift
//  CascadeKit
//

import AppKit

/// NSScreen + hardware-notch detection.
///
/// macOS describes the notch indirectly: `safeAreaInsets.top` is non-zero on a
/// notched display, and the two `auxiliaryTop*Area` rects are the usable strips
/// to either side of the cut-out. The notch width is therefore the screen width
/// minus those two strips. We read this once and freeze it into an
/// `ActiveDisplay` so the rest of the engine never has to touch AppKit again.
extension NSScreen {

    /// The CoreGraphics display id, used to tell screens apart cheaply.
    var displayID: CGDirectDisplayID {
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        return (deviceDescription[key] as? NSNumber)?.uint32Value ?? 0
    }

    /// Measure this screen's hardware notch, or `.absent` if it has none.
    var hardwareNotch: HardwareNotch {

        guard safeAreaInsets.top > 0 else {
            return .absent
        }

        let leftStrip  = auxiliaryTopLeftArea?.width  ?? 0
        let rightStrip = auxiliaryTopRightArea?.width ?? 0
        let notchWidth = frame.width - leftStrip - rightStrip

        guard notchWidth > 0 else {
            return .absent
        }

        return HardwareNotch(
            isPresent: true,
            size     : CGSize(width: notchWidth - 1, height: safeAreaInsets.top - 1)
        )
    }

    /// Freeze this screen into an immutable snapshot for the engine.
    func activeDisplaySnapshot() -> ActiveDisplay {
        ActiveDisplay(
            displayID   : displayID,
            frame       : frame,
            backingScale: backingScaleFactor,
            notch       : hardwareNotch
        )
    }
}
