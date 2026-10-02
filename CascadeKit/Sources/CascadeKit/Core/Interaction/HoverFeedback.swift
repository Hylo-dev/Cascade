//
//  HoverFeedback.swift
//  CascadeKit
//

/// HoverFeedback emits at entry, synchronously before the opening animation.
/// Tracking entry even when disabled prevents a delayed impulse if preferences
/// change while the pointer is already inside the notch. It also plays the snap
/// that widget editing asks for, under the same preference.
@MainActor
final class HoverFeedback {

    var isEnabled = true

    private var isHovering = false

    private let performer: any HapticFeedbackPerforming

    init(performer: any HapticFeedbackPerforming) {
        self.performer = performer
    }

    func update(isHovering: Bool) {
        let entered     = isHovering && !self.isHovering
        self.isHovering = isHovering

        if entered && isEnabled { performer.performHoverFeedback() }
    }

    /// snap ticks the trackpad once, while haptics are on.
    func snap() {
        if isEnabled { performer.performSnapFeedback() }
    }
}
