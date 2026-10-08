//
//  RulerGestureDriver.swift
//  CascadeKit
//

import SwiftUI

/// RulerGestureDriver is the glue between a ruler's gestures and its control: it asks
/// `RulerInteraction` what a gesture means and applies the answer to the value and to the
/// release. The view holds no logic of its own beyond handing it the drag, the end of the drag
/// and the accessibility steps, so what the user's hand does can be tested by calling these
/// methods, through a real `PluginNodeStore`, without a window.
///
/// It is a value built at every body from the view's bindings: it owns nothing, and the
/// interaction's state lives in the view's `@State`. `released` lets go of the control with the
/// animation the value settled in, nil under Reduce Motion, and sends the one action;
/// `cancelled` lets go without sending.
struct RulerGestureDriver {

    let interaction: Binding<RulerInteraction>
    let value      : Binding<Double>
    let scale      : RulerScale
    let animation  : Animation?
    let released   : (Animation?) -> Void
    let cancelled  : () -> Void

    /// deferCheck runs a block one main turn later, by default; a test runs it when it chooses.
    var deferCheck : (@escaping () -> Void) -> Void = { block in
        DispatchQueue.main.async(execute: block)
    }

    /// changed follows a drag that has moved `translation` points: the ticks move, nothing is sent.
    func changed(translation: Double) {
        let before = interaction.wrappedValue
        var next   = before

        if let shown = next.change(translation: translation, current: value.wrappedValue, scale: scale) {
            value.wrappedValue = shown
        }
        if next != before {
            interaction.wrappedValue = next
        }
    }

    /// ended settles a drag on its nearest step and sends the one action; a tap sends nothing.
    func ended() {
        var next = interaction.wrappedValue
        let target = next.end(current: value.wrappedValue, scale: scale)
        interaction.wrappedValue = next

        if let target {
            settle(on: target)
        }
    }

    /// adjust is an accessibility step, `+1` or `-1`: one action per step, none at the range's end.
    func adjust(_ direction: Int) {
        if let target = interaction.wrappedValue.adjust(direction, current: value.wrappedValue, scale: scale) {
            settle(on: target)
        }
    }

    /// gestureStateReset is told that the drag's `GestureState` went back to false. That happens
    /// on a normal end and on a cancel by the system, and SwiftUI does not say in which order it
    /// runs this and `onEnded`. So it decides nothing at once: it notes which drag it saw and
    /// looks again one main turn later. By then a real end has finished the drag and the check
    /// finds nothing to do; a cancel, which has no end, is let go of without sending; and a
    /// drag that began in between is another generation and is left alone.
    func gestureStateReset() {
        let seen = interaction.wrappedValue

        guard seen.isDragging else { return }

        deferCheck {
            let now = interaction.wrappedValue

            if now.isDragging, now.generation == seen.generation {
                interrupted()
            }
        }
    }

    /// interrupted ends a drag that will never end by itself: its control left the screen, or
    /// the system cancelled the gesture (a `@GestureState` that reset with no `onEnded`). It
    /// lets go without sending, so the control does not stay held.
    func interrupted() {
        var next = interaction.wrappedValue

        if next.cancel() {
            cancelled()
        }
        interaction.wrappedValue = next
    }

    /// settle moves the value to `target`, a step, and lets go of the control. The animation is
    /// chosen once by the view and handed to the store, so the value is not animated a second
    /// time on its way out.
    private func settle(on target: Double) {
        withAnimation(animation) {
            value.wrappedValue = target
        }
        released(animation)
    }
}
