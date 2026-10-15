//
//  RulerInteraction.swift
//  CascadeKit
//

import Foundation

/// RulerScale is the ruler's range, grid and tick spacing as the node publishes them now. A
/// publication can change them under a gesture (Caffeinate's "Until" ruler moves its range with
/// the clock), so every decision is made against the scale of the moment and none is remembered.
nonisolated struct RulerScale: Equatable, Sendable {

    let minimum: Double
    let maximum: Double
    let step   : Double
    let spacing: Double
}

/// RulerInteraction decides what a ruler slider's gestures do, with no view and no store in it,
/// so the rules can be tested without a pointer. The view feeds it the drag's translation, the
/// end of the drag and the accessibility steps, together with the value shown and the current
/// `RulerScale`, and applies the answers: a value to show, and, for a release or a step, the
/// value to settle on and send.
///
/// The only thing it remembers is the value the drag started from. The scale is passed to each
/// call, never kept, so a release always lands inside the range and on the grid that are drawn
/// at that moment, even when a publication changed them mid-drag.
///
/// A touch that moves less than a point is a tap and does nothing: it must not make the plugin
/// wake for a value that did not change. A drag sends nothing until it ends, and its end sends
/// once, at the nearest step, unless that step is the one the drag started from. A step at
/// either end of the range finds nothing to do.
nonisolated struct RulerInteraction: Equatable {

    /// movementThreshold is the translation, in points, below which a touch is a tap.
    static let movementThreshold = 1.0

    /// dragStart is the value shown when the drag began, nil while no drag is under way.
    private(set) var dragStart: Double?

    /// generation counts the drags started, so a check made about one drag can tell, later,
    /// that the drag it saw is gone and another one has taken its place.
    private(set) var generation = 0

    var isDragging: Bool {
        dragStart != nil
    }

    /// change is the value to show for a drag that has moved `translation` points, or nil while
    /// the touch is still a tap.
    mutating func change(
        translation: Double,
        current    : Double,
        scale      : RulerScale
    ) -> Double? {
        if dragStart == nil {
            guard abs(translation) >= Self.movementThreshold else { return nil }
            dragStart  = current
            generation += 1
        }

        return RulerGeometry.dragged(
            from       : dragStart ?? current,
            translation: translation,
            minimum    : scale.minimum,
            maximum    : scale.maximum,
            step       : scale.step,
            spacing    : scale.spacing
        )
    }

    /// end finishes the drag: the step to settle on and send, or nil when there is nothing to
    /// send, either because there was no drag or because the finger came back to the step the
    /// drag started from. A release that changes nothing must not move a running session: the
    /// value shown for a running "For" is its time left rounded up, so sending it back would
    /// rewrite the end to a figure the user never chose.
    mutating func end(
        current: Double,
        scale  : RulerScale
    ) -> Double? {
        guard let start = dragStart else { return nil }
        dragStart = nil

        let target = snapped(current, scale)

        return target == snapped(start, scale) ? nil : target
    }

    /// cancel forgets a drag that will not end, and says whether there was one.
    mutating func cancel() -> Bool {
        defer { dragStart = nil }

        return dragStart != nil
    }

    /// adjust is the step an accessibility increment (`+1`) or decrement (`-1`) lands on, or
    /// nil at the end of the range, where the value would not change.
    func adjust(
        _ direction: Int,
        current    : Double,
        scale      : RulerScale
    ) -> Double? {
        let now  = snapped(current, scale)
        let next = snapped(now + Double(direction) * scale.step, scale)

        return next == now ? nil : next
    }

    private func snapped(
        _ value: Double,
        _ scale: RulerScale
    ) -> Double {
        RulerGeometry.snapped(value, minimum: scale.minimum, maximum: scale.maximum, step: scale.step)
    }
}
