//
//  SettingsWindowPlacement.swift
//  Cascade
//

import CoreGraphics

/// SettingsWindowPlacement keeps the complete window, including its title bar,
/// below the expanded notch and inside the display's usable area.
nonisolated enum SettingsWindowPlacement {

    static func constrain(
        _ proposed : CGRect,
        below notch: CGRect,
        within area: CGRect
    ) -> CGRect {
        let top    = min(area.maxY, notch.minY - 8)
        let width  = min(proposed.width, area.width)
        let height = min(proposed.height, max(0, top - area.minY))

        return CGRect(
            x     : min(max(proposed.minX, area.minX), area.maxX - width),
            y     : min(max(proposed.minY, area.minY), top - height),
            width : width,
            height: height
        )
    }
}
