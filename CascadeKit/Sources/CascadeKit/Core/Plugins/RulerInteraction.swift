//
//  RulerInteraction.swift
//  CascadeKit
//

import Foundation

/// RulerInteraction decides what a ruler slider's gestures do, with no view and no store in it,
/// so the rules can be tested without a pointer. The view feeds it the drag's translation, the
/// end of the drag and the accessibility steps, together with the value shown, and applies the
/// answers: a value to show, and, for a release or a step, the value to settle on and send.
///
/// A touch that moves less than a point is a tap and does nothing: it must not make the plugin
/// wake for a value that did not change. A drag sends nothing until it ends, and its end sends
/// once, at the nearest step. A step at either end of the range finds nothing to do.
nonisolated struct RulerInteraction: Equatable {

    /// movementThreshold is the translation, in points, below which a touch is a tap.
    static let movementThreshold = 1.0

    let minimum: Double
    let maximum: Double
    let step   : Double
    let spacing: Double

    /// dragStart is the value shown when the drag began, nil while no drag is under way.
    private(set) var dragStart: Double?

    init(
        minimum: Double,
        maximum: Double,
        step   : Double,
        spacing: Double
    ) {
        self.minimum = minimum
        self.maximum = maximum
        self.step    = step
        self.spacing = spacing
    }

    var isDragging: Bool {
        dragStart != nil
    }

    /// change is the value to show for a drag that has moved `translation` points, or nil while
    /// the touch is still a tap.
    mutating func change(
        translation: Double,
        current    : Double
    ) -> Double? {
        if dragStart == nil {
            guard abs(translation) >= Self.movementThreshold else { return nil }
            dragStart = current
        }

        return RulerGeometry.dragged(
            from       : dragStart ?? current,
            translation: translation,
            minimum    : minimum,
            maximum    : maximum,
            step       : step,
            spacing    : spacing
        )
    }

    /// end finishes the drag: the step to settle on and send, or nil when there was no drag.
    mutating func end(current: Double) -> Double? {
        guard dragStart != nil else { return nil }
        dragStart = nil

        return RulerGeometry.snapped(current, minimum: minimum, maximum: maximum, step: step)
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
        current    : Double
    ) -> Double? {
        let now  = RulerGeometry.snapped(current, minimum: minimum, maximum: maximum, step: step)
        let next = RulerGeometry.snapped(now + Double(direction) * step, minimum: minimum, maximum: maximum, step: step)

        return next == now ? nil : next
    }
}
