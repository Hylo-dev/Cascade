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
    let animation  : Animation?
    let released   : (Animation?) -> Void
    let cancelled  : () -> Void

    /// changed follows a drag that has moved `translation` points: the ticks move, nothing is sent.
    func changed(translation: Double) {
        var next = interaction.wrappedValue

        if let shown = next.change(translation: translation, current: value.wrappedValue) {
            value.wrappedValue = shown
        }
        interaction.wrappedValue = next
    }

    /// ended settles a drag on its nearest step and sends the one action; a tap sends nothing.
    func ended() {
        var next = interaction.wrappedValue
        let target = next.end(current: value.wrappedValue)
        interaction.wrappedValue = next

        if let target {
            settle(on: target)
        }
    }

    /// adjust is an accessibility step, `+1` or `-1`: one action per step, none at the range's end.
    func adjust(_ direction: Int) {
        if let target = interaction.wrappedValue.adjust(direction, current: value.wrappedValue) {
            settle(on: target)
        }
    }

    /// disappeared ends a drag whose control left the screen, so it cannot stay held.
    func disappeared() {
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
