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
        let screenNumberKey = NSDeviceDescriptionKey("NSScreenNumber")
        return (deviceDescription[screenNumberKey] as? NSNumber)?.uint32Value ?? 0
    }

    /// hardwareNotch measures the compact footprint, or `.absent` without a
    /// cutout. The width bounds the complete compact outline, flared top
    /// corners included: its body sits just inside the unsafe gap and the two
    /// concave top corners flare past it into the bezel. The underside ends on
    /// the safe-area line. On a 14" MacBook Pro at its default scaling this is
    /// the 192 × 32 pt standard; deriving it from the gap keeps it right under
    /// scaled resolutions too. "Regola dimensioni del notch…" overrides it per
    /// display.
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

        let bodyInset: CGFloat = 1 // The body stays one point inside the gap.
        let flare    : CGFloat = 4 // NotchConfiguration.restingTopCornerRadius.

        return HardwareNotch(
            isPresent: true,
            size     : CGSize(
                width : notchWidth - bodyInset + 2 * flare,
                height: safeAreaInsets.top
            )
        )
    }

    /// activeDisplaySnapshot freezes this screen into an immutable snapshot for
    /// the engine.
    func activeDisplaySnapshot() -> ActiveDisplay {
        ActiveDisplay(
            displayID   : displayID,
            frame       : frame,
            backingScale: backingScaleFactor,
            notch       : hardwareNotch
        )
    }
}
