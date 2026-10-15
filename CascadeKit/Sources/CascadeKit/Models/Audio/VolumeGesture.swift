//
//  VolumeGesture.swift
//  CascadeKit
//

import CoreGraphics

/// VolumeGesture follows one press on the volume capsule, from touch-down to release, and turns
/// it into a click (open the mixer) or a drag (set the level). Scrolling has no press, so it is a
/// pure function beside it. Muting is never decided here: it is set only from the mixer, and a
/// level of zero is not mute.
///
/// It is a reducer: the view feeds it the pointer's translation and elapsed time, and it answers
/// what to do. It reuses `WidgetPress`'s slop and hold duration, so the capsule's feel matches the
/// widget tiles'. A press that stays inside the slop and is released before the hold duration is
/// a click; one held still past it is neither a click nor a drag, because that hold belongs to the
/// grid's editing (the tile's hold): the capsule neither opens the mixer nor changes the level.
/// Once the pointer has left the slop it is a drag for good, even if it comes back, because the
/// user has started choosing a level.
nonisolated public struct VolumeGesture: Equatable, Sendable {

    public enum Outcome: Equatable, Sendable {

        case none
        case click
        case level(Double)
    }

    /// wheelStep is how far one notch of a mouse wheel moves the level.
    private static let wheelStep = 1.0 / 16.0

    /// preciseDivisor turns trackpad points into level: 200 points sweep the whole range.
    private static let preciseDivisor = 200.0

    private let startLevel: Double
    private let travel    : Double
    private var isDragging = false

    /// travel is the capsule's height in points, so dragging its full height sweeps the range.
    public init(
        startLevel: Double,
        travel    : Double
    ) {
        self.startLevel = startLevel
        self.travel     = travel
    }

    public mutating func move(
        to translation: CGSize,
        elapsed       : Duration
    ) -> Outcome {
        guard isDragging || Self.distance(of: translation) > WidgetPress.slop else { return .none }

        isDragging = true
        return .level(level(at: translation))
    }

    public mutating func end(
        translation: CGSize,
        elapsed    : Duration
    ) -> Outcome {
        if isDragging || Self.distance(of: translation) > WidgetPress.slop {
            isDragging = true
            return .level(level(at: translation))
        }
        return elapsed < WidgetPress.holdDuration ? .click : .none
    }

    /// overshoot is how many points the pointer has gone past the end of the range: positive past
    /// the top (the level is full and the user keeps pulling up), negative past the bottom. It is
    /// zero inside the range and before the press becomes a drag, so a click never stretches.
    public func overshoot(at translation: CGSize) -> Double {
        guard isDragging else { return 0 }

        let unclamped = startLevel - translation.height / Swift.max(travel, 1)
        return (unclamped - Self.clamp(unclamped)) * Swift.max(travel, 1)
    }

    /// scrolled moves the level for one scroll event. A wheel steps by a sixteenth in the sign of
    /// `deltaY`, so every notch is the same; a trackpad is continuous and follows the finger.
    /// `deltaY` is the physical delta (`ScrollWheelReader.physicalDeltaY`): positive when the
    /// fingers move up or the wheel rolls away, whatever the scrolling-direction setting, and
    /// positive raises the level in both.
    public static func scrolled(
        _ level  : Double,
        deltaY   : Double,
        isPrecise: Bool
    ) -> Double {
        let change = isPrecise
            ? deltaY / preciseDivisor
            : (deltaY > 0 ? wheelStep : (deltaY < 0 ? -wheelStep : 0))
        return clamp(level + change)
    }

    /// ScrollStep is one scroll event's answer: the new level and how far, in points, the scroll
    /// has pushed past an end (positive past the top), which stretches the pill.
    public struct ScrollStep: Equatable, Sendable {

        public let level    : Double
        public let overshoot: Double
    }

    /// wheelKick is how far one wheel notch against an end pushes the pill: a wheel has no finger
    /// to follow, so it gets a fixed nudge that springs straight back.
    public static let wheelKick = 14.0

    /// scrolledPastEnds is `scrolled` with the rubber band. A trackpad pushing past an end piles
    /// its points into the overshoot instead of the level; scrolling back first undoes the
    /// overshoot, and only what is left moves the level. A wheel notch against an end answers
    /// `wheelKick`, which the view springs back at once.
    public static func scrolledPastEnds(
        _ level  : Double,
        overshoot: Double,
        deltaY   : Double,
        isPrecise: Bool
    ) -> ScrollStep {
        guard isPrecise else {
            let step      = deltaY > 0 ? wheelStep : (deltaY < 0 ? -wheelStep : 0)
            let unclamped = level + step
            let excess    = unclamped - clamp(unclamped)
            return ScrollStep(
                level    : clamp(unclamped),
                overshoot: excess > 0 ? wheelKick : (excess < 0 ? -wheelKick : 0)
            )
        }

        var points = deltaY
        if overshoot != 0 {
            let next = overshoot + points
            if next == 0 || (next > 0) == (overshoot > 0) {
                return ScrollStep(level: level, overshoot: next)
            }
            points = next
        }

        let unclamped = level + points / preciseDivisor
        return ScrollStep(
            level    : clamp(unclamped),
            overshoot: (unclamped - clamp(unclamped)) * preciseDivisor
        )
    }

    private func level(at translation: CGSize) -> Double {
        Self.clamp(startLevel - translation.height / Swift.max(travel, 1))
    }

    private static func distance(of translation: CGSize) -> Double {
        (translation.width * translation.width + translation.height * translation.height).squareRoot()
    }

    private static func clamp(_ level: Double) -> Double {
        Swift.min(Swift.max(level, 0), 1)
    }
}
