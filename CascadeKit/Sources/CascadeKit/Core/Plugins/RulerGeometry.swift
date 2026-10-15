//
//  RulerGeometry.swift
//  CascadeKit
//

import Foundation

/// RulerTick is one visible tick of a ruler slider, already resolved to what the drawing needs:
/// where it stands, how tall and how opaque it is, whether the value has passed it and which
/// step of the ruler it is. `offset` is in points from the indicator, negative to its left.
nonisolated struct RulerTick: Equatable, Sendable {

    let value         : Double
    let offset        : Double
    let heightFraction: Double
    let alpha         : Double
    let isPassed      : Bool
    let labelIndex    : Int
}

/// RulerGeometry is the arithmetic of the kernel's ruler slider, with no view in it. The ruler
/// is a row of ticks, one per `step`, that slides under a fixed indicator at the middle of its
/// width: a tick stands at `(tick - value) / step * spacing` points from the indicator, so the
/// value maps to a scroll position and the drag maps back to a value, with no state of its own.
///
/// Only the ticks that can be seen are produced. The first and last are found by arithmetic,
/// not by walking the whole range, so a ruler of two thousand steps costs what a screenful
/// does: about twenty ticks. Height and alpha fall off linearly with the distance from the
/// indicator, `1 → 0.45` for the height and `1 → 0` for the alpha, so the ticks near the edge
/// fade out before they are cut and the row looks like a dial, not a strip.
///
/// Everything is `nonisolated`: CascadeKit defaults to the main actor, and these are pure
/// functions of their arguments. `forEachTick` is the drawing path, which allocates nothing;
/// `ticks` collects the same ticks for tests and for any caller that wants an array.
nonisolated enum RulerGeometry {

    /// edgeFalloff makes the alpha reach zero a little before the edge, so a tick is never
    /// drawn as a sliver the eye cannot see; heightAtEdge is what the height falls to there.
    static let edgeFalloff  = 1.05
    static let heightAtEdge = 0.45

    /// forEachTick calls `body` for each visible tick, from left to right. A tick is visible
    /// when it lies inside the width, in the range and not yet fully faded. `origin` is added to
    /// a tick's value before its step is counted into `labelIndex`: a ruler of clock times
    /// passes the zone's offset from UTC, so the labelled ticks fall on the local hour.
    static func forEachTick(
        value  : Double,
        minimum: Double,
        maximum: Double,
        step   : Double,
        width  : Double,
        spacing: Double,
        origin : Double = 0,
        _ body : (RulerTick) -> Void
    ) {
        guard step > 0, spacing > 0, width > 0, maximum > minimum,
              value.isFinite, step.isFinite, width.isFinite
        else { return }

        let half     = width / 2
        let halfSpan = half / spacing * step
        let last     = Int(((maximum - minimum) / step + 1e-9).rounded(.down))
        let first    = max(0, Int(((value - halfSpan - minimum) / step).rounded(.up)))
        let final    = min(last, Int(((value + halfSpan - minimum) / step).rounded(.down)))
        let epsilon  = step * 1e-9

        guard first <= final else { return }

        for index in first...final {
            let tickValue = minimum + Double(index) * step
            let offset    = (tickValue - value) / step * spacing
            let distance  = abs(offset) / half
            let alpha     = 1 - distance * edgeFalloff

            guard alpha > 0 else { continue }

            body(
                RulerTick(
                    value         : tickValue,
                    offset        : offset,
                    heightFraction: 1 - distance * (1 - heightAtEdge),
                    alpha         : alpha,
                    isPassed      : tickValue <= value + epsilon,
                    labelIndex    : Int(((tickValue + origin) / step).rounded())
                )
            )
        }
    }

    /// ticks is `forEachTick` collected, at most `⌈width / spacing⌉ + 2` of them.
    static func ticks(
        value  : Double,
        minimum: Double,
        maximum: Double,
        step   : Double,
        width  : Double,
        spacing: Double,
        origin : Double = 0
    ) -> [RulerTick] {
        var collected = [RulerTick]()
        collected.reserveCapacity(Int((max(width, 0) / max(spacing, 1)).rounded(.up)) + 2)

        forEachTick(
            value  : value,
            minimum: minimum,
            maximum: maximum,
            step   : step,
            width  : width,
            spacing: spacing,
            origin : origin
        ) { collected.append($0) }

        return collected
    }

    /// snapped is the step of the ruler nearest to `value`, inside the range: where a release
    /// settles, and where an accessibility step lands.
    static func snapped(
        _ value: Double,
        minimum: Double,
        maximum: Double,
        step   : Double
    ) -> Double {
        guard step > 0, maximum > minimum, value.isFinite else { return minimum }

        let last  = (maximum - minimum) / step + 1e-9
        let index = ((value - minimum) / step).rounded()

        return minimum + min(max(index, 0), last.rounded(.down)) * step
    }

    /// dragged is the value after a horizontal drag of `translation` points from `start`:
    /// dragging left slides the ticks left and raises the value, as the iOS timer's does. It is
    /// continuous, so the ticks follow the finger; the snap to a step comes on release.
    static func dragged(
        from start : Double,
        translation: Double,
        minimum    : Double,
        maximum    : Double,
        step       : Double,
        spacing    : Double
    ) -> Double {
        guard spacing > 0, step > 0 else { return start }

        return min(max(start - translation / spacing * step, minimum), maximum)
    }
}
