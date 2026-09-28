//
//  FocusedDisplayResolver.swift
//  CascadeKit
//

import CoreGraphics

/// FocusedDisplayResolver chooses the logical display that owns user focus.
///
/// Window geometry has priority over the pointer. A window that crosses display
/// boundaries belongs to the display containing its largest positive area; an
/// exact tie keeps the previous winner when possible, then falls back to the
/// lowest runtime display ID for a deterministic result.
nonisolated enum FocusedDisplayResolver {

    /// resolve applies window-first focus and the pointer, main-display and
    /// stable-ID fallbacks without consulting AppKit or Accessibility.
    static func resolve(
        window  : CGRect?,
        pointer : CGPoint,
        frames  : [CGDirectDisplayID: CGRect],
        previous: CGDirectDisplayID?,
        main    : CGDirectDisplayID?
    ) -> CGDirectDisplayID? {
        let validFrames = frames.filter { Self.isValid($0.value) }
        let orderedIDs  = validFrames.keys.sorted()

        if let window, Self.isValid(window) {
            let intersections = orderedIDs.compactMap { displayID -> (CGDirectDisplayID, CGFloat)? in
                guard let displayFrame = validFrames[displayID] else { return nil }

                let area = Self.positiveIntersectionArea(window, displayFrame)
                return area > 0 ? (displayID, area) : nil
            }

            if let largestArea = intersections.map(\.1).max() {
                let candidates = intersections.filter { $0.1 == largestArea }.map(\.0)
                if let previous, candidates.contains(previous) {
                    return previous
                }
                return candidates.first
            }
        }

        if pointer.x.isFinite, pointer.y.isFinite,
           let pointedDisplay = orderedIDs.first(where: { displayID in
               validFrames[displayID]?.contains(pointer) == true
           }) {
            return pointedDisplay
        }

        if let main, validFrames[main] != nil {
            return main
        }

        return orderedIDs.first
    }

    private static func positiveIntersectionArea(
        _ lhs: CGRect,
        _ rhs: CGRect
    ) -> CGFloat {
        let intersection = lhs.intersection(rhs)
        guard Self.isValid(intersection) else { return 0 }

        return intersection.width * intersection.height
    }

    private static func isValid(_ frame: CGRect) -> Bool {
        !frame.isNull
            && !frame.isInfinite
            && frame.origin.x.isFinite
            && frame.origin.y.isFinite
            && frame.width.isFinite
            && frame.height.isFinite
            && frame.width > 0
            && frame.height > 0
    }
}
