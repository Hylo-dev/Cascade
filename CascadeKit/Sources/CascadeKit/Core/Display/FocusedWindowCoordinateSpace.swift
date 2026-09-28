//
//  FocusedWindowCoordinateSpace.swift
//  CascadeKit
//

import AppKit
@preconcurrency import ApplicationServices

/// FocusedWindowCoordinateSpace converts Accessibility's top-left, downward-y
/// desktop space into AppKit's global bottom-left, upward-y space.
nonisolated enum FocusedWindowCoordinateSpace {

    /// appKitFrame preserves x because both spaces share the primary display's
    /// horizontal origin and reflects y around that display's AppKit top edge.
    static func appKitFrame(
        fromAXFrame frame: CGRect,
        desktopTop         : CGFloat
    ) -> CGRect? {
        guard desktopTop.isFinite,
              !frame.isNull,
              !frame.isInfinite,
              frame.origin.x.isFinite,
              frame.origin.y.isFinite,
              frame.width.isFinite,
              frame.height.isFinite,
              frame.width > 0,
              frame.height > 0 else {
            return nil
        }

        return CGRect(
            x     : frame.minX,
            y     : desktopTop - frame.maxY,
            width : frame.width,
            height: frame.height
        )
    }
}
